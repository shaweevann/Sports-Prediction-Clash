import Foundation
import Observation

// MARK: - Market definitions

enum MarketKind { case end, first, second, third, threeAndOut, over }

struct MarketDef {
    let id: String
    let tag: String
    let rule: String
    var kind: MarketKind = .end
    /// Stat markets settle YES once `stat >= line`; `cands` lets the feed pick the line closest to even odds.
    var stat: ((DriveStats) -> Int)? = nil
    var monotonic = true
    var cands: [Int] = []
    var line = 1
    var question: (Int) -> String
    var test: ((DriveStats) -> Bool)? = nil

    static func result(_ id: String, _ tag: String, _ q: String, _ rule: String, kind: MarketKind = .end, _ test: @escaping (DriveStats) -> Bool) -> MarketDef {
        MarketDef(id: id, tag: tag, rule: rule, kind: kind, question: { _ in q }, test: test)
    }

    static func stat(_ id: String, _ tag: String, line: Int = 1, cands: [Int] = [], monotonic: Bool = true, _ rule: String,
                     _ stat: @escaping (DriveStats) -> Int, _ q: @escaping (Int) -> String) -> MarketDef {
        MarketDef(id: id, tag: tag, rule: rule, kind: .over, stat: stat, monotonic: monotonic, cands: cands, line: line, question: q)
    }
}

