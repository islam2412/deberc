import Foundation
import DebercKit

/// Аргументы запуска для проверки на симуляторе (CI, скриншоты для App Store).
///
///     -DebercAutoplay YES            за всех играют компьютеры, быстро, партия за партией
///     -DebercPlayers 2|3             число игроков
///     -DebercLevel novice|amateur|expert|master   уровень соперников (понимает и easy/medium/hard)
///     -DebercScreen <экран>          открыть экран: menu, table, settings, rules, scoresheet, stats,
///                                    onboarding, summary (итог сдачи), gameover (конец партии),
///                                    persona (карточка соперника), opponents (выбор соперника)
///     -DebercSeed N                  зерно случайности — чтобы прогон повторялся
///     -DebercResume YES              открыть партию, сохранённую прошлым демо-запуском, как при обычном
///                                    перезапуске приложения (проверка восстановления в CI)
///     -DebercLarge YES               крупный режим (крупные карты, подписи и кнопки)
///     -DebercSpeed slow|normal|fast  темп игры
///     -DebercBanter off|rare|normal|often   как часто подначивают соперники
///     -DebercZoom YES                показать приложение как на iPhone с «Увеличенным» видом экрана
///                                    (ширина 320 pt, растянутая на весь экран) — проверка тесной раскладки
///     -DebercScriptedHuman YES       (с -DebercScreen table) за человека ходит компьютер — через те же
///                                    действия, что и касания: видно автоход, отмену, панели хода
///     -DebercDragPreview YES         в свой ход первая допустимая карта «в пальцах» (снимок броска)
///     -DebercHumanDelay MS           автоигра: за человека компьютер ходит не раньше чем через MS мс,
///                                    чтобы на снимках были видны кнопки хода
///     -DebercOrientation landscape   iPad, iOS 17+: альбомная ориентация — приложение само поворачивает окно
///                                    (симулятор иначе не повернуть), а если система не даёт (режим
///                                    «Приложения в окнах»), рисует альбомный экран уменьшенным;
///                                    на iPhone ничего не делает
///
/// Остальные флаги (-DebercLarge, -DebercSpeed, -DebercBanter, -DebercZoom, -DebercScriptedHuman,
/// -DebercDragPreview, -DebercHumanDelay, -DebercOrientation) действуют только вместе
/// с `-DebercAutoplay` или `-DebercScreen`:
/// настройки игрока они не трогают. -DebercScriptedHuman ходит за человека теми же действиями,
/// что и касания, — с отменой хода и всем прочим.
///
/// С любым из `-DebercAutoplay`/`-DebercScreen` приложение работает в «демо-режиме»:
/// настройки, партия и статистика игрока не читаются и не затираются (свой отдельный каталог),
/// а ход автоигры пишется в Library/Caches/autoplay-progress.json.
struct LaunchOptions: Equatable {
    enum Screen: String, CaseIterable {
        case menu, table, settings, rules, scoresheet, stats, onboarding, summary, gameover
        /// Карточка соперника за столом и выбор соперника в меню.
        case persona, opponents
    }

    var autoplay = false
    var players: Int?
    var level: BotLevel?
    /// Запрошенный экран как есть (в нижнем регистре); `screen` — если он известен.
    var screenName: String?
    var screen: Screen?
    var seed: UInt64?
    var large = false
    var speed: GameSpeed?
    var banter: BanterLevel?
    var humanDelay: Duration?
    var zoomed = false
    var dragPreview = false
    var scriptedHuman = false
    /// Альбомная ориентация на iPad (`-DebercOrientation landscape`), только в демо-режиме.
    var landscape = false

    var resume = false

    var isDemo: Bool { autoplay || screenName != nil || resume }

    /// Аргументы этого запуска.
    static let current = LaunchOptions(defaults: .standard)

    init() {}

    /// Разбор из UserDefaults: аргументы вида `-Ключ значение` попадают туда сами.
    init(defaults: UserDefaults) {
        autoplay = defaults.bool(forKey: "DebercAutoplay")
        let count = defaults.integer(forKey: "DebercPlayers")
        players = (2...3).contains(count) ? count : nil
        if let raw = defaults.string(forKey: "DebercLevel") {
            level = LaunchOptions.level(raw)
        }
        if let raw = defaults.string(forKey: "DebercScreen") {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !name.isEmpty {
                screen = LaunchOptions.screen(name)
                screenName = screen?.rawValue ?? name
            }
        }
        if let raw = defaults.string(forKey: "DebercSeed") {
            seed = UInt64(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        large = defaults.bool(forKey: "DebercLarge")
        zoomed = defaults.bool(forKey: "DebercZoom")
        resume = defaults.bool(forKey: "DebercResume")
        dragPreview = defaults.bool(forKey: "DebercDragPreview")
        scriptedHuman = defaults.bool(forKey: "DebercScriptedHuman")
        let delay = defaults.integer(forKey: "DebercHumanDelay")
        if delay > 0 { humanDelay = .milliseconds(delay) }
        if let raw = defaults.string(forKey: "DebercBanter") {
            banter = BanterLevel(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        if let raw = defaults.string(forKey: "DebercSpeed") {
            speed = GameSpeed(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        // Поворот — только для снимков: у игрока iPad поворачивается сам.
        if isDemo, let raw = defaults.string(forKey: "DebercOrientation") {
            landscape = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "landscape"
        }
    }

    static func level(_ raw: String) -> BotLevel? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return nil }
        if let level = BotLevel(rawValue: name) { return level }
        switch name {
        case "easy", "новичок": return .novice
        case "medium", "любитель": return .amateur
        case "hard", "strong", "знаток": return .expert
        case "мастер": return .master
        default: return nil
        }
    }

    static func screen(_ name: String) -> Screen? {
        if let screen = Screen(rawValue: name) { return screen }
        switch name {
        case "game", "play": return .table
        case "sheet", "score", "scores", "record": return .scoresheet
        case "statistics": return .stats
        case "welcome", "intro": return .onboarding
        case "deal", "dealsummary", "deal-summary": return .summary
        case "over", "matchover", "match-over", "victory": return .gameover
        default: return nil
        }
    }

    /// Настройки демо-режима: всегда с чистого листа, чтобы кадры не зависели от устройства.
    func demoSettings() -> AppSettings {
        var s = AppSettings()
        if let players { s.playerCount = players }
        if let level {
            s.difficulty = level
            s.opponentIDs = AppSettings.defaultOpponentIDs(for: level)
        }
        if autoplay { s.speed = .fast }
        if let speed { s.speed = speed }
        if let banter { s.banter = banter }
        s.largeCards = large
        // Приветствие закрыло бы любой другой экран.
        s.hasSeenOnboarding = screen != .onboarding
        return s
    }
}
