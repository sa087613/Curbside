import SwiftData
import SwiftUI

@main
struct CurbsideApp: App {
    private let container: ModelContainer
    @State private var prompts: PromptGate
    @State private var recorder: DriveRecorder
    @State private var family: FamilyStore

    init() {
        do {
            container = try ModelContainer(for: Drive.self)
        } catch {
            fatalError("Couldn't open the drive store: \(error)")
        }
        let prompts = PromptGate()
        _prompts = State(initialValue: prompts)
        let recorder = DriveRecorder(container: container, prompts: prompts)
        let family = FamilyStore(container: container, prompts: prompts)
        recorder.onDriveSaved = { [weak family] drive in await family?.driveSaved(drive) }
        _recorder = State(initialValue: recorder)
        _family = State(initialValue: family)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(prompts)
                .environment(recorder)
                .environment(family)
        }
        .modelContainer(container)
    }
}
