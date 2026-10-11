import CurbsideCore
import SwiftUI

enum Format {
    static func miles(_ meters: Double) -> String {
        String(format: "%.1f mi", meters / Units.metersPerMile)
    }

    static func mph(_ mps: Double) -> String {
        "\(Int(Units.mph(fromMps: mps).rounded())) mph"
    }

    /// "45 sec", "23 min", "1 hr 5 min"
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds)) sec" }
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    /// Time into the drive, "4:12".
    static func clock(_ t: Double) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension DrivingEventKind {
    var symbol: String {
        switch self {
        case .hardBrake: "exclamationmark.octagon.fill"
        case .harshAcceleration: "hare.fill"
        case .sharpTurn: "arrow.turn.up.right"
        }
    }
}

extension EventSeverity {
    var color: Color {
        switch self {
        case .moderate: .yellow
        case .hard: .orange
        case .severe: .red
        }
    }
}
