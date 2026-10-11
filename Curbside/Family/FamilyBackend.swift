import CurbsideCore
import Foundation

struct AccountProfile: Codable, Equatable, Sendable {
    var displayName: String
    var familyID: String?
}

struct FamilyInfo: Equatable, Sendable {
    var id: String
    var name: String
    var createdBy: String
}

struct InviteInfo: Equatable, Sendable {
    var code: String
    var familyID: String
    var familyName: String
    var role: FamilyRole
    var expiresAt: Date
}

struct MemberRecord: Equatable, Sendable, Identifiable {
    var id: String
    var displayName: String
    var role: FamilyRole
    /// Sharing is on (consented and not paused).
    var sharing: Bool
    /// They've seen the consent screen and chosen (either way).
    var consentDecided: Bool
    /// Published Curbside Score standing; nil if not sharing or no scored drives yet.
    var standing: SharedStanding?
}

/// Result of Sign in with Apple, passed to the backend.
struct AppleCredential: Sendable {
    var idToken: String
    var rawNonce: String
    var authorizationCode: String?
    var fullName: PersonNameComponents?
}

enum FamilyError: LocalizedError {
    case notSignedIn
    case invalidCode
    case expiredCode
    case alreadyInFamily
    case needsRecentSignIn
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're signed out. Sign in again to continue."
        case .invalidCode: "That code doesn't match a family. Check it with whoever sent it."
        case .expiredCode: "That code has expired. Ask for a new one."
        case .alreadyInFamily: "You're already in a family. Leave it first to join another."
        case .needsRecentSignIn: "For your security, confirm with Apple again to do that."
        case .unavailable: "Family features aren't set up in this build."
        }
    }
}

/// Everything the app needs from a family backend. Firebase in production; an in-memory
/// demo family for previews, screenshots, and trying the parent view on one phone.
@MainActor
protocol FamilyBackend: AnyObject {
    var isDemo: Bool { get }
    var currentUserID: String? { get }

    func signIn(with credential: AppleCredential) async throws
    func signOut() throws
    /// Re-confirms with Apple, revokes the Apple token, deletes all of the user's data and the account.
    func deleteAccount(confirmingWith credential: AppleCredential, familyID: String?) async throws

    func loadProfile() async throws -> AccountProfile?
    func saveProfile(_ profile: AccountProfile) async throws

    func createFamily(name: String, displayName: String) async throws -> FamilyInfo
    func loadFamily(id: String) async throws -> FamilyInfo
    func createInvite(for family: FamilyInfo, role: FamilyRole) async throws -> InviteInfo
    func lookupInvite(code: String) async throws -> InviteInfo
    func join(_ invite: InviteInfo, displayName: String) async throws

    /// Live member list. Ends (or errors) when the user loses access.
    func members(familyID: String) -> AsyncThrowingStream<[MemberRecord], Error>

    /// Records the consent choice. Turning sharing off also clears the published score and deletes shared drives.
    func setSharing(_ on: Bool, familyID: String) async throws
    func publish(_ standing: SharedStanding?, familyID: String) async throws
    func upload(_ drive: SharedDrive, familyID: String) async throws
    func drives(of memberID: String, familyID: String, limit: Int) async throws -> [SharedDrive]

    /// A parent removes someone (and their shared drives).
    func removeMember(_ memberID: String, familyID: String) async throws
    /// Leave the family, deleting everything you shared with it.
    func leaveFamily(familyID: String) async throws
}
