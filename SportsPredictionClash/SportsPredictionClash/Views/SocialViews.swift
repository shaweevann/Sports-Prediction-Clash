import SwiftUI

// MARK: - Who's on this bet

/// One line under a card's question: friends who picked it, and how the room splits.
struct SocialProof: View {
    @Environment(GameModel.self) private var model
    let market: Market

    var body: some View {
        let yes = model.backers(market, .yes), no = model.backers(market, .no)
        let friendPicks = yes.friends.map { ($0, Side.yes) } + no.friends.map { ($0, Side.no) }
        HStack(spacing: 8) {
            if !friendPicks.isEmpty {
                HStack(spacing: -8) {
                    ForEach(friendPicks.prefix(3), id: \.0) { pick in
                        Avatar(name: bots[pick.0].name, color: bots[pick.0].color, size: 22)
                            .overlay(Circle().stroke(Brand.burgundyDeep, lineWidth: 2))
                    }
                }
                Text(friendLine(friendPicks)).font(.caption.weight(.semibold)).lineLimit(1)
            } else {
                Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(.secondary)
                Text(yes.total + no.total == 0 ? "No one's on this yet" : "\(yes.total + no.total) \(yes.total + no.total == 1 ? "player" : "players") on this")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if yes.total + no.total > 0 {
                Text("\(Text("\(yes.total) YES").foregroundStyle(.green)) · \(Text("\(no.total) NO").foregroundStyle(.red))")
                    .font(.caption.monospacedDigit())
            }
        }
    }

    private func friendLine(_ picks: [(Int, Side)]) -> String {
        let first = picks[0]
        let more = picks.count - 1
        return more > 0 ? "\(bots[first.0].name) +\(more) on this" : "\(bots[first.0].name) is on \(first.1.label)"
    }
}

// MARK: - Top bar buttons

struct TailButton: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        Button { model.showTail = true } label: {
            Label("Tail", systemImage: "person.2.fill").font(.caption.weight(.semibold))
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Tail a friend's slip")
    }
}

struct ProgressButton: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        Button { model.showProgress = true } label: {
            HStack(spacing: 6) {
                Text("Lv \(model.level)").font(.caption.weight(.bold)).foregroundStyle(Brand.goldInk)
                if model.streak > 0 {
                    Label("\(model.streak)", systemImage: "flame.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.claimable > 0 {
                    Circle().fill(Brand.gold).frame(width: 8, height: 8).offset(x: 8, y: -6)
                }
            }
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Level \(model.level), \(model.streak) win streak, \(model.claimable) missions ready")
    }
}

// MARK: - Tail a slip

