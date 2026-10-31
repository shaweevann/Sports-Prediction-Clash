import SwiftUI

// MARK: - Types

/// A simulated player's slip for the current drive, chosen when the markets open.
struct BotSlip {
    let legs: [Leg]
    let stake: Int
}

/// How a simulated player's slip settled, kept for the game standings.
struct BotResult: Codable {
    let bot: Int
    let mult: Double, picks: Int, won: Bool, stake: Int, payout: Double
}

enum BoardSpan: String, Codable { case drive, game }

/// One player's running total across the drives of this game.
struct Standing: Identifiable {
    let id: String
    let name: String
    let color: Color
    let isBot: Bool
    let isMe: Bool
    var net = 0.0, hits = 0, played = 0, best = 0.0
}

/// Today's counters for the daily missions; resets at local midnight.
struct DayProgress: Codable {
    var date = DayProgress.today
    var drives = 0, hits = 0, bigSlips = 0, tails = 0, shares = 0, follows = 0, tenX = 0
    var claimed: [String] = []
    static var today: String { Date().formatted(.iso8601.year().month().day()) }
}

struct Mission: Identifiable {
    let id: String
    let title: String
    let goal: Int
    let reward: Int
    let count: (DayProgress) -> Int
}

/// Three of these are picked each day, the same three for everyone.
let missionPool: [Mission] = [
    Mission(id: "play5", title: "Play 5 drives", goal: 5, reward: 100) { $0.drives },
    Mission(id: "hit2", title: "Hit 2 slips", goal: 2, reward: 200) { $0.hits },
    Mission(id: "big", title: "Snap a slip with 3+ picks", goal: 1, reward: 100) { $0.bigSlips },
    Mission(id: "tail", title: "Tail a friend's slip", goal: 1, reward: 100) { $0.tails },
    Mission(id: "share", title: "Share a slip", goal: 1, reward: 50) { $0.shares },
    Mission(id: "follow", title: "Follow 2 players", goal: 2, reward: 50) { $0.follows },
    Mission(id: "tenx", title: "Hit a ×10 slip", goal: 1, reward: 300) { $0.tenX },
]

// MARK: - Simulated players, tailing and boards

extension GameModel {
    /// Seeded by game and drive, so every player sees the same simulated slips.
    func planBots() {
        botSlips = [:]
        guard simPlayers else { return }
        let r = RNG("\(key):bots")
        for (i, bot) in bots.enumerated() {
            if r.next() > bot.play { continue }
            let legs = botSlip(bot, r)
            if legs.isEmpty { continue }
            botSlips[i] = BotSlip(legs: legs, stake: bot.stakes[r.int(bot.stakes.count)])
        }
    }

