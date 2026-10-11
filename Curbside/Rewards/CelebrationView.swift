import CurbsideCore
import SwiftUI

/// Full-screen celebration card with confetti (static sparkles when Reduce Motion is on).
struct CelebrationView: View {
    let celebration: Celebration
    var onSeeRewards: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            if !reduceMotion {
                ConfettiView().ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(accent.opacity(0.18)).frame(width: 110, height: 110)
                    Image(systemName: symbol)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(accent)
                        .symbolEffect(.bounce, value: appeared)
                }
                Text(title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    Button(action: onSeeRewards) {
                        Text("See rewards").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Nice!", action: onDismiss)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28))
            .shadow(radius: 20)
            .padding(24)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var symbol: String {
        switch celebration {
        case .reward: "gift.fill"
        case .tier: "star.circle.fill"
        }
    }

    private var accent: Color {
        switch celebration {
        case .reward: Color("AccentColor")
        case .tier(let tier, _): tier.color
        }
    }

    private var title: String {
        switch celebration {
        case .reward(let r): "You earned \(r.prize.title)!"
        case .tier(let tier, _): "You reached \(tier.displayName)!"
        }
    }

    private var message: String {
        switch celebration {
        case .reward(let r):
            "\(r.goal.summary): done. \(r.createdByName) set this reward and can see you've earned it."
        case .tier(let tier, let offers):
            "Your Curbside Score hit \(tier.range().lowerBound)+, unlocking \(offers) new partner \(offers == 1 ? "reward" : "rewards")."
        }
    }
}

/// Lightweight falling confetti drawn with Canvas.
private struct ConfettiView: View {
    private struct Piece {
        var x: Double, delay: Double, speed: Double, spin: Double, size: Double, hue: Int, sway: Double
    }

    private let colors: [Color] = [Color("AccentColor"), .orange, .yellow, .pink, .blue, .green]
    private let pieces: [Piece] = (0..<70).map { i in
        var rng = SystemRandomNumberGenerator()
        return Piece(x: Double.random(in: 0...1, using: &rng), delay: Double.random(in: 0...0.8, using: &rng),
                     speed: Double.random(in: 0.25...0.45, using: &rng), spin: Double.random(in: 2...7, using: &rng),
                     size: Double.random(in: 6...11, using: &rng), hue: i % 6, sway: Double.random(in: 10...30, using: &rng))
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let life = t - p.delay
                    guard life > 0 else { continue }
                    let y = -20 + life * p.speed * size.height
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + sin(life * 3 + p.x * 10) * p.sway
                    var piece = context
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(life * p.spin))
                    piece.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)),
                               with: .color(colors[p.hue]))
                }
            }
        }
    }
}
