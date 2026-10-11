import Foundation

// ┌──────────────────────────────────────────────────────────────────────────┐
// │  Every tunable threshold in Curbside lives in this file.                  │
// │                                                                          │
// │  Tuning loop:                                                            │
// │    1. Record a drive, export its JSON from the drive's detail screen.     │
// │    2. `swift run replay drive.json --verbose` (from CurbsideCore/).       │
// │    3. Change a value here (or pass `--config my.json`; get a starting     │
// │       file with `swift run replay --dump-config`), replay again.          │
// │    4. `swift test` to make sure the known scenarios still pass.           │
// │                                                                          │
// │  Accelerations are in g (1 g = 9.81 m/s²). Speeds are in mph.             │
// └──────────────────────────────────────────────────────────────────────────┘

public struct DetectionConfig: Codable, Sendable, Equatable {

    // MARK: Signal processing

    /// Core Motion sample rate requested by the app.
    public var motionSampleRateHz: Double = 50
    /// Moving-average window applied to horizontal acceleration and yaw rate.
    public var smoothingWindowSeconds: Double = 0.25
    /// Motion is processed this far behind the newest GPS fix, so every event can be
    /// checked against GPS speed before *and after* it. (There's no UI during a drive,
    /// so the delay is invisible.)
    public var processingLatencySeconds: Double = 3.0
    /// If GPS goes quiet (tunnel), process motion anyway after this long.
    public var maxGpsWaitSeconds: Double = 10.0

    // MARK: GPS quality

    /// Fixes worse than this are ignored entirely.
    public var maxHorizontalAccuracyMeters: Double = 50
    /// Speeds with a worse reported accuracy are ignored (negative = unknown, accepted).
    public var maxSpeedAccuracyMps: Double = 2.0
    /// Don't interpolate GPS speed across gaps longer than this.
    public var maxGpsGapSeconds: Double = 4.0
    /// Core Location speed can trail the true speed. Motion is compared with GPS speed this
    /// many seconds earlier when fitting the forward axis. Tune if the axis fit correlation is low.
    public var gpsSpeedLagSeconds: Double = 0.0

    // MARK: Forward-axis estimation (which way is "forward" for the phone)

    public var axis = AxisConfig()

    // MARK: Phone handling (picked up, dropped, re-mounted)

    /// Rotation rate around a horizontal axis above this means the phone itself is moving,
    /// not the car (cars yaw, they don't pitch/roll quickly).
    public var handlingRotationRateRadPerSec: Double = 1.5
    /// Events overlapping [handling - before, handling + after] are rejected.
    public var handlingSuppressBeforeSeconds: Double = 1.0
    public var handlingSuppressAfterSeconds: Double = 3.0

    // MARK: Events

    public var hardBrake = LongitudinalEventConfig(
        moderateG: 0.28, hardG: 0.38, severeG: 0.50,
        minDurationSeconds: 0.4, releaseSeconds: 0.5,
        minStartSpeedMph: 8, minSpeedChangeMph: 3, minSpeedChangeRatio: 0.4,
        gpsMarginBeforeSeconds: 1.0, gpsMarginAfterSeconds: 1.5
    )

    public var harshAcceleration = LongitudinalEventConfig(
        moderateG: 0.25, hardG: 0.33, severeG: 0.45,
        minDurationSeconds: 0.4, releaseSeconds: 0.5,
        minStartSpeedMph: 0, minSpeedChangeMph: 3, minSpeedChangeRatio: 0.4,
        gpsMarginBeforeSeconds: 1.0, gpsMarginAfterSeconds: 1.5
    )

    public var sharpTurn = TurnEventConfig()

    /// A candidate ends when the signal drops below `threshold × exitRatio` (hysteresis).
    public var exitRatio: Double = 0.7

    public init() {}

    public static let `default` = DetectionConfig()
}

