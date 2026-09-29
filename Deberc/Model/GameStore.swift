import SwiftUI
import UIKit
import DebercKit

/// Состояние приложения и «дирижёр» партии: применяет ходы, запускает соперников,
/// держит паузы, чтобы было видно, кто чем сходил, сохраняет партию и статистику.
///
/// Решения «что дальше» принимает `GameFlow` (чистые функции), здесь — только исполнение:
/// ожидание, анимация, звук, сохранение. Один магазин на всё приложение — и на iPad
/// с несколькими окнами: фаза сцены приходит от приложения целиком, автоблокировкой
/// экрана управляет только он.
@MainActor
final class GameStore: ObservableObject {
    /// Место человека за столом.
    let humanSeat = 0

    // MARK: - Состояние для экранов

    @Published private(set) var match: Match?
    @Published var settings: AppSettings {
        didSet { settingsDidChange(from: oldValue) }
    }
    /// Открыт стол (иначе — меню). Можно менять и из экранов: `false` — то же, что `leaveGame()`.
    @Published var isInGame = false {
        didSet { if oldValue != isInGame { inGameDidChange() } }
    }
    /// Соперники текущей партии: `opponents[i]` сидит на месте i + 1.
    @Published private(set) var opponents: [Persona] = []
    @Published private(set) var stats: PlayerStats
    /// Реплики игроков при торговле по местам.
    @Published private(set) var bubbles: [Int: String] = [:]
    /// Текущее всплывающее сообщение.
    @Published private(set) var banner: String?
    /// Крупное объявление в центре стола (козырь назначен) — само гаснет через пару секунд.
    @Published private(set) var announcement: TableAnnouncement?
    /// Сообщение срочное (ошибка хода, совет, бэла) — его можно выделить цветом.
    @Published private(set) var bannerIsUrgent = false
    /// Только что собранная взятка — лежит на столе, пока её не соберут.
    @Published private(set) var displayedTrick: Trick?
    /// Кто из соперников сейчас думает.
    @Published private(set) var thinkingSeat: Int?
    /// Выбранная (приподнятая) карта на руке.
    @Published private(set) var selectedCard: Card?
    /// Совет (торговля, обмен семёрки или ход) — для подсветки.
    @Published private(set) var hintAction: Action?
    /// Совет считается.
    @Published private(set) var isHinting = false
    @Published var showDealSummary = false {
        didSet { if oldValue != showDealSummary { updateIdleTimer() } }
    }
    /// Экраны ставят `true`, пока открыт лист или диалог: игра на паузе.
    @Published var isOverlayPresented = false {
        didSet { if oldValue != isOverlayPresented { pauseDidChange() } }
    }
    /// Экран из аргумента запуска `-DebercScreen` (для CI и скриншотов); экраны открывают его сами.
    @Published var requestedScreen: String?
    /// Сколько раз в этой партии брали совет и отменяли ход.
    @Published private(set) var hintsUsed = 0
    @Published private(set) var undosUsed = 0
    /// Сохранённую партию прочитать не удалось (файл отложен в сторону) — сказать об этом в меню.
    @Published var loadProblem: String?

    @Published private var isSceneActive = true
    @Published private var undoStack: [Match] = []

    // MARK: - Внутреннее состояние

    private let options: LaunchOptions
    /// Автоигра (только по аргументу `-DebercAutoplay YES`): за человека тоже играет компьютер.
    private let autoplay: Bool
    private let storage: Storage
    private let sounds = SoundPlayer()
    private var rng: SplitMix64
    /// Зерно запуска: с ним автоигру можно повторить (`-DebercSeed`).
    private let launchSeed: UInt64

    private var gameID = UUID()
    private var startedAt = Date()

    private var driver: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var bannerQueue = BannerQueue()
    private var bannerGeneration = 0
    private var bannerShownAt = Date.distantPast
    private var hintTask: Task<Void, Never>?
    private var announcementTask: Task<Void, Never>?
    private var announcementSerial = 0
    /// Номер прогона очереди: отменённый прогон, проснувшись, не трогает новый.
    private var announcementRun = 0
    /// Объявления, ждущие своей очереди, и когда очередь освободится.
    private var announcementQueue: [(kind: TableAnnouncement.Kind, duration: Duration)] = []
    private var announcementsBusyUntil = ContinuousClock.now
    private var hintToken = 0
    private var hintCache: (match: Match, action: Action)?
    private var idleTask: Task<Void, Never>?
    private var lastActivity = Date()
    private var pauseEpoch = 0
    private var lastStepWasBot = false
    /// Раньше этого времени компьютер не ходит: только что назначили козырь, поменяли семёрку,
    /// раздали карты — это должно быть видно (`GameFlow.pause(after:speed:humanSeat:)`).
    private var holdUntil: ContinuousClock.Instant?
    private var normalizingSettings = false
    private var autoplayDeals = 0
    private var autoplayMatches = 0
    /// Сдача закончилась на глазах у игрока (а не прочитана из сохранения) — звук и вибрация итога уместны.
    private var dealEndedLive = false
    /// Когда человек последний раз сходил или отменил ход. Второе касание двойного тапа
    /// не должно стать ещё одним действием: под пальцем уже другая кнопка или карта.
    private var lastHumanActionAt = Date.distantPast
    /// Столько секунд после своего хода или отмены новое касание не считается действием.
    private static let repeatTapGuard: TimeInterval = 0.4

