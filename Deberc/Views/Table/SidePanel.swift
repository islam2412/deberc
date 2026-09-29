import SwiftUI
import UIKit
import DebercKit

/// Панель справа на широком экране (iPad в альбомной ориентации): живая запись партии —
/// счёт, отметки до штрафов, висячие очки, последние сдачи — и крупные кнопки.
struct SidePanel: View {
    @EnvironmentObject private var store: GameStore
    let match: Match
    let commands: TableCommands

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                players
                if match.pot > 0 {
                    Text("Висят \(match.pot) \(TableText.plural(match.pot, "очко", "очка", "очков"))")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.gold)
                }
                recentDeals
                buttons
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity)
        .tableSurface(cornerRadius: 22)
        .padding(.vertical, 10)
        .padding(.trailing, 14)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Партия до \(match.rules.targetScore)")
                .font(Theme.Typography.seatName)
                .foregroundStyle(Theme.tableText)
            Text("Сдача \(max(1, match.dealCount))")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.tableSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var seats: [Int] {
        let n = match.playerCount
        return (0..<n).map { (store.humanSeat + $0) % n }
    }

    private var players: some View {
        VStack(spacing: 10) {
            ForEach(seats, id: \.self) { seat in
                playerRow(seat)
            }
        }
    }

    private func playerRow(_ seat: Int) -> some View {
        let score = match.totals[seat]
        let target = max(1, match.rules.targetScore)
        let fraction = min(1, max(0, Double(score) / Double(target)))
        let name = store.displayName(for: seat)
        return HStack(spacing: 10) {
            SeatAvatar(persona: store.persona(for: seat), name: seat == store.humanSeat ? "Вы" : name,
                       seat: seat, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.tableText)
                    .lineLimit(1)
                ProgressTrack(fraction: fraction, width: 90, height: 5)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(TableText.number(score))
                    .font(Theme.Typography.score)
                    .foregroundStyle(Theme.tableText)
                    .contentTransition(.numericText())
                if let marks = marks(seat) {
                    Text(marks)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.tableSecondaryText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(TableText.number(score))")
    }

    private func marks(_ seat: Int) -> String? {
        var parts: [String] = []
        let bait = match.rules.baitPenaltyEvery
        if bait > 1, match.baitCounts.indices.contains(seat), match.baitCounts[seat] % bait > 0 {
            parts.append("байтов \(match.baitCounts[seat] % bait) из \(bait)")
        }
        let naked = match.rules.nakedPenaltyEvery
        if naked > 1, match.nakedCounts.indices.contains(seat), match.nakedCounts[seat] % naked > 0 {
            parts.append("голый \(match.nakedCounts[seat] % naked) из \(naked)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Последние сдачи

    @ViewBuilder
    private var recentDeals: some View {
        let recent = Array(match.history.suffix(6).reversed())
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Последние сдачи")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.tableSecondaryText)
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("")
                        ForEach(seats, id: \.self) { seat in
                            Text(shortName(seat))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.tableSecondaryText)
                                .lineLimit(1)
                        }
                    }
                    ForEach(recent, id: \.number) { score in
                        dealRow(score)
                    }
                }
            }
        }
    }

    private func dealRow(_ score: DealScore) -> some View {
        GridRow {
            HStack(spacing: 4) {
                Text("\(score.number)")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.tableSecondaryText)
                if let trump = score.trump {
                    SuitBadge(suit: trump, size: 18)
                }
                let mark = Narrator.sheetMark(score)
                if !mark.isEmpty {
                    Text(mark)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.gold)
                }
            }
            .gridColumnAlignment(.leading)
            ForEach(seats, id: \.self) { seat in
                Text(change(score, seat))
                    .font(Theme.Typography.label.monospacedDigit())
                    .foregroundStyle(score.bidder == seat ? Theme.gold : Theme.tableText)
            }
        }
    }

    private func change(_ score: DealScore, _ seat: Int) -> String {
        guard score.change.indices.contains(seat) else { return "" }
        return Narrator.signed(score.change[seat])
    }

    private func shortName(_ seat: Int) -> String {
        seat == store.humanSeat ? "Вы" : store.displayName(for: seat)
    }

    // MARK: - Кнопки

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: commands.showScoreSheet) {
                Label("Запись партии", systemImage: "list.number")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TableButtonStyle())
            if store.lastTrick != nil {
                Button(action: commands.showLastTrick) {
                    Label("Последняя взятка", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TableButtonStyle())
            }
            Button(action: commands.showRules) {
                Label("Правила", systemImage: "book")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TableButtonStyle())
        }
    }
}

