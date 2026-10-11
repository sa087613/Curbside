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
        #expect(r.score == 65)
        #expect(r.tier == .silver)
        #expect(r.history.isEmpty)
        #expect(r.trend.direction == .flat)
        #expect(r.factors.isEmpty)
    }

    @Test func firstDriveMovesTheScoreOnlyALittle() {
        let perfect = report(drives([100]))
        let bad = report(drives([40]))
        #expect(perfect.score > 65 && perfect.score - 65 <= 5)
        // New drivers have less history to cushion a bad drive than settled drivers (~6 points).
        #expect(bad.score < 65 && 65 - bad.score <= 11)
        // One rough first drive doesn't drop a new driver to Bronze… by much.
        #expect(bad.score >= 50)
        // The starting point is what's holding a perfect new driver back.
        #expect(perfect.factors.contains { $0.kind == .experience && $0.impact < 0 })
    }

    @Test func newDriverCannotReachPlatinumQuickly() {
        let afterFive = report(drives(Array(repeating: 100, count: 5)))
        let afterTwenty = report(drives(Array(repeating: 100, count: 20)))
        #expect(afterFive.tier < .gold)
        #expect(afterTwenty.tier == .platinum)
    }

    // MARK: Steady good driving

    @Test func steadyGoodDrivingRisesGradually() {
        let scores = (0..<40).map { 93 + Double($0 % 3) } // 93, 94, 95, …
        let r = report(drives(scores))
        let values = r.history.map(\.score)
        // Never jumps more than 3 points after any single drive.
        #expect(zip([65] + values, values).allSatisfy { abs($1 - $0) <= 3 })
        // Climbs over time and ends in Gold.
        #expect(values[4] < values[19] && values[19] <= values[39])
        #expect(values[4] < 80)
        #expect(r.tier == .gold)
        #expect(r.score >= 84 && r.score <= 89)
    }

    // MARK: One bad drive vs a bad streak

    private var settled: [ScoredDrive] { drives(Array(repeating: 95, count: 40)) }

    @Test func oneBadDriveDentsALittle() {
        let before = report(settled).score
        var withBad = settled
        withBad += drives([40], from: withBad.last!.date.addingTimeInterval(43_200))
        let after = report(withBad).score
        let drop = before - after
        #expect(drop >= 2 && drop <= 8)
        #expect(CurbsideTier.tier(for: after) >= .gold)

        // Good driving afterwards earns it back.
        withBad += drives(Array(repeating: 95, count: 15), from: withBad.last!.date.addingTimeInterval(43_200))
        #expect(before - report(withBad).score <= 2)
    }

    @Test func badStreakDropsMuchMore() {
        let before = report(settled).score
        let next = settled.last!.date.addingTimeInterval(43_200)
        let single = before - report(settled + drives([40], from: next)).score
        let streak = before - report(settled + drives(Array(repeating: 40, count: 5), from: next)).score
        #expect(streak >= 3 * single)
        #expect(streak >= 15)
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
        #expect(CurbsideScale.score(forAverage: 0) == 0)
        #expect(CurbsideScale.score(forAverage: 50) == 0)
        #expect(CurbsideScale.score(forAverage: 80) == 65)
        #expect(CurbsideScale.score(forAverage: 90) == 80)
        #expect(CurbsideScale.score(forAverage: 95) == 90)
        #expect(CurbsideScale.score(forAverage: 100) == 100)
        let samples = stride(from: 0.0, through: 100, by: 0.5).map { CurbsideScale.score(forAverage: $0) }
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func tiersCoverTheWholeRange() {
        #expect(CurbsideTier.tier(for: 0) == .bronze)
        #expect(CurbsideTier.tier(for: 59) == .bronze)
        #expect(CurbsideTier.tier(for: 60) == .silver)
        #expect(CurbsideTier.tier(for: 79) == .silver)
        #expect(CurbsideTier.tier(for: 80) == .gold)
        #expect(CurbsideTier.tier(for: 89) == .gold)
        #expect(CurbsideTier.tier(for: 90) == .platinum)
        #expect(CurbsideTier.tier(for: 100) == .platinum)
        let covered = CurbsideTier.allCases.map { $0.range().count }.reduce(0, +)
        #expect(covered == 101)
    }

    /// The mapping table agreed on for the redesign (average drive score → Curbside Score).
    @Test func mappingTable() {
        let table: [(Double, Int, CurbsideTier)] = [
            (50, 0, .bronze), (70, 43, .bronze), (77.7, 60, .silver), (80, 65, .silver), (85, 73, .silver),
            (90, 80, .gold), (92, 84, .gold), (95, 90, .platinum), (98, 96, .platinum), (100, 100, .platinum),
        ]
        for (average, score, tier) in table {
            let s = Int(CurbsideScale.score(forAverage: average).rounded())
            #expect(s == score, "average \(average)")
            #expect(CurbsideTier.tier(for: s) == tier, "average \(average)")
        }
    }

    @Test func legacyScoresConvert() {
        #expect(CurbsideScale.fromLegacy(660) == 65)
        #expect(CurbsideScale.fromLegacy(750) == 80)
        #expect(CurbsideScale.fromLegacy(800) == 90)
        #expect(CurbsideScale.fromLegacy(850) == 100)
        #expect(CurbsideScale.fromLegacy(300) == 0)
        #expect(CurbsideScale.fromLegacy(84) == 84) // already new
    }

    @Test func legacyRewardGoalsConvertWhenDecoded() throws {
        let json = #"{"kind":"hold","minScore":750,"weeks":4}"#.data(using: .utf8)!
        let goal = try JSONDecoder().decode(RewardGoal.self, from: json)
        #expect(goal == .hold(80, weeks: 4))
        let fresh = try JSONDecoder().decode(RewardGoal.self, from: JSONEncoder().encode(RewardGoal.reach(85)))
        #expect(fresh == .reach(85))
    }

    @Test func orderOfInputDoesNotMatter() {
        let d = drives([90, 60, 99, 75, 88])
        #expect(report(d) == report(d.reversed()))
    }
}
