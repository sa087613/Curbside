import CurbsideCore
import SwiftUI

/// The only screen shown while driving: current speed and a Stop button. Nothing else.
struct RecordingView: View {
    @Environment(DriveRecorder.self) private var recorder

    private var speedText: String {
        guard let mps = recorder.speedMps else { return "--" }
        return String(Int(Units.mph(fromMps: mps).rounded()))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(speedText)
                .font(.system(size: 160, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .accessibilityLabel(recorder.speedMps == nil ? "Speed unavailable" : "\(speedText) miles per hour")
            Text("mph")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            Spacer()
            Button {
                Task { await recorder.stop() }
            } label: {
                Text(recorder.phase == .saving ? "Saving…" : "End drive")
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.danger)
            .disabled(recorder.phase == .saving)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .screenBackground()
        .preferredColorScheme(.dark)
        .animation(.default, value: speedText)
    }
}
