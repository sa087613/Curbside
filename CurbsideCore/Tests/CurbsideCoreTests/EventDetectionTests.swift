import CurbsideCore
import Foundation
import Testing

@Suite("Event detection")
struct EventDetectionTests {

    // MARK: Real events

    @Test func hardBrakeIsDetectedAndConfirmedByGPS() {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.changeSpeed(to: 40, g: 0.12)
        drive.cruise(5)
        drive.changeSpeed(to: 10, g: 0.45)
        drive.cruise(5)

        let result = drive.detect()
        #expect(result.events.count == 1)
        let e = try! #require(result.events.first)
        #expect(e.kind == .hardBrake)
        #expect(e.severity == .hard)
        #expect(e.usedCalibratedAxis)
        #expect(abs(e.peakG - 0.45) < 0.05)
        #expect(abs(Units.mph(fromMps: e.speedBefore) - 40) < 3)
        #expect(e.latitude != nil)
    }

    @Test func hardBrakeIsDetectedBeforeAxisIsCalibrated() {
        var drive = SyntheticDrive(startMph: 40)
        drive.cruise(6)
        drive.changeSpeed(to: 10, g: 0.45)
        drive.cruise(5)

        let result = drive.detect()
        #expect(result.events.map(\.kind) == [.hardBrake])
        #expect(result.events.first?.usedCalibratedAxis == false)
    }

    @Test(arguments: [(0.32, EventSeverity.moderate), (0.42, .hard), (0.58, .severe)])
    func brakeSeverityTiers(g: Double, expected: EventSeverity) {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.changeSpeed(to: 45, g: 0.12)
        drive.cruise(4)
        drive.changeSpeed(to: 10, g: g)
        drive.cruise(5)

        let result = drive.detect()
        #expect(result.events.map(\.kind) == [.hardBrake])
        #expect(result.events.first?.severity == expected)
    }

    @Test func harshAccelerationFromStop() {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.changeSpeed(to: 0, g: 0.12)
        drive.cruise(4)
        drive.changeSpeed(to: 30, g: 0.38)
        drive.cruise(5)

        let result = drive.detect()
        #expect(result.events.map(\.kind) == [.harshAcceleration])
        #expect(result.events.first?.severity == .hard)
    }

    @Test func sharpTurnIsDetected() {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.changeSpeed(to: 25, g: 0.12)
        drive.cruise(3)
        drive.turn(seconds: 3, lateralG: 0.5)
        drive.cruise(5)

        let result = drive.detect()
        #expect(result.events.map(\.kind) == [.sharpTurn])
        #expect(result.events.first?.severity == .hard)
    }

    // MARK: Normal driving

    @Test func normalDrivingHasNoEvents() {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.turn(seconds: 4, lateralG: 0.2)
        drive.cruise(3)
        drive.changeSpeed(to: 15, g: 0.2)
        drive.turn(seconds: 3, lateralG: 0.25)
        drive.changeSpeed(to: 40, g: 0.18)
        drive.cruise(5)
        drive.changeSpeed(to: 0, g: 0.2)
        drive.cruise(3)

        let result = drive.detect()
        #expect(result.events.isEmpty)
        #expect(result.calibratedFraction > 0.5)
    }

    // MARK: False positives

    @Test func droppedPhoneIsNotAnEvent() {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.cruise(10)
        let t = drive.elapsed - 6
        drive.disturbances = [
            .init(start: t, duration: 0.15, accelG: Vector3(-1.2, -1.8, 2.2)),
            .init(start: t, duration: 0.6, rotation: Vector3(5, 3, 1)),
        ]

        let result = drive.detect()
        #expect(result.events.isEmpty)
    }

