import Foundation

/// One scored drive, as input to the Curbside Score.
public struct ScoredDrive: Sendable, Equatable {
    public var id: UUID
    public var date: Date
    /// Drive score, 0…100.
    public var score: Double
    public var miles: Double
    /// Points lost per habit on this drive.
    public var deductions: [HabitDeduction]

    public init(id: UUID = UUID(), date: Date, score: Double, miles: Double, deductions: [HabitDeduction] = []) {
        self.id = id
        self.date = date
        self.score = score
        self.miles = miles
        self.deductions = deductions
    }

    public init(id: UUID, date: Date, driveScore: DriveScore) {
        self.init(id: id, date: date, score: driveScore.value, miles: driveScore.distanceMiles, deductions: driveScore.deductions)
    }
}

public enum CurbsideTier: Int, Sendable, CaseIterable, Comparable {
    case needsWork, fair, good, great, excellent

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var displayName: String {
        switch self {
        case .needsWork: "Needs Work"
        case .fair: "Fair"
        case .good: "Good"
        case .great: "Great"
        case .excellent: "Excellent"
        }
    }

    public static func tier(for score: Int, config: CurbsideScoreConfig = .default) -> CurbsideTier {
        switch score {
        case config.excellentFrom...: .excellent
        case config.greatFrom...: .great
        case config.goodFrom...: .good
        case config.fairFrom...: .fair
        default: .needsWork
        }
    }

    /// Score range covered by this tier.
    public func range(config: CurbsideScoreConfig = .default) -> ClosedRange<Int> {
        switch self {
        case .needsWork: CurbsideScale.minimum...(config.fairFrom - 1)
        case .fair: config.fairFrom...(config.goodFrom - 1)
        case .good: config.goodFrom...(config.greatFrom - 1)
        case .great: config.greatFrom...(config.excellentFrom - 1)
        case .excellent: config.excellentFrom...CurbsideScale.maximum
        }
    }
}

/// Converts a 0–100 average drive score to 300–850.
public enum CurbsideScale {
    public static let minimum = 300
    public static let maximum = 850

    public static func score(forAverage average: Double, config: CurbsideScoreConfig = .default) -> Double {
        let anchors = config.scaleAnchors.sorted { $0.average < $1.average }
        guard let first = anchors.first, let last = anchors.last else { return Double(minimum) }
        let value: Double
        if average <= first.average {
            value = first.score
        } else if average >= last.average {
            value = last.score
        } else {
            let i = anchors.firstIndex { $0.average >= average }!
            let a = anchors[i - 1], b = anchors[i]
            value = a.score + (b.score - a.score) * (average - a.average) / (b.average - a.average)
        }
        return min(Double(maximum), max(Double(minimum), value))
    }
}

/// The score after a given drive, for history charts.
public struct CurbsideScorePoint: Sendable, Equatable {
    public var date: Date
    public var driveID: UUID
    public var score: Int
    public var exactScore: Double

    public init(date: Date, driveID: UUID, score: Int, exactScore: Double) {
        self.date = date
        self.driveID = driveID
        self.score = score
        self.exactScore = exactScore
    }
}

public enum TrendDirection: Sendable, Equatable {
    case up, down, flat
}

public struct ScoreTrend: Sendable, Equatable {
    /// Change versus `windowDays` ago.
    public var delta: Int
    public var direction: TrendDirection
    public var windowDays: Int

    public init(delta: Int, direction: TrendDirection, windowDays: Int) {
        self.delta = delta
        self.direction = direction
        self.windowDays = windowDays
    }

    /// Direction from the change, using the configured deadband.
    public init(delta: Int, config: CurbsideScoreConfig = .default) {
        self.init(delta: delta,
                  direction: delta > config.trendDeadband ? .up : delta < -config.trendDeadband ? .down : .flat,
                  windowDays: config.trendWindowDays)
    }
}

public enum ScoreFactorKind: Sendable, Hashable {
    /// Points this habit is costing right now.
    case habit(DrivingEventKind)
    /// Change over the last few drives.
    case momentum
    /// How much the new-driver starting point is still pulling the score.
    case experience
}

/// One "what's moving your score" line.
public struct ScoreFactor: Sendable, Equatable {
    public var kind: ScoreFactorKind
    /// Curbside points: negative hurts, positive helps.
    public var impact: Int
    /// Habit factors: recency-weighted events per 10 miles.
    public var ratePer10Miles: Double?
    /// Momentum: drives compared; experience: scored drives so far.
    public var driveCount: Int?
}

