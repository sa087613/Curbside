import Foundation

/// What the teen has to do. Stored flat (not as an enum with payloads) so it maps cleanly to Firestore.
public struct RewardGoal: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Get the Curbside Score to `minScore` at least once.
        case reach
        /// Keep the Curbside Score at or above `minScore` for `weeks` weeks without dipping below.
        case hold
    }

    public var kind: Kind
    public var minScore: Int
    public var weeks: Int?

    public init(kind: Kind, minScore: Int, weeks: Int? = nil) {
        self.kind = kind
        self.minScore = minScore
        self.weeks = kind == .hold ? max(1, weeks ?? 1) : nil
    }

    public static func reach(_ score: Int) -> RewardGoal { RewardGoal(kind: .reach, minScore: score) }
    public static func hold(_ score: Int, weeks: Int) -> RewardGoal { RewardGoal(kind: .hold, minScore: score, weeks: weeks) }

    var holdDuration: TimeInterval { Double(weeks ?? 0) * 7 * 86_400 }

    /// "Hold 750+ for 4 weeks" / "Reach 750+"
    public var summary: String {
        switch kind {
        case .reach: "Reach \(minScore)+"
        case .hold: "Hold \(minScore)+ for \(weeks ?? 1) \(weeks == 1 ? "week" : "weeks")"
        }
    }
}

public struct RewardPrize: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case money
        case privilege
        case custom
    }

    public var kind: Kind
    public var dollars: Int?
    public var text: String?

    public init(kind: Kind, dollars: Int? = nil, text: String? = nil) {
        self.kind = kind
        self.dollars = kind == .money ? dollars : nil
        self.text = kind == .money ? nil : text
    }

    public static func money(_ dollars: Int) -> RewardPrize { RewardPrize(kind: .money, dollars: dollars) }
    public static func privilege(_ text: String) -> RewardPrize { RewardPrize(kind: .privilege, text: text) }
    public static func custom(_ text: String) -> RewardPrize { RewardPrize(kind: .custom, text: text) }

    /// "$20", "Later curfew"
    public var title: String {
        switch kind {
        case .money: "$\(dollars ?? 0)"
        case .privilege, .custom: (text?.isEmpty == false ? text! : "A surprise")
        }
    }
}

/// Progress, computed on the teen's phone (it has the score history) and published while sharing.
/// The score only changes when they drive, so a hold streak keeps running between drives.
public struct RewardProgress: Codable, Sendable, Equatable {
    public var currentScore: Int
    /// Hold goals: when the current run at or above the target began (nil when below it).
    public var streakStart: Date?
    /// Set once the goal is met; never cleared.
    public var earnedAt: Date?
    public var updatedAt: Date

    public init(currentScore: Int, streakStart: Date?, earnedAt: Date?, updatedAt: Date) {
        self.currentScore = currentScore
        self.streakStart = streakStart
        self.earnedAt = earnedAt
        self.updatedAt = updatedAt
    }
}

