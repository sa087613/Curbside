import Foundation

/// A 3D vector used for device-frame sensor data.
public struct Vector3: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(0, 0, 0)

    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var lengthSquared: Double { x * x + y * y + z * z }

    /// Unit vector in the same direction, or `.zero` for a (near) zero vector.
    public var normalized: Vector3 {
        let len = length
        return len > 1e-12 ? self / len : .zero
    }

    public func dot(_ o: Vector3) -> Double { x * o.x + y * o.y + z * o.z }

    public func cross(_ o: Vector3) -> Vector3 {
        Vector3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    /// Removes the component along `unitAxis` (which must be normalized).
    public func rejecting(_ unitAxis: Vector3) -> Vector3 {
        self - unitAxis * dot(unitAxis)
    }

    /// Angle between two vectors in degrees.
    public func angleDegrees(to o: Vector3) -> Double {
        let denom = length * o.length
        guard denom > 1e-12 else { return 0 }
        let c = max(-1, min(1, dot(o) / denom))
        return acos(c) * 180 / .pi
    }

    public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vector3, s: Double) -> Vector3 { Vector3(a.x * s, a.y * s, a.z * s) }
    public static func / (a: Vector3, s: Double) -> Vector3 { Vector3(a.x / s, a.y / s, a.z / s) }
    public static func += (a: inout Vector3, b: Vector3) { a = a + b }
    public static func -= (a: inout Vector3, b: Vector3) { a = a - b }
}

/// Row-major 3x3 matrix.
public struct Matrix3: Sendable, Equatable {
    public var rows: (Vector3, Vector3, Vector3)

    public init(rows r0: Vector3, _ r1: Vector3, _ r2: Vector3) {
        rows = (r0, r1, r2)
    }

    public static let identity = Matrix3(rows: Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

    /// Rotation Rz(yaw) * Ry(pitch) * Rx(roll), angles in radians.
    public static func rotation(yaw: Double, pitch: Double, roll: Double) -> Matrix3 {
        let (cy, sy) = (cos(yaw), sin(yaw))
        let (cp, sp) = (cos(pitch), sin(pitch))
        let (cr, sr) = (cos(roll), sin(roll))
        return Matrix3(
            rows: Vector3(cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr),
            Vector3(sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr),
            Vector3(-sp, cp * sr, cp * cr)
        )
    }

    public static func * (m: Matrix3, v: Vector3) -> Vector3 {
        Vector3(m.rows.0.dot(v), m.rows.1.dot(v), m.rows.2.dot(v))
    }

    public static func * (a: Matrix3, b: Matrix3) -> Matrix3 {
        let c0 = Vector3(b.rows.0.x, b.rows.1.x, b.rows.2.x)
        let c1 = Vector3(b.rows.0.y, b.rows.1.y, b.rows.2.y)
        let c2 = Vector3(b.rows.0.z, b.rows.1.z, b.rows.2.z)
        func row(_ r: Vector3) -> Vector3 { Vector3(r.dot(c0), r.dot(c1), r.dot(c2)) }
        return Matrix3(rows: row(a.rows.0), row(a.rows.1), row(a.rows.2))
    }

    public static func == (a: Matrix3, b: Matrix3) -> Bool {
        a.rows.0 == b.rows.0 && a.rows.1 == b.rows.1 && a.rows.2 == b.rows.2
    }

    public var determinant: Double {
        rows.0.dot(rows.1.cross(rows.2))
    }

    /// Solves `self * x = b` with Cramer's rule. Returns nil when singular.
    public func solve(_ b: Vector3) -> Vector3? {
        let det = determinant
        guard abs(det) > 1e-15 else { return nil }
        let c0 = Vector3(rows.0.x, rows.1.x, rows.2.x)
        let c1 = Vector3(rows.0.y, rows.1.y, rows.2.y)
        let c2 = Vector3(rows.0.z, rows.1.z, rows.2.z)
        let dx = b.dot(c1.cross(c2))
        let dy = c0.dot(b.cross(c2))
        let dz = c0.dot(c1.cross(b))
        return Vector3(dx / det, dy / det, dz / det)
    }
}
