import CurbsideCore
import Foundation
import Observation
import SwiftData

enum Celebration: Identifiable, Equatable {
    /// A parent-set reward was just earned.
    case reward(ParentReward)
    /// The score reached a new tier for the first time, unlocking partner offers.
    case tier(CurbsideTier, offers: Int)

    var id: String {
        switch self {
        case .reward(let r): "reward-\(r.id)"
        case .tier(let t, _): "tier-\(t.rawValue)"
        }
    }
}

/// Partner catalog plus post-drive celebrations.
///
/// Celebrations are only *detected* when a drive is saved, and only *shown* once recording has
/// fully stopped (`CelebrationQueue` refuses while `isDriving` is true).
@MainActor
@Observable
final class RewardsCenter {
    private(set) var offers: [PartnerOffer] = []
    private(set) var current: Celebration?

    @ObservationIgnored let provider: PartnerRewardsProvider
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var queue = CelebrationQueue<Celebration>()
    /// Asked before showing anything; true while a drive is recording or saving.
    @ObservationIgnored var isDriving: () -> Bool = { false }

    init(container: ModelContainer, provider: PartnerRewardsProvider = MockPartnerRewardsProvider()) {
        self.container = container
        self.provider = provider
    }

    func loadOffers() async {
        if let loaded = try? await provider.offers() { offers = loaded }
    }

    /// Called after each drive is saved, with any parent rewards it newly earned.
    func driveEnded(earned: [ParentReward]) {
        queue.enqueue(contentsOf: earned.map(Celebration.reward))
        let drives = (try? container.mainContext.fetch(FetchDescriptor<Drive>())) ?? []
        let report = CurbsideScoreReport.from(drives)
        let start = Int(CurbsideScale.score(forAverage: CurbsideScoreConfig.default.priorDriveScore).rounded())
        if let tier = TierUnlock.newlyReachedTier(history: report.history, startingScore: start) {
            let count = offers.filter { $0.requiredTier == tier }.count
            if count > 0 { queue.enqueue(.tier(tier, offers: count)) }
        }
        showNextSoon()
    }

    func dismissCurrent() {
        current = nil
        showNextSoon()
    }

    /// Shows the next celebration after a short pause (lets the post-drive summary appear first).
    func showNextSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard current == nil, let next = queue.next(isDriving: isDriving()) else { return }
            current = next
        }
    }
}
