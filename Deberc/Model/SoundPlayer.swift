import AVFoundation
import UIKit

/// Тихие звуки стола и вибрация.
///
/// Звуки — короткие файлы из Deberc/Sounds (сгенерированы заранее, по 5–40 КБ).
/// Категория `.ambient`: не глушат музыку и подкасты, молчат при выключенном звонке.
@MainActor
final class SoundPlayer {
    enum Sound: String, CaseIterable {
        /// Раздача: карты скользят одна за другой.
        case deal
        /// Карта ложится на стол.
        case card
        /// Сбор взятки.
        case collect
        /// Бэла.
        case bella
        /// Партия выиграна.
        case win
        /// Партия проиграна.
        case lose
        /// Так ходить нельзя.
        case error

        var volume: Float {
            switch self {
            case .deal: return 0.45
            case .card: return 0.55
            case .collect: return 0.45
            case .bella: return 0.5
            case .win: return 0.55
            case .lose: return 0.45
            case .error: return 0.5
            }
        }

        /// Сколько копий держать, чтобы быстрые повторы не обрывали друг друга.
        var voices: Int { self == .card ? 3 : 1 }
    }

    enum Haptic {
        /// Своя карта легла на стол.
        case tap
        /// Выбор карты, совет.
        case select
        /// Своя взятка, отмена хода.
        case soft
        /// Ваш ход после ходов соперников.
        case turn
        case success
        case warning
        case error
    }

    var soundEnabled = true
    var hapticsEnabled = true

    private var players: [Sound: [AVAudioPlayer]] = [:]
    private var nextVoice: [Sound: Int] = [:]
    private var missing: Set<Sound> = []
    private var sessionReady = false

    private lazy var lightImpact = UIImpactFeedbackGenerator(style: .light)
    private lazy var softImpact = UIImpactFeedbackGenerator(style: .soft)
    private lazy var selection = UISelectionFeedbackGenerator()
    private lazy var notification = UINotificationFeedbackGenerator()

    /// Загрузить звуки заранее, чтобы первый ход не ждал чтения файла.
    func prepare() {
        guard soundEnabled else { return }
        for sound in Sound.allCases { _ = player(for: sound) }
    }

    /// Приложение снова на экране: после звонка аудиосессию стоит настроить заново.
    func resume() {
        sessionReady = false
    }

    func play(_ sound: Sound) {
        guard soundEnabled else { return }
        configureSession()
        guard let player = player(for: sound) else { return }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    func haptic(_ kind: Haptic) {
        guard hapticsEnabled else { return }
        switch kind {
        case .tap: lightImpact.impactOccurred(intensity: 0.8)
        case .select: selection.selectionChanged()
        case .soft: softImpact.impactOccurred(intensity: 0.7)
        case .turn: softImpact.impactOccurred(intensity: 0.5)
        case .success: notification.notificationOccurred(.success)
        case .warning: notification.notificationOccurred(.warning)
        case .error: notification.notificationOccurred(.error)
        }
    }

    // MARK: - Внутреннее

    private func configureSession() {
        guard !sessionReady else { return }
        sessionReady = true
        let session = AVAudioSession.sharedInstance()
        do {
            // `.ambient` сама смешивается с чужим звуком (явный .mixWithOthers для неё не нужен).
            try session.setCategory(.ambient, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            Diagnostics.log("Звук: не удалось настроить аудиосессию: \(error)")
        }
    }

    private func player(for sound: Sound) -> AVAudioPlayer? {
        if missing.contains(sound) { return nil }
        if players[sound] == nil {
            guard let url = SoundPlayer.url(for: sound) else {
                missing.insert(sound)
                Diagnostics.log("Звук \(sound.rawValue).wav не найден в приложении")
                return nil
            }
            var list: [AVAudioPlayer] = []
            for _ in 0..<sound.voices {
                guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.volume = sound.volume
                player.prepareToPlay()
                list.append(player)
            }
            guard !list.isEmpty else {
                missing.insert(sound)
                return nil
            }
            players[sound] = list
        }
        guard let list = players[sound], !list.isEmpty else { return nil }
        let index = (nextVoice[sound] ?? 0) % list.count
        nextVoice[sound] = index + 1
        return list[index]
    }

    private static func url(for sound: Sound) -> URL? {
        Bundle.main.url(forResource: sound.rawValue, withExtension: "wav")
            ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "Sounds")
    }
}
