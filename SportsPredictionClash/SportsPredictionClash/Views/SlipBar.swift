import SwiftUI

/// Floating parlay slip: stake, pick count, the heat-scaled multiplier and the primary action.
struct SlipBar: View {
    @Environment(GameModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Binding var showSlip: Bool

    var body: some View {
        @Bindable var model = model
        let heat = model.heat
        let hc = heatColor(heat, dark: scheme == .dark)
        VStack(spacing: 10) {
            HStack {
                Picker("Stake", selection: $model.stake) {
                    ForEach(GameModel.stakes, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 196)
                .disabled(model.phase != .market)
                Spacer()
                Text("\(Text(trophies(model.bank)).bold().monospacedDigit()) · \(model.wins)–\(model.losses)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { showSlip = true } label: {
                    VStack(spacing: 0) {
                        Text("\(model.slip.count)").font(.title2.bold()).monospacedDigit().contentTransition(.numericText())
                        Text("picks").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("\(model.slip.count) picks. Show slip")

                VStack(alignment: .leading, spacing: 3) {
                    HeatMultiplier(text: model.slip.isEmpty ? "×—" : "×\(Pricing.fmt(model.math.mult))",
                                   heat: heat, busted: model.busted, bump: model.bump)
                    Text(payLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                BrandButton(title: primaryTitle, action: primary)
                .disabled(model.phase == .loading || (model.phase == .market && !model.slip.isEmpty && Double(model.stake) > model.bank))
            }
            Text("Play for trophies · No real money")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassEffect(.regular.tint(hc.opacity(heat * heat * 0.35)), in: .rect(cornerRadius: 30))
        .shadow(color: hc.opacity(heat * heat * 0.6), radius: heat * heat * 22)
        .animation(.easeInOut(duration: 0.6), value: heat)
        .onChange(of: model.stake) { model.save() }
    }

    private var payLine: String {
        let n = model.slip.count, pays = payout(model.stake, model.math.mult)
        switch model.phase {
        case .market:
            if n == 0 { return "Swipe a market to start your slip" }
            if Double(model.stake) > model.bank { return "Not enough trophies. Lower your stake." }
            return "\(trophies(Double(model.stake))) pays \(trophies(pays)) if all \(n) hit"
        case .live:
            if n == 0 { return "Just watching this drive" }
            if let lost = model.slip.first(where: { $0.won == false }) { return "Busted: \(lost.market.question)" }
            return "\(model.slip.filter { $0.won == true }.count) of \(n) hit · pays \(trophies(pays))"
        case .done: return model.summary?.title ?? ""
        case .final: return "Game over"
        case .loading: return "Setting the lines"
        }
    }

    private var primaryTitle: String {
        switch model.phase {
        case .market: model.slip.isEmpty ? "Watch" : "Snap"
        case .live: "Skip"
        case .done: model.g.over ? "Final" : "Next"
        case .final: "New"
        case .loading: "…"
        }
    }

    private func primary() {
        guard model.debounce("primary") else { return }
        switch model.phase {
        case .market: model.snap()
        case .live: model.skip()
        case .done: if model.g.over { model.showFinal() } else { model.next() }
        case .final: model.newGame()
        case .loading: break
        }
    }
}

/// The multiplier runs cool to hot as the slip climbs, then glows and shakes near the cap.
struct HeatMultiplier: View {
    let text: String
    let heat: Double
    let busted: Bool
    let bump: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = heatColor(heat, dark: scheme == .dark)
        let shaking = heat >= 0.6 && !busted && !reduceMotion
        TimelineView(.animation(paused: !shaking)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let amp = shaking ? 0.4 + (heat - 0.6) / 0.4 * 2.6 : 0
            let w = 30 + heat * 30
            Text(text)
                .font(.system(size: 26 + heat * 8, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(busted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(c))
                .shadow(color: c.opacity(busted ? 0 : heat * 0.9), radius: 2 + heat * 12)
                .offset(x: sin(t * w) * amp, y: cos(t * w * 1.3) * amp * 0.6)
                .rotationEffect(.degrees(sin(t * w * 0.8) * amp * 0.5))
        }
        .contentTransition(.numericText())
        .phaseAnimator([1.0, 1.2, 1.0], trigger: bump) { view, scale in
            view.scaleEffect(scale, anchor: .leading)
        } animation: { _ in .spring(duration: 0.22) }
        .animation(.easeInOut(duration: 0.6), value: heat)
    }
}

struct SlipSheet: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let m = model.math
        let fair = Pricing.joint(model.slip).p
        NavigationStack {
            List {
                Section {
                    if model.slip.isEmpty {
                        Text("No picks yet. Swipe right for YES, left for NO.").foregroundStyle(.secondary)
                    }
                    ForEach(model.slip) { leg in
                        HStack(spacing: 10) {
                            SideChip(side: leg.side)
                            Text(leg.market.question)
                            Spacer()
                            Text("×\(Pricing.fmt(100 / Double(leg.price)))").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            if model.phase == .market {
                                Button("Remove", role: .destructive) { model.remove(leg) }
                            }
                        }
                    }
                }
                if !model.slip.isEmpty {
                    Section {
                        LabeledContent("Market payouts multiplied", value: "×\(Pricing.fmt(m.naive))")
                        LabeledContent("Correlation adjustment", value: "×" + String(format: "%.2f", m.corr))
                        LabeledContent("Slip multiplier", value: "×\(Pricing.fmt(m.mult)) of ×\(Int(Pricing.maxMult))")
                        LabeledContent("\(trophies(Double(model.stake))) pays", value: trophies(payout(model.stake, m.mult)))
                        LabeledContent("Model fair odds", value: "×\(Pricing.fmt(1 / fair))")
                        LabeledContent("House edge", value: String(format: "%.1f%%", (1 - m.mult * fair) * 100))
                    } header: {
                        Text("How it's priced")
                    } footer: {
                        Text(m.corr < 0.98 ? "Your picks tend to happen together, so the combo is likelier than it looks and pays less."
                             : m.corr > 1.02 ? "Your picks rarely happen together, so the combo pays more."
                             : "Your picks are close to independent.")
                    }
                }
            }
            .navigationTitle("Drive slip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