    @Test func phoneSlidingWithoutSlowingDownIsRejected() {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.cruise(10)
        // Motion says -0.45 g for over a second, but GPS speed never changes.
        drive.disturbances = [.init(start: drive.elapsed - 6, duration: 1.2, accelG: Vector3(-0.45, 0, 0))]

        let result = drive.detect()
        #expect(result.events.isEmpty)
        #expect(result.rejected.contains {
            if case .gpsSpeedNotConfirmed = $0.reason { return $0.kind == .hardBrake }
            return false
        })
    }

    @Test func potholeIsNotAnEvent() {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.cruise(8)
        let t = drive.elapsed - 4
        drive.disturbances = [
            .init(start: t, duration: 0.1, accelG: Vector3(0, 0, 1.5), rotation: Vector3(0, 1.0, 0)),
            .init(start: t + 0.1, duration: 0.1, accelG: Vector3(0, 0, -1.0), rotation: Vector3(0, -1.0, 0)),
        ]

        #expect(drive.detect().events.isEmpty)
    }

    @Test func brakeWithoutGPSIsNotCounted() {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.cruise(5)
        let start = drive.elapsed
        drive.changeSpeed(to: 10, g: 0.45)
        drive.cruise(8)
        drive.gpsDropouts = [(start - 2)...(start + 8)]

        let result = drive.detect()
        #expect(result.events.isEmpty)
        #expect(result.rejected.contains { $0.kind == .hardBrake && $0.reason == .noGPS })
    }

    /// Drives, re-mounts the phone, relearns, then brakes hard.
    private func remountScenario(second: Matrix3, transitionRotation: Vector3) -> DetectionResult {
        var drive = SyntheticDrive()
        drive.warmUp()
        let remountAt = drive.elapsed
        drive.cruise(6)
        drive.changeSpeed(to: 20, g: 0.12)
        drive.changeSpeed(to: 38, g: 0.12)
        drive.changeSpeed(to: 22, g: 0.12)
        drive.changeSpeed(to: 40, g: 0.12)
        drive.cruise(4)
        drive.changeSpeed(to: 10, g: 0.45)
        drive.cruise(5)
        drive.phone = { t in t < remountAt + 0.5 ? SyntheticDrive.oddMount : second }
        drive.disturbances = [.init(start: remountAt, duration: 1, rotation: transitionRotation)]
        return drive.detect()
    }

    @Test func remountedPhoneRelearnsAxis() {
        let second = SyntheticDrive.oddMount * Matrix3.rotation(yaw: 0.3, pitch: 0, roll: 1.0)
        let down1 = SyntheticDrive.oddMount * Vector3(0, 0, -1)
        #expect(down1.angleDegrees(to: second * Vector3(0, 0, -1)) > 30)

        let result = remountScenario(second: second, transitionRotation: Vector3(2, 1, 0))
        #expect(result.notes.contains { $0.message.contains("re-learning") })
        #expect(result.events.map(\.kind) == [.hardBrake])
        #expect(result.events.first?.severity == .hard)
    }

    @Test func phoneSpunFlatInMountRelearnsAxis() {
        // Same tilt, rotated 90° about vertical; slow enough that it isn't "handling".
        let second = SyntheticDrive.oddMount * Matrix3.rotation(yaw: -.pi / 2, pitch: 0, roll: 0)
        let result = remountScenario(second: second, transitionRotation: Vector3(0, 0, .pi / 2))
        #expect(result.notes.contains { $0.message.contains("rotated in mount") })
        #expect(result.events.map(\.kind) == [.hardBrake])
        #expect(result.events.first?.severity == .hard)
    }

    // MARK: Determinism

    @Test func liveArrivalOrderMatchesReplay() throws {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.changeSpeed(to: 40, g: 0.12)
        drive.turn(seconds: 2.5, lateralG: 0.5)
        drive.cruise(3)
        drive.changeSpeed(to: 10, g: 0.45)
        drive.changeSpeed(to: 30, g: 0.36)
        drive.cruise(5)
        let (locations, motion) = drive.generate()

        // Live: GPS fixes arrive ~0.7 s after their timestamp, interleaved with motion.
        let live = EventDetector()
        var li = 0
        for m in motion {
            while li < locations.count, locations[li].t + 0.7 <= m.t {
                live.ingest(locations[li])
                li += 1
            }
            live.ingest(m)
        }
        while li < locations.count { live.ingest(locations[li]); li += 1 }
        let liveResult = live.finish()

        // Replay: through an encoded/decoded export.
        let log = DriveLog(driveID: UUID(), startDate: Date(), endDate: Date(), deviceModel: "test", appVersion: "test",
                           config: .default, liveEvents: liveResult.events, locations: locations, motion: motion)
        let replayResult = try DriveLog.decode(log.encoded()).detect()

        #expect(liveResult.events.count == 3)
        #expect(liveResult.events.map(\.kind) == replayResult.events.map(\.kind))
        #expect(liveResult.events.map(\.startTime) == replayResult.events.map(\.startTime))
        #expect(liveResult.events.map(\.peakG) == replayResult.events.map(\.peakG))
    }
}