func marketDefs(offense o: String, defense d: String) -> [MarketDef] {
    let reach: (Int) -> String = { L in L == 51 ? "\(o) cross midfield" : L == 80 ? "\(o) reach the red zone" : "\(o) reach the \(d) \(100 - L)" }
    return [
        .result("td", "Result", "\(o) score a touchdown", "YES if this drive ends in an offensive touchdown.") { $0.result == .td },
        .result("pts", "Result", "\(o) put points on the board", "YES on a touchdown or a made field goal.") { $0.result == .td || $0.result == .fg },
        .result("fg", "Result", "Drive ends in a made field goal", "YES only if the kick is good. A miss settles NO.") { $0.result == .fg },
        .result("punt", "Result", "Drive ends in a punt", "YES if the offense punts it away.") { $0.result == .punt },
        .result("to", "Defense", "Defense forces a turnover", "Interception or lost fumble. Turnover on downs does not count.") { $0.result == .int || $0.result == .fum },
        .result("tao", "Defense", "Three-and-out", "YES if the drive ends in a punt without a single first down.", kind: .threeAndOut) { $0.result == .punt && $0.firstDowns == 0 },
        .result("p1", "First snap", "First snap is a pass", "Dropbacks count, including sacks and scrambles.", kind: .first) { $0.firstPass == true },
        .result("p1y", "First snap", "First snap gains 5+ yards", "Settles the moment the first play is whistled dead.", kind: .first) { $0.plays >= 1 && $0.firstYards >= 5 },
        .stat("yds", "Yardage", cands: [10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70], monotonic: false, "Net yards from scrimmage, sacks included, penalty yards excluded.", { $0.yards }) { "Drive gains \($0)+ yards" },
        .stat("fd", "Chains", cands: [1, 2, 3, 4, 5], "First downs by penalty count.", { $0.firstDowns }) { "\($0)+ first down\($0 > 1 ? "s" : "")" },
        .stat("pl", "Tempo", cands: [3, 4, 5, 6, 7, 8, 9, 10], "Snaps only. Pre-snap penalties and kicks don't count.", { $0.plays }) { "Drive runs \($0)+ plays" },
        .stat("tm", "Tempo", cands: [60, 90, 120, 150, 180, 210, 240, 300], "Game clock elapsed from first snap to the end of the drive.", { $0.time }) { "Drive burns \(fmtClock($0))+ of clock" },
        .stat("big", "Explosive", line: 20, "Any run, catch or scramble.", { $0.maxGain }) { _ in "A single play gains 20+ yards" },
        .stat("lp", "Explosive", cands: [10, 15, 20, 25, 30], "Scrambles don't count. Has to be a caught pass.", { $0.longPass }) { "A completion of \($0)+ yards" },
        .stat("sk", "Defense", "Any sack on the drive.", { $0.sacks }) { _ in "Defense records a sack" },
        .stat("pen", "Flags", "Any accepted penalty on either side.", { $0.pens }) { _ in "A flag gets thrown" },
        .stat("opn", "Flags", "False start or offensive holding.", { $0.offPens }) { _ in "Flag on the offense" },
        .stat("dpn", "Flags", "Any accepted penalty on the defense.", { $0.defPens }) { _ in "Flag on the defense" },
        .stat("tfl", "Defense", "Any designed run for no gain or a loss.", { $0.tfl }) { _ in "A run gets stuffed at the line" },
        .result("p2", "Snap 2", "Second snap is a pass", "Dropbacks count. If the drive ends before a second snap, settles NO.", kind: .second) { $0.secondPass == true },
        .result("p2y", "Snap 2", "Second snap gains 5+ yards", "If the drive ends before a second snap, settles NO.", kind: .second) { $0.plays >= 2 && $0.secondYards >= 5 },
        .result("p3", "Snap 3", "Third snap is a pass", "Dropbacks count. If the drive ends before a third snap, settles NO.", kind: .third) { $0.thirdPass == true },
        .stat("rr3", "Play calling", line: 3, "Three designed runs in a row, penalties aside.", { $0.runStreak }) { _ in "Three straight runs" },
        .stat("pp3", "Play calling", line: 3, "Three pass plays in a row, sacks and scrambles included.", { $0.passStreak }) { _ in "Three straight dropbacks" },
        .result("air", "Explosive", "Biggest gain comes through the air", "Longest completion beats the longest designed run. Ties settle NO.") { $0.longPass > $0.longRun },
        .stat("3l", "Chains", "Any third-down snap needing 7+ yards.", { $0.thirdLong }) { _ in "They face 3rd & 7 or longer" },
        .stat("bbi", "QB", "Two incomplete passes in a row. Penalties in between don't reset it.", { $0.b2bInc }) { _ in "Back-to-back incompletions" },
        .stat("reach", "Field", cands: [51, 60, 70, 80, 90, 95], "YES the moment the ball is spotted at or past that yard line.", { $0.maxYl }, reach),
        .result("rzs", "Field", "Red zone trip, no touchdown", "YES if they get inside the 20 and come away without a TD: a field goal, a stop or a turnover.") { $0.redZone == 1 && $0.result != .td },
        .stat("lr", "Ground game", cands: [6, 8, 10, 12, 15], "Designed runs only. QB scrambles don't count.", { $0.longRun }) { "A run of \($0)+ yards" },
        .result("ph", "Play calling", "More passes than runs", "Counts snaps. Sacks and scrambles are passes. A tie settles NO.") { $0.passes > $0.runs },
        .stat("3c", "Chains", "Moving the chains on 3rd down, by play or by penalty.", { $0.thirdConv }) { _ in "They convert a third down" },
        .stat("4g", "Coaching", "Any 4th-down snap that isn't a punt or field goal try.", { $0.fourthGo }) { _ in "They go for it on fourth down" },
        .stat("scr", "QB", "A called pass where the QB runs it.", { $0.scrambles }) { _ in "QB takes off and scrambles" },
    ]
}

// MARK: - A live market

@Observable
final class Market: Identifiable {
    let id: String
    let tag: String
    let question: String
    let rule: String
    let kind: MarketKind
    let line: Int
    let stat: ((DriveStats) -> Int)?
    let test: (DriveStats) -> Bool
    /// One flag per simulated drive: did this market settle YES there?
    let bits: [UInt8]
    /// Fair probability of YES from the simulations.
    let p: Double
    let open: Double
    var mid: Double
    var hist: [Double]
    var vol: Int
    /// Prices are set when the market opens and hold until the snap. The line still drifts on screen, but every
    /// player pays the price the server accepts, and nobody can wait for a drift below the fair price.
    let yesPrice: Int, noPrice: Int

