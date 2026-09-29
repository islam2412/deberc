import SwiftUI
import UIKit
import DebercKit

// Геометрия стола: размеры карт под экран, веер руки, раскладка взятки и открытой карты.
// Чистые вычисления без состояния — их используют и раскладка (касания, подписи),
// и слой карт, поэтому карта под пальцем всегда там, где её видно.

// MARK: - Места на столе

/// Места, которые раскладка стола сообщает слою карт (кадры собираются через anchorPreference).
enum TableSlot: Hashable {
    /// Центр стола: взятка, а во время торговли — открытая карта.
    case center
    /// Рука человека.
    case hand
    /// Плашка игрока.
    case seat(Int)
    /// Веер рубашек соперника.
    case fan(Int)
    /// Стопка взяток игрока.
    case pile(Int)
    /// Колода у левого края стола: рубашки, под ними — открытая карта, ниже — нижняя карта.
    case deck
}

struct TableSlotKey: PreferenceKey {
    static let defaultValue: [TableSlot: Anchor<CGRect>] = [:]

    static func reduce(value: inout [TableSlot: Anchor<CGRect>], nextValue: () -> [TableSlot: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Сообщить слою карт кадр этого места.
    func tableSlot(_ slot: TableSlot) -> some View {
        anchorPreference(key: TableSlotKey.self, value: .bounds) { anchor in [slot: anchor] }
    }
}

// MARK: - Размеры

/// Размеры стола под окно: ширина карт, аватаров, отступы, тип раскладки.
struct TableMetrics: Equatable {
    /// Крупное окно (iPad): крупнее аватары, шрифты и карты.
    let roomy: Bool
    /// Широкое окно (iPad в альбомной ориентации): справа — панель счёта.
    let wide: Bool
    /// Втроём в широком окне соперники сидят слева и справа от центра.
    let sideSeats: Bool
    let large: Bool
    let gutter: CGFloat
    let spacing: CGFloat
    /// Ширина стола: окно без панели счёта справа.
    let tableWidth: CGFloat
    let sidePanelWidth: CGFloat
    let sideSeatWidth: CGFloat
    let topBarHeight: CGFloat
    /// Отступ верхней полосы от края экрана: на iPhone с кнопкой «Домой» строка состояния скрыта
    /// и верхнего отступа безопасной зоны нет — без него меню и плашка соперника касались бы кромки.
    let topPadding: CGFloat
    /// Вдвоём соперник сидит в верхней полосе, между меню и козырем (иначе — строкой ниже).
    /// Решается по ширине окна и размеру текста с запасом на самый длинный счёт, а не по тому,
    /// что сейчас на плашке: иначе полоса перескакивала бы на две строки посреди партии
    /// (счёт стал трёхзначным) и стол вдруг сжимался бы на 70 pt.
    let opponentInTopBar: Bool
    /// iPhone с вырезом или Dynamic Island: строка состояния за столом скрыта, и меню с козырем стоят
    /// в «ушках» по бокам выреза (`TableEarBar`). Полоса под вырезом не нужна — стол выше на 50–60 pt.
    let earBar: Bool
    /// Высота кнопок в ушках (центр — посередине верхнего отступа, там же центр острова).
    /// Не выше 46 pt: у скруглённого угла экрана высокая кнопка задела бы край.
    let earHeight: CGFloat
    /// Ширина правого ушка под козырь: от выреза (с зазором 8 pt) до поля `earTrailing`.
    let earWidth: CGFloat
    /// Две строки подписи козыря помещаются в ушко по высоте.
    let earTwoLines: Bool
    /// Вид козыря в правом ушке — один на всю партию: он выбирается по самой длинной масти и подписи
    /// торговли, а не по той, что сейчас. Иначе от сдачи к сдаче («Пики» и «Трефы») индикатор менял бы вид.
    let earTrumpStyle: EarTrumpStyle
    /// Втроём с ушками: место под висячие очки в левом ушке — от кнопки меню (с зазором 8 pt) до выреза
    /// (с зазором 8 pt). Не помещаются и в две строки — золотым числом на уголке козыря.
    let earLeftSpace: CGFloat
    static let earLeading: CGFloat = 16
    static let earTrailing: CGFloat = 20
    /// Втроём на телефоне — ширина колонки соперника (плашка, веер и стопка): оба соперника с промежутком
    /// 12 pt помещаются между полями. В остальных раскладках — без ограничения.
    let opponentColumnWidth: CGFloat
    let handCardWidth: CGFloat
    let fanCardWidth: CGFloat
    let pileCardWidth: CGFloat
    /// Карты колоды на столе (лёжа, у левого края).
    let deckCardWidth: CGFloat
    let avatarSize: CGFloat
    /// Какая доля высоты карт руки видна: на телефоне (и на iPad в альбомной ориентации) рука уходит
    /// за нижний край экрана — видны уголки с индексами и верх картинки, зато сами карты крупнее.
    let handVisible: CGFloat
    /// На сколько рука приподнята на iPhone с полоской «Домой» (половина нижнего отступа, 17 pt на 14 Pro):
    /// второе быстрое смахивание от нижнего края система забирает себе и уводит на домашний экран.
    /// Карты по-прежнему уходят за край, но уголки с индексами и верх карт, за которые берут карту,
    /// стоят выше — палец реже начинает бросок у самой кромки.
    let handRaise: CGFloat
    /// Поля руки слева и справа.
    let handInset: CGFloat
    /// Высота панели над рукой в розыгрыше: «Ваш ход» с двумя строками подписи. «Ходит Саша…» получает
    /// ту же высоту — центр стола, колода и взятка не подпрыгивают при каждой смене хода.
    let actionMinHeight: CGFloat
    /// Высота мини-карт в отметках комбинаций у мест (в крупном режиме — крупнее).
    let tileHeight: CGFloat

    /// `safeTop`, `bottomInset` — отступы безопасной зоны (на телефоне рука ложится до самого нижнего края).
    /// `typeSize` — размер текста за столом (`TableMetrics.typeSize`): по нему оцениваются высоты полос
    /// вокруг центра, иначе при крупном тексте всё сжатие доставалось бы центру.
    init(size: CGSize, playerCount: Int, large: Bool, safeTop: CGFloat = 0, bottomInset: CGFloat = 0,
         typeSize: DynamicTypeSize = .large) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let roomy = width >= 600 && height >= 640
        let wide = roomy && width >= 900 && width > height * 1.2
        let sideSeats = wide && playerCount == 3
        self.roomy = roomy
        self.wide = wide
        self.sideSeats = sideSeats
        self.large = large
        let gutter: CGFloat = roomy ? 20 : 12
        let spacing: CGFloat = roomy ? 10 : 6
        self.gutter = gutter
        self.spacing = spacing
        sidePanelWidth = wide ? min(340, (width * 0.27).rounded()) : 0
        let tableWidth = width - sidePanelWidth
        self.tableWidth = tableWidth
        sideSeatWidth = sideSeats ? min(240, (tableWidth * 0.22).rounded()) : 0
        let topBarHeight: CGFloat = roomy ? (large ? 72 : 62) : (large ? 60 : 50)
        self.topBarHeight = topBarHeight
        let topPadding: CGFloat = !roomy && safeTop < 1 ? 6 : 0
        self.topPadding = topPadding
        let avatarSize: CGFloat = roomy ? (large ? 64 : 56) : (large ? 48 : 42)
        self.avatarSize = avatarSize
        // Колода на столе — не главное: в крупном режиме она не растёт (её место отнимало бы ширину
        // у взятки, и крупный режим делал бы карты на столе мельче). На 320 pt — 43 вместо 52:
        // там центр узкий, и лежащая колода иначе теснила бы взятку.
        deckCardWidth = roomy ? (large ? 66 : 60) : min(52, (width * 0.135).rounded())
        let tileHeight: CGFloat = roomy ? (large ? 36 : 32) : (large ? 30 : 24)
        self.tileHeight = tileHeight

        let text = TableTextMetrics(typeSize: typeSize)
        // Кнопки стола (`TableButtonStyle`): не ниже 48/60 pt, с крупным текстом — выше.
        let buttonHeight = max(large ? 60 : 48, text.lineHeight(large ? .title3 : .seatName) + (large ? 28 : 24))
        let actionMinHeight = max(roomy ? (large ? 72 : 62) : (large ? 64 : 52), buttonHeight,
                                  text.lineHeight(.seatName) + 2 + 2 * text.lineHeight(.caption)).rounded(.up)
        self.actionMinHeight = actionMinHeight

        // Вдвоём: меню, плашка соперника с самым длинным счётом («−888») и именем, козырь с висячими очками.
        // Обычный текст: 44 + 32 + 129 + 103 ≈ 308 — помещается на 393 и 375 pt (369 и 351 между полями),
        // на 320 pt (296) — нет: соперник строкой ниже, как и раньше. Крупный режим: ≈ 338 — одна полоса
        // и на 375 pt; крупный режим с системным AX1: ≈ 376 — две полосы и на 393 pt.
        let menuSize: CGFloat = roomy ? 50 : 44
        let fanCap = TableMetrics.fanWidth(hand: .greatestFiniteMagnitude, roomy: roomy)
        let plateMin = 8 + avatarSize + 10 + max(text.width("Борис", .seatName), text.width("−888", .score)) + 12
        let rightColumn = max(TrumpBadge.estimatedWidth(text, height: topBarHeight), PotChip.estimatedWidth(text))
        opponentInTopBar = playerCount == 2
            && tableWidth - 2 * gutter >= menuSize + 4 * 8 + max(plateMin, (fanCap * 3.6).rounded()) + rightColumn

        // Ушки: вырез есть, если верхний отступ большой (без строки состояния у iPhone без выреза он 0).
        // Dynamic Island — 126 pt в ширину (при «Увеличенном» виде — пропорционально меньше); у него
        // отступ ≥ 51 pt, а при «Увеличенном» виде — 0,15 ширины. Вырез — оценка сверху: до 56 % ширины.
        let earBar = !roomy && safeTop >= 40
        self.earBar = earBar
        if earBar {
            let island = safeTop >= 51 || safeTop / width >= 0.145
            let cutout = island ? 126 * min(1, width / 393) : min(width * 0.56, 230)
            // У выреза верхний отступ меньше (44–50 pt), чем у острова, — ушко выше за счёт полей:
            // 40 pt на 12–14 и 16e, 37 на X/XS/11 Pro, 41 на 11/XR, 43 на mini.
            let earHeight = island ? min(46, safeTop - 13) : min(44, safeTop - 7)
            self.earHeight = earHeight
            let earWidth = max(0, ((width - cutout) / 2 - 8 - TableMetrics.earTrailing).rounded(.down))
            self.earWidth = earWidth
            let earTwoLines = text.lineHeight(.caption) + text.lineHeight(.label) + 6 <= earHeight
            self.earTwoLines = earTwoLines
            earLeftSpace = max(0, ((width - cutout) / 2 - TableMetrics.earLeading - 44 - 16).rounded(.down))
            // Вид козыря — по самой длинной масти и по подписи торговли (до козыря бейдж пишет круг торговли,
            // без значка масти): помещаются оба — этот вид и берём на всю партию.
            let suits = Suit.allCases.map { text.width(TableText.suitTitle($0), .label) }.max() ?? 0
            let rounds = TrumpBadge.roundTexts.map { text.width($0, .label) }.max() ?? 0
            let roundCaptions = TrumpBadge.roundTexts.map { text.width($0, .caption) }.max() ?? 0
            let badge = min(30, earHeight - 10)
            let twoLinesWidth = max(16 + badge + 6 + max(suits, text.width("козырь", .caption), text.width("обязы", .caption)),
                                    16 + max(text.width("Торговля", .label), roundCaptions))
            if earTwoLines && twoLinesWidth <= earWidth {
                earTrumpStyle = .twoLines
            } else if max(16 + badge + 6 + suits, 16 + rounds) <= earWidth {
                earTrumpStyle = .oneLine
            } else if max(12 + 26 + 4 + suits, 12 + rounds) <= earWidth {
                earTrumpStyle = .tight
            } else {
                earTrumpStyle = .compact
            }
        } else {
            earHeight = 0
            earWidth = 0
            earTwoLines = false
            earTrumpStyle = .compact
            earLeftSpace = 0
        }

        let handUnderEdge = !roomy || wide
        let handVisible: CGFloat = handUnderEdge ? (roomy ? 0.75 : (large ? 0.66 : 0.72)) : 1
        let handRaise: CGFloat = handUnderEdge ? (bottomInset * 0.5).rounded() : 0
        // В крупном режиме индекс шире — шаг веера больше; чтобы карты от этого не мельчали,
        // рука на телефоне заходит в поля (4 pt от края вместо 12).
        let handInset: CGFloat = !roomy && large ? 4 : gutter
        let liftShare: CGFloat = roomy ? 0.22 : 0.3
        self.handVisible = handVisible
        self.handRaise = handRaise
        self.handInset = handInset

        let hand: CGFloat
        if handUnderEdge {
            // Телефон и iPad в альбомной ориентации: 9 карт внахлёст так, что видны уголки с индексами
            // (у крупных индексов уголок шире: шаг 0,315w вместо 0,29w), а над рукой — центр, где взятка
            // не меньше ≈ 0,87 карты руки. Всё, что вокруг центра, оценивается по размеру текста:
            // при крупном тексте рука мельчает, а не центр схлопывается.
            let byWidth = roomy
                ? (tableWidth - 2 * gutter) / 4.6
                : (tableWidth - 2 * handInset) / (large ? 3.52 : 3.3)
            let cap: CGFloat = roomy ? (large ? 180 : 165) : (large ? 132 : 120)
            let plate = max(avatarSize, text.lineHeight(.seatName) + 1 + text.lineHeight(.score)) + 12
            // Веер и стопка соперника — как у самой крупной руки, что помещается по ширине: с запасом,
            // но на узком экране (320 pt) веер мельче, и центру остаётся больше.
            let widest = min(cap, byWidth)
            let fanSlotHeight = (TableMetrics.fanWidth(hand: widest, roomy: roomy) * CardView.aspectRatio).rounded() + 4
            let pileSlotHeight = TableMetrics.pileWidth(hand: widest, roomy: roomy) + 12
            let top: CGFloat
            if sideSeats {
                top = topBarHeight
            } else if playerCount == 3 {
                top = (earBar ? 0 : topBarHeight + spacing) + plate + spacing + max(fanSlotHeight, pileSlotHeight)
            } else if earBar {
                top = plate + 4 + fanSlotHeight
            } else if opponentInTopBar {
                top = max(topBarHeight, plate + 4 + fanSlotHeight)
            } else {
                top = topBarHeight + spacing + plate + 4 + fanSlotHeight
            }
            let strip = max(roomy ? 50 : 40, text.lineHeight(.score) + 8, 2 * text.lineHeight(.caption), tileHeight + 8)
            // Промежутки колонки стола; втроём с ушками верхней полосы нет — на один меньше.
            let gaps = CGFloat(playerCount == 3 && !sideSeats && !earBar ? 5 : 4) * spacing
            // Центр и рука вместе (рука — видимая часть карты, подъём выбранной и приподнятость над краем).
            let room = height + bottomInset - topPadding - top - strip - actionMinHeight - gaps - handRaise
            let handShare = handVisible * CardView.aspectRatio + liftShare
            // Взятка по высоте — (центр − 44) / 2,54w; центр ≥ 2,2w + 44 даёт взятку ≥ 0,87 карты руки.
            let byTrick = (room - TrickGeometry.topInset - 8) / (handShare + 2.2)
            var byHero = CGFloat.greatestFiniteMagnitude
            if !roomy {
                // Во 2-м круге торговли кнопки мастей — в два ряда, центр ниже на столько же;
                // открытой карте там — не меньше 0,75 карты руки (в 1-м круге и в розыгрыше места больше).
                // Строже нельзя: на 320 pt и на iPhone SE втроём рука мельчала бы ради нескольких секунд торговли.
                let biddingExtra = max(0, 2 * buttonHeight + 8 - actionMinHeight)
                byHero = (room - biddingExtra - TrickGeometry.topInset - HeroGeometry.captionSpace)
                    / (handShare + 0.75 * CardView.aspectRatio * 1.04)
            }
            hand = max(44, min(cap, byWidth, byTrick, byHero)).rounded()
        } else {
            // iPad стоя: карта видна целиком; 9 карт внахлёст по ширине и место под взятку по высоте.
            let byWidth = (tableWidth - 2 * gutter) / 4.6
            let plate: CGFloat = 84
            let opponents: CGFloat
            if playerCount == 3 {
                opponents = plate + spacing + 64
            } else {
                opponents = 64
            }
            let chrome = topBarHeight + opponents + 50 + 70 + 5 * spacing + (large ? 30 : 0)
            let byHeight = (height - chrome) / 4.6
            hand = max(44, min(large ? 180 : 165, byWidth, byHeight)).rounded()
        }
        handCardWidth = hand
        var fan = TableMetrics.fanWidth(hand: hand, roomy: roomy)
        var pile = TableMetrics.pileWidth(hand: hand, roomy: roomy)
        var column = CGFloat.infinity
        if playerCount == 3 && !sideSeats && handUnderEdge {
            // Втроём на телефоне два соперника стоят в ряд: веер и стопка каждого — в пол-стола
            // (2 pt запаса на округления). На 320 pt веер чуть мельче, на 375–440 pt — как был.
            column = ((tableWidth - 2 * gutter - 12) / 2 - 2).rounded(.down)
            func stack(_ f: CGFloat, _ p: CGFloat) -> CGFloat {
                (f * 3.6).rounded() + 8 + (p * CardView.aspectRatio).rounded() + 12
            }
            while stack(fan, pile) > column && (fan > 18 || pile > 16) {
                if fan > 18 { fan -= 1 } else { pile -= 1 }
            }
        }
        opponentColumnWidth = column
        fanCardWidth = fan
        pileCardWidth = pile
        #if DEBUG
        if earBar {
            assert(earWidth >= 44, "Ушко меньше 44 pt в ширину: \(earWidth)")
        }
        if column.isFinite {
            assert(2 * (fanSlotSize.width + 8 + pileSlotSize.width) + 12 + 2 * gutter <= tableWidth + 0.5,
                   "Соперники втроём не помещаются в \(tableWidth) pt")
        }
        #endif
    }

    /// Вид козыря в правом ушке (`TableEarBar`), от просторного к тесному.
    enum EarTrumpStyle {
        /// «козырь» над названием масти, значок 30 pt.
        case twoLines
        /// Название масти в одну строку, значок 30 pt.
        case oneLine
        /// Название масти, поля и промежуток поменьше, значок 26 pt.
        case tight
        /// Один значок масти (до козыря — «круг 1»).
        case compact
    }

    /// Вдвоём с ушками: место справа от веера соперника под висячие очки — от веера (с зазором 8 pt) до поля.
    var fanSideSpace: CGFloat {
        max(0, ((tableWidth - fanSlotSize.width) / 2 - 8 - gutter).rounded(.down))
    }

    #if DEBUG
    /// Самопроверка раскладки (`-DebercLayoutCheck`): что на этом размере не помещается; пусто — всё в порядке.
    var layoutProblems: [String] {
        var problems: [String] = []
        if opponentColumnWidth.isFinite {
            let row = 2 * (fanSlotSize.width + 8 + pileSlotSize.width) + 12 + 2 * gutter
            if row > tableWidth + 0.5 {
                problems.append("соперники втроём: \(row) pt при ширине \(tableWidth)")
            }
            if fanSlotSize.width + 8 + pileSlotSize.width > opponentColumnWidth {
                problems.append("веер и стопка шире колонки \(opponentColumnWidth)")
            }
        }
        if earBar {
            if earWidth < 44 { problems.append("ушко \(earWidth) pt в ширину — меньше 44") }
            if earHeight < 34 { problems.append("ушко низкое: \(earHeight) pt") }
            // Самый узкий вид козыря — значок масти с полями.
            if 12 + min(36, earHeight - 10) > earWidth { problems.append("значок козыря не помещается в ушко") }
        }
        return problems
    }
    #endif

    /// Карты веера соперника — по руке.
    private static func fanWidth(hand: CGFloat, roomy: Bool) -> CGFloat {
        roomy ? min(54, max(22, (hand * 0.34).rounded())) : min(30, max(22, (hand * 0.28).rounded()))
    }

    /// Карты стопки взяток — по руке.
    private static func pileWidth(hand: CGFloat, roomy: Bool) -> CGFloat {
        roomy ? min(44, max(20, (hand * 0.28).rounded())) : min(26, max(20, (hand * 0.24).rounded()))
    }

    /// Насколько приподнимается выбранная карта (на телефоне заметнее: рука уходит за край экрана).
    var handLift: CGFloat { (handCardWidth * (roomy ? 0.22 : 0.3)).rounded() }
    /// Видимая высота руки: карта (без ушедшей за край части), приподнятость над краем и подъём выбранной.
    var handHeight: CGFloat { (handCardWidth * CardView.aspectRatio * handVisible + handRaise + handLift).rounded() }
    /// Карты взятки бывают крупнее карт руки — во сколько раз самое большее.
    var trickScale: CGFloat { roomy ? 1.1 : 1.3 }
    /// Ширина, в которой рисуются карты руки и взятки (одна для всех мест, чтобы карта летела без скачков):
    /// по самой крупной — картинка остаётся чёткой.
    var renderCardWidth: CGFloat { min(200, (handCardWidth * trickScale).rounded()) }
    /// Ширина, в которой рисуется открытая карта в центре во время торговли.
    var heroRenderWidth: CGFloat { min(200, (handCardWidth * max(1.2, trickScale)).rounded()) }
    var fanSlotSize: CGSize {
        CGSize(width: (fanCardWidth * 3.6).rounded(), height: (fanCardWidth * CardView.aspectRatio).rounded() + 4)
    }
    var pileSlotSize: CGSize {
        CGSize(width: (pileCardWidth * CardView.aspectRatio).rounded() + 12, height: pileCardWidth + 12)
    }
    var deckSlotSize: CGSize { DeckGeometry.slotSize(cardWidth: deckCardWidth) }
    /// Сдвиг колоды влево от края центра (iPad, соперники по бокам): центр там узкий, и колода у его края
    /// упиралась бы во взятку. Рубашки уходят в промежуток до колонки левого соперника — ровно до его
    /// стопки взяток (она по центру колонки), внизу, под веером. 11" в альбомной ориентации: ≈ −30 pt.
    var deckShift: CGFloat {
        guard sideSeats else { return 0 }
        let h = deckCardWidth * CardView.aspectRatio
        // Левый край лежащих рубашек — на 0,42 их длины левее края места колоды; до стопки — 4 pt.
        return min(0, (pileSlotSize.width - sideSeatWidth) / 2 - 8 + 0.42 * h)
    }
    /// Кегль вертикальной надписи «сдача · до 701» у правого края: растёт в крупном режиме и на iPad.
    var matchLabelSize: CGFloat { roomy ? (large ? 21 : 19) : (large ? 17 : 15) }

    /// Размер текста за столом: на iPad крупнее, на iPhone — с потолком, чтобы стол не разъезжался;
    /// крупный режим поднимает на две ступени. На узком экране (iPhone с «Увеличенным» видом, 320 pt)
    /// потолок ниже: там всё и так крупнее на четверть, а с бо́льшим текстом кнопки торговли уходят
    /// во второй ряд и сжимают стол.
    static func typeSize(system: DynamicTypeSize, size: CGSize, large: Bool) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        var result = system
        let roomy = size.width >= 600 && size.height >= 640
        if roomy {
            let floor: DynamicTypeSize = size.height >= 820 && size.width >= 700 ? .xxxLarge : .xLarge
            result = max(result, floor)
        }
        if large, let index = all.firstIndex(of: result) {
            result = all[min(all.count - 1, index + 2)]
        }
        let cap: DynamicTypeSize
        if roomy {
            cap = .accessibility2
        } else if size.width < 350 {
            cap = .xxLarge
        } else {
            cap = large ? .accessibility1 : .xxLarge
        }
        return min(result, cap)
    }
}

