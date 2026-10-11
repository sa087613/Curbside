import Foundation

/// One moment of an event replay.
public struct ReplayFrame: Sendable, Equatable {
    /// Seconds since drive start.
    public var t: Double
    public var latitude: Double
    public var longitude: Double
    /// Degrees clockwise from north.
    public var headingDegrees: Double
    /// m/s.
    public var speed: Double?
    /// Smoothed longitudinal acceleration in g (+ speeding up, − braking).
    public var longitudinalG: Double?
    /// Smoothed lateral acceleration magnitude in g.
    public var lateralG: Double?

    public init(t: Double, latitude: Double, longitude: Double, headingDegrees: Double,
                speed: Double?, longitudinalG: Double?, lateralG: Double?) {
        self.t = t
        self.latitude = latitude
        self.longitude = longitude
        self.headingDegrees = headingDegrees
        self.speed = speed
        self.longitudinalG = longitudinalG
        self.lateralG = lateralG
    }
}

/// Where a clip's acceleration numbers came from.
public enum ReplaySource: Sendable, Equatable {
    /// Re-processed from the raw 50 Hz motion log: the same signal the detector saw.
    case sensors
    /// Raw log unavailable: braking estimated from 1 Hz GPS speed changes; no cornering force.
    case gpsOnly
}

/// The few seconds of driving leading up to an event, ready to play back.
public struct EventClip: Sendable, Identifiable {
    public var event: DrivingEvent
    /// Evenly spaced frames from `startTime` to `endTime`.
    public var frames: [ReplayFrame]
    public var source: ReplaySource

    public init(event: DrivingEvent, frames: [ReplayFrame], source: ReplaySource) {
        self.event = event
        self.frames = frames
        self.source = source
    }

    public var id: UUID { event.id }
    public var startTime: Double { frames.first?.t ?? event.peakTime }
    public var endTime: Double { frames.last?.t ?? event.peakTime }
    public var duration: Double { endTime - startTime }

    /// Interpolated frame at drive time `t` (clamped to the clip).
    public func frame(at t: Double) -> ReplayFrame {
        guard let first = frames.first, let last = frames.last else {
            return ReplayFrame(t: t, latitude: event.latitude ?? 0, longitude: event.longitude ?? 0,
                               headingDegrees: 0, speed: nil, longitudinalG: nil, lateralG: nil)
        }
        if t <= first.t { return first }
        if t >= last.t { return last }
        var lo = 0, hi = frames.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if frames[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = frames[lo], b = frames[hi]
        let f = (t - a.t) / (b.t - a.t)
        func mix(_ x: Double?, _ y: Double?) -> Double? {
            guard let x, let y else { return x ?? y }
            return x + (y - x) * f
        }
        var dh = b.headingDegrees - a.headingDegrees
        if dh > 180 { dh -= 360 }
        if dh < -180 { dh += 360 }
        return ReplayFrame(
            t: t,
            latitude: a.latitude + (b.latitude - a.latitude) * f,
            longitude: a.longitude + (b.longitude - a.longitude) * f,
            headingDegrees: (a.headingDegrees + dh * f + 360).truncatingRemainder(dividingBy: 360),
            speed: mix(a.speed, b.speed),
            longitudinalG: mix(a.longitudinalG, b.longitudinalG),
            lateralG: mix(a.lateralG, b.lateralG)
        )
    }

    /// The force that matters for this event's kind, in g: braking for hard brakes,
    /// acceleration for fast starts, cornering for sharp turns. Nil if unavailable.
    public func force(in frame: ReplayFrame) -> Double? {
        switch event.kind {
        case .hardBrake: frame.longitudinalG.map { max(0, -$0) }
        case .harshAcceleration: frame.longitudinalG.map { max(0, $0) }
        case .sharpTurn: frame.lateralG
        }
    }
}

public enum EventClipBuilder {
    /// Builds clips by re-running the raw log through the detector and keeping the processed
    /// signal around each event. Uses the same code path as live detection.
    public static func clips(for events: [DrivingEvent], log: DriveLog,
                             detection: DetectionConfig = .default,
                             replay: ReplayConfig = .default) -> [EventClip] {
        guard !events.isEmpty else { return [] }
        let windows = events.map { window(for: $0, replay: replay) }
        var signal: [SignalFrame] = []
        _ = log.detect(config: detection) { frame in
            if windows.contains(where: { frame.t >= $0.lowerBound - 0.1 && frame.t <= $0.upperBound + 0.1 }) {
                signal.append(frame)
            }
        }
        let track = makeTrack(log.locations, detection)
        return zip(events, windows).map { event, window in
            build(event: event, window: window, track: track, replay: replay, source: .sensors) { t in
                guard let (a, b) = bracket(signal, t) else { return (nil, nil) }
                let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
                return (a.longitudinalG + (b.longitudinalG - a.longitudinalG) * f,
                        a.lateralG + (b.lateralG - a.lateralG) * f)
            }
        }
    }