    init(def: MarketDef, line: Int, test: @escaping (DriveStats) -> Bool, bits: [UInt8], p: Double, mid: Double, vol: Int,
         prices: (yes: Int, no: Int)? = nil) {
        id = def.id; tag = def.tag; rule = def.rule
        question = def.question(line)
        kind = def.stat != nil ? (def.monotonic ? .over : .end) : def.kind
        self.line = line; stat = def.stat; self.test = test
        self.bits = bits; self.p = p
        self.mid = mid; open = mid; hist = [mid]; self.vol = vol
        let ask = prices ?? Market.openPrices(mid: mid, p: p)
        yesPrice = ask.yes; noPrice = ask.no
    }

    /// Asks never dip below the model's fair price plus half a point, so a drifting line never offers free edge.
    static func openPrices(mid: Double, p: Double) -> (yes: Int, no: Int) {
        (min(99, Int(ceil(max(mid + 1, p * 100 + 0.5)))), min(99, Int(ceil(max(100 - mid + 1, (1 - p) * 100 + 0.5)))))
    }
    func ask(_ side: Side) -> Int { side == .yes ? yesPrice : noPrice }

    /// YES outcome as far as the drive has gone: true/false once settled, nil while still open.
    func outcome(_ s: DriveStats, done: Bool) -> Bool? {
        switch kind {
        case .over: return (stat?(s) ?? 0) >= line ? true : done ? false : nil
        case .first: return s.plays >= 1 || done ? test(s) : nil
        case .second: return s.plays >= 2 || done ? test(s) : nil
        case .third: return s.plays >= 3 || done ? test(s) : nil
        case .threeAndOut: return s.firstDowns > 0 ? false : done ? test(s) : nil
        case .end: return done ? test(s) : nil
        }
    }

    func tick() {
        mid = clamp(mid + 0.08 * (p * 100 - mid) + Double.random(in: -1.4...1.4), 2, 98)
        hist.append(mid)
        if hist.count > 60 { hist.removeFirst() }
        if Bool.random() { vol += Int.random(in: 0...400) }
    }
}

// MARK: - Building a drive's feed

enum FeedBuilder {
    static let samples = 5000
    static let feedSize = 20
    static let band = 0.05...0.95       // fair probability a market must sit in to be listed
    static let maxLongshots = 4         // markets under 15% or over 85% allowed in one feed
    static let phiMax = 0.5             // max correlation between two markets in the same feed
    static let minCond = 0.04           // every YES/NO pairing of two feed markets must stay at least this possible

    static func build(start: DriveStart, offense: String, defense: String, seed: String) -> [Market] {
        let rng = RNG(seed)
        let sims = (0..<samples).map { _ in DriveEngine.simulate(start, rng: rng, record: false).stats }
        var all: [Market] = []
        for d in marketDefs(offense: offense, defense: defense) {
            var line = d.line
            if let stat = d.stat, !d.cands.isEmpty {
                line = d.cands.min { a, b in
                    abs(Double(sims.filter { stat($0) >= a }.count) / Double(samples) - 0.5)
                        < abs(Double(sims.filter { stat($0) >= b }.count) / Double(samples) - 0.5)
                } ?? d.cands[0]
            }
            let test = settle(d, line: line)
            var bits = [UInt8](repeating: 0, count: samples), c = 0
            for i in 0..<samples where test(sims[i]) { bits[i] = 1; c += 1 }
            let p = Double(c) / Double(samples)
            guard band.contains(p) else { continue }
            let mid = clamp(p * 100 + rng.normal() * 2.5, 3, 97)
            all.append(Market(def: d, line: line, test: test, bits: bits, p: p, mid: mid, vol: Int(900 + rng.next() * rng.next() * 32000)))
        }
        return order(select(all, rng: rng), rng: rng)
    }

    /// How a market settles at a given line.
    static func settle(_ d: MarketDef, line: Int) -> (DriveStats) -> Bool {
        guard let stat = d.stat else { return d.test ?? { _ in false } }
        return { stat($0) >= line }
    }