/// Everything the UI needs about the Curbside Score. Pure function of the drive list.
public struct CurbsideScoreReport: Sendable, Equatable {
    public var score: Int
    public var exactScore: Double
    /// Recency-weighted average drive score (0–100), including the new-driver prior.
    public var averageDriveScore: Double
    public var tier: CurbsideTier
    public var scoredDriveCount: Int
    /// Score after each drive, oldest first.
    public var history: [CurbsideScorePoint]
    public var trend: ScoreTrend
    /// Biggest movers first.
    public var factors: [ScoreFactor]

    public static func compute(drives: [ScoredDrive], now: Date = Date(),
                               config: CurbsideScoreConfig = .default) -> CurbsideScoreReport {
        let sorted = drives.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
        let λ = config.decayPerDrive

        // Running recency-weighted sums. Every new drive first decays everything before it.
        var priorRemaining = config.priorWeight
        var weightedScores = config.priorWeight * config.priorDriveScore
        var totalWeight = config.priorWeight
        var habitPoints: [DrivingEventKind: Double] = [:]
        var habitCounts: [DrivingEventKind: Double] = [:]
        var recentMiles = 0.0

        var history: [CurbsideScorePoint] = []
        history.reserveCapacity(sorted.count)

        for drive in sorted {
            priorRemaining *= λ
            weightedScores *= λ
            totalWeight *= λ
            recentMiles *= λ
            for k in habitPoints.keys { habitPoints[k]! *= λ }
            for k in habitCounts.keys { habitCounts[k]! *= λ }

            let w = min(config.maxDistanceWeight, max(config.minDistanceWeight, drive.miles / config.milesPerDriveWeight))
            weightedScores += w * drive.score
            totalWeight += w
            recentMiles += drive.miles
            for d in drive.deductions {
                habitPoints[d.kind, default: 0] += w * d.points
                habitCounts[d.kind, default: 0] += Double(d.count)
            }

            let exact = CurbsideScale.score(forAverage: weightedScores / totalWeight, config: config)
            history.append(CurbsideScorePoint(date: drive.date, driveID: drive.id, score: Int(exact.rounded()), exactScore: exact))
        }

        let average = weightedScores / totalWeight
        let exact = CurbsideScale.score(forAverage: average, config: config)
        let score = Int(exact.rounded())
        let startingScore = Int(CurbsideScale.score(forAverage: config.priorDriveScore, config: config).rounded())

        // Trend: versus the score as of `trendWindowDays` ago (the starting score if they began since).
        let cutoff = now.addingTimeInterval(-Double(config.trendWindowDays) * 86_400)
        let baseline = sorted.isEmpty ? score : (history.last { $0.date <= cutoff }?.score ?? startingScore)
        let delta = score - baseline
        let direction: TrendDirection = delta > config.trendDeadband ? .up : delta < -config.trendDeadband ? .down : .flat

        // Factors.
        var factors: [ScoreFactor] = []
        for kind in DrivingEventKind.allCases {
            guard let points = habitPoints[kind], points > 0 else { continue }
            // What the score would be if this habit had cost nothing.
            let without = CurbsideScale.score(forAverage: min(100, average + points / totalWeight), config: config)
            let impact = -Int((without - exact).rounded())
            guard impact != 0 else { continue }
            let rate = recentMiles > 0 ? (habitCounts[kind] ?? 0) / recentMiles * 10 : nil
            factors.append(ScoreFactor(kind: .habit(kind), impact: impact, ratePer10Miles: rate, driveCount: nil))
        }
        if !history.isEmpty {
            let m = config.momentumDrives
            let base = history.count > m ? history[history.count - 1 - m].score : startingScore
            let change = score - base
            if abs(change) > config.trendDeadband {
                factors.append(ScoreFactor(kind: .momentum, impact: change, ratePer10Miles: nil, driveCount: min(m, history.count)))
            }
            // Score from real drives alone vs with the starting point mixed in.
            let realWeight = totalWeight - priorRemaining
            if realWeight > 0 {
                let realAverage = (weightedScores - priorRemaining * config.priorDriveScore) / realWeight
                let impact = Int((exact - CurbsideScale.score(forAverage: realAverage, config: config)).rounded())
                if abs(impact) > config.trendDeadband {
                    factors.append(ScoreFactor(kind: .experience, impact: impact, ratePer10Miles: nil, driveCount: history.count))
                }
            }
        }
        factors.sort { abs($0.impact) > abs($1.impact) }

        return CurbsideScoreReport(
            score: score,
            exactScore: exact,
            averageDriveScore: average,
            tier: CurbsideTier.tier(for: score, config: config),
            scoredDriveCount: sorted.count,
            history: history,
            trend: ScoreTrend(delta: delta, direction: direction, windowDays: config.trendWindowDays),
            factors: factors
        )
    }
}