public struct AxisConfig: Codable, Sendable, Equatable {
    /// Need at least this many 1-second GPS intervals with a real speed change before trusting the fit.
    public var minExcitedIntervals: Int = 6
    /// An interval counts as "excited" when GPS shows at least this much acceleration.
    public var excitationG: Double = 0.05
    /// Correlation between projected motion and GPS acceleration required to trust the axis.
    public var minCorrelation: Double = 0.7
    /// Rolling window of intervals used for the fit.
    public var maxIntervals: Int = 600
    /// Both ends of an interval must be at least this fast (stationary GPS speed is noise).
    public var minSpeedMph: Double = 5
    /// Longest GPS interval used for fitting.
    public var maxIntervalSeconds: Double = 2.5
    /// If the phone's orientation (gravity direction) shifts by more than this, re-fit from scratch.
    public var gravityShiftResetDegrees: Double = 20
    /// Time constant of the gravity low-pass filter used for the shift check.
    public var gravityFilterSeconds: Double = 1.0
    /// If the gyro's heading change over a GPS interval differs from GPS heading change by more
    /// than this, the phone was rotated in its mount (e.g. spun flat on the dash): re-fit.
    public var yawMismatchResetDegrees: Double = 45
    /// GPS course readings worse than this are not used for the yaw check.
    public var maxCourseAccuracyDegrees: Double = 15

    public init() {}
}

public struct LongitudinalEventConfig: Codable, Sendable, Equatable {
    /// Peak smoothed acceleration for each severity tier.
    public var moderateG: Double
    public var hardG: Double
    public var severeG: Double
    /// Signal must stay above the exit level for at least this long.
    public var minDurationSeconds: Double
    /// Dips below the exit level shorter than this don't end the event.
    public var releaseSeconds: Double
    /// Ignore events that start slower than this (parking lots).
    public var minStartSpeedMph: Double
    /// GPS must show at least this speed change across the event…
    public var minSpeedChangeMph: Double
    /// …and at least this fraction of the change implied by integrating the accelerometer.
    public var minSpeedChangeRatio: Double
    /// GPS speed is sampled this long before the event starts and after it ends.
    public var gpsMarginBeforeSeconds: Double
    public var gpsMarginAfterSeconds: Double

    public init(moderateG: Double, hardG: Double, severeG: Double, minDurationSeconds: Double,
                releaseSeconds: Double, minStartSpeedMph: Double, minSpeedChangeMph: Double,
                minSpeedChangeRatio: Double, gpsMarginBeforeSeconds: Double, gpsMarginAfterSeconds: Double) {
        self.moderateG = moderateG
        self.hardG = hardG
        self.severeG = severeG
        self.minDurationSeconds = minDurationSeconds
        self.releaseSeconds = releaseSeconds
        self.minStartSpeedMph = minStartSpeedMph
        self.minSpeedChangeMph = minSpeedChangeMph
        self.minSpeedChangeRatio = minSpeedChangeRatio
        self.gpsMarginBeforeSeconds = gpsMarginBeforeSeconds
        self.gpsMarginAfterSeconds = gpsMarginAfterSeconds
    }
}

public struct TurnEventConfig: Codable, Sendable, Equatable {
    public var moderateG: Double = 0.35
    public var hardG: Double = 0.45
    public var severeG: Double = 0.60
    public var minDurationSeconds: Double = 0.5
    public var releaseSeconds: Double = 0.5
    /// Turns slower than this (parking, U-turns at a crawl) are ignored.
    public var minSpeedMph: Double = 10
    /// Gyro-derived centripetal acceleration (speed × yaw rate) must reach this fraction of
    /// `moderateG`, so a phone sliding sideways doesn't count as a turn.
    public var gyroConfirmRatio: Double = 0.6
    /// GPS heading must change at least this much across the turn (skipped when GPS course is unavailable).
    public var minCourseChangeDegrees: Double = 10

    public init() {}
}

extension LongitudinalEventConfig {
    func severity(forPeak g: Double) -> EventSeverity {
        g >= severeG ? .severe : g >= hardG ? .hard : .moderate
    }
}

extension TurnEventConfig {
    func severity(forPeak g: Double) -> EventSeverity {
        g >= severeG ? .severe : g >= hardG ? .hard : .moderate
    }
}

// MARK: - Drive score (0–100)

/// Score = 100 − Σ(points × severity multiplier) × (normalizationMiles / max(miles, minimumMiles)),
/// clamped to 0…100.
///
/// Read the point values as "points lost per event, per `normalizationMiles` driven". So one hard-severity
/// hard brake (8 × 1.5 = 12 points) costs 12 on a 5-mile drive, 6 on a 10-mile drive, and 20 on a short
/// errand (anything under `minimumMiles` counts as `minimumMiles`).
public struct ScoringConfig: Codable, Sendable, Equatable {
    public var hardBrakePoints: Double = 8
    public var harshAccelerationPoints: Double = 5
    public var sharpTurnPoints: Double = 6

    public var moderateMultiplier: Double = 1.0
    public var hardMultiplier: Double = 1.5
    public var severeMultiplier: Double = 2.5

