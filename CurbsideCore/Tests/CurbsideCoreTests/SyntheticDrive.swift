import CurbsideCore
import Foundation

/// Builds physically consistent fake drives: motion samples in a (rotated) phone frame plus
/// 1 Hz GPS fixes. Car frame: x forward, y left, z up.
struct SyntheticDrive {
    struct Phase {
        var duration: Double
        var accelG: Double = 0
        var yawRate: Double = 0
    }

    /// Extra motion that GPS doesn't see (phone drops, potholes, sliding phone).
    struct Disturbance {
        var start: Double
        var duration: Double
        /// Added acceleration in the car frame, g.
        var accelG: Vector3 = .zero
        /// Added rotation rate in the car frame, rad/s.
        var rotation: Vector3 = .zero
    }

    var initialSpeedMph: Double
    private(set) var phases: [Phase] = []
    private(set) var speedMph: Double

    var rate = 50.0
    var gpsInterval = 1.0
    var noiseG = 0.02
    var seed: UInt64 = 42
    /// Car → device rotation as a function of time.
    var phone: @Sendable (Double) -> Matrix3 = { _ in SyntheticDrive.oddMount }
    var disturbances: [Disturbance] = []
    var gpsDropouts: [ClosedRange<Double>] = []

    /// A deliberately awkward mount: rotated, tilted back, slightly rolled.
    static let oddMount = Matrix3.rotation(yaw: 1.1, pitch: -1.2, roll: 0.3)

    init(startMph: Double = 0) {
        initialSpeedMph = startMph
        speedMph = startMph
    }

    var elapsed: Double { phases.reduce(0) { $0 + $1.duration } }

    mutating func cruise(_ seconds: Double) {
        phases.append(Phase(duration: seconds))
    }

    /// Constant acceleration (or braking) to a new speed.
    mutating func changeSpeed(to mph: Double, g: Double) {
        let dv = Units.mps(fromMph: mph - speedMph)
        guard dv != 0 else { return }
        phases.append(Phase(duration: abs(dv) / (g * Units.g), accelG: dv > 0 ? g : -g))
        speedMph = mph
    }

    /// Constant-speed turn with the given lateral acceleration (left turn).
    mutating func turn(seconds: Double, lateralG: Double) {
        let v = Units.mps(fromMph: speedMph)
        phases.append(Phase(duration: seconds, yawRate: lateralG * Units.g / v))
    }

    /// Gentle speed changes so the detector can learn the forward axis. Ends cruising at 35 mph.
    mutating func warmUp() {
        cruise(3)
        changeSpeed(to: 30, g: 0.15)
        cruise(5)
        changeSpeed(to: 20, g: 0.12)
        cruise(4)
        changeSpeed(to: 35, g: 0.12)
        cruise(5)
    }

    func generate() -> (locations: [LocationSample], motion: [MotionSample]) {
        var rng = SeededRNG(seed: seed)
        var motion: [MotionSample] = []
        var locations: [LocationSample] = []

        let dt = 1 / rate
        let total = elapsed
        var v = Units.mps(fromMph: initialSpeedMph)
        var course = 90.0 // heading east, degrees clockwise from north
        var north = 0.0, east = 0.0
        let lat0 = 33.7756, lon0 = -84.3963
        var nextFix = 0.0

        var phaseIndex = 0
        var phaseStart = 0.0
        var step = 0
        while true {
            let t = Double(step) * dt
            if t > total + 1e-9 { break }
            while phaseIndex < phases.count - 1, t >= phaseStart + phases[phaseIndex].duration {
                phaseStart += phases[phaseIndex].duration
                phaseIndex += 1
            }
            let phase = phases[phaseIndex]

            // GPS fix
            if t >= nextFix - 1e-9 {
                nextFix += gpsInterval
                if !gpsDropouts.contains(where: { $0.contains(t) }) {
                    locations.append(LocationSample(
                        t: t,
                        latitude: lat0 + north / 111_320,
                        longitude: lon0 + east / (111_320 * cos(lat0 * .pi / 180)),
                        horizontalAccuracy: 5,
                        speed: max(0, v + rng.gaussian() * 0.05),
                        speedAccuracy: 0.5,
                        course: v > 1 ? course : -1,
                        courseAccuracy: v > 1 ? 5 : -1
                    ))
                }
            }

            // Motion
            let lateral = v * phase.yawRate / Units.g
            var accel = Vector3(v > 0 || phase.accelG > 0 ? phase.accelG : 0, lateral, 0)
            var rotation = Vector3(0, 0, phase.yawRate)
            for d in disturbances where t >= d.start && t < d.start + d.duration {
                accel += d.accelG
                rotation += d.rotation
            }
            accel += Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * noiseG
            rotation += Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * 0.01

            let r = phone(t)
            motion.append(MotionSample(
                t: t,
                userAcceleration: r * accel,
                gravity: r * Vector3(0, 0, -1),
                rotationRate: r * rotation
            ).quantized())

            // Integrate
            v = max(0, v + phase.accelG * Units.g * dt)
            course -= phase.yawRate * dt * 180 / .pi
            course = (course.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            north += v * cos(course * .pi / 180) * dt
            east += v * sin(course * .pi / 180) * dt
            step += 1
        }
        return (locations, motion)
    }

    func detect(config: DetectionConfig = .default) -> DetectionResult {
        let (locations, motion) = generate()
        return EventDetector.run(locations: locations, motion: motion, config: config)
    }
}

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func gaussian() -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
