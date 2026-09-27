import Foundation
import DebercKit
#if canImport(os)
import os
#endif

/// Сохранённая партия вместе с соперниками — всё, что нужно, чтобы продолжить её после перезапуска.
///
/// Формат 1 (первые сборки) — «голый» `Match` в current-match.json; он переводится в этот
/// при первом запуске новой версии (`migrating(_:settings:)`).
/// Читается терпимо: обязательна только сама партия, остальное — по умолчанию.
struct SavedGame: Codable, Equatable {
    static let currentVersion = 2

    var version = SavedGame.currentVersion
    /// Метка партии: одна и та же от первой сдачи до последней.
    var id = UUID()
    var match: Match
    /// Соперники по местам: `opponentIDs[i]` сидит на месте i + 1.
    var opponentIDs: [String]
    var startedAt = Date()
    var hintsUsed = 0
    var undosUsed = 0
    /// Игрок был за столом — после перезапуска сразу вернуть его туда.
    var inGame = false

    init(match: Match, opponentIDs: [String]) {
        self.match = match
        self.opponentIDs = opponentIDs
    }

    enum CodingKeys: String, CodingKey {
        case version, id, match, opponentIDs, startedAt, hintsUsed, undosUsed, inGame
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        match = try c.decode(Match.self, forKey: .match)
        version = value(Int.self, .version) ?? SavedGame.currentVersion
        id = value(UUID.self, .id) ?? UUID()
        opponentIDs = value([String].self, .opponentIDs) ?? []
        startedAt = value(Date.self, .startedAt) ?? Date()
        hintsUsed = max(0, value(Int.self, .hintsUsed) ?? 0)
        undosUsed = max(0, value(Int.self, .undosUsed) ?? 0)
        inGame = value(Bool.self, .inGame) ?? false
    }

    /// Партия из первых сборок: соперников подбираем по именам (если совпадают с персонажами),
    /// иначе — по настройкам. Имена ботов в партии приводятся к именам персонажей.
    static func migrating(_ legacy: Match, settings: AppSettings) -> SavedGame {
        var match = legacy
        let count = match.playerCount - 1
        let named = (1..<match.playerCount).compactMap { seat -> String? in
            guard match.names.indices.contains(seat) else { return nil }
            let name = match.names[seat].trimmingCharacters(in: .whitespaces)
            return Persona.all.first { $0.name == name }?.id
        }
        let ids = Set(named).count == count ? named : settings.opponentIDs
        let opponents = GameFlow.opponents(ids: ids, count: count, fallback: settings.difficulty)
        GameFlow.syncNames(&match, opponents: opponents)
        return SavedGame(match: match, opponentIDs: opponents.map(\.id))
    }
}

/// Сохранение настроек, партии и статистики на устройстве.
///
/// Запись — атомарная, в фоновой очереди (порядок сохраняется). Нечитаемый файл не затирается:
/// он переименовывается в `*.unreadable-<время>.json` рядом с исходным — его можно вытащить и починить.
/// Демо-режим (аргументы запуска для CI) работает в своём каталоге и не трогает данные игрока.
struct Storage {
    enum Space { case user, demo }

    enum GameLoad {
        case none
        case loaded(SavedGame)
        /// Партия старого формата (current-match.json) — её нужно перевести и сохранить заново.
        case legacy(Match)
        /// Файл есть, но прочитать его не удалось; он отложен в сторону.
        case unreadable
    }

    let space: Space
    let directory: URL

    private static let settingsKey = "deberc.settings.v1"
    private static let io = DispatchQueue(label: "deberc.storage", qos: .utility)

    init(space: Space) {
        self.space = space
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        switch space {
        case .user:
            directory = base
        case .demo:
            directory = base.appendingPathComponent("Demo", isDirectory: true)
            // Каждый демо-запуск — с чистого листа.
            try? fm.removeItem(at: directory)
        }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var gameURL: URL { directory.appendingPathComponent("current-game.json") }
    private var legacyGameURL: URL { directory.appendingPathComponent("current-match.json") }
    private var statsURL: URL { directory.appendingPathComponent("stats.json") }

    // MARK: - Настройки

    func loadSettings() -> AppSettings {
        guard space == .user, let data = UserDefaults.standard.data(forKey: Storage.settingsKey) else {
            return AppSettings()
        }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Diagnostics.log("Настройки не прочитались: \(error)")
            UserDefaults.standard.set(data, forKey: Storage.settingsKey + ".unreadable")
            return AppSettings()
        }
    }

