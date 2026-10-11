import CoreMotion
import CurbsideCore
import Foundation

/// Streams CMDeviceMotion (gravity-free acceleration, gravity, rotation rate) off the main thread.
final class MotionService {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "Curbside.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// Returns false when the device has no motion sensors (e.g. Simulator).
    /// `referenceUptime` is `ProcessInfo.systemUptime` at drive start; CMLogItem timestamps use the same clock.
    @discardableResult
    func start(referenceUptime: TimeInterval, rateHz: Double, onSample: @escaping @Sendable (MotionSample) -> Void) -> Bool {
        guard manager.isDeviceMotionAvailable else { return false }
        manager.deviceMotionUpdateInterval = 1 / rateHz
        manager.startDeviceMotionUpdates(to: queue) { motion, _ in
            guard let motion else { return }
            let a = motion.userAcceleration, g = motion.gravity, r = motion.rotationRate
            onSample(MotionSample(
                t: motion.timestamp - referenceUptime,
                userAcceleration: Vector3(a.x, a.y, a.z),
                gravity: Vector3(g.x, g.y, g.z),
                rotationRate: Vector3(r.x, r.y, r.z)
            ).quantized())
        }
        return true
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
