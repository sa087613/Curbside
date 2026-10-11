import CoreLocation
import CurbsideCore
import Foundation
import Observation
import SwiftData

private enum SensorInput: Sendable {
    case motion(MotionSample)
    case location(LocationSample)
}

private struct Capture: Sendable {
    var locations: [LocationSample]
    var motion: [MotionSample]
    var result: DetectionResult
}

/// Owns a drive from Start to Stop: sensors → EventDetector (off the main thread) → saved Drive.
@MainActor
@Observable
final class DriveRecorder {
    enum Phase: Equatable {
        case idle, starting, recording, saving
    }

    private(set) var phase: Phase = .idle
    /// Latest GPS speed, m/s. Nil until the first valid fix.
    private(set) var speedMps: Double?

    /// The drive just saved, so the UI can open its summary.
    var lastSavedDriveID: UUID?

    /// True while the recording screen should be shown.
    var isRecording: Bool { phase == .recording || phase == .saving }

    @ObservationIgnored private let config: DetectionConfig
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let prompts: PromptGate
    @ObservationIgnored private let location = LocationService()
    @ObservationIgnored private let motion = MotionService()
    @ObservationIgnored private var continuation: AsyncStream<SensorInput>.Continuation?
    @ObservationIgnored private var processing: Task<Capture, Never>?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var startDate: Date?

    init(container: ModelContainer, prompts: PromptGate, config: DetectionConfig = .default) {
        self.container = container
        self.prompts = prompts
        self.config = config
    }

    func start() async {
        guard phase == .idle else { return }
        phase = .starting

        let status = await location.requestAuthorizationIfNeeded()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            phase = .idle
            prompts.present(.locationDenied)
            return
        }

        let start = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let (stream, continuation) = AsyncStream.makeStream(of: SensorInput.self, bufferingPolicy: .unbounded)
        let config = self.config

        // All detection runs here, in arrival order, off the main thread.
        processing = Task.detached(priority: .userInitiated) {
            let detector = EventDetector(config: config)
            var locations: [LocationSample] = []
            var motion: [MotionSample] = []
            motion.reserveCapacity(Int(config.motionSampleRateHz) * 60 * 30)
            for await input in stream {
                switch input {
                case .motion(let m):
                    motion.append(m)
                    detector.ingest(m)
                case .location(let l):
                    locations.append(l)
                    detector.ingest(l)
                }
            }
            return Capture(locations: locations, motion: motion, result: detector.finish())
        }

        self.continuation = continuation
        startDate = start
        speedMps = nil

        // Keeps location (and with it, our process and Core Motion) running in the background.
        backgroundSession = CLBackgroundActivitySession()
        location.start(referenceDate: start) { [weak self] sample in
            continuation.yield(.location(sample))
            self?.speedMps = sample.hasValidSpeed ? sample.speed : nil
        }
        motion.start(referenceUptime: uptime, rateHz: config.motionSampleRateHz) { sample in
            continuation.yield(.motion(sample))
        }

        prompts.setDriving(true)
        phase = .recording
    }

    func stop() async {
        guard phase == .recording, let startDate, let processing else { return }
        phase = .saving

        location.stop()
        motion.stop()
        backgroundSession?.invalidate()
        backgroundSession = nil
        continuation?.finish()
        continuation = nil

        let capture = await processing.value
        self.processing = nil
        self.startDate = nil

        do {
            try await save(capture, start: startDate, end: Date())
        } catch {
            prompts.present(.saveFailed(error))
        }

        phase = .idle
        prompts.setDriving(false)
    }

    private func save(_ capture: Capture, start: Date, end: Date) async throws {
        let id = UUID()
        let log = DriveLog(
            driveID: id, startDate: start, endDate: end,
            deviceModel: DeviceInfo.modelIdentifier, appVersion: DeviceInfo.appVersion,
            config: config, liveEvents: capture.result.events,
            locations: capture.locations, motion: capture.motion
        )
        let fileName = try await DriveFiles.write(log)
        let metrics = DriveMetrics.compute(locations: capture.locations, duration: end.timeIntervalSince(start))

        let context = container.mainContext
        context.insert(Drive(id: id, startDate: start, endDate: end, metrics: metrics, result: capture.result,
                             route: RoutePoint.route(from: capture.locations),
                             motionSampleCount: capture.motion.count, locationCount: capture.locations.count,
                             logFileName: fileName))
        try context.save()
        lastSavedDriveID = id
    }
}
