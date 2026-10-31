import CryptoKit
import Foundation

/// An error the player can see, with the HTTP status it goes out as.
struct ServiceError: Error {
    let status: Int
    let message: String
    static func bad(_ m: String) -> ServiceError { ServiceError(status: 400, message: m) }
}

struct User {
    let id: String
    let name: String
}

/// The game rules on the server. Everything here runs on one queue (the HTTP layer's), so there is no locking.
final class Service {
    let store: Store
    /// Mixed into every drive seed. Without it, anyone with the app's code could compute drives ahead of time.
    private let secret: String
    private let now: () -> Date
    /// Feeds are the same for every player on a drive, and building one takes about a second, so keep recent ones.
    private var feeds: [String: [Market]] = [:]
    private var feedOrder: [String] = []

    init(store: Store, secret: String, now: @escaping () -> Date = Date.init) {
        self.store = store; self.secret = secret; self.now = now
    }

    private var stamp: Int { Int(now().timeIntervalSince1970) }

    // MARK: Accounts

    /// A new anonymous account with the starting trophies. Sign in with Apple replaces this before launch.
    func createAccount(name: String?) throws -> AccountReply {
        let id = UUID().uuidString.lowercased()
        let token = Self.randomHex(32)
        let clean = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)
        let display = clean.isEmpty ? "Player \(id.prefix(4).uppercased())" : String(clean)
        try store.transaction {
            try store.run("INSERT INTO users (id, token_hash, name, created_at) VALUES (?, ?, ?, ?)", [id, Self.hash(token), display, stamp])
            try credit(id, Economy.startingBalance, "signup", nil)
        }
        return AccountReply(userId: id, token: token, name: display, balance: Economy.startingBalance)
    }

    func user(token: String) throws -> User? {
        let r = try store.rows("SELECT id, name FROM users WHERE token_hash = ?", [Self.hash(token)])
        guard let row = r.first, let id = row[0] as? String, let name = row[1] as? String else { return nil }
        return User(id: id, name: name)
    }

    func me(_ u: User) throws -> MeReply { MeReply(userId: u.id, name: u.name, balance: try balance(u.id)) }

    // MARK: Ledger

    func balance(_ userId: String) throws -> Int {
        let r = try store.rows("SELECT COALESCE(SUM(amount), 0) FROM ledger WHERE user_id = ?", [userId])
        return Int(r.first?.first as? Int64 ?? 0)
    }

    private func credit(_ userId: String, _ amount: Int, _ reason: String, _ ref: String?) throws {
        try store.run("INSERT INTO ledger (user_id, amount, reason, ref, created_at) VALUES (?, ?, ?, ?, ?)", [userId, amount, reason, ref, stamp])
    }

    func ledger(_ u: User, limit: Int = 50) throws -> [LedgerEntry] {
        try store.rows("SELECT id, amount, reason, ref, created_at FROM ledger WHERE user_id = ? ORDER BY id DESC LIMIT ?", [u.id, limit]).map {
            LedgerEntry(id: Int($0[0] as? Int64 ?? 0), amount: Int($0[1] as? Int64 ?? 0), reason: $0[2] as? String ?? "",
                        ref: $0[3] as? String, at: Int($0[4] as? Int64 ?? 0))
        }
    }

    /// Pays a daily mission once. Progress is still counted on the phone, so this trusts the claim but caps it
    /// at the listed reward and one payment per mission per day.
    func claim(_ u: User, _ req: ClaimRequest) throws -> BalanceReply {
        guard let reward = Economy.missionRewards[req.mission] else { throw ServiceError.bad("Unknown mission.") }
        let today = DayStamp.of(now())
        guard req.day == today else { throw ServiceError.bad("That mission is from another day.") }
        do {
            try credit(u.id, reward, "mission", "mission:\(today):\(req.mission)")
        } catch StoreError.constraint {
            throw ServiceError(status: 409, message: "Already claimed today.")
        }
        return BalanceReply(balance: try balance(u.id))
    }

    // MARK: The game

    /// This player's place in the current game window; a new window starts a fresh game.
    func game(_ u: User) throws -> GameState {
        let gid = currentGameId(now())
        if let row = try store.rows("SELECT state FROM games WHERE user_id = ? AND game_id = ?", [u.id, gid]).first,
           let json = row[0] as? String, let g = try? JSONDecoder().decode(GameState.self, from: Data(json.utf8)) {
            return g
        }
        var g = GameState()
        g.gameId = gid
        return g
    }

    private func save(_ u: User, _ g: GameState) throws {
        let json = String(decoding: try JSONEncoder().encode(g), as: UTF8.self)
        try store.run("INSERT INTO games (user_id, game_id, state) VALUES (?, ?, ?) ON CONFLICT(user_id, game_id) DO UPDATE SET state = excluded.state",
                      [u.id, g.gameId, json])
    }

    func markets(for g: GameState) -> [Market] {
        if let m = feeds[g.key] { return m }
        let m = FeedBuilder.build(start: g.driveStart, offense: teamAbbrs[g.off], defense: teamAbbrs[1 - g.off], seed: g.marketSeed(secret))
        feeds[g.key] = m
        feedOrder.append(g.key)
        if feedOrder.count > 64 { feeds[feedOrder.removeFirst()] = nil }
        return m
    }

    func feed(_ u: User) throws -> FeedReply {
        let g = try game(u)
        return FeedReply(game: g, balance: try balance(u.id), markets: g.over ? [] : markets(for: g).map(\.dto))
    }

    /// The snap: check the slip, take the stake, play the drive, settle, pay, and move the game on, all in one
    /// transaction. The drive is played from the secret seed only after the slip is locked in.
    func snap(_ u: User, _ req: SnapRequest) throws -> SnapReply {
        try store.transaction {
            var g = try game(u)
            guard !g.over else { throw ServiceError(status: 409, message: "This game is over. A new one starts with the next window.") }
            guard req.gameId == g.gameId, req.drive == g.drive else {
                throw ServiceError(status: 409, message: "That drive has already been played. Pull to refresh.")
            }
            let feed = markets(for: g)
            let legs = try validate(req, feed)
            let mult = legs.isEmpty ? 0 : Pricing.math(legs).mult
            var bank = try balance(u.id)
            if !legs.isEmpty {
                guard req.stake <= bank else { throw ServiceError(status: 402, message: "Not enough trophies for that stake.") }
                try credit(u.id, -req.stake, "stake", "\(g.key)")
                bank -= req.stake
            }

            let rng = RNG(g.playSeed(secret))
            let out = DriveEngine.simulate(g.driveStart, rng: rng, record: true)
            let drive = g.drive
            let after = g.apply(out, rng: rng)

            var slip: SlipDTO?
            if !legs.isEmpty {
                let won = legs.allSatisfy { $0.market.outcome(out.stats, done: true) == ($0.side == .yes) }
                let pay = won ? Int(payout(req.stake, mult)) : 0
                if pay > 0 { try credit(u.id, pay, "payout", "\(req.gameId)-d\(drive)"); bank += pay }
                let legsJSON = String(decoding: try JSONEncoder().encode(req.legs), as: UTF8.self)
                let id = try store.run("INSERT INTO slips (user_id, game_id, drive, legs, stake, mult, won, payout, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                       [u.id, req.gameId, drive, legsJSON, req.stake, mult, won, pay, stamp])
                slip = SlipDTO(id: Int(id), legs: req.legs, stake: req.stake, mult: mult, won: won, payout: pay)
            }
            var reloaded = false
            if bank < Economy.reloadBelow {
                try credit(u.id, Economy.startingBalance - bank, "reload", nil)
                bank = Economy.startingBalance
                reloaded = true
            }
            try save(u, g)
            return SnapReply(drive: drive, log: out.log, stats: out.stats, yl: out.yl, qtr: out.qtr, clock: out.clock,
                             after: after, game: g, slip: slip, balance: bank, reloaded: reloaded)
        }
    }

    /// Rebuilds the slip from the server's own markets and prices. The app shows the same rules as you swipe,
    /// but only this check counts.
    private func validate(_ req: SnapRequest, _ feed: [Market]) throws -> [Leg] {
        if req.legs.isEmpty { return [] }
        guard Economy.stakes.contains(req.stake) else { throw ServiceError.bad("Stakes are 10, 50, 100 or 250 trophies.") }
        guard req.legs.count <= Pricing.maxLegs else { throw ServiceError.bad(Blocked.slipFull.message) }
        guard Set(req.legs.map(\.market)).count == req.legs.count else { throw ServiceError.bad("Each market can be picked once.") }
        let legs = try req.legs.map { l -> Leg in
            guard let m = feed.first(where: { $0.id == l.market }) else { throw ServiceError.bad("\(l.market) isn't listed on this drive.") }
            return Leg(market: m, side: l.side, price: m.ask(l.side))
        }
        if Pricing.joint(legs).hits < 4 { throw ServiceError.bad(Blocked.conflicts.message) }
        if Pricing.math(legs).raw > Pricing.maxMult { throw ServiceError.bad(Blocked.overCap.message) }
        return legs
    }

    // MARK: Helpers

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func randomHex(_ bytes: Int) -> String {
        var g = SystemRandomNumberGenerator()
        return (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &g)) }.joined()
    }
}

/// The calendar day a mission belongs to, in the same form the app uses.
enum DayStamp {
    static func of(_ date: Date) -> String { date.formatted(.iso8601.year().month().day()) }
}
