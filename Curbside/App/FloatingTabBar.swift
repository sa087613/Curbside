import SwiftUI

/// The floating glass tab bar. The selected tab is a yellow pill.
struct FloatingTabBar: View {
    @Binding var selection: RootView.AppTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RootView.AppTab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(height: 18)
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? DS.Palette.onAccent : DS.Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background {
                        if selected {
                            Capsule().fill(DS.Palette.accent)
                                .shadow(color: DS.Palette.accent.opacity(0.35), radius: 8)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.35), in: Capsule())
        .overlay(Capsule().strokeBorder(DS.Palette.cardBorder, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .padding(.horizontal, DS.Spacing.gutter)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: selection)
    }
}

extension RootView.AppTab {
    var title: String {
        switch self {
        case .home: "Drive"
        case .trends: "Trends"
        case .history: "History"
        case .family: "Family"
        case .rewards: "Rewards"
        }
    }

    var symbol: String {
        switch self {
        case .home: "car.fill"
        case .trends: "chart.line.uptrend.xyaxis"
        case .history: "clock.arrow.circlepath"
        case .family: "person.3.fill"
        case .rewards: "gift.fill"
        }
    }
}

extension View {
    /// Hides the system tab bar and leaves room for the floating one.
    func floatingTabContent() -> some View {
        toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: DS.Spacing.tabBarClearance - 20) }
    }
}
