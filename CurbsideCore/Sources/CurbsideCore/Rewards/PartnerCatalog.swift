import Foundation

/// A partner offer that unlocks at a Curbside Score tier.
public struct PartnerOffer: Codable, Sendable, Equatable, Identifiable {
    public enum Category: String, Codable, Sendable, CaseIterable {
        case food, beauty, entertainment, retail, car

        public var displayName: String {
            switch self {
            case .food: "Food & drink"
            case .beauty: "Beauty"
            case .entertainment: "Fun"
            case .retail: "Shopping"
            case .car: "Car"
            }
        }
    }

    public var id: String
    public var partnerName: String
    public var title: String
    public var detail: String
    public var category: Category
    public var requiredTier: CurbsideTier
    /// SF Symbol shown instead of a logo.
    public var symbol: String
    /// Mock data: not a real partnership, not redeemable.
    public var isSample: Bool

    public init(id: String, partnerName: String, title: String, detail: String, category: Category,
                requiredTier: CurbsideTier, symbol: String, isSample: Bool) {
        self.id = id
        self.partnerName = partnerName
        self.title = title
        self.detail = detail
        self.category = category
        self.requiredTier = requiredTier
        self.symbol = symbol
        self.isSample = isSample
    }
}

extension CurbsideTier: Codable {}

public struct RedemptionCode: Sendable, Equatable {
    public var code: String
    public var instructions: String
    public var isSample: Bool
}

public enum PartnerRewardsError: LocalizedError, Equatable {
    case locked(CurbsideTier)

    public var errorDescription: String? {
        switch self {
        case .locked(let tier): "This unlocks at \(tier.displayName) (\(tier.range().lowerBound)+)."
        }
    }
}

/// Source of partner offers. Mock today; a real partner backend can replace it without touching the UI.
public protocol PartnerRewardsProvider: Sendable {
    func offers() async throws -> [PartnerOffer]
    /// Fails with `PartnerRewardsError.locked` if the member's tier is too low.
    func redeem(_ offer: PartnerOffer, score: Int) async throws -> RedemptionCode
}

public enum PartnerCatalog {
    /// Tiers that have partner offers, lowest first.
    public static func unlockTiers(_ offers: [PartnerOffer]) -> [CurbsideTier] {
        Array(Set(offers.map(\.requiredTier))).sorted()
    }

    public static func isUnlocked(_ offer: PartnerOffer, score: Int) -> Bool {
        CurbsideTier.tier(for: score) >= offer.requiredTier
    }

    public static func unlocked(_ offers: [PartnerOffer], score: Int) -> [PartnerOffer] {
        offers.filter { isUnlocked($0, score: score) }
    }

    /// The next tier with offers above the current score, and the points needed to get there.
    public static func nextUnlock(_ offers: [PartnerOffer], score: Int) -> (tier: CurbsideTier, pointsNeeded: Int, offers: Int)? {
        let current = CurbsideTier.tier(for: score)
        guard let tier = unlockTiers(offers).first(where: { $0 > current }) else { return nil }
        return (tier, tier.range().lowerBound - score, offers.filter { $0.requiredTier == tier }.count)
    }
}

/// Fictional placeholder partners, clearly marked as samples. No real brands, no logos.
public struct MockPartnerRewardsProvider: PartnerRewardsProvider {
    public init() {}

    public static let catalog: [PartnerOffer] = [
        PartnerOffer(id: "sunrise-coffee", partnerName: "Sunrise Coffee Co.", title: "Free size upgrade",
                     detail: "Any drink, any size, one upgrade.", category: .food, requiredTier: .silver,
                     symbol: "cup.and.saucer.fill", isSample: true),
        PartnerOffer(id: "pixel-cinema", partnerName: "Pixel Cinema", title: "$2 off a movie ticket",
                     detail: "Any showing, any day.", category: .entertainment, requiredTier: .silver,
                     symbol: "film.fill", isSample: true),
        PartnerOffer(id: "fresh-squeeze", partnerName: "Fresh Squeeze Juice", title: "Second smoothie half off",
                     detail: "Bring a friend.", category: .food, requiredTier: .silver,
                     symbol: "takeoutbag.and.cup.and.straw.fill", isSample: true),
        PartnerOffer(id: "glow-beauty", partnerName: "Glow Beauty Bar", title: "15% off skincare",
                     detail: "In store or online.", category: .beauty, requiredTier: .gold,
                     symbol: "sparkles", isSample: true),
        PartnerOffer(id: "taco-rocket", partnerName: "Taco Rocket", title: "Free taco",
                     detail: "With any order.", category: .food, requiredTier: .gold,
                     symbol: "fork.knife", isSample: true),
        PartnerOffer(id: "gear-up", partnerName: "Gear Up Sports", title: "10% off",
                     detail: "Shoes and gear.", category: .retail, requiredTier: .gold,
                     symbol: "figure.run", isSample: true),
        PartnerOffer(id: "fuelstop", partnerName: "FuelStop", title: "10¢ off per gallon",
                     detail: "Up to 15 gallons.", category: .car, requiredTier: .platinum,
                     symbol: "fuelpump.fill", isSample: true),
        PartnerOffer(id: "arcade-galaxy", partnerName: "Arcade Galaxy", title: "$10 game card",
                     detail: "Play anything in the arcade.", category: .entertainment, requiredTier: .platinum,
                     symbol: "gamecontroller.fill", isSample: true),
        PartnerOffer(id: "road-ready", partnerName: "Road Ready Car Spa", title: "Free car wash",
                     detail: "Exterior wash and dry.", category: .car, requiredTier: .platinum,
                     symbol: "car.side.fill", isSample: true),
    ]

    public func offers() async throws -> [PartnerOffer] { Self.catalog }

    public func redeem(_ offer: PartnerOffer, score: Int) async throws -> RedemptionCode {
        guard PartnerCatalog.isUnlocked(offer, score: score) else { throw PartnerRewardsError.locked(offer.requiredTier) }
        let suffix = String(offer.id.uppercased().filter(\.isLetter).prefix(4))
        return RedemptionCode(code: "SAMPLE-\(suffix)",
                              instructions: "Sample offer for testing. Not a real partnership and not redeemable.",
                              isSample: true)
    }
}
