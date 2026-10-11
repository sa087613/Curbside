import Charts
import CurbsideCore
import SwiftData
import SwiftUI

enum TrendRange: String, CaseIterable, Identifiable {
    case month = "30 days"
    case quarter = "90 days"
    case all = "All time"

    var id: Self { self }

    func cutoff(now: Date = .now) -> Date? {
        switch self {
        case .month: Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .quarter: Calendar.current.date(byAdding: .day, value: -90, to: now)
        case .all: nil
        }
    }
}

/// Habit series colors: fixed per habit (never by rank), validated for color-vision deficiency
/// on the dark background. Always shown with a legend; the table view covers low-contrast aqua.
private extension DrivingEventKind {
    var seriesColor: Color {
        switch self {
        case .hardBrake: DS.Palette.hardBrake
        case .harshAcceleration: DS.Palette.harshAcceleration
        case .sharpTurn: DS.Palette.sharpTurn
        }
    }
}

struct TrendsView: View {
    @Query(sort: \Drive.startDate) private var drives: [Drive]
    @State private var range: TrendRange = .month

    var body: some View {
        let report = CurbsideScoreReport.from(drives)
        let cutoff = range.cutoff()
        let inRange = drives.filter { d in cutoff.map { d.startDate >= $0 } ?? true }
        let scored = inRange.compactMap { d in d.score.map { (drive: d, score: $0) } }
        let history = report.history.filter { p in cutoff.map { p.date >= $0 } ?? true }

        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if drives.isEmpty {
                    ContentUnavailableView("No drives yet", systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Trends appear after your first few drives."))
                        .padding(.top, 40)
                } else {
                    Card {
                        VStack(spacing: 6) {
                            CurbsideScoreCard(report: report)
                        }
                    }
                    SummaryTiles(drives: inRange, scored: scored.map(\.score))
                    Card {
                        ChartHeader(title: "Curbside Score", subtitle: "After each drive")
                        ScoreHistoryChart(points: history)
                            .frame(height: 220)
                    }
                    Card {
                        ChartHeader(title: "Drive scores", subtitle: "Each dot is one drive (0–100)")
                        DriveScoreChart(drives: scored.map { ($0.drive.startDate, $0.score.rounded) })
                            .frame(height: 180)
                    }
                    Card {
                        ChartHeader(title: "Habits", subtitle: "Events per 10 miles, by week")
                        HabitChart(drives: inRange)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What's moving your score").font(.headline)
                            FactorList(report: report)
                        }
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Trends")
    }
}

private struct ChartHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

private struct SummaryTiles: View {
    let drives: [Drive]
    let scored: [DriveScore]

    var body: some View {
        let miles = drives.reduce(0) { $0 + $1.distanceMeters } / Units.metersPerMile
        let average = scored.isEmpty ? nil : scored.reduce(0) { $0 + $1.value } / Double(scored.count)
        let clean = scored.isEmpty ? nil : Double(scored.filter { $0.deductions.isEmpty }.count) / Double(scored.count)
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Tile(value: "\(drives.count)", label: "Drives")
                Tile(value: String(format: "%.0f", miles), label: "Miles")
            }
            GridRow {
                Tile(value: average.map { "\(Int($0.rounded()))" } ?? "—", label: "Avg drive score")
                Tile(value: clean.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—", label: "Clean drives")
            }
        }
    }

    private struct Tile: View {
        let value: String
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.weight(.bold)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: DS.Radius.row, padding: nil)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Curbside Score over time

private struct ScoreHistoryChart: View {
    let points: [CurbsideScorePoint]
    @State private var selected: Date?

    private var selectedPoint: CurbsideScorePoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        if points.isEmpty {
            Text("No scored drives in this range").font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let lower = lowerBound
            let boundaries = CurbsideTier.allCases.map { $0.range().lowerBound }.filter { $0 > lower } + [CurbsideScale.maximum]
            Chart {
                // Tier boundaries; tier names sit on the right-hand axis so they never cover the line.
                ForEach(boundaries.dropLast(), id: \.self) { boundary in
                    RuleMark(y: .value("Tier", boundary))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                ForEach(points, id: \.driveID) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Score", p.score))
                        .foregroundStyle(DS.Palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                if points.count == 1, let only = points.first {
                    PointMark(x: .value("Date", only.date), y: .value("Score", only.score))
                        .foregroundStyle(DS.Palette.accent)
                }
                if let p = selectedPoint {
                    RuleMark(x: .value("Date", p.date))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                    PointMark(x: .value("Date", p.date), y: .value("Score", p.score))
                        .foregroundStyle(DS.Palette.accent)
                        .symbolSize(80)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: p.date.formatted(.dateTime.month().day().hour().minute()),
                                         value: "\(p.score) · \(CurbsideTier.tier(for: p.score).displayName)")
                        }
                }
            }
            .chartYScale(domain: lower...CurbsideScale.maximum)
            .chartYAxis {
                AxisMarks(position: .leading, values: [lower] + boundaries)
                AxisMarks(position: .trailing, values: tierMidpoints(above: lower)) { value in
                    AxisValueLabel {
                        if let mid = value.as(Int.self) {
                            let tier = CurbsideTier.tier(for: mid)
                            HStack(spacing: 3) {
                                Circle().fill(tier.color).frame(width: 6, height: 6)
                                Text(tier.displayName)
                            }
                        }
                    }
                }
            }
            .chartXSelection(value: $selected)
        }
    }

    /// Axis starts at the tier boundary below the lowest score shown, so the line isn't squashed.
    private var lowerBound: Int {
        let minScore = points.map(\.score).min() ?? CurbsideScale.minimum
        return CurbsideTier.allCases.map { $0.range().lowerBound }.filter { $0 <= minScore - 3 }.max() ?? CurbsideScale.minimum
    }

    /// Middle of each visible tier band, used to place the tier name labels.
    private func tierMidpoints(above lower: Int) -> [Int] {
        CurbsideTier.allCases.compactMap { tier in
            let r = tier.range()
            let low = max(r.lowerBound, lower)
            return low < r.upperBound ? (low + r.upperBound) / 2 : nil
        }
    }
}

// MARK: - Drive scores

private struct DriveScoreChart: View {
    let drives: [(date: Date, score: Int)]
    @State private var selected: Date?

