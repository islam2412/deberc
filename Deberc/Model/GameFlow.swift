import Foundation
import DebercKit

// Чистые решения «дирижёра» партии — без SwiftUI, таймеров и анимаций, чтобы их можно было
// проверить отдельно. GameStore только исполняет: ждёт, анимирует, сохраняет.

/// Что делать дальше.
enum FlowStep: Equatable {
    /// Ничего: партии нет или ждать нечего.
    case idle
    /// Раздать первую сдачу (или сдачу, которую не удалось прочитать из сохранения).
    case startDeal
    /// На столе собранная взятка: подержать и убрать.
    case collectTrick
    /// Все спасовали — пересдать без окна итогов.
    case redeal
    /// Сдача (или партия) окончена — показать итоги.
    case showSummary
    /// Итоги уже на экране — ждём игрока.
    case waitSummary
    /// Ход компьютера.
    case botMove(seat: Int)
    /// Ход человека.
    case waitHuman
}

enum GameFlow {

    static func nextStep(match: Match?, displayedTrick: Trick?, showingSummary: Bool,
                         humanSeat: Int, autoplay: Bool) -> FlowStep {
        guard let match else { return .idle }
        if displayedTrick != nil { return .collectTrick }
        if match.isOver { return showingSummary ? .waitSummary : .showSummary }
        if match.needsNewDeal {
            guard match.deal != nil, let last = match.history.last else { return .startDeal }
            if last.outcome == .allPassed { return .redeal }
            return showingSummary ? .waitSummary : .showSummary
        }
        guard let actor = match.actor else { return .idle }
        if actor == humanSeat && !autoplay { return .waitHuman }
        return .botMove(seat: actor)
    }

    /// Сколько подождать со следующим ходом компьютера после событий хода: назначенный козырь,
    /// обмен семёрки, бэла, пас соперника в торговле, прикуп — чтобы их успели увидеть. nil — не ждать.
    static func pause(after events: [DealEvent], speed: GameSpeed, humanSeat: Int) -> Duration? {
        var result: Duration?
        func atLeast(_ pause: Duration) {
            result = max(result ?? .zero, pause)
        }
        for event in events {
            switch event {
            case .trumpChosen:
                atLeast(speed.announcePause)
            case .sevenExchanged:
                atLeast(speed.announcePause * 0.8)
            case .bella:
                atLeast(speed.announcePause * 0.5)
            case .bid(let bid) where bid.kind == .pass && bid.seat != humanSeat:
                // Реплику соперника «Пас» успевают прочитать до реплики следующего.
                atLeast(speed.botDelay * 0.6)
            case .prikupDealt:
                // Прикуп летит в руки.
                atLeast(.milliseconds(Int(speed.cardFlight * 1000) + 450))
            default:
                break
            }
        }
        return result
    }

    /// Фаза для файла прогресса автоигры: menu, bidding-1, exchange, playing, summary, gameover…
    static func phaseName(match: Match?, showingSummary: Bool, inGame: Bool) -> String {
        guard inGame, let match else { return "menu" }
        if showingSummary { return match.isOver ? "gameover" : "summary" }
        guard let deal = match.deal else { return "dealing" }
        switch deal.phase {
        case .bidding(let round): return "bidding-\(round)"
        case .exchange: return "exchange"
        case .playing: return "playing"
        case .finished: return "finished"
        }
    }

    /// Реплики торговли по местам — как они выглядели бы в живой игре: последняя заявка
    /// каждого, пока идёт торговля, обмен семёрки и до первой карты розыгрыша
    /// (нужно после «Продолжить» и отмены хода).
    static func bubbles(for deal: Deal?, phrase: (Bid) -> String) -> [Int: String] {
        guard let deal else { return [:] }
        switch deal.phase {
        case .bidding, .exchange:
            break
        case .playing:
            guard deal.tricks.isEmpty && deal.currentTrick.plays.isEmpty else { return [:] }
        case .finished:
            return [:]
        }
        var result: [Int: String] = [:]
        for bid in deal.bids { result[bid.seat] = phrase(bid) }
        return result
    }

