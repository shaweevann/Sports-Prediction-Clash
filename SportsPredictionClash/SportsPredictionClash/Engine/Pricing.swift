import Foundation

enum Side: String, Codable { case yes, no
    var label: String { rawValue.uppercased() }
}

struct Leg: Identifiable {
    let market: Market
    let side: Side
    /// Price paid, in cents per $1 contract.
    let price: Int
    /// Fair probability of this side from the simulations.
    let fair: Double
    var won: Bool? = nil
    var id: String { market.id }

    init(market: Market, side: Side, price: Int) {
        self.market = market; self.side = side; self.price = price
        fair = side == .yes ? market.p : 1 - market.p
    }
}

enum Blocked: Error {
    case slipFull, conflicts, covered, overCap, tooSafe

    var message: String {
        switch self {
        case .slipFull: "\(Pricing.maxLegs) picks max per drive."
        case .conflicts: "Can't pair this with your other picks. They almost never happen together."
        case .covered: "Your other picks already lock this in."
        case .overCap: "This pick would push your slip past the ×\(Int(Pricing.maxMult)) cap."
        case .tooSafe: "Too safe to add. It barely moves your multiplier."
        }
    }
    var short: String {
        switch self {
        case .slipFull: "slip full"
        case .conflicts: "conflicts"
        case .covered: "already covered"
        case .overCap: "over ×\(Int(Pricing.maxMult)) cap"
        case .tooSafe: "too safe"
        }
    }
}

struct SlipMath {
    let mult: Double, raw: Double, naive: Double, corr: Double
}

enum Pricing {
    static let maxLegs = 8
    static let maxMult = 500.0     // $25 stake tops out at $12,500
    static let minStep = 1.05      // a pick must raise the multiplier at least this much

    /// Joint probability of a set of legs, read straight off the simulated drives.
    static func joint(_ legs: [Leg]) -> (p: Double, hits: Int) {
        guard let n = legs.first?.market.bits.count else { return (1, Int.max) }
        var hits = 0
        outer: for i in 0..<n {
            for l in legs where (l.market.bits[i] == 1) != (l.side == .yes) { continue outer }
            hits += 1
        }
        return ((Double(hits) + 0.5) / Double(n + 1), hits)
    }

    /// Parlay multiplier: product of market payouts, corrected for correlation between legs.
    static func math(_ legs: [Leg]) -> SlipMath {
        guard !legs.isEmpty else { return SlipMath(mult: 0, raw: 0, naive: 0, corr: 1) }
        var naive = 1.0, indep = 1.0
        for l in legs { naive *= 100 / Double(l.price); indep *= l.fair }
        let corr = indep / joint(legs).p
        // Picks that would exceed the cap are refused in tryAdd; the clamp only guards odd cases like removing a leg
        return SlipMath(mult: min(maxMult, naive * corr), raw: naive * corr, naive: naive, corr: corr)
    }

    /// Would this pick fit the slip? Same rules for real and simulated players.
    static func tryAdd(_ leg: Leg, to slip: [Leg]) -> Result<[Leg], Blocked> {
        let others = slip.filter { $0.market !== leg.market }
        let trial = others + [leg]
        if trial.count > maxLegs { return .failure(.slipFull) }
        let j = joint(trial)
        if j.hits < 4 { return .failure(.conflicts) }
        if !others.isEmpty && j.p / joint(others).p > 0.97 { return .failure(.covered) }
        let before = others.isEmpty ? 1 : math(others).mult
        let raw = math(trial).raw
        if raw > maxMult { return .failure(.overCap) }
        if raw / before < minStep { return .failure(.tooSafe) }
        return .success(trial)
    }

    static func fmt(_ x: Double) -> String {
        x >= 100 ? String(format: "%.0f", x) : x >= 10 ? String(format: "%.1f", x) : String(format: "%.2f", x)
    }
}

func money(_ v: Double) -> String { String(format: "$%.2f", v) }
