import SwiftUI
import UIKit
import DebercKit

/// Игровой стол.
struct GameView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showScoreSheet = false
    @State private var showRules = false
    @State private var confirmLeave = false

    var body: some View {
        GeometryReader { geo in
            let cardWidth = handCardWidth(geo.size)
            let isLarge = isLargeScreen(geo.size)
            ZStack {
                FeltBackground()
                if let match = store.match, let deal = match.deal {
                    table(match: match, deal: deal, size: geo.size, cardWidth: cardWidth)
                } else {
                    ProgressView().tint(.white)
                }

                VStack {
                    if let banner = store.banner {
                        BannerView(text: banner)
                            .id(banner)
                            .padding(.top, geo.size.height * 0.2)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.25), value: store.banner)

                if store.showDealSummary, let match = store.match {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    DealSummaryView(match: match, maxHeight: geo.size.height - 40, maxWidth: isLarge ? 720 : 560)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: store.showDealSummary)
            // На iPad текст крупнее; на iPhone ограничиваем, чтобы не ломалась раскладка стола.
            .dynamicTypeSize(isLarge ? max(dynamicTypeSize, .xxxLarge) : min(dynamicTypeSize, .xxLarge))
        }
        .sheet(isPresented: $showScoreSheet) {
            if let match = store.match {
                ScoreSheetView(match: match, humanSeat: store.humanSeat)
            }
        }
        .sheet(isPresented: $showRules) {
            RulesView(rules: store.match?.rules ?? store.settings.rules)
        }
        .confirmationDialog("Выйти в меню?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Выйти (партия сохранится)") { store.leaveGame() }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func isLargeScreen(_ size: CGSize) -> Bool {
        min(size.width, size.height) >= 600
    }

    /// Ширина карты на руке — под размер экрана.
    private func handCardWidth(_ size: CGSize) -> CGFloat {
        let byWidth = (size.width - 24) / 4.6
        let byHeight = size.height / 5.6
        let limit: CGFloat = isLargeScreen(size) ? 170 : 110
        return max(44, min(limit, min(byWidth, byHeight)))
    }

    private func table(match: Match, deal: Deal, size: CGSize, cardWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            topBar(match: match, deal: deal)
            opponentsRow(match: match, deal: deal, cardWidth: cardWidth * 0.5)
            center(match: match, deal: deal, cardWidth: cardWidth)
            actionPanel(match: match, deal: deal)
                .frame(minHeight: 52)
                .padding(.horizontal, 12)
            hand(deal: deal, cardWidth: cardWidth)
        }
    }

    private func opponentsRow(match: Match, deal: Deal, cardWidth: CGFloat) -> some View {
        let human = store.humanSeat
        let opponents = (1..<match.playerCount).map { (human + $0) % match.playerCount }
        return HStack(alignment: .top) {
            ForEach(opponents, id: \.self) { seat in
                if seat != opponents.first {
                    Spacer()
                }
                OpponentView(
                    name: match.names[seat],
                    cardCount: deal.hands[seat].count,
                    bubble: store.bubbles[seat],
                    isThinking: store.thinkingSeat == seat,
                    cardWidth: cardWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func center(match: Match, deal: Deal, cardWidth: CGFloat) -> some View {
        let trick: Trick = store.displayedTrick ?? deal.currentTrick
        let bottom: Card? = deal.bottomCardVisible ? deal.bottomCard : nil
        return ZStack {
            TrickView(
                plays: trick.plays,
                winner: store.displayedTrick?.winner,
                playerCount: match.playerCount,
                humanSeat: store.humanSeat,
                cardWidth: cardWidth * 0.95)

            if deal.phase != .finished {
                let isBidding: Bool = {
                    if case .bidding = deal.phase { return true }
                    return false
                }()
                HStack {
                    DeckView(openCard: deal.openCard, bottomCard: bottom, showsStock: true,
                             cardWidth: cardWidth * (isBidding ? 0.85 : 0.62))
                    Spacer()
                }
                .padding(.leading, 12)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hand(deal: Deal, cardWidth: CGFloat) -> some View {
        HandView(
            cards: deal.hands[store.humanSeat].sortedForDisplay(trump: deal.trump),
            legal: store.legalCards,
            isActive: store.isHumanTurn && deal.phase == .playing,
            selected: store.selectedCard,
            cardWidth: cardWidth,
            onTap: { store.tapCard($0) })
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
    }

    // MARK: - Верхняя панель

    private func topBar(match: Match, deal: Deal) -> some View {
        HStack(spacing: 8) {
            Menu {
                Button { showScoreSheet = true } label: { Label("Запись партии", systemImage: "list.number") }
                Button { showRules = true } label: { Label("Правила", systemImage: "book") }
                Button { store.showHint() } label: { Label("Подсказка", systemImage: "lightbulb") }
                Divider()
                Button { confirmLeave = true } label: { Label("Выйти в меню", systemImage: "house") }
            } label: {
                Image(systemName: "line.3.horizontal.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<match.playerCount, id: \.self) { seat in
                        ScoreChip(
                            name: match.names[seat],
                            score: match.totals[seat],
                            isDealer: deal.dealer == seat,
                            isBidder: deal.bidder == seat,
                            trump: deal.trump,
                            isActive: deal.actor == seat)
                    }
                }
            }

            Spacer(minLength: 0)

            if let trump = deal.trump {
                VStack(spacing: 0) {
                    Text("козырь")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(trump.glyph)
                        .font(.system(size: 30))
                        .foregroundStyle(trump.tableColor)
                }
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Панель действий

    @ViewBuilder
    private func actionPanel(match: Match, deal: Deal) -> some View {
        let human = store.humanSeat
        if store.isHumanTurn {
            switch deal.phase {
            case .bidding(let round):
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        if round == 1 {
                            Button("Беру \(deal.openCard.suit.glyph)") { store.perform(.take) }
                                .buttonStyle(TableButtonStyle(prominent: true))
                        } else {
                            ForEach(Suit.allCases.filter { $0 != deal.openCard.suit }, id: \.self) { suit in
                                Button {
                                    store.perform(.name(suit))
                                } label: {
                                    Text(suit.glyph)
                                        .font(.system(size: 26))
                                        .foregroundStyle(suit.isRed ? Theme.red : Color.black)
                                        .frame(minWidth: 34)
                                }
                                .buttonStyle(TableButtonStyle(prominent: true))
                            }
                        }
                        Button("Пас") { store.perform(.pass) }
                            .buttonStyle(TableButtonStyle())
                    }
                    Text(store.bidHint ?? (round == 1 ? "Играете на \(Narrator.suitTitle(deal.openCard.suit))?" : "Назовите козырь или пас"))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
            case .exchange:
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Button("Поменять 7 на \(deal.openCard.rank.symbol)\(deal.openCard.suit.glyph)") {
                            store.perform(.exchangeSeven(true))
                        }
                        .buttonStyle(TableButtonStyle(prominent: true))
                        Button("Оставить") { store.perform(.exchangeSeven(false)) }
                            .buttonStyle(TableButtonStyle())
                    }
                    Text("У вас козырная семёрка")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
            case .playing:
                HStack(spacing: 12) {
                    Text(store.selectedCard == nil || !store.settings.confirmCardTap
                         ? "Ваш ход"
                         : "Коснитесь карты ещё раз, чтобы сходить")
                        .font(.headline)
                        .foregroundStyle(Theme.gold)
                    Button {
                        store.showHint()
                    } label: {
                        Image(systemName: "lightbulb")
                    }
                    .buttonStyle(TableButtonStyle())
                }
            case .finished:
                EmptyView()
            }
        } else if let actor = deal.actor, actor != human, store.displayedTrick == nil {
            Text("Ходит \(match.names[actor])…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        } else {
            Color.clear.frame(height: 1)
        }
    }
}