/// Размеры текста стола при заданном размере шрифта — те же стили, что в `Theme.Typography`.
/// По ним раскладка заранее оценивает высоты полос и ширину верхней полосы. Мерить готовую раскладку
/// (PreferenceKey) и по замеру менять размер карт нельзя: карты меняют раскладку, и она могла бы колебаться.
struct TableTextMetrics {
    enum Style {
        /// `Theme.Typography.caption`: footnote, полужирный.
        case caption
        /// `Theme.Typography.label`: subheadline, полужирный.
        case label
        /// `Theme.Typography.seatName`, `banner`: headline.
        case seatName
        /// `Theme.Typography.score`: title2, жирный, цифры одной ширины.
        case score
        /// Крупные кнопки стола: title3, полужирный.
        case title3
    }

    let typeSize: DynamicTypeSize

    func font(_ style: Style) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        func size(_ textStyle: UIFont.TextStyle) -> CGFloat {
            UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits).pointSize
        }
        switch style {
        case .caption: return .systemFont(ofSize: size(.footnote), weight: .semibold)
        case .label: return .systemFont(ofSize: size(.subheadline), weight: .semibold)
        case .seatName: return .systemFont(ofSize: size(.headline), weight: .semibold)
        case .score: return .monospacedDigitSystemFont(ofSize: size(.title2), weight: .bold)
        case .title3: return .systemFont(ofSize: size(.title3), weight: .semibold)
        }
    }

    /// Высота строки.
    func lineHeight(_ style: Style) -> CGFloat {
        font(style).lineHeight.rounded(.up)
    }

    /// Ширина строки в одну линию.
    func width(_ text: String, _ style: Style) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font(style)]).width.rounded(.up)
    }
}

