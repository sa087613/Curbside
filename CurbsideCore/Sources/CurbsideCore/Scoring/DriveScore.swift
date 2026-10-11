import Foundation

/// Points lost to one kind of event in a drive.
public struct HabitDeduction: Codable, Sendable, Equatable {
    public var kind: DrivingEventKind
    public var count: Int
    /// Points deducted from the 100, after distance normalization.
    public var points: Double

    public init(kind: DrivingEventKind, count: Int, points: Double) {
        self.kind = kind
        self.count = count
        self.points = points
    }
}

/// The 0–100 score for one drive.
public struct DriveScore: Codable, Sendable, Equatable {
    /// Unrounded score, 0…100.
    public var value: Double
    /// One entry per event kind that occurred, most costly first.
    public var deductions: [HabitDeduction]
    public var distanceMiles: Double

    /// Displayed score.
    public var rounded: Int { Int(value.rounded()) }

    /// The single habit that cost the most points, or nil for a clean drive.
    public var habitToFix: HabitDeduction? { deductions.first }

    public var totalDeduction: Double { deductions.reduce(0) { $0 + $1.points } }

    /// Scores a drive. Returns nil when the drive is too short to score.
    public static func compute(events: [DrivingEvent], distanceMeters: Double,
                               config: ScoringConfig = .default) -> DriveScore? {
        let miles = distanceMeters / Units.metersPerMile
        guard miles >= config.minScoredMiles else { return nil }

        let scale = config.normalizationMiles / max(miles, config.minimumMiles)
        var byKind: [DrivingEventKind: HabitDeduction] = [:]
        for event in events {
            let points = config.points(for: event.kind) * config.multiplier(for: event.severity) * scale
            byKind[event.kind, default: HabitDeduction(kind: event.kind, count: 0, points: 0)].count += 1
            byKind[event.kind]!.points += points
        }

        // Most costly first; ties go to the more frequent habit, then a fixed order.
        let order = DrivingEventKind.allCases
        let deductions = byKind.values.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.count != $1.count { return $0.count > $1.count }
            return order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)!
        }
        let total = deductions.reduce(0) { $0 + $1.points }
        return DriveScore(value: min(100, max(0, 100 - total)), deductions: deductions, distanceMiles: miles)
    }
}

/// A 1 Hz route point, stored with each drive for the map and speed chart.
/// Encoded as a compact array `[t, latitude, longitude, speed]`.
public struct RoutePoint: Sendable, Equatable {
    /// Seconds since drive start.
    public var t: Double
    public var latitude: Double
    public var longitude: Double
    /// m/s, or nil if GPS speed was unavailable.
    public var speed: Double?

    public init(t: Double, latitude: Double, longitude: Double, speed: Double?) {
        self.t = t
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
    }

    /// Accurate fixes from a drive, thinned to at most one per `interval` seconds.
    public static func route(from locations: [LocationSample], interval: Double = 1,
                             maxAccuracyMeters: Double = 30) -> [RoutePoint] {
        var points: [RoutePoint] = []
        for s in locations where s.horizontalAccuracy >= 0 && s.horizontalAccuracy <= maxAccuracyMeters {
            if let last = points.last, s.t - last.t < interval * 0.9 { continue }
            points.append(RoutePoint(t: s.t, latitude: s.latitude, longitude: s.longitude,
                                     speed: s.hasValidSpeed ? s.speed : nil))
        }
        return points
    }
}

extension RoutePoint: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        t = try c.decode(Double.self)
        latitude = try c.decode(Double.self)
        longitude = try c.decode(Double.self)
        speed = try c.decodeNil() ? nil : try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(t)
        try c.encode(latitude)
        try c.encode(longitude)
        if let speed { try c.encode((speed * 100).rounded() / 100) } else { try c.encodeNil() }
    }
}
