import SwiftUI
import DebercKit

/// Правила — собираются из правил партии (или настроек). Очки карт — наглядной таблицей,
/// значки стола, «О приложении». Кнопка «Поделиться» отправляет правила текстом —
/// чтобы друзья играли по тем же.
struct RulesView: View {
    let rules: RuleSet
    /// Правила новой партии, если они отличаются от правил идущей (`rules`): тогда наверху — переключатель.
    let newGameRules: RuleSet?

    @State private var showNewGameRules = false

    init(rules: RuleSet, newGameRules: RuleSet? = nil) {
        self.rules = rules
        self.newGameRules = newGameRules == rules ? nil : newGameRules
    }

    private var shown: RuleSet {
        showNewGameRules ? (newGameRules ?? rules) : rules
    }

    var body: some View {
        SheetContainer(title: "Правила", sizing: .page) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if newGameRules != nil {
                        ChoiceRow(title: "Какие правила показать",
                                  options: [ChoiceOption(false, "Текущая партия"), ChoiceOption(true, "Новая партия")],
                                  selected: showNewGameRules) { showNewGameRules = $0 }
                    }
                    CardPointsCard(rules: shown)
                    ForEach(RulesText.sections(for: shown), id: \.title) { section in
                        RuleSectionCard(section: section)
                    }
                    TableIconsLegend()
                    AboutCard()
                }
                .padding(16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: RulesShareText.text(for: shown),
                              subject: Text("Деберц — наши правила"),
                              message: Text("Правила, по которым мы играем в деберц")) {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

/// Правила обычным текстом — для «Сообщений», WhatsApp и Telegram (без разметки Markdown).
enum RulesShareText {
    static func text(for rules: RuleSet) -> String {
        var lines = ["Деберц — наши правила", ""]
        for section in RulesText.sections(for: rules) {
            lines.append(section.title.uppercased())
            for item in section.items {
                lines.append("• \(item)")
            }
            lines.append("")
        }
        lines.append("Из приложения «Деберц».")
        return lines.joined(separator: "\n")
    }
}

/// Раздел правил карточкой: заголовок золотом и пункты с точками.
private struct RuleSectionCard: View {
    let section: RulesText.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.gold)
                .accessibilityAddTraits(.isHeader)
            ForEach(section.items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .foregroundStyle(Theme.gold)
                        .accessibilityHidden(true)
                    Text(item)
                        .foregroundStyle(Theme.tableText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableSurface(cornerRadius: 18)
    }
}

/// Очки карт: козыри и остальные масти — мини-картами в порядке старшинства.
private struct CardPointsCard: View {
    let rules: RuleSet

    private let trumpOrder: [Rank] = [.jack, .nine, .ace, .ten, .king, .queen, .eight, .seven]
    private let plainOrder: [Rank] = [.ace, .ten, .king, .queen, .jack, .nine, .eight, .seven]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Очки карт")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.gold)
                .accessibilityAddTraits(.isHeader)
            ranksRow(title: "Козыри — от старшей", suit: .hearts, order: trumpOrder, trump: true)
            ranksRow(title: "Остальные масти", suit: .spades, order: plainOrder, trump: false)
            Text("За последнюю взятку — ещё 10. Терц — \(rules.terzPoints), полтинник — \(rules.fiftyPoints), бэла — \(rules.bellaPoints).")
                .font(.subheadline)
                .foregroundStyle(Theme.tableSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableSurface(cornerRadius: 18)
    }

    private func ranksRow(title: String, suit: Suit, order: [Rank], trump: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.tableText)
            ViewThatFits(in: .horizontal) {
                cardsLine(suit: suit, order: order, trump: trump, width: 40)
                cardsLine(suit: suit, order: order, trump: trump, width: 32)
                cardsLine(suit: suit, order: order, trump: trump, width: 26)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(title: title, suit: suit, order: order))
    }

    private func cardsLine(suit: Suit, order: [Rank], trump: Bool, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { rank in
                let card = Card(rank, suit)
                VStack(spacing: 4) {
                    CardView(card: card, width: width, isTrump: trump)
                    Text("\(card.points(trump: trump ? suit : otherSuit(suit)))")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.tableText)
                }
            }
        }
    }

    private func otherSuit(_ suit: Suit) -> Suit {
        suit == .hearts ? .spades : .hearts
    }

    private func spoken(title: String, suit: Suit, order: [Rank]) -> String {
        let trump = suit == .hearts
        let items = order.map { rank -> String in
            let card = Card(rank, suit)
            return "\(rank.name) — \(card.points(trump: trump ? suit : otherSuit(suit)))"
        }
        return "\(title): " + items.joined(separator: ", ")
    }
}

