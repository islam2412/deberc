import SwiftUI
import DebercKit

/// Конец партии: победа или поражение, итоговые места, как прошла партия, «Реванш».
///
/// Показывается поверх стола (`RootView`), когда партия окончена и итоги открыты.
/// Победа — золотой кубок и «дождь» из мастей (без него при «Уменьшении движения»).
struct MatchOverView: View {
    @EnvironmentObject private var store: GameStore
    let match: Match

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var showScoreSheet = false
    @State private var showLastDeal = false
    /// «Как прошла партия» открыта или свёрнута; nil — как принято для высоты экрана.
    @State private var showFacts: Bool?

    private var seats: SeatNames { SeatNames(names: match.names, humanSeat: store.humanSeat) }
    private var humanWon: Bool { match.winner == store.humanSeat }

    /// Места по убыванию очков (при равенстве — по порядку мест).
    private var standings: [Int] {
        match.totals.indices.sorted { a, b in
            match.totals[a] != match.totals[b] ? match.totals[a] > match.totals[b] : a < b
        }
    }

    var body: some View {
        ZStack {
            FeltBackground()
            GeometryReader { screen in
                let large = min(screen.size.width, screen.size.height) >= 600
                let narrow = screen.size.width < 360
                let width: CGFloat = large ? 620 : 520
                // Невысокий экран — «Как прошла партия» сначала свёрнута, как «Последняя сдача».
                let factsOpen = showFacts ?? (screen.size.height >= 760)
                // Кнопки не прокручиваются: «Реванш» виден сразу, итоги прокручиваются над ними.
                // Карточка растягивается на высоту над кнопками — на iPad лишней прокрутки нет.
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        ScrollView {
                            card(narrow: narrow, factsOpen: factsOpen)
                                .frame(maxWidth: width)
                                .padding(.horizontal, narrow ? 10 : 16)
                                .padding(.top, 24)
                                .padding(.bottom, 28)
                                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .bottomFade()
                    }
                    buttons
                        .frame(maxWidth: width)
                        .padding(.horizontal, narrow ? 10 : 16)
                        .padding(.bottom, 8)
                }
                // На узком экране таблица и кнопки со словами целиком помещаются только до этого размера.
                .dynamicTypeSize(...(narrow ? DynamicTypeSize.xxxLarge : DynamicTypeSize.accessibility3))
            }
            if humanWon && !reduceMotion {
                ConfettiView()
                    .ignoresSafeArea()
            }
        }
        .adaptiveTextSize(.screen)
        .accessibilityAddTraits(.isModal)
        .sheet(isPresented: $showScoreSheet) {
            ScoreSheetView(match: match, humanSeat: store.humanSeat)
        }
        .pausesGame(while: showScoreSheet)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.15)) { appeared = true }
            }
        }
    }

    private func card(narrow: Bool, factsOpen: Bool) -> some View {
        VStack(spacing: 20) {
            header
            standingsList
            factsSection(narrow: narrow, isOpen: factsOpen)
            adviceSection
            lastDealSection
        }
        .padding(narrow ? 14 : 22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(ScreenStyle.cardFill)
                .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.gold.opacity(humanWon ? 0.8 : 0.4), lineWidth: humanWon ? 2 : 1))
        .foregroundStyle(Theme.tableText)
    }

    // MARK: - Заголовок

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: humanWon ? "trophy.fill" : "flag.checkered")
                .font(.system(size: humanWon ? 64 : 48, weight: .semibold))
                .foregroundStyle(humanWon ? Theme.gold : Theme.tableSecondaryText)
                .shadow(color: humanWon ? Theme.gold.opacity(0.5) : Color.clear, radius: 12)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
            Text(humanWon ? "Победа!" : "Партия окончена")
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(humanWon ? Theme.gold : Theme.tableText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.headline)
                .foregroundStyle(Theme.tableSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        guard let winner = match.winner else { return "" }
        let others = standings.filter { $0 != winner }
        let second = others.first.map { match.totals[$0] } ?? 0
        let margin = match.totals[winner] - second
        if winner == store.humanSeat {
            return "Вы набрали \(Narrator.number(match.totals[winner])) — отрыв \(Narrator.points(margin))"
        }
        let name = store.displayName(for: winner)
        let verb = store.persona(for: winner)?.feminine == true ? "выиграла" : "выиграл"
        return "\(name) \(verb) партию: \(Narrator.points(match.totals[winner])) против ваших \(Narrator.number(match.totals[store.humanSeat]))"
    }

    // MARK: - Места

    private var standingsList: some View {
        VStack(spacing: 10) {
            ForEach(Array(standings.enumerated()), id: \.element) { place, seat in
                standingRow(place: place + 1, seat: seat)
            }
        }
    }

    private func standingRow(place: Int, seat: Int) -> some View {
        let total = match.totals[seat]
        let isWinner = seat == match.winner
        return HStack(spacing: 12) {
            StandingPlaceBadge(place: place)
            PlayerAvatarView(persona: store.persona(for: seat), humanName: match.names[seat], size: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(seats.column(seat))
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Narrator.number(total))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(isWinner ? Theme.gold : Theme.tableText)
                }
                GoalProgressBar(value: total, target: match.rules.targetScore,
                                  tint: isWinner ? Theme.gold : Theme.tableSecondaryText.opacity(0.8), height: 7)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isWinner ? Theme.gold.opacity(0.14) : Color.black.opacity(0.2)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place)-е место: \(seats.column(seat)), \(Narrator.points(total))")
    }

    // MARK: - Как прошла партия

    private func factsSection(narrow: Bool, isOpen: Bool) -> some View {
        let played = match.history.filter { $0.wasPlayed }
        let redeals = match.history.count - played.count
        let count = redeals > 0
            ? "\(RuPlural.count(played.count, "сдача", "сдачи", "сдач")), пересдач \(redeals)"
            : RuPlural.count(played.count, "сдача", "сдачи", "сдач")
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showFacts = !isOpen }
            } label: {
                HStack(spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            factsTitle
                            Spacer()
                            factsCount(count)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            factsTitle
                            factsCount(count)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Theme.gold)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "открыто" : "закрыто")
            if isOpen {
                // Заголовки столбцов не переносятся по слогам: тесно — таблица мельче.
                ViewThatFits(in: .horizontal) {
                    factsGrid(played: played, font: .subheadline, header: .caption, spacing: 12)
                    factsGrid(played: played, font: .footnote, header: .caption2, spacing: 8)
                    // Совсем тесно — та же таблица «набок»: строки — показатели, столбцы — игроки.
                    factsByPlayer(played: played)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(narrow ? 10 : 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.2)))
    }

    private var factsTitle: some View {
        Text("Как прошла партия")
            .font(.headline)
    }

    private func factsCount(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.tableSecondaryText)
    }

    private func factsGrid(played: [DealScore], font: Font, header: Font, spacing: CGFloat) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: spacing, verticalSpacing: 6) {
            GridRow {
                Text("")
                factHeader("Игр", font: header)
                factHeader("Сделано", font: header)
                factHeader("Байтов", font: header)
                factHeader("Голых", font: header)
            }
            // Строка игрока читается целиком («Саша: игр 4, сделано 2…») — заголовки отдельно не нужны.
            .accessibilityHidden(true)
            ForEach(standings, id: \.self) { seat in
                factRow(seat, played: played)
            }
        }
        .font(font.monospacedDigit())
    }

    private func factHeader(_ title: String, font: Font) -> some View {
        Text(title)
            .font(font.weight(.semibold))
            .foregroundStyle(Theme.tableSecondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// Итоги игрока за партию: сколько раз играл, сделал, байтов, голых.
    /// Байты и голые — из счётчиков партии, как в «Записи»: висячий байт считается по правилам.
    private func facts(_ seat: Int, played: [DealScore]) -> (played: Int, made: Int, baits: Int, naked: Int) {
        let asBidder = played.filter { $0.bidder == seat }
        let made = asBidder.filter { $0.outcome == .made }.count
        let baits = match.baitCounts.indices.contains(seat) ? match.baitCounts[seat] : 0
        let naked = match.nakedCounts.indices.contains(seat) ? match.nakedCounts[seat] : 0
        return (asBidder.count, made, baits, naked)
    }

    /// «Саша: игр 4, сделано 2, байтов 1, голых 0».
    private func spokenFacts(_ seat: Int, played: [DealScore]) -> String {
        let f = facts(seat, played: played)
        return "\(seats.column(seat)): игр \(f.played), сделано \(f.made), байтов \(f.baits), голых \(f.naked)"
    }

    private func factRow(_ seat: Int, played: [DealScore]) -> some View {
        let f = facts(seat, played: played)
        return GridRow {
            // Имя забирает свободное место — таблица тянется на всю ширину карточки.
            Text(seats.column(seat))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridColumnAlignment(.leading)
            Text("\(f.played)")
            Text("\(f.made)")
                .foregroundStyle(f.made > 0 ? ScreenStyle.positive : Theme.tableText)
            Text("\(f.baits)")
                .foregroundStyle(f.baits > 0 ? ScreenStyle.negative : Theme.tableText)
            Text("\(f.naked)")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenFacts(seat, played: played))
    }

    private func factsByPlayer(played: [DealScore]) -> some View {
        let all = standings.map { facts($0, played: played) }
        return Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("")
                ForEach(standings, id: \.self) { seat in
                    Text(seats.column(seat))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.tableSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            factLine("Игр", all.map { ($0.played, Theme.tableText) })
            factLine("Сделано", all.map { ($0.made, $0.made > 0 ? ScreenStyle.positive : Theme.tableText) })
            factLine("Байтов", all.map { ($0.baits, $0.baits > 0 ? ScreenStyle.negative : Theme.tableText) })
            factLine("Голых", all.map { ($0.naked, Theme.tableText) })
        }
        .font(.subheadline.monospacedDigit())
        // Таблица «набок» читается так же, как обычная: по игроку за раз.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(standings.map { spokenFacts($0, played: played) }.joined(separator: ". "))
    }

    private func factLine(_ title: String, _ values: [(Int, Color)]) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(Theme.tableSecondaryText)
                .lineLimit(1)
                .gridColumnAlignment(.leading)
            ForEach(values.indices, id: \.self) { index in
                Text("\(values[index].0)")
                    .foregroundStyle(values[index].1)
            }
        }
    }

    // MARK: - Совет об уровне

    @ViewBuilder
    private var adviceSection: some View {
        if let advice = LevelAdvice.afterMatch(stats: store.stats, opponents: store.opponents, humanWon: humanWon) {
            VStack(alignment: .leading, spacing: 10) {
                Label(advice.text, systemImage: advice.isStepUp ? "arrow.up.circle.fill" : "hand.thumbsup.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.tableText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    playWith(advice.level)
                } label: {
                    Text(advice.buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TableButtonStyle())
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1))
        }
    }

    private func playWith(_ level: BotLevel) {
        var settings = store.settings
        settings.playerCount = match.playerCount
        settings.difficulty = level
        settings.opponentIDs = AppSettings.defaultOpponentIDs(for: level)
        store.settings = settings
        store.newGame()
    }

    // MARK: - Последняя сдача

    @ViewBuilder
    private var lastDealSection: some View {
        if let last = match.history.last {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showLastDeal.toggle() }
                } label: {
                    HStack {
                        Label("Последняя сдача", systemImage: "rectangle.stack")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showLastDeal ? 180 : 0))
                    }
                    .foregroundStyle(Theme.gold)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showLastDeal ? "открыто" : "закрыто")
                if showLastDeal {
                    VStack(spacing: 12) {
                        OutcomeHeader(score: last, seats: seats)
                        DealScoreTable(score: last, seats: seats)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.2)))
        }
    }

    // MARK: - Кнопки

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                store.rematch()
            } label: {
                VStack(spacing: 2) {
                    Label("Реванш", systemImage: "arrow.counterclockwise")
                    Text("те же соперники и правила")
                        .font(.caption)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TableButtonStyle(prominent: true))

            // «Новая партия» и «Запись» — в ряд равной ширины, если обе помещаются словами целиком,
            // под ними «В меню». Тесно (крупный режим на узком экране) — «Новая партия» одна,
            // а «Запись» и «В меню» короче — они в ряд: всё те же три ряда кнопок, а не четыре.
            ViewThatFits(in: .horizontal) {
                VStack(spacing: 10) {
                    EqualWidthHStack(spacing: 10) {
                        newGameButton(icon: true)
                        scoreSheetButton(icon: true)
                    }
                    menuButton(icon: true)
                }
                VStack(spacing: 10) {
                    EqualWidthHStack(spacing: 10) {
                        newGameButton(icon: false)
                        scoreSheetButton(icon: false)
                    }
                    menuButton(icon: true)
                }
                VStack(spacing: 10) {
                    newGameButton(icon: true)
                    ViewThatFits(in: .horizontal) {
                        EqualWidthHStack(spacing: 10) {
                            scoreSheetButton(icon: true)
                            menuButton(icon: true)
                        }
                        EqualWidthHStack(spacing: 10) {
                            scoreSheetButton(icon: false)
                            menuButton(icon: false)
                        }
                        VStack(spacing: 10) {
                            scoreSheetButton(icon: true)
                            menuButton(icon: true)
                        }
                    }
                }
            }
        }
    }
}

