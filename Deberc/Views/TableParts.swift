import SwiftUI
import DebercKit

// Детали стола: плашки игроков, аватары, отметки, реплики, комбинации, сообщения, индикатор козыря.

// MARK: - Сведения о месте

/// Объявленное игроком и видимое всем до конца сдачи.
enum DeclItem: Hashable {
    /// Записанная комбинация (терц, полтинник).
    case meld(Meld)
    /// Объявленная бэла.
    case bella(Suit)
    /// Свои комбинации сгорели: старше у другого.
    case burned
    /// Обмен козырной семёрки: какую карту забрал.
    case exchange(Card)
}

/// Всё, что показывает плашка игрока.
struct SeatInfo {
    var seat: Int
    var name: String
    var persona: Persona?
    var isHuman: Bool
    var score: Int
    var target: Int
    var isDealer: Bool
    var isBidder: Bool
    var trump: Suit?
    /// Сейчас его ход (или его взятка на столе).
    var isActive: Bool
    var isThinking: Bool
    var baitMarks: Int
    var nakedMarks: Int
    var tricks: Int
    var bubble: String?
    var declarations: [DeclItem]
    var rules: RuleSet

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, Double(score) / Double(target)))
    }

    /// «Б·Б», «Г» — счётчики до штрафа.
    var marksText: String? {
        var parts: [String] = []
        if baitMarks > 0 { parts.append(Array(repeating: "Б", count: baitMarks).joined(separator: "·")) }
        if nakedMarks > 0 { parts.append(Array(repeating: "Г", count: nakedMarks).joined(separator: "·")) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Описание для VoiceOver.
    var spokenValue: String {
        var parts: [String] = []
        parts.append("\(TableText.number(score)) \(TableText.plural(score, "очко", "очка", "очков")) из \(target)")
        if isDealer { parts.append(isHuman ? "вы сдаёте" : "сдаёт") }
        if isBidder, let trump { parts.append((isHuman ? "вы играете" : "играет") + ", козырь \(trump.name)") }
        if isThinking {
            parts.append("думает")
        } else if isActive {
            parts.append(isHuman ? "ваш ход" : "ходит")
        }
        if tricks > 0 { parts.append("взяток \(tricks)") }
        if baitMarks > 0 { parts.append("байтов: \(baitMarks) из \(rules.baitPenaltyEvery)") }
        if nakedMarks > 0 { parts.append("голых: \(nakedMarks) из \(rules.nakedPenaltyEvery)") }
        if let bubble { parts.append("говорит: \(bubble)") }
        for item in declarations {
            parts.append(DeclarationChip.spoken(item, rules: rules))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Аватар

/// Круглый аватар персонажа: эмодзи на цвете персонажа. Ход — золотое кольцо, раздумье — бегущая дуга.
struct SeatAvatar: View {
    let persona: Persona?
    let name: String
    let seat: Int
    let size: CGFloat
    var isActive = false
    var isThinking = false
    var isDealer = false
    var bidSuit: Suit?

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .top, endPoint: .bottom))
            Text(symbol)
                .font(.system(size: size * (persona == nil ? 0.44 : 0.54), weight: .bold, design: .rounded))
                .foregroundStyle(Theme.onGold)
                .minimumScaleFactor(0.5)
            Circle()
                .strokeBorder(isActive ? Theme.gold : Theme.ivory.opacity(0.75), lineWidth: isActive ? 3 : 1.5)
            if isThinking {
                ThinkingRing(size: size + 8)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if let bidSuit {
                SuitBadge(suit: bidSuit, size: max(18, size * 0.42))
                    .offset(x: size * 0.14, y: -size * 0.1)
            }
        }
        .overlay(alignment: .bottom) {
            if isDealer {
                DealerTag()
                    .offset(y: size * 0.22)
            }
        }
        .accessibilityHidden(true)
    }

    /// Цвет персонажа; у человека — золото, как в меню и итогах (`HumanAvatarView`),
    /// чтобы не совпасть по цвету с соперником.
    private var tint: Color {
        persona.map { Theme.seatTint($0.tint) } ?? Theme.goldFill
    }

    private var symbol: String {
        if let persona { return persona.avatar }
        return String(name.prefix(1)).uppercased()
    }
}

/// Отметка сдающего: словом, а не значком.
struct DealerTag: View {
    var text = "сдаёт"

    var body: some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.onGold)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Theme.gold))
            .overlay(Capsule().strokeBorder(Theme.goldDeep.opacity(0.6), lineWidth: 1))
    }
}