    init() {
        let options = LaunchOptions.current
        let storage = Storage(space: options.isDemo ? .demo : .user)
        self.options = options
        self.autoplay = options.autoplay
        self.storage = storage
        settings = options.isDemo ? options.demoSettings() : storage.loadSettings()
        stats = storage.loadStats()
        // Экраны для скриншотов — с постоянным зерном, чтобы кадры повторялись; автоигра — каждый раз своя.
        let fixedDemoSeed: UInt64? = options.screen != nil && !options.autoplay ? 20_260_927 : nil
        let seed = options.seed ?? fixedDemoSeed ?? UInt64.random(in: 0...UInt64.max)
        launchSeed = seed
        rng = SplitMix64(seed: seed)
        requestedScreen = options.screenName
        sounds.soundEnabled = settings.soundEnabled && !autoplay
        sounds.hapticsEnabled = settings.hapticsEnabled && !autoplay

        if options.isDemo {
            startDemo()
        } else {
            restoreSavedGame()
        }
    }

    // MARK: - Свойства для экранов

    /// Пауза: открыт лист/диалог или приложение не на экране.
    var isPaused: Bool {
        isOverlayPresented || (!isSceneActive && !autoplay)
    }

    var canContinue: Bool {
        guard let match else { return false }
        return !match.isOver
    }

    var isHumanTurn: Bool {
        guard isInGame, let match, match.actor == humanSeat else { return false }
        return displayedTrick == nil && !showDealSummary
    }

    /// Карты, которыми человек может сходить сейчас.
    var legalCards: Set<Card> {
        guard isHumanTurn, let deal = match?.deal, deal.phase == .playing else { return [] }
        return Set(deal.legalCards(for: humanSeat))
    }

    /// Карты, которые можно бросить на стол прямо сейчас: в свой ход — допустимые;
    /// взятка ещё лежит на столе, а заходить вам — любые (взятка соберётся сама).
    var throwableCards: Set<Card> {
        if isHumanTurn { return legalCards }
        guard isInGame, !showDealSummary, displayedTrick != nil, let match, match.actor == humanSeat,
              let deal = match.deal, deal.phase == .playing else { return [] }
        return Set(deal.legalCards(for: humanSeat))
    }

    /// Можно отменить своё последнее действие: только в идущей сдаче.
    var canUndo: Bool {
        guard !autoplay, isInGame, !undoStack.isEmpty, let match, !match.isOver,
              let deal = match.deal, !deal.isFinished else { return false }
        return true
    }

    /// Последняя собранная взятка текущей сдачи.
    var lastTrick: Trick? {
        match?.deal?.tricks.last
    }

    /// Текст совета для панели торговли и обмена семёрки (nil — совета нет).
    var bidHint: String? {
        guard let hintAction else { return nil }
        if case .play = hintAction { return nil }
        return GameFlow.hintText(hintAction, deal: match?.deal)
    }

    /// Персонаж на месте (nil — человек или место пустое).
    func persona(for seat: Int) -> Persona? {
        guard seat != humanSeat else { return nil }
        let index = seat < humanSeat ? seat : seat - 1
        return opponents.indices.contains(index) ? opponents[index] : nil
    }

    /// «Вы» для человека, имя персонажа для соперника.
    func displayName(for seat: Int) -> String {
        if seat == humanSeat { return "Вы" }
        if let persona = persona(for: seat) { return persona.name }
        if let names = match?.names, names.indices.contains(seat) { return names[seat] }
        return "Игрок \(seat + 1)"
    }

    // MARK: - Управление партией

    /// Новая партия по настройкам: число игроков, соперники, правила.
    func newGame() {
        setUpNewMatch(playerCount: settings.playerCount, rules: settings.rules,
                      opponents: chosenOpponents(count: settings.playerCount - 1))
        isInGame = true
        sounds.prepare()
        startNextDeal()
    }

    /// Новая партия с теми же соперниками и правилами.
    func rematch() {
        guard let old = match else {
            newGame()
            return
        }
        let count = old.playerCount - 1
        let same = opponents.count == count
            ? opponents
            : GameFlow.opponents(ids: opponents.map(\.id), count: count, fallback: settings.difficulty)
        setUpNewMatch(playerCount: old.playerCount, rules: old.rules, opponents: same)
        isInGame = true
        sounds.prepare()
        startNextDeal()
    }

    func continueGame() {
        guard let match else { return }
        driver?.cancel()
        resetTransient()
        clearBanners()
        bubbles = GameFlow.bubbles(for: match.deal, phrase: phrase(for:))
        isInGame = true
        sounds.prepare()
        noteActivity()
        persist()
        if match.deal == nil {
            startNextDeal()
            return
        }
        drive()
    }

    func leaveGame() {
        isInGame = false
    }

    func startNextDeal() {
        guard var current = match, current.needsNewDeal else { return }
        driver?.cancel()
        showDealSummary = false
        resetTransient()
        clearBanners()
        undoStack.removeAll()
        let events = current.startNextDeal()
        withAnimation(animation(.easeInOut(duration: 0.35))) {
            match = current
            process(events)
        }
        // Пока карты разлетаются по рукам, первый торгующийся компьютер не говорит.
        hold(.milliseconds(Int(settings.speed.cardFlight * 1000) + 600))
        sounds.play(.deal)
        noteActivity()
        persist()
        reportProgress()
        drive()
    }

    // MARK: - Действия человека

