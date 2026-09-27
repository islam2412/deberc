import Foundation
import DebercKit

// Геометрия карт без SwiftUI: контуры мастей, раскладка пипсов, рамка картинок.
// Все размеры — доли ширины карты w (высота h = 1.45w). Макет той же геометрии,
// по которому подбирались числа: scratchpad/cards-mock (HTML/SVG).

/// Команда контура в координатах карты (ось y направлена вниз).
enum OutlineCommand: Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(to: CGPoint, control: CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    case close

    func mapped(_ transform: (CGPoint) -> CGPoint) -> OutlineCommand {
        switch self {
        case .move(let p): return .move(transform(p))
        case .line(let p): return .line(transform(p))
        case .quad(let p, let c): return .quad(to: transform(p), control: transform(c))
        case .curve(let p, let c1, let c2):
            return .curve(to: transform(p), control1: transform(c1), control2: transform(c2))
        case .close: return .close
        }
    }
}

/// Простые контуры: окружность, звезда, многоугольник со скруглёнными углами.
enum Outline {
    /// Окружность из четырёх кубических дуг, обход по часовой стрелке.
    static func circle(center c: CGPoint, radius r: CGFloat) -> [OutlineCommand] {
        let k = 0.5523 * r
        return [
            .move(CGPoint(x: c.x + r, y: c.y)),
            .curve(to: CGPoint(x: c.x, y: c.y + r),
                   control1: CGPoint(x: c.x + r, y: c.y + k), control2: CGPoint(x: c.x + k, y: c.y + r)),
            .curve(to: CGPoint(x: c.x - r, y: c.y),
                   control1: CGPoint(x: c.x - k, y: c.y + r), control2: CGPoint(x: c.x - r, y: c.y + k)),
            .curve(to: CGPoint(x: c.x, y: c.y - r),
                   control1: CGPoint(x: c.x - r, y: c.y - k), control2: CGPoint(x: c.x - k, y: c.y - r)),
            .curve(to: CGPoint(x: c.x + r, y: c.y),
                   control1: CGPoint(x: c.x + k, y: c.y - r), control2: CGPoint(x: c.x + r, y: c.y - k)),
            .close,
        ]
    }

    /// Пятиконечная звезда (маркер козыря).
    static func star(center c: CGPoint, radius r: CGFloat) -> [OutlineCommand] {
        var result: [OutlineCommand] = []
        for i in 0..<10 {
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
            let rr = i % 2 == 0 ? r : r * 0.45
            let p = CGPoint(x: c.x + CGFloat(cos(angle)) * rr, y: c.y + CGFloat(sin(angle)) * rr)
            result.append(i == 0 ? .move(p) : .line(p))
        }
        result.append(.close)
        return result
    }

    /// Многоугольник со скруглёнными углами (квадратичные кривые в вершинах).
    static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> [OutlineCommand] {
        let n = points.count
        guard n >= 3 else { return [] }
        var result: [OutlineCommand] = []
        for i in 0..<n {
            let prev = points[(i - 1 + n) % n], vertex = points[i], next = points[(i + 1) % n]
            let l1 = hypot(prev.x - vertex.x, prev.y - vertex.y)
            let l2 = hypot(next.x - vertex.x, next.y - vertex.y)
            guard l1 > 0, l2 > 0 else { continue }
            let rr = min(radius, l1 / 2, l2 / 2)
            let a = CGPoint(x: vertex.x + (prev.x - vertex.x) / l1 * rr, y: vertex.y + (prev.y - vertex.y) / l1 * rr)
            let b = CGPoint(x: vertex.x + (next.x - vertex.x) / l2 * rr, y: vertex.y + (next.y - vertex.y) / l2 * rr)
            result.append(result.isEmpty ? .move(a) : .line(a))
            result.append(.quad(to: b, control: vertex))
        }
        result.append(.close)
        return result
    }

    /// Сдвиг прямоугольного многоугольника (обход по часовой стрелке) внутрь на `distance`.
    static func inset(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        let n = points.count
        return points.indices.map { i in
            let prev = points[(i - 1 + n) % n], vertex = points[i], next = points[(i + 1) % n]
            let e1 = normalized(CGPoint(x: vertex.x - prev.x, y: vertex.y - prev.y))
            let e2 = normalized(CGPoint(x: next.x - vertex.x, y: next.y - vertex.y))
            // Внутренняя нормаль ребра при обходе по часовой стрелке (y вниз): (−dy, dx).
            let nx = -e1.y - e2.y
            let ny = e1.x + e2.x
            return CGPoint(x: vertex.x + nx * distance, y: vertex.y + ny * distance)
        }
    }