    func saveSettings(_ settings: AppSettings) {
        guard space == .user else { return }
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(settings), forKey: Storage.settingsKey)
        } catch {
            Diagnostics.log("Настройки не сохранились: \(error)")
        }
    }

    // MARK: - Партия

    func loadGame() -> GameLoad {
        let fm = FileManager.default
        if let data = fm.contents(atPath: gameURL.path) {
            do {
                return .loaded(try JSONDecoder().decode(SavedGame.self, from: data))
            } catch {
                Diagnostics.log("Партия не прочиталась: \(error)")
                moveAside(gameURL)
                return .unreadable
            }
        }
        if let data = fm.contents(atPath: legacyGameURL.path) {
            do {
                return .legacy(try JSONDecoder().decode(Match.self, from: data))
            } catch {
                Diagnostics.log("Партия старого формата не прочиталась: \(error)")
                moveAside(legacyGameURL)
                return .unreadable
            }
        }
        return .none
    }

    /// nil — удалить сохранение.
    func saveGame(_ game: SavedGame?) {
        let url = gameURL
        let legacy = legacyGameURL
        guard let game else {
            Storage.io.async {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: legacy)
            }
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(game)
        } catch {
            Diagnostics.log("Партия не сохранилась: \(error)")
            return
        }
        Storage.write(data, to: url) {
            // Новый файл записан — старый формат больше не нужен.
            if FileManager.default.fileExists(atPath: legacy.path) {
                try? FileManager.default.removeItem(at: legacy)
            }
        }
    }

    // MARK: - Статистика

    func loadStats() -> PlayerStats {
        guard let data = FileManager.default.contents(atPath: statsURL.path) else { return PlayerStats() }
        do {
            return try JSONDecoder().decode(PlayerStats.self, from: data)
        } catch {
            Diagnostics.log("Статистика не прочиталась: \(error)")
            moveAside(statsURL)
            return PlayerStats()
        }
    }

    func saveStats(_ stats: PlayerStats) {
        do {
            Storage.write(try JSONEncoder().encode(stats), to: statsURL)
        } catch {
            Diagnostics.log("Статистика не сохранилась: \(error)")
        }
    }

    // MARK: - Прогресс автоигры (для CI)

    /// Library/Caches/autoplay-progress.json: {"deals": N, "matches": M, "phase": "...", "updated": <unix time>}.
    func writeProgress(deals: Int, matches: Int, phase: String) {
        guard space == .demo,
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let object: [String: Any] = [
            "deals": deals,
            "matches": matches,
            "phase": phase,
            "updated": Int(Date().timeIntervalSince1970),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        Storage.io.async {
            try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            try? data.write(to: caches.appendingPathComponent("autoplay-progress.json"), options: .atomic)
        }
    }

    /// Дождаться, пока всё поставленное в очередь запишется (перед уходом в фон).
    func flush() {
        Storage.io.sync {}
    }

    // MARK: - Внутреннее

    private static func write(_ data: Data, to url: URL, then done: (@Sendable () -> Void)? = nil) {
        io.async {
            do {
                try data.write(to: url, options: .atomic)
                done?()
            } catch {
                Diagnostics.log("Не удалось записать \(url.lastPathComponent): \(error)")
            }
        }
    }

    /// Отложить нечитаемый файл, чтобы следующее сохранение его не затёрло.
    @discardableResult
    private func moveAside(_ url: URL) -> URL? {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let name = "\(url.deletingPathExtension().lastPathComponent).unreadable-\(stamp).json"
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        try? fm.removeItem(at: target)
        do {
            try fm.moveItem(at: url, to: target)
            return target
        } catch {
            Diagnostics.log("Не удалось отложить \(url.lastPathComponent): \(error)")
            try? fm.removeItem(at: url)
            return nil
        }
    }
}

/// Служебный журнал (Console.app, `log show --predicate 'subsystem == "deberc"'`).
enum Diagnostics {
    #if canImport(os)
    private static let logger = Logger(subsystem: "deberc", category: "app")
    #endif

    static func log(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #else
        FileHandle.standardError.write(Data(("deberc: " + message + "\n").utf8))
        #endif
    }

    /// Строка для CI в stderr (только в автоигре): «AUTOPLAY …».
    static func trace(_ message: String) {
        FileHandle.standardError.write(Data(("AUTOPLAY " + message + "\n").utf8))
    }
}