    /// Действие человека: торговля, обмен семёрки или ход картой.
    /// `byUser == false` — автоход: второе касание двойного тапа тут ни при чём.
    func perform(_ action: Action, byUser: Bool = true) {
        guard isHumanTurn, var current = match else { return }
        // Второе касание двойного тапа попадает в новую кнопку на том же месте («Беру» → «Взять … за 7»)
        // или в карту после сбора взятки — такой «ход» отбрасываем.
        guard !byUser || !isRepeatTap else { return }
        let before = current
        do {
            let events = try current.apply(action)
            lastHumanActionAt = Date()
            cancelHint()
            lastStepWasBot = false
            if !autoplay {
                // Отменить можно только последнее своё решение — один шаг назад.
                // Автоход (вынужденная карта) решением не считается: его не отменить.
                undoStack = byUser ? [before] : []
            }
            withAnimation(animation(.spring(response: 0.35, dampingFraction: 0.82))) {
                selectedCard = nil
                hintAction = nil
                match = current
                process(events)
            }
            if case .play = action { sounds.haptic(.tap) }
            noteActivity()
            persist()
            reportProgress()
            drive()
        } catch {
            if case .play(let card) = action, let deal = current.deal {
                rejectCard(card, in: deal)
            } else {
                showBanner("Так сейчас нельзя", urgent: true)
                sounds.play(.error)
                sounds.haptic(.warning)
            }
        }
    }

    /// Касание карты на руке: с двойным касанием первое выбирает, второе ходит.
    /// Пока на столе лежит собранная взятка, касание сразу её убирает.
    func tapCard(_ card: Card) {
        if displayedTrick != nil { collectTrick() }
        guard isHumanTurn, let deal = match?.deal, deal.phase == .playing else { return }
        noteActivity()
        guard deal.legalCards(for: humanSeat).contains(card) else {
            rejectCard(card, in: deal)
            return
        }
        if settings.confirmCardTap && selectedCard != card {
            withAnimation(animation(.easeOut(duration: 0.15))) { selectedCard = card }
            sounds.haptic(.select)
            return
        }
        perform(.play(card))
    }

    /// Лёгкий отклик: карту взяли рассмотреть.
    func feelCardPreview() {
        sounds.haptic(.select)
    }

    /// Бросок карты на стол (и действие VoiceOver «Сходить»): лежащая взятка сначала соберётся сама.
    /// true — карта ушла на стол.
    @discardableResult
    func throwCard(_ card: Card) -> Bool {
        if displayedTrick != nil { collectTrick() }
        guard isHumanTurn, legalCards.contains(card) else { return false }
        perform(.play(card))
        return !(match?.deal?.hands[humanSeat].contains(card) ?? true)
    }

    /// Выбор карты ведением пальца по руке (nil — снять выбор). Недопустимую карту не поднимает.
    func selectCard(_ card: Card?) {
        guard let card else {
            if selectedCard != nil {
                withAnimation(animation(.easeOut(duration: 0.15))) { selectedCard = nil }
            }
            return
        }
        guard isHumanTurn, selectedCard != card else { return }
        noteActivity()
        withAnimation(animation(.easeOut(duration: 0.15))) {
            selectedCard = legalCards.contains(card) ? card : nil
        }
        if selectedCard == card { sounds.haptic(.select) }
    }

    /// Убрать собранную взятку со стола сразу, не дожидаясь паузы.
    func collectTrick() {
        guard displayedTrick != nil else { return }
        gatherTrick()
        noteActivity()
        drive()
    }

    /// Совет Мастера для текущего решения: торговля, обмен семёрки или ход.
    /// В одной и той же позиции — всегда один и тот же.
    func showHint() {
        guard isHumanTurn, let snapshot = match else { return }
        noteActivity()
        if let cached = hintCache, cached.match == snapshot {
            presentHint(cached.action)
            return
        }
        guard hintTask == nil else { return }
        hintToken &+= 1
        let token = hintToken
        let seat = humanSeat
        isHinting = true
        hintTask = Task { [weak self] in
            let action = await Task.detached(priority: .userInitiated) { () -> Action? in
                Bot.hint(match: snapshot, seat: seat)
            }.value
            guard let self, token == self.hintToken else { return }
            self.hintTask = nil
            self.isHinting = false
            guard !Task.isCancelled, self.match == snapshot, let action else { return }
            self.hintCache = (snapshot, action)
            self.hintsUsed += 1
            self.presentHint(action)
            self.persist()
        }
    }

    /// Отменить своё последнее действие — один шаг назад, до конца сдачи; второй раз подряд нельзя.
    /// Соперники потом могут сыграть иначе.
    func undo() {
        // Двойное касание «Отменить» не должно отменять два хода (и сразу отменять только что сделанный).
        guard canUndo, !isRepeatTap, let previous = undoStack.popLast() else { return }
        lastHumanActionAt = Date()
        driver?.cancel()
        resetTransient()
        clearBanners()
        undosUsed += 1
        withAnimation(animation(.easeInOut(duration: 0.3))) {
            match = previous
            bubbles = GameFlow.bubbles(for: previous.deal, phrase: phrase(for:))
        }
        sounds.play(.collect)
        sounds.haptic(.soft)
        showBanner("Ход отменён", urgent: true)
        noteActivity()
        persist()
        reportProgress()
        drive()
    }

    /// Касание пришло сразу после своего хода или отмены — это второе касание двойного тапа.
    private var isRepeatTap: Bool {
        Date().timeIntervalSince(lastHumanActionAt) < Self.repeatTapGuard
    }

    // MARK: - Сообщения

    func showBanner(_ text: String) {
        showBanner(text, urgent: false)
    }

