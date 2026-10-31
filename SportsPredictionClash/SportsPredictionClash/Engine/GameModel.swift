import SwiftUI
import Observation

struct Team {
    let abbr: String, name: String, color: Color
}

let teams = [
    Team(abbr: "BAY", name: "Gulls", color: Color(red: 0.12, green: 0.64, blue: 0.72)),
    Team(abbr: "IRN", name: "Pines", color: Color(red: 0.91, green: 0.45, blue: 0.18)),
]

/// One shared game per two-hour window: everyone in the window plays the same seeded game at their own pace.
let gameWindow: TimeInterval = 2 * 3600
func currentGameId() -> String { "g\(Int(Date().timeIntervalSince1970 / gameWindow))" }
func gameStart(_ id: String) -> Date { Date(timeIntervalSince1970: Double(Int(id.dropFirst()) ?? 0) * gameWindow) }
func gameLabel(_ id: String) -> String {
    let f = Date.FormatStyle().hour()
    let s = gameStart(id)
    return "\(s.formatted(f))–\(s.addingTimeInterval(gameWindow).formatted(f)) game"
}

struct GameState: Codable {
    var score = [0, 0], qtr = 1, clock = 900, off = 0, yl = 25, drive = 1, firstReceiver = 0, over = false
    var gameId = currentGameId()
}

enum Phase { case loading, market, live, done, final }
enum BoardScope: String, Codable { case global, friends }

struct DriveSummary {
    let title: String
    let detail: String
    let line: String
    let won: Bool?   // nil = watched without a slip
}

/// The first slip snapped on a drive is the ranked one; settling may only resolve that same slip.
struct DriveEntry: Codable {
    var sig: String, mult: Double, picks: Int, won: Bool, stake: Int, payout: Double, pending: Bool
}

struct BoardRow: Identifiable {
    let id: String
    let name: String
    let color: Color
    let isBot: Bool
    let isMe: Bool
    let mult: Double, picks: Int, won: Bool, payout: Double, order: Int
}

struct Bot {
    let name: String, color: Color
    let legs: ClosedRange<Int>
    /// Chance of taking the cheaper (underdog) side, and of betting a given drive.
    let dog: Double, play: Double
    let stakes: [Int]
    var initials: String { String(name.filter(\.isUppercase).prefix(2)) }
}

/// Simulated players. Each drive the ones who show up build a slip from the same feed at opening prices and settle
/// against the same drive, seeded by game and drive so every player sees the same bots with the same results.
let simPlayers = true
let bots: [Bot] = [
    Bot(name: "BlitzKing", color: Color(red: 0.85, green: 0.28, blue: 0.06), legs: 5...8, dog: 0.8, play: 0.9, stakes: [10, 50]),
    Bot(name: "ChainMover", color: Color(red: 0.17, green: 0.54, blue: 0.24), legs: 2...3, dog: 0.2, play: 0.95, stakes: [100, 250]),
    Bot(name: "RedZoneRita", color: Color(red: 0.76, green: 0.15, blue: 0.36), legs: 3...5, dog: 0.5, play: 0.85, stakes: [50, 100]),
    Bot(name: "PuntGod", color: Color(red: 0.37, green: 0.24, blue: 0.77), legs: 1...2, dog: 0.15, play: 0.7, stakes: [250]),
    Bot(name: "HailMaryHank", color: Color(red: 0.91, green: 0.35, blue: 0.05), legs: 6...8, dog: 0.9, play: 0.75, stakes: [10]),
    Bot(name: "SlantRoute", color: Color(red: 0.10, green: 0.44, blue: 0.76), legs: 3...4, dog: 0.4, play: 0.8, stakes: [50]),
    Bot(name: "TwoMinuteTess", color: Color(red: 0.05, green: 0.52, blue: 0.60), legs: 2...5, dog: 0.55, play: 0.65, stakes: [50, 100, 250]),
    Bot(name: "CoverTwo", color: Color(red: 0.36, green: 0.58, blue: 0.05), legs: 2...4, dog: 0.3, play: 0.75, stakes: [100]),
    Bot(name: "PocketPasser", color: Color(red: 0.21, green: 0.31, blue: 0.78), legs: 1...3, dog: 0.35, play: 0.8, stakes: [50, 100]),
    Bot(name: "GoalLineGabe", color: Color(red: 0.65, green: 0.12, blue: 0.30), legs: 4...6, dog: 0.65, play: 0.7, stakes: [10, 50]),
    Bot(name: "SafetyValve", color: Color(red: 0.03, green: 0.50, blue: 0.36), legs: 1...2, dog: 0.1, play: 0.85, stakes: [100, 250]),
    Bot(name: "Pick6Paige", color: Color(red: 0.53, green: 0.18, blue: 0.61), legs: 3...6, dog: 0.7, play: 0.6, stakes: [10, 50]),
    Bot(name: "AudibleAndy", color: Color(red: 0.90, green: 0.47, blue: 0.0), legs: 2...3, dog: 0.45, play: 0.8, stakes: [50]),
    Bot(name: "FlexBone", color: Color(red: 0.18, green: 0.62, blue: 0.27), legs: 1...3, dog: 0.25, play: 0.75, stakes: [50, 100]),
    Bot(name: "NickelPackage", color: Color(red: 0.09, green: 0.39, blue: 0.67), legs: 2...4, dog: 0.5, play: 0.7, stakes: [50, 100]),
    Bot(name: "OnsideKiki", color: Color(red: 0.79, green: 0.16, blue: 0.16), legs: 7...8, dog: 0.95, play: 0.5, stakes: [10]),
]

