import XCTest
@testable import DebercKit

/// Точный решатель вдвоём сверяется с полным перебором без отсечений,
/// ходы в котором берутся из настоящих правил (`PlayRules.legalCards`).
final class SolverTests: XCTestCase {

    private func legal(_ hand: UInt32, lead: Int?, trump: Int, rules: RuleSet) -> [Int] {
        let cards = ids(in: hand).map { Card(id: $0) }
        let trick = lead.map { [Card(id: $0)] } ?? []
        return PlayRules.legalCards(hand: cards, trick: trick, trump: Suit(rawValue: trump)!, rules: rules).map(\.id)
    }

    /// Ценность оставшихся взяток для заходящего — полный перебор.
    private func brute(_ h: [UInt32], leader: Int, flags: Int, trump: Int, rules: RuleSet, bonus: [Int]) -> Int {
        if h[leader] == 0 { return 0 }
        var best = Int.min
        for c in legal(h[leader], lead: nil, trump: trump, rules: rules) {
            var hh = h
            hh[leader] &= ~bit(c)
            best = max(best, afterLead(hh, leader: leader, lead: c, flags: flags, trump: trump, rules: rules, bonus: bonus))
        }
        return best
    }

    private func afterLead(_ h: [UInt32], leader: Int, lead: Int, flags: Int, trump: Int, rules: RuleSet, bonus: [Int]) -> Int {
        let follower = 1 - leader
        var worst = Int.max
        for r in legal(h[follower], lead: lead, trump: trump, rules: rules) {
            var hh = h
            hh[follower] &= ~bit(r)
            worst = min(worst, trick(hh, leader: leader, lead: lead, response: r, flags: flags, trump: trump,
                                     rules: rules, bonus: bonus))
        }
        return worst
    }

    private func trick(_ h: [UInt32], leader: Int, lead: Int, response: Int, flags: Int, trump: Int,
                       rules: RuleSet, bonus: [Int]) -> Int {
        let t = Suit(rawValue: trump)!
        let a = Card(id: lead), b = Card(id: response)
        let leaderWins = b.suit == a.suit ? a.power(trump: t) > b.power(trump: t) : b.suit != t
        let w = leaderWins ? leader : 1 - leader
        var p = a.points(trump: t) + b.points(trump: t)
        if h[0] | h[1] == 0 { p += 10 }
        var nf = flags
        if nf & (1 << w) == 0 { p += bonus[w]; nf |= 1 << w }
        let rest = brute(h, leader: w, flags: nf, trump: trump, rules: rules, bonus: bonus)
        return leaderWins ? p + rest : -p - rest
    }

    func testMatchesBruteForce() {
        var variants = RuleSet.house
        variants.overtrump = .trumpLeadOnly
        compareWithBruteForce(seed: 2026, iterations: 600) { $0 % 3 == 0 ? variants : RuleSet.house }
    }

    /// Без обязанности козырять «перебивать на ход с козыря» не действует — и в решателе тоже.
    func testMatchesBruteForceWithoutTrumpObligation() {
        var loose = RuleSet.house
        loose.mustTrump = false
        loose.overtrump = .trumpLeadOnly
        compareWithBruteForce(seed: 2027, iterations: 200) { _ in loose }
    }

    private func compareWithBruteForce(seed: UInt64, iterations: Int, rules pick: (Int) -> RuleSet) {
        var rng = SplitMix64(seed: seed)
        let solver = TwoPlayerSolver(tableBits: 12)
        for iteration in 0..<iterations {
            let rules = pick(iteration)
            var deck = Card.deck
            deck.shuffle(using: &rng)
            let k = 1 + Int(rng.next() % 6)
            let hands = [mask(of: Array(deck[0..<k])), mask(of: Array(deck[k..<(2 * k)]))]
            let trump = Int(rng.next() % 4)
            let me = Int(rng.next() % 2)
            let bonus = [Int(rng.next() % 3) == 0 ? 20 : 0, Int(rng.next() % 3) == 0 ? 50 : 0]
            let flags = (bonus[0] == 0 ? 1 : 0) | (bonus[1] == 0 ? 2 : 0)
            solver.configure(trump: trump, rules: rules, bonus: bonus)

            if rng.next() % 2 == 0 {
                // Захожу я.
                let moves = legal(hands[me], lead: nil, trump: trump, rules: rules)
                let got = solver.moveValues(hands: hands, me: me, tableCard: nil, flags: flags, moves: moves)
                for (i, m) in moves.enumerated() {
                    var hh = hands
                    hh[me] &= ~bit(m)
                    let want = afterLead(hh, leader: me, lead: m, flags: flags, trump: trump, rules: rules, bonus: bonus)
                    XCTAssertEqual(got[i], want, "lead \(Card(id: m)) k=\(k) iteration \(iteration)")
                }
            } else {
                // Соперник уже зашёл — отвечаю я.
                let other = 1 - me
                let lead = legal(hands[other], lead: nil, trump: trump, rules: rules)[0]
                var hh = hands
                hh[other] &= ~bit(lead)
                let moves = legal(hh[me], lead: lead, trump: trump, rules: rules)
                let got = solver.moveValues(hands: hh, me: me, tableCard: lead, flags: flags, moves: moves)
                for (i, m) in moves.enumerated() {
                    var h2 = hh
                    h2[me] &= ~bit(m)
                    let want = -trick(h2, leader: other, lead: lead, response: m, flags: flags, trump: trump,
                                      rules: rules, bonus: bonus)
                    XCTAssertEqual(got[i], want, "response \(Card(id: m)) to \(Card(id: lead)) k=\(k) iteration \(iteration)")
                }
            }
        }
    }
}
