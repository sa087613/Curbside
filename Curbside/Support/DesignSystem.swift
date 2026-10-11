import CurbsideCore
import SwiftUI

/// Curbside's design system: every color, font, spacing value, and the glass card style.
/// Values come from `design/curbside-demo-video.html`. Views use these instead of hard-coding styles.
enum DS {
    // MARK: Colors

    enum Palette {
        /// Near-black app background.
        static let background = Color(hex: 0x0D0D0F)
        static let backgroundMid = Color(hex: 0x17171A)
        /// Primary buttons, selected tab, score ring, routes, highlights.
        static let accent = Color(hex: 0xFFC400)
        /// Text and icons on top of the accent yellow.
        static let onAccent = Color(hex: 0x0B0B0C)
        /// End drive and hard-brake markers.
        static let coral = Color(hex: 0xFF5A4E)
        /// Gains.
        static let good = Color(hex: 0x4ADE80)
        /// The cool glow in the bottom corner of the background.
        static let ice = Color(hex: 0x7DD3FC)

        static let text = Color.white
        static let muted = Color.white.opacity(0.62)
        static let faint = Color.white.opacity(0.4)

        static let cardFill = Color.white.opacity(0.07)
        static let cardBorder = Color.white.opacity(0.13)
        /// Unfilled part of progress bars and rings.
        static let track = Color.white.opacity(0.14)
        static let divider = Color.white.opacity(0.08)
        /// Map tiles and other solid dark surfaces.
        static let surface = Color(hex: 0x161618)

        /// Event severity (always shown with its name).
        static let severityModerate = Color(hex: 0xFF9F1C)
        static let severityHard = Color(hex: 0xFF5A4E)
        static let severitySevere = Color(hex: 0xE0245E)

        /// Habit series in charts (validated categorical palette, dark-mode steps).
        static let hardBrake = Color(hex: 0x3987E5)
        static let harshAcceleration = Color(hex: 0xD95926)
        static let sharpTurn = Color(hex: 0x199E70)
    }

    static func tierColor(_ tier: CurbsideTier) -> Color {
        switch tier {
        case .bronze: Color(hex: 0xCD7F32)
        case .silver: Color(hex: 0xC0C7D1)
        case .gold: Color(hex: 0xFFC400)
        case .platinum: Color(hex: 0xF2F6FF)
        }
    }

    /// Partner offer tiles (SF Symbol on a category color; never a logo).
    static func categoryColor(_ category: PartnerOffer.Category) -> Color {
        switch category {
        case .food: Color(hex: 0xF5923E)
        case .beauty: Color(hex: 0xE5675F)
        case .entertainment: Color(hex: 0x8E6CEF)
        case .retail: Color(hex: 0x3987E5)
        case .car: Color(hex: 0x3E8F82)
        }
    }

    /// Dark fill behind a tier badge's text.
    static func tierBadgeFill(_ tier: CurbsideTier) -> Color {
        switch tier {
        case .bronze: Color(hex: 0x4A3220)
        case .silver: Color(hex: 0x35383D)
        case .gold: Color(hex: 0x443B1A)
        case .platinum: Color(hex: 0x34383F)
        }
    }

    // MARK: Type

    enum Typeface {
        /// Big, heavy, rounded numbers (scores, speeds, stats).
        static func number(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        /// Screen titles ("Curbside", "Drive Complete").
        static let screenTitle = Font.system(size: 30, weight: .heavy, design: .rounded)
        static let cardTitle = Font.system(size: 18, weight: .heavy)
        static let rowTitle = Font.system(size: 15, weight: .bold)
        static let body = Font.system(size: 15)
        static let secondary = Font.system(size: 13.5)
        static let small = Font.system(size: 12)
        /// Small uppercase letter-spaced labels.
        static let label = Font.system(size: 10.5, weight: .semibold)
        static let labelTracking: CGFloat = 1.5
        static let sectionTitle = Font.system(size: 15.5, weight: .bold)
        static let button = Font.system(size: 17, weight: .bold)
    }

    // MARK: Spacing and shape

    enum Spacing {
        /// Screen side gutter.
        static let gutter: CGFloat = 16
        /// Inside a glass card.
        static let card: CGFloat = 18
        /// Between cards.
        static let stack: CGFloat = 14
        static let tight: CGFloat = 8
        /// Room left under scrolling content for the floating tab bar.
        static let tabBarClearance: CGFloat = 84
    }

    enum Radius {
        static let card: CGFloat = 28
        static let tile: CGFloat = 24
        static let row: CGFloat = 20
        static let button: CGFloat = 26
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension CurbsideTier {
    /// Tier colors always appear next to the tier name, never alone.
    var color: Color { DS.tierColor(self) }
}

// MARK: - UIKit appearance

extension DS {
    /// Navigation bars and segmented controls in the design's style. Called once at launch.
    @MainActor static func configureAppearance() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        for a in [edge, scrolled] {
            a.largeTitleTextAttributes = [.font: rounded(32, .heavy), .foregroundColor: UIColor.white]
            a.titleTextAttributes = [.font: rounded(17, .bold), .foregroundColor: UIColor.white]
        }
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = edge
        UINavigationBar.appearance().compactAppearance = scrolled

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(DS.Palette.accent)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(DS.Palette.onAccent),
                                          .font: UIFont.systemFont(ofSize: 13, weight: .bold)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.8)], for: .normal)
    }
}

