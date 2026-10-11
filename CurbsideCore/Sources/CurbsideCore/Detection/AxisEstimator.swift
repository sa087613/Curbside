import Foundation

/// Learns which direction (in the phone's own frame) points toward the front of the car.
///
/// Each 1-second GPS interval gives a pair: the average horizontal motion acceleration
/// vector `h` (device frame) and the GPS acceleration `a` (speed change / time). The
/// forward axis `f` is the direction that best explains `a ≈ h · f`, found by
/// least squares. This works for any phone orientation and doesn't use the compass,
/// which is unreliable inside a car.
public struct AxisEstimator: Sendable {
    public struct Interval: Sendable {
        /// Mean gravity-free horizontal acceleration over the interval, device frame, in g.
        public var horizontal: Vector3
        /// Mean gravity direction (unit) over the interval.
        public var gravity: Vector3
        /// GPS acceleration over the interval, in g.
        public var gpsAccelerationG: Double

        public init(horizontal: Vector3, gravity: Vector3, gpsAccelerationG: Double) {
            self.horizontal = horizontal
            self.gravity = gravity
            self.gpsAccelerationG = gpsAccelerationG
        }
    }

    private let config: AxisConfig
    private var intervals: [Interval] = []

    /// Unit forward vector in the device frame, set once the fit is trustworthy.
    public private(set) var forward: Vector3?
    /// Fit quality of the latest solve (Pearson correlation of predicted vs GPS acceleration).
    public private(set) var correlation: Double = 0
    /// Gravity direction the current fit was learned under.
    public private(set) var referenceGravity: Vector3?

    public init(config: AxisConfig) {
        self.config = config
    }

    public var isCalibrated: Bool { forward != nil }
    public var intervalCount: Int { intervals.count }

    public mutating func reset() {
        intervals.removeAll()
        forward = nil
        correlation = 0
        referenceGravity = nil
    }

    public mutating func add(_ interval: Interval) {
        intervals.append(interval)
        if intervals.count > config.maxIntervals {
            intervals.removeFirst(intervals.count - config.maxIntervals)
        }
        if referenceGravity == nil { referenceGravity = interval.gravity }
        solve()
    }

    private mutating func solve() {
        let excited = intervals.filter { abs($0.gpsAccelerationG) >= config.excitationG }.count
        guard excited >= config.minExcitedIntervals else {
            forward = nil
            return
        }

        // Normal equations (Σ h hᵀ + λI) f = Σ h a, with a small ridge term because
        // h has (almost) no vertical component, which makes Σ h hᵀ singular.
        var r0 = Vector3.zero, r1 = Vector3.zero, r2 = Vector3.zero
        var b = Vector3.zero
        var gravitySum = Vector3.zero
        for i in intervals {
            let h = i.horizontal
            r0 += h * h.x
            r1 += h * h.y
            r2 += h * h.z
            b += h * i.gpsAccelerationG
            gravitySum += i.gravity
        }
        let trace = r0.x + r1.y + r2.z
        let lambda = 1e-9 + 1e-3 * trace / 3
        r0.x += lambda
        r1.y += lambda
        r2.z += lambda
        guard let raw = Matrix3(rows: r0, r1, r2).solve(b) else {
            forward = nil
            return
        }
        let up = gravitySum.normalized
        let f = raw.rejecting(up).normalized
        guard f != .zero else {
            forward = nil
            return
        }

        correlation = Self.pearson(intervals.map { $0.horizontal.dot(f) }, intervals.map(\.gpsAccelerationG))
        forward = correlation >= config.minCorrelation ? f : nil
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        guard n > 1 else { return 0 }
        let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (a, b) in zip(x, y) {
            sxy += (a - mx) * (b - my)
            sxx += (a - mx) * (a - mx)
            syy += (b - my) * (b - my)
        }
        let d = (sxx * syy).squareRoot()
        return d > 1e-15 ? sxy / d : 0
    }
}
