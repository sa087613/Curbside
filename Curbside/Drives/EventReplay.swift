import CurbsideCore
import MapKit
import Observation
import SwiftUI

/// Builds replay clips for a drive from data it already stores: the raw sensor log when present
/// (exact detector signal), otherwise the 1 Hz route (GPS-only estimate).
enum EventClipLoader {
    @MainActor
    static func load(for drive: Drive) async -> [UUID: EventClip] {
        let events = drive.events
        guard !events.isEmpty else { return [:] }
        let url = drive.logURL
        let route = drive.route
        let clips = await Task.detached(priority: .userInitiated) { () -> [EventClip] in
            if let data = try? Data(contentsOf: url), let log = try? DriveLog.decode(data) {
                return EventClipBuilder.clips(for: events, log: log)
            }
            return EventClipBuilder.clips(for: events, route: route)
        }.value
        return Dictionary(uniqueKeysWithValues: clips.filter { !$0.frames.isEmpty }.map { ($0.id, $0) })
    }
}

/// Plays a clip in real time. `time` is seconds since the clip start.
@MainActor
@Observable
final class ReplayPlayer {
    let clip: EventClip
    private(set) var isPlaying = false
    /// Set directly by the scrubber (its range is 0…duration); playback clamps when advancing.
    /// No didSet clamp: on an @Observable class that re-enters the setter and recurses.
    var time: Double = 0

    @ObservationIgnored private var task: Task<Void, Never>?

    init(clip: EventClip) {
        self.clip = clip
    }

    var frame: ReplayFrame { clip.frame(at: clip.startTime + time) }
    var isAtEnd: Bool { time >= clip.duration - 1e-6 }

    func play() {
        if isAtEnd { time = 0 }
        isPlaying = true
        task?.cancel()
        task = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, self.isPlaying else { return }
                let now = ContinuousClock.now
                let elapsed = now - last
                last = now
                let dt = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                self.time = min(self.time + dt, self.clip.duration)
                if self.isAtEnd {
                    self.isPlaying = false
                    return
                }
            }
        }
    }

    func pause() {
        isPlaying = false
        task?.cancel()
        task = nil
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }
}

extension EventClip {
    /// Map region framing the whole clip, with some breathing room.
    var region: MKCoordinateRegion {
        let lats = frames.map(\.latitude), lons = frames.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: event.latitude ?? 0, longitude: event.longitude ?? 0),
                                      latitudinalMeters: 300, longitudinalMeters: 300)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        // At least ~200 m across so slow events aren't zoomed in absurdly far.
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.8, 0.0018),
                                    longitudeDelta: max((maxLon - minLon) * 1.8, 0.0018 / max(cos(center.latitude * .pi / 180), 0.1)))
        return MKCoordinateRegion(center: center, span: span)
    }

    var coordinates: [CLLocationCoordinate2D] {
        frames.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

// MARK: - Views

/// Top-down car drawn in code (no image assets), pointing up before rotation.
struct CarMarker: View {
    let headingDegrees: Double
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 18, height: 32)
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.85))
                .frame(width: 12, height: 7)
                .offset(y: -6)
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.6))
                .frame(width: 12, height: 4)
                .offset(y: 9)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2).frame(width: 18, height: 32))
        .shadow(radius: 3)
        .rotationEffect(.degrees(headingDegrees))
        .accessibilityHidden(true)
    }
}

/// Speed readout, force bar, play/pause and scrubber for the selected event.
struct ReplayPanel: View {
    @Bindable var player: ReplayPlayer
    var onClose: () -> Void

    private var event: DrivingEvent { player.clip.event }

    var body: some View {
        let frame = player.frame
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                EventRow(event: event)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close replay")
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 0) {
                    Text(frame.speed.map { "\(Int(Units.mph(fromMps: $0).rounded()))" } ?? "--")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("mph").font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 84)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(frame.speed.map { "\(Int(Units.mph(fromMps: $0).rounded())) miles per hour" } ?? "Speed unavailable")

                ForceBar(kind: event.kind, value: player.clip.force(in: frame))
            }

            HStack(spacing: 12) {
                Button {
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : (player.isAtEnd ? "arrow.counterclockwise" : "play.fill"))
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Slider(value: $player.time, in: 0...max(player.clip.duration, 0.01)) { editing in
                    if editing { player.pause() }
                }
                .accessibilityLabel("Replay position")

                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }

            if player.clip.source == .gpsOnly {
                Label("Raw sensor data isn't available for this drive, so force is estimated from GPS.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Counts down to the event: "−3.2 s" … "0.0 s".
    private var timeLabel: String {
        let remaining = player.clip.duration - player.time
        return remaining < 0.05 ? "0.0 s" : String(format: "−%.1f s", remaining)
    }
}

/// Horizontal force meter with tick marks at the moderate / hard / severe thresholds.
struct ForceBar: View {
    let kind: DrivingEventKind
    let value: Double?

    private var thresholds: (moderate: Double, hard: Double, severe: Double) {
        let c = DetectionConfig.default
        switch kind {
        case .hardBrake: return (c.hardBrake.moderateG, c.hardBrake.hardG, c.hardBrake.severeG)
        case .harshAcceleration: return (c.harshAcceleration.moderateG, c.harshAcceleration.hardG, c.harshAcceleration.severeG)
        case .sharpTurn: return (c.sharpTurn.moderateG, c.sharpTurn.hardG, c.sharpTurn.severeG)
        }
    }

    private var title: String {
        switch kind {
        case .hardBrake: "Braking force"
        case .harshAcceleration: "Acceleration"
        case .sharpTurn: "Cornering force"
        }
    }

    private var color: Color {
        guard let value else { return .secondary }
        let t = thresholds
        if value >= t.severe { return EventSeverity.severe.color }
        if value >= t.hard { return EventSeverity.hard.color }
        if value >= t.moderate { return EventSeverity.moderate.color }
        return .green
    }

    var body: some View {
        let t = thresholds
        let scale = t.severe * 1.3
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(value.map { String(format: "%.2f g", $0) } ?? "n/a")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(color)
                        .frame(width: width * min(max((value ?? 0) / scale, 0), 1))
                    ForEach([t.moderate, t.hard, t.severe], id: \.self) { g in
                        Rectangle()
                            .fill(Color.primary.opacity(0.35))
                            .frame(width: 2, height: 22)
                            .offset(x: width * g / scale - 1)
                    }
                }
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { String(format: "%.2f g", $0) } ?? "unavailable")
    }
}
