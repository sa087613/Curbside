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
    /// "Hard braking cost you 12 points"
    var habitName: String {
        switch self {
        case .hardBrake: "Hard braking"
        case .harshAcceleration: "Fast starts"
        case .sharpTurn: "Sharp turns"
        }
    }

    func noun(count: Int) -> String {
        let singular = switch self {
        case .hardBrake: "hard brake"
        case .harshAcceleration: "fast start"
        case .sharpTurn: "sharp turn"
        }
        return count == 1 ? singular : singular + "s"
    }

    var tip: String {
        switch self {
        case .hardBrake: "Leave more space and look further ahead so you can slow down gradually."
        case .harshAcceleration: "Press the gas gently when pulling away and take a few seconds to reach speed."
        case .sharpTurn: "Slow down before the turn, not during it, and turn the wheel smoothly."
        }
    }

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
        case .moderate: DS.Palette.severityModerate
        case .hard: DS.Palette.severityHard
        case .severe: DS.Palette.severitySevere
        }
    }
}

enum ScoreStyle {
    static func color(_ score: Int?) -> Color {
        guard let score else { return .secondary }
        switch score {
        case 90...: return DS.Palette.good
        case 75..<90: return DS.Palette.accent
        case 60..<75: return DS.Palette.severityModerate
        default: return DS.Palette.coral
        }
    }

    static func headline(_ score: Int?) -> String {
        guard let score else { return "Not scored" }
        switch score {
        case 90...: return "Great drive"
        case 75..<90: return "Good drive"
        case 60..<75: return "Room to improve"
        default: return "Rough drive"
        }
    }
}