    /// Deductions are expressed per this many miles.
    public var normalizationMiles: Double = 5
    /// Short drives count as at least this long, so one event on a 1-mile errand doesn't zero the score.
    public var minimumMiles: Double = 3
    /// Drives shorter than this aren't scored at all (parking-lot moves, GPS noise).
    public var minScoredMiles: Double = 0.3

    public init() {}

    public static let `default` = ScoringConfig()

    public func points(for kind: DrivingEventKind) -> Double {
        switch kind {
        case .hardBrake: hardBrakePoints
        case .harshAcceleration: harshAccelerationPoints
        case .sharpTurn: sharpTurnPoints
        }
    }

    public func multiplier(for severity: EventSeverity) -> Double {
        switch severity {
        case .moderate: moderateMultiplier
        case .hard: hardMultiplier
        case .severe: severeMultiplier
        }
    }
}

// MARK: - Event replay

public struct ReplayConfig: Codable, Sendable, Equatable {
    /// How much driving before the event's peak to replay.
    public var leadSeconds: Double = 5
    /// How much after the peak to include (0 = the clip ends at the worst moment).
    public var trailSeconds: Double = 0
    /// Frames per second in a built clip. Playback interpolates between frames.
    public var frameRateHz: Double = 30

    public init() {}

    public static let `default` = ReplayConfig()
}

// MARK: - Curbside Score (300–850)

/// The long-term score: a recency-weighted average of drive scores, mapped onto 300–850.
///
/// - Weight of a drive = `decayPerDrive^k × distance weight`, where k = how many drives ago it was.
///   Decay counts drives, not days, so a break from driving never moves the score.
/// - A new driver starts with `priorWeight` "virtual drives" scoring `priorDriveScore`. They decay
///   like real drives, so they stop mattering after a few dozen drives.
/// - The 0–100 average is converted with the piecewise-linear `scaleAnchors`.
public struct CurbsideScoreConfig: Codable, Sendable, Equatable {
    /// How much each older drive counts relative to the next newer one (0.95 → half weight ~14 drives back).
    public var decayPerDrive: Double = 0.95
    /// A drive of this many miles counts as one drive.
    public var milesPerDriveWeight: Double = 5
    /// Bounds on a single drive's distance weight (a 1-mile errand counts 0.4; 10+ miles counts 2).
    public var minDistanceWeight: Double = 0.4
    public var maxDistanceWeight: Double = 2.0
    /// New-driver starting point: this many virtual drives at this drive score (80 → 660).
    public var priorWeight: Double = 8
    public var priorDriveScore: Double = 80
    /// (average drive score, Curbside Score) points; linear in between, clamped outside.
    public var scaleAnchors: [ScaleAnchor] = [
        ScaleAnchor(average: 40, score: 300),
        ScaleAnchor(average: 70, score: 580),
        ScaleAnchor(average: 85, score: 700),
        ScaleAnchor(average: 95, score: 800),
        ScaleAnchor(average: 100, score: 850),
    ]
    /// Lower bounds of each tier above Needs Work.
    public var fairFrom = 580
    public var goodFrom = 670
    public var greatFrom = 740
    public var excellentFrom = 800
    /// Trend arrow compares with the score this many days ago…
    public var trendWindowDays = 7
    /// …and stays flat for changes this small.
    public var trendDeadband = 3
    /// "Momentum" factor: change over this many drives.
    public var momentumDrives = 5

    public init() {}

    public static let `default` = CurbsideScoreConfig()
}

public struct ScaleAnchor: Codable, Sendable, Equatable {
    public var average: Double
    public var score: Double

    public init(average: Double, score: Double) {
        self.average = average
        self.score = score
    }
}

// MARK: - Family sharing

public struct FamilyConfig: Codable, Sendable, Equatable {
    /// Characters in an invite code (shown as two groups of four).
    public var inviteCodeLength = 8
    /// Invite codes stop working after this many days.
    public var inviteValidDays = 7
    /// Shared routes are simplified to at most this many points…
    public var sharedRouteMaxPoints = 300
    /// …starting with this tolerance (meters) and loosening until they fit.
    public var sharedRouteToleranceMeters = 8.0
    /// Coordinates are rounded to this many decimal places before upload (5 ≈ 1 m).
    public var sharedCoordinateDecimals = 5
    /// Drives a parent sees per teen.
    public var recentDrivesShown = 20
    /// "This week" for the weekly summary.
    public var weeklySummaryDays = 7

    public init() {}

    public static let `default` = FamilyConfig()
}
