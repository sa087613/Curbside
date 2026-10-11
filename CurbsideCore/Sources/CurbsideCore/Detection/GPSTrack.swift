import Foundation

/// Filtered GPS fixes with time-based lookups (speed, acceleration, position, heading change).
struct GPSTrack {
    private let config: DetectionConfig
    /// Fixes with acceptable horizontal accuracy (used for position).
    private(set) var fixes: [LocationSample] = []
    /// Subset of `fixes` with a usable speed.
    private(set) var speedFixes: [LocationSample] = []

    init(config: DetectionConfig) {
        self.config = config
    }

    var latestTime: Double? { fixes.last?.t }

    /// Returns false if the fix was discarded.
    @discardableResult
    mutating func append(_ s: LocationSample) -> Bool {
        guard s.horizontalAccuracy >= 0, s.horizontalAccuracy <= config.maxHorizontalAccuracyMeters else { return false }
        if let last = fixes.last, s.t <= last.t { return false }
        fixes.append(s)
        if s.hasValidSpeed, s.speedAccuracy < 0 || s.speedAccuracy <= config.maxSpeedAccuracyMps {
            speedFixes.append(s)
        }
        return true
    }

    /// Index of the first element with `t >= time`.
    private static func lowerBound(_ a: [LocationSample], _ time: Double) -> Int {
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid].t < time { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The two speed fixes surrounding `time`, if they're close enough together.
    func speedBracket(at time: Double) -> (LocationSample, LocationSample)? {
        var i = Self.lowerBound(speedFixes, time)
        // A time exactly on the first fix still has a bracket: the first interval.
        if i == 0, i < speedFixes.count, speedFixes[0].t == time { i = 1 }
        guard i > 0, i < speedFixes.count else { return nil }
        let a = speedFixes[i - 1], b = speedFixes[i]
        guard b.t - a.t <= config.maxGpsGapSeconds else { return nil }
        return (a, b)
    }

    /// Linearly interpolated GPS speed (m/s).
    func speed(at time: Double) -> Double? {
        guard let (a, b) = speedBracket(at: time) else { return nil }
        let f = (time - a.t) / (b.t - a.t)
        return a.speed + (b.speed - a.speed) * f
    }

    /// GPS longitudinal acceleration (m/s²) over the interval containing `time`.
    func acceleration(at time: Double) -> Double? {
        guard let (a, b) = speedBracket(at: time), b.t > a.t else { return nil }
        return (b.speed - a.speed) / (b.t - a.t)
    }

    func coordinate(at time: Double) -> (latitude: Double, longitude: Double)? {
        guard !fixes.isEmpty else { return nil }
        let i = Self.lowerBound(fixes, time)
        if i == 0 { return (fixes[0].latitude, fixes[0].longitude) }
        if i >= fixes.count { return (fixes[fixes.count - 1].latitude, fixes[fixes.count - 1].longitude) }
        let a = fixes[i - 1], b = fixes[i]
        let f = (time - a.t) / (b.t - a.t)
        return (a.latitude + (b.latitude - a.latitude) * f, a.longitude + (b.longitude - a.longitude) * f)
    }

    /// Net heading change (degrees, absolute) across fixes in [t0 - 1, t1 + 1], or nil if
    /// fewer than two fixes have a valid course.
    func courseChange(from t0: Double, to t1: Double) -> Double? {
        let start = Self.lowerBound(fixes, t0 - 1)
        var previous: Double?
        var total = 0.0
        var count = 0
        var i = start
        while i < fixes.count, fixes[i].t <= t1 + 1 {
            let f = fixes[i]
            if f.hasValidCourse {
                if let p = previous {
                    var d = f.course - p
                    if d > 180 { d -= 360 }
                    if d < -180 { d += 360 }
                    total += d
                }
                previous = f.course
                count += 1
            }
            i += 1
        }
        return count >= 2 ? abs(total) : nil
    }
}
