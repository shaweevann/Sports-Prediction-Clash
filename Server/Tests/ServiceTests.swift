import XCTest
@testable import ClashServer

final class ServiceTests: XCTestCase {
    private var service: Service!
    // A fixed moment, so every test sits in the same game window and day
    private let moment = Date(timeIntervalSince1970: 1_793_000_000)

    override func setUpWithError() throws {
        service = Service(store: try Store(path: ":memory:"), secret: "test-secret", now: { [moment] in moment })
    }

    private func signUp(_ name: String? = nil) throws -> User {
        let a = try service.createAccount(name: name)
        return try XCTUnwrap(service.user(token: a.token))
    }

    /// A slip the server accepts: legs added the way the app adds them.
    private func slip(_ feed: FeedReply, count: Int) -> [LegDTO] {
        let g = feed.game
        let markets = feed.markets.compactMap { Market.from($0, offense: teamAbbrs[g.off], defense: teamAbbrs[1 - g.off]) }
        var legs: [Leg] = []
        for m in markets where legs.count < count {
            for side in [Side.yes, .no] {
                if case .success(let t) = Pricing.tryAdd(Leg(market: m, side: side, price: m.ask(side)), to: legs) { legs = t; break }
            }
        }
        return legs.map { LegDTO(market: $0.market.id, side: $0.side) }
    }

    func testNewAccountStartsWithTrophiesAndTokenWorks() throws {
        let a = try service.createAccount(name: "  Evan ")
        XCTAssertEqual(a.name, "Evan")
        XCTAssertEqual(a.balance, 1000)
        XCTAssertNotNil(try service.user(token: a.token))
        XCTAssertNil(try service.user(token: "not-a-token"))
    }

    func testEveryPlayerGetsTheSameFeed() throws {
        let a = try service.feed(signUp()), b = try service.feed(signUp())
        XCTAssertGreaterThanOrEqual(a.markets.count, 15)
        XCTAssertEqual(a.markets.map(\.id), b.markets.map(\.id))
        XCTAssertEqual(a.markets.map(\.yes), b.markets.map(\.yes))
    }

    func testTheSecretChangesTheDrive() throws {
        let other = Service(store: try Store(path: ":memory:"), secret: "another-secret", now: { [moment] in moment })
        let a = try service.feed(signUp())
        let u = try other.createAccount(name: nil)
        let b = try other.feed(XCTUnwrap(other.user(token: u.token)))
        XCTAssertNotEqual(a.markets.map(\.bits), b.markets.map(\.bits))
    }

    func testAppPreviewMatchesServerMultiplier() throws {
        let u = try signUp()
        let feed = try service.feed(u)
        let legs = slip(feed, count: 4)
        XCTAssertEqual(legs.count, 4)
        let g = feed.game
        let markets = feed.markets.compactMap { Market.from($0, offense: teamAbbrs[g.off], defense: teamAbbrs[1 - g.off]) }
        let preview = Pricing.math(legs.map { l in
            let m = markets.first { $0.id == l.market }!
            return Leg(market: m, side: l.side, price: m.ask(l.side))
        }).mult
        let reply = try service.snap(u, SnapRequest(gameId: g.gameId, drive: g.drive, stake: 50, legs: legs))
        XCTAssertEqual(try XCTUnwrap(reply.slip).mult, preview, accuracy: 1e-9)
    }

    func testSnapMovesTrophiesThroughTheLedgerAndAdvancesTheGame() throws {
        let u = try signUp()
        let feed = try service.feed(u)
        let reply = try service.snap(u, SnapRequest(gameId: feed.game.gameId, drive: feed.game.drive, stake: 100, legs: slip(feed, count: 2)))
        let s = try XCTUnwrap(reply.slip)
        XCTAssertEqual(reply.balance, 1000 - 100 + s.payout)
        XCTAssertEqual(try service.balance(u.id), reply.balance)
        XCTAssertEqual(s.payout, s.won ? Int((100 * s.mult).rounded(.down)) : 0)
        XCTAssertEqual(reply.game.drive, feed.game.drive + 1)
        XCTAssertEqual(try service.game(u), reply.game)
        XCTAssertFalse(reply.log.isEmpty)
        let reasons = try service.ledger(u).map(\.reason)
        XCTAssertTrue(reasons.contains("stake"))
        XCTAssertEqual(reasons.last, "signup")
    }

    func testADriveCanOnlyBeSnappedOnce() throws {
        let u = try signUp()
        let feed = try service.feed(u)
        let req = SnapRequest(gameId: feed.game.gameId, drive: feed.game.drive, stake: 10, legs: slip(feed, count: 1))
        _ = try service.snap(u, req)
        XCTAssertThrowsError(try service.snap(u, req)) { XCTAssertEqual(($0 as? ServiceError)?.status, 409) }
    }

    func testWatchingADriveCostsNothing() throws {
        let u = try signUp()
        let feed = try service.feed(u)
        let reply = try service.snap(u, SnapRequest(gameId: feed.game.gameId, drive: feed.game.drive, stake: 50, legs: []))
        XCTAssertNil(reply.slip)
        XCTAssertEqual(reply.balance, 1000)
    }

    func testBadSlipsAreRefusedAndChargeNothing() throws {
        let u = try signUp()
        let feed = try service.feed(u)
        let g = feed.game
        let legs = slip(feed, count: 2)
        let bad: [SnapRequest] = [
            SnapRequest(gameId: g.gameId, drive: g.drive, stake: 77, legs: legs),                                        // odd stake
            SnapRequest(gameId: g.gameId, drive: g.drive, stake: 10, legs: [LegDTO(market: "nope", side: .yes)]),        // not listed
            SnapRequest(gameId: g.gameId, drive: g.drive, stake: 10, legs: [legs[0], legs[0]]),                          // twice
            SnapRequest(gameId: g.gameId, drive: g.drive + 1, stake: 10, legs: legs),                                    // future drive
        ]
        for r in bad { XCTAssertThrowsError(try service.snap(u, r)) }
        XCTAssertEqual(try service.balance(u.id), 1000)
        XCTAssertEqual(try service.game(u).drive, g.drive)
    }

    func testCannotStakeMoreThanTheBalance() throws {
        let u = try signUp()
        var feed = try service.feed(u)
        // Lose trophies until fewer than 250 are left, then try a 250 stake
        while try service.balance(u.id) >= 250 {
            let r = try service.snap(u, SnapRequest(gameId: feed.game.gameId, drive: feed.game.drive, stake: 250, legs: slip(feed, count: 6)))
            feed = try service.feed(u)
            if r.game.over { return }
        }
        XCTAssertThrowsError(try service.snap(u, SnapRequest(gameId: feed.game.gameId, drive: feed.game.drive, stake: 250, legs: slip(feed, count: 1)))) {
            XCTAssertEqual(($0 as? ServiceError)?.status, 402)
        }
    }

    func testMissionPaysOncePerDay() throws {
        let u = try signUp()
        let today = DayStamp.of(moment)
        XCTAssertEqual(try service.claim(u, ClaimRequest(mission: "hit2", day: today)).balance, 1200)
        XCTAssertThrowsError(try service.claim(u, ClaimRequest(mission: "hit2", day: today)))
        XCTAssertThrowsError(try service.claim(u, ClaimRequest(mission: "made-up", day: today)))
        XCTAssertThrowsError(try service.claim(u, ClaimRequest(mission: "tail", day: "2001-01-01")))
        XCTAssertEqual(try service.balance(u.id), 1200)
    }
}
