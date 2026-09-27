import Foundation
import DebercKit

/// Сохранение настроек и текущей партии на устройстве.
enum Storage {
    private static let settingsKey = "deberc.settings.v1"

    static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    static func saveSettings(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private static var matchURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("current-match.json")
    }

    static func loadMatch() -> Match? {
        guard let data = try? Data(contentsOf: matchURL) else { return nil }
        return try? JSONDecoder().decode(Match.self, from: data)
    }

    static func saveMatch(_ match: Match?) {
        if let match, let data = try? JSONEncoder().encode(match) {
            try? data.write(to: matchURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: matchURL)
        }
    }
}
