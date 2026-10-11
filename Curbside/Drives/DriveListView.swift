import CurbsideCore
import SwiftData
import SwiftUI

struct DriveListView: View {
    @Query(sort: \Drive.startDate, order: .reverse) private var drives: [Drive]
    @Environment(\.modelContext) private var context
    @Environment(DriveRecorder.self) private var recorder

    var body: some View {
        List {
            Section {
                Button {
                    Task { await recorder.start() }
                } label: {
                    Label("Start Drive", systemImage: "car.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(recorder.phase != .idle)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Drives") {
                if drives.isEmpty {
                    Text("Your recorded drives will show up here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(drives) { drive in
                    NavigationLink(value: drive) {
                        DriveRow(drive: drive)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Curbside")
        .navigationDestination(for: Drive.self) { DriveSummaryView(drive: $0) }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let drive = drives[index]
            DriveFiles.delete(drive.logFileName)
            context.delete(drive)
        }
        try? context.save()
    }
}

private struct DriveRow: View {
    let drive: Drive

    var body: some View {
        let events = drive.events
        let score = drive.score?.rounded
        HStack(spacing: 14) {
            Text(score.map(String.init) ?? "—")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(score == nil ? Color.secondary : Color.white)
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
                            .foregroundStyle(.orange)
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