    private static func normalized(_ v: CGPoint) -> CGPoint {
        let length = hypot(v.x, v.y)
        guard length > 0 else { return .zero }
        return CGPoint(x: v.x / length, y: v.y / length)
    }
}

/// Контуры мастей в квадрате 100×100, обход по часовой стрелке.
/// Рисуются векторами, а не шрифтом: одинаково на всех устройствах и в любом размере.
enum SuitOutline {
    static func unit(_ suit: Suit) -> [OutlineCommand] {
        switch suit {
        case .hearts: return hearts
        case .diamonds: return diamonds
        case .spades: return spades
        case .clubs: return clubs
        }
    }

    /// Контур масти в квадрате `size`×`size` с центром `center`; `inverted` — поворот на 180°.
    static func commands(_ suit: Suit, center: CGPoint, size: CGFloat, inverted: Bool = false) -> [OutlineCommand] {
        let scale = size / 100
        let sign: CGFloat = inverted ? -1 : 1
        return unit(suit).map { command in
            command.mapped { p in
                CGPoint(x: center.x + (p.x - 50) * scale * sign, y: center.y + (p.y - 50) * scale * sign)
            }
        }
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func c(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                          _ x: CGFloat, _ y: CGFloat) -> OutlineCommand {
        .curve(to: p(x, y), control1: p(x1, y1), control2: p(x2, y2))
    }

    private static let hearts: [OutlineCommand] = [
        .move(p(50, 97)),
        c(44, 87, 31, 76, 17, 63),
        c(5, 52, 0, 43, 0, 30),
        c(0, 13, 12, 3, 27, 3),
        c(38, 3, 46, 10, 50, 20),
        c(54, 10, 62, 3, 73, 3),
        c(88, 3, 100, 13, 100, 30),
        c(100, 43, 95, 52, 83, 63),
        c(69, 76, 56, 87, 50, 97),
        .close,
    ]

    private static let diamonds: [OutlineCommand] = [
        .move(p(50, 0)),
        c(59, 17, 71, 34, 86, 50),
        c(71, 66, 59, 83, 50, 100),
        c(41, 83, 29, 66, 14, 50),
        c(29, 34, 41, 17, 50, 0),
        .close,
    ]

    private static let spades: [OutlineCommand] = [
        .move(p(50, 0)),
        c(56, 11, 69, 23, 83, 35),
        c(95, 45, 100, 54, 100, 63),
        c(100, 78, 90, 87, 77, 87),
        c(67, 87, 59, 82, 54, 75),
        c(55, 85, 59, 93, 68, 100),
        .line(p(32, 100)),
        c(41, 93, 45, 85, 46, 75),
        c(41, 82, 33, 87, 23, 87),
        c(10, 87, 0, 78, 0, 63),
        c(0, 54, 5, 45, 17, 35),
        c(31, 23, 44, 11, 50, 0),
        .close,
    ]

    // Три листа, клин между ними и ножка; все части обходятся по часовой стрелке,
    // поэтому заливка по правилу ненулевого числа оборотов даёт объединение без дыр.
    private static let clubs: [OutlineCommand] = {
        var result = Outline.circle(center: p(50, 25), radius: 22)
        result += Outline.circle(center: p(25, 57), radius: 22)
        result += Outline.circle(center: p(75, 57), radius: 22)
        let wedge: [OutlineCommand] = [.move(p(50, 33)), .line(p(68, 62)), .line(p(32, 62)), .close]
        let stem: [OutlineCommand] = [
            .move(p(54, 60)), c(54, 80, 58, 92, 68, 100), .line(p(32, 100)), c(42, 92, 46, 80, 46, 60), .close,
        ]
        result += wedge
        result += stem
        return result
    }()
}

/// Размеры и раскладка одной карты заданной ширины.
struct CardMetrics: Equatable {
    /// Отношение высоты к ширине.
    static let aspectRatio: CGFloat = 1.45
    /// Уже этой ширины карта рисуется упрощённо: индекс и крупная масть.
    static let compactWidth: CGFloat = 46

    struct Pip: Equatable {
        let center: CGPoint
        let inverted: Bool
    }

