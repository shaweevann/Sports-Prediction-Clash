import SwiftUI

/// The drive playing out: result, leaderboard (once it's over), your slip settling, and play-by-play.
struct LiveView: View {
    @Environment(GameModel.self) private var model
    let insets: EdgeInsets
    @Binding var showFriends: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let s = model.summary { ResultCard(summary: s) }
                if model.phase == .done { LeaderboardCard(showFriends: $showFriends) }
                SectionLabel(text: "Your slip")
                if model.slip.isEmpty {
                    Text("No slip this drive. Just watching.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
                ForEach(model.slip) { LegRow(leg: $0) }
                SectionLabel(text: "Play by play")
                VStack(spacing: 0) {
                    ForEach(model.pbp) { e in
                        PlayRow(event: e)
                        if e.id != model.pbp.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .opacity(model.pbp.isEmpty ? 0 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
    }
}

private struct ResultCard: View {
    @Environment(GameModel.self) private var model
    let summary: DriveSummary
    @State private var shareImage: Image?

    var body: some View {
        let tint: Color = summary.won == true ? .green : summary.won == false ? .red : .clear
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(summary.won == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
                Spacer()
                if let img = shareImage {
                    ShareLink(item: img, preview: SharePreview("My Sports Prediction Clash slip", image: img)) {
                        Label("Share", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                    }
                    .simultaneousGesture(TapGesture().onEnded { model.didShare() })
                }
            }
            if !summary.detail.isEmpty { Text(summary.detail).font(.subheadline).foregroundStyle(.secondary) }
            Text(summary.line).font(.subheadline).foregroundStyle(.secondary)
        }
        .task(id: summary.title) {
            guard summary.won != nil, !model.slip.isEmpty else { shareImage = nil; return }
            shareImage = renderShareImage(SlipShareCard(legs: model.slip, mult: model.math.mult, won: summary.won,
                                                        stake: model.stake, game: gameLabel(model.g.gameId)))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.22)), in: .rect(cornerRadius: 28))
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

private struct LegRow: View {
    @Environment(GameModel.self) private var model
    let leg: Leg

    var body: some View {
        let color: Color = leg.won == true ? .green : leg.won == false ? .red : .clear
        HStack(spacing: 10) {
            SideChip(side: leg.side)
            Text(leg.market.question).font(.subheadline)
            Spacer()
            Text(status).font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(leg.won == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(color, lineWidth: 1.5) }
        .opacity(leg.won == false ? 0.8 : 1)
        .animation(.snappy, value: leg.won)
    }

    private var status: String {
        if leg.won == true { return "✓ hit" }
        if leg.won == false { return "✗ miss" }
        if let st = model.view?.stats, let stat = leg.market.stat {
            return leg.market.kind == .over ? "\(min(stat(st), leg.market.line))/\(leg.market.line)" : "\(stat(st))/\(leg.market.line)"
        }
        return "live"
    }
}

private struct PlayRow: View {
    let event: PlayEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(fmtClock(event.clock)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            Text(event.text)
                .font(.subheadline.weight(event.tag == .score ? .semibold : .regular))
                .foregroundStyle(style)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var style: AnyShapeStyle {
        switch event.tag {
        case .score: AnyShapeStyle(Brand.goldInk)
        case .good: AnyShapeStyle(.green)
        case .bad: AnyShapeStyle(.red)
        case .pen: AnyShapeStyle(.yellow)
        case .plain: AnyShapeStyle(.primary)
        }
    }
}

// MARK: - Leaderboard

private struct LeaderboardCard: View {
    @Environment(GameModel.self) private var model
    @Binding var showFriends: Bool

    var body: some View {
        @Bindable var model = model
        let rows = model.boardRows
        let winners = rows.filter(\.won).sorted { $0.mult != $1.mult ? $0.mult > $1.mult : $0.order < $1.order }
        let myRank = winners.firstIndex { $0.isMe }
        let top = Array(winners.prefix(5)) + (myRank.map { $0 >= 5 ? [winners[$0]] : [] } ?? [])
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.span == .drive ? "Drive \(model.boardDrive) leaderboard" : "Game standings").font(.title3.bold())
                Spacer()
                Text(gameLabel(model.g.gameId)).font(.caption).foregroundStyle(.secondary)
            }
            Picker("Period", selection: $model.span) {
                Text("This drive").tag(BoardSpan.drive)
                Text("This game").tag(BoardSpan.game)
            }
            .pickerStyle(.segmented)
            HStack {
                Picker("Leaderboard", selection: $model.scope) {
                    Text("Global").tag(BoardScope.global)
                    Text("Friends").tag(BoardScope.friends)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Spacer()
                Button("Add friends") { showFriends = true }.font(.subheadline.weight(.semibold))
            }
            if model.span == .game {
                let standings = model.gameStandings
                let shown = Array(standings.prefix(5)) + (standings.firstIndex { $0.isMe }.map { $0 >= 5 ? [standings[$0]] : [] } ?? [])
                if shown.isEmpty {
                    Text("No settled slips in this game yet.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(shown) { r in StandingRowView(row: r, rank: (standings.firstIndex { $0.id == r.id } ?? 0) + 1) }
                Text("\(standings.count) \(standings.count == 1 ? "player" : "players") this game, ranked by net winnings across every drive.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if top.isEmpty {
                    Text(model.scope == .friends && model.friends.isEmpty ? "Add friends to see how they did on each drive."
                         : "No \(model.scope == .friends ? "friend's " : "")slip hit on this drive.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(top) { r in
                    BoardRowView(row: r, rank: (winners.firstIndex { $0.id == r.id } ?? 0) + 1)
                }
                Text(footer(rows: rows, hits: winners.count)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .onChange(of: model.scope) { model.save() }
        .onChange(of: model.span) { model.save() }
    }

    private func footer(rows: [BoardRow], hits: Int) -> String {
        let sims = rows.filter(\.isBot).count
        let busted = rows.filter { $0.picks > 0 && !$0.won }.count
        let watched = rows.filter { $0.picks == 0 }.count
        var parts = ["\(hits) hit", "\(busted) busted"]
        if watched > 0 { parts.append("\(watched) watched") }
        let who = model.scope == .friends ? "You and friends: " : ""
        return "\(who)\(rows.count) \(rows.count == 1 ? "player" : "players") (\(sims) simulated) · \(parts.joined(separator: " · "))."
    }
}

private struct BoardRowView: View {
    let row: BoardRow
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
                Text("\(row.picks) \(row.picks == 1 ? "pick" : "picks") · +\(money(row.payout))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Text("×\(Pricing.fmt(row.mult))")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(rank == 1 ? AnyShapeStyle(Brand.goldInk) : AnyShapeStyle(.primary))
                .shadow(color: rank == 1 ? Brand.gold.opacity(0.6) : .clear, radius: 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(row.isMe ? AnyShapeStyle(Brand.gold.opacity(0.18)) : AnyShapeStyle(.primary.opacity(0.05)), in: .rect(cornerRadius: 18))
        .overlay { if row.isMe { RoundedRectangle(cornerRadius: 18).stroke(Brand.goldInk, lineWidth: 1.5) } }
    }
}

struct Avatar: View {
    let name: String
    let color: Color
    var isMe = false
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(color)
            if isMe {
                Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(.white)
            } else {
                Text(String(name.filter(\.isUppercase).prefix(2))).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

struct SimTag: View {
    var body: some View {
        Text("Sim").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.primary.opacity(0.08), in: .capsule)
    }
}

// MARK: - Friends

struct FriendsSheet: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let following = bots.indices.filter { model.friends.contains("bot:\($0)") }
        NavigationStack {
            List {
                Section("Following") {
                    if following.isEmpty {
                        Text("You're not following anyone yet.").foregroundStyle(.secondary)
                    }
                    ForEach(following, id: \.self) { FriendRow(index: $0) }
                }
                Section("Simulated players") {
                    ForEach(bots.indices, id: \.self) { FriendRow(index: $0) }
                }
                Section("People") {
                    Text("Following real people needs player accounts and an online leaderboard. The web version gets these from claude.ai sign-in; this app needs its own, such as Sign in with Apple plus a server.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct FriendRow: View {
    @Environment(GameModel.self) private var model
    let index: Int

    var body: some View {
        let bot = bots[index], id = "bot:\(index)", on = model.friends.contains(id)
        HStack(spacing: 12) {
            Avatar(name: bot.name, color: bot.color, size: 32)
            Text(bot.name).font(.body.weight(.semibold))
            SimTag()
            Spacer()
            if on {
                Button("Following") { model.toggleFriend(id) }.buttonStyle(.glass)
            } else {
                BrandButton(title: "Follow") { model.toggleFriend(id) }
            }
        }
    }
}

// MARK: - Final

struct FinalView: View {
    @Environment(GameModel.self) private var model
    let insets: EdgeInsets

    var body: some View {
        let a = model.g.score[0], b = model.g.score[1]
        let winner = a == b ? "Tie game" : "\(teams[a > b ? 0 : 1].abbr) win"
        let next = gameStart(model.g.gameId).addingTimeInterval(gameWindow).formatted(date: .omitted, time: .shortened)
        VStack(alignment: .leading, spacing: 14) {
            Text("Final")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
            Text("\(winner), \(max(a, b))–\(min(a, b))").font(.system(size: 32, weight: .bold))
            Text(money(model.bank)).font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Brand.goldInk)
            Text("Bank after the game · \(model.wins) slips hit, \(model.losses) busted.").foregroundStyle(.secondary)
            Text(model.isReplay
                 ? "A replay of this game is unranked: your first result on each drive is the one on the leaderboard. The next ranked game starts at \(next)."
                 : "A new ranked game is ready.")
                .font(.subheadline).foregroundStyle(.secondary)
            BrandButton(title: model.isReplay ? "Replay" : "Play the new game") { model.newGame() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .padding(.horizontal, 16)
        .padding(.top, insets.top)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}