// MARK: - Веер руки

/// Карта, которую человек тянет пальцем из руки, чтобы бросить на стол.
struct HandDrag: Equatable {
    var card: Card
    /// Смещение от места карты в руке.
    var translation: CGSize
    /// Этой картой можно ходить: она идёт за пальцем. Нельзя — лишь чуть поддаётся.
    var playable: Bool
    /// Долгое нажатие: карту рассматривают — крупно над рукой, ход не делается.
    var preview = false
    /// Палец просто лежит на карте или ведёт по руке: карта чуть приподнята над соседними.
    var hover = false
}

enum HandFan {
    /// Лёгкий веер, как в руке у живого игрока: крайние карты чуть повёрнуты и опущены.
    static func arc(index i: Int, count n: Int, cardWidth w: CGFloat) -> (angle: Double, dy: CGFloat) {
        guard n > 1 else { return (0, 0) }
        let mid = Double(n - 1) / 2
        let t = (Double(i) - mid) / mid
        let spread = min(8, 1.5 * mid)
        return (t * spread, CGFloat(t * t) * w * 0.06)
    }

    /// Центры карт веера по x (от левого края области). Между мастями — зазор, чтобы пики и трефы
    /// не сливались: просторно — 0,12 ширины карты, теснее — 0,05. Зазор допустим, пока шаг карт
    /// не меньше 0,3 ширины: так открыт уголок даже с крупным индексом (обычный занимает 0,245w,
    /// крупный — до 0,31–0,345w). На телефоне шаг полной руки без зазоров ≈ 0,29w (крупный режим — 0,315w),
    /// поэтому при 9 картах зазоров нет, а с 8 карт уже есть.
    static func centers(for cards: [Card], width: CGFloat, cardWidth w: CGFloat) -> [CGFloat] {
        let n = cards.count
        guard n > 0 else { return [] }
        guard n > 1 else { return [width / 2] }
        var breaks = 0
        for i in 1..<n where cards[i].suit != cards[i - 1].suit {
            breaks += 1
        }
        func stepWith(gap: CGFloat) -> CGFloat {
            min(w * 0.92, (width - w - CGFloat(breaks) * gap) / CGFloat(n - 1))
        }
        // Тесно — зазоры между мастями не помещаются.
        var gap: CGFloat = 0
        var step = stepWith(gap: 0)
        for share in [0.12, 0.05] as [CGFloat] where breaks > 0 {
            let candidate = (w * share).rounded()
            if stepWith(gap: candidate) >= w * 0.3 {
                gap = candidate
                step = stepWith(gap: candidate)
                break
            }
        }
        step = max(step, 1)
        let total = w + step * CGFloat(n - 1) + gap * CGFloat(breaks)
        var x = max(0, (width - total) / 2) + w / 2
        var result: [CGFloat] = [x]
        for i in 1..<n {
            x += step
            if cards[i].suit != cards[i - 1].suit {
                x += gap
            }
            result.append(x)
        }
        return result
    }