    let width: CGFloat
    let height: CGFloat
    let isCompact: Bool
    let isLarge: Bool
    let showsBottomIndex: Bool
    let isTrump: Bool

    let cornerRadius: CGFloat
    /// Тонкая линия: кромка, контуры орнамента.
    let hairline: CGFloat

    // Угловой индекс.
    let rankSize: CGFloat
    let indexX: CGFloat
    let indexMaxWidth: CGFloat
    let rankCenterY: CGFloat
    let suitSize: CGFloat
    let suitCenterY: CGFloat
    let trumpSize: CGFloat
    let trumpCenterY: CGFloat
    /// Нижняя и правая границы блока индекса (с маркером козыря).
    let blockBottom: CGFloat
    let blockRight: CGFloat

    // Пипсы 7–10.
    let pipSize: CGFloat
    let pipColumn: CGFloat
    let pipTop: CGFloat
    let pipBottom: CGFloat

    init(width: CGFloat, largeIndex: Bool = false, showsBottomIndex: Bool = true, isTrump: Bool = false) {
        let w = max(width, 1)
        let h = w * CardMetrics.aspectRatio
        let compact = w < CardMetrics.compactWidth
        let large = largeIndex && !compact
        self.width = w
        self.height = h
        self.isCompact = compact
        self.isLarge = large
        self.showsBottomIndex = showsBottomIndex && !compact
        self.isTrump = isTrump
        cornerRadius = w * 0.075
        hairline = max(0.5, w * 0.008)

        let rankTop: CGFloat
        if compact {
            rankSize = w * 0.40; indexX = w * 0.215; indexMaxWidth = w * 0.34; suitSize = w * 0.27; rankTop = w * 0.07
            trumpSize = w * 0.20
        } else if large {
            rankSize = w * 0.38; indexX = w * 0.195; indexMaxWidth = w * 0.30; suitSize = w * 0.25; rankTop = w * 0.06
            trumpSize = w * 0.19
        } else {
            rankSize = w * 0.31; indexX = w * 0.14; indexMaxWidth = w * 0.21; suitSize = w * 0.185; rankTop = w * 0.065
            trumpSize = w * 0.15
        }
        // Высота прописной ≈ 0.70 кегля; зазор до масти оставляет место «ножкам» буквы «Д».
        rankCenterY = rankTop + 0.35 * rankSize
        suitCenterY = rankTop + 0.70 * rankSize + w * 0.012 + rankSize * 0.19 + suitSize / 2
        let indexBottom = suitCenterY + suitSize / 2
        trumpCenterY = indexBottom + w * 0.035 + trumpSize / 2
        blockBottom = isTrump ? trumpCenterY + trumpSize / 2 : indexBottom
        blockRight = indexX + max(indexMaxWidth, suitSize) / 2

        pipSize = w * 0.16
        pipColumn = w * 0.15
        pipTop = h * 0.16
        pipBottom = h * 0.84
    }

    /// Кегль ранга: «10» набирается чуть мельче и дополнительно сжимается по ширине.
    func rankFontSize(for rank: Rank) -> CGFloat {
        rank == .ten ? rankSize * 0.86 : rankSize
    }

    // MARK: Пипсы

    /// Раскладка пипсов как на французской колоде: (колонка −1/0/1, доля пути от верхнего ряда к нижнему).
    static func pipLayout(for rank: Rank) -> [(column: Int, t: CGFloat)] {
        switch rank {
        case .seven:
            return [(-1, 0), (-1, 0.5), (-1, 1), (1, 0), (1, 0.5), (1, 1), (0, 0.25)]
        case .eight:
            return [(-1, 0), (-1, 0.5), (-1, 1), (1, 0), (1, 0.5), (1, 1), (0, 0.25), (0, 0.75)]
        case .nine:
            return [(-1, 0), (-1, 1.0 / 3), (-1, 2.0 / 3), (-1, 1),
                    (1, 0), (1, 1.0 / 3), (1, 2.0 / 3), (1, 1), (0, 0.5)]
        case .ten:
            return [(-1, 0), (-1, 1.0 / 3), (-1, 2.0 / 3), (-1, 1),
                    (1, 0), (1, 1.0 / 3), (1, 2.0 / 3), (1, 1), (0, 1.0 / 6), (0, 5.0 / 6)]
        case .jack, .queen, .king, .ace:
            return []
        }
    }

