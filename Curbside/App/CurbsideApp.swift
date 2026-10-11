import SwiftData
import SwiftUI

@main
struct CurbsideApp: App {
    private let container: ModelContainer
    @State private var prompts: PromptGate
    @State private var recorder: DriveRecorder
    @State private var family: FamilyStore
    @State private var rewards: RewardsCenter

    init() {
        DS.configureAppearance()
        do {
            container = try ModelContainer(for: Drive.self)
        } catch {
            fatalError("Couldn't open the drive store: \(error)")
        }
        let prompts = PromptGate()
        _prompts = State(initialValue: prompts)
        let recorder = DriveRecorder(container: container, prompts: prompts)
        let family = FamilyStore(container: container, prompts: prompts)
        let rewards = RewardsCenter(container: container)
        // Celebrations wait until recording has fully stopped and no drive is in progress.
        rewards.isDriving = { [weak recorder, weak prompts] in
            (recorder?.isRecording ?? false) || (prompts?.isDriving ?? false)
        }
        recorder.onDriveSaved = { [weak family, weak rewards] drive in
            let earned = await family?.driveSaved(drive) ?? []
            rewards?.driveEnded(earned: earned)
        }
        _recorder = State(initialValue: recorder)
        _family = State(initialValue: family)
        _rewards = State(initialValue: rewards)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(prompts)
                .environment(recorder)
                .environment(family)
                .environment(rewards)
        }
        .modelContainer(container)
    }
}
