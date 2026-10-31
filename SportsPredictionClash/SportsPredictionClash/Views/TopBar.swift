import SwiftUI

/// Floating scoreboard capsule plus the phase pill underneath it.
struct TopBar: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        // During a live drive the board follows the play; otherwise it shows where the next drive starts
        let v = model.phase == .live ? model.view : nil
        let g = model.g
        let yl = v?.yl ?? g.yl
        let down = v?.down ?? 1
        let dist = v?.dist ?? min(10, 100 - g.yl)
        let clock = v?.clock ?? g.clock
        let qtr = v?.qtr ?? g.qtr

        VStack(spacing: 8) {
            VStack(spacing: 9) {
                HStack {
                    TeamScore(index: 0)
                    Spacer()
                    VStack(spacing: 1) {
                        Text(fmtClock(clock))
                            .font(.headline.monospacedDigit())
                            .contentTransition(.numericText())
                        Text(g.over && model.phase == .final ? "Final" : "\(ordinal(qtr)) qtr")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TeamScore(index: 1)
                }
                FieldStrip(offense: model.offense, defense: model.defense, yl: yl, dist: dist)
                HStack {
                    if g.over && model.phase == .final {
                        Text("Final").font(.footnote.weight(.semibold))
                    } else {
                        Text("\(Text("\(model.offense.abbr) ball").bold()) · \(ordinal(down)) & \(yl + dist >= 100 ? "Goal" : "\(dist)") at \(spot(yl))")
                            .font(.footnote)
                    }
                    Spacer()
                    Text("Drive \(g.drive)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))

            HStack(spacing: 8) {
                if model.phase == .market && !model.botSlips.isEmpty { TailButton() }
                PhasePill()
                ProgressButton()
            }
        }
    }

    private func spot(_ yl: Int) -> String {
        yl == 50 ? "midfield" : yl < 50 ? "own \(yl)" : "\(model.defense.abbr) \(100 - yl)"
    }
}

private struct TeamScore: View {
    @Environment(GameModel.self) private var model
    let index: Int

    var body: some View {
        let team = teams[index]
        let hasBall = model.g.off == index && !model.g.over
        HStack(spacing: 8) {
            if index == 1 { score }
            if index == 0 { dot(hasBall) }
            Text(team.abbr).font(.subheadline.weight(.bold)).foregroundStyle(team.color)
            if index == 1 { dot(hasBall) }
            if index == 0 { score }
        }
    }

    private var score: some View {
        Text("\(model.g.score[index])")
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private func dot(_ on: Bool) -> some View {
        Circle().fill(Brand.gold).frame(width: 7, height: 7).shadow(color: Brand.gold, radius: 4).opacity(on ? 1 : 0)
    }
}

/// The field, end zone to end zone, offense always driving left to right.
struct FieldStrip: View {
    let offense: Team, defense: Team, yl: Int, dist: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, ez = w / 12
            let x: (Int) -> CGFloat = { ez + CGFloat($0) / 100 * (w - 2 * ez) }
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(red: 0.16, green: 0.50, blue: 0.30))
                ForEach(1..<12, id: \.self) { i in
                    Rectangle().fill(.white.opacity(0.3)).frame(width: 1).offset(x: CGFloat(i) * w / 12)
                }
                HStack(spacing: 0) {
                    zone(offense).frame(width: ez)
                    Spacer(minLength: 0)
                    zone(defense).frame(width: ez)
                }
                Rectangle().fill(Color(red: 0.49, green: 0.71, blue: 1)).frame(width: 2, height: 14).offset(x: x(yl) - 1)
                Rectangle().fill(.yellow).frame(width: 2, height: 14).offset(x: x(min(100, yl + dist)) - 1)
                Ellipse()
                    .fill(Color(red: 0.66, green: 0.39, blue: 0.18))
                    .overlay(Ellipse().stroke(.white, lineWidth: 1.5))
                    .frame(width: 13, height: 8)
                    .shadow(radius: 2)
                    .offset(x: x(yl) - 6.5)
            }
            .clipShape(.capsule)
            .animation(.snappy, value: yl)
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    private func zone(_ t: Team) -> some View {
        Text(t.abbr).font(.system(size: 8, weight: .bold)).foregroundStyle(.black.opacity(0.6))
            .frame(maxHeight: .infinity).frame(maxWidth: .infinity).background(t.color)
    }
}

private struct PhasePill: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .loading:
                Text("Setting the lines")
            case .market:
                Text("\(Text("\(model.markets.count)").bold()) markets")
                Text(fmtClock(model.timeLeft))
                    .bold().monospacedDigit()
                    .foregroundStyle(model.hurry ? Color.red : Color.primary)
                    .contentTransition(.numericText(countsDown: true))
            case .live:
                Label("Live", systemImage: "circle.fill").labelStyle(.titleAndIcon).foregroundStyle(.red).bold()
                Text("\(model.offense.abbr) drive \(model.g.drive)")
            case .done:
                Text("\(Text("Drive over").bold()) · \(model.lastResult)")
            case .final:
                Text("Final").bold()
            case .offline:
                Text("Offline").bold()
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 14).padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            if model.phase == .market {
                GeometryReader { geo in
                    Capsule()
                        .fill(model.hurry ? Color.red : Brand.gold)
                        .frame(width: geo.size.width * CGFloat(model.timeLeft) / CGFloat(GameModel.marketSeconds), height: 2)
                        .animation(.linear(duration: 1), value: model.timeLeft)
                }
                .frame(height: 2)
                .padding(.horizontal, 14)
            }
        }
        .glassEffect(.regular, in: .capsule)
    }
}
