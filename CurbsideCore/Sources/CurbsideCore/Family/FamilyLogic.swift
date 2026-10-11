import Foundation

// MARK: - Invite codes

public enum InviteCode {
    /// No 0/O, 1/I/L, or U/V look-alikes, so codes survive being read aloud or typed from a screenshot.
    public static let alphabet = Array("ABCDEFGHJKMNPQRSTWXYZ23456789")

    public static func generate<R: RandomNumberGenerator>(length: Int = FamilyConfig.default.inviteCodeLength,
                                                         using rng: inout R) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &rng)! })
    }

    public static func generate(length: Int = FamilyConfig.default.inviteCodeLength) -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(length: length, using: &rng)
    }

    /// Uppercases and strips spaces/dashes; returns nil if anything else is wrong.
    public static func normalize(_ input: String, length: Int = FamilyConfig.default.inviteCodeLength) -> String? {
        let cleaned = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, cleaned.allSatisfy(alphabet.contains) else { return nil }
        return cleaned
    }

    /// "ABCD-EFGH"
    public static func display(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let mid = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[..<mid])-\(code[mid...])"
    }
}

// MARK: - Leaderboard

/// One family member as the leaderboard sees them.
public struct MemberStanding: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var role: FamilyRole
    /// Nil when the member isn't sharing (or hasn't driven yet).
    public var standing: SharedStanding?
    public var isMe: Bool

    public init(id: String, displayName: String, role: FamilyRole, standing: SharedStanding?, isMe: Bool) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.standing = standing
        self.isMe = isMe
    }
}

public struct LeaderboardEntry: Sendable, Equatable, Identifiable {
    /// 1-based; ties share a rank (1, 1, 3). Nil for members without a shared score.
    public var rank: Int?
    public var member: MemberStanding
    public var id: String { member.id }
}

public enum Leaderboard {
    /// Highest Curbside Score first; members who aren't sharing go last, unranked.
    public static func rank(_ members: [MemberStanding]) -> [LeaderboardEntry] {
        let scored = members.filter { $0.standing != nil }.sorted {
            let a = $0.standing!.score, b = $1.standing!.score
            return a != b ? a > b : $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        var entries: [LeaderboardEntry] = []
        for (i, m) in scored.enumerated() {
            let rank = i > 0 && scored[i - 1].standing!.score == m.standing!.score ? entries[i - 1].rank : i + 1
            entries.append(LeaderboardEntry(rank: rank, member: m))
        }
        let unranked = members.filter { $0.standing == nil }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { LeaderboardEntry(rank: nil, member: $0) }
        return entries + unranked
    }
}

// MARK: - Consent disclosure

/// The single source of truth for what sharing means. The consent screen renders this, and a test
/// checks that every field uploaded in `SharedDrive` / `SharedStanding` is listed in `fields` here.
public struct SharingDisclosure: Sendable {
    public struct Item: Sendable, Identifiable {
        public var id: String { title }
        public var symbol: String
        public var title: String
        public var detail: String
        /// Coding keys of the shared types this item covers.
        public var fields: [String]
    }

    public var audience: String
    public var shared: [Item]
    public var neverShared: [Item]
    public var controls: [String]

    public static func forRole(_ role: FamilyRole) -> SharingDisclosure {
        let standing = Item(
            symbol: "gauge.with.needle",
            title: "Your Curbside Score",
            detail: "Your score, its tier, and whether it went up or down this week. Everyone in the family sees this on the leaderboard.",
            fields: ["score", "trendDelta", "updatedAt"])
        let weekly = Item(
            symbol: "calendar",
            title: "Your weekly summary",
            detail: "How many drives and miles this week, your average drive score, and how many hard brakes, fast starts, and sharp turns.",
            fields: ["weekly", "drives", "miles", "averageScore", "hardBrakes", "fastStarts", "sharpTurns"])
        let drives = Item(
            symbol: "map",
            title: "Each drive from now on",
            detail: "When it started, how long it was, its distance and score, and a map of the route with each hard brake, fast start, and sharp turn pinned (what type, how severe, where).",
            fields: ["id", "startDate", "durationSeconds", "miles", "score", "events", "route",
                     "kind", "severity", "offsetSeconds", "lat", "lon"])
        let rewardProgress = Item(
            symbol: "gift",
            title: "Progress on rewards your parents set",
            detail: "Your current score and how close you are to each goal, like \"day 9 of 28 at 80+\".",
            fields: ["progress", "currentScore", "streakStart", "earnedAt", "updatedAt"])
        let never: [Item] = [
            Item(symbol: "location.slash", title: "Where you are right now",
                 detail: "There's no live location. Parents only see a drive after it's finished.", fields: []),
            Item(symbol: "speedometer", title: "Your speed",
                 detail: "Speeds, top speed, and braking force stay on your phone.", fields: []),
            Item(symbol: "play.slash", title: "Event replays and raw sensor data",
                 detail: "The 5-second replays and the motion/GPS recordings never leave your phone.", fields: []),
            Item(symbol: "clock.arrow.circlepath", title: "Drives from before you agreed",
                 detail: "Only drives recorded after you turn on sharing are sent.", fields: []),
        ]
        switch role {
        case .teen:
            return SharingDisclosure(
                audience: "the parents in your family",
                shared: [standing, weekly, drives, rewardProgress],
                neverShared: never,
                controls: [
                    "You can turn sharing off at any time in Family › Settings. Parents will see \"Sharing paused\".",
                    "Turning it off also deletes the drives you've already shared.",
                    "Leaving the family deletes everything you shared with it.",
                ])
        case .parent:
            return SharingDisclosure(
                audience: "the other parents in your family (teens only see your score on the leaderboard)",
                shared: [standing, weekly, drives],
                neverShared: never,
                controls: [
                    "You can turn sharing off at any time in Family › Settings.",
                    "Turning it off also deletes the drives you've already shared.",
                ])
        }
    }

    /// Every field name covered by `shared`.
    public var disclosedFields: Set<String> { Set(shared.flatMap(\.fields)) }
}
