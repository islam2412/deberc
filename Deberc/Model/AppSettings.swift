import Foundation
import DebercKit

/// Темп игры: сколько «думают» компьютеры, сколько лежит собранная взятка и висит сообщение.
/// Меняется прямо во время партии — действует со следующего хода.
enum GameSpeed: String, Codable, CaseIterable, Identifiable {
    case slow, normal, fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slow: return "Медленно"
        case .normal: return "Обычно"
        case .fast: return "Быстро"
        }
    }

    /// Обычное время раздумья компьютера. Над трудным решением он думает дольше,
    /// над единственной допустимой картой — короче (см. `ThinkingTime`).
    var botDelay: Duration {
        switch self {
        case .slow: return .milliseconds(1500)
        case .normal: return .milliseconds(1000)
        case .fast: return .milliseconds(550)
        }
    }

    /// Пауза после важного события — назначен козырь, поменяли семёрку: соперник не ходит сразу,
    /// чтобы было видно, что произошло (см. `GameFlow.pause(after:speed:humanSeat:)`).
    var announcePause: Duration {
        switch self {
        case .slow: return .milliseconds(2600)
        case .normal: return .milliseconds(1900)
        case .fast: return .milliseconds(1200)
        }
    }

    /// Сколько показывать собранную взятку.
    var trickPause: Duration {
        switch self {
        case .slow: return .milliseconds(2000)
        case .normal: return .milliseconds(1250)
        case .fast: return .milliseconds(700)
        }
    }

    /// Сколько показывать сообщение.
    var bannerTime: Duration {
        switch self {
        case .slow: return .milliseconds(2800)
        case .normal: return .milliseconds(2100)
        case .fast: return .milliseconds(1500)
        }
    }

    /// Длительность перелёта карты, с — для анимаций стола.
    var cardFlight: Double {
        switch self {
        case .slow: return 0.45
        case .normal: return 0.35
        case .fast: return 0.25
        }
    }
}

/// Автоход: когда карта ходит сама, без касания.
enum AutoPlay: String, Codable, CaseIterable, Identifiable {
    /// Всегда ходить самому.
    case off
    /// Последняя карта сдачи ходит сама.
    case lastCard
    /// Сама ходит любая вынужденная карта — когда ходить можно только ею.
    case onlyCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Выключен"
        case .lastCard: return "Последняя карта"
        case .onlyCard: return "Любая вынужденная"
        }
    }

    /// Карта, которой нужно сходить за человека (nil — ждать его хода).
    /// `hand` — карты на руке, `legal` — которыми можно ходить сейчас.
    func card(hand: [Card], legal: [Card]) -> Card? {
        guard legal.count == 1, let only = legal.first else { return nil }
        switch self {
        case .off: return nil
        case .lastCard: return hand.count == 1 ? only : nil
        case .onlyCard: return only
        }
    }
}

/// Настройки игрока. Хранятся на устройстве; читаются терпимо: отсутствующие поля — по умолчанию,
/// старые поля (`botLevel`, `botNames` из первых сборок) переводятся в новые.
struct AppSettings: Codable, Equatable {
    /// Правила для новой партии (идущая партия играет по своим).
    var rules = RuleSet.house
    /// Быстрый выбор уровня: подбирает соперников этого уровня.
    var difficulty = BotLevel.amateur
    /// Соперники новой партии: id персонажей [место 1, место 2]. Вдвоём играет только первый.
    var opponentIDs: [String] = AppSettings.defaultOpponentIDs(for: .amateur)
    var speed = GameSpeed.normal
    var playerName = "Вы"
    /// Первое касание выбирает карту, второе — ходит.
    var confirmCardTap = true
    /// 2 или 3.
    var playerCount = 2
    var soundEnabled = true
    var hapticsEnabled = true
    /// Четырёхцветная колода: у каждой масти свой цвет.
    var fourColorDeck = false
    /// Крупный режим: крупнее карты и подписи.
    var largeCards = false
    /// Рубашка карт.
    var cardBack = CardBackStyle.burgundy
    /// Показывать свои очки и взятки во время сдачи.
    var showLivePoints = true
    /// Последняя (или любая вынужденная) карта ходит сама.
    var autoPlay = AutoPlay.lastCard
    /// Как часто соперники подначивают.
    var banter = BanterLevel.normal
    var hasSeenOnboarding = false
    /// Подсказку про жесты (коснуться дважды или смахнуть карту вверх) уже показали.
    var hasSeenPlayTip = false

    init() {}

    /// Соперники по умолчанию для уровня — всегда два разных персонажа.
    static func defaultOpponentIDs(for level: BotLevel) -> [String] {
        sanitizedOpponentIDs([], level: level)
    }

    /// Два разных существующих персонажа: сначала выбранные, потом — подходящие по уровню.
    static func sanitizedOpponentIDs(_ ids: [String], level: BotLevel) -> [String] {
        var result: [String] = []
        for id in ids where result.count < 2 && Persona.byID(id) != nil && !result.contains(id) {
            result.append(id)
        }
        for persona in Persona.defaults(level: level, count: 2) + Persona.all
        where result.count < 2 && !result.contains(persona.id) {
            result.append(persona.id)
        }
        return result
    }