/// Бегущая золотая дуга вокруг аватара, пока соперник думает.
struct ThinkingRing: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: reduceMotion ? 1 : 0.28)
            .stroke(Theme.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}

/// Тонкая полоса прогресса к цели партии.
struct ProgressTrack: View {
    let fraction: Double
    var width: CGFloat = 44
    var height: CGFloat = 5

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Theme.goldLight, Theme.gold], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, width * CGFloat(fraction)), height: height)
                    .opacity(fraction > 0 ? 1 : 0)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Плашка соперника

/// Место соперника: аватар, имя, счёт, прогресс к цели, отметки сдающего и играющего, раздумье.
struct SeatPlate: View {
    let info: SeatInfo
    let avatarSize: CGFloat
    var maxWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: 10) {
            SeatAvatar(persona: info.persona, name: info.name, seat: info.seat, size: avatarSize,
                       isActive: info.isActive, isThinking: info.isThinking, isDealer: info.isDealer,
                       bidSuit: info.isBidder ? info.trump : nil)
            VStack(alignment: .leading, spacing: 1) {
                nameLine
                scoreLine
            }
            .layoutPriority(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .tableSurface(cornerRadius: 18, highlighted: info.isActive)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.name)
        .accessibilityValue(info.spokenValue)
        .accessibilityHint(personaHint)
    }

    /// Характер соперника: уровень и манера игры.
    private var personaHint: String {
        guard let persona = info.persona else { return "" }
        return "\(persona.level.title). \(persona.bio)"
    }

    private var nameLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                nameText
                if let level = info.persona?.level {
                    LevelStarsView(level: level, size: 9)
                }
            }
            nameText
        }
    }

    private var nameText: some View {
        Text(info.name)
            .font(Theme.Typography.seatName)
            .foregroundStyle(Theme.tableText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var scoreLine: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(TableText.number(info.score))
                .font(Theme.Typography.score)
                .foregroundStyle(Theme.tableText)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 3) {
                ProgressTrack(fraction: info.progress, width: avatarSize * 0.9)
                if let marks = info.marksText {
                    Text(marks)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.tableSecondaryText)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Мини-карты и комбинации

/// Крошечная карта-индекс: достоинство и масть на слоновой кости.
struct MiniTile: View {
    let card: Card
    var height: CGFloat = 26
    @Environment(\.cardAppearance) private var appearance

    var body: some View {
        let color = Theme.suitColor(card.suit, fourColor: appearance.fourColor)
        VStack(spacing: 0) {
            Text(card.rank.symbol)
                .font(.system(size: height * 0.5, weight: .bold, design: .serif))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            SuitShape(suit: card.suit)
                .fill(color)
                .frame(width: height * 0.34, height: height * 0.34)
        }
        .frame(width: height * 0.78, height: height)
        .background(
            RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
                .fill(Theme.ivory)
        )
        .overlay(
            RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CardView.spokenName(card))
    }
}

/// Постоянная отметка у места игрока: комбинация картами, бэла, обмен семёрки.
struct DeclarationChip: View {
    let item: DeclItem
    let rules: RuleSet
    var tileHeight: CGFloat = 26

    var body: some View {
        HStack(spacing: 6) {
            label
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .tableSurface(cornerRadius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DeclarationChip.spoken(item, rules: rules))
    }

    @ViewBuilder
    private var label: some View {
        switch item {
        case .meld(let meld):
            caption(meld.name(rules))
            tiles(meld.cards)
        case .bella(let suit):
            caption("бэла")
            tiles([Card(.king, suit), Card(.queen, suit)])
        case .burned:
            Text("комбинации сгорели")
                .strikethrough(true, color: Theme.tableSecondaryText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.tableSecondaryText)
                .lineLimit(1)
        case .exchange(let card):
            caption("обмен")
            MiniTile(card: card, height: tileHeight)
            caption("за 7")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.tableText)
            .lineLimit(1)
            .fixedSize()
    }

    private func tiles(_ cards: [Card]) -> some View {
        HStack(spacing: -tileHeight * 0.2) {
            ForEach(cards, id: \.self) { card in
                MiniTile(card: card, height: tileHeight)
            }
        }
    }

    /// Коротко словами: «терц», «бэла», «обмен 7».
    nonisolated static func short(_ item: DeclItem, rules: RuleSet) -> String {
        switch item {
        case .meld(let meld): return meld.name(rules)
        case .bella: return "бэла"
        case .burned: return "сгорели"
        case .exchange: return "обмен 7"
        }
    }

    nonisolated static func spoken(_ item: DeclItem, rules: RuleSet) -> String {
        switch item {
        case .meld(let meld):
            let ranks = meld.cards.map { $0.rank.name }.joined(separator: ", ")
            return "\(meld.name(rules)): \(ranks), \(meld.suit.name)"
        case .bella(let suit):
            return "бэла, \(suit.name)"
        case .burned:
            return "ваши комбинации сгорели"
        case .exchange(let card):
            return "обмен: \(CardView.spokenName(card)) за козырную семёрку"
        }
    }
}

/// Несколько отметок в ряд. `compact` — одними словами, без мини-карт (для тесного места).
struct DeclarationRow: View {
    let items: [DeclItem]
    let rules: RuleSet
    var tileHeight: CGFloat = 26
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                if compact {
                    Text(DeclarationChip.short(item, rules: rules))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.tableText)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .tableSurface(cornerRadius: 12)
                        .accessibilityLabel(DeclarationChip.spoken(item, rules: rules))
                } else {
                    DeclarationChip(item: item, rules: rules, tileHeight: tileHeight)
                }
            }
        }
    }
}

