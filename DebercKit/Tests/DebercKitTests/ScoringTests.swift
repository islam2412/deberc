import XCTest
@testable import DebercKit

final class ScoringTests: XCTestCase {
    let rules = RuleSet.house

    private func settle(
        points: [Int], tricks: [Int], bidder: Int, priority: [Int],
        declarations: Declarations? = nil, pot: Int = 0,
        baitCounts: [Int]? = nil, nakedCounts: [Int]? = nil, rules customRules: RuleSet? = nil
    ) -> Settlement {
        let n = points.count
        return Scoring.settle(
            cardPoints: points, tricksTaken: tricks, declarations: declarations, bidder: bidder,
            priority: priority, rules: customRules ?? rules, pot: pot,
            baitCounts: baitCounts ?? [Int](repeating: 0, count: n),
            nakedCounts: nakedCounts ?? [Int](repeating: 0, count: n))
    }

    func testMadeEachWritesOwn() {
        let s = settle(points: [100, 62], tricks: [5, 4], bidder: 0, priority: [1, 0])
        XCTAssertEqual(s.outcome, .made)
        XCTAssertEqual(s.written, [100, 62])
        XCTAssertEqual(s.change, [100, 62])
    }

    func testBaitTwoPlayersAllPointsGoToOpponent() {
        let decl = Declarations(melds: [[Meld(suit: .spades, low: .seven, length: 3)], []], meldWinner: 0, bellaSeat: nil)
        let s = settle(points: [60, 102], tricks: [4, 5], bidder: 0, priority: [1, 0], declarations: decl)
        // 60 + 20 (терц) = 80 < 102 — байт, всё уходит сопернику.
        XCTAssertEqual(s.outcome, .bait)
        XCTAssertEqual(s.raw, [80, 102])
        XCTAssertEqual(s.written, [0, 182])
    }

    func testBaitBurnVariant() {
        var burn = rules
        burn.baitTransfer = .burn
        let s = settle(points: [60, 102], tricks: [4, 5], bidder: 0, priority: [1, 0], rules: burn)
        XCTAssertEqual(s.written, [0, 102])
    }

    func testHangingBaitTwoPlayers() {
        let s = settle(points: [81, 81], tricks: [5, 4], bidder: 0, priority: [1, 0])
        XCTAssertEqual(s.outcome, .hanging)
        XCTAssertEqual(s.written, [0, 81])
        XCTAssertEqual(s.potAdded, 81)
        XCTAssertEqual(s.potAfter, 81)
    }

    func testHangingPotGoesToNextDealLeader() {
        let s = settle(points: [50, 112], tricks: [3, 6], bidder: 1, priority: [0, 1], pot: 81)
        XCTAssertEqual(s.outcome, .made)
        XCTAssertEqual(s.potAwarded, [0, 81])
        XCTAssertEqual(s.potAfter, 0)
        XCTAssertEqual(s.change, [50, 193])
    }

    func testHangingPotGoesToBaitRecipient() {
        let s = settle(points: [120, 42], tricks: [7, 2], bidder: 1, priority: [0, 1], pot: 70)
        XCTAssertEqual(s.outcome, .bait)
        XCTAssertEqual(s.written, [162, 0])
        XCTAssertEqual(s.potAwarded, [70, 0])
    }

    func testHangingPotAccumulatesOnAnotherTie() {
        let s = settle(points: [81, 81], tricks: [5, 4], bidder: 1, priority: [0, 1], pot: 70)
        XCTAssertEqual(s.outcome, .hanging)
        XCTAssertEqual(s.potAwarded, [0, 0])
        XCTAssertEqual(s.potAfter, 151)
    }

    func testThreePlayersBaitGoesToLeadingOpponent() {
        let s = settle(points: [40, 60, 50], tricks: [3, 3, 3], bidder: 0, priority: [1, 2, 0])
        XCTAssertEqual(s.outcome, .bait)
        XCTAssertEqual(s.written, [0, 100, 50])
    }

    func testThreePlayersBaitSplitWhenOpponentsEqual() {
        let s = settle(points: [41, 60, 60], tricks: [3, 3, 3], bidder: 0, priority: [1, 2, 0])
        XCTAssertEqual(s.outcome, .bait)
        XCTAssertEqual(s.written, [0, 81, 80])
    }

    func testThreePlayersMustBeatEachOpponent() {
        let made = settle(points: [61, 60, 41], tricks: [3, 3, 3], bidder: 0, priority: [1, 2, 0])
        XCTAssertEqual(made.outcome, .made)
        let bait = settle(points: [59, 60, 43], tricks: [3, 3, 3], bidder: 0, priority: [1, 2, 0])
        XCTAssertEqual(bait.outcome, .bait)
        XCTAssertEqual(bait.written, [0, 119, 43])
    }

