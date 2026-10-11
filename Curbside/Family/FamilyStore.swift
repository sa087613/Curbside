import CurbsideCore
import Foundation
import Observation
import SwiftData

/// App-wide family state: where the user is in setup, their family, its members, and syncing.
@MainActor
@Observable
final class FamilyStore {
    enum Phase: Equatable {
        case loading
        case signedOut
        case needsName
        case needsFamily
        case needsConsent
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var profile: AccountProfile?
    private(set) var family: FamilyInfo?
    private(set) var members: [MemberRecord] = []
    private(set) var invites: [FamilyRole: InviteInfo] = [:]
    /// Name from Sign in with Apple, to prefill the name step.
    private(set) var suggestedName = ""
    var isWorking = false

    @ObservationIgnored private var backend: FamilyBackend
    @ObservationIgnored private let firebase: FamilyBackend?
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let prompts: PromptGate
    @ObservationIgnored private var membersTask: Task<Void, Never>?

    init(container: ModelContainer, prompts: PromptGate) {
        self.container = container
        self.prompts = prompts
        FirebaseFamilyBackend.configureIfPossible()
        firebase = FirebaseFamilyBackend.isConfigured ? FirebaseFamilyBackend() : nil
        backend = firebase ?? DemoFamilyBackend(role: .parent, displayName: "You", center: nil)
        if firebase == nil { phase = .signedOut }
    }

    // MARK: Derived state

    var isDemo: Bool { backend.isDemo }
    var isFirebaseAvailable: Bool { firebase != nil }
    var me: MemberRecord? { members.first { $0.id == backend.currentUserID } }
    var myRole: FamilyRole? { me?.role }
    var isParent: Bool { myRole == .parent }
    var teens: [MemberRecord] { members.filter { $0.role == .teen } }

    var leaderboard: [LeaderboardEntry] {
        Leaderboard.rank(members.map {
            MemberStanding(id: $0.id, displayName: $0.displayName, role: $0.role, standing: $0.standing,
                           isMe: $0.id == backend.currentUserID)
        })
    }

    // MARK: Setup flow

    /// Works out which step the user is on. Call at launch and after any account change.
    func refresh() async {
        guard backend.currentUserID != nil else {
            stopListening()
            profile = nil
            family = nil
            phase = .signedOut
            return
        }
        do {
            profile = try await backend.loadProfile()
            guard let profile, !profile.displayName.isEmpty else {
                phase = .needsName
                return
            }
            guard let familyID = profile.familyID else {
                stopListening()
                family = nil
                phase = .needsFamily
                return
            }
            family = try await backend.loadFamily(id: familyID)
            listen(familyID: familyID)
        } catch {
            // Lost access to the family (removed by a parent, or it was deleted).
            if profile?.familyID != nil, var p = profile {
                p.familyID = nil
                try? await backend.saveProfile(p)
                profile = p
                stopListening()
                family = nil
                phase = .needsFamily
            } else {
                report(error)
            }
        }
    }

    func signIn(with credential: AppleCredential) async {
        await run {
            try await self.backend.signIn(with: credential)
            if let name = credential.fullName {
                self.suggestedName = PersonNameComponentsFormatter.localizedString(from: name, style: .short)
            }
            await self.refresh()
        }
    }

    func setName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await run {
            var p = self.profile ?? AccountProfile(displayName: trimmed, familyID: nil)
            p.displayName = trimmed
            try await self.backend.saveProfile(p)
            await self.refresh()
        }
    }

    func createFamily(named name: String) async {
        guard let profile else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await run {
            let family = try await self.backend.createFamily(name: trimmed.isEmpty ? "\(profile.displayName)'s family" : trimmed,
                                                             displayName: profile.displayName)
            try await self.backend.saveProfile(AccountProfile(displayName: profile.displayName, familyID: family.id))
            await self.refresh()
        }
    }

    func lookupInvite(_ input: String) async -> InviteInfo? {
        guard let code = InviteCode.normalize(input) else {
            report(FamilyError.invalidCode)
            return nil
        }
        var found: InviteInfo?
        await run { found = try await self.backend.lookupInvite(code: code) }
        return found
    }

    func join(_ invite: InviteInfo) async {
        guard let profile else { return }
        await run {
            try await self.backend.join(invite, displayName: profile.displayName)
            try await self.backend.saveProfile(AccountProfile(displayName: profile.displayName, familyID: invite.familyID))
            await self.refresh()
        }
    }

    // MARK: Members