    /// Насколько карта руки опущена от верха области руки: выбранная — наверху, допустимые в ваш ход —
    /// на полподъёма ниже, остальные — на весь подъём. Одна формула и для рисования, и для касаний.
    static func rise(selected: Bool, legal: Bool, active: Bool, lift: CGFloat) -> CGFloat {
        if selected { return 0 }
        return active && legal ? lift * 0.5 : lift
    }

    /// Насколько выше поднимается карта под пальцем (недопустимая в ваш ход — едва-едва).
    static func hoverRise(legal: Bool, active: Bool, lift: CGFloat) -> CGFloat {
        active && !legal ? lift * 0.15 : lift * 0.45
    }

    /// Карта под точкой касания — по видимым картам: с их подъёмом и наклоном веера, сверху вниз.
    /// `tops[i]` — верхняя кромка карты i от верха области руки. Мимо всех карт — ближайшая по x.
    static func index(at point: CGPoint, centers: [CGFloat], tops: [CGFloat], cardWidth w: CGFloat) -> Int? {
        let n = centers.count
        guard n > 0, tops.count == n else { return index(at: point.x, centers: centers, cardWidth: w) }
        let h = w * CardView.aspectRatio
        for i in stride(from: n - 1, through: 0, by: -1) {
            let arc = HandFan.arc(index: i, count: n, cardWidth: w)
            let center = CGPoint(x: centers[i], y: tops[i] + arc.dy + h / 2)
            // Точка в системе карты: поворот обратно на наклон веера.
            let a = -arc.angle * .pi / 180
            let dx = point.x - center.x, dy = point.y - center.y
            let x = dx * cos(a) - dy * sin(a)
            let y = dx * sin(a) + dy * cos(a)
            // Небольшой запас по краям — пальцем не всегда попадают точно.
            if abs(x) <= w / 2 + 2 && y >= -h / 2 - 4 && y <= h / 2 {
                return i
            }
        }
        return index(at: point.x, centers: centers, cardWidth: w)
    }

