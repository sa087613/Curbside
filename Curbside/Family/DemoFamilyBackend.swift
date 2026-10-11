import CurbsideCore
import Foundation

/// An in-memory family for trying Curbside's family features on one phone. Nothing leaves the device.
/// Other members' names, scores, and drives are made up.
@MainActor
final class DemoFamilyBackend: FamilyBackend {
    let isDemo = true
    let currentUserID: String? = "me"

    private var profile: AccountProfile?
    private let family = FamilyInfo(id: "demo-family", name: "Demo Family", createdBy: "jordan")
    private var memberList: [MemberRecord]
    private var sharedDrives: [String: [SharedDrive]]
    private var continuations: [UUID: AsyncThrowingStream<[MemberRecord], Error>.Continuation] = [:]
    private var rewardList: [ParentReward] = []
    private var rewardContinuations: [UUID: (teenID: String?, continuation: AsyncThrowingStream<[ParentReward], Error>.Continuation)] = [:]

    /// - Parameters:
    ///   - role: the role you preview as.
    ///   - center: where to draw the made-up drives (your latest drive's area if known).
    init(role: FamilyRole, displayName: String, center: SharedPoint?) {
        let now = Date()
        let c = center ?? SharedPoint(lat: 33.7756, lon: -84.3963)
        func standing(_ score: Int, _ trend: Int, drives: Int, miles: Double, avg: Int, brakes: Int, starts: Int, turns: Int) -> SharedStanding {
            SharedStanding(score: score, trendDelta: trend,
                           weekly: WeeklySummary(drives: drives, miles: miles, averageScore: avg,
                                                 hardBrakes: brakes, fastStarts: starts, sharpTurns: turns),
                           updatedAt: now)
        }
        profile = AccountProfile(displayName: displayName, familyID: family.id)
        memberList = [
            MemberRecord(id: "me", displayName: displayName, role: role, sharing: false,
                         consentDecided: role == .parent, standing: nil),
            MemberRecord(id: "jordan", displayName: "Jordan", role: .parent, sharing: true, consentDecided: true,
                         standing: standing(742, 4, drives: 9, miles: 61, avg: 93, brakes: 2, starts: 1, turns: 0)),
            MemberRecord(id: "riley", displayName: "Riley", role: .teen, sharing: true, consentDecided: true,
                         standing: standing(781, 12, drives: 11, miles: 48, avg: 95, brakes: 1, starts: 1, turns: 1)),
            MemberRecord(id: "sam", displayName: "Sam", role: .teen, sharing: false, consentDecided: false, standing: nil),
        ]
        if role == .teen {
            // A second parent so the teen preview has someone to share with besides Jordan.
            memberList.append(MemberRecord(id: "casey", displayName: "Casey", role: .parent, sharing: true, consentDecided: true,
                                           standing: standing(705, -6, drives: 6, miles: 70, avg: 88, brakes: 3, starts: 2, turns: 1)))
        }
        sharedDrives = ["riley": Self.makeDrives(center: c, now: now)]

        let day: TimeInterval = 86_400
        if role == .parent {
            rewardList = [
                ParentReward(id: "demo-r1", teenID: "riley", teenName: "Riley", createdBy: "me", createdByName: displayName,
                             createdAt: now.addingTimeInterval(-12 * day), goal: .hold(750, weeks: 4), prize: .money(20),
                             progress: RewardProgress(currentScore: 781, streakStart: now.addingTimeInterval(-9 * day), earnedAt: nil, updatedAt: now)),
                ParentReward(id: "demo-r2", teenID: "riley", teenName: "Riley", createdBy: "jordan", createdByName: "Jordan",
                             createdAt: now.addingTimeInterval(-30 * day), goal: .reach(740), prize: .privilege("Later curfew on Friday"),
                             progress: RewardProgress(currentScore: 781, streakStart: nil, earnedAt: now.addingTimeInterval(-4 * day), updatedAt: now)),
                ParentReward(id: "demo-r3", teenID: "sam", teenName: "Sam", createdBy: "me", createdByName: displayName,
                             createdAt: now.addingTimeInterval(-2 * day), goal: .reach(700), prize: .custom("Pick the weekend movie")),
            ]
        } else {
            rewardList = [
                ParentReward(id: "demo-t1", teenID: "me", teenName: displayName, createdBy: "jordan", createdByName: "Jordan",
                             createdAt: now.addingTimeInterval(-3 * day), goal: .hold(750, weeks: 2), prize: .money(25)),
                ParentReward(id: "demo-t2", teenID: "me", teenName: displayName, createdBy: "casey", createdByName: "Casey",
                             createdAt: now.addingTimeInterval(-3 * day), goal: .reach(700), prize: .privilege("Car for the weekend")),
            ]
        }
    }

    // MARK: Made-up drives