    private func listen(familyID: String) {
        stopListening()
        membersTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await list in self.backend.members(familyID: familyID) {
                    self.apply(list)
                }
            } catch {
                await self.refresh()
            }
        }
    }

    private func stopListening() {
        membersTask?.cancel()
        membersTask = nil
        members = []
    }

    private func apply(_ list: [MemberRecord]) {
        members = list
        guard let me else {
            // We're no longer in the member list: removed by a parent.
            if !list.isEmpty { Task { await refresh() } }
            return
        }
        phase = me.consentDecided ? .ready : .needsConsent
    }

    // MARK: Consent & sharing

    /// Records the consent choice. Turning on publishes the current score right away.
    func setSharing(_ on: Bool) async {
        guard let family else { return }
        await run {
            try await self.backend.setSharing(on, familyID: family.id)
            if on { try await self.backend.publish(self.currentStanding(), familyID: family.id) }
        }
    }

    /// Called after every saved drive. Silent: never prompts (the driver may still be in the car).
    func driveSaved(_ drive: Drive) async {
        guard phase == .ready, let family, me?.sharing == true else { return }
        do {
            try await backend.upload(sharedDrive(for: drive), familyID: family.id)
            try await backend.publish(currentStanding(), familyID: family.id)
        } catch {
            // Firestore queues writes offline; anything else is retried with the next drive.
        }
    }

    /// Keeps the weekly summary current when the app opens.
    func republishStanding() async {
        guard phase == .ready, let family, me?.sharing == true else { return }
        try? await backend.publish(currentStanding(), familyID: family.id)
    }

    // MARK: Parent tools

    func invite(role: FamilyRole) async -> InviteInfo? {
        if let existing = invites[role], existing.expiresAt > Date().addingTimeInterval(3600) { return existing }
        guard let family else { return nil }
        var made: InviteInfo?
        await run { made = try await self.backend.createInvite(for: family, role: role) }
        if let made { invites[role] = made }
        return made
    }

    func drives(of member: MemberRecord) async -> [SharedDrive] {
        guard let family else { return [] }
        return (try? await backend.drives(of: member.id, familyID: family.id, limit: FamilyConfig.default.recentDrivesShown)) ?? []
    }

    func remove(_ member: MemberRecord) async {
        guard let family else { return }
        await run { try await self.backend.removeMember(member.id, familyID: family.id) }
    }

    // MARK: Leaving, signing out, deleting

    func leaveFamily() async {
        guard let family else { return }
        await run {
            try await self.backend.leaveFamily(familyID: family.id)
            self.stopListening()
            self.family = nil
            await self.refresh()
        }
    }

    func signOut() {
        if isDemo {
            exitDemo()
            return
        }
        do {
            try backend.signOut()
        } catch {
            report(error)
        }
        stopListening()
        invites = [:]
        Task { await refresh() }
    }

    func deleteAccount(confirmingWith credential: AppleCredential) async {
        await run {
            try await self.backend.deleteAccount(confirmingWith: credential, familyID: self.family?.id)
            self.stopListening()
            self.invites = [:]
            self.family = nil
            await self.refresh()
        }
    }

    // MARK: Demo

    func startDemo(as role: FamilyRole) {
        stopListening()
        let center = latestRouteCenter()
        let name = profile?.displayName.isEmpty == false ? profile!.displayName : "Alex"
        backend = DemoFamilyBackend(role: role, displayName: name, center: center)
        invites = [:]
        Task {
            profile = try? await backend.loadProfile()
            family = try? await backend.loadFamily(id: "demo-family")
            listen(familyID: "demo-family")
        }
    }

    func exitDemo() {
        stopListening()
        invites = [:]
        family = nil
        profile = nil
        if let firebase {
            backend = firebase
            Task { await refresh() }
        } else {
            phase = .signedOut
        }
    }

    // MARK: What gets shared (also used for the consent preview)

    func currentStanding(now: Date = .now) -> SharedStanding? {
        let drives = allDrives()
        let report = CurbsideScoreReport.from(drives, now: now)
        guard report.scoredDriveCount > 0 else { return nil }
        let recent = drives.filter { $0.startDate > now.addingTimeInterval(-8 * 86_400) }.map { sharedDrive(for: $0, includeRoute: false) }
        return SharedStanding(report: report, weekly: WeeklySummary.compute(drives: recent, now: now), now: now)
    }

    func sharedDrive(for drive: Drive, includeRoute: Bool = true) -> SharedDrive {
        SharedDrive.make(id: drive.id, startDate: drive.startDate, durationSeconds: drive.duration,
                         distanceMeters: drive.distanceMeters, score: drive.score, events: drive.events,
                         route: includeRoute ? drive.route : [])
    }

    /// The user's latest drive as a parent would see it, for the consent preview.
    func latestSharedDrive() -> SharedDrive? {
        allDrives().max { $0.startDate < $1.startDate }.map { sharedDrive(for: $0) }
    }

    private func allDrives() -> [Drive] {
        (try? container.mainContext.fetch(FetchDescriptor<Drive>())) ?? []
    }

    private func latestRouteCenter() -> SharedPoint? {
        guard let drive = allDrives().filter({ !$0.route.isEmpty }).max(by: { $0.startDate < $1.startDate }) else { return nil }
        let r = drive.route
        return SharedPoint(lat: r.map(\.latitude).reduce(0, +) / Double(r.count),
                           lon: r.map(\.longitude).reduce(0, +) / Double(r.count))
    }

    // MARK: Helpers

    private func run(_ work: @escaping @MainActor () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        prompts.present(AppPrompt(title: "Something went wrong", message: error.localizedDescription))
    }
}
