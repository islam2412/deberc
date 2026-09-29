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
                              subject: Text(RulesShareText.title(for: shown)),
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
    /// «Деберц — домашние правила»; изменённые правила так не назвать — «Деберц — правила партии».
    static func title(for rules: RuleSet) -> String {
        rules == .house ? "Деберц — \(RulesText.houseTitle.lowercased())" : "Деберц — правила партии"
    }

    static func text(for rules: RuleSet) -> String {
        var lines = [title(for: rules), ""]
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
            Text(pointsLine)
                .font(.subheadline)
                .foregroundStyle(Theme.tableSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableSurface(cornerRadius: 18)
    }

    /// «За последнюю взятку — ещё 10. Терц — 20, полтинник — 50, бэла — 20.» (и сотня, если она в правилах).
    private var pointsLine: String {
        let hundred = rules.hundredForFive ? ", сотня (5 подряд) — 100" : ""
        return "За последнюю взятку — ещё 10. Терц — \(rules.terzPoints), полтинник — \(rules.fiftyPoints)"
            + "\(hundred), бэла — \(rules.bellaPoints)."
    }

    private func ranksRow(title: String, suit: Suit, order: [Rank], trump: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.tableText)
            // На iPad карты крупнее — самая большая ширина, что помещается в строку.
            ViewThatFits(in: .horizontal) {
                cardsLine(suit: suit, order: order, trump: trump, width: 64)
                cardsLine(suit: suit, order: order, trump: trump, width: 52)
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
                        .font((width >= 52 ? Font.headline : Font.subheadline).weight(.bold).monospacedDigit())
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

/// «Как ходить» и «Значки на столе». Пункты про касание и автоход собраны из настроек игрока:
/// с выключенным «Ходом в два касания» не обещаем «коснитесь ещё раз», с выключенным автоходом —
/// что последняя карта ходит сама.
struct TableIconsLegend: View {
    @EnvironmentObject private var store: GameStore

    private struct Item: Identifiable {
        /// Значок SF Symbols или, если nil, золотая плашка с текстом `tag`.
        let icon: String?
        var tag: String? = nil
        let text: String
        var id: String { icon ?? tag ?? text }
    }

    private var moveItems: [Item] {
        let settings = store.settings
        return [
            Item(icon: "hand.tap", text: settings.confirmCardTap
                 ? "Ход: коснитесь карты — она приподнимется, коснитесь ещё раз — сходите (настройка «Ход в два касания»)."
                 : "Ход: коснитесь карты — сразу ход. Чтобы сначала приподнимать карту, включите в настройках «Ход в два касания»."),
            Item(icon: "arrow.up", text: "Или потяните карту пальцем вверх, к центру стола, и отпустите — ход сразу. Отпустите у самой руки — карта вернётся."),
            Item(icon: "hand.draw", text: "Ведите пальцем по руке — карта под пальцем приподнимается, её лучше видно. В свой ход отпустите палец — эта карта останется выбранной."),
            Item(icon: "hand.point.up.left", text: "Подержите палец на карте — она покажется крупно. Хода при этом не будет."),
            Item(icon: "wand.and.stars", text: autoPlayText(settings.autoPlay)),
            Item(icon: "arrow.uturn.backward", text: "«Отменить» возвращает только что сделанный ход или заявку — пока соперник не ответил. Заявку, после которой раздали прикуп, решение об обмене семёрки и вынужденную карту отменить нельзя."),
            Item(icon: "lightbulb", text: "Совет — как сыграл бы сильный игрок: как торговаться, менять ли семёрку, чем ходить."),
        ]
    }

    private var tableItems: [Item] {
        [
            Item(icon: "star.fill", text: "Золотая звёздочка в углу карты — козырь."),
            Item(icon: "sparkles", text: "Золотое свечение вокруг карты — ею можно ходить."),
            Item(icon: "seal", text: "Крупная «печать» в центре стола — назначен козырь или объявлены комбинации: какие и у кого старше."),
            Item(icon: nil, tag: "сдаёт", text: "Метка у игрока — он сдаёт эту сдачу."),
            Item(icon: "circle.dashed", text: "Золотая дуга вокруг аватара — соперник думает."),
            Item(icon: "person.crop.circle", text: "Коснитесь соперника — его характер, уровень и ваши партии с ним."),
            Item(icon: "bubble.left", text: banterText(store.settings.banter)),
            Item(icon: "rectangle.stack", text: "Колода лежит у левого края стола: из-под неё выглядывает открытая карта, ниже — «низ», нижняя карта колоды (её показывают только для сведения)."),
            Item(icon: "suit.spade.fill", text: "Вверху справа, в золотой рамке — козырь этой сдачи; во время торговли там написан круг. Золотые надписи «висит 81» и «пересдача 1 из 2» — сколько очков висит и сколько было пересдач подряд."),
            Item(icon: "text.line.last.and.arrowtriangle.forward", text: AppInfo.isPad
                 ? "Вдоль правого края стола — номер сдачи и до скольких очков идёт партия, а на широком экране — в панели справа."
                 : "Вдоль правого края стола — номер сдачи и до скольких очков идёт партия."),
            Item(icon: "eye", text: "Коснитесь стопки взяток — покажется последняя взятка: что в неё легло."),
            Item(icon: "pause.circle", text: "Висячие очки достанутся тому, кто наберёт больше всех в следующей сдаче."),
            Item(icon: "paintpalette", text: "Рубашку карт, четырёхцветную колоду и крупный режим выбирают в Настройках → Вид."),
        ]
    }

    private func autoPlayText(_ mode: AutoPlay) -> String {
        switch mode {
        case .lastCard:
            return "Автоход: последняя карта сдачи ходит сама. В настройках его можно выключить или включить для любой вынужденной карты."
        case .onlyCard:
            return "Автоход: когда ходить можно только одной картой, она ходит сама. Это можно поменять в настройках."
        case .off:
            return "Автоход выключен: все карты кладёте вы сами. В настройках можно включить — тогда последняя карта сдачи будет ходить сама."
        }
    }

    private func banterText(_ level: BanterLevel) -> String {
        level == .off
            ? "Реплики соперников выключены. Включить весёлые подначки у аватара можно в настройках."
            : "Соперники иногда подшучивают — реплика появляется у аватара. Как часто — настройка «Реплики соперников», там же их можно выключить."
    }

    var body: some View {
        VStack(spacing: 16) {
            card(title: "Как ходить", items: moveItems)
            card(title: "Значки на столе", items: tableItems)
        }
    }

    private func card(title: String, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
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