    /// Текст совета.
    static func hintText(_ action: Action, deal: Deal?) -> String {
        switch action {
        case .play(let card):
            return "Совет: \(card)"
        case .take:
            if let suit = deal?.openCard.suit { return "Совет: брать \(suit.symbol)" }
            return "Совет: брать"
        case .name(let suit):
            return "Совет: назначить \(suit.symbol)"
        case .pass:
            return "Совет: пас"
        case .exchangeSeven(let accept):
            return accept ? "Совет: поменять семёрку" : "Совет: оставить семёрку"
        }
    }

    /// Соперники по id: сначала выбранные, затем — подходящие по уровню; всегда `count` разных.
    static func opponents(ids: [String], count: Int, fallback level: BotLevel) -> [Persona] {
        guard count > 0 else { return [] }
        var result: [Persona] = []
        for id in ids where result.count < count {
            if let persona = Persona.byID(id), !result.contains(persona) { result.append(persona) }
        }
        for persona in Persona.defaults(level: level, count: count) + Persona.all
        where result.count < count && !result.contains(persona) {
            result.append(persona)
        }
        return result
    }

    /// Имена ботов в партии — как у персонажей (место i + 1 — `opponents[i]`).
    static func syncNames(_ match: inout Match, opponents: [Persona]) {
        for (index, persona) in opponents.enumerated() {
            let seat = index + 1
            if match.names.indices.contains(seat) && match.names[seat] != persona.name {
                match.names[seat] = persona.name
            }
        }
    }

    /// Уровень партии для статистики: общий уровень соперников (разные уровни — не записывать).
    static func levelKey(for opponents: [Persona]) -> String? {
        let levels = Set(opponents.map(\.level))
        guard levels.count == 1, let level = levels.first else { return nil }
        return level.rawValue
    }

    /// Имя человека для записи партии.
    static func humanName(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Вы" : name
    }
}

/// Сколько «думает» компьютер: база по скорости × трудность решения × лёгкий разброс.
enum ThinkingTime {
    /// - Parameters:
    ///   - weight: трудность решения 0…1 (`Bot.decisionWeight`): 0 — единственная карта, 1 — выбор козыря.
    ///   - jitter: случайный множитель около 1 (0,85…1,15), чтобы паузы не были одинаковыми.
    static func delay(base: Duration, weight: Double, jitter: Double) -> Duration {
        let w = weight.isFinite ? min(1, max(0, weight)) : 0.5
        let j = jitter.isFinite ? min(1.2, max(0.8, jitter)) : 1
        let factor = min(2.0, max(0.5, (0.45 + 1.1 * w) * j))
        return base * factor
    }
}

/// Когда не давать экрану гаснуть: только за столом, пока приложение на экране
/// и человек недавно что-то делал (ходы соперников тоже считаются). Оставленный телефон
/// погаснет как обычно: во время игры — через 5 минут тишины, на итогах — через полторы.
enum IdlePolicy {
    /// Сколько ждать во время игры (человек может долго думать над ходом).
    static let playLimit: TimeInterval = 300
    /// Сколько ждать на итогах сдачи и в конце партии.
    static let summaryLimit: TimeInterval = 90

    static func keepAwake(inGame: Bool, sceneActive: Bool, matchOver: Bool, showingSummary: Bool,
                          idleFor: TimeInterval, autoplay: Bool) -> Bool {
        guard inGame, sceneActive else { return false }
        if autoplay { return true }
        return idleFor < idleLimit(matchOver: matchOver, showingSummary: showingSummary)
    }

    static func idleLimit(matchOver: Bool, showingSummary: Bool) -> TimeInterval {
        matchOver || showingSummary ? summaryLimit : playLimit
    }
}

