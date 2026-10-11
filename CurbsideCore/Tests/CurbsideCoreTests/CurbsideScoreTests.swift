import CurbsideCore
import Foundation
import Testing

@Suite("Curbside Score")
struct CurbsideScoreTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// Two drives a day, 5 miles each, starting at `start`.
    private func drives(_ scores: [Double], from: Date? = nil, miles: Double = 5) -> [ScoredDrive] {
        let base = from ?? start
        return scores.enumerated().map { i, s in
            ScoredDrive(date: base.addingTimeInterval(Double(i) * 43_200), score: s, miles: miles)
        }
    }

    private func report(_ drives: [ScoredDrive], now: Date? = nil) -> CurbsideScoreReport {
        CurbsideScoreReport.compute(drives: drives, now: now ?? (drives.last?.date ?? start))
    }

    // MARK: Brand-new driver

    @Test func brandNewDriverStartsInTheMiddle() {
        let r = report([])
        #expect(r.score == 660)
        #expect(r.tier == .fair)
        #expect(r.history.isEmpty)
        #expect(r.trend.direction == .flat)
        #expect(r.factors.isEmpty)
    }

    @Test func firstDriveMovesTheScoreOnlyALittle() {
        let perfect = report(drives([100]))
        let bad = report(drives([40]))
        #expect(perfect.score > 660 && perfect.score - 660 < 25)
        // New drivers have less history to cushion a bad drive than settled drivers (~25 points).
        #expect(bad.score < 660 && 660 - bad.score < 50)
        // The starting point is what's holding a perfect new driver back.
        #expect(perfect.factors.contains { $0.kind == .experience && $0.impact < 0 })
    }

    @Test func newDriverCannotReachExcellentQuickly() {
        let afterFive = report(drives(Array(repeating: 100, count: 5)))
        let afterTwenty = report(drives(Array(repeating: 100, count: 20)))
        #expect(afterFive.tier < .great)
        #expect(afterTwenty.tier == .excellent)
    }

    // MARK: Steady good driving

    @Test func steadyGoodDrivingRisesGradually() {
        let scores = (0..<40).map { 93 + Double($0 % 3) } // 93, 94, 95, …
        let r = report(drives(scores))
        let values = r.history.map(\.score)
        // Never jumps more than 15 points after any single drive.
        #expect(zip([660] + values, values).allSatisfy { abs($1 - $0) <= 15 })
        // Climbs over time and ends in Great.
        #expect(values[4] < values[19] && values[19] <= values[39])
        #expect(values[4] < 740)
        #expect(r.tier == .great)
        #expect(r.score >= 770 && r.score <= 800)
    }

    // MARK: One bad drive vs a bad streak

    private var settled: [ScoredDrive] { drives(Array(repeating: 95, count: 40)) }

    @Test func oneBadDriveDentsALittle() {
        let before = report(settled).score
        var withBad = settled
        withBad += drives([40], from: withBad.last!.date.addingTimeInterval(43_200))
        let after = report(withBad).score
        let drop = before - after
        #expect(drop >= 10 && drop <= 40)
        #expect(CurbsideTier.tier(for: after) >= .good)

        // Good driving afterwards earns it back.
        withBad += drives(Array(repeating: 95, count: 15), from: withBad.last!.date.addingTimeInterval(43_200))
        #expect(before - report(withBad).score <= 12)
    }

    @Test func badStreakDropsMuchMore() {
        let before = report(settled).score
        let next = settled.last!.date.addingTimeInterval(43_200)
        let single = before - report(settled + drives([40], from: next)).score
        let streak = before - report(settled + drives(Array(repeating: 40, count: 5), from: next)).score
        #expect(streak >= 3 * single)
        #expect(streak >= 80)
    }

    @Test func longBadDriveCountsMoreThanShortErrand() {
        let next = settled.last!.date.addingTimeInterval(43_200)
        let errand = report(settled + drives([40], from: next, miles: 1)).score
        let highway = report(settled + drives([40], from: next, miles: 25)).score
        #expect(errand > highway)
    }

    // MARK: Long break

    @Test func longBreakChangesNothing() {
        let first = drives(Array(repeating: 92, count: 10))
        let second = drives(Array(repeating: 96, count: 10), from: first.last!.date.addingTimeInterval(43_200))
        let gap = TimeInterval(120 * 86_400)
        let secondAfterBreak = second.map { ScoredDrive(id: $0.id, date: $0.date.addingTimeInterval(gap), score: $0.score, miles: $0.miles) }

        #expect(report(first + second).score == report(first + secondAfterBreak).score)

        // Mid-break, a month later, the score is untouched and the arrow is flat.
        let midBreak = report(first, now: first.last!.date.addingTimeInterval(30 * 86_400))
        #expect(midBreak.score == report(first).score)
        #expect(midBreak.trend.direction == .flat)
        #expect(midBreak.trend.delta == 0)
    }

    // MARK: Trend and factors

    @Test func trendComparesWithAWeekAgo() {
        // 30 drives at 80, then a week of 98s.
        let old = drives(Array(repeating: 80, count: 30))
        let weekStart = old.last!.date.addingTimeInterval(86_400)
        let recent = drives(Array(repeating: 98, count: 12), from: weekStart)
        let r = report(old + recent, now: recent.last!.date)
        #expect(r.trend.direction == .up)
        #expect(r.trend.delta == r.score - report(old).score)
        #expect(r.factors.contains { $0.kind == .momentum && $0.impact > 0 })
    }

    @Test func habitFactorsShowWhatCostsPoints() {
        let mixed = (0..<30).map { i in
            ScoredDrive(date: start.addingTimeInterval(Double(i) * 43_200), score: 82, miles: 5, deductions: [
                HabitDeduction(kind: .hardBrake, count: 2, points: 14),
                HabitDeduction(kind: .sharpTurn, count: 1, points: 4),
            ])
        }
        let r = report(mixed)
        let habits = r.factors.filter { if case .habit = $0.kind { return true } else { return false } }
        #expect(habits.first?.kind == .habit(.hardBrake))
        #expect(habits.allSatisfy { $0.impact < 0 })
        #expect(abs(habits.first!.impact) > abs(habits.last!.impact))
        // 2 hard brakes every 5 miles → 4 per 10 miles.
        #expect(abs(habits.first!.ratePer10Miles! - 4) < 1e-6)
    }

    // MARK: Scale and tiers

    @Test func scaleHitsAnchorsAndClamps() {
        #expect(CurbsideScale.score(forAverage: 0) == 300)
        #expect(CurbsideScale.score(forAverage: 40) == 300)
        #expect(CurbsideScale.score(forAverage: 70) == 580)
        #expect(CurbsideScale.score(forAverage: 80) == 660)
        #expect(CurbsideScale.score(forAverage: 95) == 800)
        #expect(CurbsideScale.score(forAverage: 100) == 850)
        let samples = stride(from: 0.0, through: 100, by: 0.5).map { CurbsideScale.score(forAverage: $0) }
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func tiersCoverTheWholeRange() {
        #expect(CurbsideTier.tier(for: 300) == .needsWork)
        #expect(CurbsideTier.tier(for: 579) == .needsWork)
        #expect(CurbsideTier.tier(for: 580) == .fair)
        #expect(CurbsideTier.tier(for: 670) == .good)
        #expect(CurbsideTier.tier(for: 740) == .great)
        #expect(CurbsideTier.tier(for: 800) == .excellent)
        #expect(CurbsideTier.tier(for: 850) == .excellent)
        let covered = CurbsideTier.allCases.map { $0.range().count }.reduce(0, +)
        #expect(covered == 551)
    }

    @Test func orderOfInputDoesNotMatter() {
        let d = drives([90, 60, 99, 75, 88])
        #expect(report(d) == report(d.reversed()))
    }
}