    /// Срочное сообщение (ошибка хода, совет) показывается сразу, не дожидаясь очереди.
    /// `long` — подсказка в целое предложение: держится дольше.
    func showBanner(_ text: String, urgent: Bool, long: Bool = false) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if urgent {
            let current = banner.map { BannerQueue.Item(text: $0, urgent: bannerIsUrgent) }
            bannerQueue.pushUrgent(text, current: current, shownFor: Date().timeIntervalSince(bannerShownAt),
                                   long: long)
            pumpBanners()
        } else if bannerQueue.pushInfo(text, current: banner), bannerTask == nil {
            pumpBanners()
        }
    }

    /// Объявление в центре стола на `duration` — по очереди с остальными; компьютер ждёт, пока все
    /// объявления не покажут (пауза игры время не съедает).
    private func announce(_ kind: TableAnnouncement.Kind, for duration: Duration) {
        let duration = unattended ? .milliseconds(400) : duration
        let now = ContinuousClock.now
        announcementsBusyUntil = max(announcementsBusyUntil, now) + duration + .milliseconds(250)
        hold(announcementsBusyUntil - now)
        announcementQueue.append((kind, duration))
        guard announcementTask == nil else { return }
        announcementRun &+= 1
        let run = announcementRun
        announcementTask = Task { [weak self] in
            await self?.runAnnouncements(run)
        }
    }

    private func runAnnouncements(_ run: Int) async {
        while !Task.isCancelled, run == announcementRun, !announcementQueue.isEmpty {
            let next = announcementQueue.removeFirst()
            announcementSerial &+= 1
            let item = TableAnnouncement(id: announcementSerial, kind: next.kind)
            withAnimation(animation(.spring(response: 0.42, dampingFraction: 0.7))) { announcement = item }
            guard await visibleSleep(next.duration), run == announcementRun, announcement?.id == item.id else { break }
            withAnimation(.easeOut(duration: 0.3)) { announcement = nil }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if run == announcementRun { announcementTask = nil }
    }

    private func clearAnnouncement() {
        announcementRun &+= 1
        announcementTask?.cancel()
        announcementTask = nil
        announcementQueue.removeAll()
        announcementsBusyUntil = .now
        announcement = nil
    }

    /// VoiceOver проговаривает событие, у которого вместо строки внизу — «печать» в центре.
    private func speak(_ event: DealEvent, in match: Match) {
        guard UIAccessibility.isVoiceOverRunning,
              let text = Narrator.message(for: event, in: match, humanSeat: humanSeat) else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// Главное сообщение сдачи (козырь, обмен семёрки): в очереди, но держится полное время.
    private func showImportantBanner(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if bannerQueue.pushInfo(text, current: banner, important: true), bannerTask == nil {
            pumpBanners()
        }
    }

    // MARK: - Приложение

    /// Приложение на экране (сцена активна) или нет: не на экране — пауза и сохранение.
    func setScenePhaseActive(_ active: Bool) {
        guard active != isSceneActive else { return }
        isSceneActive = active
        if active {
            sounds.resume()
            noteActivity()
        } else {
            persist()
            storage.flush()
        }
        pauseDidChange()
    }

    /// Стереть статистику.
    func resetStats() {
        var fresh = PlayerStats()
        // Доигранная партия остаётся в сохранении — без метки её снова запишут при запуске (adopt).
        fresh.lastRecordedMatch = stats.lastRecordedMatch
        stats = fresh
        storage.saveStats(fresh)
    }

    // MARK: - Ход партии

    private func drive() {
        driver?.cancel()
        driver = Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            guard isInGame, await waitWhilePaused() else { return }
            let step = GameFlow.nextStep(match: match, displayedTrick: displayedTrick,
                                         showingSummary: showDealSummary, humanSeat: humanSeat,
                                         autoplay: autoplay)
            switch step {
            case .idle:
                thinkingSeat = nil
                return

            case .startDeal:
                startNextDeal()
                return

            case .collectTrick:
                thinkingSeat = nil
                guard await visibleSleep(settings.speed.trickPause) else { return }
                gatherTrick()

            case .redeal:
                thinkingSeat = nil
                if autoplay, let match { traceDeal(match) }
                guard await visibleSleep(settings.speed.bannerTime) else { return }
                startNextDeal()
                return

            case .showSummary:
                thinkingSeat = nil
                guard await visibleSleep(.milliseconds(450)) else { return }
                presentSummary()
                await advanceAutoplayIfNeeded()
                return

            case .waitSummary:
                thinkingSeat = nil
                await advanceAutoplayIfNeeded()
                return

            case .waitHuman:
                thinkingSeat = nil
                if lastStepWasBot { sounds.haptic(.turn) }
                lastStepWasBot = false
                if let card = autoMoveCard() {
                    await autoMove(card)
                    return
                }
                showPlayTipIfNeeded()
                if options.scriptedHuman && options.isDemo {
                    await scriptedHumanMove()
                }
                return

            case .botMove(let seat):
                guard await botMove(seat) else { return }
                lastStepWasBot = true
            }
        }
    }

    /// Ход компьютера: считает в фоне, «думает» по трудности решения, затем ходит.
    /// false — цикл нужно остановить.
    private func botMove(_ seat: Int) async -> Bool {
        // Сначала — пауза после важного события (козырь, обмен семёрки): соперник «смотрит» вместе со всеми.
        if let until = holdUntil {
            holdUntil = nil
            let now = ContinuousClock.now
            if until > now {
                thinkingSeat = nil
                guard await visibleSleep(until - now) else { return false }
            }
        }
        guard let snapshot = match else { return false }
        thinkingSeat = seat == humanSeat ? nil : seat
        let bot = makeBot(for: seat)
        let seed = rng.next()
        let jitter = 0.85 + 0.3 * Double(rng.next() % 1000) / 1000
        let clock = ContinuousClock()
        let started = clock.now
        let decision = await Task.detached(priority: .userInitiated) { () -> (Action, Double) in
            var local = SplitMix64(seed: seed)
            let action = bot.chooseAction(match: snapshot, seat: seat, rng: &local)
            return (action, Bot.decisionWeight(match: snapshot, seat: seat))
        }.value
        if Task.isCancelled { return false }

        var target = ThinkingTime.delay(base: settings.speed.botDelay, weight: decision.1, jitter: jitter)
        if autoplay, seat == humanSeat, let delay = options.humanDelay { target = max(target, delay) }
        let elapsed = started.duration(to: clock.now)
        if target > elapsed {
            guard await visibleSleep(target - elapsed) else { return false }
        }
        guard await waitWhilePaused() else { return false }
        // Пока думали, партия могла измениться (отмена хода, новая партия) — решаем заново.
        guard var current = match, current == snapshot else { return true }

        do {
            let events = try current.apply(decision.0)
            commitBotMove(current, events)
            return true
        } catch {
            Diagnostics.log("Компьютер (место \(seat)) сделал недопустимый ход \(decision.0): \(error)")
            if autoplay {
                Diagnostics.trace("ERROR bot seat=\(seat) action=\(decision.0): \(error)")
                reportProgress(phase: "error")
                fatalError("Автоигра: недопустимый ход компьютера \(decision.0): \(error)")
            }
            var retry = snapshot
            if let fallback = snapshot.deal?.legalActions().first, let events = try? retry.apply(fallback) {
                commitBotMove(retry, events)
                return true
            }
            thinkingSeat = nil
            showBanner("Компьютер не смог сходить. Выйдите в меню и продолжите партию", urgent: true)
            return false
        }
    }

    // MARK: - Автоход

    /// Карта, которая ходит за человека сама (настройка «Автоход»), — nil, если ждём его.
    private func autoMoveCard() -> Card? {
        guard !autoplay, isHumanTurn, let deal = match?.deal, deal.phase == .playing else { return nil }
        return settings.autoPlay.card(hand: deal.hands[humanSeat], legal: deal.legalCards(for: humanSeat))
    }

    /// Автоход: карта приподнимается, чтобы было видно, чем ходим, и через мгновение уходит на стол.
    /// Коснуться карты можно и раньше — тогда ход сделает касание.
    private func autoMove(_ card: Card) async {
        withAnimation(animation(.easeOut(duration: 0.2))) { selectedCard = card }
        guard await visibleSleep(settings.speed.botDelay * 0.8) else { return }
        guard !Task.isCancelled, autoMoveCard() == card else { return }
        perform(.play(card), byUser: false)
    }

    /// `-DebercScriptedHuman`: за человека решает компьютер, но ходит теми же действиями, что и касания.
    private func scriptedHumanMove() async {
        guard let snapshot = match else { return }
        guard await visibleSleep(options.humanDelay ?? .milliseconds(2500)) else { return }
        guard !Task.isCancelled, isHumanTurn, match == snapshot else { return }
        var local = SplitMix64(seed: rng.next())
        let action = Bot(level: .expert).chooseAction(match: snapshot, seat: humanSeat, rng: &local)
        if case .play(let card) = action {
            withAnimation(animation(.easeOut(duration: 0.15))) { selectedCard = card }
            guard await visibleSleep(.milliseconds(500)), isHumanTurn, match == snapshot else { return }
        }
        perform(action, byUser: false)
    }

    /// Первый свой ход в розыгрыше — одна подсказка, как ходить картой.
    private func showPlayTipIfNeeded() {
        guard !autoplay, !settings.hasSeenPlayTip, isHumanTurn, match?.deal?.phase == .playing else { return }
        settings.hasSeenPlayTip = true
        showBanner(settings.confirmCardTap
                   ? "Чтобы сходить, коснитесь карты дважды или бросьте её пальцем вверх, к центру стола"
                   : "Чтобы сходить, коснитесь карты или бросьте её пальцем вверх, к центру стола",
                   urgent: true, long: true)
    }

    private func commitBotMove(_ updated: Match, _ events: [DealEvent]) {
        thinkingSeat = nil
        withAnimation(animation(.easeInOut(duration: 0.3))) {
            hintAction = nil
            match = updated
            process(events)
        }
        noteActivity()
        persist()
        reportProgress()
    }

    private func makeBot(for seat: Int) -> Bot {
        if let persona = persona(for: seat) { return Bot(persona: persona) }
        return Bot(level: options.level ?? settings.difficulty)
    }

    private func gatherTrick() {
        guard displayedTrick != nil else { return }
        withAnimation(animation(.easeInOut(duration: 0.35))) { displayedTrick = nil }
        sounds.play(.collect)
        // Взятка улетает в стопку — следующий заход не раньше, чем стол опустеет.
        hold(.milliseconds(Int(settings.speed.cardFlight * 1000) + 150))
    }

    /// Автоигра для проверки (CI): смотреть некому — паузы и объявления не нужны.
    /// С `-DebercHumanDelay` (съёмка) всё как у человека.
    private var unattended: Bool { autoplay && options.humanDelay == nil }

    /// Компьютер не ходит раньше чем через `pause` (если уже ждёт дольше — не сокращать).
    private func hold(_ pause: Duration) {
        guard !unattended else { return }
        let until = ContinuousClock.now + pause
        if let current = holdUntil, current > until { return }
        holdUntil = until
    }

    private func presentSummary() {
        guard let match else { return }
        clearBanners()
        withAnimation(animation(.easeInOut(duration: 0.3))) { showDealSummary = true }
        let live = dealEndedLive
        dealEndedLive = false
        if match.isOver {
            recordStatsIfNeeded()
            if live {
                let won = match.winner == humanSeat
                sounds.play(won ? .win : .lose)
                sounds.haptic(won ? .success : .warning)
            }
        } else if live, let last = match.history.last, last.bidder == humanSeat {
            switch last.outcome {
            case .made: sounds.haptic(.success)
            case .bait, .hanging: sounds.haptic(.warning)
            default: break
            }
        }
        if autoplay { traceDeal(match) }
        reportProgress()
    }

    /// Автоигра: подержать итоги и идти дальше (кроме съёмки экранов итогов и конца партии).
    private func advanceAutoplayIfNeeded() async {
        guard autoplay, options.screen != .summary, options.screen != .gameover else { return }
        // Обычный сон, не «видимый»: итоги не должны залипнуть, если экран что-то накрыл.
        try? await Task.sleep(for: .milliseconds(2500))
        guard !Task.isCancelled, let match, isInGame else { return }
        if match.isOver {
            autoplayMatches += 1
            rematch()
        } else if match.needsNewDeal {
            startNextDeal()
        }
    }

    // MARK: - События сдачи

    private func process(_ events: [DealEvent]) {
        guard let current = match else { return }
        if let pause = GameFlow.pause(after: events, speed: settings.speed, humanSeat: humanSeat) {
            hold(pause)
        }
        for event in events {
            var urgent = false
            var important = false
            switch event {
            case .bid(let bid):
                bubbles[bid.seat] = phrase(for: bid)
            case .trumpChosen(let seat, let suit, let forced):
                // Вместо строки внизу — крупная «печать» с мастью в центре стола.
                announce(.trump(seat: seat, suit: suit, forced: forced), for: settings.speed.announcePause * 0.85)
                speak(event, in: current)
                continue
            case .playStarted(let decl):
                // Комбинации — «печатью» с самими картами: у кого и сколько записано.
                if let winner = decl.meldWinner, decl.melds.indices.contains(winner), !decl.melds[winner].isEmpty {
                    let others = decl.melds.enumerated().contains { $0.offset != winner && !$0.element.isEmpty }
                    // Свои комбинации человек и так видит — их «печать» короче.
                    announce(.melds(seat: winner, melds: decl.melds[winner],
                                    points: decl.meldPoints(for: winner, rules: current.rules), senior: others),
                             for: settings.speed.announcePause * (winner == humanSeat ? 0.7 : 0.9))
                    speak(event, in: current)
                    continue
                }
            case .sevenExchanged:
                important = true
            case .prikupDealt:
                sounds.play(.deal)
            case .cardPlayed:
                // Реплики торговли («Беру ♦», «Пас») видны до первой карты розыгрыша.
                if !bubbles.isEmpty { bubbles = [:] }
                sounds.play(.card)
            case .bella(let seat):
                urgent = true
                sounds.play(.bella)
                if seat == humanSeat { sounds.haptic(.soft) }
            case .trickCompleted(let trick):
                displayedTrick = trick
                if trick.winner == humanSeat && !autoplay { sounds.haptic(.soft) }
            case .allPassed, .fourSevens:
                bubbles = [:]
            case .dealFinished:
                dealEndedLive = true
                autoplayDeals += 1
                // Сразу, а не только при показе итогов: из-за выхода в меню до итогов партия
                // иначе могла не попасть в статистику (повторная запись PlayerStats не засчитает).
                if current.isOver { recordStatsIfNeeded() }
            default:
                break
            }
            // `current` — партия уже после хода: при пересдаче сообщение предупредит о сдаче на обязах.
            if let text = Narrator.message(for: event, in: current, humanSeat: humanSeat) {
                if important && !urgent {
                    showImportantBanner(text)
                } else {
                    showBanner(text, urgent: urgent)
                }
            }
        }
    }

    /// Реплика при торговле: у соперника — в его характере. Меняется от сдачи к сдаче,
    /// а в пределах сдачи одна и та же (после «Продолжить» и отмены хода реплики те же).
    private func phrase(for bid: Bid) -> String {
        if let persona = persona(for: bid.seat) {
            return persona.phrase(for: bid, variant: match?.dealCount ?? 0)
        }
        return Narrator.bidText(bid)
    }

    private func presentHint(_ action: Action) {
        withAnimation(animation(.easeOut(duration: 0.2))) {
            hintAction = action
            if case .play(let card) = action { selectedCard = card }
        }
        showBanner(GameFlow.hintText(action, deal: match?.deal), urgent: true)
        sounds.haptic(.select)
    }

    private func rejectCard(_ card: Card, in deal: Deal) {
        let reason = Narrator.illegalCardReason(deal: deal, seat: humanSeat, card: card)
        showBanner(reason.isEmpty ? "Так сейчас нельзя" : reason, urgent: true)
        sounds.play(.error)
        sounds.haptic(.warning)
    }

    // MARK: - Пауза

    private func pauseDidChange() {
        if isPaused { pauseEpoch &+= 1 }
        updateIdleTimer()
    }

    /// Ждёт, пока игра на паузе. false — задачу отменили.
    private func waitWhilePaused() async -> Bool {
        while isPaused {
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return false }
        }
        return !Task.isCancelled
    }

    /// Пауза «на виду»: если за это время игру ставили на паузу (лист, звонок, фон),
    /// после возврата выдерживается заново целиком — взятку и сообщение успеют увидеть.
    private func visibleSleep(_ duration: Duration) async -> Bool {
        while true {
            guard await waitWhilePaused() else { return false }
            let epoch = pauseEpoch
            try? await Task.sleep(for: duration)
            if Task.isCancelled { return false }
            if !isPaused && pauseEpoch == epoch { return true }
        }
    }

    // MARK: - Очередь сообщений

    private func pumpBanners() {
        bannerGeneration &+= 1
        let generation = bannerGeneration
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            await self?.runBanners(generation)
        }
    }

    private func runBanners(_ generation: Int) async {
        while !Task.isCancelled && generation == bannerGeneration {
            guard await waitWhilePaused(), generation == bannerGeneration else { return }
            guard let item = bannerQueue.pop() else {
                withAnimation(.easeInOut(duration: 0.25)) { banner = nil }
                bannerIsUrgent = false
                bannerTask = nil
                return
            }
            let hold = bannerQueue.hold(for: item, base: settings.speed.bannerTime)
            withAnimation(.easeInOut(duration: 0.25)) { banner = item.text }
            bannerIsUrgent = item.urgent
            bannerShownAt = Date()
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: item.text)
            }
            guard await visibleSleep(hold), generation == bannerGeneration else { return }
        }
    }

    private func clearBanners() {
        bannerGeneration &+= 1
        bannerTask?.cancel()
        bannerTask = nil
        bannerQueue.removeAll()
        banner = nil
        bannerIsUrgent = false
    }

    // MARK: - Внутреннее

    private func chosenOpponents(count: Int) -> [Persona] {
        GameFlow.opponents(ids: settings.opponentIDs, count: count, fallback: settings.difficulty)
    }

    /// Новая партия без раздачи.
    private func setUpNewMatch(playerCount: Int, rules: RuleSet, opponents chosen: [Persona]) {
        driver?.cancel()
        cancelHint()
        opponents = chosen
        let names = [GameFlow.humanName(settings.playerName)] + chosen.map(\.name)
        match = Match(playerCount: playerCount, names: names, rules: rules, seed: rng.next())
        gameID = UUID()
        startedAt = Date()
        hintsUsed = 0
        undosUsed = 0
        hintCache = nil
        undoStack.removeAll()
        resetTransient()
        clearBanners()
        showDealSummary = false
        loadProblem = nil
    }

    private func resetTransient() {
        dealEndedLive = false
        lastStepWasBot = false
        holdUntil = nil
        clearAnnouncement()
        bubbles = [:]
        displayedTrick = nil
        thinkingSeat = nil
        selectedCard = nil
        hintAction = nil
        cancelHint()
    }

    private func cancelHint() {
        hintToken &+= 1
        hintTask?.cancel()
        hintTask = nil
        isHinting = false
    }

    private func inGameDidChange() {
        if !isInGame {
            driver?.cancel()
            driver = nil
            cancelHint()
            thinkingSeat = nil
            showDealSummary = false
            displayedTrick = nil
            selectedCard = nil
            hintAction = nil
            clearBanners()
            clearAnnouncement()
            // Экран, который поставил паузу, уже закрыт.
            isOverlayPresented = false
        }
        persist()
        updateIdleTimer()
    }

    private func settingsDidChange(from old: AppSettings) {
        guard !normalizingSettings else { return }
        normalizingSettings = true
        let fixed = settings.normalized(from: old)
        if fixed != settings { settings = fixed }
        normalizingSettings = false

        sounds.soundEnabled = settings.soundEnabled && !autoplay
        sounds.hapticsEnabled = settings.hapticsEnabled && !autoplay
        if settings.soundEnabled && !old.soundEnabled { sounds.play(.card) }
        if settings.hapticsEnabled && !old.hapticsEnabled { sounds.haptic(.tap) }
        if settings != old { storage.saveSettings(settings) }
    }

    private func restoreSavedGame() {
        switch storage.loadGame() {
        case .none:
            break
        case .loaded(let game):
            markReturningPlayer()
            adopt(game)
            if game.inGame { continueGame() }
        case .legacy(let old):
            markReturningPlayer()
            adopt(SavedGame.migrating(old, settings: settings))
            persist()
        case .unreadable:
            markReturningPlayer()
            loadProblem = "Сохранённую партию открыть не удалось. Копия файла осталась на устройстве — начните новую партию."
        }
    }

    /// Партия уже была, значит приложение открывали раньше: приветствие не показывать
    /// (старые сборки не сохраняли неизменённые настройки, и его флаг мог потеряться).
    private func markReturningPlayer() {
        if !settings.hasSeenOnboarding { settings.hasSeenOnboarding = true }
    }

    private func adopt(_ game: SavedGame) {
        var restored = game.match
        let chosen = GameFlow.opponents(ids: game.opponentIDs, count: restored.playerCount - 1,
                                        fallback: settings.difficulty)
        GameFlow.syncNames(&restored, opponents: chosen)
        opponents = chosen
        match = restored
        gameID = game.id
        startedAt = game.startedAt
        hintsUsed = game.hintsUsed
        undosUsed = game.undosUsed
        if restored.isOver { recordStatsIfNeeded() }
    }

    private func persist() {
        guard let match else { return }
        var game = SavedGame(match: match, opponentIDs: opponents.map(\.id))
        game.id = gameID
        game.startedAt = startedAt
        game.hintsUsed = hintsUsed
        game.undosUsed = undosUsed
        game.inGame = isInGame
        storage.saveGame(game)
    }

    /// Записать доигранную партию в статистику — один раз (повтор PlayerStats не засчитает).
    private func recordStatsIfNeeded() {
        guard let match, match.isOver else { return }
        var updated = stats
        updated.record(match: match, humanSeat: humanSeat, personaIDs: opponents.map(\.id),
                       levelKey: GameFlow.levelKey(for: opponents))
        if updated != stats {
            stats = updated
            storage.saveStats(updated)
        }
    }

    // MARK: - Экран не гаснет

    private func noteActivity() {
        lastActivity = Date()
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        let idleFor = Date().timeIntervalSince(lastActivity)
        let keepAwake = IdlePolicy.keepAwake(inGame: isInGame, sceneActive: isSceneActive,
                                             matchOver: match?.isOver ?? true, showingSummary: showDealSummary,
                                             idleFor: idleFor, autoplay: autoplay)
        if UIApplication.shared.isIdleTimerDisabled != keepAwake {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        idleTask?.cancel()
        idleTask = nil
        guard keepAwake, !autoplay else { return }
        let limit = IdlePolicy.idleLimit(matchOver: match?.isOver ?? true, showingSummary: showDealSummary)
        let remaining = max(1, limit - idleFor)
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.updateIdleTimer()
        }
    }

    private func animation(_ base: Animation) -> Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeInOut(duration: 0.2) : base
    }

    // MARK: - Демо-режим (CI, скриншоты)

    private enum DemoGoal {
        /// Итог первой сыгранной сдачи.
        case summary
        /// Конец партии.
        case gameover
        /// Несколько сдач в записи, на столе — новая сдача.
        case scoresheet
        /// Идущая партия в меню («Продолжить»).
        case menu
    }

    private func startDemo() {
        if autoplay {
            let level = options.level ?? settings.difficulty
            Diagnostics.trace("start players=\(settings.playerCount) level=\(level.rawValue) seed=\(launchSeed) screen=\(options.screenName ?? "-")")
        }
        switch options.screen {
        case .none, .table?, .persona?:
            newGame()
        case .summary?:
            runDemo(.summary)
        case .gameover?:
            runDemo(.gameover)
        case .scoresheet?:
            runDemo(.scoresheet)
        case .stats?:
            runDemoStats()
            runDemo(.menu)
        case .menu?, .settings?, .rules?, .onboarding?, .opponents?:
            runDemo(.menu)
        }
    }

    private func runDemo(_ goal: DemoGoal) {
        setUpNewMatch(playerCount: settings.playerCount, rules: settings.rules,
                      opponents: chosenOpponents(count: settings.playerCount - 1))
        guard let start = match else { return }
        let seed = rng.next()
        let stop: (Match) -> Bool
        switch goal {
        case .summary:
            stop = { DemoSimulator.dealJustScored($0) }
        case .gameover:
            stop = { _ in false }
        case .scoresheet:
            stop = { $0.needsNewDeal && $0.history.filter { $0.outcome != .allPassed }.count >= 4 }
        case .menu:
            stop = { $0.needsNewDeal && $0.history.filter { $0.outcome != .allPassed }.count >= 3 }
        }
        // Компьютеры-«новички» играют мгновенно: вся партия — доли секунды, поэтому прямо здесь,
        // чтобы экраны сразу увидели нужное состояние.
        finishDemo(goal, DemoSimulator.play(start, level: .novice, seed: seed, stop: stop))
    }

    private func finishDemo(_ goal: DemoGoal, _ played: Match) {
        var result = played
        autoplayDeals += result.history.count
        if goal == .scoresheet || goal == .menu, result.needsNewDeal {
            result.startNextDeal()
        }
        match = result
        switch goal {
        case .summary, .gameover:
            isInGame = true
            drive()
        case .scoresheet:
            continueGame()
        case .menu:
            persist()
        }
        reportProgress()
    }

    /// Статистика для экрана «Статистика»: несколько быстрых партий компьютеров.
    private func runDemoStats() {
        var demo = PlayerStats()
        var seeds = SplitMix64(seed: rng.next())
        let count = settings.playerCount
        let cast = Persona.all
        for game in 0..<6 {
            let rivals = (0..<(count - 1)).map { cast[(game * (count - 1) + $0) % cast.count] }
            let start = Match(playerCount: count, names: [GameFlow.humanName(settings.playerName)] + rivals.map(\.name),
                              rules: settings.rules, seed: seeds.next())
            let done = DemoSimulator.play(start, level: .novice, seed: seeds.next()) { _ in false }
            demo.record(match: done, humanSeat: humanSeat, personaIDs: rivals.map(\.id),
                        levelKey: GameFlow.levelKey(for: rivals))
        }
        stats = demo
        storage.saveStats(demo)
    }

    private func reportProgress(phase: String? = nil) {
        guard options.isDemo else { return }
        let name = phase ?? GameFlow.phaseName(match: match, showingSummary: showDealSummary, inGame: isInGame)
        storage.writeProgress(deals: autoplayDeals, matches: autoplayMatches, phase: name)
    }

    private func traceDeal(_ match: Match) {
        guard let last = match.history.last else { return }
        let totals = match.totals.map(String.init).joined(separator: ":")
        Diagnostics.trace("deal=\(match.history.count) outcome=\(last.outcome.rawValue) totals=\(totals)")
        if match.isOver, let winner = match.winner {
            Diagnostics.trace("match-over winner=\(displayName(for: winner)) totals=\(totals)")
        }
    }
}