    /// Fallback when the raw log is gone: GPS-only clips from the stored 1 Hz route.
    public static func clips(for events: [DrivingEvent], route: [RoutePoint],
                             detection: DetectionConfig = .default,
                             replay: ReplayConfig = .default) -> [EventClip] {
        let locations = route.map {
            LocationSample(t: $0.t, latitude: $0.latitude, longitude: $0.longitude, horizontalAccuracy: 5,
                           speed: $0.speed ?? -1, speedAccuracy: -1, course: -1, courseAccuracy: -1)
        }
        let track = makeTrack(locations, detection)
        return events.map { event in
            build(event: event, window: window(for: event, replay: replay), track: track, replay: replay, source: .gpsOnly) { t in
                (track.acceleration(at: t).map { $0 / Units.g }, nil)
            }
        }
    }

    // MARK: Helpers

    static func window(for event: DrivingEvent, replay: ReplayConfig) -> ClosedRange<Double> {
        let end = event.peakTime + replay.trailSeconds
        return max(0, end - replay.leadSeconds - replay.trailSeconds)...end
    }

    private static func makeTrack(_ locations: [LocationSample], _ config: DetectionConfig) -> GPSTrack {
        var track = GPSTrack(config: config)
        for l in locations { track.append(l) }
        return track
    }

    private static func build(event: DrivingEvent, window: ClosedRange<Double>, track: GPSTrack,
                              replay: ReplayConfig, source: ReplaySource,
                              forces: (Double) -> (Double?, Double?)) -> EventClip {
        let step = 1 / replay.frameRateHz
        var times = Array(stride(from: window.lowerBound, to: window.upperBound, by: step))
        times.append(window.upperBound)

        var frames: [ReplayFrame] = []
        frames.reserveCapacity(times.count)
        var lastHeading = track.heading(at: window.upperBound) ?? 0
        for t in times {
            guard let position = track.coordinate(at: t) else { continue }
            let heading = track.heading(at: t) ?? lastHeading
            lastHeading = heading
            let (longitudinal, lateral) = forces(t)
            frames.append(ReplayFrame(t: t, latitude: position.latitude, longitude: position.longitude,
                                      headingDegrees: heading, speed: track.speed(at: t),
                                      longitudinalG: longitudinal, lateralG: lateral))
        }
        return EventClip(event: event, frames: frames, source: source)
    }

    private static func bracket(_ frames: [SignalFrame], _ t: Double) -> (SignalFrame, SignalFrame)? {
        guard !frames.isEmpty else { return nil }
        var lo = 0, hi = frames.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if frames[mid].t < t { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return abs(frames[0].t - t) < 0.2 ? (frames[0], frames[0]) : nil }
        if lo == frames.count { return abs(frames[lo - 1].t - t) < 0.2 ? (frames[lo - 1], frames[lo - 1]) : nil }
        let a = frames[lo - 1], b = frames[lo]
        // Don't interpolate across a gap between two events' windows.
        return b.t - a.t < 0.5 ? (a, b) : nil
    }
}