/// Карточка соперника: портрет, имя, уровень и манера игры, ваш счёт против него. Закрывается касанием.
struct PersonaPanel: View {
    let persona: Persona
    /// Партии против этого соперника (nil или 0 — ещё не играли).
    let record: PlayerStats.Record?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            // При крупном системном тексте рассказ о сопернике может не поместиться — тогда прокрутка.
            ViewThatFits(in: .vertical) {
                content
                ScrollView(showsIndicators: false) {
                    content
                }
            }
            .frame(maxWidth: 380)
            .modalCard(cornerRadius: 26)
            .padding(24)
            .modalPanelAccessibility(onClose: onClose)
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            PersonaAvatarView(persona: persona, size: 96)
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
            Text(persona.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.tableText)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                LevelStarsView(level: persona.level, size: 13)
                Text("\(persona.level.title) · \(persona.style.title)")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.tableSecondaryText)
            }
            Text(persona.bio)
                .font(.body)
                .foregroundStyle(Theme.tableText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(recordText)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.gold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Закрыть", action: onClose)
                .buttonStyle(TableButtonStyle(prominent: true))
                .padding(.top, 4)
        }
        .padding(24)
    }

    private var recordText: String {
        let with = persona.feminine ? "с ней" : "с ним"
        guard let record, record.played > 0 else { return "Вы ещё не доигрывали партию \(with)" }
        let games = RuPlural.count(record.played, "партия", "партии", "партий")
        return "Ваши партии \(with): \(games), побед — \(record.won)"
    }
}

/// Последняя взятка: карты с именами, кто зашёл и кто взял. Закрывается касанием.
struct LastTrickPanel: View {
    let trick: Trick
    let names: [String]
    /// Самая крупная ширина карты: как в руке, но не больше 110.
    let maxCardWidth: CGFloat
    /// Ширина окна: втроём три колонки с картами должны поместиться вместе с полями карточки.
    let screenWidth: CGFloat
    let onClose: () -> Void

    /// Поля вокруг карточки: на телефоне уже, чтобы трём картам хватило места.
    private var outerPadding: CGFloat { screenWidth < 400 ? 12 : 24 }
    private let innerPadding: CGFloat = 22
    private let columnSpacing: CGFloat = 12

    /// Ширина карты — по свободному месту: окно минус поля, промежутки и запас колонки (8 pt) на каждую карту.
    /// Втроём: 393 pt — (393 − 24 − 44 − 24) / 3 − 8 = 92; 375 — 86; 320 — 68; 430 (поля 24) — 96;
    /// вдвоём и на iPad — до 110. Раньше колонки были по 118 pt и втроём карточка выходила за края экрана.
    private var cardWidth: CGFloat {
        let n = CGFloat(max(1, trick.plays.count))
        let room = screenWidth - 2 * outerPadding - 2 * innerPadding - (n - 1) * columnSpacing
        return max(56, min(maxCardWidth, (room / n - 8).rounded(.down)))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            VStack(spacing: 16) {
                Text("Последняя взятка")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.tableText)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(Array(trick.plays.enumerated()), id: \.offset) { index, play in
                        playColumn(index: index, play: play)
                    }
                }
                if let winner = trick.winner {
                    Text("Взятка: \(name(winner))")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.gold)
                }
                Button("Закрыть", action: onClose)
                    .buttonStyle(TableButtonStyle(prominent: true))
            }
            .padding(innerPadding)
            .modalCard(cornerRadius: 24)
            .padding(outerPadding)
            .modalPanelAccessibility(onClose: onClose)
        }
    }

    private func name(_ seat: Int) -> String {
        names.indices.contains(seat) ? names[seat] : ""
    }

    private func playColumn(index: Int, play: PlayedCard) -> some View {
        VStack(spacing: 6) {
            CardView(card: play.card, width: cardWidth, highlighted: trick.winner == play.seat)
            Text(name(play.seat))
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.tableText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if index == 0 {
                Text("заход")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.tableSecondaryText)
            }
        }
        .frame(width: cardWidth + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(play.seat)): \(CardView.spokenName(play.card))" + (index == 0 ? ", заход" : ""))
    }
}

extension View {
    /// Карточка поверх стола для VoiceOver — как окно: карты руки за затемнением недоступны
    /// (иначе с них можно было сходить при игре на паузе), жест «назад» закрывает, фокус переходит на карточку.
    func modalPanelAccessibility(onClose: @escaping () -> Void) -> some View {
        accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onClose)
            .onAppear {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
    }

    /// Плотная карточка поверх стола (карточка соперника, последняя взятка): как окно итогов,
    /// без «стекла» — сквозь него просвечивал стол, и текст читался плохо.
    func modalCard(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ScreenStyle.cardFill)
                .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
    }
}
