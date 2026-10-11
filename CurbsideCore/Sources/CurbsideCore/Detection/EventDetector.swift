import Foundation

/// One processed motion sample, exposed for debugging/plotting (`replay --csv`).
public struct SignalFrame: Sendable {
    public var t: Double
    /// Interpolated GPS speed, m/s.
    public var speed: Double?
    /// Smoothed longitudinal acceleration in g (+ = speeding up, − = braking).
    public var longitudinalG: Double
    /// Smoothed lateral acceleration magnitude in g.
    public var lateralG: Double
    /// Speed × yaw rate, in g: lateral acceleration as seen by the gyro.
    public var gyroLateralG: Double
    public var axisCalibrated: Bool
    public var handling: Bool
}

/// Streaming hard-brake / harsh-acceleration / sharp-turn detector.
///
/// Feed samples in time order with `ingest`, then call `finish()`. The live app and the
/// replay harness both use this exact class, so a replayed export reproduces the app.
///
/// Pipeline per motion sample:
/// 1. Remove the vertical component using the gravity vector → horizontal acceleration
///    in the phone's frame (tilt no longer matters).
/// 2. Project onto the learned forward axis (`AxisEstimator`) → longitudinal / lateral g.
///    Before the axis is learned, fall back to |horizontal| signed by GPS acceleration.
/// 3. Hysteresis state machines open candidates; each candidate is then checked against
///    GPS (did the car really slow down / turn?) and phone-handling windows.
public final class EventDetector {
    public let config: DetectionConfig
    public var signalTap: ((SignalFrame) -> Void)?

    private var track: GPSTrack
    private var axis: AxisEstimator

    private var pending: [MotionSample] = []
    private var pendingHead = 0
    private var latestMotionT = -Double.infinity
    private var lastProcessedT: Double?

    private var smoother: Smoother
    private var filteredGravity: Vector3?

    private var suppressions: [(start: Double, end: Double)] = []
    private var wasHandling = false
    private var bucket = Bucket()

    private var brake: Tracker
    private var accel: Tracker
    private var turn: Tracker
    private var closed: [Candidate] = []

    private var events: [DrivingEvent] = []
    private var rejected: [RejectedCandidate] = []
    private var notes: [DetectorNote] = []
    private var processed = 0
    private var processedCalibrated = 0
    private var wasCalibrated = false

    public init(config: DetectionConfig = .default) {
        self.config = config
        track = GPSTrack(config: config)
        axis = AxisEstimator(config: config.axis)
        let window = max(1, Int((config.smoothingWindowSeconds * config.motionSampleRateHz).rounded()))
        smoother = Smoother(window: window)
        brake = Tracker(kind: .hardBrake, enterG: config.hardBrake.moderateG,
                        exitG: config.hardBrake.moderateG * config.exitRatio, release: config.hardBrake.releaseSeconds)
        accel = Tracker(kind: .harshAcceleration, enterG: config.harshAcceleration.moderateG,
                        exitG: config.harshAcceleration.moderateG * config.exitRatio, release: config.harshAcceleration.releaseSeconds)
        turn = Tracker(kind: .sharpTurn, enterG: config.sharpTurn.moderateG,
                       exitG: config.sharpTurn.moderateG * config.exitRatio, release: config.sharpTurn.releaseSeconds)
    }

    // MARK: - Input

    public func ingest(_ sample: MotionSample) {
        guard sample.t > latestMotionT else { return }
        latestMotionT = sample.t
        pending.append(sample)
        processReady(force: false)
    }

    public func ingest(_ sample: LocationSample) {
        track.append(sample)
        processReady(force: false)
    }

    /// Processes everything left and returns the final result.
    public func finish() -> DetectionResult {
        processReady(force: true)
        closeBucket()
        closed += [brake.flush(), accel.flush(), turn.flush()].compactMap { $0 }
        evaluateClosed(upTo: .infinity)
        events.sort { $0.startTime < $1.startTime }
        rejected.sort { $0.startTime < $1.startTime }
        return DetectionResult(
            events: events,
            rejected: rejected,
            notes: notes,
            calibratedFraction: processed > 0 ? Double(processedCalibrated) / Double(processed) : 0,
            processedMotionSamples: processed
        )
    }

    /// Runs a whole recorded drive through a fresh detector.
    public static func run(locations: [LocationSample], motion: [MotionSample],
                           config: DetectionConfig = .default,
                           signalTap: ((SignalFrame) -> Void)? = nil) -> DetectionResult {
        let detector = EventDetector(config: config)
        detector.signalTap = signalTap
        var li = 0
        for m in motion {
            while li < locations.count, locations[li].t <= m.t {
                detector.ingest(locations[li])
                li += 1
            }
            detector.ingest(m)
        }
        while li < locations.count {
            detector.ingest(locations[li])
            li += 1
        }
        return detector.finish()
    }

