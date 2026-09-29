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
    /// Подначка соперника в облачке у его места — сама гаснет через пару секунд.
    @Published private(set) var taunt: TableTaunt?
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
    /// Снимок до последнего своего решения — вместе с генератором случайностей соперников:
    /// после отмены на ту же карту они ответят так же.
    @Published private var undoStack: [(match: Match, rng: SplitMix64)] = []
    /// Когда кнопка «Отменить» пропала (соперник ответил): касание в её место в ближайшие полсекунды
    /// не должно нажать лампочку, которая встала туда же.
    private var undoClearedAt = Date.distantPast
    /// Палец на руке (касание идёт) и касался ли человек руки в этот свой ход.
    private var handTouchActive = false
    private var handTouchedThisTurn = false
    /// Какой это ход человека (сдача, взятка, карта во взятке) — чтобы понять, что начался новый.
    private var humanTurnKey: [Int] = []
    /// Когда подсказывали «сейчас ходит…» на касание карты не в свой ход.
    private var lastNotYourTurnAt = Date.distantPast

    // MARK: - Внутреннее состояние

    private let options: LaunchOptions
    /// Автоигра (только по аргументу `-DebercAutoplay YES`): за человека тоже играет компьютер.
    private let autoplay: Bool
    private let storage: Storage
    private let sounds = SoundPlayer()
    private var rng: SplitMix64
    /// Случайность подначек — отдельная, чтобы не менять ходы компьютеров при том же зерне.
    private var banterRng: SplitMix64
    private var tauntTask: Task<Void, Never>?
    private var tauntSerial = 0
    private var lastTauntAt = Date.distantPast
    /// Недавние реплики — чтобы не повторяться.
    private var recentTaunts: [String] = []
    /// Ждём, не задумался ли человек надолго (подначка «долго думаете»).
    private var longThinkTask: Task<Void, Never>?
    /// В этой сдаче про раздумья уже шутили.
    private var longThinkDeal = -1
    /// Зерно запуска: с ним автоигру можно повторить (`-DebercSeed`).
    private let launchSeed: UInt64

    private var gameID = UUID()
    private var startedAt = Date()

    private var driver: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var bannerQueue = BannerQueue()
    private var bannerGeneration = 0
    private var bannerShownAt = Date.distantPast
    /// Сообщение на экране целиком — со всеми флагами (важное, подсказка первого хода).
    private var currentBannerItem: BannerQueue.Item?
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
        let storage = Storage(space: options.isDemo ? .demo : .user, fresh: !options.resume)
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
        banterRng = SplitMix64(seed: seed ^ 0xBA17_E4ED_0000_0001)
        requestedScreen = options.screenName
        sounds.soundEnabled = settings.soundEnabled && !autoplay
        sounds.hapticsEnabled = settings.hapticsEnabled && !autoplay

        if options.resume {
            // Как обычный перезапуск, но из демо-каталога: настройки и партия игрока не трогаются.
            restoreSavedGame()
            reportProgress()
        } else if options.isDemo {
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

    /// Последняя собранная взятка текущей сдачи — уже в стопке (не та, что ещё лежит на столе).
    var lastTrick: Trick? {
        guard let deal = match?.deal else { return nil }
        return TableScene.collected(deal: deal, displayed: displayedTrick).last
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
        // Вернулись к партии: сначала оглядеться — соперник не ходит сразу, а свежая раздача
        // успевает долететь. Вынужденная карта в этот ход сама не уходит: пусть игрок сходит сам.
        if let deal = match.deal, !deal.prikupDealt, deal.tricks.isEmpty {
            hold(.milliseconds(Int(settings.speed.cardFlight * 1000) + 600))
        } else {
            hold(.milliseconds(1200))
        }
        handTouchedThisTurn = true
        if let deal = match.deal {
            humanTurnKey = [match.dealCount, deal.tricks.count, deal.currentTrick.plays.count, deal.bids.count]
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
        // Соперник вспоминает прошлую сдачу или счёт — пока раздают карты.
        if let say = BanterTriggers.atDealStart(current, humanSeat: humanSeat, bots: botSeats,
                                                 pick: { Int(self.banterRng.next() % UInt64($0)) }) {
            banter(say.event, seat: say.seat, after: .milliseconds(Int(settings.speed.cardFlight * 1000) + 500))
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
        // или в карту после сбора взятки — такой «ход» отбрасываем. Пока открыта панель или лист —
        // тоже: ход делают за столом, а не сквозь меню.
        guard !byUser || (!isRepeatTap && !isOverlayPresented) else { return }
        let before = current
        let rngBefore = rng
        // Вынужденный ход (одна допустимая карта) — не решение: его не отменяют.
        let forced: Bool = {
            guard case .play = action, let deal = current.deal else { return false }
            return deal.legalCards(for: humanSeat).count == 1
        }()
        do {
            let events = try current.apply(action)
            lastHumanActionAt = Date()
            cancelHint()
            lastStepWasBot = false
            if !autoplay {
                // Отменить можно только последнее своё решение и только пока соперник не ответил.
                // Решение, после которого раздали прикуп, не отменить: карты прикупа уже видны.
                let revealed = events.contains { if case .prikupDealt = $0 { return true } else { return false } }
                if byUser && !forced && !revealed {
                    undoStack = [(before, rngBefore)]
                    // Чуть дольше, чем обычно, до ответа соперника — успеть передумать.
                    hold(.milliseconds(700))
                } else {
                    clearUndo()
                }
            }
            // Сами походили, пока в центре «печать» козыря или комбинаций, — её уже посмотрели.
            if announcement != nil || !announcementQueue.isEmpty {
                switch action {
                case .play, .exchangeSeven:
                    clearAnnouncement()
                    holdUntil = nil
                default:
                    break
                }
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
        if displayedTrick != nil { collectTrick(byUser: true) }
        guard isHumanTurn, let deal = match?.deal, deal.phase == .playing else {
            explainNotYourTurn()
            return
        }
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

    /// Бросили карту, которой ходить нельзя (или не время), — объяснить почему.
    func explainCard(_ card: Card) {
        guard isHumanTurn, let deal = match?.deal, deal.phase == .playing else {
            explainNotYourTurn()
            return
        }
        rejectCard(card, in: deal)
    }

    /// Палец лёг на руку или ушёл с неё (автоход ждёт, пока палец на руке).
    func setHandTouch(_ active: Bool) {
        handTouchActive = active
        if active && isHumanTurn { handTouchedThisTurn = true }
    }

    /// Касание карты не в свой ход: коротко сказать, чего ждём (не чаще раза в 3 секунды).
    private func explainNotYourTurn() {
        guard !autoplay, isInGame, !showDealSummary, let match, let deal = match.deal,
              Date().timeIntervalSince(lastNotYourTurnAt) > 3 else { return }
        let text: String
        switch deal.phase {
        case .bidding, .exchange:
            guard let actor = match.actor else { return }
            text = actor == humanSeat ? "Сначала торговля: беру или пас" : "Идёт торговля — отвечает \(displayName(for: actor))"
        case .playing:
            guard displayedTrick == nil, let actor = match.actor, actor != humanSeat else { return }
            text = "Сейчас ходит \(displayName(for: actor)) — подождите"
        case .finished:
            return
        }
        lastNotYourTurnAt = Date()
        showBanner(text, urgent: true)
    }

    /// Бросок карты на стол (и действие VoiceOver «Сходить»): лежащая взятка сначала соберётся сама.
    /// true — карта ушла на стол.
    @discardableResult
    func throwCard(_ card: Card) -> Bool {
        if displayedTrick != nil { collectTrick(byUser: false) }
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

    /// Убрать собранную взятку со стола сразу, не дожидаясь паузы. `byUser` — касанием: второе касание
    /// сразу после своего хода (двойной тап, дрогнул палец) не сметает только что закрытую взятку.
    func collectTrick(byUser: Bool = true) {
        guard displayedTrick != nil, !byUser || !isRepeatTap else { return }
        gatherTrick()
        noteActivity()
        drive()
    }

    /// Совет Мастера для текущего решения: торговля, обмен семёрки или ход.
    /// В одной и той же позиции — всегда один и тот же.
    func showHint() {
        // Второе касание «Отменить» или касание в место пропавшей кнопки отмены — не за советом.
        guard isHumanTurn, !isRepeatTap, Date().timeIntervalSince(undoClearedAt) > 0.6,
              let snapshot = match else { return }
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

    /// Отменить своё последнее решение — один шаг назад и только пока соперник не ответил.
    /// Соперники потом ответят так же (генератор случайностей возвращается вместе с партией).
    func undo() {
        // Двойное касание «Отменить» не должно отменять два хода (и сразу отменять только что сделанный).
        guard canUndo, !isRepeatTap, let snapshot = undoStack.popLast() else { return }
        let previous = snapshot.match
        rng = snapshot.rng
        let wasBid: Bool = {
            switch previous.deal?.phase {
            case .bidding?, .exchange?: return true
            default: return false
            }
        }()
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
        showBanner(wasBid ? "Заявка отменена" : "Ход отменён — карта вернулась в руку", urgent: true)
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
        showBanner(text, urgent: urgent, long: long, playTip: false)
    }

    private func showBanner(_ text: String, urgent: Bool, long: Bool, playTip: Bool) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if urgent {
            let current = banner == nil ? nil : currentBannerItem
            bannerQueue.pushUrgent(text, current: current, shownFor: Date().timeIntervalSince(bannerShownAt),
                                   base: settings.speed.bannerTime, long: long, playTip: playTip)
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

    // MARK: - Подначки соперников

    /// Места соперников.
    private var botSeats: [Int] {
        (0..<(match?.playerCount ?? 0)).filter { $0 != humanSeat }
    }

    private func randomBotSeat() -> Int {
        let bots = botSeats
        guard !bots.isEmpty else { return humanSeat }
        return bots[Int(banterRng.next() % UInt64(bots.count))]
    }

    /// Подначка соперника — если повод хороший и давно ничего не говорили (настройка «Реплики соперников»).
    /// Не перебивает «печати» в центре: ждёт, пока их покажут. `after` — не раньше, чем через столько.
    private func banter(_ event: BanterEvent, seat: Int, after delay: Duration = .zero) {
        guard !unattended, let persona = persona(for: seat) else { return }
        let roll = Double(banterRng.next() % 10_000) / 10_000
        guard Banter.shouldSpeak(event, level: settings.banter, sinceLast: Date().timeIntervalSince(lastTauntAt),
                                 roll: roll),
              let text = Banter.line(event, persona: persona, variant: banterRng.next(),
                                     avoid: Set(recentTaunts)) else { return }
        lastTauntAt = Date()
        recentTaunts.append(text)
        if recentTaunts.count > 20 { recentTaunts.removeFirst() }
        tauntSerial &+= 1
        let item = TableTaunt(id: tauntSerial, seat: seat, text: text)
        let busy = announcementsBusyUntil - .now
        let wait = max(delay, busy)
        let hold = max(.milliseconds(2800), settings.speed.bannerTime * 1.3)
        tauntTask?.cancel()
        tauntTask = Task { [weak self] in
            guard let self else { return }
            if wait > .zero {
                guard await self.visibleSleep(wait) else { return }
            }
            withAnimation(self.animation(.spring(response: 0.35, dampingFraction: 0.72))) { self.taunt = item }
            guard await self.visibleSleep(hold), self.taunt?.id == item.id else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.taunt = nil }
        }
    }

    /// Человек задумался надолго — кто-нибудь из соперников пошутит (раз за сдачу).
    private func scheduleLongThinkBanter() {
        longThinkTask?.cancel()
        guard settings.banter != .off, !unattended, let snapshot = match, longThinkDeal != snapshot.dealCount else { return }
        let wait: Duration = settings.speed == .slow ? .seconds(40) : .seconds(28)
        longThinkTask = Task { [weak self] in
            guard let self, await self.visibleSleep(wait), !Task.isCancelled,
                  self.match == snapshot, self.isHumanTurn else { return }
            self.longThinkDeal = snapshot.dealCount
            self.banter(.longThink, seat: self.randomBotSeat())
        }
    }

    private func clearTaunt() {
        tauntTask?.cancel()
        tauntTask = nil
        longThinkTask?.cancel()
        longThinkTask = nil
        taunt = nil
    }

    /// VoiceOver проговаривает событие, у которого вместо строки внизу — «печать» в центре.
    private func speak(_ event: DealEvent, in match: Match) {
        guard let text = Narrator.message(for: event, in: match, humanSeat: humanSeat) else { return }
        speakForVoiceOver(text)
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
                // Считать от момента, когда последняя карта легла, — иначе полную взятку с подписью
                // «Берёт Саша» видно меньше секунды.
                guard await visibleSleep(settings.speed.trickPause
                                         + .milliseconds(Int(settings.speed.cardFlight * 1000) + 200)) else { return }
                gatherTrick()

            case .redeal:
                thinkingSeat = nil
                if autoplay, let match { traceDeal(match) }
                // Сообщение «Все спасовали… Следующая — на обязах» дочитывают до конца.
                guard await visibleSleep(settings.speed.bannerTime), await waitForBanners() else { return }
                startNextDeal()
                return

            case .showSummary:
                thinkingSeat = nil
                // Четыре семёрки выпадают сразу после раздачи: дать увидеть раздачу и прочитать сообщение.
                let fourSevens = match?.history.last?.outcome == .fourSevens
                let pause: Duration = fourSevens && !unattended
                    ? .milliseconds(Int(settings.speed.cardFlight * 1000)) + settings.speed.bannerTime
                    : .milliseconds(450)
                guard await visibleSleep(pause) else { return }
                presentSummary()
                await advanceAutoplayIfNeeded()
                return

            case .waitSummary:
                thinkingSeat = nil
                await advanceAutoplayIfNeeded()
                return

            case .waitHuman:
                thinkingSeat = nil
                // «Ваш ход» — вибрация и тихий сигнал; но не перед автоходом: карта всё равно уйдёт сама.
                if lastStepWasBot && autoMoveCard() == nil {
                    sounds.haptic(.turn)
                    sounds.play(.turn)
                }
                lastStepWasBot = false
                if let deal = match?.deal {
                    let key = [match?.dealCount ?? 0, deal.tricks.count, deal.currentTrick.plays.count, deal.bids.count]
                    if key != humanTurnKey {
                        humanTurnKey = key
                        handTouchedThisTurn = handTouchActive
                    }
                }
                if let card = autoMoveCard() {
                    await autoMove(card)
                    return
                }
                showPlayTipIfNeeded()
                scheduleLongThinkBanter()
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
        // Палец на руке (рассматривают, тянут) — карту из-под пальца не забирать: подождать
        // (не дольше 5 с — вдруг касание «залипло»), потом снова выдержать паузу.
        var waited = 0
        while handTouchActive && waited < 50 {
            guard await visibleSleep(.milliseconds(100)) else { return }
            waited += 1
        }
        if waited > 0 {
            guard await visibleSleep(.milliseconds(400)) else { return }
        }
        // Человек в этот ход сам взялся за карты — пусть и ходит сам.
        guard !Task.isCancelled, !handTouchedThisTurn, autoMoveCard() == card else { return }
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
        // Как касание человека: с отменой хода и всем прочим.
        lastHumanActionAt = .distantPast
        perform(action, byUser: true)
    }

    /// Первый свой ход в розыгрыше — одна подсказка, как ходить картой.
    private func showPlayTipIfNeeded() {
        guard !autoplay, !settings.hasSeenPlayTip, isHumanTurn, match?.deal?.phase == .playing,
              currentBannerItem?.playTip != true, !bannerQueue.hasPlayTip else { return }
        // Пока в центре «печать» козыря или комбинаций — подождать: две крупные надписи сразу не читают.
        let busy = announcementsBusyUntil - .now
        if busy > .zero {
            Task { [weak self] in
                guard let self, await self.visibleSleep(busy) else { return }
                self.showPlayTipIfNeeded()
            }
            return
        }
        // Показанной подсказка считается, только когда провисит целиком (её могла перебить ошибка хода).
        showBanner(settings.confirmCardTap
                   ? "Коснитесь карты — она поднимется, коснитесь ещё раз — сходите. Или бросьте её пальцем вверх"
                   : "Коснитесь карты, чтобы сходить, или бросьте её пальцем вверх",
                   urgent: true, long: true, playTip: true)
    }

    /// Отмена больше недоступна (соперник ответил, взятка собрана).
    private func clearUndo() {
        guard !undoStack.isEmpty else { return }
        undoStack.removeAll()
        undoClearedAt = Date()
    }

    private func commitBotMove(_ updated: Match, _ events: [DealEvent]) {
        // Соперник ответил — свой прошлый ход уже не отменить.
        clearUndo()
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
        // Взятка ушла в стопку — отменить карту, закрывшую её, уже нельзя.
        clearUndo()
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
                if bid.seat != humanSeat {
                    speakForVoiceOver("\(displayName(for: bid.seat)): \(Narrator.bidText(bid))")
                }
            case .trumpChosen(let seat, let suit, let forced):
                // Вместо строки внизу — крупная «печать» с мастью в центре стола.
                announce(.trump(seat: seat, suit: suit, forced: forced), for: settings.speed.announcePause * 1.15)
                speak(event, in: current)
                if !forced {
                    if seat == humanSeat {
                        banter(.humanTakesGame, seat: randomBotSeat())
                    } else {
                        banter(.botTakesGame, seat: seat)
                    }
                }
                continue
            case .playStarted(let decl):
                // Комбинации — «печатью» с самими картами: у кого и сколько записано.
                if let winner = decl.meldWinner, decl.melds.indices.contains(winner), !decl.melds[winner].isEmpty {
                    let others = decl.melds.enumerated().contains { $0.offset != winner && !$0.element.isEmpty }
                    // Свои комбинации человек и так видит — их «печать» короче.
                    announce(.melds(seat: winner, melds: decl.melds[winner],
                                    points: decl.meldPoints(for: winner, rules: current.rules), senior: others),
                             for: settings.speed.announcePause * (winner == humanSeat ? 0.8 : 1.15)
                                 + .milliseconds(winner == humanSeat ? 0 : 500 * decl.melds[winner].count))
                    speak(event, in: current)
                    if winner != humanSeat { banter(.botMelds, seat: winner) }
                    continue
                }
            case .sevenExchanged:
                important = true
            case .prikupDealt:
                sounds.play(.deal)
            case .cardPlayed(let played):
                // Реплики торговли («Беру ♦», «Пас») видны до первой карты розыгрыша.
                if !bubbles.isEmpty { bubbles = [:] }
                sounds.play(.card)
                if played.seat != humanSeat {
                    speakForVoiceOver("\(displayName(for: played.seat)): \(Narrator.spokenCard(played.card))")
                }
            case .bella(let seat):
                urgent = true
                sounds.play(.bella)
                if seat == humanSeat {
                    sounds.haptic(.soft)
                    banter(.humanBella, seat: randomBotSeat())
                } else {
                    banter(.botBella, seat: seat)
                }
            case .trickCompleted(let trick):
                displayedTrick = trick
                if trick.winner == humanSeat && !autoplay { sounds.haptic(.soft) }
                if let winner = trick.winner {
                    speakForVoiceOver(winner == humanSeat ? "Ваша взятка" : "Взятку берёт \(displayName(for: winner))")
                }
                if let say = BanterTriggers.afterTrick(trick, trump: current.deal?.trump, humanSeat: humanSeat) {
                    // Когда последняя карта легла.
                    banter(say.event, seat: say.seat, after: .milliseconds(Int(settings.speed.cardFlight * 1000)))
                }
            case .allPassed:
                bubbles = [:]
                banter(.allPassed, seat: randomBotSeat(), after: .milliseconds(600))
            case .fourSevens:
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
        // Совет торговли и обмена уже написан золотом в панели под кнопками — не дублировать внизу стола.
        if case .play = action {
            showBanner(GameFlow.hintText(action, deal: match?.deal), urgent: true)
        } else {
            speakForVoiceOver(GameFlow.hintText(action, deal: match?.deal))
        }
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
                currentBannerItem = nil
                bannerTask = nil
                return
            }
            let hold = bannerQueue.hold(for: item, base: settings.speed.bannerTime)
            withAnimation(.easeInOut(duration: 0.25)) { banner = item.text }
            bannerIsUrgent = item.urgent
            currentBannerItem = item
            bannerShownAt = Date()
            speakForVoiceOver(item.text)
            guard await visibleSleep(hold), generation == bannerGeneration else { return }
            // Подсказка первого хода провисела целиком — больше не показывать.
            if item.playTip && !settings.hasSeenPlayTip { settings.hasSeenPlayTip = true }
        }
    }

    private func clearBanners() {
        bannerGeneration &+= 1
        bannerTask?.cancel()
        bannerTask = nil
        bannerQueue.removeAll()
        banner = nil
        bannerIsUrgent = false
        currentBannerItem = nil
    }

    /// Дождаться, пока покажут все сообщения (не дольше 6 с). false — задачу отменили.
    private func waitForBanners() async -> Bool {
        var waited = 0
        while (banner != nil || !bannerQueue.isEmpty) && waited < 40 {
            guard await visibleSleep(.milliseconds(150)) else { return false }
            waited += 1
        }
        return true
    }

    /// Проговорить VoiceOver — в очередь, не обрывая то, что уже говорится.
    private func speakForVoiceOver(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let spoken = NSAttributedString(string: Narrator.spoken(text),
                                        attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: spoken)
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
        clearTaunt()
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
            clearTaunt()
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
        // Включили автоход в свой ход — последняя карта уходит сразу, как и обещано в настройках.
        if settings.autoPlay != old.autoPlay && isHumanTurn { drive() }
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
