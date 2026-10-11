import CurbsideCore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseCore
@preconcurrency import FirebaseFirestore
import Foundation

/// Firestore layout and access rules: see firebase/firestore.rules.
@MainActor
final class FirebaseFamilyBackend: FamilyBackend {
    let isDemo = false
    private var db: Firestore { Firestore.firestore() }

    /// True when GoogleService-Info.plist is bundled and Firebase was configured at launch.
    static var isConfigured: Bool { FirebaseApp.app() != nil }

    static func configureIfPossible() {
        guard FirebaseApp.app() == nil,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
    }

    var currentUserID: String? { Auth.auth().currentUser?.uid }

    private func uid() throws -> String {
        guard let id = currentUserID else { throw FamilyError.notSignedIn }
        return id
    }

    // MARK: Paths

    private func userRef(_ uid: String) -> DocumentReference { db.collection("users").document(uid) }
    private func familyRef(_ fid: String) -> DocumentReference { db.collection("families").document(fid) }
    private func memberRef(_ fid: String, _ uid: String) -> DocumentReference {
        familyRef(fid).collection("members").document(uid)
    }
    private func drivesRef(_ fid: String, _ uid: String) -> CollectionReference {
        memberRef(fid, uid).collection("drives")
    }
    private func rewardsRef(_ fid: String) -> CollectionReference { familyRef(fid).collection("rewards") }

    /// Firestore shape of a member document.
    private struct MemberDoc: Codable {
        var displayName: String
        var role: FamilyRole
        var sharing: Bool
        var consentDecided: Bool
        var inviteCode: String?
        var joinedAt: Date
        var standing: SharedStanding?
    }

    // MARK: Auth

    func signIn(with credential: AppleCredential) async throws {
        let firebaseCredential = OAuthProvider.appleCredential(withIDToken: credential.idToken,
                                                               rawNonce: credential.rawNonce,
                                                               fullName: credential.fullName)
        _ = try await Auth.auth().signIn(with: firebaseCredential)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func deleteAccount(confirmingWith credential: AppleCredential, familyID: String?) async throws {
        guard let user = Auth.auth().currentUser else { throw FamilyError.notSignedIn }
        let firebaseCredential = OAuthProvider.appleCredential(withIDToken: credential.idToken,
                                                               rawNonce: credential.rawNonce,
                                                               fullName: nil)
        _ = try await user.reauthenticate(with: firebaseCredential)

        // Data first (needs the account), then the Apple token (App Store requirement), then the account.
        if let familyID { try await leaveFamily(familyID: familyID) }
        let invites = try await db.collection("inviteCodes").whereField("createdBy", isEqualTo: user.uid).getDocuments()
        for doc in invites.documents { try await doc.reference.delete() }
        try await userRef(user.uid).delete()
        if let code = credential.authorizationCode {
            try await Auth.auth().revokeToken(withAuthorizationCode: code)
        }
        try await user.delete()
    }

    // MARK: Profile

    func loadProfile() async throws -> AccountProfile? {
        let snapshot = try await userRef(try uid()).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: AccountProfile.self)
    }

    func saveProfile(_ profile: AccountProfile) async throws {
        try userRef(try uid()).setData(from: profile)
    }

    // MARK: Families & invites

    func createFamily(name: String, displayName: String) async throws -> FamilyInfo {
        let me = try uid()
        let ref = db.collection("families").document()
        try await ref.setData(["name": name, "createdBy": me, "createdAt": FieldValue.serverTimestamp()])
        let member = MemberDoc(displayName: displayName, role: .parent, sharing: false, consentDecided: false,
                               inviteCode: nil, joinedAt: Date(), standing: nil)
        try memberRef(ref.documentID, me).setData(from: member)
        return FamilyInfo(id: ref.documentID, name: name, createdBy: me)
    }

    func loadFamily(id: String) async throws -> FamilyInfo {
        let snapshot = try await familyRef(id).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { throw FamilyError.invalidCode }
        return FamilyInfo(id: id, name: data["name"] as? String ?? "Family", createdBy: data["createdBy"] as? String ?? "")
    }

    func createInvite(for family: FamilyInfo, role: FamilyRole) async throws -> InviteInfo {
        let me = try uid()
        let expires = Date().addingTimeInterval(Double(FamilyConfig.default.inviteValidDays) * 86_400)
        // Retry on the (astronomically unlikely) collision with an existing code.
        for _ in 0..<5 {
            let code = InviteCode.generate()
            let ref = db.collection("inviteCodes").document(code)
            if try await ref.getDocument().exists { continue }
            try await ref.setData([
                "familyID": family.id, "familyName": family.name, "role": role.rawValue,
                "createdBy": me, "expiresAt": Timestamp(date: expires),
            ])
            return InviteInfo(code: code, familyID: family.id, familyName: family.name, role: role, expiresAt: expires)
        }
        throw FamilyError.invalidCode
    }

    func lookupInvite(code: String) async throws -> InviteInfo {
        let snapshot = try await db.collection("inviteCodes").document(code).getDocument()
        guard snapshot.exists, let data = snapshot.data(),
              let familyID = data["familyID"] as? String,
              let role = (data["role"] as? String).flatMap(FamilyRole.init(rawValue:)),
              let expires = (data["expiresAt"] as? Timestamp)?.dateValue() else { throw FamilyError.invalidCode }
        guard expires > Date() else { throw FamilyError.expiredCode }
        return InviteInfo(code: code, familyID: familyID, familyName: data["familyName"] as? String ?? "your family",
                          role: role, expiresAt: expires)
    }

