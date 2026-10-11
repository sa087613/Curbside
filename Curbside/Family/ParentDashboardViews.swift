import CurbsideCore
import MapKit
import SwiftUI

/// A member's score and weekly summary, as shown on the parent dashboard (and the consent preview).
struct MemberStandingCard: View {
    let name: String
    let role: FamilyRole
    let sharing: Bool
    let standing: SharedStanding?
    var showsChevron = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Avatar(name: name, tier: standing?.tier, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        if let s = standing {
                            HStack(spacing: 4) {
                                Text("\(s.score)").monospacedDigit().fontWeight(.semibold)
                                Text("· \(s.tier.displayName)")
                                TrendArrow(delta: s.trendDelta)
                                Text(s.trendDelta == 0 ? "" : (s.trendDelta > 0 ? "+\(s.trendDelta)" : "\(s.trendDelta)"))
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        } else {
                            Text(sharing ? "No scored drives yet" : (role == .teen ? "Hasn't turned on sharing" : "Not sharing"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if showsChevron {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                if let w = standing?.weekly {
                    WeeklySummaryGrid(weekly: w)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WeeklySummaryGrid: View {
    let weekly: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This week").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                stat("\(weekly.drives)", "drives")
                stat(String(format: "%.0f", weekly.miles), "miles")
                stat(weekly.averageScore.map(String.init) ?? "—", "avg score")
                stat("\(weekly.totalEvents)", weekly.totalEvents == 1 ? "event" : "events")
            }
            if weekly.totalEvents > 0 {
                HStack(spacing: 12) {
                    if weekly.hardBrakes > 0 { Label("\(weekly.hardBrakes)", systemImage: DrivingEventKind.hardBrake.symbol) }
                    if weekly.fastStarts > 0 { Label("\(weekly.fastStarts)", systemImage: DrivingEventKind.harshAcceleration.symbol) }
                    if weekly.sharpTurns > 0 { Label("\(weekly.sharpTurns)", systemImage: DrivingEventKind.sharpTurn.symbol) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Teen detail

struct TeenDetailView: View {
    let member: MemberRecord
    @Environment(FamilyStore.self) private var store
    @State private var drives: [SharedDrive]?

    /// Latest version of this member from the live list.
    private var live: MemberRecord { store.members.first { $0.id == member.id } ?? member }

    var body: some View {
        let m = live
        ScrollView {
            VStack(spacing: 16) {
                if let s = m.standing {
                    Card {
                        VStack(spacing: 8) {
                            ScoreGauge(score: s.score).frame(maxWidth: 260)
                            HStack(spacing: 10) {
                                Text(s.tier.displayName)
                                    .font(.headline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(s.tier.color.opacity(0.18), in: Capsule())
                                TrendChip(trend: ScoreTrend(delta: s.trendDelta), hasDrives: true)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Card { WeeklySummaryGrid(weekly: s.weekly) }
                } else {
                    Card {
                        Label(m.sharing ? "\(m.displayName) hasn't recorded a scored drive yet."
                                        : "\(m.displayName) hasn't turned on sharing. They can do it in Family › Settings. Only they can choose to share.",
                              systemImage: m.sharing ? "car" : "eye.slash")
                            .font(.subheadline)
                    }
                }

                if m.sharing {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent drives").font(.title3.weight(.bold))
                        if let drives {
                            if drives.isEmpty {
                                Card {
                                    Text("Drives \(m.displayName) records from now on will show up here.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            ForEach(Array(drives.enumerated()), id: \.element.id) { index, drive in
                                NavigationLink {
                                    SharedDriveView(memberName: m.displayName, drive: drive)
                                } label: {
                                    Card {
                                        VStack(alignment: .leading, spacing: 10) {
                                            SharedDriveRow(drive: drive, showsChevron: true)
                                            // The latest drive gets its map inline; the rest open on tap.
                                            if index == 0 {
                                                SharedDriveMap(drive: drive)
                                                    .frame(height: 180)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                                    .allowsHitTesting(false)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(m.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: m.sharing) { drives = m.sharing ? await store.drives(of: m) : [] }
        .refreshable { drives = await store.drives(of: live) }
    }
}

// MARK: - Shared drive

struct SharedDriveRow: View {
    let drive: SharedDrive
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            Text(drive.score.map(String.init) ?? "—")
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(drive.score == nil ? Color.secondary : Color.white)
                .frame(width: 44, height: 44)
                .background(drive.score == nil ? Color.secondary.opacity(0.15) : ScoreStyle.color(drive.score), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(drive.startDate.formatted(.dateTime.weekday(.wide).hour().minute())).font(.subheadline.weight(.semibold))
                Text("\(Format.duration(drive.durationSeconds)) · \(String(format: "%.1f mi", drive.miles))"
                     + (drive.events.isEmpty ? " · No events" : " · \(drive.events.count) \(drive.events.count == 1 ? "event" : "events")"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsChevron { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SharedDriveMap: View {
    let drive: SharedDrive

    var body: some View {
        Map(initialPosition: .automatic) {
            if drive.route.count > 1 {
                MapPolyline(coordinates: drive.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                    .stroke(Color("AccentColor"), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(drive.events.enumerated()), id: \.offset) { _, event in
                if let lat = event.lat, let lon = event.lon {
                    Annotation(event.kind.displayName, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                        Image(systemName: event.kind.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(event.severity.color, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .overlay {
            if drive.route.count < 2 {
                Text("No route").font(.caption).padding(6).background(.regularMaterial, in: Capsule())
            }
        }
    }
}

struct SharedDriveView: View {
    let memberName: String
    let drive: SharedDrive

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card { SharedDriveRow(drive: drive) }
                SharedDriveMap(drive: drive)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Events").font(.headline)
                        if drive.events.isEmpty {
                            Text("No hard brakes, fast starts, or sharp turns.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(Array(drive.events.enumerated()), id: \.offset) { _, e in
                            HStack(spacing: 12) {
                                Image(systemName: e.kind.symbol)
                                    .font(.callout.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(e.severity.color, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(e.kind.displayName) · \(e.severity.displayName)").font(.subheadline.weight(.semibold))
                                    Text("\(Format.clock(e.offsetSeconds)) into the drive").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Text("Speeds, braking force, and replays stay on \(memberName)'s phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(memberName)'s drive")
        .navigationBarTitleDisplayMode(.inline)
    }
}
