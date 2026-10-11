import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(DriveRecorder.self) private var recorder
    @Environment(PromptGate.self) private var prompts
    @Environment(FamilyStore.self) private var family
    @Environment(RewardsCenter.self) private var rewards
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .home
    @State private var homePath: [Drive] = []

    enum AppTab: Hashable, CaseIterable {
        case home, trends, history, family, rewards
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) {
                HomeView(showTrends: { tab = .trends }, showHistory: { tab = .history })
            }
            .floatingTabContent()
            .tag(AppTab.home)

            NavigationStack {
                TrendsView()
            }
            .floatingTabContent()
            .tag(AppTab.trends)

            NavigationStack {
                DriveHistoryView()
            }
            .floatingTabContent()
            .tag(AppTab.history)

            FamilyTabView()
                .floatingTabContent()
                .tag(AppTab.family)

            NavigationStack {
                RewardsView(showFamily: { tab = .family })
            }
            .floatingTabContent()
            .tag(AppTab.rewards)
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $tab)
                .padding(.bottom, 2)
        }
        // Post-drive celebrations, shown over everything once the drive has ended.
        .overlay {
            if let celebration = rewards.current {
                CelebrationView(celebration: celebration,
                                onSeeRewards: {
                                    tab = .rewards
                                    homePath = []
                                    rewards.dismissCurrent()
                                },
                                onDismiss: { rewards.dismissCurrent() })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: rewards.current)
        .tint(DS.Palette.accent)
        .preferredColorScheme(.dark)
        .onChange(of: recorder.phase) { _, phase in
            if phase == .idle { rewards.showNextSoon() }
        }
        .task { await family.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await family.republishStanding() } }
        }
        // Open the summary of the drive that was just saved.
        .onChange(of: recorder.lastSavedDriveID) { _, id in
            guard let id else { return }
            recorder.lastSavedDriveID = nil
            let descriptor = FetchDescriptor<Drive>(predicate: #Predicate { $0.id == id })
            if let drive = try? context.fetch(descriptor).first {
                tab = .home
                homePath = [drive]
            }
        }
        .fullScreenCover(isPresented: Binding(get: { recorder.isRecording }, set: { _ in })) {
            RecordingView()
        }
        .alert(
            prompts.current?.title ?? "",
            isPresented: Binding(get: { prompts.current != nil }, set: { if !$0 { prompts.dismissCurrent() } }),
            presenting: prompts.current
        ) { prompt in
            if prompt.opensSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }
}