    // MARK: - Processing

    private func processReady(force: Bool) {
        while pendingHead < pending.count {
            let s = pending[pendingHead]
            if !force {
                let gpsReady = track.latestTime.map { s.t <= $0 - config.processingLatencySeconds } ?? false
                let stalled = latestMotionT - s.t >= config.maxGpsWaitSeconds
                guard gpsReady || stalled else { break }
            }
            process(s)
            pendingHead += 1
        }
        if pendingHead > 2048 {
            pending.removeFirst(pendingHead)
            pendingHead = 0
        }
    }

    private func process(_ s: MotionSample) {
        let nominalDt = 1 / config.motionSampleRateHz
        let dt = lastProcessedT.map { min(max(s.t - $0, 0), 5 * nominalDt) } ?? nominalDt
        lastProcessedT = s.t

        let down = s.gravity.normalized
        guard down != .zero else { return }
        let horizontal = s.userAcceleration.rejecting(down)
        let yawRate = s.rotationRate.dot(down)
        let tiltRate = s.rotationRate.rejecting(down).length
        let (smoothH, smoothYaw) = smoother.add(horizontal, yawRate)

        // Phone handling: fast rotation about a horizontal axis.
        let handling = tiltRate >= config.handlingRotationRateRadPerSec
        if handling { addSuppression(at: s.t) }
        // Picked up / moved: wherever it ends up, the old axis can't be trusted.
        if handling, !wasHandling, axis.intervalCount > 0 {
            resetAxis(at: s.t, String(format: "Phone moved (%.1f rad/s); re-learning forward axis", tiltRate))
        }
        wasHandling = handling

        // Phone re-oriented in the car: forget the learned axis.
        let alpha = min(1, dt / config.axis.gravityFilterSeconds)
        filteredGravity = filteredGravity.map { ($0 * (1 - alpha) + down * alpha) } ?? down
        if let ref = axis.referenceGravity, let fg = filteredGravity,
           fg.angleDegrees(to: ref) > config.axis.gravityShiftResetDegrees {
            resetAxis(at: s.t, String(format: "Phone orientation changed %.0f°; re-learning forward axis", fg.angleDegrees(to: ref)))
        }

        accumulateBucket(s, horizontal: horizontal, yawRate: yawRate, dt: dt, handling: handling)
        noteCalibrationChange(at: s.t)

        let speed = track.speed(at: s.t)
        let gyroLateral = (speed ?? 0) * abs(smoothYaw) / Units.g

        let longitudinal: Double
        let lateral: Double
        let calibrated: Bool
        if let f = axis.forward {
            let fwd = f.rejecting(down).normalized
            let left = down.cross(fwd)
            longitudinal = smoothH.dot(fwd)
            lateral = abs(smoothH.dot(left))
            calibrated = true
        } else {
            // Fallback: the part of horizontal acceleration not explained by turning,
            // signed by whether GPS says we're speeding up or slowing down.
            let magnitude = max(0, smoothH.lengthSquared - gyroLateral * gyroLateral).squareRoot()
            if let a = track.acceleration(at: s.t), abs(a) / Units.g >= 0.02 {
                longitudinal = a > 0 ? magnitude : -magnitude
            } else {
                longitudinal = 0
            }
            lateral = gyroLateral
            calibrated = false
        }

        processed += 1
        if calibrated { processedCalibrated += 1 }

        signalTap?(SignalFrame(t: s.t, speed: speed, longitudinalG: longitudinal, lateralG: lateral,
                               gyroLateralG: gyroLateral, axisCalibrated: calibrated, handling: handling))

        if let c = brake.update(t: s.t, dt: dt, signal: -longitudinal, gyro: gyroLateral, calibrated: calibrated) { closed.append(c) }
        if let c = accel.update(t: s.t, dt: dt, signal: longitudinal, gyro: gyroLateral, calibrated: calibrated) { closed.append(c) }
        if let c = turn.update(t: s.t, dt: dt, signal: lateral, gyro: gyroLateral, calibrated: calibrated) { closed.append(c) }

        // Wait until any handling that could overlap a closed candidate has been seen.
        evaluateClosed(upTo: s.t - config.handlingSuppressBeforeSeconds)
    }

    private func resetAxis(at t: Double, _ message: String) {
        axis.reset()
        bucket = Bucket()
        notes.append(DetectorNote(t: t, message: message))
    }

    private func noteCalibrationChange(at t: Double) {
        guard axis.isCalibrated != wasCalibrated else { return }
        wasCalibrated = axis.isCalibrated
        notes.append(DetectorNote(t: t, message: wasCalibrated
            ? String(format: "Forward axis calibrated (fit correlation %.2f, %d intervals)", axis.correlation, axis.intervalCount)
            : String(format: "Forward axis lost (fit correlation %.2f)", axis.correlation)))
    }

