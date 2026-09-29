import SwiftUI
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
    let sidePanelWidth: CGFloat
    let sideSeatWidth: CGFloat
    let topBarHeight: CGFloat
    let handCardWidth: CGFloat
    let fanCardWidth: CGFloat
    let pileCardWidth: CGFloat
    /// Карты колоды на столе (лёжа, у левого края).
    let deckCardWidth: CGFloat
    let avatarSize: CGFloat
    /// Какая доля высоты карт руки видна: на телефоне рука уходит за нижний край экрана —
    /// видны уголки с индексами и верх картинки, зато сами карты крупнее.
    let handVisible: CGFloat

    /// `bottomInset` — нижний отступ безопасной зоны: на телефоне рука ложится до самого края экрана.
    init(size: CGSize, playerCount: Int, large: Bool, bottomInset: CGFloat = 0) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let roomy = width >= 600 && height >= 640
        let wide = roomy && width >= 900 && width > height * 1.2
        self.roomy = roomy
        self.wide = wide
        self.sideSeats = wide && playerCount == 3
        self.large = large
        gutter = roomy ? 20 : 12
        spacing = roomy ? 10 : 6
        sidePanelWidth = wide ? min(340, (width * 0.27).rounded()) : 0
        let tableWidth = width - sidePanelWidth
        sideSeatWidth = sideSeats ? min(240, (tableWidth * 0.22).rounded()) : 0
        topBarHeight = roomy ? (large ? 72 : 62) : (large ? 60 : 50)
        avatarSize = roomy ? (large ? 64 : 56) : (large ? 48 : 42)
        deckCardWidth = roomy ? (large ? 66 : 60) : (large ? 58 : 52)
        handVisible = roomy ? 1 : 0.72

        let hand: CGFloat
        if roomy {
            // iPad: 9 карт внахлёст по ширине и место под взятку по высоте.
            let byWidth = (tableWidth - 2 * gutter) / 4.6
            let plate: CGFloat = 84
            let opponents: CGFloat
            if sideSeats {
                opponents = 0
            } else if playerCount == 3 {
                opponents = plate + spacing + 64
            } else {
                opponents = 64
            }
            let chrome = topBarHeight + opponents + 50 + 70 + 5 * spacing + (large ? 30 : 0)
            let byHeight = (height - chrome) / 4.6
            hand = max(44, min(large ? 180 : 165, byWidth, byHeight)).rounded()
        } else {
            // Телефон: карты крупные — 9 карт внахлёст так, что видны уголки с индексами
            // (у крупных индексов уголок шире), а над рукой — место под взятку того же размера.
            let byWidth = (tableWidth - 2 * gutter) / (large ? 3.56 : 3.3)
            let plate: CGFloat = large ? 66 : 58
            let fanRow: CGFloat = 46
            let top = playerCount == 3
                ? topBarHeight + spacing + plate + spacing + fanRow
                : max(topBarHeight, plate) + 4 + fanRow
            let chrome = top + 40 + (large ? 64 : 52) + 4 * spacing
            // Рука занимает видимую часть карты и подъём; взятке над ней — не меньше 2,2 ширины карты.
            let byHeight = (height + bottomInset - chrome - 44) / (0.72 * CardView.aspectRatio + 0.22 + 2.2)
            hand = max(44, min(large ? 132 : 120, byWidth, byHeight)).rounded()
        }
        handCardWidth = hand
        fanCardWidth = roomy ? min(54, max(22, (hand * 0.34).rounded())) : min(30, max(22, (hand * 0.28).rounded()))
        pileCardWidth = roomy ? min(44, max(20, (hand * 0.28).rounded())) : min(26, max(20, (hand * 0.24).rounded()))
    }

    var handLift: CGFloat { (handCardWidth * 0.22).rounded() }
    /// Видимая высота руки: карта (без ушедшей за край части) и подъём выбранной.
    var handHeight: CGFloat { (handCardWidth * CardView.aspectRatio * handVisible + handLift).rounded() }
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
    var actionMinHeight: CGFloat { roomy ? (large ? 72 : 62) : (large ? 64 : 52) }

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

    /// Центры карт веера по x (от левого края области). Между мастями — небольшой зазор,
    /// чтобы пики и трефы не сливались.
    static func centers(for cards: [Card], width: CGFloat, cardWidth w: CGFloat) -> [CGFloat] {
        let n = cards.count
        guard n > 0 else { return [] }
        guard n > 1 else { return [width / 2] }
        var breaks = 0
        for i in 1..<n where cards[i].suit != cards[i - 1].suit {
            breaks += 1
        }
        var gap = (w * 0.12).rounded()
        var step = min(w * 0.92, (width - w - CGFloat(breaks) * gap) / CGFloat(n - 1))
        if step < w * 0.34 {
            // Тесно — зазоры между мастями не помещаются.
            gap = 0
            step = min(w * 0.92, (width - w) / CGFloat(n - 1))
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

    /// Карта под пальцем: самая верхняя (правая) из тех, чья левая кромка левее точки.
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
    static func cardWidth(center: CGRect, playerCount: Int, metrics: TableMetrics, deck: CGRect?) -> CGFloat {
        let h = max(40, center.height - topInset - 8)
        let byHeight = h / (CardView.aspectRatio * 1.75)
        let byWidth = (center.width - 16) / (playerCount == 3 ? 2.5 : 1.7)
        // Левая карта взятки: втроём — на 0,62 ширины левее центра, вдвоём (соперника) — на 0,28.
        var byDeck = CGFloat.greatestFiniteMagnitude
        if let deck {
            let room = center.midX - (deck.maxX + 6)
            byDeck = room / (playerCount == 3 ? 1.12 : 0.78)
        }
        return max(30, min(metrics.handCardWidth * metrics.trickScale, 200, byHeight, byWidth, byDeck))
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
}

// MARK: - Открытая карта во время торговли

enum HeroGeometry {
    /// Место под подпись под открытой картой.
    static let captionSpace: CGFloat = 40

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

    /// Точка подписи под картой.
    static func captionPoint(_ center: CGRect, cardWidth w: CGFloat) -> CGPoint {
        let c = self.center(center)
        return CGPoint(x: c.x, y: c.y + w * CardView.aspectRatio / 2 + 22)
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
        switch suit {
        case .spades: return "пик"
        case .clubs: return "треф"
        case .diamonds: return "бубен"
        case .hearts: return "червей"
        }
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