@MainActor
@Observable
final class GameModel {
    static let marketSeconds = 60
    static let hurrySeconds = 10
    static let stakes = [10, 50, 100, 250]

    var g = GameState()
    var phase: Phase = .loading
    var markets: [Market] = []
    var slip: [Leg] = []
    var stake = 50
    var bank = 1000.0
    var wins = 0
    var losses = 0
    var timeLeft = marketSeconds
    var page: Int? = 0
    var notes: [String: String] = [:]
    var toast: String?
    var bump = 0
    var winPulse = 0

    // Live drive
    var view: PlayEvent?
    var pbp: [PlayEvent] = []
    var summary: DriveSummary?
    var lastResult = ""
    var afterNote = ""

    // Leaderboard
    var boardKey = ""
    var boardDrive = 0
    var mine: [String: DriveEntry] = [:]
    var friends: Set<String> = []
    var scope: BoardScope = .global
    var span: BoardSpan = .drive

    // Social: simulated players pick their slips when the markets open, so friends can be seen and tailed
    var botSlips: [Int: BotSlip] = [:]
    var botResults: [String: [BotResult]] = [:]

    // Progress
    var xp = 0
    var streak = 0
    var bestStreak = 0
    var day = DayProgress()

    // Sheets opened from the top bar
    var showTail = false
    var showProgress = false

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var outcome: DriveOutcome?
    @ObservationIgnored private var playRng: RNG?
    @ObservationIgnored private var shown = 0
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var lastTap: (key: String, at: Date) = ("", .distantPast)


    // MARK: Derived

    var offense: Team { teams[g.off] }
    var defense: Team { teams[1 - g.off] }
    var math: SlipMath { Pricing.math(slip) }
    var busted: Bool { slip.contains { $0.won == false } }
    /// 0...1 heat on a log scale, so every pick warms the multiplier about the same.
    var heat: Double { slip.isEmpty || busted ? 0 : clamp(log(math.mult) / log(Pricing.maxMult), 0, 1) }
    var hurry: Bool { phase == .market && timeLeft <= Self.hurrySeconds }
    var key: String { "\(g.gameId)-d\(g.drive)" }

    func leg(for m: Market) -> Leg? { slip.first { $0.market === m } }

    /// Why a side can't join the slip right now, or nil if it can.
    func blocked(_ m: Market, _ side: Side) -> Blocked? {
        guard leg(for: m) == nil, !slip.isEmpty else { return nil }
        if case .failure(let b) = check(m, side) { return b }
        return nil
    }
    func locked(_ m: Market) -> Bool { blocked(m, .yes) != nil && blocked(m, .no) != nil }

    func caption(_ m: Market, _ side: Side) -> String {
        if let l = leg(for: m), l.side == side { return "Picked · tap to remove" }
        if slip.isEmpty || (slip.count == 1 && leg(for: m) != nil) { return "wins \(trophies(payout(stake, 100 / Double(m.ask(side)))))" }
        switch check(m, side) {
        case .failure(let b): return b.short
        case .success(let mult): return "slip → ×\(Pricing.fmt(mult))"
        }
    }

    // MARK: Fast slip checks
    // Cards re-render several times a second and each asks whether both sides fit the slip. Rather than rescanning
    // every simulated drive for every leg on each ask, keep one mask of the drives where the whole slip hits and
    // test a candidate against it in a single pass. Same rules as Pricing.tryAdd.

