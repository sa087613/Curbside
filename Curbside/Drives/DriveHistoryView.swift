import CurbsideCore
import SwiftData
import SwiftUI

/// Every drive, grouped by month, with simple filters.
struct DriveHistoryView: View {
    @Query(sort: \Drive.startDate, order: .reverse) private var drives: [Drive]
    @Environment(\.modelContext) private var context
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case withEvents = "With events"
        case clean = "Clean"

        var id: Self { self }

        func includes(_ drive: Drive) -> Bool {
            switch self {
            case .all: true
            case .withEvents: !drive.events.isEmpty
            case .clean: drive.events.isEmpty && drive.score != nil
            }
        }
    }

    private var months: [(month: Date, drives: [Drive])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: drives.filter(filter.includes)) {
            calendar.dateInterval(of: .month, for: $0.startDate)?.start ?? $0.startDate
        }
        return grouped.map { ($0.key, $0.value) }.sorted { $0.month > $1.month }
    }

    var body: some View {
        let months = months
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            ForEach(months, id: \.month) { month in
                Section {
                    ForEach(month.drives) { drive in
                        NavigationLink(value: drive) {
                            DriveRow(drive: drive)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { month.drives[$0] }.forEach { $0.deleteWithLog(in: context) }
                    }
                } header: {
                    MonthHeader(month: month.month, drives: month.drives)
                }
            }
        }
        .overlay {
            if drives.isEmpty {
                ContentUnavailableView("No drives yet", systemImage: "car",
                                       description: Text("Drives you record show up here."))
            } else if months.isEmpty {
                ContentUnavailableView("No matching drives", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: Drive.self) { DriveSummaryView(drive: $0) }
    }
}

private struct MonthHeader: View {
    let month: Date
    let drives: [Drive]

    var body: some View {
        let miles = drives.reduce(0) { $0 + $1.distanceMeters } / Units.metersPerMile
        let scores = drives.compactMap { $0.score?.value }
        let average = scores.isEmpty ? nil : Int((scores.reduce(0, +) / Double(scores.count)).rounded())
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()))
            Spacer()
            Text("\(drives.count) \(drives.count == 1 ? "drive" : "drives") · \(String(format: "%.0f", miles)) mi"
                 + (average.map { " · avg \($0)" } ?? ""))
                .monospacedDigit()
        }
    }
}