    /// Карта под пальцем по одной координате x: самая верхняя (правая) из тех, чья левая кромка левее точки.
    static func index(at x: CGFloat, centers: [CGFloat], cardWidth w: CGFloat) -> Int? {
        guard let first = centers.first, let last = centers.last else { return nil }
        guard x >= first - w / 2 - 12, x <= last + w / 2 + 12 else { return nil }
        var i = centers.count - 1
        while i > 0 && x < centers[i] - w / 2 {
            i -= 1
        }
        return i
    }
}

// MARK: - Взятка

enum TrickGeometry {
    /// Верхняя полоса центра остаётся под реплики и комбинации соперников.
    static let topInset: CGFloat = 36

    /// Ширина карты взятки: крупно, но так, чтобы вся взятка помещалась в центр
    /// и не заходила на колоду у левого края (`deck` — её место).
    ///
    /// Колоду проверяем по настоящим контурам: карты взятки повёрнуты (втроём левая — на −10°,
    /// и её описанный прямоугольник шире на четверть), а колода занимает не всю высоту центра.
    /// Поэтому ищем самую крупную карту, при которой ни одна карта взятки не задевает колоду;
    /// если колода по высоте в стороне (втроём она внизу слева, на iPad — сбоку), взятка растёт до высоты центра.
    static func cardWidth(center: CGRect, playerCount: Int, metrics: TableMetrics, deck: CGRect?) -> CGFloat {
        let h = max(40, center.height - topInset - 8)
        let byHeight = h / (CardView.aspectRatio * 1.75)
        let byWidth = (center.width - 16) / (playerCount == 3 ? 2.5 : 1.7)
        let largest = max(30, min(metrics.handCardWidth * metrics.trickScale, 200, byHeight, byWidth))
        guard let deck else { return largest }
        let obstacles = DeckGeometry.footprint(deck, cardWidth: metrics.deckCardWidth)
        func fits(_ w: CGFloat) -> Bool {
            (0..<playerCount).allSatisfy { relative in
                let (position, angle) = point(relative: relative, playerCount: playerCount, center: center, cardWidth: w)
                let card = CardFootprint(center: position, width: w, angle: angle)
                return !obstacles.contains { card.intersects($0) }
            }
        }
        if fits(largest) { return largest }
        var low: CGFloat = 30
        var high = largest
        guard fits(low) else { return low }
        // Чем крупнее взятка, тем ближе её карты к колоде — делим отрезок пополам (точность — доли пункта).
        for _ in 0..<14 {
            let middle = (low + high) / 2
            if fits(middle) {
                low = middle
            } else {
                high = middle
            }
        }
        return low.rounded(.down)
    }

