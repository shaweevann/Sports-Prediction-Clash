import SwiftUI

/// One screen: the stadium backdrop, the feed (or the live drive) scrolling full-bleed underneath
/// floating Liquid Glass chrome — scoreboard on top, parlay slip at the bottom.
struct RootView: View {
    @State private var model = GameModel()
    @State private var topHeight: CGFloat = 180
    @State private var bottomHeight: CGFloat = 150
    @State private var showSlip = false
    @State private var showFriends = false

    var body: some View {
        GeometryReader { geo in
            // Content pads itself by the chrome's measured height so it can scroll underneath the glass
            let insets = EdgeInsets(top: geo.safeAreaInsets.top + topHeight + 10, leading: 0,
                                    bottom: geo.safeAreaInsets.bottom + bottomHeight + 10, trailing: 0)
            ZStack {
                StadiumBackground().ignoresSafeArea()
                switch model.phase {
                case .loading:
                    ProgressView("Setting the lines").controlSize(.large)
                case .market:
                    FeedView(insets: insets)
                case .live, .done:
                    LiveView(insets: insets, showFriends: $showFriends)
                case .final:
                    FinalView(insets: insets)
                }
            }
            .overlay(alignment: .top) {
                TopBar()
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
            }
            .overlay(alignment: .bottom) {
                SlipBar(showSlip: $showSlip)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
            }
            .overlay {
                if let text = model.toast {
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.horizontal, 32)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
        }
        .environment(model)
        .tint(Brand.goldInk)
        .sheet(isPresented: $showSlip) {
            SlipSheet().environment(model).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $model.showTail) {
            TailSheet().environment(model).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $model.showProgress) {
            ProgressSheet().environment(model).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFriends) {
            FriendsSheet().environment(model).presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.bump)
        .sensoryFeedback(.success, trigger: model.winPulse)
        .task { await model.start() }
    }
}

/// Slow-moving stadium lights behind the glass, in the brand's burgundy and gold.
/// Sports Prediction Clash always runs in its dark look (UIUserInterfaceStyle = Dark in the build settings).
struct StadiumBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let t = Float(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
            let s: (Float) -> Float = { k in 0.09 * sin(t * k) }
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + s(0.21), 0], [1, 0],
                [0, 0.5 + s(0.17)], [0.5 + s(0.23), 0.5 + s(0.13)], [1, 0.5 + s(0.11)],
                [0, 1], [0.5 + s(0.15), 1], [1, 1],
            ], colors: Self.night)
        }
    }

    private static let night: [Color] = [
        Color(red: 0.42, green: 0.07, blue: 0.14), Color(red: 0.09, green: 0.01, blue: 0.03), Color(red: 0.45, green: 0.30, blue: 0.06),
        Color(red: 0.14, green: 0.02, blue: 0.05), Color(red: 0.48, green: 0.08, blue: 0.15), Color(red: 0.07, green: 0.01, blue: 0.03),
        Color(red: 0.30, green: 0.18, blue: 0.03), Color(red: 0.05, green: 0.01, blue: 0.02), Color(red: 0.36, green: 0.05, blue: 0.11),
    ]
}

// MARK: - Shared bits

/// The multiplier's heat color: cool blue → violet → magenta → red as the slip climbs toward the cap.
func heatColor(_ t: Double, dark: Bool) -> Color {
    let hue = (215 + 145 * pow(t, 1.1)).truncatingRemainder(dividingBy: 360) / 360
    return Color(hue: hue, saturation: 0.6 + 0.35 * t, brightness: dark ? 1 : 0.82)
}

func ordinal(_ n: Int) -> String { ["1st", "2nd", "3rd", "4th"][clamp(n, 1, 4) - 1] }

struct SideChip: View {
    let side: Side
    var body: some View {
        Text(side.label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(side == .yes ? Color.green : Color.red, in: .capsule)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.top, 4)
    }
}
