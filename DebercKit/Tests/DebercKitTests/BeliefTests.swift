import XCTest
@testable import DebercKit

/// «Чутьё»: признаки позиции и сеть, которая по ним оценивает, у кого какая карта.
final class BeliefTests: XCTestCase {

    private func midDeal(players: Int, seed: UInt64, actions: Int) throws -> Match {
        var match = Match(playerCount: players, names: Array(["A", "B", "C"].prefix(players)), rules: .house, seed: seed)
        match.startNextDeal()
        var rng = SplitMix64(seed: seed)
        let bot = Bot(level: .amateur)
        for _ in 0..<actions {
            guard let actor = match.actor, !match.needsNewDeal else { break }
            try match.apply(bot.chooseAction(match: match, seat: actor, rng: &rng))
        }
        return match
    }

    func testFeaturesAreBoundedAndSeeOnlyTheTable() throws {
        for players in [2, 3] {
            let match = try midDeal(players: players, seed: 5, actions: 14)
            for seat in 0..<players {
                let v = SeatView(match: match, seat: seat)
                let x = BeliefFeatures.encode(v)
                XCTAssertEqual(x.count, BeliefFeatures.count)
                XCTAssertTrue(x.allSatisfy { $0 >= 0 && $0 <= 1 })
                // Невидимые карты — ровно те, что у соперников и в колоде/прикупе.
                let unknown = BeliefFeatures.unknownMask(v)
                XCTAssertEqual(unknown & mask(of: v.myHand), 0)
                XCTAssertEqual(unknown & mask(of: v.playedCards), 0)
                for s in 0..<players where s != seat {
                    XCTAssertEqual(mask(of: match.deal!.hands[s]) & ~unknown & ~mask(of: v.knownCardsOfOthers[s]), 0)
                }
            }
        }
    }

    func testNetworkGivesProbabilitiesForHiddenCards() throws {
        let net = try XCTUnwrap(BeliefNet.shared, "веса сети не нашлись в ресурсах пакета")
        for players in [2, 3] {
            let match = try midDeal(players: players, seed: 9, actions: 12)
            let v = SeatView(match: match, seat: match.actor ?? 0)
            let logP = net.logProbabilities(v)
            XCTAssertEqual(logP.count, 32 * 3)
            for c in 0..<32 {
                let p = (0..<3).map { exp(Double(logP[c * 3 + $0])) }
                XCTAssertEqual(p.reduce(0, +), 1, accuracy: 1e-4)
                if players == 2 { XCTAssertEqual(p[1], 0, accuracy: 1e-6) }   // вдвоём «следующего за ним» нет
            }
            XCTAssertEqual(logP, net.logProbabilities(v))
        }
    }

    func testHalfFloatConversion() {
        XCTAssertEqual(DenseNet.float(half: 0x3C00), 1)
        XCTAssertEqual(DenseNet.float(half: 0xC000), -2)
        XCTAssertEqual(DenseNet.float(half: 0x3555), 0.333251953125)
        XCTAssertEqual(DenseNet.float(half: 0x0001), 5.9604645e-8)          // наименьшее ненормализованное
        XCTAssertEqual(DenseNet.float(half: 0x7BFF), 65504)
        XCTAssertEqual(DenseNet.float(half: 0x7C00), .infinity)
    }

    /// Мастер с «чутьём» тоже решает только по тому, что видно со своего места.
    func testBeliefPlayDecidesOnlyFromSeatView() throws {
        let mine = cards("Вч 9ч Тп 10т 8б Дп"), myPrikup = cards("7б Вп 7п")
        let deckA = arrangedDeck(dealer: 0, hands: [cards("8п 9п Кт Дт 9б 10б"), mine], open: c("Кч"),
                                 prikup: [cards("8ч 10ч Тб"), myPrikup])
        let deckB = arrangedDeck(dealer: 0, hands: [cards("Кп 10п Вт 9т Кб Дб"), mine], open: c("Кч"),
                                 prikup: [cards("10ч 9б 8т"), myPrikup])
        var a = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        var b = Match(playerCount: 2, names: ["A", "B"], rules: .house, seed: 1)
        a.startDeal(deck: deckA, dealer: 0)
        b.startDeal(deck: deckB, dealer: 0)
        for action in [Action.take, .play(c("9ч")), .play(c("10ч"))] {
            try a.apply(action)
            try b.apply(action)
        }
        XCTAssertEqual(SeatView(match: a, seat: 1), SeatView(match: b, seat: 1))
        var config = Bot.Config.preset(.master)
        config.timeBudget = nil
        config.playSamples = 40
        config.belief = 1
        let bot = Bot(config: config, level: .master)
        var r1 = SplitMix64(seed: 3), r2 = SplitMix64(seed: 3)
        XCTAssertEqual(bot.chooseAction(match: a, seat: 1, rng: &r1), bot.chooseAction(match: b, seat: 1, rng: &r2))
    }
}