    /// Центры пипсов; пипсы нижней половины повёрнуты на 180°.
    func pips(for rank: Rank) -> [Pip] {
        CardMetrics.pipLayout(for: rank).map { item in
            let y = pipTop + item.t * (pipBottom - pipTop)
            return Pip(center: CGPoint(x: width / 2 + CGFloat(item.column) * pipColumn, y: y),
                       inverted: y > height / 2 + 0.5)
        }
    }

    // MARK: Картинки (В, Д, К)

    /// Отступ рамки картинки от края карты.
    var courtMargin: CGFloat { width * 0.065 }

    /// Рамка картинки: прямоугольник с вырезами под угловые индексы (обход по часовой стрелке).
    func courtFrame() -> [CGPoint] {
        let w = width, h = height, fm = courtMargin
        let nx = blockRight + w * 0.04
        let ny = blockBottom + w * 0.035
        var points = [CGPoint(x: nx, y: fm), CGPoint(x: w - fm, y: fm)]
        if showsBottomIndex {
            points += [CGPoint(x: w - fm, y: h - ny), CGPoint(x: w - nx, y: h - ny), CGPoint(x: w - nx, y: h - fm)]
        } else {
            points.append(CGPoint(x: w - fm, y: h - fm))
        }
        points += [CGPoint(x: fm, y: h - fm), CGPoint(x: fm, y: ny), CGPoint(x: nx, y: ny)]
        return points
    }

    /// Полосы «перевязи» у середины картинки: смещения от середины вверх (нижняя половина — зеркально).
    enum BandRole: Equatable { case ink, gold, soft }

    var courtBands: [(from: CGFloat, to: CGFloat, role: BandRole)] {
        let w = width
        let b1 = w * 0.04, b2 = b1 + w * 0.016, b3 = b2 + w * 0.05, b4 = b3 + w * 0.014
        return [(0, b1, .ink), (b1, b2, .gold), (b2, b3, .soft), (b3, b4, .gold)]
    }

    /// Раскладка верхней половины картинки: эмблема и крупная буква справа от выреза под индекс.
    struct CourtHalf: Equatable {
        let emblemCenter: CGPoint
        let emblemSize: CGSize
        let letterCenter: CGPoint
        let letterCapHeight: CGFloat
        var letterFontSize: CGFloat { letterCapHeight / 0.7 }
    }

    func courtHalf(for rank: Rank) -> CourtHalf {
        let w = width
        let left = blockRight + w * 0.04
        let right = w - courtMargin
        let centerX = (left + right) / 2
        let emblemSize = CGSize(width: w * 0.24, height: w * 0.10)
        let emblemCenterY = courtMargin + w * 0.05 + emblemSize.height / 2
        let sashTop = height / 2 - (courtBands.last?.to ?? 0)
        let letterTop = emblemCenterY + emblemSize.height / 2 + w * 0.035
        let available = sashTop - letterTop - w * 0.035
        // У «Д» ножки опускаются ниже строки примерно на 0.2 кегля (≈ 0.29 высоты прописной).
        let fitting = rank == .queen ? available / 1.29 : available
        let capHeight = max(w * 0.1, min(0.7 * w * 0.42, fitting))
        return CourtHalf(
            emblemCenter: CGPoint(x: centerX, y: emblemCenterY),
            emblemSize: emblemSize,
            letterCenter: CGPoint(x: centerX, y: letterTop + capHeight / 2),
            letterCapHeight: capHeight)
    }

    /// Радиус медальона с мастью в центре картинки.
    var medallionRadius: CGFloat { width * 0.105 }

    // MARK: Туз и упрощённый вид

    /// Размер центральной масти туза.
    var aceSuitSize: CGFloat { isLarge ? width * 0.36 : width * 0.37 }
    /// Кольца орнамента туза (в крупном режиме орнамента нет — он мешал бы индексу).
    var aceRingRadii: (outer: CGFloat, inner: CGFloat)? {
        isLarge ? nil : (width * 0.29, width * 0.255)
    }