    /// Соперники, которые сядут за стол при нынешнем числе игроков.
    var activeOpponentIDs: [String] {
        Array(opponentIDs.prefix(max(0, playerCount - 1)))
    }

    /// Согласовать поля после изменения (`old` — значение до него):
    /// сменили уровень — подбираются соперники этого уровня; выбрали соперников одного уровня —
    /// переключается и уровень. Число игроков — 2 или 3, соперники — два разных персонажа.
    func normalized(from old: AppSettings) -> AppSettings {
        var s = self
        if !(2...3).contains(s.playerCount) { s.playerCount = old.playerCount == 3 ? 3 : 2 }
        if s.difficulty != old.difficulty && s.opponentIDs == old.opponentIDs {
            s.opponentIDs = AppSettings.defaultOpponentIDs(for: s.difficulty)
        } else if s.opponentIDs != old.opponentIDs && s.difficulty == old.difficulty {
            let levels = Set(s.activeOpponentIDs.compactMap { Persona.byID($0)?.level })
            if levels.count == 1, let level = levels.first { s.difficulty = level }
        }
        s.opponentIDs = AppSettings.sanitizedOpponentIDs(s.opponentIDs, level: s.difficulty)
        return s
    }

    // MARK: - Сохранение

    enum CodingKeys: String, CodingKey {
        case rules, difficulty, opponentIDs, speed, playerName, confirmCardTap, playerCount
        case soundEnabled, hapticsEnabled, fourColorDeck, largeCards, cardBack, showLivePoints, autoPlay, banter
        case hasSeenOnboarding, hasSeenPlayTip
    }

    /// Поля первых сборок.
    private enum LegacyKeys: String, CodingKey {
        case botLevel, botNames
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
        let oldLevel = legacy.flatMap { (try? $0.decodeIfPresent(String.self, forKey: .botLevel)) ?? nil }
        let oldNames = legacy.flatMap { (try? $0.decodeIfPresent([String].self, forKey: .botNames)) ?? nil }

        var s = AppSettings()
        s.rules = value(RuleSet.self, .rules) ?? s.rules
        if let level = value(BotLevel.self, .difficulty) {
            s.difficulty = level
        } else if let oldLevel {
            s.difficulty = AppSettings.migratedLevel(oldLevel)
        }
        if let ids = value([String].self, .opponentIDs) {
            s.opponentIDs = ids
        } else {
            // Раньше соперники были безымянными ботами уровня; если имя совпадает с персонажем — берём его.
            let named = (oldNames ?? []).compactMap { name in
                Persona.all.first { $0.name == name.trimmingCharacters(in: .whitespaces) }?.id
            }
            s.opponentIDs = named + AppSettings.defaultOpponentIDs(for: s.difficulty)
        }
        s.speed = value(GameSpeed.self, .speed) ?? s.speed
        s.playerName = value(String.self, .playerName) ?? s.playerName
        s.confirmCardTap = value(Bool.self, .confirmCardTap) ?? s.confirmCardTap
        s.playerCount = value(Int.self, .playerCount) ?? s.playerCount
        s.soundEnabled = value(Bool.self, .soundEnabled) ?? s.soundEnabled
        s.hapticsEnabled = value(Bool.self, .hapticsEnabled) ?? s.hapticsEnabled
        s.fourColorDeck = value(Bool.self, .fourColorDeck) ?? s.fourColorDeck
        s.largeCards = value(Bool.self, .largeCards) ?? s.largeCards
        s.cardBack = value(CardBackStyle.self, .cardBack) ?? s.cardBack
        s.showLivePoints = value(Bool.self, .showLivePoints) ?? s.showLivePoints
        s.autoPlay = value(AutoPlay.self, .autoPlay) ?? s.autoPlay
        s.banter = value(BanterLevel.self, .banter) ?? s.banter
        s.hasSeenPlayTip = value(Bool.self, .hasSeenPlayTip) ?? s.hasSeenPlayTip
        // Настройки уже были сохранены — значит, приложение открывали: приветствие не показываем.
        s.hasSeenOnboarding = value(Bool.self, .hasSeenOnboarding) ?? true

        if !(2...3).contains(s.playerCount) { s.playerCount = 2 }
        s.opponentIDs = AppSettings.sanitizedOpponentIDs(s.opponentIDs, level: s.difficulty)
        self = s
    }

    /// Уровни первых сборок: «Лёгкий», «Средний», «Сильный».
    static func migratedLevel(_ raw: String) -> BotLevel {
        switch raw.lowercased() {
        case "easy": return .novice
        case "medium": return .amateur
        case "hard": return .expert
        default: return BotLevel(rawValue: raw.lowercased()) ?? .amateur
        }
    }
}
