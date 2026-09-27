import SwiftUI
import UIKit
import DebercKit

/// Состояние приложения и «дирижёр» партии: применяет ходы, запускает ботов,
/// держит паузы, чтобы было видно, кто чем сходил.
@MainActor
final class GameStore: ObservableObject {
    /// Место человека за столом.
    let humanSeat = 0

    @Published private(set) var match: Match?
    @Published var settings: AppSettings {
        didSet { Storage.saveSettings(settings) }
    }
    @Published var isInGame = false

    /// Реплики игроков при торговле («Пас», «Беру ♥»).
    @Published private(set) var bubbles: [Int: String] = [:]
    /// Текущее всплывающее сообщение.
    @Published private(set) var banner: String?
    /// Только что собранная взятка — показывается на столе несколько секунд.
    @Published private(set) var displayedTrick: Trick?
    /// Кто из компьютеров сейчас думает.
    @Published private(set) var thinkingSeat: Int?
    /// Выбранная (приподнятая) карта на руке.
    @Published private(set) var selectedCard: Card?
    /// Подсказка для торговли.
    @Published private(set) var bidHint: String?
    @Published var showDealSummary = false

    private var driver: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var bannerQueue: [String] = []
    private var rng: SplitMix64
    /// Автоигра для проверки на симуляторе: за человека тоже играет компьютер.
    /// Включается только аргументом запуска `-DebercAutoplay YES`.
    private let autoplay: Bool