    func testThreePlayersHangingWhenTiedWithLeader() {
        let s = settle(points: [60, 60, 42], tricks: [3, 3, 3], bidder: 0, priority: [1, 2, 0])
        XCTAssertEqual(s.outcome, .hanging)
        XCTAssertEqual(s.written, [0, 60, 42])
        XCTAssertEqual(s.potAfter, 60)
    }

    func testOpponentsCombinedVariant() {
        var combined = rules
        combined.bidderMustBeat = .opponentsCombined
        let s = settle(points: [80, 50, 32], tricks: [5, 2, 2], bidder: 0, priority: [1, 2, 0], rules: combined)
        XCTAssertEqual(s.outcome, .bait)
    }

    func testCombosRequireATrick() {
        let decl = Declarations(melds: [[], [Meld(suit: .clubs, low: .seven, length: 4)]], meldWinner: 1, bellaSeat: 1)
        let s = settle(points: [162, 0], tricks: [9, 0], bidder: 0, priority: [1, 0], declarations: decl)
        XCTAssertEqual(s.meldPoints, [0, 0])
        XCTAssertEqual(s.bellaPoints, [0, 0])
        XCTAssertEqual(s.outcome, .made)

        let s2 = settle(points: [140, 22], tricks: [8, 1], bidder: 0, priority: [1, 0], declarations: decl)
        XCTAssertEqual(s2.meldPoints, [0, 50])
        XCTAssertEqual(s2.bellaPoints, [0, 20])
        XCTAssertEqual(s2.raw, [140, 92])
    }

    func testBellaOnlyNeedsTrickVariant() {
        var r = rules
        r.combosNeedTrick = .bellaOnly
        let decl = Declarations(melds: [[], [Meld(suit: .clubs, low: .seven, length: 4)]], meldWinner: 1, bellaSeat: 1)
        let s = settle(points: [162, 0], tricks: [9, 0], bidder: 0, priority: [1, 0], declarations: decl, rules: r)
        XCTAssertEqual(s.meldPoints, [0, 50])
        XCTAssertEqual(s.bellaPoints, [0, 0])
    }

    func testEveryThirdBaitCostsHundred() {
        let second = settle(points: [60, 102], tricks: [4, 5], bidder: 0, priority: [1, 0], baitCounts: [1, 0])
        XCTAssertEqual(second.penalties, [0, 0])
        XCTAssertEqual(second.baitCountsAfter, [2, 0])
        let third = settle(points: [60, 102], tricks: [4, 5], bidder: 0, priority: [1, 0], baitCounts: [2, 0])
        XCTAssertEqual(third.penalties, [-100, 0])
        XCTAssertEqual(third.baitPenalty, [true, false])
        XCTAssertEqual(third.change, [-100, 162])
        let sixth = settle(points: [60, 102], tricks: [4, 5], bidder: 0, priority: [1, 0], baitCounts: [5, 0])
        XCTAssertEqual(sixth.penalties, [-100, 0])
    }

    func testHangingBaitDoesNotCountForPenalty() {
        let s = settle(points: [81, 81], tricks: [5, 4], bidder: 0, priority: [1, 0], baitCounts: [2, 0])
        XCTAssertEqual(s.baitCountsAfter, [2, 0])
        XCTAssertEqual(s.penalties, [0, 0])
    }

    func testEverySecondNakedCostsHundred() {
        let first = settle(points: [162, 0], tricks: [9, 0], bidder: 0, priority: [1, 0])
        XCTAssertEqual(first.naked, [false, true])
        XCTAssertEqual(first.penalties, [0, 0])
        XCTAssertEqual(first.nakedCountsAfter, [0, 1])
        let second = settle(points: [162, 0], tricks: [9, 0], bidder: 0, priority: [1, 0], nakedCounts: [0, 1])
        XCTAssertEqual(second.penalties, [0, -100])
        XCTAssertEqual(second.nakedPenalty, [false, true])
        let third = settle(points: [162, 0], tricks: [9, 0], bidder: 0, priority: [1, 0], nakedCounts: [0, 2])
        XCTAssertEqual(third.penalties, [0, 0])
    }

    func testNakedBidderGetsBothPenalties() {
        let s = settle(points: [0, 162], tricks: [0, 9], bidder: 0, priority: [1, 0],
                       baitCounts: [2, 0], nakedCounts: [1, 0])
        XCTAssertEqual(s.outcome, .bait)
        XCTAssertEqual(s.penalties, [-200, 0])
    }
}