    @ObservationIgnored private var cacheKey = ""
    @ObservationIgnored private var mask: [UInt8] = []
    @ObservationIgnored private var maskHits = 0
    @ObservationIgnored private var slipNaive = 1.0
    @ObservationIgnored private var slipIndep = 1.0
    @ObservationIgnored private var slipMult = 1.0

    private func refreshCache() {
        let k = slip.map { "\($0.market.id):\($0.side.rawValue):\($0.price)" }.joined(separator: ",")
        guard k != cacheKey else { return }
        cacheKey = k
        let n = markets.first?.bits.count ?? 0
        mask = [UInt8](repeating: 1, count: n)
        for l in slip {
            let want: UInt8 = l.side == .yes ? 1 : 0
            for i in 0..<n where mask[i] == 1 && l.market.bits[i] != want { mask[i] = 0 }
        }
        maskHits = mask.reduce(0) { $0 + Int($1) }
        slipNaive = slip.reduce(1) { $0 * 100 / Double($1.price) }
        slipIndep = slip.reduce(1) { $0 * $1.fair }
        slipMult = slip.isEmpty ? 1 : Pricing.math(slip).mult
    }

    /// Multiplier the slip would have with this pick added, or why it can't be added.
    private func check(_ m: Market, _ side: Side) -> Result<Double, Blocked> {
        if leg(for: m) != nil {
            // Switching sides on a market already in the slip: rare, use the full check
            return Pricing.tryAdd(Leg(market: m, side: side, price: m.ask(side)), to: slip).map { Pricing.math($0).mult }
        }
        refreshCache()
        if slip.count + 1 > Pricing.maxLegs { return .failure(.slipFull) }
        let want: UInt8 = side == .yes ? 1 : 0
        var hits = 0
        for i in 0..<mask.count where mask[i] == 1 && m.bits[i] == want { hits += 1 }
        if hits < 4 { return .failure(.conflicts) }
        let n = Double(mask.count + 1)
        let jp = (Double(hits) + 0.5) / n, jOthers = (Double(maskHits) + 0.5) / n
        if !slip.isEmpty && jp / jOthers > 0.97 { return .failure(.covered) }
        let fair = side == .yes ? m.p : 1 - m.p
        let raw = slipNaive * 100 / Double(m.ask(side)) * slipIndep * fair / jp
        if raw > Pricing.maxMult { return .failure(.overCap) }
        if raw / slipMult < Pricing.minStep { return .failure(.tooSafe) }
        return .success(raw)
    }

    // MARK: Markets phase

    func start() async {
        if g.over { phase = .final; return }
        await openMarkets()
    }

