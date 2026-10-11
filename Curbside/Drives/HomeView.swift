import CurbsideCore
import SwiftData
import SwiftUI

/// Home: Curbside Score, Start Drive, what's moving the score, and the latest drives.
struct HomeView: View {
    @Query(sort: \Drive.startDate, order: .reverse) private var drives: [Drive]
    @Environment(\.modelContext) private var context
    @Environment(DriveRecorder.self) private var recorder
    var showTrends: () -> Void
    var showHistory: () -> Void

    private let recentCount = 5

    var body: some View {
        let report = CurbsideScoreReport.from(drives)
        ScrollView {
            VStack(spacing: DS.Spacing.stack) {
                Button(action: showTrends) {
                    CurbsideScoreCard(report: report)
                        .glassCard()
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows score trends")

                Button {
                    Task { await recorder.start() }
                } label: {
                    Label("Start Drive", systemImage: "car.fill")
                }
                .buttonStyle(.primary)
                .disabled(recorder.phase != .idle)

                SectionHeading("What's moving your score")
                VStack(alignment: .leading, spacing: 14) {
                    FactorList(report: report)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                SectionHeading("Recent drives")
                if drives.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your recorded drives will show up here.")
                            .font(DS.Typeface.body)
                            .foregroundStyle(DS.Palette.muted)
                        Button("Load demo drives", systemImage: "sparkles") { DemoDrives.load(into: context) }
                            .buttonStyle(.glassCompact)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
                ForEach(drives.prefix(recentCount)) { drive in
                    NavigationLink(value: drive) {
                        DriveRow(drive: drive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(radius: DS.Radius.row, padding: 14)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete drive", systemImage: "trash", role: .destructive) {
                            drive.deleteWithLog(in: context)
                        }
                    }
                }
                if drives.count > recentCount {
                    Button("See all \(drives.count) drives", action: showHistory)
                        .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, DS.Spacing.gutter)
            .padding(.bottom, DS.Spacing.stack)
        }
        .screenBackground()
        .navigationTitle("Curbside")
        .navigationDestination(for: Drive.self) { DriveSummaryView(drive: $0) }
    }
}

extension Drive {
    /// Deletes the drive and its raw sensor log.
    func deleteWithLog(in context: ModelContext) {
        DriveFiles.delete(logFileName)
        context.delete(self)
        try? context.save()
    }
}

struct DriveRow: View {
    let drive: Drive

    var body: some View {
        let events = drive.events
        let score = drive.score?.rounded
        HStack(spacing: 14) {
            Text(score.map(String.init) ?? "—")
                .font(DS.Typeface.number(18))
                .monospacedDigit()
                .foregroundStyle(score == nil ? DS.Palette.muted : DS.Palette.onAccent)
                .frame(width: 44, height: 44)
                .background(score == nil ? Color.secondary.opacity(0.15) : ScoreStyle.color(score), in: Circle())
                .accessibilityLabel(score.map { "Score \($0)" } ?? "Not scored")
            VStack(alignment: .leading, spacing: 4) {
                Text(drive.startDate, format: .dateTime.weekday(.wide).hour().minute())
                    .font(.headline)
                HStack(spacing: 10) {
                    Text("\(Format.duration(drive.duration)) · \(Format.miles(drive.distanceMeters))")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    ForEach(DrivingEventKind.allCases, id: \.self) { kind in
                        let count = events.filter { $0.kind == kind }.count
                        if count > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: kind.symbol)
                                Text("\(count)").monospacedDigit()
                            }
                            .foregroundStyle(DS.Palette.severityModerate)
                            .fixedSize()
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(count) \(kind.noun(count: count))")
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
