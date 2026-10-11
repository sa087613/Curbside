import Foundation

public enum DrivingEventKind: String, Codable, Sendable, CaseIterable {
    case hardBrake
    case harshAcceleration
    case sharpTurn

    public var displayName: String {
        switch self {
        case .hardBrake: "Hard brake"
        case .harshAcceleration: "Fast start"
        case .sharpTurn: "Sharp turn"
        }
    }
}

public enum EventSeverity: Int, Codable, Sendable, Comparable, CaseIterable {
    case moderate = 1
    case hard = 2
    case severe = 3

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var displayName: String {
        switch self {
        case .moderate: "Moderate"
        case .hard: "Hard"
        case .severe: "Severe"
        }
    }
}

/// A confirmed driving event.
public struct DrivingEvent: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var kind: DrivingEventKind
    public var severity: EventSeverity
    /// Seconds since drive start.
    public var startTime: Double
    public var endTime: Double
    public var peakTime: Double
    /// Peak smoothed acceleration in g (always positive).
    public var peakG: Double
    /// GPS speed (m/s) just before and just after the event.
    public var speedBefore: Double
    public var speedAfter: Double
    public var latitude: Double?
    public var longitude: Double?
    /// False when the event was measured before the forward axis was calibrated (fallback mode).
    public var usedCalibratedAxis: Bool

    public init(id: UUID = UUID(), kind: DrivingEventKind, severity: EventSeverity, startTime: Double,
                endTime: Double, peakTime: Double, peakG: Double, speedBefore: Double, speedAfter: Double,
                latitude: Double?, longitude: Double?, usedCalibratedAxis: Bool) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.startTime = startTime
        self.endTime = endTime
        self.peakTime = peakTime
        self.peakG = peakG
        self.speedBefore = speedBefore
        self.speedAfter = speedAfter
        self.latitude = latitude
        self.longitude = longitude
        self.usedCalibratedAxis = usedCalibratedAxis
    }
}

/// A motion spike that looked like an event but failed a check. Kept for tuning.
public struct RejectedCandidate: Codable, Sendable, Hashable {
    public var kind: DrivingEventKind
    public var startTime: Double
    public var endTime: Double
    public var peakG: Double
    public var reason: RejectionReason

    public init(kind: DrivingEventKind, startTime: Double, endTime: Double, peakG: Double, reason: RejectionReason) {
        self.kind = kind
        self.startTime = startTime
        self.endTime = endTime
        self.peakG = peakG
        self.reason = reason
    }
}

public enum RejectionReason: Codable, Sendable, Hashable {
    case tooShort(seconds: Double)
    case phoneMovement
    case noGPS
    case tooSlow(mph: Double)
    case gpsSpeedNotConfirmed(changeMph: Double, requiredMph: Double)
    case gyroNotConfirmed(gyroG: Double)
    case headingNotConfirmed(degrees: Double)

    /// Stable short key for grouping in reports.
    public var key: String {
        switch self {
        case .tooShort: "too short"
        case .phoneMovement: "phone movement"
        case .noGPS: "no GPS"
        case .tooSlow: "too slow"
        case .gpsSpeedNotConfirmed: "GPS speed not confirmed"
        case .gyroNotConfirmed: "gyro not confirmed"
        case .headingNotConfirmed: "heading not confirmed"
        }
    }

    public var description: String {
        switch self {
        case .tooShort(let s): String(format: "too short (%.2fs)", s)
        case .phoneMovement: "phone was moving (picked up / dropped)"
        case .noGPS: "no GPS speed around event"
        case .tooSlow(let mph): String(format: "too slow (%.0f mph)", mph)
        case .gpsSpeedNotConfirmed(let c, let r): String(format: "GPS speed changed %.1f mph, needed %.1f", c, r)
        case .gyroNotConfirmed(let g): String(format: "gyro turn rate only %.2fg", g)
        case .headingNotConfirmed(let d): String(format: "GPS heading changed only %.0f°", d)
        }
    }
}

/// Free-form detector diagnostics (axis calibration, resets) for the replay report.
public struct DetectorNote: Codable, Sendable, Hashable {
    public var t: Double
    public var message: String
}

public struct DetectionResult: Codable, Sendable {
    public var events: [DrivingEvent]
    public var rejected: [RejectedCandidate]
    public var notes: [DetectorNote]
    /// Fraction of processed motion samples measured with a calibrated forward axis.
    public var calibratedFraction: Double
    public var processedMotionSamples: Int
}
