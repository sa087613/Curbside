import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(DriveRecorder.self) private var recorder
    @Environment(PromptGate.self) private var prompts
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @State private var path: [Drive] = []

    var body: some View {
        NavigationStack(path: $path) {
            DriveListView()
        }
        // Open the summary of the drive that was just saved.
        .onChange(of: recorder.lastSavedDriveID) { _, id in
            guard let id else { return }
            recorder.lastSavedDriveID = nil
            let descriptor = FetchDescriptor<Drive>(predicate: #Predicate { $0.id == id })
            if let drive = try? context.fetch(descriptor).first { path = [drive] }
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
