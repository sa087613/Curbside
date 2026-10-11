import CurbsideCore
import SwiftUI

/// Shows exactly what sharing means, including a live preview built from the user's own data with the
/// same views parents see. Content comes from `SharingDisclosure`, which a test ties to the uploaded fields.
struct ConsentView: View {
    enum Mode {
        /// Must choose before continuing (after joining).
        case firstTime
        /// Turning sharing back on from Settings.
        case review
        /// Read-only reminder of what's shared.
        case info
    }

    let role: FamilyRole
    let mode: Mode
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let disclosure = SharingDisclosure.forRole(role)
        let parentNames = store.members.filter { $0.role == .parent && $0.id != store.me?.id }.map(\.displayName)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(mode == .info ? "What you share" : "Share your driving with your family?")
                        .font(.title2.weight(.bold))
                    Text("If you agree, \(audience(parentNames, fallback: disclosure.audience)) will see:")
                        .foregroundStyle(.secondary)
                }

                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(disclosure.shared) { item in
                            DisclosureRow(item: item, tint: DS.Palette.accent)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Exactly what they'll see").font(.headline)
                    Text("This is built from your own data, using the same screens parents use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ParentPreview(name: store.me?.displayName ?? "You",
                                  standing: store.currentStanding(),
                                  drive: store.latestSharedDrive())
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Never shared").font(.headline)
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(disclosure.neverShared) { item in
                                DisclosureRow(item: item, tint: .secondary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("You're in control").font(.headline)
                    ForEach(disclosure.controls, id: \.self) { line in
                        Label(line, systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }

                if mode != .info {
                    VStack(spacing: 10) {
                        Button {
                            Task {
                                await store.setSharing(true)
                                if mode == .review { dismiss() }
                            }
                        } label: {
                            Text("I agree, share with my family")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.primary)
                        .disabled(store.isWorking)

                        Button {
                            Task {
                                if mode == .firstTime { await store.setSharing(false) }
                                dismiss()
                            }
                        } label: {
                            Text("Not now")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(store.isWorking)

                        if role == .teen {
                            Text("If you choose Not now, you'll still be in the family, but parents and the leaderboard won't see your score or drives.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(mode == .info ? "What you share" : "Sharing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func audience(_ names: [String], fallback: String) -> String {
        guard !names.isEmpty else { return fallback }
        let list = ListFormatter.localizedString(byJoining: names)
        return role == .teen ? list : "\(list) (teens only see your score on the leaderboard)"
    }
}

private struct DisclosureRow: View {
    let item: SharingDisclosure.Item
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The teen card and latest drive exactly as a parent's dashboard renders them.
private struct ParentPreview: View {
    let name: String
    let standing: SharedStanding?
    let drive: SharedDrive?

    var body: some View {
        VStack(spacing: 12) {
            MemberStandingCard(name: name, role: .teen, sharing: true, standing: standing)
            if let drive {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SharedDriveRow(drive: drive)
                        SharedDriveMap(drive: drive)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                Text("Your drives will appear here once you've recorded one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}
