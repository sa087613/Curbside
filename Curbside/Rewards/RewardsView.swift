import CurbsideCore
import SwiftData
import SwiftUI

/// Rewards tab: parent-set rewards (set or earn) and the partner catalog.
struct RewardsView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(RewardsCenter.self) private var center
    @Query private var drives: [Drive]
    var showFamily: () -> Void
    @State private var showNewReward = false

    var body: some View {
        let score = CurbsideScoreReport.from(drives).score
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // In a family (even before deciding on sharing): show family rewards.
                if family.family != nil, family.me != nil {
                    if family.isParent {
                        ParentRewardsSection(showNew: { showNewReward = true })
                    } else {
                        TeenRewardsSection()
                    }
                } else {
                    Card {
                        HStack(spacing: 14) {
                            Image(systemName: "gift").font(.title2).foregroundStyle(DS.Palette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rewards from your family").font(.headline)
                                Text("Join or create a family and parents can set rewards for hitting score goals.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("Go to Family", action: showFamily).font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
                PartnerCatalogSection(score: score)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Rewards")
        .toolbar {
            if family.family != nil && family.isParent {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewReward = true
                    } label: {
                        Label("New reward", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showNewReward) { NewRewardSheet(preselectedTeen: nil) }
        .task { if center.offers.isEmpty { await center.loadOffers() } }
    }
}

// MARK: - Parent

private struct ParentRewardsSection: View {
    @Environment(FamilyStore.self) private var family
    var showNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rewards you've set").font(.title3.weight(.bold))
            if family.teens.isEmpty {
                Card {
                    Text("Invite a teen from the Family tab, then set rewards for hitting Curbside Score goals.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else if family.rewards.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reward safe driving with something they care about, like \"Hold 80+ for 4 weeks → $20\".")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Set a reward", action: showNew).buttonStyle(.primary)
                    }
                }
            }
            ForEach(family.teens) { teen in
                let theirs = family.rewards.filter { $0.teenID == teen.id }
                if !theirs.isEmpty {
                    Text(teen.displayName).font(.headline).padding(.top, 6)
                    ForEach(theirs) { reward in
                        RewardCard(reward: reward, viewer: .parent, displayProgress: reward.progress)
                    }
                }
            }
        }
    }
}

// MARK: - Teen

private struct TeenRewardsSection: View {
    @Environment(FamilyStore.self) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("From your family").font(.title3.weight(.bold))
            if family.me?.sharing != true {
                Label("You're not sharing, so your parents can't see your progress. You can still earn these.",
                      systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if family.rewards.isEmpty {
                Card {
                    Text("No rewards yet. When a parent sets one, it'll show up here with your progress.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(family.rewards) { reward in
                // Teens see progress computed live from their own drives.
                RewardCard(reward: reward, viewer: .teen, displayProgress: family.localProgress(for: reward))
            }
        }
    }
}

// MARK: - Reward card

struct RewardCard: View {
    let reward: ParentReward
    let viewer: FamilyRole
    let displayProgress: RewardProgress?
    @Environment(FamilyStore.self) private var family
    @State private var confirmDelete = false

    var body: some View {
        var shown = reward
        shown.progress = displayProgress ?? reward.progress
        let status = shown.status()
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reward.prize.title).font(.title3.weight(.bold))
                        Text(reward.goal.summary).font(.subheadline)
                        Text(viewer == .teen ? "From \(reward.createdByName)" : "Set by \(reward.createdBy == family.me?.id ? "you" : reward.createdByName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: status)
                }
                GlassProgressBar(value: shown.fraction(), color: statusColor(status))
                    .accessibilityLabel("Progress")
                    .accessibilityValue(shown.progressDescription())
                Text(shown.progressDescription())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewer == .parent {
                    HStack {
                        if case .earned = status {
                            Button("Mark as given") { Task { await family.markGiven(reward) } }
                                .buttonStyle(.primary)
                        }
                        if case .given = status {
                            Button("Undo given") { Task { await family.markGiven(reward, given: false) } }
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete reward")
                    }
                    .font(.subheadline)
                } else if case .earned = status {
                    Text("Show this to \(reward.createdByName) to collect it.")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .confirmationDialog("Delete this reward?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await family.deleteReward(reward) } }
        }
    }

    private func statusColor(_ status: ParentReward.Status) -> Color {
        switch status {
        case .earned, .given: DS.Palette.good
        default: DS.Palette.accent
        }
    }
}

private struct StatusBadge: View {
    let status: ParentReward.Status

    var body: some View {
        let (text, symbol, color): (String, String, Color) = switch status {
        case .waitingForProgress: ("Waiting", "hourglass", .secondary)
        case .inProgress: ("In progress", "figure.walk.motion", DS.Palette.accent)
        case .earned: ("Earned", "checkmark.seal.fill", DS.Palette.good)
        case .given: ("Given", "gift.fill", .secondary)
        }
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - New reward

struct NewRewardSheet: View {
    let preselectedTeen: MemberRecord?
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var teenID: String?
    @State private var goalKind: RewardGoal.Kind = .hold
    @State private var score = 80
    @State private var weeks = 4
    @State private var prizeKind: RewardPrize.Kind = .money
    @State private var dollars = 20
    @State private var text = ""

    private let config = RewardsConfig.default
    private let privilegeIdeas = ["Later curfew", "Car for the weekend", "Pick the weekend plans", "Skip a chore"]

    private var teen: MemberRecord? { family.teens.first { $0.id == teenID } }
    private var goal: RewardGoal { goalKind == .hold ? .hold(score, weeks: weeks) : .reach(score) }
    private var prize: RewardPrize {
        switch prizeKind {
        case .money: .money(dollars)
        case .privilege: .privilege(text.trimmingCharacters(in: .whitespaces))
        case .custom: .custom(text.trimmingCharacters(in: .whitespaces))
        }
    }
    private var isValid: Bool { teen != nil && (prizeKind == .money ? dollars > 0 : !text.trimmingCharacters(in: .whitespaces).isEmpty) }

    var body: some View {
        NavigationStack {
            Form {
                Section("For") {
                    Picker("Teen", selection: $teenID) {
                        ForEach(family.teens) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    if let teen, let current = teen.standing?.score {
                        Text("\(teen.displayName) is at \(current) (\(CurbsideTier.tier(for: current).displayName)) right now.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Goal", selection: $goalKind) {
                        Text("Hold a score").tag(RewardGoal.Kind.hold)
                        Text("Reach a score").tag(RewardGoal.Kind.reach)
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $score, in: config.goalScoreRange, step: config.goalScoreStep) {
                        LabeledContent("Curbside Score", value: "\(score)+")
                    }
                    HStack {
                        ForEach([CurbsideTier.silver, .gold, .platinum], id: \.self) { tier in
                            Button(tier.displayName) { score = tier.range().lowerBound }
                                .buttonStyle(.bordered)
                                .tint(score == tier.range().lowerBound ? tier.color : .secondary)
                        }
                    }
                    .font(.caption)
                    if goalKind == .hold {
                        Stepper(value: $weeks, in: config.holdWeeksRange) {
                            LabeledContent("For", value: "\(weeks) \(weeks == 1 ? "week" : "weeks")")
                        }
                    }
                } header: {
                    Text("Goal")
                } footer: {
                    if goalKind == .hold {
                        Text("The clock starts when their score is at or above \(score) and resets if it drops below.")
                    } else if let current = teen?.standing?.score, current >= score {
                        Text("They're already above this, so it'll be earned after their next drive.")
                    }
                }

                Section("Reward") {
                    Picker("Type", selection: $prizeKind) {
                        Text("Money").tag(RewardPrize.Kind.money)
                        Text("Privilege").tag(RewardPrize.Kind.privilege)
                        Text("Custom").tag(RewardPrize.Kind.custom)
                    }
                    .pickerStyle(.segmented)
                    switch prizeKind {
                    case .money:
                        Stepper(value: $dollars, in: 5...config.maxPrizeDollars, step: 5) {
                            LabeledContent("Amount", value: "$\(dollars)")
                        }
                    case .privilege:
                        TextField("e.g. Later curfew", text: $text)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(privilegeIdeas, id: \.self) { idea in
                                    Button(idea) { text = idea }.buttonStyle(.bordered).font(.caption)
                                }
                            }
                        }
                    case .custom:
                        TextField("Anything you like", text: $text)
                    }
                }

                if isValid, let teen {
                    Section("Preview") {
                        Text("\(teen.displayName): \(goal.summary) → \(prize.title)")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .glassList()
            .navigationTitle("New reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let teen else { return }
                        Task {
                            await family.createReward(for: teen, goal: goal, prize: prize)
                            dismiss()
                        }
                    }
                    .disabled(!isValid || family.isWorking)
                }
            }
            .onAppear { teenID = preselectedTeen?.id ?? family.teens.first?.id }
            .onChange(of: prizeKind) { text = "" }
        }
    }
}