// MARK: - Glass card

struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = DS.Radius.card
    var padding: CGFloat? = DS.Spacing.card
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding ?? 0)
            .background {
                shape.fill(DS.Palette.cardFill)
                if let tint { shape.fill(tint.opacity(0.12)) }
            }
            .overlay {
                shape.strokeBorder(tint?.opacity(0.55) ?? DS.Palette.cardBorder, lineWidth: 1.5)
            }
            .clipShape(shape)
    }
}

extension View {
    /// Translucent rounded card with a thin light border.
    func glassCard(radius: CGFloat = DS.Radius.card, padding: CGFloat? = DS.Spacing.card, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(radius: radius, padding: padding, tint: tint))
    }

    /// The app background: near-black with a warm and a cool glow and the topographic texture.
    func screenBackground() -> some View {
        background { ScreenBackground().ignoresSafeArea() }
    }

    /// Lists and forms on the app background with glass rows.
    func glassList() -> some View {
        scrollContentBackground(.hidden)
            .screenBackground()
            .listRowBackground(DS.Palette.cardFill)
    }
}

// MARK: - Background

struct ScreenBackground: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                LinearGradient(stops: [
                    .init(color: DS.Palette.background, location: 0),
                    .init(color: DS.Palette.backgroundMid, location: 0.55),
                    .init(color: DS.Palette.background, location: 1),
                ], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1))
                RadialGradient(colors: [DS.Palette.accent.opacity(0.14), .clear],
                               center: UnitPoint(x: 0.08, y: 0), startRadius: 0, endRadius: size.width * 1.1)
                RadialGradient(colors: [DS.Palette.ice.opacity(0.09), .clear],
                               center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: size.width * 0.9)
                TopoTexture()
                    .stroke(.white.opacity(0.07), lineWidth: 1.6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The faint contour lines behind every screen (traced from the design's 356 × 756 SVG, then scaled).
struct TopoTexture: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 356, sy = rect.height / 756
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        // Each contour is the SVG's "M start C c1 c2 mid S c2' end", with the S control reflected.
        let contours: [[CGFloat]] = [
            [-10, 170, 80, 120, 150, 210, 250, 150, 350, 90, 340, 110, 370, 130],
            [-10, 330, 70, 290, 160, 380, 260, 320, 360, 260, 350, 290, 370, 300],
            [-10, 520, 90, 470, 150, 560, 250, 500, 350, 440, 340, 470, 370, 490],
            [40, 0, 20, 120, 90, 200, 60, 330, 30, 460, 10, 560, 50, 756],
            [220, 0, 260, 140, 190, 230, 240, 360, 290, 490, 300, 600, 230, 756],
        ]
        var path = Path()
        for c in contours {
            path.move(to: p(c[0], c[1]))
            path.addCurve(to: p(c[6], c[7]), control1: p(c[2], c[3]), control2: p(c[4], c[5]))
            path.addCurve(to: p(c[12], c[13]), control1: p(c[8], c[9]), control2: p(c[10], c[11]))
        }
        return path
    }
}

// MARK: - Labels and headers

/// Small uppercase letter-spaced label ("CURBSIDE SCORE", "LAST DRIVE").
struct CapsLabel: View {
    let text: String
    var color: Color = DS.Palette.muted

    init(_ text: String, color: Color = DS.Palette.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(DS.Typeface.label)
            .tracking(DS.Typeface.labelTracking)
            .foregroundStyle(color)
    }
}

/// Big screen title with an optional muted subtitle, used at the top of each tab.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DS.Typeface.screenTitle)
                    .foregroundStyle(DS.Palette.text)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typeface.secondary)
                        .foregroundStyle(DS.Palette.muted)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Muted section heading between cards ("What's moving your score").
struct SectionHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Typeface.sectionTitle)
            .foregroundStyle(DS.Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Tier name on its tier's dark fill.
struct TierBadge: View {
    let tier: CurbsideTier
    var large = false

    var body: some View {
        Text(tier.displayName)
            .font(.system(size: large ? 13 : 10.5, weight: .heavy))
            .foregroundStyle(tier.color)
            .padding(.horizontal, large ? 12 : 7)
            .padding(.vertical, large ? 5 : 2.5)
            .background(DS.tierBadgeFill(tier), in: Capsule())
    }
}

// MARK: - Buttons

/// Yellow pill with a soft glow (Start Drive, primary actions).
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = DS.Palette.accent
    var foreground: Color = DS.Palette.onAccent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typeface.button)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(isEnabled ? 0.35 : 0), radius: 12, y: 4)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Outlined glass pill (secondary actions, "See the breakdown").
struct GlassButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .system(size: 14, weight: .bold) : DS.Typeface.button)
            .foregroundStyle(DS.Palette.text)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 38 : 48)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    /// Coral pill for End drive.
    static var danger: PrimaryButtonStyle { PrimaryButtonStyle(color: DS.Palette.coral, foreground: .white) }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
    static var glassCompact: GlassButtonStyle { GlassButtonStyle(compact: true) }
}

// MARK: - Progress bar

/// Rounded progress bar on a faint track.
struct GlassProgressBar: View {
    let value: Double
    var color: Color = DS.Palette.accent
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.track)
                Capsule().fill(color).frame(width: max(height, geo.size.width * min(1, max(0, value))))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}
