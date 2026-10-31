import Foundation

/// Team abbreviations, home first. The app adds names and colours.
let teamAbbrs = ["BAY", "IRN"]

/// One shared game per two-hour window: everyone in the window plays the same game at their own pace.
let gameWindow: TimeInterval = 2 * 3600
func currentGameId(_ now: Date = Date()) -> String { "g\(Int(now.timeIntervalSince1970 / gameWindow))" }
func gameStart(_ id: String) -> Date { Date(timeIntervalSince1970: Double(Int(id.dropFirst()) ?? 0) * gameWindow) }
func gameLabel(_ id: String) -> String {
    let f = Date.FormatStyle().hour()
    let s = gameStart(id)
    return "\(s.formatted(f))–\(s.addingTimeInterval(gameWindow).formatted(f)) game"
}

struct GameState: Codable, Equatable {
    var score = [0, 0], qtr = 1, clock = 900, off = 0, yl = 25, drive = 1, firstReceiver = 0, over = false
    var gameId = currentGameId()
}

extension GameState {
    var key: String { "\(gameId)-d\(drive)" }
    var driveStart: DriveStart { DriveStart(yl: yl, qtr: qtr, clock: clock, trailing: score[off] < score[1 - off]) }

    /// Seeds for this drive's feed and its plays. The server mixes in a secret, so nobody can compute a drive
    /// before it is played; without one (local play) anyone with the code can.
    func marketSeed(_ secret: String) -> String { "\(secret)\(gameId):\(drive):markets" }
    func playSeed(_ secret: String) -> String { "\(secret)\(gameId):\(drive):play" }

    /// Score, possession and clock after a drive. Uses the drive's own RNG stream (the one that played it),
    /// so it comes out the same for every player.
    mutating func apply(_ out: DriveOutcome, rng: RNG) -> String {
        let off = self.off, def = 1 - off, st = out.stats, yl = out.yl
        qtr = out.qtr; clock = out.clock
        var next = 25, note = ""
        func kick() -> Int {
            clock = max(0, clock - 5)
            if rng.next() < 0.68 { note += " Kickoff, touchback."; return 25 }
            let y = clamp(Int((24 + rng.normal() * 8).rounded()), 8, 60)
            note += " Kickoff returned to the \(y)."
            return y
        }
        switch st.result {
        case .td:
            let xp = rng.next() < 0.95
            score[off] += xp ? 7 : 6
            note = "Extra point \(xp ? "is good" : "is missed")."
            next = kick()
        case .fg: score[off] += 3; next = kick()
        case .miss: next = max(20, 100 - (yl - 7)); note = "\(teamAbbrs[def]) take over at the spot of the kick."
        case .punt:
            let spot = yl + st.punt
            next = spot >= 100 ? 20 : 100 - spot
            note = spot >= 100 ? "Punt sails into the end zone. Touchback." : "\(teamAbbrs[def]) fair catch."
        case .int: next = clamp(100 - yl - Int((8 + rng.normal() * 8).rounded()), 5, 95); note = "\(teamAbbrs[def]) return it."
        case .fum, .downs: next = 100 - yl
        case .safety: score[def] += 2; next = clamp(Int((38 + rng.normal() * 8).rounded()), 20, 60); note = "Free kick after the safety."
        case .half, .none: break
        }
        self.off = def; self.yl = next; drive += 1
        if st.result == .half || clock <= 0 {
            if qtr >= 4 { over = true; note += " Final whistle." }
            else if qtr == 2 { qtr = 3; clock = 900; self.off = 1 - firstReceiver; self.yl = 25; note += " Halftime. \(teamAbbrs[self.off]) receive to open the 3rd." }
            else { qtr += 1; clock = 900 }
        }
        return note.trimmingCharacters(in: .whitespaces)
    }
}
