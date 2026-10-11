import CurbsideCore
import SwiftUI

/// The family once set up: family tree, leaderboard, parent dashboard, invites.
struct FamilyHomeView: View {
    @Environment(FamilyStore.self) private var store
    @State private var showInvite = false
    @State private var showConsent = false

    var body: some View {
        let entries = store.leaderboard
        ScrollView {
            VStack(spacing: 16) {
                if let me = store.me, !me.sharing {
                    NotSharingBanner { showConsent = true }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.family?.name ?? "Family").font(.headline)
                        FamilyTreeView(entries: entries)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leaderboard").font(.headline)
                        Text("Ranked by Curbside Score").font(.caption).foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                        ForEach(entries) { entry in
                            LeaderboardRow(entry: entry)
                            if entry.id != entries.last?.id { Divider() }
                        }
                    }
                }

                if store.isParent {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Your teens").font(.title3.weight(.bold))
                            Spacer()
                            Button {
                                showInvite = true
                            } label: {
                                Label("Invite", systemImage: "person.badge.plus")
                            }
                        }
                        if store.teens.isEmpty {
                            Card {
                                Text("No teens yet. Tap Invite to get a code they can enter in Curbside.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(store.teens) { teen in
                            NavigationLink {
                                TeenDetailView(member: teen)
                            } label: {
                                MemberStandingCard(name: teen.displayName, role: .teen, sharing: teen.sharing,
                                                   standing: teen.standing, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Family")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    FamilySettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Family settings")
            }
        }
        .sheet(isPresented: $showInvite) { InviteSheet() }
        .sheet(isPresented: $showConsent) {
            if let role = store.myRole {
                NavigationStack { ConsentView(role: role, mode: .review) }
            }
        }
        .refreshable { await store.republishStanding() }
    }
}

private struct NotSharingBanner: View {
    var review: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're not sharing").font(.subheadline.weight(.semibold))
                Text("Your family can't see your score or drives.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review", action: review).buttonStyle(.bordered)
        }
        .padding(14)
        .glassCard(radius: DS.Radius.row, padding: nil)
    }
}

// MARK: - Family tree

/// Parents on top, teens below, joined by lines, each with their score. The leader wears a crown.
struct FamilyTreeView: View {
    let entries: [LeaderboardEntry]

    var body: some View {
        let parents = entries.filter { $0.member.role == .parent }
        let teens = entries.filter { $0.member.role == .teen }
        VStack(spacing: 0) {
            NodeRow(entries: parents)
            if !parents.isEmpty && !teens.isEmpty {
                Connector(top: parents.count, bottom: teens.count)
                    .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(height: 34)
            }
            NodeRow(entries: teens)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private struct NodeRow: View {
        let entries: [LeaderboardEntry]

        var body: some View {
            HStack(alignment: .top, spacing: 0) {
                ForEach(entries) { entry in
                    TreeNode(entry: entry).frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Lines from the middle of the parents' row down to each teen.
    private struct Connector: Shape {
        let top: Int
        let bottom: Int

        func path(in rect: CGRect) -> Path {
            var p = Path()
            func x(_ i: Int, of n: Int) -> CGFloat { rect.width * (CGFloat(i) + 0.5) / CGFloat(n) }
            let midY = rect.midY
            let topXs = (0..<top).map { x($0, of: top) }
            let bottomXs = (0..<bottom).map { x($0, of: bottom) }
            for tx in topXs {
                p.move(to: CGPoint(x: tx, y: rect.minY))
                p.addLine(to: CGPoint(x: tx, y: midY))
            }
            let xs = topXs + bottomXs
            p.move(to: CGPoint(x: xs.min()!, y: midY))
            p.addLine(to: CGPoint(x: xs.max()!, y: midY))
            for bx in bottomXs {
                p.move(to: CGPoint(x: bx, y: midY))
                p.addLine(to: CGPoint(x: bx, y: rect.maxY))
            }
            return p
        }
    }
}

private struct TreeNode: View {
    let entry: LeaderboardEntry

    var body: some View {
        let m = entry.member
        VStack(spacing: 4) {
            ZStack(alignment: .top) {
                Avatar(name: m.displayName, tier: m.standing?.tier, size: 52)
                    .overlay(Circle().stroke(m.isMe ? DS.Palette.accent : .clear, lineWidth: 3))
                if entry.rank == 1 {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.accent)
                        .shadow(radius: 1)
                        .offset(y: -12)
                        .accessibilityLabel("Leader")
                }
            }
            Text(m.isMe ? "\(m.displayName) (you)" : m.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(m.standing.map { "\($0.score)" } ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Avatar: View {
    let name: String
    let tier: CurbsideTier?
    var size: CGFloat = 40

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tier?.color ?? Color.secondary.opacity(0.5), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Leaderboard

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        let m = entry.member
        HStack(spacing: 12) {
            Text(entry.rank.map { "\($0)" } ?? "–")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Avatar(name: m.displayName, tier: m.standing?.tier, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.isMe ? "\(m.displayName) (you)" : m.displayName).font(.subheadline.weight(.semibold))
                Text(m.role.displayName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let s = m.standing {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(s.score)").font(.headline.monospacedDigit())
                    HStack(spacing: 3) {
                        TrendArrow(delta: s.trendDelta)
                        Text(s.tier.displayName)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Not sharing").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct TrendArrow: View {
    let delta: Int

    var body: some View {
        switch ScoreTrend(delta: delta).direction {
        case .up: Image(systemName: "arrow.up.right").foregroundStyle(DS.Palette.good).accessibilityLabel("up \(delta)")
        case .down: Image(systemName: "arrow.down.right").foregroundStyle(DS.Palette.coral).accessibilityLabel("down \(-delta)")
        case .flat: Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityLabel("steady")
        }
    }
}

// MARK: - Invite

private struct InviteSheet: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var role: FamilyRole = .teen
    @State private var invite: InviteInfo?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Who are you inviting?", selection: $role) {
                    Text("A teen").tag(FamilyRole.teen)
                    Text("Another parent").tag(FamilyRole.parent)
                }
                .pickerStyle(.segmented)

                if let invite {
                    VStack(spacing: 8) {
                        Text("Invite code").font(.subheadline).foregroundStyle(.secondary)
                        Text(InviteCode.display(invite.code))
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Works until \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted)). Anyone with it can join as a \(invite.role.displayName.lowercased()), so only send it to family.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    ShareLink(item: "Join \(invite.familyName) on Curbside: open the Family tab and enter code \(InviteCode.display(invite.code))") {
                        Label("Send code", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.primary)
                } else {
                    ProgressView()
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Invite to \(store.family?.name ?? "family")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: role) {
                invite = nil
                invite = await store.invite(role: role)
            }
        }
        .presentationDetents([.medium])
    }
}
