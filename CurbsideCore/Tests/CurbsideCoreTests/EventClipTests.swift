import CurbsideCore
import Foundation
import Testing

@Suite("Event replay clips")
struct EventClipTests {
    /// Warm-up, cruise east at 40 mph, hard brake to 10, then a sharp left turn.
    private func makeLog() -> (DriveLog, DetectionResult) {
        var drive = SyntheticDrive()
        drive.warmUp()
        drive.changeSpeed(to: 40, g: 0.12)
        drive.cruise(6)
        drive.changeSpeed(to: 10, g: 0.45)
        drive.cruise(3)
        drive.changeSpeed(to: 25, g: 0.15)
        drive.cruise(3)
        drive.turn(seconds: 3, lateralG: 0.5)
        drive.cruise(4)
        let (locations, motion) = drive.generate()
        let log = DriveLog(driveID: UUID(), startDate: Date(), endDate: Date(), deviceModel: "test", appVersion: "test",
                           config: .default, liveEvents: nil, locations: locations, motion: motion)
        return (log, log.detect())
    }

    @Test func brakeClipCoversFiveSecondsBeforePeak() throws {
        let (log, result) = makeLog()
        let brake = try #require(result.events.first { $0.kind == .hardBrake })
        let clip = try #require(EventClipBuilder.clips(for: [brake], log: log).first)

        #expect(clip.source == .sensors)
        #expect(abs(clip.duration - 5) < 1e-6)
        #expect(abs(clip.endTime - brake.peakTime) < 1e-6)
        #expect(clip.frames.count >= 150)

        // Car is heading east (course ≈ 90°) and moving east the whole clip.
        #expect(clip.frames.allSatisfy { abs($0.headingDegrees - 90) < 5 })
        #expect(zip(clip.frames, clip.frames.dropFirst()).allSatisfy { $1.longitude >= $0.longitude })

        // Cruising at the start, braking hard by the end.
        let start = clip.frame(at: clip.startTime)
        let end = clip.frame(at: clip.endTime)
        #expect(abs(Units.mph(fromMps: try #require(start.speed)) - 40) < 2)
        #expect(try #require(end.speed) < start.speed!)
        #expect(try #require(clip.force(in: start)) < 0.1)
        #expect(abs(try #require(clip.force(in: end)) - brake.peakG) < 0.02)
    }

    @Test func turnClipShowsCorneringForce() throws {
        let (log, result) = makeLog()
        let turn = try #require(result.events.first { $0.kind == .sharpTurn })
        let clip = try #require(EventClipBuilder.clips(for: [turn], log: log).first)
        #expect(try #require(clip.force(in: clip.frame(at: clip.endTime))) > 0.4)
        // Heading swings left (counter-clockwise) through the turn.
        let headingChange = clip.frame(at: clip.startTime).headingDegrees - clip.frame(at: clip.endTime).headingDegrees
        #expect(headingChange > 20)
    }

    @Test func clipsForSeveralEventsDontBleedIntoEachOther() {
        let (log, result) = makeLog()
        let clips = EventClipBuilder.clips(for: result.events, log: log)
        #expect(clips.map(\.id) == result.events.map(\.id))
        #expect(clips.allSatisfy { clip in clip.frames.allSatisfy { $0.longitudinalG != nil } })
    }

    @Test func gpsOnlyFallbackEstimatesBraking() throws {
        let (log, result) = makeLog()
        let brake = try #require(result.events.first { $0.kind == .hardBrake })
        let clip = try #require(EventClipBuilder.clips(for: [brake], route: RoutePoint.route(from: log.locations)).first)

        #expect(clip.source == .gpsOnly)
        #expect(abs(clip.duration - 5) < 1e-6)
        let braking = try #require(clip.force(in: clip.frame(at: clip.endTime)))
        #expect(braking > 0.3 && braking < 0.6)
        #expect(clip.frame(at: clip.endTime).lateralG == nil)
    }

    @Test func eventNearDriveStartGetsShorterClip() throws {
        let event = DrivingEvent(kind: .hardBrake, severity: .hard, startTime: 1, endTime: 3, peakTime: 2, peakG: 0.4,
                                 speedBefore: 10, speedAfter: 5, latitude: nil, longitude: nil, usedCalibratedAxis: false)
        let route = (0..<10).map { RoutePoint(t: Double($0), latitude: 33, longitude: -84 + Double($0) * 1e-4, speed: 10) }
        let clip = try #require(EventClipBuilder.clips(for: [event], route: route).first)
        #expect(clip.startTime == 0)
        #expect(abs(clip.duration - 2) < 1e-6)
    }

    @Test func frameInterpolationClampsAndWrapsHeading() {
        let event = DrivingEvent(kind: .sharpTurn, severity: .hard, startTime: 0, endTime: 1, peakTime: 1, peakG: 0.5,
                                 speedBefore: 10, speedAfter: 10, latitude: nil, longitude: nil, usedCalibratedAxis: true)
        let clip = EventClip(event: event, frames: [
            ReplayFrame(t: 0, latitude: 0, longitude: 0, headingDegrees: 350, speed: 10, longitudinalG: 0, lateralG: 0.2),
            ReplayFrame(t: 1, latitude: 1, longitude: 2, headingDegrees: 10, speed: 20, longitudinalG: nil, lateralG: 0.6),
        ], source: .sensors)
        let mid = clip.frame(at: 0.5)
        #expect(mid.latitude == 0.5 && mid.longitude == 1)
        #expect(abs(mid.headingDegrees - 0) < 1e-9 || abs(mid.headingDegrees - 360) < 1e-9)
        #expect(mid.speed == 15)
        #expect(mid.longitudinalG == 0)
        #expect(abs(mid.lateralG! - 0.4) < 1e-9)
        #expect(clip.frame(at: -3) == clip.frames[0])
        #expect(clip.frame(at: 9) == clip.frames[1])
    }
}
