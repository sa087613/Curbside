import Foundation
import Observation

struct AppPrompt: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var opensSettings = false

    static let locationDenied = AppPrompt(
        title: "Location is off for Curbside",
        message: "Curbside needs your location while recording to measure your speed and draw your route. In Settings, set Location to \"While Using the App\".",
        opensSettings: true
    )

    static func saveFailed(_ error: Error) -> AppPrompt {
        AppPrompt(title: "Couldn't save drive", message: error.localizedDescription)
    }
}

/// The single path for any alert, sheet, or notification-style prompt in the app.
///
/// Safety rule: nothing interactive appears while a drive is being recorded. Prompts raised
/// during a drive wait in a queue and are shown one at a time after the drive ends.
@MainActor
@Observable
final class PromptGate {
    private(set) var isDriving = false
    private(set) var current: AppPrompt?
    @ObservationIgnored private var queue: [AppPrompt] = []

    func present(_ prompt: AppPrompt) {
        if isDriving || current != nil {
            queue.append(prompt)
        } else {
            current = prompt
        }
    }

    func setDriving(_ driving: Bool) {
        isDriving = driving
        if !driving { showNextSoon() }
    }

    func dismissCurrent() {
        current = nil
        showNextSoon()
    }

    /// Small delay so a new alert doesn't collide with a dismissing screen or alert.
    private func showNextSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !isDriving, current == nil, !queue.isEmpty else { return }
            current = queue.removeFirst()
        }
    }
}
