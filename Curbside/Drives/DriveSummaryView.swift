import Charts
import CurbsideCore
import MapKit
import SwiftUI

/// Post-drive summary: score, the one habit to fix, event map, speed chart, event list.
struct DriveSummaryView: View {
    let drive: Drive
    @State private var selectedEventID: UUID?
    @State private var clips: [UUID: EventClip]?
    @State private var player: ReplayPlayer?
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        let events = drive.events
        let score = drive.score
        let route = drive.route

        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 16) {
                    ScoreHeader(drive: drive, score: score)

                    HabitCard(score: score)

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Route").font(.headline)
                                Spacer()
                                if !events.isEmpty, player == nil {
                                    Text("Tap an event to replay it")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            DriveMap(route: route, events: events, position: $mapPosition, player: player) { event in
                                select(event)
                            }
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            SeverityLegend()
                            if let player {
                                ReplayPanel(player: player, onClose: closeReplay)
                                    .padding(12)
                                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                            } else if let selected = events.first(where: { $0.id == selectedEventID }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    EventRow(event: selected)
                                    if clips == nil {
                                        ProgressView("Preparing replay…").font(.caption)
                                    } else {
                                        Text("Replay isn't available for this event.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .id("map")

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Speed").font(.headline)
                            SpeedChart(route: route, events: events)
                                .frame(height: 200)
                        }
                    }

                    if !events.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Events").font(.headline)
                                ForEach(events) { event in
                                    Button {
                                        select(event)
                                    } label: {
                                        EventRow(event: event)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(8)
                                    .background(selectedEventID == event.id ? Color.accentColor.opacity(0.12) : .clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }

                    NavigationLink {
                        DriveDebugView(drive: drive)
                    } label: {
                        Label("Debug details & raw data", systemImage: "wrench.and.screwdriver")
                            .font(.subheadline)
                    }
                    .padding(.bottom, 8)
                }
                .padding(16)
            }
            // Bring the map and replay controls into view whenever an event is picked.
            .onChange(of: selectedEventID) { _, id in
                guard id != nil else { return }
                withAnimation { scroll.scrollTo("map", anchor: .top) }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(drive.startDate.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await DriveRouteLoader.backfillIfNeeded(drive)
            clips = await EventClipLoader.load(for: drive)
            // An event tapped while clips were loading starts as soon as they're ready.
            if player == nil, let id = selectedEventID, let event = events.first(where: { $0.id == id }) {
                select(event)
            }
        }
        .onDisappear { player?.pause() }
    }

    private func select(_ event: DrivingEvent) {
        selectedEventID = event.id
        player?.pause()
        guard let clip = clips?[event.id] else {
            player = nil
            return
        }
        let newPlayer = ReplayPlayer(clip: clip)
        player = newPlayer
        withAnimation(.easeInOut(duration: 0.6)) { mapPosition = .region(clip.region) }
        newPlayer.play()
    }

    private func closeReplay() {
        player?.pause()
        player = nil
        selectedEventID = nil
        withAnimation(.easeInOut(duration: 0.6)) { mapPosition = .automatic }
    }
}

// MARK: - Score

private struct ScoreHeader: View {
    let drive: Drive
    let score: DriveScore?

    var body: some View {
        Card {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: (score?.value ?? 0) / 100)
                        .stroke(ScoreStyle.color(score?.rounded), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(score.map { "\($0.rounded)" } ?? "—")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("out of 100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(score.map { "Drive score \($0.rounded) out of 100" } ?? "Not scored")

                Text(ScoreStyle.headline(score?.rounded))
                    .font(.title3.weight(.semibold))

                HStack(spacing: 0) {
                    Stat(value: Format.miles(drive.distanceMeters), label: "Distance")
                    Divider().frame(height: 30)
                    Stat(value: Format.duration(drive.duration), label: "Time")
                    Divider().frame(height: 30)
                    Stat(value: Format.mph(drive.maxSpeedMps), label: "Top speed")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Habit to fix

private struct HabitCard: View {
    let score: DriveScore?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                if let habit = score?.habitToFix {
                    Image(systemName: habit.kind.symbol)
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The one habit to fix")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text("\(habit.kind.habitName) cost you \(Int(habit.points.rounded())) \(Int(habit.points.rounded()) == 1 ? "point" : "points")")
                            .font(.headline)
                        Text("\(habit.count) \(habit.kind.noun(count: habit.count)) this drive. \(habit.kind.tip)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(score == nil ? "Too short to score" : "Nothing to fix")
                            .font(.headline)
                        Text(score == nil
                             ? "Drives need to be at least a few blocks long to get a score."
                             : "No hard brakes, fast starts, or sharp turns. Keep it up.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Map

private struct DriveMap: View {
    let route: [RoutePoint]
    let events: [DrivingEvent]
    @Binding var position: MapCameraPosition
    /// Active replay, if any: draws the clip path and the moving car.
    let player: ReplayPlayer?
    var onSelect: (DrivingEvent) -> Void

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            if route.count > 1 {
                MapPolyline(coordinates: route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                    // Map content doesn't resolve Color.accentColor to the app's accent; use the asset.
                    .stroke(Color("AccentColor"), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let start = route.first {
                Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)) {
                    Circle().fill(.white).stroke(Color("AccentColor"), lineWidth: 4).frame(width: 14, height: 14)
                }
            }
            if let end = route.last, route.count > 1 {
                Annotation("End", coordinate: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude)) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .black)
                }
            }
            ForEach(events) { event in
                if let lat = event.latitude, let lon = event.longitude {
                    Annotation(event.kind.displayName, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                        Button {
                            onSelect(event)
                        } label: {
                            EventPin(event: event, selected: player?.clip.id == event.id)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            if let player {
                MapPolyline(coordinates: player.clip.coordinates)
                    .stroke(player.clip.event.severity.color, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                let frame = player.frame
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: frame.latitude, longitude: frame.longitude)) {
                    CarMarker(headingDegrees: frame.headingDegrees, color: .indigo)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .overlay {
            if route.count < 2 {
                Text("No route recorded")
                    .font(.subheadline)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }
}

private struct EventPin: View {
    let event: DrivingEvent
    let selected: Bool

    var body: some View {
        Image(systemName: event.kind.symbol)
            .font(.system(size: selected ? 16 : 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: selected ? 36 : 28, height: selected ? 36 : 28)
            .background(event.severity.color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
            .accessibilityLabel("\(event.severity.displayName) \(event.kind.displayName.lowercased())")
    }
}

private struct SeverityLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(EventSeverity.allCases, id: \.self) { severity in
                HStack(spacing: 5) {
                    Circle().fill(severity.color).frame(width: 10, height: 10)
                    Text(severity.displayName)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Speed chart

private struct SpeedChart: View {
    let route: [RoutePoint]
    let events: [DrivingEvent]

    private struct Point: Identifiable {
        let id: Int
        let minutes: Double
        let mph: Double
    }

    /// At most ~400 points so the chart stays smooth on long drives.
    private var points: [Point] {
        let step = max(1, route.count / 400)
        return stride(from: 0, to: route.count, by: step).compactMap { i in
            route[i].speed.map { Point(id: i, minutes: route[i].t / 60, mph: Units.mph(fromMps: $0)) }
        }
    }

    private func mph(at t: Double) -> Double? {
        guard let i = route.firstIndex(where: { $0.t >= t }) else { return route.last?.speed.map(Units.mph(fromMps:)) }
        guard i > 0, let a = route[i - 1].speed, let b = route[i].speed else { return route[i].speed.map(Units.mph(fromMps:)) }
        let f = (t - route[i - 1].t) / max(route[i].t - route[i - 1].t, 1e-6)
        return Units.mph(fromMps: a + (b - a) * f)
    }

    var body: some View {
        let points = points
        if points.count < 2 {
            Text("No speed data recorded")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Minutes", p.minutes), y: .value("mph", p.mph))
                        .foregroundStyle(Color.accentColor.opacity(0.15).gradient)
                    LineMark(x: .value("Minutes", p.minutes), y: .value("mph", p.mph))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(events) { event in
                    if let speed = mph(at: event.peakTime) {
                        PointMark(x: .value("Minutes", event.peakTime / 60), y: .value("mph", speed))
                            .foregroundStyle(event.severity.color)
                            .symbolSize(90)
                            .accessibilityLabel(event.kind.displayName)
                    }
                }
            }
            .chartXAxisLabel("minutes")
            .chartYAxisLabel("mph")
        }
    }
}

// MARK: - Shared pieces

struct EventRow: View {
    let event: DrivingEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(event.severity.color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.kind.displayName) · \(event.severity.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text("at \(Format.clock(event.startTime)) · \(Format.mph(event.speedBefore)) → \(Format.mph(event.speedAfter)) · \(event.peakG, format: .number.precision(.fractionLength(2)))g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
