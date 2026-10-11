import CurbsideCore
import Foundation
import Testing

@Suite("Forward axis")
struct AxisEstimatorTests {
    @Test func recoversForwardDirectionForAnyMount() {
        for mount in [Matrix3.identity, SyntheticDrive.oddMount, .rotation(yaw: -2.5, pitch: 0.4, roll: -1.3)] {
            var rng = SeededRNG(seed: 7)
            var estimator = AxisEstimator(config: AxisConfig())
            let forward = mount * Vector3(1, 0, 0)
            let left = mount * Vector3(0, 1, 0)
            let gravity = mount * Vector3(0, 0, -1)
            for _ in 0..<60 {
                let a = rng.gaussian() * 0.1
                let lateral = rng.gaussian() * 0.15
                let noise = Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * 0.01
                let h = (forward * a + left * lateral + noise).rejecting(gravity)
                estimator.add(.init(horizontal: h, gravity: gravity, gpsAccelerationG: a + rng.gaussian() * 0.01))
            }
            let f = try! #require(estimator.forward)
            #expect(f.angleDegrees(to: forward) < 5)
        }
    }

    @Test func staysUncalibratedWithoutSpeedChanges() {
        var estimator = AxisEstimator(config: AxisConfig())
        for i in 0..<100 {
            estimator.add(.init(horizontal: Vector3(0.01 * sin(Double(i)), 0, 0), gravity: Vector3(0, 0, -1), gpsAccelerationG: 0.001))
        }
        #expect(!estimator.isCalibrated)
    }

    @Test func rejectsFitWhenMotionDoesNotMatchGPS() {
        var rng = SeededRNG(seed: 3)
        var estimator = AxisEstimator(config: AxisConfig())
        for _ in 0..<60 {
            let h = Vector3(rng.gaussian(), rng.gaussian(), 0) * 0.1
            estimator.add(.init(horizontal: h, gravity: Vector3(0, 0, -1), gpsAccelerationG: rng.gaussian() * 0.1))
        }
        #expect(!estimator.isCalibrated)
    }
}

@Suite("Export")
struct ExportTests {
    @Test func motionSampleUsesCompactArray() throws {
        let s = MotionSample(t: 1.25, userAcceleration: Vector3(0.1, -0.2, 0.3), gravity: Vector3(0, 0, -1), rotationRate: Vector3(0.01, 0, 0))
        let json = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(json.hasPrefix("[1.25,0.1,-0.2,0.3"))
        #expect(try JSONDecoder().decode(MotionSample.self, from: Data(json.utf8)) == s)
    }

    @Test func configRoundTrips() throws {
        var config = DetectionConfig.default
        config.hardBrake.hardG = 0.41
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(DetectionConfig.self, from: data) == config)
    }

    @Test func driveLogSurvivesUnreadableConfig() throws {
        let log = DriveLog(driveID: UUID(), startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 60),
                           deviceModel: "iPhone", appVersion: "1", config: .default, liveEvents: [], locations: [], motion: [])
        var object = try JSONSerialization.jsonObject(with: log.encoded()) as! [String: Any]
        object["config"] = ["someOldField": 1]
        let decoded = try DriveLog.decode(JSONSerialization.data(withJSONObject: object))
        #expect(decoded.config == nil)
        #expect(decoded.driveID == log.driveID)
    }

    @Test func metricsSumDistanceAndIgnoreJumps() {
        let fixes = (0..<11).map { i in
            LocationSample(t: Double(i), latitude: 33.0 + Double(i) * 0.0001, longitude: -84, horizontalAccuracy: 5,
                           speed: 11, speedAccuracy: 0.5, course: 0, courseAccuracy: 5)
        }
        var withJump = fixes
        withJump.insert(LocationSample(t: 5.5, latitude: 34, longitude: -84, horizontalAccuracy: 5,
                                       speed: 11, speedAccuracy: 0.5, course: 0, courseAccuracy: 5), at: 6)
        let m = DriveMetrics.compute(locations: fixes, duration: 10)
        #expect(abs(m.distanceMeters - 111.2) < 1)
        #expect(m.maxSpeedMps == 11)
        #expect(abs(DriveMetrics.compute(locations: withJump, duration: 10).distanceMeters - m.distanceMeters) < 0.01)
    }
}