    func join(_ invite: InviteInfo, displayName: String) async throws {
        let member = MemberDoc(displayName: displayName, role: invite.role, sharing: false, consentDecided: false,
                               inviteCode: invite.code, joinedAt: Date(), standing: nil)
        try memberRef(invite.familyID, try uid()).setData(from: member)
    }

    // MARK: Members

    func members(familyID: String) -> AsyncThrowingStream<[MemberRecord], Error> {
        let query = familyRef(familyID).collection("members")
        return AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                let records = (snapshot?.documents ?? []).compactMap { doc -> MemberRecord? in
                    guard let m = try? doc.data(as: MemberDoc.self) else { return nil }
                    return MemberRecord(id: doc.documentID, displayName: m.displayName, role: m.role, sharing: m.sharing,
                                        consentDecided: m.consentDecided, standing: m.sharing ? m.standing : nil)
                }
                continuation.yield(records)
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    // MARK: Sharing

    func setSharing(_ on: Bool, familyID: String) async throws {
        let me = try uid()
        if on {
            try await memberRef(familyID, me).updateData(["sharing": true, "consentDecided": true])
        } else {
            // Clear the score in the same write (the rules require it), then delete shared drives.
            try await memberRef(familyID, me).updateData([
                "sharing": false, "consentDecided": true, "standing": FieldValue.delete(),
            ])
            try await deleteAllDrives(familyID: familyID, memberID: me)
        }
    }

    func publish(_ standing: SharedStanding?, familyID: String) async throws {
        let me = try uid()
        if let standing {
            try await memberRef(familyID, me).updateData(["standing": try Firestore.Encoder().encode(standing)])
        } else {
            try await memberRef(familyID, me).updateData(["standing": FieldValue.delete()])
        }
    }

    func upload(_ drive: SharedDrive, familyID: String) async throws {
        try drivesRef(familyID, try uid()).document(drive.id).setData(from: drive)
    }

    func drives(of memberID: String, familyID: String, limit: Int) async throws -> [SharedDrive] {
        let snapshot = try await drivesRef(familyID, memberID)
            .order(by: "startDate", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: SharedDrive.self) }
    }

    private func deleteAllDrives(familyID: String, memberID: String) async throws {
        let snapshot = try await drivesRef(familyID, memberID).getDocuments()
        for doc in snapshot.documents { try await doc.reference.delete() }
    }

    // MARK: Leaving

    func removeMember(_ memberID: String, familyID: String) async throws {
        try await deleteAllDrives(familyID: familyID, memberID: memberID)
        let theirRewards = try await rewardsRef(familyID).whereField("teenID", isEqualTo: memberID).getDocuments()
        for doc in theirRewards.documents { try await doc.reference.delete() }
        try await memberRef(familyID, memberID).delete()
    }

    // MARK: Rewards

    func rewards(familyID: String, teenID: String?) -> AsyncThrowingStream<[ParentReward], Error> {
        // Teens must query only their own (the rules reject anything broader).
        let query: Query = teenID.map { rewardsRef(familyID).whereField("teenID", isEqualTo: $0) } ?? rewardsRef(familyID)
        return AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                let rewards = (snapshot?.documents ?? []).compactMap { try? $0.data(as: ParentReward.self) }
                continuation.yield(rewards.sorted { $0.createdAt > $1.createdAt })
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func createReward(_ reward: ParentReward, familyID: String) async throws {
        var clean = reward
        clean.progress = nil
        clean.givenAt = nil
        try rewardsRef(familyID).document(reward.id).setData(from: clean)
    }

    func updateReward(_ reward: ParentReward, familyID: String) async throws {
        let encoder = Firestore.Encoder()
        try await rewardsRef(familyID).document(reward.id).updateData([
            "goal": try encoder.encode(reward.goal),
            "prize": try encoder.encode(reward.prize),
            "givenAt": reward.givenAt.map { Timestamp(date: $0) } ?? FieldValue.delete(),
        ])
    }

    func deleteReward(id: String, familyID: String) async throws {
        try await rewardsRef(familyID).document(id).delete()
    }

    func publishProgress(_ progress: RewardProgress?, rewardID: String, familyID: String) async throws {
        let value: Any = try progress.map { try Firestore.Encoder().encode($0) } ?? FieldValue.delete()
        try await rewardsRef(familyID).document(rewardID).updateData(["progress": value])
    }

    func leaveFamily(familyID: String) async throws {
        let me = try uid()
        try await deleteAllDrives(familyID: familyID, memberID: me)
        // The last member out also deletes the family (while still allowed to, as a member).
        let others = try await familyRef(familyID).collection("members").getDocuments().documents.filter { $0.documentID != me }
        if others.isEmpty { try await familyRef(familyID).delete() }
        try await memberRef(familyID, me).delete()
        if var profile = try await loadProfile() {
            profile.familyID = nil
            try await saveProfile(profile)
        }
    }
}