    private func addSuppression(at t: Double) {
        let start = t - config.handlingSuppressBeforeSeconds
        let end = t + config.handlingSuppressAfterSeconds
        if let last = suppressions.last, start <= last.end {
            suppressions[suppressions.count - 1].end = max(last.end, end)
        } else {
            suppressions.append((start, end))
        }
    }

    private func overlapsSuppression(_ start: Double, _ end: Double) -> Bool {
        suppressions.contains { $0.start <= end && start <= $0.end }
    }

    // MARK: - Axis calibration buckets (one per GPS interval)

    private struct Bucket {
        var start = -Double.infinity
        var end = -Double.infinity
        var startSpeed = 0.0
        var endSpeed = 0.0
        var startCourse: Double?
        var endCourse: Double?
        /// Integrated gyro yaw, degrees clockwise (same sense as GPS course).
        var gyroYawDegrees = 0.0
        var sumHorizontal = Vector3.zero
        var sumGravity = Vector3.zero
        var count = 0
        var hadHandling = false
    }

    private func accumulateBucket(_ s: MotionSample, horizontal: Vector3, yawRate: Double, dt: Double, handling: Bool) {
        guard let (a, b) = track.speedBracket(at: s.t - config.gpsSpeedLagSeconds) else {
            closeBucket()
            return
        }
        if b.t != bucket.end {
            closeBucket()
            func course(_ f: LocationSample) -> Double? {
                f.hasValidCourse && f.courseAccuracy >= 0 && f.courseAccuracy <= config.axis.maxCourseAccuracyDegrees ? f.course : nil
            }
            bucket = Bucket(start: a.t, end: b.t, startSpeed: a.speed, endSpeed: b.speed,
                            startCourse: course(a), endCourse: course(b))
        }
        // Rotation about "down" is clockwise seen from above, matching GPS course.
        bucket.gyroYawDegrees += yawRate * dt * 180 / .pi
        bucket.sumHorizontal += horizontal
        bucket.sumGravity += s.gravity
        bucket.count += 1
        bucket.hadHandling = bucket.hadHandling || handling
    }

    private func closeBucket() {
        defer { bucket = Bucket() }
        let duration = bucket.end - bucket.start
        guard bucket.count > 0, duration > 0, duration <= config.axis.maxIntervalSeconds,
              !bucket.hadHandling,
              Double(bucket.count) >= 0.5 * duration * config.motionSampleRateHz else { return }
        let minSpeed = Units.mps(fromMph: config.axis.minSpeedMph)
        guard bucket.startSpeed >= minSpeed, bucket.endSpeed >= minSpeed else { return }

        if let c0 = bucket.startCourse, let c1 = bucket.endCourse, axis.intervalCount > 0 {
            var gpsTurn = c1 - c0
            if gpsTurn > 180 { gpsTurn -= 360 }
            if gpsTurn < -180 { gpsTurn += 360 }
            let mismatch = abs(gpsTurn - bucket.gyroYawDegrees)
            if mismatch > config.axis.yawMismatchResetDegrees {
                resetAxis(at: bucket.end, String(format: "Gyro turned %.0f° but GPS heading turned %.0f°; phone rotated in mount, re-learning forward axis",
                                                 bucket.gyroYawDegrees, gpsTurn))
                return
            }
        }

        let n = Double(bucket.count)
        axis.add(.init(horizontal: bucket.sumHorizontal / n,
                       gravity: (bucket.sumGravity / n).normalized,
                       gpsAccelerationG: (bucket.endSpeed - bucket.startSpeed) / duration / Units.g))
    }

    // MARK: - Candidate evaluation

    private func evaluateClosed(upTo time: Double) {
        guard !closed.isEmpty else { return }
        var remaining: [Candidate] = []
        for c in closed {
            if c.lastAbove <= time { evaluate(c) } else { remaining.append(c) }
        }
        closed = remaining
    }

