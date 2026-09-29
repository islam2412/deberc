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

    /// Счётчики до штрафа словами: «байт: 2 из 3 · голый: 1 из 3» — сколько уже есть из скольких до штрафа.
    var marksText: String? { marks(compact: false) }

    /// Покороче для тесного места — те же слова, без «из»: «байт 2/3 · голый 1/3».
    var marksShort: String? { marks(compact: true) }

    private func marks(compact: Bool) -> String? {
        var parts: [String] = []
        func mark(_ word: String, _ count: Int, _ every: Int) -> String {
            compact ? "\(word) \(count)/\(every)" : "\(word): \(count) из \(every)"
        }
        if baitMarks > 0 { parts.append(mark("байт", baitMarks, rules.baitPenaltyEvery)) }
        if nakedMarks > 0 { parts.append(mark("голый", nakedMarks, rules.nakedPenaltyEvery)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
        if tricks > 0 {
            let count = RuPlural.count(tricks, "взятка", "взятки", "взяток")
            parts.append(isHuman ? "у вас \(count)" : count)
        }
        if baitMarks > 0 { parts.append("байтов: \(baitMarks) из \(rules.baitPenaltyEvery)") }
        if nakedMarks > 0 { parts.append("голых: \(nakedMarks) из \(rules.nakedPenaltyEvery)") }
        if let bubble { parts.append("говорит: \(Narrator.spoken(bubble))") }
        for item in declarations {
            parts.append(DeclarationChip.spoken(item, rules: rules))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Аватар

/// Круглый аватар персонажа: портрет (или эмодзи) на цвете персонажа. Ход — золотое кольцо, раздумье — бегущая дуга.
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
            if let portrait = persona.flatMap(CardArt.avatarImageName) {
                PortraitImage(name: portrait, size: size)
            } else {
                Text(symbol)
                    .font(.system(size: size * (persona == nil ? 0.44 : 0.54), weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onGold)
                    .minimumScaleFactor(0.5)
            }
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
                // Шрифт — по размеру аватара, а не системного текста: иначе отметка наезжает на счёт.
                // Не мельче 12 pt (при аватаре 48 в крупном режиме — 13): кто сдаёт, важно — от этого обязы.
                // «сдаёт» 12 pt с полями ≈ 49 pt при аватаре 42 — выступает по 3–4 pt в поля плашки, не до счёта.
                DealerTag(fontSize: max(12, (size * 0.27).rounded()))
                    .offset(y: size * 0.2)
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
    /// Постоянный размер шрифта (у аватара); nil — подпись стола, растёт с размером текста.
    var fontSize: CGFloat? = nil

    var body: some View {
        Text(text)
            .font(fontSize.map { Font.system(size: $0, weight: .bold) } ?? Theme.Typography.caption)
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
    /// Касание плашки — карточка соперника.
    var onTap: (() -> Void)? = nil

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
        // Варианты строк (со звёздами и без, с полоской и без) сменяются сразу, без затухания.
        .transaction { $0.animation = nil }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName)
        .accessibilityValue(info.spokenValue)
        // Подсказка говорит, что будет по касанию; характер и манера игры — в самой карточке.
        .accessibilityHint(onTap == nil ? "" : "Открыть карточку соперника")
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityAction { onTap?() }
    }

    /// Имя и уровень (звёзды на экране): «Саша, любитель».
    private var spokenName: String {
        guard let level = info.persona?.level else { return info.name }
        return "\(info.name), \(level.title.lowercased())"
    }

    /// Имя и звёзды уровня; тесно — одно имя.
    private var nameLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                nameText
                if let level = info.persona?.level {
                    // По аватару: 10 pt на телефоне, 12 — в крупном режиме, 13–15 — на iPad.
                    LevelStarsView(level: level, size: (avatarSize * 0.24).rounded())
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

    /// Счёт и полоска до цели; тесно (узкий экран, крупный текст) — без полоски: счёт важнее.
    private var scoreLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 6) {
                scoreText
                VStack(alignment: .leading, spacing: 3) {
                    ProgressTrack(fraction: info.progress, width: avatarSize * 0.9)
                    marks
                }
            }
            HStack(alignment: .center, spacing: 6) {
                scoreText
                marks
            }
            scoreText
        }
    }

    private var scoreText: some View {
        Text(TableText.number(info.score))
            .font(Theme.Typography.score)
            .foregroundStyle(Theme.tableText)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var marks: some View {
        MarksLabel(info: info)
    }
}

/// Счётчики байтов и голых до штрафа: словами, в тесноте — короче, а совсем тесно — не показываются
/// (они есть в записи партии и в VoiceOver).
struct MarksLabel: View {
    let info: SeatInfo

    var body: some View {
        if let long = info.marksText, let short = info.marksShort {
            ViewThatFits(in: .horizontal) {
                text(long)
                text(short)
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    private func text(_ value: String) -> some View {
        Text(value)
            .font(Theme.Typography.caption)
            .foregroundStyle(ScreenStyle.negative)
            .lineLimit(1)
            .fixedSize()
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
    /// Подначка (а не заявка): тёплое золотистое облачко — чтобы не путать с «Пас» и «Беру».
    var chatter = false
    @Environment(\.cardAppearance) private var appearance

    private var fill: Color { chatter ? Theme.goldLight : Theme.ivory }

    var body: some View {
        // Масть — своим цветом, как на картах: «Беру ♦» с красной бубной.
        Text(TableText.styled(text, onLight: true, fourColor: appearance.fourColor))
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.onGold)
            // Одно слово («Воздержусь») не переносится по слогам, а чуть уменьшается.
            .lineLimit(text.contains(" ") ? (chatter ? 3 : 2) : 1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fill)
                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.goldDeep.opacity(chatter ? 0.6 : 0), lineWidth: 1)
            )
            .overlay(alignment: tailOnTop ? .top : .bottom) {
                BubbleTail()
                    .fill(fill)
                    .frame(width: 14, height: 7)
                    .rotationEffect(.degrees(tailOnTop ? 0 : 180))
                    .offset(y: tailOnTop ? -6 : 6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
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

/// «Печать» назначенного козыря: крупная масть в круге слоновой кости, под ней — «Козырь — бубны»
/// и кто играет. Показывается в центре стола на пару секунд.
struct TrumpStamp: View {
    let suit: Suit
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            SuitBadge(suit: suit, size: 72)
                .shadow(color: Theme.gold.opacity(0.65), radius: 14)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.tableText)
            Text(subtitle)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.gold)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .tableSurface(cornerRadius: 26, highlighted: true)
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// «Печать» записанных комбинаций: название («Терц», «Два терца», «Терц и полтинник»),
/// сами карты, у кого и сколько очков.
struct MeldStamp: View {
    let melds: [Meld]
    let rules: RuleSet
    /// «Вы», «Борис» — чьи комбинации.
    let owner: String
    let points: Int
    /// У других тоже были комбинации, но младше.
    let senior: Bool
    let tileHeight: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.tableText)
            HStack(spacing: 10) {
                ForEach(Array(melds.enumerated()), id: \.offset) { _, meld in
                    HStack(spacing: -tileHeight * 0.18) {
                        ForEach(meld.cards, id: \.self) { card in
                            MiniTile(card: card, height: tileHeight)
                                .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                        }
                    }
                }
            }
            Text("\(owner) · +\(points)" + (senior ? " · старше" : ""))
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.gold)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .tableSurface(cornerRadius: 26, highlighted: true)
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        let names = melds.map { $0.name(rules) }
        if names.count == 2, names[0] == names[1] {
            switch names[0] {
            case "терц": return "Два терца"
            case "полтинник": return "Два полтинника"
            default: break
            }
        }
        let joined = names.joined(separator: " и ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}

/// Всплывающее сообщение стола. Срочное (ошибка хода, совет, бэла) — с золотой каймой.
struct BannerView: View {
    let text: String
    var urgent = false
    @Environment(\.cardAppearance) private var appearance

    var body: some View {
        Text(TableText.styled(text, onLight: false, fourColor: appearance.fourColor))
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
    /// «играет Саша», «играете вы», «обязы · Саша».
    let detail: String?
    /// Круг торговли: 1, 2; 0 — все спасовали.
    let biddingRound: Int?
    let height: CGFloat
    /// Узкий вариант для тесной верхней полосы: только масть (или круг торговли).
    var compact: Bool = false
    /// Сдача на обязах. Без подробности «играет …» (вдвоём) над мастью пишется «обязы» вместо «козырь»:
    /// после «печати» и первой карты это больше нигде не видно.
    var forced: Bool = false
    /// Две строки подписи или одна; nil — две, если текст не из самых крупных.
    var twoLinesOverride: Bool? = nil
    /// Потеснее (ушко у выреза): поля 6 pt, промежуток 4 pt, значок 26 pt.
    var tight = false
    /// Сначала подпись, потом значок масти (правое ушко): значок дальше от острова,
    /// и активная Live Activity его не закроет.
    var iconTrailing = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Круги торговли в подписи — по ним же стол заранее решает, какой вид индикатора помещается.
    static let roundTexts = ["1-й круг", "2-й круг", "все пас"]

    /// Две строки подписи помещаются в полосу только при обычных размерах текста.
    private var twoLines: Bool { twoLinesOverride ?? !typeSize.isAccessibilitySize }

    /// Узкий вариант — одна масть: кружок крупнее, его и читают.
    private var badgeSize: CGFloat {
        if tight && !compact { return 26 }
        return compact && trump != nil ? min(36, height - 16) : min(30, height - 16)
    }

    var body: some View {
        content
            .padding(.horizontal, compact || tight ? 6 : 8)
            .padding(.vertical, 3)
            .frame(height: height - 6)
            .tableSurface(cornerRadius: 14, highlighted: trump != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var content: some View {
        if compact {
            if let trump {
                SuitBadge(suit: trump, size: badgeSize)
            } else {
                // Коротко и без `fixedSize`: в узком ушке у выреза подпись ужимается, а не заходит под вырез.
                Text(shortRoundText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.tableText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        } else if let trump {
            HStack(spacing: tight ? 4 : 6) {
                if !iconTrailing {
                    SuitBadge(suit: trump, size: badgeSize)
                }
                VStack(alignment: iconTrailing ? .trailing : .leading, spacing: 0) {
                    if detail == nil && twoLines {
                        // Без «играет …» — подсказать, что это за масть.
                        Text(forced ? "обязы" : "козырь")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.tableSecondaryText)
                    }
                    Text(TableText.suitTitle(trump))
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.tableText)
                    if let detail, twoLines {
                        Text(detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.tableSecondaryText)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if iconTrailing {
                    SuitBadge(suit: trump, size: badgeSize)
                }
            }
        } else {
            VStack(alignment: iconTrailing ? .trailing : .leading, spacing: 0) {
                if twoLines {
                    Text("Торговля")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.tableText)
                }
                Text(roundText)
                    .font(twoLines ? Theme.Typography.caption : Theme.Typography.label)
                    .foregroundStyle(twoLines ? Theme.tableSecondaryText : Theme.tableText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private var roundText: String {
        switch biddingRound {
        case 2: return Self.roundTexts[1]
        case 0: return Self.roundTexts[2]
        default: return Self.roundTexts[0]
        }
    }

    /// Для самого узкого вида: «круг 1», «круг 2», «все пас».
    private var shortRoundText: String {
        switch biddingRound {
        case 2: return "круг 2"
        case 0: return "все пас"
        default: return "круг 1"
        }
    }

    private var spoken: String {
        if let trump {
            let forcedNote = forced && detail == nil ? ", обязы" : ""
            return "Козырь \(trump.name)" + forcedNote + (detail.map { ", \($0)" } ?? "")
        }
        switch biddingRound {
        case 2: return "Торговля, второй круг"
        case 0: return "Все спасовали, пересдача"
        default: return "Торговля, первый круг"
        }
    }

    /// Ширина самого широкого варианта без подробности (масть с подписью или «Торговля»):
    /// по ней стол заранее решает, поместится ли вдвоём соперник в одну полосу с меню и козырем.
    static func estimatedWidth(_ text: TableTextMetrics, height: CGFloat) -> CGFloat {
        let twoLines = !text.typeSize.isAccessibilitySize
        let suits = Suit.allCases.map { text.width(TableText.suitTitle($0), .label) }.max() ?? 0
        let trumpLines = twoLines
            ? max(suits, text.width("козырь", .caption), text.width("обязы", .caption))
            : suits
        let rounds = roundTexts.map { text.width($0, twoLines ? .caption : .label) }.max() ?? 0
        let bidding = twoLines ? max(text.width("Торговля", .label), rounds) : rounds
        return 16 + max(min(30, height - 16) + 6 + trumpLines, bidding)
    }
}

/// Висячие очки или пересдачи до обязов — золотом под индикатором козыря. На iPhone их больше
/// нигде нет, а вертикальную надпись у края стола пожилому игроку не прочесть, не наклонив голову.
struct PotChip: View {
    let text: String
    /// В две строки — «висят» над «40», «пересдача» над «1 из 2»: где места в ширину мало.
    var twoLines = false
    /// Не помещается и так в предложенную ширину — текст чуть мельче, а не за край экрана.
    var shrinks = false

    var body: some View {
        Text(twoLines ? Self.lines(text).joined(separator: "\n") : text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.gold)
            .multilineTextAlignment(.center)
            .lineLimit(twoLines ? 2 : 1)
            .minimumScaleFactor(shrinks ? 0.7 : 1)
            .fixedSize(horizontal: !shrinks, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .tableSurface(cornerRadius: 10)
            .accessibilityHidden(true)
    }

    /// «висит 21», «висят 40» или «пересдача 1 из 2» (nil — показывать нечего).
    static func text(pot: Int, redeals: Int, forcedAfter: Int) -> String? {
        if pot > 0 { return "\(RuPlural.form(pot, "висит", "висят", "висят")) \(pot)" }
        if redeals > 0 && forcedAfter > 0 { return "пересдача \(redeals) из \(forcedAfter)" }
        return nil
    }

    /// Две строки: первое слово — и остальное.
    private static func lines(_ text: String) -> [String] {
        guard let space = text.firstIndex(of: " ") else { return [text] }
        return [String(text[..<space]), String(text[text.index(after: space)...])]
    }

    /// Ширина плашки с этим текстом — в одну строку или в две.
    static func width(_ text: String, _ metrics: TableTextMetrics, twoLines: Bool = false) -> CGFloat {
        let parts = twoLines ? lines(text) : [text]
        return (parts.map { metrics.width($0, .caption) }.max() ?? 0) + 16
    }

    /// Высота плашки в две строки.
    static func twoLinesHeight(_ metrics: TableTextMetrics) -> CGFloat {
        2 * metrics.lineHeight(.caption) + 6
    }

    /// Ширина с висячими очками — для заранее рассчитанной верхней полосы. Пересдачи подряд бывают редко,
    /// их строка длиннее — тогда плашка соперника рядом на время ужимается (убирает звёзды и полоску).
    static func estimatedWidth(_ text: TableTextMetrics) -> CGFloat {
        width("висят 888", text)
    }
}
