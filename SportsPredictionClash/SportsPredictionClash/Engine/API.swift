import Foundation

// What the app and the server send each other. Both compile this file, so the two sides can't drift apart.

struct AccountRequest: Codable {
    var name: String?
}

struct AccountReply: Codable {
    let userId: String
    let token: String
    let name: String
    let balance: Int
}

struct MeReply: Codable {
    let userId: String
    let name: String
    let balance: Int
}

/// A listed market. `bits` packs one flag per simulated drive (did it settle YES?), so the app can price
/// combinations locally exactly as the server will.
struct MarketDTO: Codable {
    let id: String
    let line: Int
    let p: Double
    let mid: Double
    let vol: Int
    let yes: Int
    let no: Int
    let bits: String
}

struct FeedReply: Codable {
    let game: GameState
    let balance: Int
    let markets: [MarketDTO]
}

struct LegDTO: Codable, Equatable {
    let market: String
    let side: Side
}

/// Sent at the snap. An empty `legs` means the player is only watching this drive.
struct SnapRequest: Codable {
    let gameId: String
    let drive: Int
    let stake: Int
    let legs: [LegDTO]
}

struct SlipDTO: Codable {
    let id: Int
    let legs: [LegDTO]
    let stake: Int
    let mult: Double
    let won: Bool
    let payout: Int
}

struct SnapReply: Codable {
    let drive: Int
    let log: [PlayEvent]
    let stats: DriveStats
    let yl: Int, qtr: Int, clock: Int
    /// What happened after the whistle: the kick, the change of possession, halftime.
    let after: String
    let game: GameState
    let slip: SlipDTO?
    let balance: Int
    /// The server topped the player back up because they ran out of trophies.
    let reloaded: Bool
}

struct ClaimRequest: Codable {
    let mission: String
    let day: String
}

struct BalanceReply: Codable {
    let balance: Int
}

struct LedgerEntry: Codable {
    let id: Int
    let amount: Int
    let reason: String
    let ref: String?
    let at: Int
}

struct ErrorReply: Codable {
    let error: String
}

/// Trophy rules both sides agree on.
enum Economy {
    static let stakes = [10, 50, 100, 250]
    static let startingBalance = 1000
    /// Below this, the next settled drive tops the player back up to the starting balance.
    static let reloadBelow = 10
    /// Daily mission rewards by mission id. The server pays at most these, once per mission per day.
    static let missionRewards = ["play5": 100, "hit2": 200, "big": 100, "tail": 100, "share": 50, "follow": 50, "tenx": 300]
}

extension Market {
    var dto: MarketDTO {
        MarketDTO(id: id, line: line, p: p, mid: open, vol: vol, yes: yesPrice, no: noPrice, bits: Market.pack(bits))
    }

    static func from(_ d: MarketDTO, offense: String, defense: String) -> Market? {
        guard let bits = unpack(d.bits, count: FeedBuilder.samples) else { return nil }
        return FeedBuilder.restore(id: d.id, line: d.line, offense: offense, defense: defense, bits: bits, p: d.p, mid: d.mid, vol: d.vol,
                       prices: (d.yes, d.no))
    }

    static func pack(_ bits: [UInt8]) -> String {
        var bytes = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for (i, b) in bits.enumerated() where b == 1 { bytes[i / 8] |= 1 << UInt8(i % 8) }
        return Data(bytes).base64EncodedString()
    }

    static func unpack(_ s: String, count: Int) -> [UInt8]? {
        guard let data = Data(base64Encoded: s), data.count == (count + 7) / 8 else { return nil }
        let bytes = [UInt8](data)
        return (0..<count).map { (bytes[$0 / 8] >> UInt8($0 % 8)) & 1 }
    }
}
