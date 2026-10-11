import Foundation

public enum Units {
    /// Standard gravity in m/s².
    public static let g = 9.80665
    public static let mphPerMps = 2.2369362920544
    public static let metersPerMile = 1609.344

    public static func mph(fromMps mps: Double) -> Double { mps * mphPerMps }
    public static func mps(fromMph mph: Double) -> Double { mph / mphPerMps }
}

/// One Core Motion device-motion reading, in the phone's own (device) frame.
///
/// Encoded as a compact array `[t, ax, ay, az, gx, gy, gz, rx, ry, rz]` to keep exports small.
public struct MotionSample: Sendable, Equatable {
    /// Seconds since the drive started.
    public var t: Double
    /// `CMDeviceMotion.userAcceleration`: gravity already removed, in g.
    public var userAcceleration: Vector3
    /// `CMDeviceMotion.gravity`: points toward the ground, in g.
    public var gravity: Vector3
    /// `CMDeviceMotion.rotationRate`: rad/s.
    public var rotationRate: Vector3

    public init(t: Double, userAcceleration: Vector3, gravity: Vector3, rotationRate: Vector3) {
        self.t = t
        self.userAcceleration = userAcceleration
        self.gravity = gravity
        self.rotationRate = rotationRate
    }

    /// Rounds values to the precision used in exports, so live detection and replay
    /// of an exported drive see identical numbers.
    public func quantized() -> MotionSample {
        func q(_ v: Double, _ scale: Double) -> Double { (v * scale).rounded() / scale }
        func qv(_ v: Vector3) -> Vector3 { Vector3(q(v.x, 1e5), q(v.y, 1e5), q(v.z, 1e5)) }
        return MotionSample(t: q(t, 1e4), userAcceleration: qv(userAcceleration), gravity: qv(gravity), rotationRate: qv(rotationRate))
    }
}

extension MotionSample: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var v = [Double]()
        v.reserveCapacity(10)
        while !c.isAtEnd { v.append(try c.decode(Double.self)) }
        guard v.count == 10 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Motion sample needs 10 values, got \(v.count)"))
        }
        self.init(t: v[0], userAcceleration: Vector3(v[1], v[2], v[3]), gravity: Vector3(v[4], v[5], v[6]), rotationRate: Vector3(v[7], v[8], v[9]))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for v in [t, userAcceleration.x, userAcceleration.y, userAcceleration.z,
                  gravity.x, gravity.y, gravity.z,
                  rotationRate.x, rotationRate.y, rotationRate.z] {
            try c.encode(v)
        }
    }
}

/// One Core Location fix. Negative accuracy/speed/course values mean "invalid", matching CLLocation.
public struct LocationSample: Codable, Sendable, Equatable {
    /// Seconds since the drive started (from `CLLocation.timestamp`).
    public var t: Double
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    /// m/s, negative if invalid.
    public var speed: Double
    public var speedAccuracy: Double
    /// Degrees clockwise from true north, negative if invalid.
    public var course: Double
    public var courseAccuracy: Double

    public init(t: Double, latitude: Double, longitude: Double, horizontalAccuracy: Double,
                speed: Double, speedAccuracy: Double, course: Double, courseAccuracy: Double) {
        self.t = t
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
    }

    public var hasValidSpeed: Bool { speed >= 0 }
    public var hasValidCourse: Bool { course >= 0 }
}

/// Great-circle distance in meters.
public func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let r = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(min(1, a.squareRoot()))
}

/// Initial bearing from point 1 to point 2, degrees clockwise from north.
public func bearingDegrees(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let φ1 = lat1 * .pi / 180, φ2 = lat2 * .pi / 180
    let Δλ = (lon2 - lon1) * .pi / 180
    let y = sin(Δλ) * cos(φ2)
    let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}
