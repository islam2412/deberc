import SwiftUI
import DebercKit

/// Панель над рукой: кнопки торговли и обмена семёрки, «Ваш ход», совет (во всех фазах), отмена хода;
/// когда ходят соперники — кто ходит и чего ждать.
struct ActionPanel: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.cardAppearance) private var appearance
    let match: Match
    let deal: Deal
    let metrics: TableMetrics

    var body: some View {
        let contentWidth: CGFloat = metrics.roomy ? 720 : .infinity
        Group {
            if store.showDealSummary {
                Color.clear.frame(height: 1)
            } else if store.isHumanTurn {
                humanControls
                    .transition(Self.swap)
            } else {
                waitingLine
                    .transition(Self.swap)
            }
        }
        .frame(maxWidth: contentWidth)
        .frame(maxWidth: .infinity)
        .frame(minHeight: metrics.actionMinHeight)
        .padding(.horizontal, metrics.gutter)
    }

    /// Смена содержимого панели: старое исчезает сразу, новое проявляется — надписи не наезжают
    /// друг на друга («Ваш ход» поверх «Ходит Саша…»).
    static let swap = AnyTransition.asymmetric(insertion: .opacity, removal: .identity)

    // MARK: - Ход человека

    @ViewBuilder
    private var humanControls: some View {
        switch deal.phase {
        case .bidding(let round):
            if round == 1 {
                roundOne
            } else {
                roundTwo
            }
        case .exchange:
            exchange
        case .playing:
            playing
        case .finished:
            Color.clear.frame(height: 1)
        }
    }

    private var roundOne: some View {
        let suit = deal.openCard.suit
        return VStack(spacing: 6) {
            // Слово «Беру» не должно пропадать: на узком экране с крупным шрифтом сначала уходит
            // название масти, потом «Пас» с подсказкой переезжают во второй ряд.
            // В ряду «Беру» забирает всё свободное место, «Пас» — по ширине слова: поровну делить нельзя,
            // иначе длинная надпись «Беру ♣ трефы» обрезается, хотя ряд целиком помещается.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    takeButton(suit, named: true)
                    passButton(fill: false)
                    hintButton
                }
                HStack(spacing: 10) {
                    takeButton(suit, named: false)
                    passButton(fill: false)
                    hintButton
                }
                VStack(spacing: 8) {
                    takeButton(suit, named: true)
                    HStack(spacing: 10) {
                        passButton()
                        hintButton
                    }
                }
            }
            prompt(store.bidHint ?? "Берёте? Козырь — \(suit.name)")
        }
    }

    private func takeButton(_ suit: Suit, named: Bool) -> some View {
        Button {
            store.perform(.take)
        } label: {
            HStack(spacing: 6) {
                Text("Беру")
                SuitBadge(suit: suit, size: 24)
                if named {
                    Text(suit.name)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TableButtonStyle(prominent: true))
        .modifier(HintRing(active: store.hintAction == .take))
        .accessibilityLabel("Беру, козырь \(suit.name)")
    }

    private var roundTwo: some View {
        let suits = Suit.allCases.filter { $0 != deal.openCard.suit }
        return VStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(suits, id: \.self) { suit in
                        suitButton(suit)
                    }
                    passButton()
                    hintButton
                }
                .fixedSize(horizontal: true, vertical: false)
                HStack(spacing: 10) {
                    suitGrid(suits)
                    hintButton
                }
                // Узкий экран с крупным текстом: мастям — вся ширина; подсказка остаётся в меню стола
                // (лишний ряд кнопок сжал бы стол так, что открытая карта стала бы с ноготь).
                suitGrid(suits)
            }
            // Что делать во 2-м круге, сказано под открытой картой; здесь — только совет.
            if let hint = store.bidHint {
                prompt(hint)
            }
        }
    }

    @ViewBuilder
    private func suitGrid(_ suits: [Suit]) -> some View {
        if suits.count == 3 {
            Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    suitButton(suits[0])
                    suitButton(suits[1])
                }
                GridRow {
                    suitButton(suits[2])
                    passButton()
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(suits, id: \.self) { suit in
                    suitButton(suit)
                }
                passButton()
            }
        }
    }

    private func suitButton(_ suit: Suit) -> some View {
        Button {
            store.perform(.name(suit))
        } label: {
            HStack(spacing: 8) {
                SuitBadge(suit: suit, size: 26)
                Text(TableText.suitTitle(suit))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TableButtonStyle())
        .modifier(HintRing(active: store.hintAction == .name(suit)))
        .accessibilityLabel("Козырь \(suit.name)")
    }

    /// `fill` — растягиваться на свободное место (в сетке мастей и во втором ряду); иначе — по ширине слова.
    private func passButton(fill: Bool = true) -> some View {
        Button {
            store.perform(.pass)
        } label: {
            Text("Пас")
                .lineLimit(1)
                .frame(minWidth: 44)
                .frame(maxWidth: fill ? .infinity : nil)
        }
        .buttonStyle(TableButtonStyle())
        .modifier(HintRing(active: store.hintAction == .pass))
    }

    private var exchange: some View {
        VStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    exchangeButton
                    keepButton(fill: false)
                    exchangeTools
                }
                // Тесно — «Взять … за 7» во всю ширину, остальное — вторым рядом.
                VStack(spacing: 8) {
                    exchangeButton
                    HStack(spacing: 10) {
                        keepButton()
                        exchangeTools
                    }
                }
            }
            prompt(store.bidHint ?? "У вас козырная семёрка — поменять на открытую карту?")
        }
    }

    private var exchangeButton: some View {
        let open = deal.openCard
        return Button {
            store.perform(.exchangeSeven(true))
        } label: {
            HStack(spacing: 6) {
                Text("Взять")
                MiniTile(card: open, height: 28)
                Text("за 7")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TableButtonStyle(prominent: true))
        .modifier(HintRing(active: store.hintAction == .exchangeSeven(true)))
        .accessibilityLabel("Поменять козырную семёрку на \(CardView.spokenName(open))")
    }

    private func keepButton(fill: Bool = true) -> some View {
        Button {
            store.perform(.exchangeSeven(false))
        } label: {
            Text("Оставить")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: fill ? .infinity : nil)
        }
        .buttonStyle(TableButtonStyle())
        .modifier(HintRing(active: store.hintAction == .exchangeSeven(false)))
        .accessibilityLabel("Оставить семёрку")
    }

    /// Отмена ошибочного «Беру» (значком — ряд и так тесный) и подсказка.
    @ViewBuilder
    private var exchangeTools: some View {
        if store.canUndo {
            undoButton(compact: true)
        }
        hintButton
    }

    private var playing: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ваш ход")
                    .font(Theme.Typography.seatName)
                    .foregroundStyle(Theme.gold)
                if let subtitle = playSubtitle {
                    Text(suited(subtitle))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.tableSecondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.identity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Строки меняются сразу, без анимации сдвига: иначе заголовок на миг наезжает на подпись.
            .transaction { $0.animation = nil }
            if store.canUndo {
                undoButton()
            }
            hintButton
        }
    }

    private var playSubtitle: String? {
        if store.selectedCard != nil && store.settings.confirmCardTap {
            return "Коснитесь ещё раз или бросьте её вверх"
        }
        if let lead = deal.currentTrick.plays.first, lead.seat != store.humanSeat {
            // Втроём на столе две карты — какая из них заход, видно не сразу.
            return "Заход: \(store.displayName(for: lead.seat)), " + TableText.short(lead.card)
        }
        return store.settings.confirmCardTap
            ? "Коснитесь или бросьте карту вверх"
            : "Коснитесь карты — сразу ход"
    }

    private var hintButton: some View {
        Button {
            store.showHint()
        } label: {
            ZStack {
                Image(systemName: "lightbulb")
                    .opacity(store.isHinting ? 0 : 1)
                if store.isHinting {
                    ProgressView()
                        .tint(Theme.tableText)
                }
            }
            .frame(minWidth: 24)
        }
        .buttonStyle(TableButtonStyle(compact: true))
        .disabled(store.isHinting)
        .accessibilityLabel("Подсказка")
    }

    /// «Отменить» — словом, если помещается; `compact` — всегда значком.
    private func undoButton(compact: Bool = false) -> some View {
        Button {
            store.undo()
        } label: {
            if compact {
                Image(systemName: "arrow.uturn.backward")
                    .frame(minWidth: 24)
            } else {
                ViewThatFits(in: .horizontal) {
                    Label("Отменить", systemImage: "arrow.uturn.backward")
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: "arrow.uturn.backward")
                }
            }
        }
        .buttonStyle(TableButtonStyle(compact: compact))
        .accessibilityLabel("Отменить ход")
    }

    // MARK: - Ждём соперников

    private var waitingLine: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let title = waitingTitle {
                    Text(title)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.tableText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.identity)
                        .transition(.identity)
                }
                if let subtitle = waitingSubtitle {
                    Text(suited(subtitle))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.tableSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.identity)
                        .transition(.identity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transaction { $0.animation = nil }
            if store.canUndo {
                undoButton()
            }
        }
    }

    private var waitingTitle: String? {
        let human = store.humanSeat
        if let trick = store.displayedTrick, let winner = trick.winner {
            return winner == human ? "Ваша взятка" : "Взятку берёт \(store.displayName(for: winner))"
        }
        guard let actor = deal.actor, actor != human else { return nil }
        let name = store.displayName(for: actor)
        return store.thinkingSeat == actor ? "\(name) думает…" : "Ходит \(name)…"
    }

    private var waitingSubtitle: String? {
        if store.displayedTrick != nil {
            return "Коснитесь стола, чтобы собрать"
        }
        switch deal.phase {
        case .bidding, .exchange:
            if let own = store.bubbles[store.humanSeat] {
                return "Вы: " + own
            }
            return nil
        default:
            return nil
        }
    }

    /// Масти в подписях панели — своим цветом.
    private func suited(_ text: String) -> AttributedString {
        TableText.styled(text, onLight: false, fourColor: appearance.fourColor)
    }

    private func prompt(_ text: String) -> some View {
        Text(suited(text))
            .font(Theme.Typography.caption)
            .foregroundStyle(store.bidHint != nil ? Theme.gold : Theme.tableSecondaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }
}

/// Золотое кольцо вокруг кнопки, которую советует подсказка.
struct HintRing: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.gold, lineWidth: 3)
                    .padding(-4)
                    .allowsHitTesting(false)
            }
        }
    }
}