    /// Центр взятки.
    static func clusterCenter(_ center: CGRect) -> CGPoint {
        CGPoint(x: center.midX, y: center.minY + topInset + (center.height - topInset) / 2)
    }

    /// Смещение от центра взятки и наклон карты места (`relative` — место относительно человека:
    /// 0 — вы, 1 — следующий, 2 — третий). Карты лежат внахлёст, как на живом столе.
    static func offset(relative: Int, playerCount: Int, cardWidth w: CGFloat) -> (dx: CGFloat, dy: CGFloat, angle: Double) {
        let h = w * CardView.aspectRatio
        if playerCount == 2 {
            return relative == 0 ? (w * 0.28, h * 0.30, -4) : (-w * 0.28, -h * 0.36, 6)
        }
        switch relative {
        case 0: return (0, h * 0.32, -2)
        case 1: return (-w * 0.62, -h * 0.22, -10)
        default: return (w * 0.62, -h * 0.22, 10)
        }
    }

    /// Точка карты места на столе.
    static func point(relative: Int, playerCount: Int, center: CGRect, cardWidth w: CGFloat) -> (CGPoint, Double) {
        let c = clusterCenter(center)
        let o = offset(relative: relative, playerCount: playerCount, cardWidth: w)
        return (CGPoint(x: c.x + o.dx, y: c.y + o.dy), o.angle)
    }
}