// MARK: - Реплика и сообщение

/// Реплика игрока при торговле — облачко с хвостиком к месту.
struct SpeechBubble: View {
    let text: String
    /// Хвостик сверху (место выше облачка) или снизу.
    var tailOnTop = true

    var body: some View {
        Text(TableText.textSuits(text))
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.onGold)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.ivory)
                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
            )
            .overlay(alignment: tailOnTop ? .top : .bottom) {
                BubbleTail()
                    .fill(Theme.ivory)
                    .frame(width: 14, height: 7)
                    .rotationEffect(.degrees(tailOnTop ? 0 : 180))
                    .offset(y: tailOnTop ? -6 : 6)
            }
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Всплывающее сообщение стола. Срочное (ошибка хода, совет, бэла) — с золотой каймой.
struct BannerView: View {
    let text: String
    var urgent = false

    var body: some View {
        Text(TableText.textSuits(text))
            .font(Theme.Typography.banner)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.tableText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .tableSurface(cornerRadius: 14, highlighted: urgent)
            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Верхняя полоса

/// Индикатор козыря: масть настоящим цветом, её название и кто играет.
/// Во время торговли — какой идёт круг.
struct TrumpBadge: View {
    let trump: Suit?
    /// «играет Саша», «играете Вы», «обязы · Саша».
    let detail: String?
    /// Круг торговли: 1, 2; 0 — все спасовали.
    let biddingRound: Int?
    let height: CGFloat

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(height: height - 6)
            .tableSurface(cornerRadius: 14, highlighted: trump != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var content: some View {
        if let trump {
            HStack(spacing: 8) {
                SuitBadge(suit: trump, size: min(34, height - 16))
                VStack(alignment: .leading, spacing: 0) {
                    Text(TableText.suitTitle(trump))
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.tableText)
                    if let detail {
                        Text(detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.tableSecondaryText)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Торговля")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.tableText)
                Text(roundText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.tableSecondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private var roundText: String {
        switch biddingRound {
        case 2: return "2-й круг"
        case 0: return "все пас"
        default: return "1-й круг"
        }
    }

    private var spoken: String {
        if let trump {
            return "Козырь \(trump.name)" + (detail.map { ", \($0)" } ?? "")
        }
        switch biddingRound {
        case 2: return "Торговля, второй круг"
        case 0: return "Все спасовали, пересдача"
        default: return "Торговля, первый круг"
        }
    }
}

/// Цель партии, висячие очки, пересдачи подряд.
struct MatchInfoBadge: View {
    let target: Int
    let pot: Int
    /// Сколько пересдач подряд (все спасовали) — после `forcedAfter` сдача на обязах.
    let redeals: Int
    let forcedAfter: Int

    var body: some View {
        VStack(spacing: 1) {
            Text("до \(target)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.tableSecondaryText)
            if pot > 0 {
                Text("висят \(pot)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.gold)
            } else if redeals > 0 && forcedAfter > 0 {
                Text("пересдач: \(redeals)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.gold)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var text = "Партия до \(target)"
        if pot > 0 { text += ", висят \(pot) \(TableText.plural(pot, "очко", "очка", "очков"))" }
        if redeals > 0 && forcedAfter > 0 {
            text += ", пересдач подряд: \(redeals), после \(forcedAfter) — обязы"
        }
        return text
    }
}