/// A reward a parent set for a teen.
public struct ParentReward: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var teenID: String
    public var teenName: String
    public var createdBy: String
    public var createdByName: String
    public var createdAt: Date
    public var goal: RewardGoal
    public var prize: RewardPrize
    public var progress: RewardProgress?
    /// Set by a parent once they've handed the reward over.
    public var givenAt: Date?

    public init(id: String, teenID: String, teenName: String, createdBy: String, createdByName: String,
                createdAt: Date, goal: RewardGoal, prize: RewardPrize, progress: RewardProgress? = nil, givenAt: Date? = nil) {
        self.id = id
        self.teenID = teenID
        self.teenName = teenName
        self.createdBy = createdBy
        self.createdByName = createdByName
        self.createdAt = createdAt
        self.goal = goal
        self.prize = prize
        self.progress = progress
        self.givenAt = givenAt
    }

    public enum Status: Equatable, Sendable {
        case waitingForProgress
        case inProgress
        case earned(Date)
        case given(Date)
    }

    public func status(now: Date = Date()) -> Status {
        if let givenAt { return .given(givenAt) }
        guard let progress else { return .waitingForProgress }
        if let earned = progress.earnedAt { return .earned(earned) }
        // A hold streak that has run long enough is met even before the next drive confirms it.
        if goal.kind == .hold, let start = progress.streakStart, now >= start.addingTimeInterval(goal.holdDuration) {
            return .earned(start.addingTimeInterval(goal.holdDuration))
        }
        return .inProgress
    }

    /// 0…1, for progress bars.
    public func fraction(now: Date = Date()) -> Double {
        switch status(now: now) {
        case .earned, .given: return 1
        case .waitingForProgress: return 0
        case .inProgress:
            guard let progress else { return 0 }
            switch goal.kind {
            case .reach:
                let floor = Double(CurbsideScale.minimum)
                return min(0.99, max(0, (Double(progress.currentScore) - floor) / (Double(goal.minScore) - floor)))
            case .hold:
                guard let start = progress.streakStart else { return 0 }
                return min(0.99, max(0, now.timeIntervalSince(start) / goal.holdDuration))
            }
        }
    }

    /// Plain-language progress line.
    public func progressDescription(now: Date = Date()) -> String {
        switch status(now: now) {
        case .given(let date): return "Given \(Self.day(date))"
        case .earned(let date): return "Earned \(Self.day(date))!"
        case .waitingForProgress: return "Progress shows up after \(teenName)'s next drive"
        case .inProgress:
            guard let progress else { return "" }
            switch goal.kind {
            case .reach:
                return "\(progress.currentScore) now · \(goal.minScore - progress.currentScore) to go"
            case .hold:
                guard let start = progress.streakStart else {
                    return "\(progress.currentScore) now · reach \(goal.minScore) to start the clock"
                }
                let total = (goal.weeks ?? 1) * 7
                let day = min(total, Int(now.timeIntervalSince(start) / 86_400) + 1)
                return "Day \(day) of \(total) at \(goal.minScore)+"
            }
        }
    }

    private static func day(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day()) }
}

// MARK: - Evaluating progress

public enum RewardEvaluator {
    /// Computes progress from the teen's score history (score after each drive, oldest first).
    /// Only time after the reward was created counts.
    public static func progress(for goal: RewardGoal, createdAt: Date, history: [CurbsideScorePoint],
                                startingScore: Int, previous: RewardProgress?, now: Date) -> RewardProgress {
        func score(at t: Date) -> Int { history.last { $0.date <= t }?.score ?? startingScore }
        let current = score(at: now)
        let later = history.filter { $0.date > createdAt && $0.date <= now }

        var earnedAt = previous?.earnedAt
        var streakStart: Date?

        switch goal.kind {
        case .reach:
            if earnedAt == nil {
                if score(at: createdAt) >= goal.minScore {
                    earnedAt = createdAt
                } else {
                    earnedAt = later.first { $0.score >= goal.minScore }?.date
                }
            }
        case .hold:
            let need = goal.holdDuration
            if score(at: createdAt) >= goal.minScore { streakStart = createdAt }
            for p in later {
                if p.score >= goal.minScore {
                    if streakStart == nil { streakStart = p.date }
                } else if let start = streakStart {
                    if earnedAt == nil, p.date.timeIntervalSince(start) >= need { earnedAt = start.addingTimeInterval(need) }
                    streakStart = nil
                }
            }
            if earnedAt == nil, let start = streakStart, now.timeIntervalSince(start) >= need {
                earnedAt = start.addingTimeInterval(need)
            }
        }
        return RewardProgress(currentScore: current, streakStart: streakStart, earnedAt: earnedAt, updatedAt: now)
    }
}

// MARK: - Unlocks and celebrations

public enum TierUnlock {
    /// The tier reached by the latest drive, if it's higher than any tier reached before it
    /// (so dipping and recovering doesn't celebrate twice).
    public static func newlyReachedTier(history: [CurbsideScorePoint], startingScore: Int) -> CurbsideTier? {
        guard let latest = history.last else { return nil }
        let earlier = [startingScore] + history.dropLast().map(\.score)
        let best = earlier.map { CurbsideTier.tier(for: $0) }.max() ?? .needsWork
        let now = CurbsideTier.tier(for: latest.score)
        return now > best ? now : nil
    }
}

/// Holds celebrations until it's safe to show them. Nothing comes out while driving.
public struct CelebrationQueue<Item: Sendable>: Sendable {
    private var items: [Item] = []

    public init() {}

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public mutating func enqueue(_ item: Item) { items.append(item) }

    public mutating func enqueue(contentsOf more: [Item]) { items += more }

    /// The next celebration, or nil while a drive is in progress.
    public mutating func next(isDriving: Bool) -> Item? {
        guard !isDriving, !items.isEmpty else { return nil }
        return items.removeFirst()
    }
}
