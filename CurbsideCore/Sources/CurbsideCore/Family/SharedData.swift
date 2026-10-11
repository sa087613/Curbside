import Foundation

// Everything in this file is what leaves the phone when a family member shares.
// `SharingDisclosure` must describe every field here; a test enforces that.

public enum FamilyRole: String, Codable, Sendable, CaseIterable {
    case parent
    case teen

    public var displayName: String {
        switch self {
        case .parent: "Parent"
        case .teen: "Teen"
        }
    }
}

/// A point on a shared route. Encoded as a map because Firestore can't store nested arrays.
public struct SharedPoint: Codable, Sendable, Equatable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// An event as a parent sees it: what, how bad, when, and where. No g-forces or speeds.
public struct SharedEvent: Codable, Sendable, Equatable {
    public var kind: DrivingEventKind
    public var severity: EventSeverity
    /// Seconds into the drive.
    public var offsetSeconds: Double
    public var lat: Double?
    public var lon: Double?

    public init(kind: DrivingEventKind, severity: EventSeverity, offsetSeconds: Double, lat: Double?, lon: Double?) {
        self.kind = kind
        self.severity = severity
        self.offsetSeconds = offsetSeconds
        self.lat = lat
        self.lon = lon
    }
}

/// The summary of one drive that a parent can see. Raw sensor data, speeds, and replays never leave the phone.
public struct SharedDrive: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var startDate: Date
    public var durationSeconds: Double
    public var miles: Double
    /// 0–100, nil when the drive was too short to score.
    public var score: Int?
    public var events: [SharedEvent]
    /// Simplified route (a few hundred points at most).
    public var route: [SharedPoint]

    public init(id: String, startDate: Date, durationSeconds: Double, miles: Double, score: Int?,
                events: [SharedEvent], route: [SharedPoint]) {
        self.id = id
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.miles = miles
        self.score = score
        self.events = events
        self.route = route
    }

    /// Builds the shareable summary of a recorded drive.
    public static func make(id: UUID, startDate: Date, durationSeconds: Double, distanceMeters: Double,
                            score: DriveScore?, events: [DrivingEvent], route: [RoutePoint],
                            config: FamilyConfig = .default) -> SharedDrive {
        let round = { (v: Double) -> Double in
            let scale = pow(10, Double(config.sharedCoordinateDecimals))
            return (v * scale).rounded() / scale
        }
        let simplified = RouteSimplifier.simplify(route.map { SharedPoint(lat: $0.latitude, lon: $0.longitude) },
                                                  toleranceMeters: config.sharedRouteToleranceMeters,
                                                  maxPoints: config.sharedRouteMaxPoints)
        return SharedDrive(
            id: id.uuidString,
            startDate: startDate,
            durationSeconds: durationSeconds.rounded(),
            miles: (distanceMeters / Units.metersPerMile * 100).rounded() / 100,
            score: score?.rounded,
            events: events.map {
                SharedEvent(kind: $0.kind, severity: $0.severity, offsetSeconds: $0.startTime.rounded(),
                            lat: $0.latitude.map(round), lon: $0.longitude.map(round))
            },
            route: simplified.map { SharedPoint(lat: round($0.lat), lon: round($0.lon)) }
        )
    }
}

/// A member's 7-day summary.
public struct WeeklySummary: Codable, Sendable, Equatable {
    public var drives: Int
    public var miles: Double
    /// Average drive score over scored drives, nil if none.
    public var averageScore: Int?
    public var hardBrakes: Int
    public var fastStarts: Int
    public var sharpTurns: Int

    public init(drives: Int, miles: Double, averageScore: Int?, hardBrakes: Int, fastStarts: Int, sharpTurns: Int) {
        self.drives = drives
        self.miles = miles
        self.averageScore = averageScore
        self.hardBrakes = hardBrakes
        self.fastStarts = fastStarts
        self.sharpTurns = sharpTurns
    }

    public static let empty = WeeklySummary(drives: 0, miles: 0, averageScore: nil, hardBrakes: 0, fastStarts: 0, sharpTurns: 0)

    public var totalEvents: Int { hardBrakes + fastStarts + sharpTurns }

    public static func compute(drives: [SharedDrive], now: Date = Date(), config: FamilyConfig = .default) -> WeeklySummary {
        let cutoff = now.addingTimeInterval(-Double(config.weeklySummaryDays) * 86_400)
        let week = drives.filter { $0.startDate > cutoff && $0.startDate <= now }
        let scores = week.compactMap(\.score)
        let events = week.flatMap(\.events)
        return WeeklySummary(
            drives: week.count,
            miles: (week.reduce(0) { $0 + $1.miles } * 10).rounded() / 10,
            averageScore: scores.isEmpty ? nil : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded()),
            hardBrakes: events.filter { $0.kind == .hardBrake }.count,
            fastStarts: events.filter { $0.kind == .harshAcceleration }.count,
            sharpTurns: events.filter { $0.kind == .sharpTurn }.count
        )
    }
}

/// What a member publishes to the family: their Curbside Score standing and weekly summary.
public struct SharedStanding: Codable, Sendable, Equatable {
    public var score: Int
    public var trendDelta: Int
    public var weekly: WeeklySummary
    public var updatedAt: Date

    public init(score: Int, trendDelta: Int, weekly: WeeklySummary, updatedAt: Date) {
        self.score = score
        self.trendDelta = trendDelta
        self.weekly = weekly
        self.updatedAt = updatedAt
    }

    public var tier: CurbsideTier { CurbsideTier.tier(for: score) }

    public init(report: CurbsideScoreReport, weekly: WeeklySummary, now: Date = Date()) {
        self.init(score: report.score, trendDelta: report.trend.delta, weekly: weekly, updatedAt: now)
    }
}

// MARK: - Route simplification

public enum RouteSimplifier {
    /// Douglas–Peucker in a local flat projection. Keeps the endpoints; loosens the tolerance
    /// until the result has at most `maxPoints` points.
    public static func simplify(_ points: [SharedPoint], toleranceMeters: Double, maxPoints: Int) -> [SharedPoint] {
        guard points.count > 2 else { return points }
        let lat0 = points[0].lat * .pi / 180
        let xy = points.map { (x: $0.lon * 111_320 * cos(lat0), y: $0.lat * 110_540) }
        var tolerance = max(toleranceMeters, 0.1)
        while true {
            var keep = [Bool](repeating: false, count: points.count)
            keep[0] = true
            keep[points.count - 1] = true
            var stack = [(0, points.count - 1)]
            while let (a, b) = stack.popLast() {
                guard b > a + 1 else { continue }
                var worst = -1.0, index = a
                for i in (a + 1)..<b {
                    let d = distance(xy[i], xy[a], xy[b])
                    if d > worst { worst = d; index = i }
                }
                if worst > tolerance {
                    keep[index] = true
                    stack.append((a, index))
                    stack.append((index, b))
                }
            }
            let result = zip(points, keep).filter(\.1).map(\.0)
            if result.count <= max(maxPoints, 2) { return result }
            tolerance *= 1.5
        }
    }

    private static func distance(_ p: (x: Double, y: Double), _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