/// Контур повёрнутой карты на столе — чтобы проверить, не наезжает ли она на колоду.
struct CardFootprint {
    let corners: [CGPoint]

    /// `angle` — как у `rotationEffect`: в градусах, по часовой стрелке.
    init(center: CGPoint, width w: CGFloat, angle: Double) {
        let h = w * CardView.aspectRatio
        let radians = angle * .pi / 180
        let c = CGFloat(cos(radians)), s = CGFloat(sin(radians))
        corners = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)].map { dx, dy in
            CGPoint(x: center.x + dx * c - dy * s, y: center.y + dx * s + dy * c)
        }
    }

    /// Пересекается ли карта с прямоугольником: ищем разделяющую ось среди сторон обоих.
    func intersects(_ rect: CGRect) -> Bool {
        let box = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                   CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        let axes = [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1),
                    CGPoint(x: corners[1].x - corners[0].x, y: corners[1].y - corners[0].y),
                    CGPoint(x: corners[2].x - corners[1].x, y: corners[2].y - corners[1].y)]
        for axis in axes {
            let card = corners.map { $0.x * axis.x + $0.y * axis.y }
            let other = box.map { $0.x * axis.x + $0.y * axis.y }
            if let cardMax = card.max(), let cardMin = card.min(), let otherMax = other.max(), let otherMin = other.min(),
               cardMax < otherMin || otherMax < cardMin {
                return false
            }
        }
        return true
    }
}

// MARK: - Колода на столе

/// Колода у левого края стола, как на живом столе: рубашки лёжа (частично за краем экрана),
/// из-под них выглядывает открытая карта, ниже — нижняя карта колоды с подписью «низ».
enum DeckGeometry {
    /// Место под колоду: ширина лёжащей карты с выглядывающей открытой, высота — колода и нижняя карта.
    static func slotSize(cardWidth w: CGFloat) -> CGSize {
        let h = w * CardView.aspectRatio
        return CGSize(width: (h * 1.1).rounded(), height: (w + 10 + h * 0.9).rounded())
    }

    /// Центр колоды (рубашки лёжа): почти половина — за левым краем.
    static func stockCenter(_ slot: CGRect, cardWidth w: CGFloat) -> CGPoint {
        let h = w * CardView.aspectRatio
        return CGPoint(x: slot.minX + h * 0.08, y: slot.minY + w / 2)
    }

    /// Открытая карта — под колодой, выглядывает вправо уголком с индексом.
    static func openCenter(_ slot: CGRect, cardWidth w: CGFloat) -> CGPoint {
        let stock = stockCenter(slot, cardWidth: w)
        return CGPoint(x: stock.x + w * CardView.aspectRatio * 0.52, y: stock.y + 2)
    }

