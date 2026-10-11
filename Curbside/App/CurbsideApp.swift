import SwiftData
import SwiftUI

@main
struct CurbsideApp: App {
    private let container: ModelContainer
    @State private var prompts: PromptGate
    @State private var recorder: DriveRecorder

    init() {
        do {
            container = try ModelContainer(for: Drive.self)
        } catch {
            fatalError("Couldn't open the drive store: \(error)")
        }
        let prompts = PromptGate()
        _prompts = State(initialValue: prompts)
        _recorder = State(initialValue: DriveRecorder(container: container, prompts: prompts))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(prompts)
                .environment(recorder)
        }
        .modelContainer(container)
    }
}
