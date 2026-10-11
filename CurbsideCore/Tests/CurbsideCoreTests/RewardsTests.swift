import CurbsideCore
import Foundation
import Testing

@Suite("Rewards")
struct RewardsTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 86_400

    private func point(_ days: Double, _ score: Int) -> CurbsideScorePoint {
        CurbsideScorePoint(date: t0.addingTimeInterval(days * day), driveID: UUID(), score: score, exactScore: Double(score))
    }

    private func evaluate(_ goal: RewardGoal, _ history: [CurbsideScorePoint], createdDay: Double = 0, nowDay: Double,
                          previous: RewardProgress? = nil) -> RewardProgress {
        RewardEvaluator.progress(for: goal, createdAt: t0.addingTimeInterval(createdDay * day), history: history,
                                 startingScore: 65, previous: previous, now: t0.addingTimeInterval(nowDay * day))
    }

    private func reward(_ goal: RewardGoal, _ progress: RewardProgress?) -> ParentReward {
        ParentReward(id: "r", teenID: "teen", teenName: "Riley", createdBy: "mom", createdByName: "Mom",
                     createdAt: t0, goal: goal, prize: .money(20), progress: progress)
    }

    // MARK: Reach

    @Test func reachIsEarnedTheFirstTimeTheScoreGetsThere() {
        let p = evaluate(.reach(80), [point(1, 75), point(3, 82), point(5, 78)], nowDay: 6)
        #expect(p.earnedAt == t0.addingTimeInterval(3 * day))
        #expect(p.currentScore == 78)
        #expect(reward(.reach(80), p).status(now: t0.addingTimeInterval(6 * day)) == .earned(t0.addingTimeInterval(3 * day)))
    }

    @Test func reachIgnoresScoresFromBeforeTheRewardWasSet() {
        let history = [point(1, 84), point(2, 76), point(6, 79)]
        let p = evaluate(.reach(80), history, createdDay: 4, nowDay: 7)
        #expect(p.earnedAt == nil)
        let r = reward(.reach(80), p)
        #expect(r.fraction(now: t0.addingTimeInterval(7 * day)) > 0.9)
        #expect(r.progressDescription(now: t0.addingTimeInterval(7 * day)) == "79 now · 1 to go")
    }

    // MARK: Hold

    @Test func holdNeedsAnUnbrokenRunAboveTheTarget() {
        // Above from day 1, dips on day 10, back above on day 12.
        let history = [point(1, 83), point(5, 86), point(10, 79), point(12, 81)]
        let goal = RewardGoal.hold(80, weeks: 2)

        let day20 = evaluate(goal, history, nowDay: 20)
        #expect(day20.earnedAt == nil)
        #expect(day20.streakStart == t0.addingTimeInterval(12 * day))

        let day26 = evaluate(goal, history, nowDay: 26)
        #expect(day26.earnedAt == t0.addingTimeInterval(26 * day))
    }

    @Test func holdStreakKeepsRunningBetweenDrives() {
        // One drive above the target, then no driving for three weeks: the score never dropped.
        let goal = RewardGoal.hold(80, weeks: 2)
        let p = evaluate(goal, [point(1, 84)], nowDay: 3)
        #expect(p.earnedAt == nil)
        let r = reward(goal, p)
        #expect(r.status(now: t0.addingTimeInterval(10 * day)) == .inProgress)
        #expect(r.progressDescription(now: t0.addingTimeInterval(10 * day)) == "Day 10 of 14 at 80+")
        #expect(r.status(now: t0.addingTimeInterval(16 * day)) == .earned(t0.addingTimeInterval(15 * day)))
    }

    @Test func holdEarnedBeforeADipStaysEarned() {
        let goal = RewardGoal.hold(80, weeks: 1)
        let history = [point(1, 84), point(9, 75)]
        let p = evaluate(goal, history, nowDay: 10)
        #expect(p.earnedAt == t0.addingTimeInterval(8 * day))
        #expect(p.streakStart == nil)
        // Once earned, it's never taken back, even when re-evaluated later.
        let later = evaluate(goal, history + [point(11, 70)], nowDay: 12, previous: p)
        #expect(later.earnedAt == p.earnedAt)
    }

    @Test func holdBelowTargetExplainsHowToStart() {
        let goal = RewardGoal.hold(90, weeks: 4)
        let r = reward(goal, evaluate(goal, [point(1, 77)], nowDay: 2))
        #expect(r.fraction(now: t0.addingTimeInterval(2 * day)) == 0)
        #expect(r.progressDescription(now: t0.addingTimeInterval(2 * day)) == "77 now · reach 90 to start the clock")
    }

    @Test func givenTrumpsEverything() {
        var r = reward(.reach(75), evaluate(.reach(75), [point(1, 76)], nowDay: 2))
        r.givenAt = t0.addingTimeInterval(3 * day)
        #expect(r.status() == .given(t0.addingTimeInterval(3 * day)))
        #expect(r.fraction() == 1)
    }

    @Test func goalAndPrizeText() {
        #expect(RewardGoal.hold(80, weeks: 4).summary == "Hold 80+ for 4 weeks")
        #expect(RewardGoal.hold(80, weeks: 1).summary == "Hold 80+ for 1 week")
        #expect(RewardGoal.reach(75).summary == "Reach 75+")
        #expect(RewardPrize.money(20).title == "$20")
        #expect(RewardPrize.privilege("Later curfew").title == "Later curfew")
        #expect(RewardGoal(kind: .reach, minScore: 75, weeks: 3).weeks == nil)
    }

    // MARK: Tier unlocks

    @Test func tierUnlockCelebratesOnlyTheFirstTime() {
        // 65 start (Silver) → Gold → dip to Silver → Gold again → Platinum.
        let h = [point(1, 81), point(2, 77), point(3, 82), point(4, 91)]
        #expect(TierUnlock.newlyReachedTier(history: Array(h.prefix(1)), startingScore: 65) == .gold)
        #expect(TierUnlock.newlyReachedTier(history: Array(h.prefix(2)), startingScore: 660) == nil)
        #expect(TierUnlock.newlyReachedTier(history: Array(h.prefix(3)), startingScore: 660) == nil)
        #expect(TierUnlock.newlyReachedTier(history: h, startingScore: 65) == .platinum)
        #expect(TierUnlock.newlyReachedTier(history: [], startingScore: 660) == nil)
    }

    // MARK: Celebrations wait for the drive to end

    @Test func celebrationsNeverComeOutWhileDriving() {
        var queue = CelebrationQueue<String>()
        queue.enqueue(contentsOf: ["$20 earned", "Gold tier unlocked"])
        #expect(queue.next(isDriving: true) == nil)
        #expect(queue.count == 2)
        #expect(queue.next(isDriving: false) == "$20 earned")
        #expect(queue.next(isDriving: true) == nil)
        #expect(queue.next(isDriving: false) == "Gold tier unlocked")
        #expect(queue.next(isDriving: false) == nil)
    }

    // MARK: Partner catalog

    @Test func catalogUnlocksByTier() async throws {
        let provider = MockPartnerRewardsProvider()
        let offers = try await provider.offers()
        #expect(PartnerCatalog.unlocked(offers, score: 55).isEmpty)
        #expect(PartnerCatalog.unlocked(offers, score: 70).allSatisfy { $0.requiredTier == .silver })
        #expect(PartnerCatalog.unlocked(offers, score: 92).count == offers.count)

        let next = try #require(PartnerCatalog.nextUnlock(offers, score: 74))
        #expect(next.tier == .gold && next.pointsNeeded == 6 && next.offers == 3)
        #expect(PartnerCatalog.nextUnlock(offers, score: 95) == nil)
    }

    @Test func lockedOffersCannotBeRedeemed() async throws {
        let provider = MockPartnerRewardsProvider()
        let platinum = try #require(MockPartnerRewardsProvider.catalog.first { $0.requiredTier == .platinum })
        await #expect(throws: PartnerRewardsError.locked(.platinum)) { try await provider.redeem(platinum, score: 84) }
        let code = try await provider.redeem(platinum, score: 93)
        #expect(code.isSample && code.code.hasPrefix("SAMPLE-"))
    }

    @Test func mockCatalogIsClearlyFictional() {
        let realBrands = ["sephora", "taco bell", "starbucks", "chipotle", "ulta", "mcdonald", "amc", "nike",
                          "shell", "chevron", "exxon", "target", "walmart", "dunkin", "jamba"]
        for offer in MockPartnerRewardsProvider.catalog {
            #expect(offer.isSample)
            #expect(!realBrands.contains { offer.partnerName.lowercased().contains($0) }, "\(offer.partnerName)")
        }
    }
}
