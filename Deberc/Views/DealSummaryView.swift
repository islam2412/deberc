import SwiftUI
import DebercKit

/// Итоги сдачи — карточка поверх стола.
///
/// Исход крупно (значок: сделано / байт / висячий), таблица сдачи со столбцом играющего
/// и окрашенным «Записано», засчитанные комбинации, пояснения и предупреждения о штрафах,
/// счёт партии с полосками до цели и раскрывающиеся «Карты всех игроков».
/// Внизу — «Следующая сдача», «Запись» и «В меню» (партия сохраняется).
///
/// Конец партии показывает `MatchOverView` поверх стола (его ставит `RootView`);
/// здесь для этого случая — только короткая запасная карточка.
struct DealSummaryView: View {
    @EnvironmentObject private var store: GameStore
    let match: Match
    /// Сколько места по высоте есть на экране.
    let maxHeight: CGFloat
    let maxWidth: CGFloat
    /// Открыть запись партии снаружи (стол). nil — карточка откроет её сама.
    let onShowScoreSheet: (() -> Void)?

    @State private var showHands = false
    @State private var showScoreSheet = false

    init(match: Match, maxHeight: CGFloat, maxWidth: CGFloat = 560, onShowScoreSheet: (() -> Void)? = nil) {
        self.match = match
        self.maxHeight = maxHeight
        self.maxWidth = maxWidth
        self.onShowScoreSheet = onShowScoreSheet
    }

    private var seats: SeatNames { SeatNames(names: match.names, humanSeat: store.humanSeat) }

    /// Ширина карточки: цифры не должны уезжать от подписей на широком iPad.
    private var cardWidth: CGFloat {
        min(maxWidth, match.playerCount == 2 ? 540 : 620)
    }

    private var isLarge: Bool { maxWidth >= 600 }