    /// Rebuild a market the server listed, so the app can preview prices and settle legs as plays arrive.
    static func restore(id: String, line: Int, offense: String, defense: String, bits: [UInt8], p: Double, mid: Double, vol: Int,
                        prices: (yes: Int, no: Int)) -> Market? {
        guard let d = marketDefs(offense: offense, defense: defense).first(where: { $0.id == id }) else { return nil }
        return Market(def: d, line: line, test: settle(d, line: line), bits: bits, p: p, mid: mid, vol: vol, prices: prices)
    }

    /// Correlation between two markets and how close any YES/NO combo is to impossible.
    private static func relation(_ a: Market, _ b: Market) -> (phi: Double, cond: Double) {
        var n11 = 0, n1 = 0, n2 = 0
        for i in 0..<samples { let x = Int(a.bits[i]), y = Int(b.bits[i]); n1 += x; n2 += y; n11 += x & y }
        let N = Double(samples), p1 = Double(n1) / N, p2 = Double(n2) / N, p11 = Double(n11) / N
        let d = (p1 * (1 - p1) * p2 * (1 - p2)).squareRoot()
        let cells: [(Double, Double, Double)] = [(p11, p1, p2), (p1 - p11, p1, 1 - p2), (p2 - p11, 1 - p1, p2), (1 - p1 - p2 + p11, 1 - p1, 1 - p2)]
        let cond = cells.map { c, ma, mb in min(c / ma, c / mb) }.min() ?? 0
        return (d > 0 ? abs(p11 - p1 * p2) / d : 1, cond)
    }

    /// One "how does the drive end" market, then greedily add the closest-to-even market that
    /// isn't strongly tied to anything already in the feed, so swipes rarely get blocked.
    private static func select(_ all: [Market], rng: RNG) -> [Market] {
        let longshot: (Market) -> Bool = { $0.p < 0.15 || $0.p > 0.85 }
        var rel = [[(phi: Double, cond: Double)]](repeating: [], count: all.count)
        for i in all.indices { rel[i] = all.indices.map { j in i == j ? (phi: 0.0, cond: 1.0) : relation(all[i], all[j]) } }
        let results = all.indices.filter { all[$0].tag == "Result" }
        let td = all.firstIndex { $0.id == "td" }
        let lead = (td != nil && rng.next() < 0.65) ? td! : (results.isEmpty ? 0 : results[rng.int(results.count)])
        var picked = [lead]
        var shots = longshot(all[lead]) ? 1 : 0
        var pool = Set(all.indices).subtracting([lead])
        while picked.count < feedSize, !pool.isEmpty {
            var best: Int?, bestScore = Double.infinity
            for m in pool.sorted() {
                if longshot(all[m]) && shots >= maxLongshots { continue }
                var worst = 0.0, ok = true
                for s in picked {
                    let r = rel[m][s]
                    if r.phi > phiMax || r.cond < minCond { ok = false; break }
                    worst = max(worst, r.phi)
                }
                guard ok else { continue }
                let score = abs(all[m].p - 0.5) + 0.8 * worst
                if score < bestScore { bestScore = score; best = m }
            }
            guard let b = best else { break }
            picked.append(b); pool.remove(b)
            if longshot(all[b]) { shots += 1 }
        }
        return picked.map { all[$0] }
    }

    /// Lead market first, then shuffle so the same category never shows twice in a row.
    private static func order(_ list: [Market], rng: RNG) -> [Market] {
        guard let head = list.first else { return [] }
        var pool = Array(list.dropFirst())
        for i in stride(from: pool.count - 1, to: 0, by: -1) { pool.swapAt(i, rng.int(i + 1)) }
        var out = [head]
        while !pool.isEmpty {
            let prev = out.last!.tag
            let k = pool.firstIndex { $0.tag != prev } ?? 0
            out.append(pool.remove(at: k))
        }
        return out
    }
}
