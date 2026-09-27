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
    @State private var confirmLeave = false

    var body: some View {
        GeometryReader { geo in
            content(size: geo.size)
        }
        .cardAppearance(fourColor: store.settings.fourColorDeck, largeIndex: store.settings.largeCards)
        .environment(\.tableLargeControls, store.settings.largeCards)
        // Рука лежит у нижнего края: жест «Домой» — только со второго смахивания.
        .defersSystemGestures(on: .bottom)
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
            // Пока открыт лист или диалог, игра на паузе: соперники не ходят, сообщения ждут.
            store.isOverlayPresented = open
        }
        .onChange(of: store.isHumanTurn) { mine in
            if mine && UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Ваш ход")
            }
        }
        .onChange(of: store.lastTrick == nil) { noTrick in
            if noTrick { showLastTrick = false }
        }
        .onAppear(perform: openRequestedScreen)
        .onDisappear {
            if store.isOverlayPresented { store.isOverlayPresented = false }
        }
    }

    private var overlayOpen: Bool {
        showScoreSheet || showRules || showSettings || showLastTrick || confirmLeave
    }

    private var commands: TableCommands {
        TableCommands(
            showScoreSheet: { showScoreSheet = true },
            showRules: { showRules = true },
            showSettings: { showSettings = true },
            showLastTrick: { showLastTrick = true },
            leave: { confirmLeave = true })
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        let players = store.match?.playerCount ?? store.settings.playerCount
        let metrics = TableMetrics(size: size, playerCount: players, large: store.settings.largeCards)
        ZStack {
            FeltBackground()
            if let match = store.match, let deal = match.deal {
                TableScreen(match: match, deal: deal, metrics: metrics, commands: commands)
            } else {
                ProgressView()
                    .tint(Theme.tableText)
            }
            if store.showDealSummary, let match = store.match {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(3)
                DealSummaryView(match: match, maxHeight: size.height - 40, maxWidth: metrics.roomy ? 640 : 560)
                    .frame(width: size.width, height: size.height)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(4)
                summaryMenu(metrics: metrics)
                    .transition(.opacity)
                    .zIndex(5)
            }
            if showLastTrick, let trick = store.lastTrick {
                LastTrickPanel(trick: trick, names: displayNames, cardWidth: min(110, metrics.handCardWidth),
                               onClose: { showLastTrick = false })
                    .transition(.opacity)
                    .zIndex(6)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.showDealSummary)
        .animation(.easeInOut(duration: 0.2), value: showLastTrick)
        .dynamicTypeSize(TableMetrics.typeSize(system: systemTypeSize, size: size, large: store.settings.largeCards))
        .statusBarHidden(!metrics.roomy)
    }

    private var displayNames: [String] {
        let count = store.match?.playerCount ?? 0
        return (0..<count).map { store.displayName(for: $0) }
    }

    /// Кнопка меню поверх окна итогов — на том же месте, что и в верхней полосе:
    /// между сдачами можно открыть запись партии, настройки или выйти.
    private func summaryMenu(metrics: TableMetrics) -> some View {
        VStack(spacing: 0) {
            HStack {
                TableMenuButton(commands: commands, inSummary: true, size: metrics.roomy ? 50 : 44)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.gutter)
            .frame(height: metrics.topBarHeight)
            Spacer(minLength: 0)
        }
    }

    /// `-DebercScreen scoresheet` (скриншоты CI): сразу открыть запись партии.
    private func openRequestedScreen() {
        guard store.requestedScreen == "scoresheet" else { return }
        store.requestedScreen = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            showScoreSheet = true
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
    }

    // MARK: Колонка стола

    private var tableColumn: some View {
        VStack(spacing: metrics.spacing) {
            TableTopBar(match: match, deal: deal, metrics: metrics, commands: commands)
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
    }

    private var leftSeat: Int { (store.humanSeat + 1) % match.playerCount }
    private var rightSeat: Int { (store.humanSeat + 2) % match.playerCount }

    @ViewBuilder
    private var opponentsRow: some View {
        if match.playerCount == 2 {
            SeatRow(info: seatInfo(leftSeat), metrics: metrics, commands: commands,
                    canShowLastTrick: store.lastTrick != nil)
                .padding(.horizontal, metrics.gutter)
        } else {
            HStack(alignment: .top, spacing: 12) {
                SeatStack(info: seatInfo(leftSeat), metrics: metrics, commands: commands,
                          canShowLastTrick: store.lastTrick != nil, leading: true)
                Spacer(minLength: 0)
                SeatStack(info: seatInfo(rightSeat), metrics: metrics, commands: commands,
                          canShowLastTrick: store.lastTrick != nil, leading: false)
            }
            .padding(.horizontal, metrics.gutter)
        }
    }

    /// Центр стола: взятка (касание собирает показанную взятку), во время торговли — открытая карта.
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
            .accessibilityAction(named: "Собрать взятку") {
                store.collectTrick()
            }
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
                        selected: store.selectedCard)
            .frame(maxWidth: maxWidth)
            .tableSlot(.hand)
            .padding(.horizontal, metrics.gutter)
            .padding(.bottom, 4)
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
        if let winner = store.displayedTrick?.winner {
            text += ". Взятку берёт \(store.displayName(for: winner))"
        }
        return text
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
            metrics: metrics)
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
            freshDeal: !deal.prikupDealt && deal.tricks.isEmpty && !deal.isFinished && !reduceMotion)
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
