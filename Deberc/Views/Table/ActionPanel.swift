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
        // Зазор до руки: касание чуть выше поднятой карты не должно попадать в «Отменить» или «Совет».
        .padding(.bottom, metrics.roomy ? 0 : 8)
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
            // Слово «Беру» не должно пропадать: на узком экране с крупным шрифтом сначала лампочка
            // теряет подпись, потом уходит название масти, потом «Пас» с подсказкой переезжают во второй ряд.
            // В ряду «Беру» забирает всё свободное место, «Пас» — по ширине слова: поровну делить нельзя,
            // иначе длинная надпись «Беру ♣ трефы» обрезается, хотя ряд целиком помещается.
            ViewThatFits(in: .horizontal) {
                takeRow(suit, named: true, hint: .captioned)
                takeRow(suit, named: true, hint: .icon)
                takeRow(suit, named: false, hint: .icon)
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

    private func takeRow(_ suit: Suit, named: Bool, hint look: HintLook) -> some View {
        HStack(spacing: 10) {
            takeButton(suit, named: named)
            passButton(fill: false)
            hintButton(look)
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
                suitRow(suits, hint: .captioned)
                suitRow(suits, hint: .icon)
                HStack(spacing: 10) {
                    suitGrid(suits)
                    hintButton
                }
                HStack(spacing: 10) {
                    suitGrid(suits)
                    hintButton(.icon)
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

    private func suitRow(_ suits: [Suit], hint look: HintLook) -> some View {
        HStack(spacing: 10) {
            ForEach(suits, id: \.self) { suit in
                suitButton(suit)
            }
            passButton()
            hintButton(look)
        }
        .fixedSize(horizontal: true, vertical: false)
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
                exchangeRow(hint: .captioned)
                exchangeRow(hint: .icon)
                // Тесно — «Взять … за 7» во всю ширину, остальное — вторым рядом.
                VStack(spacing: 8) {
                    exchangeButton
                    HStack(spacing: 10) {
                        keepButton()
                        hintButton
                    }
                }
            }
            prompt(store.bidHint ?? "У вас козырная семёрка — поменять на открытую карту?")
        }
    }

    private func exchangeRow(hint look: HintLook) -> some View {
        HStack(spacing: 10) {
            exchangeButton
            keepButton(fill: false)
            hintButton(look)
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
        .accessibilityLabel("Взять \(CardView.spokenName(open)) за козырную семёрку")
        .accessibilityInputLabels(["Взять", "Поменять"])
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

    private var playing: some View {
        HStack(spacing: 10) {
            statusLines(title: "Ваш ход", titleColor: Theme.gold, subtitle: playSubtitle)
            if store.canUndo {
                undoButton()
            }
            hintButton(.labeled)
        }
    }

    /// Заголовок и подпись в две строки — одинаковой высоты и в «Ваш ход», и в «Ходит Саша…»:
    /// иначе при каждой смене хода стол над панелью подскакивает на несколько точек.
    private func statusLines(title: String?, titleColor: Color, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title ?? " ")
                .font(Theme.Typography.seatName)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(title == nil)
            Text(suited(subtitle ?? " "))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.tableSecondaryText)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(Narrator.spoken(subtitle ?? ""))
                .accessibilityHidden(subtitle == nil)
        }
        .contentTransition(.identity)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Строки меняются сразу, без анимации сдвига: иначе заголовок на миг наезжает на подпись.
        .transaction { $0.animation = nil }
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

    /// Вид кнопки совета: словом, значком с подписью (тесные ряды торговли) или одним значком
    /// (совсем тесно — лишь бы «Беру ♣ трефы» и ряд в одну строку уцелели).
    private enum HintLook {
        case labeled, captioned, icon
    }

    private var hintButton: some View { hintButton(.captioned) }

    /// «Совет»: словом, если в ряду есть место; в рядах торговли — значком с подписью.
    private func hintButton(_ look: HintLook) -> some View {
        Button {
            store.showHint()
        } label: {
            ZStack {
                Group {
                    switch look {
                    case .labeled:
                        ViewThatFits(in: .horizontal) {
                            Label("Совет", systemImage: "lightbulb")
                                .lineLimit(1)
                                .fixedSize()
                            Image(systemName: "lightbulb")
                        }
                    case .captioned:
                        captionedLightbulb
                    case .icon:
                        Image(systemName: "lightbulb")
                    }
                }
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
        .accessibilityLabel("Совет")
        .accessibilityInputLabels(["Совет", "Подсказка"])
    }

    /// Лампочка с мелкой подписью «совет»: один значок непонятен. Место в ряду — как у одного значка
    /// (по ширине подписи): подпись уходит в поля кнопки, и ряд торговли не становится выше.
    private var captionedLightbulb: some View {
        ZStack {
            Image(systemName: "lightbulb")
            Text("совет")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .hidden()
        .overlay {
            VStack(spacing: 0) {
                Image(systemName: "lightbulb")
                Text("совет")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize()
        }
    }

    /// «Отменить» — словом, если помещается, иначе значком.
    private func undoButton() -> some View {
        Button {
            store.undo()
        } label: {
            ViewThatFits(in: .horizontal) {
                Label("Отменить", systemImage: "arrow.uturn.backward")
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "arrow.uturn.backward")
            }
        }
        .buttonStyle(TableButtonStyle())
        .accessibilityLabel("Отменить ход")
    }

    // MARK: - Ждём соперников

    private var waitingLine: some View {
        HStack(spacing: 10) {
            statusLines(title: waitingTitle, titleColor: Theme.tableText, subtitle: waitingSubtitle)
            if store.canUndo {
                undoButton()
            }
        }
    }

    private var waitingTitle: String? {
        let human = store.humanSeat
        // Кто взял — написано золотом на самой карте (с «+10» за последнюю); здесь — что будет дальше.
        if store.displayedTrick != nil {
            return "Взятка соберётся сама"
        }
        guard let actor = deal.actor, actor != human else { return nil }
        let name = store.displayName(for: actor)
        return store.thinkingSeat == actor ? "\(name) думает…" : "Ходит \(name)…"
    }

    private var waitingSubtitle: String? {
        if store.displayedTrick != nil {
            return "Коснитесь стола — быстрее"
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
            .accessibilityLabel(Narrator.spoken(text))
            .font(Theme.Typography.caption)
            .foregroundStyle(store.bidHint != nil ? Theme.gold : Theme.tableSecondaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }
}

/// Золотое кольцо вокруг кнопки, которую советует подсказка — по форме кнопки (в крупном режиме она круглее).
struct HintRing: ViewModifier {
    let active: Bool
    @Environment(\.tableLargeControls) private var large

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                RoundedRectangle(cornerRadius: (large ? 16 : 14) + 4, style: .continuous)
                    .strokeBorder(Theme.gold, lineWidth: 3)
                    .padding(-4)
                    .allowsHitTesting(false)
            }
        }
    }
}