/// Что значат значки на столе.
struct TableIconsLegend: View {
    private struct Item: Identifiable {
        /// Значок SF Symbols или, если nil, золотая плашка с текстом `tag`.
        let icon: String?
        var tag: String? = nil
        let text: String
        var id: String { icon ?? tag ?? text }
    }

    private let items: [Item] = [
        Item(icon: "hand.tap", text: "Ход: коснитесь карты — она приподнимется, коснитесь ещё раз — сходите. Или бросьте карту пальцем вверх, к центру стола: отпустите у руки — вернётся. Можно вести пальцем по руке."),
        Item(icon: "wand.and.stars", text: "Автоход: последняя карта сдачи ходит сама. В настройках можно выключить или включить автоход для любой вынужденной карты."),
        Item(icon: "star.fill", text: "Золотая звёздочка в углу карты — козырь."),
        Item(icon: "sparkles", text: "Золотое свечение вокруг карты — ею можно ходить."),
        Item(icon: nil, tag: "сдаёт", text: "Метка у игрока — он сдаёт эту сдачу."),
        Item(icon: "circle.dashed", text: "Золотая дуга вокруг аватара — соперник думает."),
        Item(icon: "rectangle.stack", text: "Колода лежит у левого края стола: из-под неё выглядывает открытая карта, ниже — «низ», нижняя карта колоды (её показывают только для сведения)."),
        Item(icon: "text.line.last.and.arrowtriangle.forward", text: "Вдоль правого края стола — до скольких очков идёт партия и сколько очков висит."),
        Item(icon: "person.crop.circle", text: "Коснитесь соперника — его характер, уровень и ваши партии с ним."),
        Item(icon: "lightbulb", text: "Подсказка — совет сильного игрока: как торговаться, менять ли семёрку, чем ходить."),
        Item(icon: "arrow.uturn.backward", text: "Отменить ход — свой ход можно вернуть, пока сдача не закончилась."),
        Item(icon: "eye", text: "Последняя взятка — можно посмотреть, что в неё легло."),
        Item(icon: "pause.circle", text: "Висячие очки достанутся тому, кто наберёт больше всех в следующей сдаче."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Значки на столе")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.gold)
                .accessibilityAddTraits(.isHeader)
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    marker(item)
                        .frame(width: 44)
                        .accessibilityHidden(true)
                    Text(item.text)
                        .foregroundStyle(Theme.tableText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableSurface(cornerRadius: 18)
    }

    @ViewBuilder
    private func marker(_ item: Item) -> some View {
        if let icon = item.icon {
            Image(systemName: icon)
                .foregroundStyle(Theme.gold)
        } else if let tag = item.tag {
            Text(tag)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.onGold)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.gold))
        }
    }
}

/// «О приложении»: версия и где хранятся данные.
private struct AboutCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("О приложении")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.gold)
                .accessibilityAddTraits(.isHeader)
            LabeledContent("Версия", value: AppInfo.version)
                .foregroundStyle(Theme.tableText)
            Text("Любое правило можно поменять: Настройки → Правила партии. Изменения действуют с новой партии.")
                .foregroundStyle(Theme.tableSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Партии, статистика и имя хранятся только на этом устройстве.")
                .foregroundStyle(Theme.tableSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableSurface(cornerRadius: 18)
    }
}