    private func evaluate(_ c: Candidate) {
        func reject(_ reason: RejectionReason) {
            rejected.append(RejectedCandidate(kind: c.kind, startTime: c.start, endTime: c.lastAbove, peakG: c.peak, reason: reason))
        }

        let duration = c.lastAbove - c.start
        let minDuration = c.kind == .sharpTurn ? config.sharpTurn.minDurationSeconds
            : c.kind == .hardBrake ? config.hardBrake.minDurationSeconds : config.harshAcceleration.minDurationSeconds
        guard duration >= minDuration else { return reject(.tooShort(seconds: duration)) }
        guard !overlapsSuppression(c.start, c.lastAbove) else { return reject(.phoneMovement) }

        let severity: EventSeverity
        let before: Double
        let after: Double

        switch c.kind {
        case .hardBrake, .harshAcceleration:
            let cfg = c.kind == .hardBrake ? config.hardBrake : config.harshAcceleration
            guard let v0 = track.speed(at: c.start - cfg.gpsMarginBeforeSeconds),
                  let v1 = track.speed(at: c.lastAbove + cfg.gpsMarginAfterSeconds) else { return reject(.noGPS) }
            guard Units.mph(fromMps: v0) >= cfg.minStartSpeedMph else { return reject(.tooSlow(mph: Units.mph(fromMps: v0))) }
            let change = c.kind == .hardBrake ? v0 - v1 : v1 - v0
            let expected = c.integral * Units.g
            let required = max(Units.mps(fromMph: cfg.minSpeedChangeMph), cfg.minSpeedChangeRatio * expected)
            guard change >= required else {
                return reject(.gpsSpeedNotConfirmed(changeMph: Units.mph(fromMps: change), requiredMph: Units.mph(fromMps: required)))
            }
            severity = cfg.severity(forPeak: c.peak)
            (before, after) = (v0, v1)

        case .sharpTurn:
            let cfg = config.sharpTurn
            guard let v = track.speed(at: c.peakTime) else { return reject(.noGPS) }
            guard Units.mph(fromMps: v) >= cfg.minSpeedMph else { return reject(.tooSlow(mph: Units.mph(fromMps: v))) }
            guard c.gyroPeak >= cfg.gyroConfirmRatio * cfg.moderateG else { return reject(.gyroNotConfirmed(gyroG: c.gyroPeak)) }
            if let course = track.courseChange(from: c.start, to: c.lastAbove), course < cfg.minCourseChangeDegrees {
                return reject(.headingNotConfirmed(degrees: course))
            }
            severity = cfg.severity(forPeak: c.peak)
            before = track.speed(at: c.start) ?? v
            after = track.speed(at: c.lastAbove) ?? v
        }

        let coordinate = track.coordinate(at: c.peakTime)
        events.append(DrivingEvent(
            kind: c.kind, severity: severity, startTime: c.start, endTime: c.lastAbove, peakTime: c.peakTime,
            peakG: c.peak, speedBefore: before, speedAfter: after,
            latitude: coordinate?.latitude, longitude: coordinate?.longitude,
            usedCalibratedAxis: c.calibratedSamples * 2 >= c.samples
        ))
    }
}

// MARK: - Helpers

private struct Candidate {
    var kind: DrivingEventKind
    var start: Double
    var lastAbove: Double
    var peak: Double
    var peakTime: Double
    /// ∫ signal dt over the candidate, in g·s (≈ speed change / g).
    var integral: Double
    var gyroPeak: Double
    var samples: Int
    var calibratedSamples: Int
}

/// Hysteresis state machine: opens above `enterG`, stays open while above `exitG`,
/// closes after the signal has been below `exitG` for `release` seconds.
private struct Tracker {
    let kind: DrivingEventKind
    let enterG: Double
    let exitG: Double
    let release: Double
    var active: Candidate?

    mutating func update(t: Double, dt: Double, signal: Double, gyro: Double, calibrated: Bool) -> Candidate? {
        if var c = active {
            if signal >= exitG {
                c.lastAbove = t
                c.integral += signal * dt
                c.samples += 1
                if calibrated { c.calibratedSamples += 1 }
                if signal > c.peak { c.peak = signal; c.peakTime = t }
                c.gyroPeak = max(c.gyroPeak, gyro)
                active = c
            } else if t - c.lastAbove >= release {
                active = nil
                return c
            }
            return nil
        }
        if signal >= enterG {
            active = Candidate(kind: kind, start: t, lastAbove: t, peak: signal, peakTime: t, integral: signal * dt,
                               gyroPeak: gyro, samples: 1, calibratedSamples: calibrated ? 1 : 0)
        }
        return nil
    }

    mutating func flush() -> Candidate? {
        defer { active = nil }
        return active
    }
}

/// Trailing moving average of a vector and a scalar.
private struct Smoother {
    let window: Int
    private var vectors: [Vector3] = []
    private var scalars: [Double] = []
    private var index = 0
    private var sumV = Vector3.zero
    private var sumS = 0.0

    init(window: Int) {
        self.window = window
        vectors.reserveCapacity(window)
        scalars.reserveCapacity(window)
    }

    mutating func add(_ v: Vector3, _ s: Double) -> (Vector3, Double) {
        if vectors.count < window {
            vectors.append(v)
            scalars.append(s)
        } else {
            sumV -= vectors[index]
            sumS -= scalars[index]
            vectors[index] = v
            scalars[index] = s
            index = (index + 1) % window
        }
        sumV += v
        sumS += s
        let n = Double(vectors.count)
        return (sumV / n, sumS / n)
    }
}
