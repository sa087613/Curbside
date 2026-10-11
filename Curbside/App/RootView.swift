import SwiftUI

struct RootView: View {
    @Environment(DriveRecorder.self) private var recorder
    @Environment(PromptGate.self) private var prompts
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            DriveListView()
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