    private func botSlip(_ bot: Bot, _ r: RNG) -> [Leg] {
        let target = bot.legs.lowerBound + r.int(bot.legs.count)
        var order = markets
        for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, r.int(i + 1)) }
        var legs: [Leg] = []
        for m in order where legs.count < target {
            let yesIsDog = m.open < 50
            let side: Side = (r.next() < bot.dog) == yesIsDog ? .yes : .no
            if case .success(let trial) = Pricing.tryAdd(Leg(market: m, side: side, price: m.openAsk(side)), to: legs) { legs = trial }
        }
        return legs
    }

    func settleBots(_ k: String, _ st: DriveStats) {
        botResults[k] = botSlips.keys.sorted().compactMap { i in
            guard let s = botSlips[i] else { return nil }
            let won = s.legs.allSatisfy { $0.market.outcome(st, done: true) == ($0.side == .yes) }
            let mult = Pricing.math(s.legs).mult
            return BotResult(bot: i, mult: mult, picks: s.legs.count, won: won, stake: s.stake, payout: won ? payout(s.stake, mult) : 0)
        }
    }

    func isFriend(_ bot: Int) -> Bool { friends.contains("bot:\(bot)") }

    /// Who is on one side of a market this drive; friends listed separately.
    func backers(_ m: Market, _ side: Side) -> (friends: [Int], total: Int) {
        var f: [Int] = [], n = 0
        for (i, s) in botSlips where s.legs.contains(where: { $0.market === m && $0.side == side }) {
            n += 1
            if isFriend(i) { f.append(i) }
        }
        return (f.sorted(), n)
    }

    /// Slips you can copy before the snap: friends first, then the biggest multipliers.
    var tailable: [(bot: Int, slip: BotSlip, mult: Double)] {
        botSlips.map { (bot: $0.key, slip: $0.value, mult: Pricing.math($0.value.legs).mult) }
            .sorted { a, b in isFriend(a.bot) != isFriend(b.bot) ? isFriend(a.bot) : a.mult > b.mult }
    }

    /// Replace your slip with a simulated player's picks, at today's prices.
    func tail(_ i: Int) {
        guard phase == .market, let s = botSlips[i], debounce("tail:\(i)") else { return }
        var legs: [Leg] = []
        for l in s.legs {
            if case .success(let t) = Pricing.tryAdd(Leg(market: l.market, side: l.side, price: l.market.ask(l.side)), to: legs) { legs = t }
        }
        guard !legs.isEmpty else { show("That slip doesn't fit at today's prices."); return }
        slip = legs
        bump += 1
        show(legs.count == s.legs.count ? "Tailed \(bots[i].name): \(legs.count) picks"
                                         : "Tailed \(bots[i].name): \(legs.count) of \(s.legs.count) picks fit")
        updateDay { $0.tails += 1 }   // after, so a completed mission's message isn't covered
        save()
    }

    /// Everyone who has a result for the drive on the board, filtered to friends when that tab is on.
    var boardRows: [BoardRow] {
        var rows = (botResults[boardKey] ?? []).map { r in
            BoardRow(id: "bot:\(r.bot)", name: bots[r.bot].name, color: bots[r.bot].color, isBot: true, isMe: false,
                     mult: r.mult, picks: r.picks, won: r.won, payout: r.payout, order: r.bot)
        }
        if let e = mine[boardKey] {
            rows.append(BoardRow(id: "me", name: "You", color: Brand.burgundy, isBot: false, isMe: true, mult: e.mult, picks: e.picks,
                                 won: e.won, payout: e.payout, order: -1))
        }
        if scope == .friends { rows = rows.filter { $0.isMe || friends.contains($0.id) } }
        return rows
    }

    /// Net winnings across this game's drives, best first.
    var gameStandings: [Standing] {
        var table: [String: Standing] = [:]
        let prefix = "\(g.gameId)-d"
        for (k, rows) in botResults where k.hasPrefix(prefix) {
            for r in rows {
                let id = "bot:\(r.bot)"
                var s = table[id] ?? Standing(id: id, name: bots[r.bot].name, color: bots[r.bot].color, isBot: true, isMe: false)
                s.net += r.payout - Double(r.stake); s.played += 1
                if r.won { s.hits += 1; s.best = max(s.best, r.mult) }
                table[id] = s
            }
        }
        for (k, e) in mine where k.hasPrefix(prefix) && !e.pending && e.picks > 0 {
            var s = table["me"] ?? Standing(id: "me", name: "You", color: Brand.burgundy, isBot: false, isMe: true)
            s.net += e.payout - Double(e.stake); s.played += 1
            if e.won { s.hits += 1; s.best = max(s.best, e.mult) }
            table["me"] = s
        }
        var list = Array(table.values)
        if scope == .friends { list = list.filter { $0.isMe || friends.contains($0.id) } }
        return list.sorted { $0.net != $1.net ? $0.net > $1.net : $0.best > $1.best }
    }

    func toggleFriend(_ id: String) {
        if friends.contains(id) { friends.remove(id) } else { friends.insert(id); updateDay { $0.follows += 1 } }
        save()
    }

    // MARK: - Missions, streaks and levels

    /// The same three missions for everyone on a given day.
    var missions: [Mission] {
        let r = RNG("missions:\(day.date)")
        var pool = missionPool
        for i in stride(from: pool.count - 1, to: 0, by: -1) { pool.swapAt(i, r.int(i + 1)) }
        return Array(pool.prefix(3))
    }
    func progress(_ m: Mission) -> Int { min(m.count(day), m.goal) }
    func canClaim(_ m: Mission) -> Bool { progress(m) >= m.goal && !day.claimed.contains(m.id) }
    var claimable: Int { missions.filter(canClaim).count }

    func claim(_ m: Mission) {
        guard canClaim(m) else { return }
        day.claimed.append(m.id)
        bank += Double(m.reward)
        winPulse += 1
        show("+\(trophies(Double(m.reward))) and 50 XP")
        gainXP(50)
        save()
    }

    /// Level n starts at 60 × (n − 1)² XP, so each level takes a little longer than the last.
    var level: Int { Int((Double(xp) / 60).squareRoot()) + 1 }
    static func xpFor(_ level: Int) -> Int { 60 * (level - 1) * (level - 1) }
    var levelProgress: Double {
        let lo = Self.xpFor(level), hi = Self.xpFor(level + 1)
        return Double(xp - lo) / Double(hi - lo)
    }

    func gainXP(_ n: Int) {
        let before = level
        xp += n
        if level > before { show("Level \(level)!") }
    }

    /// Start a fresh set of counters after midnight.
    func rollDay() {
        if day.date != DayProgress.today { day = DayProgress() }
    }

    /// Change today's counters and announce any mission that just became claimable.
    func updateDay(_ change: (inout DayProgress) -> Void) {
        rollDay()
        let before = Set(missions.filter(canClaim).map(\.id))
        change(&day)
        if let done = missions.first(where: { canClaim($0) && !before.contains($0.id) }) {
            show("Mission complete: \(done.title)")
        }
    }

    func progressOnSnap() {
        guard !slip.isEmpty else { return }
        let picks = slip.count
        updateDay { d in d.drives += 1; if picks >= 3 { d.bigSlips += 1 } }
        gainXP(10)
    }

    func progressOnFinish(hadSlip: Bool, won: Bool, mult: Double) {
        guard hadSlip else { return }   // watching a drive leaves the streak alone
        if won {
            streak += 1
            bestStreak = max(bestStreak, streak)
            updateDay { d in d.hits += 1; if mult >= 10 { d.tenX += 1 } }
            gainXP(25)
        } else {
            streak = 0
        }
    }

    func didShare() {
        updateDay { $0.shares += 1 }
        save()
    }
}