struct TailSheet: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.tailable.isEmpty {
                        Text("No one has a slip on this drive yet.").foregroundStyle(.secondary)
                    }
                    ForEach(model.tailable, id: \.bot) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Avatar(name: bots[item.bot].name, color: bots[item.bot].color, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(bots[item.bot].name).font(.body.weight(.semibold))
                                        if model.isFriend(item.bot) {
                                            Text("Friend").font(.caption2.weight(.semibold)).foregroundStyle(Brand.burgundyDeep)
                                                .padding(.horizontal, 6).padding(.vertical, 1).background(Brand.gold, in: .capsule)
                                        }
                                        SimTag()
                                    }
                                    Text("\(item.slip.legs.count) picks · ×\(Pricing.fmt(item.mult)) at opening prices")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                BrandButton(title: "Tail") { model.tail(item.bot); dismiss() }
                            }
                            ForEach(item.slip.legs) { leg in
                                HStack(spacing: 8) {
                                    SideChip(side: leg.side)
                                    Text(leg.market.question).font(.caption).lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Tailing replaces your slip with theirs at today's prices, so your multiplier can differ a little. Picks that no longer fit are skipped.")
                }
            }
            .navigationTitle("Tail a slip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Level, streak and missions

struct ProgressSheet: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Level \(model.level)").font(.system(size: 30, weight: .bold))
                            Spacer()
                            Text("\(model.xp) / \(GameModel.xpFor(model.level + 1)) XP").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ProgressView(value: model.levelProgress).tint(Brand.gold)
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill").foregroundStyle(model.streak > 0 ? .orange : .secondary)
                            Text(model.streak > 0 ? "\(model.streak)-drive win streak" : "No win streak right now")
                            Spacer()
                            Text("Best \(model.bestStreak)").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text("XP: 10 for each slip you snap, 25 for each hit, 50 for each mission.")
                }

                Section {
                    ForEach(model.missions) { m in
                        let done = model.day.claimed.contains(m.id)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(m.title).font(.body.weight(.semibold))
                                ProgressView(value: Double(model.progress(m)), total: Double(m.goal)).tint(Brand.gold)
                                Text("\(model.progress(m)) of \(m.goal) · +\(money(Double(m.reward))) and 50 XP")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if done {
                                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Brand.goldInk)
                                    .accessibilityLabel("Claimed")
                            } else if model.canClaim(m) {
                                BrandButton(title: "Claim") { model.claim(m) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Today's missions")
                } footer: {
                    Text("New missions every day at midnight.")
                }

                Section("Record") {
                    LabeledContent("Slips hit", value: "\(model.wins)")
                    LabeledContent("Slips busted", value: "\(model.losses)")
                    LabeledContent("Bank", value: money(model.bank))
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Game standings

struct StandingRowView: View {
    let row: Standing
    let rank: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)").font(.headline.monospacedDigit())
                .foregroundStyle(rank == 1 ? AnyShapeStyle(Brand.goldInk) : AnyShapeStyle(.secondary))
                .frame(width: 22)
            Avatar(name: row.name, color: row.color, isMe: row.isMe)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.name).font(.subheadline.bold()).lineLimit(1)
                    if row.isBot { SimTag() }
                }
                Text("\(row.hits) of \(row.played) hit\(row.best > 0 ? " · best ×\(Pricing.fmt(row.best))" : "")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Text((row.net >= 0 ? "+" : "−") + money(abs(row.net)))
                .font(.headline.monospacedDigit())
                .foregroundStyle(row.net >= 0 ? Color.green : Color.red)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(row.isMe ? AnyShapeStyle(Brand.gold.opacity(0.18)) : AnyShapeStyle(.primary.opacity(0.05)), in: .rect(cornerRadius: 18))
        .overlay { if row.isMe { RoundedRectangle(cornerRadius: 18).stroke(Brand.goldInk, lineWidth: 1.5) } }
    }
}

// MARK: - Share card

/// The image players share: brand colors, the multiplier in its heat color, every pick and how it landed.
struct SlipShareCard: View {
    let legs: [Leg]
    let mult: Double
    let won: Bool?
    let stake: Int
    let game: String

    var body: some View {
        let heat = clamp(log(max(mult, 1)) / log(Pricing.maxMult), 0, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SPORTS PREDICTION CLASH").font(.system(size: 13, weight: .heavy)).tracking(2).foregroundStyle(Brand.gold)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text(game).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Text(won == true ? "Slip hit" : won == false ? "So close" : "My slip")
                .font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
            Text("×\(Pricing.fmt(mult))")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(heatColor(heat, dark: true))
                .shadow(color: heatColor(heat, dark: true).opacity(0.6), radius: 14)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(legs) { leg in
                    HStack(spacing: 8) {
                        SideChip(side: leg.side)
                        Text(leg.market.question).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                        Spacer(minLength: 4)
                        if let w = leg.won {
                            Image(systemName: w ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(w ? .green : .red)
                        }
                    }
                }
            }
            Text(won == true ? "$\(stake) stake paid \(money(Double(stake) * mult)) · play money" : "$\(stake) stake · play money")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .padding(24)
        .frame(width: 360)
        .background(LinearGradient(colors: [Brand.burgundy, Brand.burgundyDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(.rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Brand.gold.opacity(0.8), lineWidth: 2))
    }
}

@MainActor
func renderShareImage(_ card: SlipShareCard) -> Image? {
    let r = ImageRenderer(content: card)
    r.scale = 3
    guard let ui = r.uiImage else { return nil }
    return Image(uiImage: ui)
}