    /// Невысокий экран (телефон лёжа): кнопки — в одну строку, чтобы итогам осталось место.
    private var isShort: Bool { maxHeight < 440 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                details
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            actions
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .padding(.top, 6)
        }
        .frame(maxWidth: cardWidth, maxHeight: max(280, maxHeight))
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ScreenStyle.cardFill)
                .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
        .foregroundStyle(Theme.tableText)
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .sheet(isPresented: $showScoreSheet) {
            ScoreSheetView(match: match, humanSeat: store.humanSeat)
        }
        .pausesGame(while: showScoreSheet)
    }

    // MARK: - Содержимое

    @ViewBuilder
    private var details: some View {
        if match.isOver {
            matchOverFallback
        } else if let score = match.history.last {
            VStack(spacing: 16) {
                OutcomeHeader(score: score, seats: seats)
                DealScoreTable(score: score, seats: seats)
                notes(score)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Счёт партии · до \(match.rules.targetScore)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.tableSecondaryText)
                    // О висячих очках уже сказано в пояснениях выше (Narrator.outcomeNotes).
                    MatchProgressList(totals: match.totals, target: match.rules.targetScore, seats: seats)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                handsSection(score)
                ProblemReportLink(title: "Что-то не так? Отправить сдачу",
                                  subject: "Деберц: сдача \(score.number)")
                    .font(.footnote)
                    .foregroundStyle(Theme.tableSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func notes(_ score: DealScore) -> some View {
        let meld = Narrator.meldLine(score, names: match.names, humanSeat: store.humanSeat, rules: match.rules)
        let lines = Narrator.outcomeNotes(score, names: match.names, humanSeat: store.humanSeat, rules: match.rules)
        if meld != nil || !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let meld {
                    SummaryNoteLine(text: "Записаны комбинации — \(meld)", systemImage: "rectangle.stack.fill", tint: Theme.gold)
                }
                ForEach(lines, id: \.self) { line in
                    SummaryNoteLine(text: line,
                             systemImage: SummaryNoteLine.isWarning(line) ? "exclamationmark.triangle.fill" : "info.circle",
                             tint: SummaryNoteLine.isWarning(line) ? Theme.gold : Theme.tableSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func handsSection(_ score: DealScore) -> some View {
        if score.wasPlayed, let deal = match.deal, deal.isFinished, !deal.tricks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showHands.toggle() }
                } label: {
                    HStack {
                        Label("Карты всех игроков", systemImage: "rectangle.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showHands ? 180 : 0))
                    }
                    .foregroundStyle(Theme.gold)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showHands ? "открыто" : "закрыто")
                if showHands {
                    HandsRevealView(deal: deal, score: score, seats: seats, cardWidth: isLarge ? 54 : 40)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.2)))
        }
    }

    private var matchOverFallback: some View {
        VStack(spacing: 8) {
            Image(systemName: match.winner == store.humanSeat ? "trophy.fill" : "flag.checkered")
                .font(.system(size: 40))
                .foregroundStyle(Theme.gold)
            Text(Narrator.matchResult(match, humanSeat: store.humanSeat) ?? "Партия окончена")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            MatchProgressList(totals: match.totals, target: match.rules.targetScore, seats: seats)
        }
    }

    // MARK: - Кнопки

    @ViewBuilder
    private var actions: some View {
        if match.isOver {
            VStack(spacing: 10) {
                Button {
                    store.rematch()
                } label: {
                    Label("Реванш", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TableButtonStyle(prominent: true))
                secondaryButtons
            }
        } else if isShort {
            HStack(spacing: 10) {
                nextDealButton
                secondaryButtons
            }
        } else {
            VStack(spacing: 10) {
                nextDealButton
                secondaryButtons
            }
        }
    }

    private var nextDealButton: some View {
        Button {
            store.startNextDeal()
        } label: {
            Label("Следующая сдача", systemImage: "arrow.forward.circle.fill")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(TableButtonStyle(prominent: true))
    }

    private var secondaryButtons: some View {
        HStack(spacing: 10) {
            Button {
                openScoreSheet()
            } label: {
                Label("Запись", systemImage: "list.number")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TableButtonStyle())
            .accessibilityHint("Все сдачи партии")

            Button {
                store.leaveGame()
            } label: {
                Label("В меню", systemImage: "house")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TableButtonStyle())
            .accessibilityHint("Партия сохранится — её можно продолжить")
        }
    }

    private func openScoreSheet() {
        if let onShowScoreSheet {
            onShowScoreSheet()
        } else {
            showScoreSheet = true
        }
    }
}

/// Заголовок итогов: значок исхода, «Игра сделана: Саша», подпись сдачи с козырем.
struct OutcomeHeader: View {
    let score: DealScore
    let seats: SeatNames

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(Narrator.outcomeTitle(score, names: seats.names, humanSeat: seats.humanSeat))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            subtitle
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: some View {
        HStack(spacing: 6) {
            Text("Сдача \(score.number)")
            if score.wasPlayed, let bidder = score.bidder, let trump = score.trump {
                Text("·")
                Text(bidder == seats.humanSeat ? "играете вы" : "играет \(seats.speaker(bidder))")
                SuitBadge(suit: trump, size: 20)
                if score.forced {
                    Text("обязы")
                        .foregroundStyle(Theme.gold)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.tableSecondaryText)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch score.outcome {
        case .made: return "checkmark.seal.fill"
        case .bait: return "xmark.octagon.fill"
        case .hanging: return "pause.circle.fill"
        case .tie: return "equal.circle.fill"
        case .allPassed: return "arrow.triangle.2.circlepath"
        case .fourSevens: return "sparkles"
        }
    }

    private var tint: Color {
        switch score.outcome {
        case .made: return score.bidder == seats.humanSeat ? ScreenStyle.positive : Theme.gold
        case .bait: return ScreenStyle.negative
        case .hanging, .tie, .allPassed: return Theme.tableSecondaryText
        case .fourSevens: return Theme.gold
        }
    }
}

/// Строка пояснения к итогам: значок и текст.
struct SummaryNoteLine: View {
    let text: String
    let systemImage: String
    var tint: Color = Theme.tableSecondaryText

    /// Предупреждения и штрафы выделяются.
    static func isWarning(_ line: String) -> Bool {
        line.contains("штраф") || line.contains("не в зачёт")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Theme.tableText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
    }
}
