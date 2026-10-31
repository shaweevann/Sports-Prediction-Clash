import SwiftUI

/// The TikTok-style feed: one market per screen, paging vertically, swipe right for YES and left for NO.
struct FeedView: View {
    @Environment(GameModel.self) private var model
    let insets: EdgeInsets

    var body: some View {
        @Bindable var model = model
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.markets.enumerated()), id: \.element.id) { i, m in
                    MarketCard(market: m, index: i, count: model.markets.count)
                        .padding(.top, insets.top).padding(.bottom, insets.bottom).padding(.horizontal, 16)
                        .containerRelativeFrame(.vertical)
                        .id(i)
                }
                EndCard()
                    .padding(.top, insets.top).padding(.bottom, insets.bottom).padding(.horizontal, 16)
                    .containerRelativeFrame(.vertical)
                    .id(model.markets.count)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $model.page)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }
}

struct MarketCard: View {
    @Environment(GameModel.self) private var model
    let market: Market
    let index: Int
    let count: Int
    @State private var drag: CGFloat = 0

    var body: some View {
        let locked = model.locked(market)
        let change = Int((market.mid - market.open).rounded())
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(market.tag)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                Text("\(index + 1) of \(count)").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "$%.1fk vol", Double(market.vol) / 1000))
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(market.question)
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.6)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text(market.rule).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(market.mid.rounded()))%")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: market.mid))
                Text("chance · \(Text(change == 0 ? "flat" : "\(change > 0 ? "▲" : "▼")\(abs(change))").foregroundStyle(change > 0 ? Color.green : change < 0 ? Color.red : Color.secondary)) since open")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Sparkline(values: market.hist, fair: market.p * 100)
                .frame(minHeight: 40, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.4), value: market.hist.count)
            SocialProof(market: market)
            HStack(spacing: 10) {
                SideButton(market: market, side: .yes)
                SideButton(market: market, side: .no)
            }
            HStack {
                Text(note(locked: locked)).foregroundStyle(Brand.goldInk).lineLimit(2)
                Spacer()
                Text("Swipe ← no · yes →").foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .opacity(locked ? 0.55 : 1)
        .saturation(locked ? 0.4 : 1)
        .overlay { stamps }
        .offset(x: drag)
        .rotationEffect(.degrees(Double(drag / 28)))
        .simultaneousGesture(
            DragGesture(minimumDistance: 15)
                .onChanged { v in
                    guard model.phase == .market else { return }
                    if abs(v.translation.width) > abs(v.translation.height) * 1.3 { drag = v.translation.width }
                }
                .onEnded { _ in
                    if drag > 90 { model.pick(market, .yes, source: "swipe") } else if drag < -90 { model.pick(market, .no, source: "swipe") }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { drag = 0 }
                }
        )
        .accessibilityElement(children: .contain)
    }

    private func note(locked: Bool) -> String {
        if locked {
            let reasons = [model.blocked(market, .yes), model.blocked(market, .no)]
            return reasons.contains { if case .overCap = $0 { true } else { false } }
                ? "Would push your slip past ×\(Int(Pricing.maxMult))" : "Doesn't fit your picks"
        }
        return model.notes[market.id] ?? ""
    }

    private var stamps: some View {
        ZStack {
            stamp("YES", .green, -8).opacity(Double(clamp(drag / 110, 0, 1)))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 28)
            stamp("NO", .red, 8).opacity(Double(clamp(-drag / 110, 0, 1)))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 28)
        }
        .allowsHitTesting(false)
    }

    private func stamp(_ text: String, _ color: Color, _ angle: Double) -> some View {
        Text(text)
            .font(.system(size: 40, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 8)
            .background(color.opacity(0.85), in: .capsule)
            .glassEffect(.regular, in: .capsule)
            .rotationEffect(.degrees(angle))
    }
}

struct SideButton: View {
    @Environment(GameModel.self) private var model
    let market: Market
    let side: Side

    var body: some View {
        let leg = model.leg(for: market)
        let on = leg?.side == side
        let dim = (leg != nil && !on) || model.blocked(market, side) != nil
        let color: Color = side == .yes ? .green : .red
        Button { model.pick(market, side) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(side.label).font(.caption.weight(.bold)).tracking(0.5)
                Text("\(on ? leg!.price : market.ask(side))¢")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(model.caption(market, side))
                    .font(.caption)
                    .foregroundStyle(on ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .foregroundStyle(on ? .white : color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(on ? color : .clear, in: .rect(cornerRadius: 22))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .opacity(dim ? 0.4 : 1)
        .accessibilityLabel("\(side.label) at \(market.ask(side)) cents")
    }
}

struct Sparkline: View {
    let values: [Double]
    let fair: Double

    var body: some View {
        GeometryReader { geo in
            let all = values + [fair]
            let lo = (all.min() ?? 0) - 4, hi = (all.max() ?? 100) + 4
            let n = max(values.count - 1, 1)
            let pt: (Int, Double) -> CGPoint = { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(n), y: geo.size.height * CGFloat(1 - (v - lo) / (hi - lo)))
            }
            let line = Path { p in
                for (i, v) in values.enumerated() {
                    if i == 0 { p.move(to: pt(i, v)) } else { p.addLine(to: pt(i, v)) }
                }
            }
            let fy = geo.size.height * CGFloat(1 - (fair - lo) / (hi - lo))
            ZStack {
                Path { p in
                    p.addPath(line)
                    p.addLine(to: CGPoint(x: values.count > 1 ? geo.size.width : 0, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(.primary.opacity(0.06))
                line.stroke(.primary, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                Path { p in p.move(to: CGPoint(x: 0, y: fy)); p.addLine(to: CGPoint(x: geo.size.width, y: fy)) }
                    .stroke(Brand.gold.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .accessibilityHidden(true)
    }
}

struct EndCard: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let m = model.math
        VStack(alignment: .leading, spacing: 14) {
            Text("End of the feed")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
            Text("That's all \(model.markets.count). Lock it in.")
                .font(.system(size: 32, weight: .bold))
            Text(model.slip.isEmpty ? "×—" : "×\(Pricing.fmt(m.mult))")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Brand.goldInk)
                .shadow(color: Brand.gold.opacity(0.5), radius: 12)
            Text(model.slip.isEmpty
                 ? "No picks yet. Scroll back up, or just watch this drive."
                 : "\(model.slip.count) picks · \(money(Double(model.stake))) pays \(money(Double(model.stake) * m.mult))")
                .foregroundStyle(.secondary)
            BrandButton(title: "Snap the ball") { model.snap() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
    }
}