    init() {
        let defaults = UserDefaults.standard
        autoplay = defaults.bool(forKey: "DebercAutoplay")
        settings = Storage.loadSettings()
        match = Storage.loadMatch()
        rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))
        if autoplay {
            let players = defaults.integer(forKey: "DebercPlayers")
            settings.playerCount = players == 3 ? 3 : 2
            settings.speed = .fast
            newGame()
        }
    }

    // MARK: - Свойства для экранов

    var canContinue: Bool {
        guard let match else { return false }
        return !match.isOver
    }

    var isHumanTurn: Bool {
        match?.actor == humanSeat && displayedTrick == nil
    }

    /// Карты, которыми человек может сходить сейчас.
    var legalCards: Set<Card> {
        guard isHumanTurn, let deal = match?.deal, deal.phase == .playing else { return [] }
        return Set(deal.legalCards(for: humanSeat))
    }

    // MARK: - Управление партией

    func newGame() {
        driver?.cancel()
        let count = settings.playerCount
        var names = [settings.playerName.trimmingCharacters(in: .whitespaces)]
        if names[0].isEmpty { names[0] = "Вы" }
        for i in 0..<(count - 1) {
            let name = i < settings.botNames.count ? settings.botNames[i].trimmingCharacters(in: .whitespaces) : ""
            names.append(name.isEmpty ? "Бот \(i + 1)" : name)
        }
        match = Match(playerCount: count, names: names, rules: settings.rules, seed: rng.next())
        resetTransient()
        bannerQueue.removeAll()
        banner = nil
        showDealSummary = false
        isInGame = true
        startNextDeal()
    }

    func continueGame() {
        guard let match else { return }
        resetTransient()
        isInGame = true
        if match.deal == nil {
            startNextDeal()
            return
        }
        if match.isOver || (match.needsNewDeal && match.history.last?.outcome != .allPassed) {
            showDealSummary = true
        }
        drive()
    }

    func leaveGame() {
        driver?.cancel()
        driver = nil
        thinkingSeat = nil
        showDealSummary = false
        isInGame = false
    }

    func startNextDeal() {
        guard var current = match, current.needsNewDeal else { return }
        showDealSummary = false
        resetTransient()
        let events = current.startNextDeal()
        match = current
        process(events)
        persist()
        drive()
    }

    // MARK: - Действия человека

    func perform(_ action: Action) {
        guard isHumanTurn, var current = match else { return }
        do {
            let events = try current.apply(action)
            match = current
            selectedCard = nil
            bidHint = nil
            if case .play = action {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            process(events)
            persist()
            drive()
        } catch {
            showBanner("Так сейчас нельзя")
        }
    }

    func tapCard(_ card: Card) {
        guard isHumanTurn, let deal = match?.deal, deal.phase == .playing else { return }
        guard deal.legalCards(for: humanSeat).contains(card) else {
            showBanner(illegalReason(deal))
            return
        }
        if settings.confirmCardTap && selectedCard != card {
            withAnimation(.easeOut(duration: 0.15)) { selectedCard = card }
            return
        }
        perform(.play(card))
    }

    /// Совет сильного бота.
    func showHint() {
        guard isHumanTurn, let snapshot = match else { return }
        let seed = rng.next()
        let seat = humanSeat
        Task {
            let action = await Task.detached(priority: .userInitiated) { () -> Action in
                var local = SplitMix64(seed: seed)
                return Bot(level: .hard).chooseAction(match: snapshot, seat: seat, rng: &local)
            }.value
            guard self.match == snapshot else { return }
            switch action {
            case .play(let card):
                withAnimation(.easeOut(duration: 0.15)) { self.selectedCard = card }
                self.showBanner("Совет: \(card)")
            case .take:
                self.bidHint = "Совет: брать"
            case .name(let suit):
                self.bidHint = "Совет: играть \(suit.symbol)"
            case .pass:
                self.bidHint = "Совет: пас"
            case .exchangeSeven:
                self.bidHint = "Совет: поменять"
            }
        }
    }

    // MARK: - Ходы компьютера

    private func drive() {
        driver?.cancel()
        driver = Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            if displayedTrick != nil {
                try? await Task.sleep(for: settings.speed.trickPause)
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.25)) { displayedTrick = nil }
                continue
            }
            guard let snapshot = match else { return }
            if snapshot.isOver || snapshot.needsNewDeal {
                thinkingSeat = nil
                // «Все пас» — просто пересдаём, без окна итогов.
                if !snapshot.isOver, snapshot.history.last?.outcome == .allPassed {
                    try? await Task.sleep(for: settings.speed.bannerTime)
                    if Task.isCancelled { return }
                    startNextDeal()
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.3)) { showDealSummary = true }
                if autoplay {
                    try? await Task.sleep(for: .milliseconds(2500))
                    if Task.isCancelled { return }
                    if snapshot.isOver { newGame() } else { startNextDeal() }
                }
                return
            }
            guard let actor = snapshot.actor, actor != humanSeat || autoplay else {
                thinkingSeat = nil
                return
            }
            thinkingSeat = actor
            let level = settings.botLevel
            let seed = rng.next()
            let started = Date()
            let action = await Task.detached(priority: .userInitiated) { () -> Action in
                var local = SplitMix64(seed: seed)
                return Bot(level: level).chooseAction(match: snapshot, seat: actor, rng: &local)
            }.value
            let remaining = settings.speed.botDelay - .milliseconds(Int(Date().timeIntervalSince(started) * 1000))
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
            if Task.isCancelled { return }
            guard var current = match, current == snapshot else { return }
            do {
                let events = try current.apply(action)
                withAnimation(.easeInOut(duration: 0.25)) {
                    match = current
                }
                process(events)
                persist()
            } catch {
                thinkingSeat = nil
                return
            }
        }
    }

    // MARK: - События

    private func process(_ events: [DealEvent]) {
        guard let current = match else { return }
        for event in events {
            switch event {
            case .bid(let bid):
                bubbles[bid.seat] = Narrator.bidText(bid)
            case .playStarted:
                bubbles = [:]
            case .trickCompleted(let trick):
                displayedTrick = trick
            case .allPassed, .fourSevens:
                bubbles = [:]
            default:
                break
            }
            if let text = Narrator.message(for: event, names: current.names, humanSeat: humanSeat, rules: current.rules) {
                showBanner(text)
            }
        }
    }

    private func resetTransient() {
        bubbles = [:]
        displayedTrick = nil
        thinkingSeat = nil
        selectedCard = nil
        bidHint = nil
    }

    private func persist() {
        Storage.saveMatch(match)
    }

    private func illegalReason(_ deal: Deal) -> String {
        guard let led = deal.currentTrick.ledSuit, let trump = deal.trump else { return "Так сейчас нельзя" }
        if deal.hands[humanSeat].contains(where: { $0.suit == led }) {
            return "Нужно ходить в масть \(led.symbol)"
        }
        return "Нужно бить козырем \(trump.symbol)"
    }

    // MARK: - Сообщения

    func showBanner(_ text: String) {
        bannerQueue.append(text)
        if bannerTask == nil { pumpBanners() }
    }

    private func pumpBanners() {
        bannerTask = Task { [weak self] in
            while true {
                guard let self else { return }
                if self.bannerQueue.isEmpty {
                    withAnimation(.easeInOut(duration: 0.25)) { self.banner = nil }
                    self.bannerTask = nil
                    return
                }
                let next = self.bannerQueue.removeFirst()
                withAnimation(.easeInOut(duration: 0.25)) { self.banner = next }
                try? await Task.sleep(for: self.settings.speed.bannerTime)
            }
        }
    }
}
