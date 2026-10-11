import CurbsideCore
import SwiftData
import SwiftUI

extension Drive {
    var scoredDrive: ScoredDrive? {
        score.map { ScoredDrive(id: id, date: startDate, driveScore: $0) }
    }
}

extension CurbsideScoreReport {
    static func from(_ drives: [Drive], now: Date = .now) -> CurbsideScoreReport {
        compute(drives: drives.compactMap(\.scoredDrive), now: now)
    }
}

extension CurbsideTier {
    /// Tier colors always appear next to the tier name, never alone.
    var color: Color {
        switch self {
        case .needsWork: .red
        case .fair: .orange
        case .good: Color(red: 0.93, green: 0.70, blue: 0.0)
        case .great: Color("AccentColor")
        case .excellent: .green
        }
    }
}

// MARK: - Gauge

/// Credit-score-style semicircle from 300 to 850, split into tier segments, with a marker at the score.
struct ScoreGauge: View {
    let score: Int
    var lineWidth: CGFloat = 18

    private static func fraction(_ value: Int) -> Double {
        Double(value - CurbsideScale.minimum) / Double(CurbsideScale.maximum - CurbsideScale.minimum)
    }

    var body: some View {
        let tier = CurbsideTier.tier(for: score)
        GeometryReader { geo in
            let inset = lineWidth / 2 + 6
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height - inset)
            let radius = min(geo.size.width / 2, geo.size.height) - inset
            let angle = Double.pi * (1 + Self.fraction(score))

            ZStack {
                ForEach(CurbsideTier.allCases, id: \.self) { t in
                    let range = t.range()
                    // A small gap between segments keeps the tiers readable.
                    GaugeArc(center: center, radius: radius,
                             from: Self.fraction(range.lowerBound) + 0.004,
                             to: Self.fraction(min(range.upperBound + 1, CurbsideScale.maximum)) - 0.004)
                        .stroke(t.color.opacity(t == tier ? 1 : 0.3), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
                Circle()
                    .fill(Color(.systemBackground))
                    .overlay(Circle().stroke(tier.color, lineWidth: 5))
                    .frame(width: lineWidth + 10, height: lineWidth + 10)
                    .shadow(radius: 2)
                    .position(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: radius * 0.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("300 – 850")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .position(x: center.x, y: center.y - radius * 0.3)
            }
        }
        .aspectRatio(1.7, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Curbside Score \(score) out of 850, \(tier.displayName)")
    }
}

private struct GaugeArc: Shape {
    let center: CGPoint
    let radius: CGFloat
    let from: Double
    let to: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: center, radius: radius,
                 startAngle: .radians(.pi * (1 + from)), endAngle: .radians(.pi * (1 + to)), clockwise: false)
        return p
    }
}

// MARK: - Score card

struct CurbsideScoreCard: View {
    let report: CurbsideScoreReport

    var body: some View {
        VStack(spacing: 10) {
            Text("Curbside Score")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScoreGauge(score: report.score)
                .frame(maxWidth: 300)
            HStack(spacing: 10) {
                Text(report.tier.displayName)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(report.tier.color.opacity(0.18), in: Capsule())
                TrendChip(trend: report.trend, hasDrives: report.scoredDriveCount > 0)
            }
            if report.scoredDriveCount == 0 {
                Text("Everyone starts at 660. Record drives to build your score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct TrendChip: View {
    let trend: ScoreTrend
    let hasDrives: Bool

    var body: some View {
        let (symbol, color, text): (String, Color, String) = switch trend.direction {
        case .up: ("arrow.up.right", .green, "+\(trend.delta) this week")
        case .down: ("arrow.down.right", .red, "\(trend.delta) this week")
        case .flat: ("arrow.right", .secondary, hasDrives ? "Steady this week" : "No drives yet")
        }
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .fontWeight(.bold)
            Text(text)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - What's moving your score

struct FactorRow: View {
    let factor: ScoreFactor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: factor.impact < 0 ? "arrow.down" : "arrow.up")
                        .foregroundStyle(factor.impact < 0 ? Color.red : Color.green)
                        .font(.caption.weight(.bold))
                    Text(factor.impact > 0 ? "+\(factor.impact)" : "\(factor.impact)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                Text(level).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var level: String {
        switch abs(factor.impact) {
        case 30...: "High impact"
        case 10..<30: "Medium impact"
        default: "Low impact"
        }
    }

    private var symbol: String {
        switch factor.kind {
        case .habit(let kind): kind.symbol
        case .momentum: factor.impact > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis"
        case .experience: "graduationcap.fill"
        }
    }

    private var title: String {
        switch factor.kind {
        case .habit(let kind): kind.habitName
        case .momentum: factor.impact > 0 ? "Improving lately" : "Rough patch lately"
        case .experience: "Building your history"
        }
    }

    private var detail: String {
        switch factor.kind {
        case .habit:
            guard let rate = factor.ratePer10Miles else { return "Costing you points" }
            return rate < 0.05 ? "Rare lately" : String(format: "About %.1f per 10 miles lately", rate)
        case .momentum:
            return "Over your last \(factor.driveCount ?? 0) drives"
        case .experience:
            let n = factor.driveCount ?? 0
            return "Your score is still settling in (\(n) drives so far)"
        }
    }
}

struct FactorList: View {
    let report: CurbsideScoreReport

    var body: some View {
        if report.factors.isEmpty {
            Text(report.scoredDriveCount == 0
                 ? "Once you've driven a few times, this shows what's raising or lowering your score."
                 : "Nothing is moving your score much right now. Keep it up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(report.factors.enumerated()), id: \.offset) { _, factor in
                FactorRow(factor: factor)
            }
        }
    }
}