    private static func makeDrives(center: SharedPoint, now: Date) -> [SharedDrive] {
        let plans: [(hoursAgo: Double, minutes: Double, miles: Double, score: Int, events: [(DrivingEventKind, EventSeverity, Double)])] = [
            (5, 14, 4.2, 92, [(.hardBrake, .moderate, 0.55)]),
            (27, 22, 7.8, 100, []),
            (30, 18, 6.1, 88, [(.sharpTurn, .moderate, 0.3), (.harshAcceleration, .moderate, 0.8)]),
            (52, 11, 3.3, 100, []),
            (76, 25, 9.4, 96, [(.hardBrake, .moderate, 0.7)]),
            (100, 16, 5.0, 100, []),
        ]
        return plans.enumerated().map { i, plan in
            // A wobbly loop around the center, different for each drive.
            let radius = 0.004 + Double(i) * 0.0012
            let route = (0...120).map { k -> SharedPoint in
                let a = Double(k) / 120 * 2 * .pi
                let wobble = 1 + 0.15 * sin(a * Double(3 + i))
                return SharedPoint(lat: center.lat + radius * wobble * sin(a + Double(i)),
                                   lon: center.lon + radius * 1.2 * wobble * cos(a + Double(i)))
            }
            let duration = plan.minutes * 60
            let events = plan.events.map { kind, severity, fraction -> SharedEvent in
                let p = route[Int(fraction * Double(route.count - 1))]
                return SharedEvent(kind: kind, severity: severity, offsetSeconds: (duration * fraction).rounded(), lat: p.lat, lon: p.lon)
            }
            return SharedDrive(id: "demo-\(i)", startDate: now.addingTimeInterval(-plan.hoursAgo * 3600),
                               durationSeconds: duration, miles: plan.miles, score: plan.score, events: events, route: route)
        }
    }

    private func broadcast() {
        continuations.values.forEach { $0.yield(memberList) }
    }

    private func updateMe(_ change: (inout MemberRecord) -> Void) {
        guard let i = memberList.firstIndex(where: { $0.id == "me" }) else { return }
        change(&memberList[i])
        broadcast()
    }

    // MARK: FamilyBackend

    func signIn(with credential: AppleCredential) async throws {}
    func signOut() throws {}
    func deleteAccount(confirmingWith credential: AppleCredential, familyID: String?) async throws {}

    func loadProfile() async throws -> AccountProfile? { profile }
    func saveProfile(_ profile: AccountProfile) async throws { self.profile = profile }

    func createFamily(name: String, displayName: String) async throws -> FamilyInfo { family }
    func loadFamily(id: String) async throws -> FamilyInfo { family }

    func createInvite(for family: FamilyInfo, role: FamilyRole) async throws -> InviteInfo {
        InviteInfo(code: InviteCode.generate(), familyID: family.id, familyName: family.name, role: role,
                   expiresAt: Date().addingTimeInterval(Double(FamilyConfig.default.inviteValidDays) * 86_400))
    }

    func lookupInvite(code: String) async throws -> InviteInfo { throw FamilyError.invalidCode }
    func join(_ invite: InviteInfo, displayName: String) async throws {}

    func members(familyID: String) -> AsyncThrowingStream<[MemberRecord], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(memberList)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    func setSharing(_ on: Bool, familyID: String) async throws {
        if !on { sharedDrives["me"] = nil }
        updateMe {
            $0.sharing = on
            $0.consentDecided = true
            if !on { $0.standing = nil }
        }
    }

    func publish(_ standing: SharedStanding?, familyID: String) async throws {
        updateMe { $0.standing = $0.sharing ? standing : nil }
    }

    func upload(_ drive: SharedDrive, familyID: String) async throws {
        sharedDrives["me", default: []].insert(drive, at: 0)
    }

    func drives(of memberID: String, familyID: String, limit: Int) async throws -> [SharedDrive] {
        let sharing = memberList.first { $0.id == memberID }?.sharing ?? false
        return sharing ? Array((sharedDrives[memberID] ?? []).prefix(limit)) : []
    }

    func removeMember(_ memberID: String, familyID: String) async throws {
        memberList.removeAll { $0.id == memberID }
        sharedDrives[memberID] = nil
        broadcast()
    }

    func leaveFamily(familyID: String) async throws {}

    // MARK: Rewards

    private func broadcastRewards() {
        for (teenID, continuation) in rewardContinuations.values {
            continuation.yield(rewardList.filter { teenID == nil || $0.teenID == teenID })
        }
    }

    func rewards(familyID: String, teenID: String?) -> AsyncThrowingStream<[ParentReward], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            rewardContinuations[id] = (teenID, continuation)
            continuation.yield(rewardList.filter { teenID == nil || $0.teenID == teenID })
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.rewardContinuations[id] = nil }
            }
        }
    }

    func createReward(_ reward: ParentReward, familyID: String) async throws {
        rewardList.insert(reward, at: 0)
        broadcastRewards()
    }

    func updateReward(_ reward: ParentReward, familyID: String) async throws {
        guard let i = rewardList.firstIndex(where: { $0.id == reward.id }) else { return }
        rewardList[i].goal = reward.goal
        rewardList[i].prize = reward.prize
        rewardList[i].givenAt = reward.givenAt
        broadcastRewards()
    }

    func deleteReward(id: String, familyID: String) async throws {
        rewardList.removeAll { $0.id == id }
        broadcastRewards()
    }

    func publishProgress(_ progress: RewardProgress?, rewardID: String, familyID: String) async throws {
        guard let i = rewardList.firstIndex(where: { $0.id == rewardID }) else { return }
        rewardList[i].progress = progress
        broadcastRewards()
    }
}
