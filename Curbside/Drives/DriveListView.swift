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
        .navigationDestination(for: Drive.self) { DriveDetailView(drive: $0) }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(drive.startDate, format: .dateTime.weekday(.wide).hour().minute())
                .font(.headline)
            HStack(spacing: 12) {
                Text(Format.duration(drive.duration))
                Text(Format.miles(drive.distanceMeters))
                Spacer()
                ForEach(DrivingEventKind.allCases, id: \.self) { kind in
                    let count = events.filter { $0.kind == kind }.count
                    if count > 0 {
                        Label("\(count)", systemImage: kind.symbol)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