/// Очередь всплывающих сообщений.
///
/// Обычные сообщения (козырь, комбинации, обмен семёрки) идут по очереди и не теряются;
/// повторы не добавляются. Срочные (недопустимый ход, совет, бэла) показываются сразу:
/// если прерванное сообщение успело побыть на экране меньше секунды, оно покажется снова следом.
struct BannerQueue: Equatable {
    struct Item: Equatable {
        var text: String
        var urgent: Bool
        /// Главное сообщение сдачи (козырь, обмен семёрки): держится полное время, даже если ждут другие.
        var important = false
        /// Подсказка длиной в предложение — держится вдвое дольше.
        var long = false
    }

    static let capacity = 4

    private(set) var items: [Item] = []

    var isEmpty: Bool { items.isEmpty }

    /// Обычное сообщение. false — это повтор, добавлять не нужно.
    @discardableResult
    mutating func pushInfo(_ text: String, current: String?, important: Bool = false) -> Bool {
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
    mutating func pushUrgent(_ text: String, current: Item?, shownFor: TimeInterval, long: Bool = false) {
        items.removeAll { $0.text == text }
        if let current, !current.urgent, current.text != text, shownFor < 1.0 {
            items.removeAll { $0 == current }
            items.insert(current, at: 0)
        }
        items.insert(Item(text: text, urgent: true, long: long), at: 0)
    }

    mutating func pop() -> Item? {
        items.isEmpty ? nil : items.removeFirst()
    }

    mutating func removeAll() {
        items.removeAll()
    }

    /// Сколько держать сообщение (вызывать после `pop()`: учитывает, ждут ли следующие).
    func hold(for item: Item, base: Duration) -> Duration {
        if item.long { return max(.milliseconds(3500), base * 2) }
        if item.urgent { return max(.milliseconds(1600), base * 0.8) }
        if item.important { return base }
        return items.isEmpty ? base : max(.milliseconds(1100), base * 0.6)
    }
}

/// Крупное объявление в центре стола: назначен козырь, записаны комбинации.
struct TableAnnouncement: Equatable, Identifiable {
    enum Kind: Equatable {
        case trump(seat: Int, suit: Suit, forced: Bool)
        /// Комбинации, которые записывает `seat`; `senior` — у других тоже были, но младше.
        case melds(seat: Int, melds: [Meld], points: Int, senior: Bool)
    }

    let id: Int
    let kind: Kind
}

/// Подначка соперника в облачке у его места.
struct TableTaunt: Equatable, Identifiable {
    let id: Int
    let seat: Int
    let text: String
}

/// Мгновенная игра компьютеров за всех — для демо-экранов (итог сдачи, конец партии, запись).
enum DemoSimulator {
    /// Играет, пока `stop` не скажет «хватит» или партия не кончится. Раздаёт сдачи сам.
    static func play(_ start: Match, level: BotLevel, seed: UInt64, maxActions: Int = 20_000,
                     stop: (Match) -> Bool) -> Match {
        var match = start
        var rng = SplitMix64(seed: seed)
        let bot = Bot(level: level)
        var actions = 0
        while !match.isOver && !stop(match) && actions < maxActions {
            actions += 1
            if match.needsNewDeal {
                match.startNextDeal()
                continue
            }
            guard let actor = match.actor else { break }
            let action = bot.chooseAction(match: match, seat: actor, rng: &rng)
            if (try? match.apply(action)) == nil {
                guard let fallback = match.deal?.legalActions().first,
                      (try? match.apply(fallback)) != nil else { break }
            }
        }
        return match
    }

    /// Итоги сдачи на экране: сдача сыграна (не «все пас»).
    static func dealJustScored(_ match: Match) -> Bool {
        guard let deal = match.deal, deal.isFinished, let last = match.history.last else { return false }
        return last.outcome != .allPassed
    }
}