extension MatchOverView {
    fileprivate func newGameButton(icon: Bool) -> some View {
        Button {
            store.newGame()
        } label: {
            SummaryButtonLabel(title: "Новая партия", systemImage: icon ? "suit.spade.fill" : nil)
        }
        .buttonStyle(TableButtonStyle())
        .accessibilityHint("С соперниками и правилами из меню")
    }

    fileprivate func menuButton(icon: Bool) -> some View {
        Button {
            store.leaveGame()
        } label: {
            SummaryButtonLabel(title: "В меню", systemImage: icon ? "house" : nil)
        }
        .buttonStyle(TableButtonStyle())
    }

    fileprivate func scoreSheetButton(icon: Bool) -> some View {
        Button {
            showScoreSheet = true
        } label: {
            SummaryButtonLabel(title: "Запись", systemImage: icon ? "list.number" : nil)
        }
        .buttonStyle(TableButtonStyle())
    }
}

/// Номер места: золото, серебро, бронза.
struct StandingPlaceBadge: View {
    let place: Int

    private var fill: Color {
        switch place {
        case 1: return Theme.gold
        case 2: return Color(red: 0.8, green: 0.83, blue: 0.87)
        default: return Color(red: 0.84, green: 0.6, blue: 0.4)
        }
    }

    var body: some View {
        Text("\(place)")
            .font(.headline.weight(.heavy))
            .foregroundStyle(Theme.onGold)
            .frame(width: 30, height: 30)
            .background(Circle().fill(fill))
            .accessibilityHidden(true)
    }
}
