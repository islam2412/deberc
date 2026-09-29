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
    /// Колода и открытая карта в верхней полосе (во время розыгрыша).
    case deck
    /// Нижняя карта колоды.
    case bottom
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
    let miniCardWidth: CGFloat
    let avatarSize: CGFloat

    init(size: CGSize, playerCount: Int, large: Bool) {
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
        miniCardWidth = roomy ? (large ? 46 : 40) : min(large ? 34 : 30, (width * 0.08).rounded())

        // Карта руки: 9 карт внахлёст по ширине и место под взятку по высоте.
        let byWidth = (tableWidth - 2 * gutter) / 4.6
        let plate: CGFloat = roomy ? 84 : 66
        let opponents: CGFloat
        if sideSeats {
            opponents = 0
        } else if playerCount == 3 {
            opponents = plate + spacing + (roomy ? 64 : 44)
        } else {
            opponents = plate
        }
        let chrome = topBarHeight + opponents + (roomy ? 50 : 40) + (roomy ? 70 : 58) + 5 * spacing + (large ? 30 : 0)
        let byHeight = (height - chrome) / 4.6
        let limit: CGFloat = roomy ? (large ? 180 : 165) : (large ? 120 : 110)
        let hand = max(44, min(limit, byWidth, byHeight)).rounded()
        handCardWidth = hand
        fanCardWidth = min(roomy ? 54 : 34, max(22, (hand * 0.34).rounded()))
        pileCardWidth = min(roomy ? 44 : 30, max(20, (hand * 0.28).rounded()))
    }

    var handLift: CGFloat { (handCardWidth * 0.22).rounded() }
    /// Ширина, в которой рисуются карты руки и взятки (одна для всех мест, чтобы карта летела без скачков).
    var renderCardWidth: CGFloat { min(180, (handCardWidth * 1.1).rounded()) }
    /// Ширина, в которой рисуется открытая карта в центре во время торговли.
    var heroRenderWidth: CGFloat { min(180, (handCardWidth * 1.2).rounded()) }
    var fanSlotSize: CGSize {
        CGSize(width: (fanCardWidth * 3.6).rounded(), height: (fanCardWidth * CardView.aspectRatio).rounded() + 4)
    }
    var pileSlotSize: CGSize {
        CGSize(width: (pileCardWidth * CardView.aspectRatio).rounded() + 12, height: pileCardWidth + 12)
    }
    var deckSlotSize: CGSize {
        CGSize(width: (miniCardWidth * 1.5).rounded(), height: (miniCardWidth * CardView.aspectRatio).rounded())
    }
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

enum HandFan {
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

    /// Ширина карты взятки: крупно, но так, чтобы вся взятка помещалась в центр.
    static func cardWidth(center: CGRect, playerCount: Int, handCardWidth: CGFloat) -> CGFloat {
        let h = max(40, center.height - topInset - 8)
        let byHeight = h / (CardView.aspectRatio * 1.75)
        let byWidth = (center.width - 16) / (playerCount == 3 ? 2.5 : 1.7)
        return max(30, min(handCardWidth * 1.1, 180, byHeight, byWidth))
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

// MARK: - Открытая карта во время торговли

enum HeroGeometry {
    /// Место под подпись под открытой картой.
    static let captionSpace: CGFloat = 40

    static func cardWidth(center: CGRect, handCardWidth: CGFloat) -> CGFloat {
        let byHeight = (center.height - TrickGeometry.topInset - captionSpace) / (CardView.aspectRatio * 1.04)
        let byWidth = (center.width - 32) / 1.8
        return max(34, min(handCardWidth * 1.2, 180, byHeight, byWidth))
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
