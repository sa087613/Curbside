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
                                 startingScore: 660, previous: previous, now: t0.addingTimeInterval(nowDay * day))
    }

    private func reward(_ goal: RewardGoal, _ progress: RewardProgress?) -> ParentReward {
        ParentReward(id: "r", teenID: "teen", teenName: "Riley", createdBy: "mom", createdByName: "Mom",
                     createdAt: t0, goal: goal, prize: .money(20), progress: progress)
    }

    // MARK: Reach

    @Test func reachIsEarnedTheFirstTimeTheScoreGetsThere() {
        let p = evaluate(.reach(750), [point(1, 700), point(3, 752), point(5, 730)], nowDay: 6)
        #expect(p.earnedAt == t0.addingTimeInterval(3 * day))
        #expect(p.currentScore == 730)
        #expect(reward(.reach(750), p).status(now: t0.addingTimeInterval(6 * day)) == .earned(t0.addingTimeInterval(3 * day)))
    }

    @Test func reachIgnoresScoresFromBeforeTheRewardWasSet() {
        let history = [point(1, 760), point(2, 720), point(6, 740)]
        let p = evaluate(.reach(750), history, createdDay: 4, nowDay: 7)
        #expect(p.earnedAt == nil)
        let r = reward(.reach(750), p)
        #expect(r.fraction(now: t0.addingTimeInterval(7 * day)) > 0.9)
        #expect(r.progressDescription(now: t0.addingTimeInterval(7 * day)) == "740 now · 10 to go")
    }

    // MARK: Hold

    @Test func holdNeedsAnUnbrokenRunAboveTheTarget() {
        // Above from day 1, dips on day 10, back above on day 12.
        let history = [point(1, 755), point(5, 770), point(10, 740), point(12, 751)]
        let goal = RewardGoal.hold(750, weeks: 2)

        let day20 = evaluate(goal, history, nowDay: 20)
        #expect(day20.earnedAt == nil)
        #expect(day20.streakStart == t0.addingTimeInterval(12 * day))

        let day26 = evaluate(goal, history, nowDay: 26)
        #expect(day26.earnedAt == t0.addingTimeInterval(26 * day))
    }

    @Test func holdStreakKeepsRunningBetweenDrives() {
        // One drive above the target, then no driving for three weeks: the score never dropped.
        let goal = RewardGoal.hold(750, weeks: 2)
        let p = evaluate(goal, [point(1, 760)], nowDay: 3)
        #expect(p.earnedAt == nil)
        let r = reward(goal, p)
        #expect(r.status(now: t0.addingTimeInterval(10 * day)) == .inProgress)
        #expect(r.progressDescription(now: t0.addingTimeInterval(10 * day)) == "Day 10 of 14 at 750+")
        #expect(r.status(now: t0.addingTimeInterval(16 * day)) == .earned(t0.addingTimeInterval(15 * day)))
    }

    @Test func holdEarnedBeforeADipStaysEarned() {
        let goal = RewardGoal.hold(750, weeks: 1)
        let history = [point(1, 760), point(9, 700)]
        let p = evaluate(goal, history, nowDay: 10)
        #expect(p.earnedAt == t0.addingTimeInterval(8 * day))
        #expect(p.streakStart == nil)
        // Once earned, it's never taken back, even when re-evaluated later.
        let later = evaluate(goal, history + [point(11, 690)], nowDay: 12, previous: p)
        #expect(later.earnedAt == p.earnedAt)
    }

    @Test func holdBelowTargetExplainsHowToStart() {
        let goal = RewardGoal.hold(800, weeks: 4)
        let r = reward(goal, evaluate(goal, [point(1, 712)], nowDay: 2))
        #expect(r.fraction(now: t0.addingTimeInterval(2 * day)) == 0)
        #expect(r.progressDescription(now: t0.addingTimeInterval(2 * day)) == "712 now · reach 800 to start the clock")
    }

    @Test func givenTrumpsEverything() {
        var r = reward(.reach(700), evaluate(.reach(700), [point(1, 710)], nowDay: 2))
        r.givenAt = t0.addingTimeInterval(3 * day)
        #expect(r.status() == .given(t0.addingTimeInterval(3 * day)))
        #expect(r.fraction() == 1)
    }

    @Test func goalAndPrizeText() {
        #expect(RewardGoal.hold(750, weeks: 4).summary == "Hold 750+ for 4 weeks")
        #expect(RewardGoal.hold(750, weeks: 1).summary == "Hold 750+ for 1 week")
        #expect(RewardGoal.reach(700).summary == "Reach 700+")
        #expect(RewardPrize.money(20).title == "$20")
        #expect(RewardPrize.privilege("Later curfew").title == "Later curfew")
        #expect(RewardGoal(kind: .reach, minScore: 700, weeks: 3).weeks == nil)
    }

    // MARK: Tier unlocks

    @Test func tierUnlockCelebratesOnlyTheFirstTime() {
        // 660 start (Fair) → Good → dip to Fair → Good again → Great.
        let h = [point(1, 675), point(2, 660), point(3, 680), point(4, 745)]
        #expect(TierUnlock.newlyReachedTier(history: Array(h.prefix(1)), startingScore: 660) == .good)
        #expect(TierUnlock.newlyReachedTier(history: Array(h.prefix(2)), startingScore: 660) == nil)
        #expect(TierUnlock.newlyReachedTier(history: Array(h.prefix(3)), startingScore: 660) == nil)
        #expect(TierUnlock.newlyReachedTier(history: h, startingScore: 660) == .great)
        #expect(TierUnlock.newlyReachedTier(history: [], startingScore: 660) == nil)
    }

    // MARK: Celebrations wait for the drive to end

    @Test func celebrationsNeverComeOutWhileDriving() {
        var queue = CelebrationQueue<String>()
        queue.enqueue(contentsOf: ["$20 earned", "Great tier unlocked"])
        #expect(queue.next(isDriving: true) == nil)
        #expect(queue.count == 2)
        #expect(queue.next(isDriving: false) == "$20 earned")
        #expect(queue.next(isDriving: true) == nil)
        #expect(queue.next(isDriving: false) == "Great tier unlocked")
        #expect(queue.next(isDriving: false) == nil)
    }

    // MARK: Partner catalog

    @Test func catalogUnlocksByTier() async throws {
        let provider = MockPartnerRewardsProvider()
        let offers = try await provider.offers()
        #expect(PartnerCatalog.unlocked(offers, score: 600).isEmpty)
        #expect(PartnerCatalog.unlocked(offers, score: 680).allSatisfy { $0.requiredTier == .good })
        #expect(PartnerCatalog.unlocked(offers, score: 805).count == offers.count)

        let next = try #require(PartnerCatalog.nextUnlock(offers, score: 712))
        #expect(next.tier == .great && next.pointsNeeded == 28 && next.offers == 3)
        #expect(PartnerCatalog.nextUnlock(offers, score: 820) == nil)
    }

    @Test func lockedOffersCannotBeRedeemed() async throws {
        let provider = MockPartnerRewardsProvider()
        let excellent = try #require(MockPartnerRewardsProvider.catalog.first { $0.requiredTier == .excellent })
        await #expect(throws: PartnerRewardsError.locked(.excellent)) { try await provider.redeem(excellent, score: 760) }
        let code = try await provider.redeem(excellent, score: 812)
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
