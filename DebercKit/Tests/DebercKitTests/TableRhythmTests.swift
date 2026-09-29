import XCTest
@testable import DebercKit

/// Ритм стола: автоход, раздумья компьютера, очередь сообщений.
final class TableRhythmTests: XCTestCase {

    // MARK: - Автоход

    func testAutoPlayOffNeverMoves() {
        XCTAssertNil(AutoPlay.off.card(hand: [c("Тп")], legal: [c("Тп")]))
    }

    func testLastCardMovesOnlyWhenItIsTheLastOne() {
        XCTAssertEqual(AutoPlay.lastCard.card(hand: [c("Тп")], legal: [c("Тп")]), c("Тп"))
        // Вынужденная, но не последняя — ходит человек.
        XCTAssertNil(AutoPlay.lastCard.card(hand: [c("Тп"), c("7ч")], legal: [c("Тп")]))
    }

    func testOnlyCardMovesAnyForcedCard() {
        XCTAssertEqual(AutoPlay.onlyCard.card(hand: [c("Тп"), c("7ч")], legal: [c("Тп")]), c("Тп"))
        XCTAssertNil(AutoPlay.onlyCard.card(hand: [c("Тп"), c("7ч")], legal: [c("Тп"), c("7ч")]))
        XCTAssertNil(AutoPlay.onlyCard.card(hand: [], legal: []))
    }

    // MARK: - Раздумья

    func testThinkingTimeGrowsWithDifficultyAndStaysBounded() {
        let base = Duration.milliseconds(1000)
        let easy = ThinkingTime.delay(base: base, weight: 0, jitter: 1)
        let hard = ThinkingTime.delay(base: base, weight: 1, jitter: 1)
        XCTAssertLessThan(easy, hard)
        // Даже единственная карта — не мгновенно: не меньше половины обычного.
        XCTAssertGreaterThanOrEqual(easy, base * 0.5)
        XCTAssertLessThanOrEqual(ThinkingTime.delay(base: base, weight: 5, jitter: 9), base * 2)
        XCTAssertGreaterThanOrEqual(ThinkingTime.delay(base: base, weight: .nan, jitter: .infinity), base * 0.5)
    }

    // MARK: - Экран не гаснет

    func testIdlePolicy() {
        XCTAssertTrue(IdlePolicy.keepAwake(inGame: true, sceneActive: true, matchOver: false, showingSummary: false,
                                           idleFor: 10, autoplay: false))
        XCTAssertFalse(IdlePolicy.keepAwake(inGame: true, sceneActive: true, matchOver: false, showingSummary: false,
                                            idleFor: IdlePolicy.playLimit + 1, autoplay: false))
        XCTAssertFalse(IdlePolicy.keepAwake(inGame: false, sceneActive: true, matchOver: false, showingSummary: false,
                                            idleFor: 0, autoplay: false))
        XCTAssertEqual(IdlePolicy.idleLimit(matchOver: false, showingSummary: true), IdlePolicy.summaryLimit)
    }

    // MARK: - Очередь сообщений

    func testInfoMessagesQueueWithoutDuplicates() {
        var queue = BannerQueue()
        XCTAssertTrue(queue.pushInfo("Козырь — бубны", current: nil))
        XCTAssertFalse(queue.pushInfo("Козырь — бубны", current: nil))
        XCTAssertTrue(queue.pushInfo("Бэла", current: nil))
        XCTAssertEqual(queue.pop()?.text, "Козырь — бубны")
        XCTAssertEqual(queue.pop()?.text, "Бэла")
        XCTAssertNil(queue.pop())
        // То же, что уже на экране, второй раз не ставится.
        XCTAssertFalse(queue.pushInfo("Бэла", current: "Бэла"))
    }

    func testOverflowDropsOrdinaryBeforeImportant() {
        var queue = BannerQueue()
        queue.pushInfo("Козырь", current: nil, important: true)
        for i in 0..<BannerQueue.capacity + 2 { queue.pushInfo("Сообщение \(i)", current: nil) }
        XCTAssertEqual(queue.items.count, BannerQueue.capacity)
        XCTAssertEqual(queue.items.first?.text, "Козырь")
    }

    func testUrgentGoesFirstAndInterruptedMessageComesBack() {
        var queue = BannerQueue()
        let shown = BannerQueue.Item(text: "Саша забирает туз за семёрку", urgent: false, important: true)
        queue.pushUrgent("Так сейчас нельзя", current: shown, shownFor: 0.3)
        XCTAssertEqual(queue.pop()?.text, "Так сейчас нельзя")
        // Прерванное важное вернулось — и осталось важным.
        let back = queue.pop()
        XCTAssertEqual(back?.text, shown.text)
        XCTAssertEqual(back?.important, true)
    }

    func testMessageShownLongEnoughIsNotRepeated() {
        var queue = BannerQueue()
        let shown = BannerQueue.Item(text: "Бэла", urgent: false)
        queue.pushUrgent("Ход отменён", current: shown, shownFor: 5)
        XCTAssertEqual(queue.items.map(\.text), ["Ход отменён"])
    }

    func testPlayTipIsKeptWhenInterruptedEarly() {
        var queue = BannerQueue()
        let tip = BannerQueue.Item(text: "Чтобы сходить, коснитесь карты дважды или бросьте её вверх",
                                   urgent: true, long: true, playTip: true)
        queue.pushUrgent("Нужно ходить в масть", current: tip, shownFor: 0.5, base: .seconds(2))
        XCTAssertTrue(queue.hasPlayTip)
        _ = queue.pop()
        XCTAssertEqual(queue.pop()?.playTip, true)
    }

    func testHoldDependsOnKindAndLength() {
        let base = Duration.milliseconds(2000)
        var queue = BannerQueue()
        let short = BannerQueue.Item(text: "Бэла", urgent: false)
        XCTAssertEqual(queue.hold(for: short, base: base), base)
        let long = BannerQueue.Item(text: String(repeating: "а", count: 70), urgent: false)
        XCTAssertEqual(queue.hold(for: long, base: base), .milliseconds(4200))
        // Очень длинное — не дольше 6 с.
        let huge = BannerQueue.Item(text: String(repeating: "а", count: 400), urgent: false)
        XCTAssertEqual(queue.hold(for: huge, base: base), .seconds(6))
        // Ждут другие — обычное сообщение короче.
        queue.pushInfo("ещё", current: nil)
        XCTAssertLessThan(queue.hold(for: short, base: base), base)
        let tip = BannerQueue.Item(text: "Подсказка", urgent: true, long: true)
        XCTAssertGreaterThanOrEqual(queue.hold(for: tip, base: base), .milliseconds(3500))
    }

    func testDurationSeconds() {
        XCTAssertEqual(Duration.milliseconds(1500).seconds, 1.5, accuracy: 1e-9)
    }
}