    func openMarkets() async {
        if g.over { phase = .final; return }
        phase = .loading
        slip = []; notes = [:]; summary = nil; pbp = []; view = nil; page = 0
        let start = DriveStart(yl: g.yl, qtr: g.qtr, clock: g.clock, trailing: g.score[g.off] < g.score[1 - g.off])
        let seed = "\(g.gameId):\(g.drive):markets", o = offense.abbr, d = defense.abbr
        markets = await Task.detached(priority: .userInitiated) {
            FeedBuilder.build(start: start, offense: o, defense: d, seed: seed)
        }.value
        timeLeft = Self.marketSeconds
        rollDay()
        planBots()
        phase = .market
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.phase == .market else { return }
                n += 1
                if n % 4 == 0 { self.markets.forEach { $0.tick() } }
                if n % 3 == 0 {
                    self.timeLeft -= 1
                    if self.timeLeft <= 0 { self.snap(); return }
                }
            }
        }
    }

    func pick(_ m: Market, _ side: Side, source: String = "button") {
        guard phase == .market, source == "remove" || debounce("pick:\(m.id)") else { return }
        if let l = leg(for: m), l.side == side {
            slip.removeAll { $0.market === m }
            m.mid = clamp(m.mid + (side == .yes ? -1 : 1), 2, 98)
            notes[m.id] = "Removed from slip"
            return
        }
        let leg = Leg(market: m, side: side, price: m.ask(side))
        switch Pricing.tryAdd(leg, to: slip) {
        case .failure(let b):
            notes[m.id] = b.message
            show(b.message)
        case .success(let trial):
            slip = trial
            m.mid = clamp(m.mid + (side == .yes ? 1.2 : -1.2), 2, 98)   // your order moves the book
            m.vol += stake
            notes[m.id] = "Added \(side.label) at ×\(Pricing.fmt(100 / Double(leg.price)))"
            bump += 1
            advance(from: markets.firstIndex { $0 === m } ?? 0)
        }
    }

    func remove(_ leg: Leg) { pick(leg.market, leg.side, source: "remove") }

    /// Move to the next card that can still join the slip.
    private func advance(from i: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self, self.phase == .market, self.page == i else { return }
            var k = i + 1
            while k < self.markets.count && self.locked(self.markets[k]) { k += 1 }
            if k >= self.markets.count && !self.markets.contains(where: { self.leg(for: $0) == nil && !self.locked($0) }) {
                self.show("Nothing else fits. Snap it!")
            }
            withAnimation(.snappy) { self.page = k }
        }
    }

    // MARK: Live phase

    func snap() {
        guard phase == .market else { return }
        if !slip.isEmpty && Double(stake) > bank { show("Not enough trophies. Lower your stake first."); return }
        tickTask?.cancel()
        if !slip.isEmpty { bank -= Double(stake) }
        progressOnSnap()
        for i in slip.indices { slip[i].won = nil }
        // Lock the slip in at the snap, so seeing the drive and replaying can't change this drive's ranked result
        record(key, DriveEntry(sig: slipSig, mult: slip.isEmpty ? 0 : math.mult, picks: slip.count, won: false,
                               stake: slip.isEmpty ? 0 : stake, payout: 0, pending: true), settle: false)
        let start = DriveStart(yl: g.yl, qtr: g.qtr, clock: g.clock, trailing: g.score[g.off] < g.score[1 - g.off])
        let rng = RNG("\(g.gameId):\(g.drive):play")
        let out = DriveEngine.simulate(start, rng: rng, record: true)
        outcome = out; playRng = rng; shown = 0; pbp = []
        phase = .live
        save()
        liveTask?.cancel()
        liveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            while let self, !Task.isCancelled, self.phase == .live {
                self.step()
                if self.phase != .live { return }
                try? await Task.sleep(for: .milliseconds(1400))
            }
        }
    }

    func skip() {
        liveTask?.cancel()
        while phase == .live { step() }
    }

    private func step() {
        guard let out = outcome, shown < out.log.count else { return }
        let e = out.log[shown]
        let done = shown == out.log.count - 1
        withAnimation(.snappy) {
            pbp.insert(e, at: 0)
            view = e
        }
        for i in slip.indices where slip[i].won == nil {
            if let o = slip[i].market.outcome(e.stats, done: done) { slip[i].won = o == (slip[i].side == .yes) }
        }
        shown += 1
        if done { finish(out) }
    }

    private func finish(_ out: DriveOutcome) {
        let driveNo = g.drive, k = key, offAbbr = offense.abbr
        let st = out.stats
        afterNote = applyDrive(out)
        lastResult = st.result.label
        if !afterNote.isEmpty {
            pbp.insert(PlayEvent(id: -1, text: afterNote, tag: .plain, yl: g.yl, down: 1, dist: 10, clock: g.clock, qtr: g.qtr, stats: st), at: 0)
        }
        let line = "\(offAbbr): \(st.result.label) · \(st.plays) plays, \(st.yards) yds, \(fmtClock(st.time))"
        let m = math.mult
        let won = !slip.isEmpty && slip.allSatisfy { $0.won == true }
        if slip.isEmpty {
            summary = DriveSummary(title: st.result.label, detail: "", line: line, won: nil)
        } else if won {
            let win = payout(stake, m)
            bank += win; wins += 1; winPulse += 1
            summary = DriveSummary(title: "Slip hits +\(trophies(win))", detail: slip.count == 1 ? "Your pick landed at ×\(Pricing.fmt(m))." : "All \(slip.count) picks landed at ×\(Pricing.fmt(m)).", line: line, won: true)
        } else {
            losses += 1
            let missed = slip.filter { $0.won == false }.map { "\($0.market.question) (\($0.side.label))" }.joined(separator: ", ")
            summary = DriveSummary(title: "Busted −\(trophies(Double(stake)))", detail: "Missed: \(missed).", line: line, won: false)
        }
        record(k, DriveEntry(sig: slipSig, mult: m, picks: slip.count, won: won, stake: slip.isEmpty ? 0 : stake,
                             payout: won ? payout(stake, m) : 0, pending: false), settle: true)
        settleBots(k, st)
        progressOnFinish(hadSlip: !slip.isEmpty, won: won, mult: m)
        boardKey = k; boardDrive = driveNo
        phase = .done
        if bank < 10 { bank = 1000; show("Out of trophies, so here's 🏆 1,000 to get back in.") }
        save()
    }

    func next() {
        Task { await openMarkets() }
    }

    /// Score, possession and clock after a drive. Uses the drive's own RNG stream so it matches for every player.
    private func applyDrive(_ out: DriveOutcome) -> String {
        let rng = playRng ?? RNG(key)
        let off = g.off, def = 1 - off, st = out.stats, yl = out.yl
        g.qtr = out.qtr; g.clock = out.clock
        var next = 25, note = ""
        func kick() -> Int {
            g.clock = max(0, g.clock - 5)
            if rng.next() < 0.68 { note += " Kickoff, touchback."; return 25 }
            let y = clamp(Int((24 + rng.normal() * 8).rounded()), 8, 60)
            note += " Kickoff returned to the \(y)."
            return y
        }
        switch st.result {
        case .td:
            let xp = rng.next() < 0.95
            g.score[off] += xp ? 7 : 6
            note = "Extra point \(xp ? "is good" : "is missed")."
            next = kick()
        case .fg: g.score[off] += 3; next = kick()
        case .miss: next = max(20, 100 - (yl - 7)); note = "\(teams[def].abbr) take over at the spot of the kick."
        case .punt:
            let spot = yl + st.punt
            next = spot >= 100 ? 20 : 100 - spot
            note = spot >= 100 ? "Punt sails into the end zone. Touchback." : "\(teams[def].abbr) fair catch."
        case .int: next = clamp(100 - yl - Int((8 + rng.normal() * 8).rounded()), 5, 95); note = "\(teams[def].abbr) return it."
        case .fum, .downs: next = 100 - yl
        case .safety: g.score[def] += 2; next = clamp(Int((38 + rng.normal() * 8).rounded()), 20, 60); note = "Free kick after the safety."
        case .half, .none: break
        }
        g.off = def; g.yl = next; g.drive += 1
        if st.result == .half || g.clock <= 0 {
            if g.qtr >= 4 { g.over = true; note += " Final whistle." }
            else if g.qtr == 2 { g.qtr = 3; g.clock = 900; g.off = 1 - g.firstReceiver; g.yl = 25; note += " Halftime. \(teams[g.off].abbr) receive to open the 3rd." }
            else { g.qtr += 1; g.clock = 900 }
        }
        return note.trimmingCharacters(in: .whitespaces)
    }

    func showFinal() { phase = .final }

    var isReplay: Bool { currentGameId() == g.gameId }

    func newGame() {
        g = GameState()
        save()
        Task { await openMarkets() }
    }

    // MARK: Leaderboard

    var slipSig: String { slip.map { "\($0.market.id):\($0.side.rawValue)" }.sorted().joined(separator: ",") }

    private func record(_ k: String, _ e: DriveEntry, settle: Bool) {
        if let old = mine[k] { guard settle, old.pending, old.sig == e.sig else { return } }
        mine[k] = e
    }

    /// Drops a repeat of the same action within a moment, so one tap (or a quick double-tap)
    /// can't add-then-remove a pick or skip straight past the drive's result screen.
    func debounce(_ key: String, _ window: TimeInterval = 0.6) -> Bool {
        let now = Date()
        if lastTap.key == key && now.timeIntervalSince(lastTap.at) < window { return false }
        lastTap = (key, now)
        return true
    }

    // MARK: Toasts

    func show(_ text: String) {
        withAnimation(.snappy) { toast = text }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.toast = nil }
        }
    }

    // MARK: Persistence

    private struct Saved: Codable {
        var bank: Double, wins: Int, losses: Int, stake: Int, game: GameState
        var mine: [String: DriveEntry], friends: [String], scope: BoardScope
        // Added with the social features; optional so older saves still load
        var span: BoardSpan?, botResults: [String: [BotResult]]?
        var xp: Int?, streak: Int?, bestStreak: Int?, day: DayProgress?
    }

    func save() {
        // Keep only this game's simulated results; earlier games' standings aren't shown
        let current = botResults.filter { $0.key.hasPrefix("\(g.gameId)-d") }
        let s = Saved(bank: bank, wins: wins, losses: losses, stake: stake, game: g, mine: mine, friends: Array(friends), scope: scope,
                      span: span, botResults: current, xp: xp, streak: streak, bestStreak: bestStreak, day: day)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "sportspredictionclash.trophies") }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "sportspredictionclash.trophies"), let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        bank = s.bank; wins = s.wins; losses = s.losses; stake = s.stake
        mine = s.mine; friends = Set(s.friends); scope = s.scope
        span = s.span ?? .drive; xp = s.xp ?? 0; streak = s.streak ?? 0; bestStreak = s.bestStreak ?? 0
        day = s.day ?? DayProgress()
        if s.game.gameId == currentGameId() { g = s.game; botResults = s.botResults ?? [:] }
        rollDay()
    }
}
