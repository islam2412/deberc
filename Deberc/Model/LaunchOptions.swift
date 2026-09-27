import Foundation
import DebercKit

/// Аргументы запуска для проверки на симуляторе (CI, скриншоты для App Store).
///
///     -DebercAutoplay YES            за всех играют компьютеры, быстро, партия за партией
///     -DebercPlayers 2|3             число игроков
///     -DebercLevel novice|amateur|expert|master   уровень соперников (понимает и easy/medium/hard)
///     -DebercScreen <экран>          открыть экран: menu, table, settings, rules, scoresheet, stats,
///                                    onboarding, summary (итог сдачи), gameover (конец партии)
///     -DebercSeed N                  зерно случайности — чтобы прогон повторялся
///
/// С любым из `-DebercAutoplay`/`-DebercScreen` приложение работает в «демо-режиме»:
/// настройки, партия и статистика игрока не читаются и не затираются (свой отдельный каталог),
/// а ход автоигры пишется в Library/Caches/autoplay-progress.json.
struct LaunchOptions: Equatable {
    enum Screen: String, CaseIterable {
        case menu, table, settings, rules, scoresheet, stats, onboarding, summary, gameover
    }

    var autoplay = false
    var players: Int?
    var level: BotLevel?
    /// Запрошенный экран как есть (в нижнем регистре); `screen` — если он известен.
    var screenName: String?
    var screen: Screen?
    var seed: UInt64?

    var isDemo: Bool { autoplay || screenName != nil }

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
        // Приветствие закрыло бы любой другой экран.
        s.hasSeenOnboarding = screen != .onboarding
        return s
    }
}
