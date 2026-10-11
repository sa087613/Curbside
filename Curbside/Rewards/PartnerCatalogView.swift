import CurbsideCore
import SwiftUI

/// Partner offers grouped by the tier that unlocks them. Mock data: placeholder partners, SF Symbols, no logos.
struct PartnerCatalogSection: View {
    let score: Int
    @Environment(RewardsCenter.self) private var center
    @State private var selected: PartnerOffer?

    var body: some View {
        let offers = center.offers
        let tier = CurbsideTier.tier(for: score)
        VStack(alignment: .leading, spacing: 12) {
            Text("Partner rewards").font(.title3.weight(.bold))

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your score: \(score)").font(.headline).monospacedDigit()
                        TierBadge(tier: tier)
                    }
                    if let next = PartnerCatalog.nextUnlock(offers, score: score) {
                        Text("\(next.pointsNeeded) more points to \(next.tier.displayName) unlocks \(next.offers) more.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        GlassProgressBar(value: Double(score - CurbsideScale.minimum)
                                         / Double(next.tier.range().lowerBound - CurbsideScale.minimum))
                    } else if !offers.isEmpty {
                        Text("Everything's unlocked. Keep it up!").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(PartnerCatalog.unlockTiers(offers), id: \.self) { unlockTier in
                let unlocked = tier >= unlockTier
                HStack(spacing: 6) {
                    Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                    Text("\(unlockTier.displayName) · \(unlockTier.range().lowerBound)+")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(unlocked ? Color.primary : Color.secondary)
                .padding(.top, 4)

                ForEach(offers.filter { $0.requiredTier == unlockTier }) { offer in
                    Button {
                        selected = offer
                    } label: {
                        OfferRow(offer: offer, unlocked: unlocked)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Sample offers from made-up partners, for testing. Curbside has no real partnerships yet, and these can't be redeemed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $selected) { offer in
            OfferDetailSheet(offer: offer, score: score)
        }
    }
}

private struct OfferRow: View {
    let offer: PartnerOffer
    let unlocked: Bool

    var body: some View {
        HStack(spacing: 14) {
            OfferIcon(offer: offer)
                .saturation(unlocked ? 1 : 0)
                .opacity(unlocked ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.partnerName).font(.caption).foregroundStyle(.secondary)
                Text(offer.title).font(.subheadline.weight(.semibold))
                Text(offer.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if unlocked {
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            } else {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityLabel("Locked")
            }
        }
        .padding(12)
        .glassCard(radius: DS.Radius.row, padding: nil)
        .accessibilityElement(children: .combine)
    }
}

/// Category-colored tile with an SF Symbol, used instead of partner logos.
struct OfferIcon: View {
    let offer: PartnerOffer
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: offer.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }

    private var color: Color {
        DS.categoryColor(offer.category)
    }
}

private struct OfferDetailSheet: View {
    let offer: PartnerOffer
    let score: Int
    @Environment(RewardsCenter.self) private var center
    @Environment(\.dismiss) private var dismiss
    @State private var code: RedemptionCode?
    @State private var error: String?

    var body: some View {
        let unlocked = PartnerCatalog.isUnlocked(offer, score: score)
        NavigationStack {
            VStack(spacing: 18) {
                OfferIcon(offer: offer, size: 84)
                VStack(spacing: 4) {
                    Text(offer.partnerName).font(.subheadline).foregroundStyle(.secondary)
                    Text(offer.title).font(.title2.weight(.bold))
                    Text(offer.detail).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                if let code {
                    VStack(spacing: 6) {
                        Text(code.code)
                            .font(.system(.title, design: .monospaced).weight(.bold))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .glassCard(radius: 12, padding: nil)
                        Text(code.instructions).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                } else if unlocked {
                    Button {
                        Task {
                            do { code = try await center.provider.redeem(offer, score: score) }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        Text("Show code").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.primary)
                } else {
                    Label("Unlocks at \(offer.requiredTier.displayName) (\(offer.requiredTier.range().lowerBound)+). You're at \(score).",
                          systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.caption).foregroundStyle(DS.Palette.coral) }
                Text("Sample offer · not a real partnership")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(DS.Palette.accent.opacity(0.25), in: Capsule())
                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
