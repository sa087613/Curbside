import CurbsideCore
import Foundation
import Testing

@Suite("Drive score")
struct DriveScoreTests {
    private func event(_ kind: DrivingEventKind, _ severity: EventSeverity = .hard) -> DrivingEvent {
        DrivingEvent(kind: kind, severity: severity, startTime: 0, endTime: 1, peakTime: 0.5, peakG: 0.4,
                     speedBefore: 15, speedAfter: 5, latitude: nil, longitude: nil, usedCalibratedAxis: true)
    }

    private func meters(_ miles: Double) -> Double { miles * Units.metersPerMile }

    @Test func cleanDriveScores100() throws {
        let score = try #require(DriveScore.compute(events: [], distanceMeters: meters(8)))
        #expect(score.rounded == 100)
        #expect(score.habitToFix == nil)
        #expect(score.deductions.isEmpty)
    }

    @Test func oneHardBrakeOnTenMiles() throws {
        // 8 points × 1.5 (hard) × 5/10 miles = 6
        let score = try #require(DriveScore.compute(events: [event(.hardBrake)], distanceMeters: meters(10)))
        #expect(abs(score.value - 94) < 1e-9)
        #expect(score.habitToFix == HabitDeduction(kind: .hardBrake, count: 1, points: 6))
    }

    @Test func deductionsScaleWithDistance() throws {
        let events = [event(.hardBrake), event(.sharpTurn)]
        let short = try #require(DriveScore.compute(events: events, distanceMeters: meters(5)))
        let long = try #require(DriveScore.compute(events: events, distanceMeters: meters(10)))
        #expect(abs(short.totalDeduction - 2 * long.totalDeduction) < 1e-9)
    }

    @Test func sameRateGivesSameScore() throws {
        let one = try #require(DriveScore.compute(events: [event(.hardBrake)], distanceMeters: meters(5)))
        let two = try #require(DriveScore.compute(events: [event(.hardBrake), event(.hardBrake)], distanceMeters: meters(10)))
        #expect(abs(one.value - two.value) < 1e-9)
    }

    @Test func shortDrivesUseMinimumDistance() throws {
        let oneMile = try #require(DriveScore.compute(events: [event(.hardBrake)], distanceMeters: meters(1)))
        let threeMiles = try #require(DriveScore.compute(events: [event(.hardBrake)], distanceMeters: meters(3)))
        #expect(oneMile.value == threeMiles.value)
        #expect(oneMile.rounded == 80)
    }

    @Test func tinyDrivesAreNotScored() {
        #expect(DriveScore.compute(events: [event(.hardBrake)], distanceMeters: meters(0.1)) == nil)
    }

    @Test func severityCostsMore() throws {
        let scores = try EventSeverity.allCases.map { severity in
            try #require(DriveScore.compute(events: [event(.hardBrake, severity)], distanceMeters: meters(5))).value
        }
        #expect(scores[0] > scores[1] && scores[1] > scores[2])
    }

    @Test func scoreNeverGoesBelowZero() throws {
        let events = Array(repeating: event(.hardBrake, .severe), count: 40)
        let score = try #require(DriveScore.compute(events: events, distanceMeters: meters(3)))
        #expect(score.value == 0)
    }

    @Test func habitToFixIsTheCostliestKind() throws {
        // Three moderate fast starts (3 × 5 = 15) vs one severe hard brake (8 × 2.5 = 20), on 5 miles.
        let events = [event(.harshAcceleration, .moderate), event(.harshAcceleration, .moderate),
                      event(.harshAcceleration, .moderate), event(.hardBrake, .severe)]
        let score = try #require(DriveScore.compute(events: events, distanceMeters: meters(5)))
        #expect(score.habitToFix?.kind == .hardBrake)
        #expect(score.habitToFix?.count == 1)
        #expect(score.deductions.map(\.kind) == [.hardBrake, .harshAcceleration])
        #expect(score.deductions.map(\.count) == [1, 3])
        #expect(abs(score.value - 65) < 1e-9)
    }

    @Test func tiesGoToTheMoreFrequentHabit() throws {
        var config = ScoringConfig()
        config.hardBrakePoints = 10
        config.harshAccelerationPoints = 5
        let events = [event(.hardBrake, .moderate), event(.harshAcceleration, .moderate), event(.harshAcceleration, .moderate)]
        let score = try #require(DriveScore.compute(events: events, distanceMeters: meters(5), config: config))
        #expect(score.habitToFix?.kind == .harshAcceleration)
    }

    @Test func detectedSyntheticDriveScores() throws {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.changeSpeed(to: 40, g: 0.12)
        drive.cruise(5)
        drive.changeSpeed(to: 10, g: 0.45)
        drive.cruise(5)
        let (locations, motion) = drive.generate()
        let result = EventDetector.run(locations: locations, motion: motion)
        let metrics = DriveMetrics.compute(locations: locations, duration: motion.last!.t)
        let score = try #require(DriveScore.compute(events: result.events, distanceMeters: metrics.distanceMeters))
        // Under 3 miles → one hard-severity brake costs 8 × 1.5 × 5/3 = 20.
        #expect(score.rounded == 80)
        #expect(score.habitToFix?.kind == .hardBrake)
    }
}

@Suite("Route")
struct RouteTests {
    @Test func thinsAndRoundTrips() throws {
        let fixes = stride(from: 0.0, to: 10, by: 0.5).map { t in
            LocationSample(t: t, latitude: 33, longitude: -84, horizontalAccuracy: t == 3 ? 80 : 5,
                           speed: t == 4 ? -1 : 10, speedAccuracy: 0.5, course: 0, courseAccuracy: 5)
        }
        let route = RoutePoint.route(from: fixes)
        #expect(route.map(\.t) == [0, 1, 2, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5])
        let decoded = try JSONDecoder().decode([RoutePoint].self, from: JSONEncoder().encode(route))
        #expect(decoded == route)

        let withMissingSpeed = RoutePoint.route(from: fixes.filter { $0.t >= 4 })
        #expect(withMissingSpeed.first?.speed == nil)
        #expect(try JSONDecoder().decode([RoutePoint].self, from: JSONEncoder().encode(withMissingSpeed)) == withMissingSpeed)
    }
}
