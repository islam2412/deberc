import Foundation

// Чистые правила ритма стола — без SwiftUI и таймеров, чтобы их можно было проверить тестами:
// автоход, время раздумья компьютера, когда не гасить экран, очередь всплывающих сообщений.

/// Автоход: когда карта ходит сама, без касания.
public enum AutoPlay: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Всегда ходить самому.
    case off
    /// Последняя карта сдачи ходит сама.
    case lastCard
    /// Сама ходит любая вынужденная карта — когда ходить можно только ею.
    case onlyCard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return "Выключен"
        case .lastCard: return "Последняя карта"
        case .onlyCard: return "Любая вынужденная"
        }
    }

    /// Карта, которой нужно сходить за человека (nil — ждать его хода).
    /// `hand` — карты на руке, `legal` — которыми можно ходить сейчас.
    public func card(hand: [Card], legal: [Card]) -> Card? {
        guard legal.count == 1, let only = legal.first else { return nil }
        switch self {
        case .off: return nil
        case .lastCard: return hand.count == 1 ? only : nil
        case .onlyCard: return only
        }
    }
}

/// Сколько «думает» компьютер: база по скорости × трудность решения × лёгкий разброс.
public enum ThinkingTime {
    /// - Parameters:
    ///   - weight: трудность решения 0…1 (`Bot.decisionWeight`): 0 — единственная карта, 1 — выбор козыря.
    ///   - jitter: случайный множитель около 1 (0,85…1,15), чтобы паузы не были одинаковыми.
    public static func delay(base: Duration, weight: Double, jitter: Double) -> Duration {
        let w = weight.isFinite ? min(1, max(0, weight)) : 0.5
        let j = jitter.isFinite ? min(1.2, max(0.8, jitter)) : 1
        let factor = min(2.0, max(0.5, (0.45 + 1.1 * w) * j))
        return base * factor
    }
}

/// Когда не давать экрану гаснуть: только за столом, пока приложение на экране
/// и человек недавно что-то делал (ходы соперников тоже считаются). Оставленный телефон
/// погаснет как обычно: во время игры — через 5 минут тишины, на итогах — через полторы.
public enum IdlePolicy {
    /// Сколько ждать во время игры (человек может долго думать над ходом).
    public static let playLimit: TimeInterval = 300
    /// Сколько ждать на итогах сдачи и в конце партии.
    public static let summaryLimit: TimeInterval = 90

    public static func keepAwake(inGame: Bool, sceneActive: Bool, matchOver: Bool, showingSummary: Bool,
                          idleFor: TimeInterval, autoplay: Bool) -> Bool {
        guard inGame, sceneActive else { return false }
        if autoplay { return true }
        return idleFor < idleLimit(matchOver: matchOver, showingSummary: showingSummary)
    }

    public static func idleLimit(matchOver: Bool, showingSummary: Bool) -> TimeInterval {
        matchOver || showingSummary ? summaryLimit : playLimit
    }
}

/// Очередь всплывающих сообщений.
///
/// Обычные сообщения (козырь, комбинации, обмен семёрки) идут по очереди и не теряются;
/// повторы не добавляются. Срочные (недопустимый ход, совет, бэла) показываются сразу:
/// если прерванное сообщение успело побыть на экране меньше секунды, оно покажется снова следом.
public struct BannerQueue: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var text: String
        public var urgent: Bool
        /// Главное сообщение сдачи (козырь, обмен семёрки): держится полное время, даже если ждут другие.
        public var important = false
        /// Подсказка длиной в предложение — держится вдвое дольше.
        public var long = false
        /// Подсказка первого хода (как ходить картой): считается показанной, только если провисела полностью.
        public var playTip = false

        public init(text: String, urgent: Bool, important: Bool = false, long: Bool = false, playTip: Bool = false) {
            self.text = text
            self.urgent = urgent
            self.important = important
            self.long = long
            self.playTip = playTip
        }
    }

    public static let capacity = 4

    public private(set) var items: [Item] = []

    public init() {}

    public var isEmpty: Bool { items.isEmpty }

    /// Обычное сообщение. false — это повтор, добавлять не нужно.
    @discardableResult
    public mutating func pushInfo(_ text: String, current: String?, important: Bool = false) -> Bool {
        if items.last?.text == text { return false }
        if items.isEmpty && current == text { return false }
        items.append(Item(text: text, urgent: false, important: important))
        while items.count > BannerQueue.capacity {
            if let index = items.firstIndex(where: { !$0.urgent && !$0.important }) ?? items.firstIndex(where: { !$0.urgent }) {
                items.remove(at: index)
            } else {
                items.removeFirst()
            }
        }
        return true
    }

    /// Срочное сообщение — первым. `current` — что на экране сейчас, `shownFor` — сколько секунд.
    /// Прерванное сообщение возвращается следом, если не успело побыть на экране: обычное — секунду,
    /// важное и длинная подсказка — половину своего времени (флаги при этом сохраняются).
    public mutating func pushUrgent(_ text: String, current: Item?, shownFor: TimeInterval, base: Duration = .seconds(2),
                             long: Bool = false, playTip: Bool = false) {
        items.removeAll { $0.text == text }
        if let current, current.text != text {
            let needed: TimeInterval
            if current.long || current.important {
                needed = hold(for: current, base: base).seconds * 0.5
            } else {
                needed = current.urgent ? 0 : 1.0
            }
            if shownFor < needed {
                items.removeAll { $0 == current }
                items.insert(current, at: 0)
            }
        }
        items.insert(Item(text: text, urgent: true, long: long, playTip: playTip), at: 0)
    }

    /// В очереди ждёт подсказка первого хода.
    public var hasPlayTip: Bool { items.contains { $0.playTip } }

    public mutating func pop() -> Item? {
        items.isEmpty ? nil : items.removeFirst()
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Сколько держать сообщение (вызывать после `pop()`: учитывает, ждут ли следующие).
    public func hold(for item: Item, base: Duration) -> Duration {
        let byKind: Duration
        if item.long {
            byKind = max(.milliseconds(3500), base * 2)
        } else if item.urgent {
            byKind = max(.milliseconds(1600), base * 0.8)
        } else if item.important {
            byKind = base
        } else {
            byKind = items.isEmpty ? base : max(.milliseconds(1100), base * 0.6)
        }
        // Длинное сообщение успевают прочитать: ~60 мс на знак, но не дольше 6 с.
        return min(max(byKind, BannerQueue.readingTime(item.text)), max(byKind, .seconds(6)))
    }

    /// Сколько нужно, чтобы прочитать текст: ~60 мс на знак.
    public static func readingTime(_ text: String) -> Duration {
        .milliseconds(60 * text.count)
    }
}

public extension Duration {
    /// Длительность в секундах.
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

