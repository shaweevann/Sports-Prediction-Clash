import Foundation

// MARK: - Seeded random numbers

/// Seeded generator: every player in the same game window gets the same feeds and drive outcomes.
final class RNG {
    private var a: UInt32

    init(_ key: String) {
        var h: UInt32 = 1_779_033_703 ^ UInt32(truncatingIfNeeded: key.utf8.count)
        for c in key.utf8 {
            h = (h ^ UInt32(c)) &* 3_432_918_353
            h = (h << 13) | (h >> 19)
        }
        a = h
    }

    func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }

    func normal() -> Double {
        var u = 0.0, v = 0.0
        while u == 0 { u = next() }
        while v == 0 { v = next() }
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }

    func int(_ n: Int) -> Int { min(n - 1, Int(next() * Double(n))) }
}

func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, x)) }

func fmtClock(_ s: Int) -> String { "\(max(0, s) / 60):" + String(format: "%02d", max(0, s) % 60) }

// MARK: - Tuning

/// Engine tuning. Targets (NFL averages): ~22 pts/team/game, TD on ~22% of drives,
/// punt ~38%, turnover ~11%, ~5.3 yards per play.
enum Tune {
    static let penalty = 0.07, sack = 0.065, int = 0.019, scramble = 0.05
    static let comp = 0.69, compLong = 0.6, passMu = 2.1, passSig = 0.75
    static let runMean = 4.3, runSd = 3.4, runBreak = 0.09, fumble = 0.016
    static let goShort = 0.65, goMid = 0.4
}

// MARK: - Drive model

enum DriveResult: String, Codable {
    case none, td, fg, miss, punt, int, fum, downs, safety, half

    var label: String {
        switch self {
        case .td: "Touchdown"
        case .fg: "Field goal"
        case .miss: "Missed field goal"
        case .punt: "Punt"
        case .int: "Interception"
        case .fum: "Fumble"
        case .downs: "Turnover on downs"
        case .safety: "Safety"
        case .half: "Clock ran out"
        case .none: "In progress"
        }
    }
}

/// Everything a market can settle on, counted over one drive. yl = yards from the offense's own goal line.
struct DriveStats: Codable {
    var plays = 0, passes = 0, runs = 0, yards = 0, firstDowns = 0
    var sacks = 0, pens = 0, offPens = 0, defPens = 0, tfl = 0
    var maxGain = 0, longPass = 0, longRun = 0
    var thirdConv = 0, thirdLong = 0, fourthGo = 0, redZone = 0, scrambles = 0, b2bInc = 0
    var runStreak = 0, passStreak = 0
    var firstPass: Bool? = nil, firstYards = 0
    var secondPass: Bool? = nil, secondYards = 0
    var thirdPass: Bool? = nil
    var time = 0, maxYl = 0, punt = 0
    var result: DriveResult = .none
}

enum PlayTag: String, Codable { case plain, good, bad, score, pen }

struct PlayEvent: Identifiable, Codable {
    let id: Int
    let text: String
    let tag: PlayTag
    let yl: Int, down: Int, dist: Int, clock: Int, qtr: Int
    let stats: DriveStats
}

struct DriveStart {
    var yl: Int, qtr: Int, clock: Int, trailing: Bool
}

struct DriveOutcome {
    let stats: DriveStats
    let log: [PlayEvent]
    let yl: Int, qtr: Int, clock: Int
}

private enum PlayKind { case sack, int, scramble, complete, incomplete, fumble, run }