    /// Нижняя карта — стоя, под колодой, чуть мельче.
    static func bottomCenter(_ slot: CGRect, cardWidth w: CGFloat) -> CGPoint {
        let small = w * 0.9
        return CGPoint(x: slot.minX + small / 2 + 6, y: slot.minY + w + 10 + small * CardView.aspectRatio / 2)
    }

    static func bottomWidth(cardWidth w: CGFloat) -> CGFloat { w * 0.9 }

    /// Что колода занимает на столе, с небольшим запасом: полоса лежащих рубашек с выглядывающей
    /// открытой картой и нижняя карта (наклонена на 4° — берём описанный прямоугольник).
    static func footprint(_ slot: CGRect, cardWidth w: CGFloat) -> [CGRect] {
        let h = w * CardView.aspectRatio
        let stock = stockCenter(slot, cardWidth: w)
        let open = openCenter(slot, cardWidth: w)
        // Слои рубашек сдвинуты до 2,6 pt вверх, открытая карта — на 2 pt ниже колоды.
        let lying = CGRect(x: stock.x - h / 2, y: stock.y - w / 2 - 3,
                           width: open.x + h / 2 - (stock.x - h / 2), height: w + 5)
        let bw = bottomWidth(cardWidth: w)
        let bh = bw * CardView.aspectRatio
        let tilt = CGFloat(sin(4 * Double.pi / 180))
        let bottom = bottomCenter(slot, cardWidth: w)
        let bottomRect = CGRect(x: bottom.x - bw / 2 - bh / 2 * tilt, y: bottom.y - bh / 2 - bw / 2 * tilt,
                                width: bw + bh * tilt, height: bh + bw * tilt)
        return [lying, bottomRect].map { $0.insetBy(dx: -4, dy: -2) }
    }
}

// MARK: - Открытая карта во время торговли

enum HeroGeometry {
    /// Место под открытой картой: подпись в две строки или однострочное сообщение внизу центра
    /// (пока видно сообщение, подпись прячется — они не лежат друг на друге).
    static let captionSpace: CGFloat = 48

    static func cardWidth(center: CGRect, handCardWidth: CGFloat) -> CGFloat {
        let byHeight = (center.height - TrickGeometry.topInset - captionSpace) / (CardView.aspectRatio * 1.04)
        let byWidth = (center.width - 32) / 1.8
        return max(34, min(handCardWidth * 1.3, 200, byHeight, byWidth))
    }

    /// Центр пары «колода + открытая карта».
    static func center(_ center: CGRect) -> CGPoint {
        CGPoint(x: center.midX,
                y: center.minY + TrickGeometry.topInset + (center.height - TrickGeometry.topInset - captionSpace) / 2)
    }

    /// Колода — чуть левее, открытая карта — правее с перекрытием, лицом к игроку.
    static func stockPoint(_ center: CGRect, cardWidth w: CGFloat) -> CGPoint {
        let c = self.center(center)
        return CGPoint(x: c.x - w * 0.32, y: c.y)
    }

    static func openPoint(_ center: CGRect, cardWidth w: CGFloat) -> CGPoint {
        let c = self.center(center)
        return CGPoint(x: c.x + w * 0.32, y: c.y + 2)
    }

    /// Верх подписи под картой: подпись растёт вниз, а не наезжает на карту при крупном тексте.
    static func captionTop(_ center: CGRect, cardWidth w: CGFloat) -> CGFloat {
        self.center(center).y + w * CardView.aspectRatio / 2 + 6
    }
}

// MARK: - Тексты стола

enum TableText {
    /// Русское множественное число: 1 очко, 2 очка, 5 очков.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        RuPlural.form(n, one, few, many)
    }

    /// Число со знаком минус U+2212.
    static func number(_ n: Int) -> String {
        Narrator.number(n)
    }

    /// «Черви», «Пики».
    static func suitTitle(_ suit: Suit) -> String {
        let name = suit.name
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Масть в родительном падеже: «кроме пик», «кроме червей».
    static func suitGenitive(_ suit: Suit) -> String {
        Narrator.suitGenitive(suit)
    }

    /// Текст с мастями своего цвета (масти — всегда текстом, не эмодзи).
    /// `onLight` — на слоновой кости (реплики игроков): как на картах; иначе — для сукна и тёмных плашек.
    static func styled(_ text: String, onLight: Bool, fourColor: Bool) -> AttributedString {
        var result = AttributedString()
        var plain = ""
        func flush() {
            guard !plain.isEmpty else { return }
            result.append(AttributedString(plain))
            plain = ""
        }
        for character in text {
            // «♦» и «♦︎» (с селектором варианта) — один символ.
            if let scalar = character.unicodeScalars.first,
               let suit = Suit.allCases.first(where: { $0.symbol.unicodeScalars.first == scalar }) {
                flush()
                var glyph = AttributedString(suit.glyph)
                let color: Color = onLight
                    ? Theme.suitColor(suit, fourColor: fourColor)
                    : Theme.tableSuitColor(suit, fourColor: fourColor)
                glyph.foregroundColor = color
                result.append(glyph)
            } else {
                plain.append(character)
            }
        }
        flush()
        return result
    }

    /// «Т♥», «10♠» — короткая запись карты.
    static func short(_ card: Card) -> String {
        card.rank.symbol + card.suit.glyph
    }
}
