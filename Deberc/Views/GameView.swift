import SwiftUI
import UIKit
import DebercKit

/// Игровой стол: раскладка, листы (запись, правила, настройки), окно итогов сдачи.
struct GameView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showScoreSheet = false
    @State private var showRules = false
    @State private var showSettings = false
    @State private var showLastTrick = false
    @State private var showTableMenu = false
    @State private var confirmLeave = false
    /// Место соперника, чью карточку открыли.
    @State private var personaSeat: Int?

    var body: some View {
        GeometryReader { geo in
            content(size: geo.size, safeTop: geo.safeAreaInsets.top, bottomInset: geo.safeAreaInsets.bottom)
        }
        .cardAppearance(fourColor: store.settings.fourColorDeck, largeIndex: store.settings.largeCards,
                        back: store.settings.cardBack)
        .environment(\.tableLargeControls, store.settings.largeCards)
        // Рука лежит у нижнего края: жест «Домой» — только со второго смахивания. Сверху — меню (в ушке у выреза
        // или в полосе, а строка состояния скрыта): смахивание от ≡ не открывает сразу Центр уведомлений.
        .defersSystemGestures(on: .vertical)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showScoreSheet) {
            if let match = store.match {
                ScoreSheetView(match: match, humanSeat: store.humanSeat)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showRules) {
            // Если правила поменяли посреди партии, можно посмотреть и те, что будут с новой партии.
            RulesView(rules: store.match?.rules ?? store.settings.rules, newGameRules: store.settings.rules)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        // Alert, а не confirmationDialog: на iPad тот показывается поповером без привязки к кнопке.
        .alert("Выйти в меню?", isPresented: $confirmLeave) {
            Button("Выйти") { store.leaveGame() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Партия сохранится — её можно продолжить из меню.")
        }
        .onChange(of: overlayOpen) { open in
            // Пока открыт лист, диалог или меню стола, игра на паузе: соперники не ходят, сообщения ждут.
            store.isOverlayPresented = open
        }
        .onChange(of: store.isHumanTurn) { mine in
            if mine && UIAccessibility.isVoiceOverRunning {
                // В очередь за тем, что VoiceOver уже читает: иначе «Ваш ход» обрывал объявление козыря.
                let text = NSAttributedString(string: "Ваш ход",
                                              attributes: [.accessibilitySpeechQueueAnnouncement: true])
                UIAccessibility.post(notification: .announcement, argument: text)
            }
        }
        .onChange(of: store.showDealSummary) { shown in
            guard shown, UIAccessibility.isVoiceOverRunning else { return }
            // Фокус — на итоги сдачи, а не на карту руки под ними (окно появляется с анимацией).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
        .onChange(of: store.lastTrick == nil) { noTrick in
            if noTrick { showLastTrick = false }
        }
        .onAppear(perform: openRequestedScreen)
        #if DEBUG
        .onAppear(perform: Self.checkLayout)
        #endif
        .onDisappear {
            if store.isOverlayPresented { store.isOverlayPresented = false }
        }
    }

    private var overlayOpen: Bool {
        showScoreSheet || showRules || showSettings || showLastTrick || showTableMenu || confirmLeave
            || personaSeat != nil
    }

    private var commands: TableCommands {
        TableCommands(
            showScoreSheet: { showScoreSheet = true },
            showRules: { showRules = true },
            showSettings: { showSettings = true },
            showLastTrick: { showLastTrick = true },
            showPersona: { seat in personaSeat = seat },
            showMenu: { showTableMenu = true },
            leave: { confirmLeave = true })
    }

    @ViewBuilder
    private func content(size: CGSize, safeTop: CGFloat, bottomInset: CGFloat) -> some View {
        let players = store.match?.playerCount ?? store.settings.playerCount
        let large = store.settings.largeCards
        // Размер текста стола — с потолком (стол не разъезжается), а окна поверх него (итоги, последняя
        // взятка, карточка соперника, меню) — как листы, до AX3: они прокручиваются или просторны.
        let tableType = TableMetrics.typeSize(system: systemTypeSize, size: size, large: large)
        // Окна поверх стола (итоги, последняя взятка, карточка соперника, меню) — не мельче стола
        // (с надбавкой крупного режима), но им можно расти до AX3: места у них больше.
        // Нижняя граница не выше верхней: при системном тексте крупнее AX3 диапазон иначе был бы пустым.
        let overlayType = min(max(tableType, systemTypeSize), .accessibility3)
        let metrics = TableMetrics(size: size, playerCount: players, large: large, safeTop: safeTop,
                                   bottomInset: bottomInset, typeSize: tableType)
        // Окно итогов — под полосой меню: длинные итоги (втроём, с раскрытыми картами) не уходят под ≡.
        // Меню в ушке у выреза — полосы нет, окну достаётся вся высота под вырезом.
        let summaryTop = metrics.earBar ? 4 : metrics.topPadding + metrics.topBarHeight
        ZStack {
            FeltBackground()
            if let match = store.match, let deal = match.deal {
                TableScreen(match: match, deal: deal, metrics: metrics, commands: commands)
                    .dynamicTypeSize(tableType)
                if metrics.earBar {
                    // VoiceOver читает стол сверху: меню и козырь в ушках — первыми, хоть они и нарисованы поверх стола.
                    earBar(match: match, deal: deal, metrics: metrics, safeTop: safeTop, trump: true)
                        .dynamicTypeSize(tableType)
                        .accessibilitySortPriority(1)
                }
            } else {
                ProgressView()
                    .tint(Theme.tableText)
            }
            if store.showDealSummary, let match = store.match {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(3)
                DealSummaryView(match: match, maxHeight: size.height - summaryTop - 40,
                                maxWidth: min(metrics.roomy ? 640 : 560, size.width))
                    .dynamicTypeSize(overlayType ... .accessibility3)
                    .frame(width: size.width, height: max(1, size.height - summaryTop))
                    .padding(.top, summaryTop)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(4)
                Group {
                    if metrics.earBar, let deal = match.deal {
                        earBar(match: match, deal: deal, metrics: metrics, safeTop: safeTop, trump: false)
                            .accessibilitySortPriority(1)
                    } else {
                        summaryMenu(metrics: metrics)
                    }
                }
                .dynamicTypeSize(tableType)
                .transition(.opacity)
                .zIndex(5)
            }
            if showLastTrick, let trick = store.lastTrick {
                LastTrickPanel(trick: trick, names: displayNames, maxCardWidth: min(110, metrics.handCardWidth),
                               screenWidth: size.width, onClose: { showLastTrick = false })
                    .dynamicTypeSize(overlayType ... .accessibility3)
                    .transition(.opacity)
                    .zIndex(6)
            }
            if let seat = personaSeat, let persona = store.persona(for: seat) {
                PersonaPanel(persona: persona, record: store.stats.byPersona[persona.id],
                             onClose: { personaSeat = nil })
                    .dynamicTypeSize(overlayType ... .accessibility3)
                    .transition(.opacity)
                    .zIndex(7)
            }
            if showTableMenu {
                TableMenuPanel(commands: commands, onClose: { showTableMenu = false })
                    .dynamicTypeSize(overlayType ... .accessibility3)
                    .transition(.opacity)
                    .zIndex(8)
            }
        }
        // Контейнер для VoiceOver: порядок чтения — внутри стола (ушки первыми), касания это не меняет.
        .accessibilityElement(children: .contain)
        .animation(.easeInOut(duration: 0.25), value: store.showDealSummary)
        .animation(.easeInOut(duration: 0.2), value: showLastTrick)
        .animation(.easeInOut(duration: 0.2), value: personaSeat)
        .animation(.easeInOut(duration: 0.2), value: showTableMenu)
        .statusBarHidden(!metrics.roomy)
    }

    private var displayNames: [String] {
        let count = store.match?.playerCount ?? 0
        return (0..<count).map { store.displayName(for: $0) }
    }

    /// Меню и козырь в ушках у выреза (`TableEarBar`): полоса в верхнем отступе, центр — посередине него.
    /// Раскладка идёт от безопасной зоны, поэтому полоса сдвинута вверх на отступ.
    private func earBar(match: Match, deal: Deal, metrics: TableMetrics, safeTop: CGFloat, trump: Bool) -> some View {
        TableEarBar(match: match, deal: deal, metrics: metrics, commands: commands, trump: trump)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(y: -(safeTop + metrics.earHeight) / 2)
    }

    /// Кнопка меню поверх окна итогов — на том же месте, что и в верхней полосе:
    /// между сдачами можно открыть запись партии, настройки или выйти.
    private func summaryMenu(metrics: TableMetrics) -> some View {
        VStack(spacing: 0) {
            HStack {
                TableMenuButton(commands: commands, size: metrics.roomy ? 50 : 44)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.gutter)
            .frame(height: metrics.topBarHeight)
            .padding(.top, metrics.topPadding)
            Spacer(minLength: 0)
        }
    }

    #if DEBUG
    /// `-DebercLayoutCheck`: прогнать раскладку стола по размерам iPhone (ширина × высота экрана, отступы
    /// сверху и снизу) вдвоём и втроём, в обычном и крупном режиме, и напечатать, что не помещается.
    private static var layoutChecked = false

    private static func checkLayout() {
        guard UserDefaults.standard.bool(forKey: "DebercLayoutCheck"), !layoutChecked else { return }
        layoutChecked = true
        let screens: [(name: String, width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat)] = [
            ("14 Pro, «Увеличенный»", 320, 693, 48, 28),
            ("X, XS, 11 Pro", 375, 812, 44, 34),
            ("12 mini, 13 mini", 375, 812, 50, 34),
            ("12–14, 16e", 390, 844, 47, 34),
            ("14 Pro–16", 393, 852, 59, 34),
            ("16 Pro, 17", 402, 874, 62, 34),
            ("11, XR", 414, 896, 48, 34),
            ("16 Pro Max", 440, 956, 62, 34),
        ]
        var checked = 0
        var failed = 0
        for screen in screens {
            let size = CGSize(width: screen.width, height: screen.height - screen.top - screen.bottom)
            for players in [2, 3] {
                for large in [false, true] {
                    for system in [DynamicTypeSize.large, .xxxLarge] {
                        let type = TableMetrics.typeSize(system: system, size: size, large: large)
                        let metrics = TableMetrics(size: size, playerCount: players, large: large, safeTop: screen.top,
                                                   bottomInset: screen.bottom, typeSize: type)
                        checked += 1
                        let problems = metrics.layoutProblems
                        guard !problems.isEmpty else { continue }
                        failed += 1
                        print("Раскладка: \(screen.name), \(players == 2 ? "вдвоём" : "втроём"), \(large ? "крупный" : "обычный") режим, "
                              + "текст \(system): " + problems.joined(separator: "; "))
                    }
                }
            }
        }
        print("Раскладка: проверено \(checked), с нарушениями \(failed)")
    }
    #endif

    /// `-DebercScreen scoresheet` (скриншоты CI): сразу открыть запись партии.
    private func openRequestedScreen() {
        guard let screen = store.requestedScreen, screen == "scoresheet" || screen == "persona" else { return }
        store.requestedScreen = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if screen == "scoresheet" {
                showScoreSheet = true
            } else {
                personaSeat = (store.humanSeat + 1) % (store.match?.playerCount ?? 2)
            }
        }
    }
}

// MARK: - Раскладка стола

/// Стол целиком: верхняя полоса, места соперников, центр, своё место, панель действий, рука;
/// на широком экране справа — панель счёта. Карты рисует слой поверх (`TableLayer`)
/// по кадрам мест, которые сообщает эта раскладка.
struct TableScreen: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let match: Match
    let deal: Deal
    let metrics: TableMetrics
    let commands: TableCommands
    /// Карта, которую тянут пальцем из руки.
    @State private var drag: HandDrag?
    /// Последнее сообщение стола: сами сообщения и «печати» гаснут через пару секунд и скрыты от VoiceOver
    /// (они в слое поверх стола), а прослушанное можно повторить действием центра стола.
    @State private var lastMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            tableColumn
            if metrics.wide {
                SidePanel(match: match, commands: commands)
                    .frame(width: metrics.sidePanelWidth)
            }
        }
        .overlayPreferenceValue(TableSlotKey.self) { anchors in
            TableLayerHost(anchors: anchors, model: layerModel)
        }
        // Новая сдача — никакой карты «в пальцах» от прошлой.
        .onChange(of: match.dealCount) { _ in drag = nil }
        .onChange(of: store.banner) { banner in
            if let banner { lastMessage = Narrator.spoken(banner) }
        }
        .onChange(of: store.announcement) { announcement in
            if let announcement { lastMessage = spoken(announcement) }
        }
    }

    // MARK: Колонка стола

    private var tableColumn: some View {
        VStack(spacing: metrics.spacing) {
            // Вдвоём соперник — в верхней полосе, между меню и козырем.
            // Втроём с ушками у выреза полосы нет: меню и козырь — в ушках (`TableEarBar`).
            if !(metrics.earBar && match.playerCount == 3) {
                TableTopBar(match: match, deal: deal, metrics: metrics, commands: commands,
                            opponent: match.playerCount == 2 ? seatInfo(leftSeat) : nil,
                            canShowLastTrick: store.lastTrick != nil)
            }
            if metrics.sideSeats {
                HStack(alignment: .top, spacing: 12) {
                    SeatColumn(info: seatInfo(leftSeat), metrics: metrics, commands: commands,
                               canShowLastTrick: store.lastTrick != nil)
                        .frame(width: metrics.sideSeatWidth)
                    centerSlot
                    SeatColumn(info: seatInfo(rightSeat), metrics: metrics, commands: commands,
                               canShowLastTrick: store.lastTrick != nil)
                        .frame(width: metrics.sideSeatWidth)
                }
                .padding(.horizontal, metrics.gutter)
            } else {
                opponentsRow
                centerSlot
            }
            HumanStrip(info: seatInfo(store.humanSeat), live: livePoints, metrics: metrics,
                       commands: commands, canShowLastTrick: store.lastTrick != nil)
            ActionPanel(match: match, deal: deal, metrics: metrics)
            hand
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // На телефоне рука ложится до самого края экрана и уходит за него: карты крупнее.
        .ignoresSafeArea(.container, edges: metrics.handVisible < 1 ? .bottom : [])
    }

    private var leftSeat: Int { (store.humanSeat + 1) % match.playerCount }
    private var rightSeat: Int { (store.humanSeat + 2) % match.playerCount }

    /// Соперники втроём: слева и справа, под верхней полосой.
    @ViewBuilder
    private var opponentsRow: some View {
        if match.playerCount == 3 {
            // Промежуток между соперниками — ровно 12 pt, не больше: колонки рассчитаны на него
            // (`opponentColumnWidth`), и на 320 pt ряд не выходит за правый край.
            HStack(alignment: .top, spacing: 0) {
                SeatStack(info: seatInfo(leftSeat), metrics: metrics, commands: commands,
                          canShowLastTrick: store.lastTrick != nil, leading: true)
                Spacer(minLength: 12)
                SeatStack(info: seatInfo(rightSeat), metrics: metrics, commands: commands,
                          canShowLastTrick: store.lastTrick != nil, leading: false)
            }
            .padding(.horizontal, metrics.gutter)
        }
    }

    /// Центр стола: взятка (касание собирает показанную взятку), во время торговли — открытая карта;
    /// у левого края — колода. Вдвоём колода — посередине высоты; втроём — внизу слева: там во взятке
    /// только своя карта по центру, а карты соперников (слева и справа, выше) колоду не задевают —
    /// взятка растёт до высоты центра. На iPad с соперниками по бокам колода так не теснит веер левого соперника
    /// (и сдвинута в промежуток до его колонки — `deckShift`).
    private var centerSlot: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if store.displayedTrick != nil { store.collectTrick() }
            }
            .tableSlot(.center)
            .accessibilityElement()
            .accessibilityLabel(centerDescription)
            .accessibilityValue(store.banner.map(Narrator.spoken) ?? "")
            .accessibilityHint(store.displayedTrick != nil ? "Коснитесь дважды, чтобы собрать взятку" : "")
            .accessibilityActions {
                if store.displayedTrick != nil {
                    Button("Собрать взятку") { store.collectTrick() }
                }
                if let lastMessage {
                    Button("Повторить сообщение") {
                        UIAccessibility.post(notification: .announcement, argument: lastMessage)
                    }
                }
            }
            .overlay(alignment: match.playerCount == 3 ? .bottomLeading : .leading) {
                let size = metrics.deckSlotSize
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .tableSlot(.deck)
                    .accessibilityElement()
                    .accessibilityLabel(deckDescription)
                    .padding(.leading, metrics.deckShift)
            }
    }

    /// «Печать» стола словами — для повтора в VoiceOver.
    private func spoken(_ announcement: TableAnnouncement) -> String {
        switch announcement.kind {
        case .trump(let seat, let suit, let forced):
            let who = seat == store.humanSeat ? "играете вы" : "играет \(store.displayName(for: seat))"
            return (forced ? "Обязы, козырь " : "Козырь ") + suit.name + ", " + who
        case .melds(let seat, let melds, let points, _):
            let owner = seat == store.humanSeat ? "Вы" : store.displayName(for: seat)
            let names = melds.map { $0.name(match.rules) }.joined(separator: " и ")
            return "\(owner): \(names), плюс \(points)"
        }
    }

    private var deckDescription: String {
        var parts = ["Колода. Открытая карта: \(CardView.spokenName(deal.openCard))"]
        if deal.bottomCardVisible, let bottom = deal.bottomCard {
            parts.append("нижняя карта: \(CardView.spokenName(bottom))")
        }
        return parts.joined(separator: ", ")
    }

    private var hand: some View {
        let isActive = store.isHumanTurn && deal.phase == .playing
        let maxWidth: CGFloat = metrics.roomy ? 1100 : .infinity
        return HandView(cards: deal.hands[store.humanSeat].sortedForDisplay(trump: deal.trump),
                        cardWidth: metrics.handCardWidth,
                        lift: metrics.handLift,
                        trump: deal.trump,
                        isActive: isActive,
                        legal: store.legalCards,
                        selected: store.selectedCard,
                        visibleHeight: metrics.handHeight - metrics.handLift,
                        drag: $drag)
            .frame(maxWidth: maxWidth)
            .tableSlot(.hand)
            .padding(.horizontal, metrics.handInset)
            .padding(.bottom, metrics.handVisible < 1 ? 0 : 4)
    }

    // MARK: Сведения

    private func seatInfo(_ seat: Int) -> SeatInfo {
        let rules = match.rules
        let isHuman = seat == store.humanSeat
        let actorSeat: Int? = store.displayedTrick?.winner ?? (store.showDealSummary ? nil : deal.actor)
        return SeatInfo(
            seat: seat,
            name: store.displayName(for: seat),
            persona: store.persona(for: seat),
            isHuman: isHuman,
            score: match.totals[seat],
            target: rules.targetScore,
            isDealer: deal.dealer == seat,
            isBidder: deal.bidder == seat,
            trump: deal.trump,
            isActive: actorSeat == seat,
            isThinking: store.thinkingSeat == seat,
            baitMarks: marks(match.baitCounts, seat, every: rules.baitPenaltyEvery),
            nakedMarks: marks(match.nakedCounts, seat, every: rules.nakedPenaltyEvery),
            tricks: TableScene.pileCountFor(seat, deal: deal, displayed: store.displayedTrick),
            bubble: store.bubbles[seat],
            declarations: declarations(seat),
            rules: rules)
    }

    /// Сколько байтов (голых) набралось к следующему штрафу.
    private func marks(_ counts: [Int], _ seat: Int, every: Int) -> Int {
        guard every > 1, counts.indices.contains(seat) else { return 0 }
        return counts[seat] % every
    }

    /// Постоянные отметки места: записанные комбинации, объявленная бэла, обмен семёрки.
    private func declarations(_ seat: Int) -> [DeclItem] {
        var items: [DeclItem] = []
        if let exchange = deal.sevenExchange, exchange.seat == seat {
            items.append(.exchange(exchange.took))
        }
        if let decl = deal.declarations {
            if decl.meldWinner == seat, decl.melds.indices.contains(seat) {
                items.append(contentsOf: decl.melds[seat].map { DeclItem.meld($0) })
            } else if seat == store.humanSeat, decl.melds.indices.contains(seat), !decl.melds[seat].isEmpty {
                items.append(.burned)
            }
            if deal.bellaAnnounced, decl.bellaSeat == seat, let trump = deal.trump {
                items.append(.bella(trump))
            }
        }
        return items
    }

    /// Свои взятки и очки в сдаче (если включено в настройках).
    private var livePoints: HumanStrip.Live? {
        guard store.settings.showLivePoints, deal.trump != nil else { return nil }
        switch deal.phase {
        case .playing, .finished:
            break
        default:
            return nil
        }
        let seat = store.humanSeat
        let tricks = deal.tricksTaken[seat]
        var points = deal.cardPoints[seat]
        if let decl = deal.declarations {
            // Как при подсчёте: комбинации и бэла пишутся, если взята взятка (или правила не требуют).
            let rules = match.rules
            if rules.combosNeedTrick != .all || tricks > 0 {
                points += decl.meldPoints(for: seat, rules: rules)
            }
            if deal.bellaAnnounced, decl.bellaSeat == seat, rules.combosNeedTrick == .none || tricks > 0 {
                points += rules.bellaPoints
            }
        }
        return HumanStrip.Live(tricks: tricks, points: points)
    }

    private var centerDescription: String {
        if case .bidding = deal.phase {
            return "Открытая карта: \(CardView.spokenName(deal.openCard))"
        }
        let trick = store.displayedTrick ?? deal.currentTrick
        guard !trick.plays.isEmpty else { return "Стол пуст" }
        let cards = trick.plays.map { "\(store.displayName(for: $0.seat)) — \(CardView.spokenName($0.card))" }
        var text = "На столе: " + cards.joined(separator: ", ")
        if let displayed = store.displayedTrick, let winner = displayed.winner {
            text += winner == store.humanSeat ? ". Взятка ваша" : ". Взятку берёт \(store.displayName(for: winner))"
            if TableScene.isLastTrick(displayed, of: deal) {
                text += ", последняя — плюс 10 очков"
            }
        }
        return text
    }

    /// `-DebercDragPreview`: в свой ход первая допустимая карта — «в пальцах» (для снимков).
    private var previewDrag: HandDrag? {
        guard LaunchOptions.current.dragPreview, store.isHumanTurn, deal.phase == .playing,
              let card = deal.hands[store.humanSeat].sortedForDisplay(trump: deal.trump)
                .first(where: { store.legalCards.contains($0) }) else { return nil }
        return HandDrag(card: card, translation: CGSize(width: 36, height: -150), playable: true)
    }

    private var layerModel: TableLayerModel {
        let scene = TableScene(
            deal: deal,
            dealKey: match.dealCount,
            humanSeat: store.humanSeat,
            displayedTrick: store.displayedTrick,
            selected: store.selectedCard,
            legal: store.legalCards,
            humanActive: store.isHumanTurn && deal.phase == .playing,
            reduceMotion: reduceMotion,
            metrics: metrics,
            drag: drag ?? previewDrag)
        var declared: [Int: [DeclItem]] = [:]
        for seat in 0..<match.playerCount where seat != store.humanSeat {
            let items = declarations(seat)
            if !items.isEmpty { declared[seat] = items }
        }
        return TableLayerModel(
            scene: scene,
            flight: store.settings.speed.cardFlight,
            names: (0..<match.playerCount).map { store.displayName(for: $0) },
            bubbles: store.bubbles,
            declarations: declared,
            rules: match.rules,
            banner: store.showDealSummary ? nil : store.banner,
            bannerUrgent: store.bannerIsUrgent,
            freshDeal: !deal.prikupDealt && deal.tricks.isEmpty && !deal.isFinished && !reduceMotion,
            dealNumber: match.dealCount,
            target: match.rules.targetScore,
            announcement: store.showDealSummary ? nil : store.announcement,
            taunt: store.showDealSummary ? nil : store.taunt,
            humanSeat: store.humanSeat)
    }
}

/// Переводит якоря мест в кадры и рисует слой карт.
private struct TableLayerHost: View {
    let anchors: [TableSlot: Anchor<CGRect>]
    let model: TableLayerModel

    var body: some View {
        GeometryReader { proxy in
            TableLayer(model: model, frames: resolve(proxy), size: proxy.size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func resolve(_ proxy: GeometryProxy) -> [TableSlot: CGRect] {
        var frames: [TableSlot: CGRect] = [:]
        for (slot, anchor) in anchors {
            frames[slot] = proxy[anchor]
        }
        return frames
    }
}
