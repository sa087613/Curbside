import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(DriveRecorder.self) private var recorder
    @Environment(PromptGate.self) private var prompts
    @Environment(FamilyStore.self) private var family
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .home
    @State private var homePath: [Drive] = []

    enum AppTab: Hashable {
        case home, trends, history, family
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) {
                HomeView(showTrends: { tab = .trends }, showHistory: { tab = .history })
            }
            .tabItem { Label("Drive", systemImage: "car.fill") }
            .tag(AppTab.home)

            NavigationStack {
                TrendsView()
            }
            .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppTab.trends)

            NavigationStack {
                DriveHistoryView()
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(AppTab.history)

            FamilyTabView()
                .tabItem { Label("Family", systemImage: "person.3.fill") }
                .tag(AppTab.family)
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