    private var selectedDrive: (date: Date, score: Int)? {
        guard let selected else { return nil }
        return drives.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        if drives.isEmpty {
            Text("No scored drives in this range").font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(Array(drives.enumerated()), id: \.offset) { _, d in
                    PointMark(x: .value("Date", d.date), y: .value("Score", d.score))
                        .foregroundStyle(DS.Palette.accent)
                        .symbolSize(50)
                }
                if let d = selectedDrive {
                    RuleMark(x: .value("Date", d.date))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: d.date.formatted(.dateTime.month().day().hour().minute()), value: "\(d.score) / 100")
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) }
            .chartXSelection(value: $selected)
        }
    }
}

// MARK: - Habits per 10 miles, by week

private struct HabitChart: View {
    let drives: [Drive]
    @State private var showTable = false

    private struct WeekRate: Identifiable {
        let week: Date
        let kind: DrivingEventKind
        let rate: Double
        var id: String { "\(week.timeIntervalSince1970)-\(kind.rawValue)" }
    }

    private var weeks: [(week: Date, miles: Double, counts: [DrivingEventKind: Int])] {
        let calendar = Calendar.current
        var buckets: [Date: (miles: Double, counts: [DrivingEventKind: Int])] = [:]
        for d in drives {
            let week = calendar.dateInterval(of: .weekOfYear, for: d.startDate)?.start ?? d.startDate
            var bucket = buckets[week] ?? (0, [:])
            bucket.miles += d.distanceMeters / Units.metersPerMile
            for e in d.events { bucket.counts[e.kind, default: 0] += 1 }
            buckets[week] = bucket
        }
        return buckets.map { ($0.key, $0.value.miles, $0.value.counts) }.sorted { $0.week < $1.week }
    }

    var body: some View {
        let weeks = weeks.filter { $0.miles >= 0.5 }
        let rates = weeks.flatMap { w in
            DrivingEventKind.allCases.map { WeekRate(week: w.week, kind: $0, rate: Double(w.counts[$0] ?? 0) / w.miles * 10) }
        }
        VStack(alignment: .leading, spacing: 10) {
            if weeks.isEmpty {
                Text("Not enough driving in this range").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(rates) { r in
                    BarMark(x: .value("Week", r.week, unit: .weekOfYear), y: .value("Per 10 mi", r.rate))
                        .foregroundStyle(by: .value("Habit", r.kind.habitName))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(domain: DrivingEventKind.allCases.map(\.habitName),
                                           range: DrivingEventKind.allCases.map(\.seriesColor))
                .chartLegend(position: .top, alignment: .leading)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 200)

                DisclosureGroup("Show as table", isExpanded: $showTable) {
                    Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Week").gridColumnAlignment(.leading)
                            ForEach(DrivingEventKind.allCases, id: \.self) { Text($0.habitName) }
                        }
                        .font(.caption.weight(.semibold))
                        ForEach(weeks.reversed(), id: \.week) { w in
                            GridRow {
                                Text(w.week.formatted(.dateTime.month(.abbreviated).day()))
                                ForEach(DrivingEventKind.allCases, id: \.self) { k in
                                    Text(String(format: "%.1f", Double(w.counts[k] ?? 0) / w.miles * 10)).monospacedDigit()
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline)
            }
        }
    }
}

private struct ChartTooltip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}