enum DriveEngine {
    static func simulate(_ s0: DriveStart, rng: RNG, record: Bool) -> DriveOutcome {
        var yl = s0.yl, down = 1, dist = min(10, 100 - s0.yl), clock = s0.clock, qtr = s0.qtr
        var st = DriveStats()
        st.redZone = yl >= 80 ? 1 : 0
        st.maxYl = yl
        var log: [PlayEvent] = []
        var lastInc = false, runRun = 0, passRun = 0

        func push(_ text: String, _ tag: PlayTag) {
            guard record else { return }
            log.append(PlayEvent(id: log.count, text: text, tag: tag, yl: yl, down: down, dist: dist, clock: clock, qtr: qtr, stats: st))
        }
        func firstDown(_ conv: Bool) {
            st.firstDowns += 1
            if conv { st.thirdConv += 1 }
            down = 1
            dist = min(10, 100 - yl)
        }

        for _ in 0..<80 {
            if clock <= 0 {
                if qtr == 2 || qtr >= 4 {
                    st.result = .half
                    push(qtr >= 4 ? "Clock hits zero. That's the game." : "Clock hits zero. End of the half.", .bad)
                    break
                }
                qtr += 1; clock = 900
                push("End of the \(qtr == 2 ? "1st" : "3rd") quarter.", .plain)
            }
            let late = (qtr == 2 || qtr == 4) && clock <= 120

            // Penalties (pre-snap and holding)
            if rng.next() < Tune.penalty {
                st.pens += 1
                let r = rng.next()
                if r < 0.4 {
                    st.offPens += 1
                    let y = min(5, yl / 2); yl -= y; dist += y
                    push("False start. Back \(y) yards.", .pen)
                    continue
                }
                if r < 0.7 {
                    st.offPens += 1
                    let y = min(10, yl / 2); yl -= y; dist += y; clock -= 6; st.time += 6
                    push("Holding on the offense. \(y) yards, replay the down.", .pen)
                    continue
                }
                st.defPens += 1
                let y = min(5, (100 - yl) / 2), conv = down == 3
                yl += y; st.maxYl = max(st.maxYl, yl)
                if yl >= 80 { st.redZone = 1 }
                clock -= 6; st.time += 6
                firstDown(conv)
                push(y > 0 ? "Defensive holding. \(y) yards and an automatic first down."
                           : "Defensive holding, half the distance to the goal. Automatic first down.", .pen)
                continue
            }

            var pre = ""
            if down == 4 {
                let fgd = 100 - yl + 17
                let go = (dist <= 1 && yl >= 35 && rng.next() < Tune.goShort)
                    || (dist <= 3 && yl >= 55 && yl < 72 && rng.next() < Tune.goMid)
                    || (late && qtr == 4 && s0.trailing)
                if !go {
                    clock -= 6; st.time += 6
                    if fgd <= 57 {
                        let p = clamp(0.99 - Double(max(0, fgd - 28)) * 0.012, 0.4, 0.99)
                        st.result = rng.next() < p ? .fg : .miss
                        push("\(fgd)-yard field goal attempt is \(st.result == .fg ? "GOOD" : "NO GOOD").", st.result == .fg ? .score : .bad)
                    } else {
                        st.punt = Int(clamp(42 + rng.normal() * 7, 25, 65).rounded())
                        st.result = .punt
                        push("Punt, \(st.punt) yards net.", .plain)
                    }
                    break
                }
                st.fourthGo = 1
                pre = "Going for it on 4th & \(dist). "
            }

            let third = down == 3, fourth = down == 4
            if third && dist >= 7 { st.thirdLong = 1 }
            var passP = down == 1 ? 0.5 : down == 2 ? (dist >= 7 ? 0.62 : 0.48) : (dist >= 4 ? 0.85 : 0.55)
            if fourth { passP = dist >= 3 ? 0.8 : 0.4 }
            if late { passP = max(passP, 0.78) }
            if yl >= 97 { passP *= 0.7 }
            let isPass = rng.next() < passP

            var y = 0, t = 0, txt = ""
            var kind = PlayKind.run
            var turnover: DriveResult? = nil
            if isPass {
                let r = rng.next()
                if r < Tune.sack {
                    y = -(5 + Int(rng.next() * 6)); kind = .sack; st.sacks += 1; t = late ? 8 : 35
                } else if r < Tune.sack + Tune.int {
                    kind = .int; turnover = .int; t = 6; txt = "Pass INTERCEPTED."
                } else if r < Tune.sack + Tune.int + Tune.scramble {
                    y = 2 + Int(rng.next() * rng.next() * 25); kind = .scramble; st.scrambles += 1; t = late ? 8 : 32
                } else {
                    let cp = third && dist >= 7 ? Tune.compLong : Tune.comp
                    if rng.next() < cp {
                        y = max(1, Int(exp(Tune.passMu + Tune.passSig * rng.normal()).rounded())); kind = .complete; t = late ? 9 : 34
                    } else {
                        kind = .incomplete; t = 6; txt = "Pass falls incomplete."
                    }
                }
            } else if rng.next() < Tune.fumble {
                kind = .fumble; turnover = .fum; t = 6; txt = "FUMBLE. Defense recovers."
                y = max(0, Int((2 + rng.normal() * 2).rounded()))
            } else {
                y = Int((Tune.runMean + rng.normal() * Tune.runSd).rounded())
                if rng.next() < Tune.runBreak { y = 8 + Int((rng.next() * rng.next() * 55).rounded()) }
                y = max(y, -4); kind = .run; t = late ? 9 : 36
            }
            y = min(y, 100 - yl)
            if yl + y < 0 { y = -yl }
            if kind == .run && y <= 0 { st.tfl += 1 }
            if kind == .incomplete && lastInc { st.b2bInc = 1 }
            lastInc = kind == .incomplete
            switch kind {
            case .sack: txt = "SACKED for a loss of \(-y)."
            case .scramble: txt = "QB scrambles for \(y)."
            case .complete: txt = "Pass complete for \(y)."
            case .run: txt = y > 0 ? "Run for \(y)." : y == 0 ? "Run, no gain." : "Run stuffed for a loss of \(-y)."
            default: break
            }
            txt = pre + txt

            st.plays += 1
            if isPass { st.passes += 1 } else { st.runs += 1 }
            if st.plays == 1 { st.firstPass = isPass; st.firstYards = y }
            if st.plays == 2 { st.secondPass = isPass; st.secondYards = y }
            if st.plays == 3 { st.thirdPass = isPass }
            runRun = isPass ? 0 : runRun + 1
            passRun = isPass ? passRun + 1 : 0
            st.runStreak = max(st.runStreak, runRun)
            st.passStreak = max(st.passStreak, passRun)
            clock -= t; st.time += t
            if clock < 0 { st.time += clock; clock = 0 }

            if let to = turnover { yl += y; st.result = to; push(txt, .bad); break }
            yl += y; st.yards += y
            st.maxGain = max(st.maxGain, y)
            if kind == .complete { st.longPass = max(st.longPass, y) }
            if kind == .run { st.longRun = max(st.longRun, y) }
            st.maxYl = max(st.maxYl, yl)
            if yl >= 80 { st.redZone = 1 }
            if yl >= 100 { st.result = .td; push(String(txt.dropLast()) + ". TOUCHDOWN!", .score); break }
            if yl <= 0 { st.result = .safety; push(txt + " Down in the end zone. SAFETY.", .bad); break }
            if y >= dist {
                firstDown(third)
                push(txt + " First down.", .good)
            } else {
                down += 1; dist -= y
                if down > 4 { st.result = .downs; push(txt + " Turnover on downs.", .bad); break }
                push(txt, kind == .sack ? .bad : .plain)
            }
        }
        return DriveOutcome(stats: st, log: log, yl: yl, qtr: qtr, clock: clock)
    }
}