    /// Центр крупной масти в упрощённом виде (справа снизу, не задевая индекс).
    var compactCenter: CGPoint { CGPoint(x: width * 0.60, y: height * 0.68) }
    /// Плашка картинки в упрощённом виде.
    var compactCourtTile: CGRect {
        let size = CGSize(width: width * 0.56, height: height * 0.40)
        return CGRect(x: compactCenter.x - size.width / 2, y: compactCenter.y - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// Эмблемы картинок — стилизованные уборы вместо портретов:
/// корона короля, диадема дамы, берет с пером валета.
enum CourtEmblem {
    enum Role: Equatable {
        case gold    // золотая заливка с тёмно-золотым контуром
        case line    // только тёмно-золотая линия
        case jewel   // заливка цветом масти
    }

    struct Part: Equatable {
        let commands: [OutlineCommand]
        let role: Role
    }

    static func parts(for rank: Rank, center: CGPoint, size: CGSize) -> [Part] {
        let ew = size.width, eh = size.height, cx = center.x
        let x0 = center.x - ew / 2, x1 = center.x + ew / 2
        let yt = center.y - eh / 2, yb = center.y + eh / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

        switch rank {
        case .king:
            let band = yb - eh * 0.28, mid = yt + eh * 0.42, side = yt + eh * 0.2
            let crown: [OutlineCommand] = [
                .move(pt(x0, yb)), .line(pt(x0, side)), .line(pt(x0 + ew * 0.27, mid)), .line(pt(cx, yt)),
                .line(pt(x1 - ew * 0.27, mid)), .line(pt(x1, side)), .line(pt(x1, yb)), .close,
            ]
            var parts = [Part(commands: crown, role: .gold),
                         Part(commands: [.move(pt(x0, band)), .line(pt(x1, band))], role: .line)]
            for ball in [pt(x0, side), pt(cx, yt), pt(x1, side)] {
                parts.append(Part(commands: Outline.circle(center: ball, radius: eh * 0.1), role: .gold))
            }
            parts.append(Part(commands: Outline.circle(center: pt(cx, (band + yb) / 2), radius: eh * 0.075),
                              role: .jewel))
            return parts

        case .queen:
            let y1 = yb - eh * 0.3
            let diadem: [OutlineCommand] = [
                .move(pt(x0, yb)), .line(pt(x0 + ew * 0.04, y1)),
                .quad(to: pt(x1 - ew * 0.04, y1), control: pt(cx, yt - eh * 0.35)),
                .line(pt(x1, yb)), .close,
            ]
            let arc: [OutlineCommand] = [
                .move(pt(x0 + ew * 0.03, y1 + eh * 0.12)),
                .quad(to: pt(x1 - ew * 0.03, y1 + eh * 0.12), control: pt(cx, yt + eh * 0.05)),
            ]
            var parts = [Part(commands: diadem, role: .gold), Part(commands: arc, role: .line),
                         Part(commands: Outline.circle(center: pt(cx, yt + eh * 0.12), radius: eh * 0.14), role: .jewel)]
            for t in [0.22, 0.78] as [CGFloat] {
                parts.append(Part(commands: Outline.circle(center: pt(x0 + ew * t, yt + eh * 0.46), radius: eh * 0.075),
                                  role: .jewel))
            }
            return parts

        case .jack:
            let band = yb - eh * 0.26
            let cap: [OutlineCommand] = [
                .move(pt(x0 + ew * 0.06, yb)), .line(pt(x0 + ew * 0.06, band)),
                .curve(to: pt(x1 - ew * 0.02, band),
                       control1: pt(x0, yt + eh * 0.3), control2: pt(x1 - ew * 0.1, yt + eh * 0.12)),
                .line(pt(x1 - ew * 0.02, yb)), .close,
            ]
            let feather: [OutlineCommand] = [
                .move(pt(cx - ew * 0.05, yt + eh * 0.28)),
                .curve(to: pt(x0 - ew * 0.02, yt - eh * 0.02),
                       control1: pt(cx - ew * 0.25, yt - eh * 0.1), control2: pt(cx - ew * 0.52, yt - eh * 0.05)),
                .curve(to: pt(cx - ew * 0.05, yt + eh * 0.28),
                       control1: pt(cx - ew * 0.4, yt + eh * 0.2), control2: pt(cx - ew * 0.2, yt + eh * 0.32)),
                .close,
            ]
            return [Part(commands: cap, role: .gold),
                    Part(commands: [.move(pt(x0 + ew * 0.06, band)), .line(pt(x1 - ew * 0.02, band))], role: .line),
                    Part(commands: feather, role: .jewel)]

        case .seven, .eight, .nine, .ten, .ace:
            return []
        }
    }
}
