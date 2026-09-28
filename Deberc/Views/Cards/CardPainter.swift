import SwiftUI
import DebercKit

/// Лицо карты: всё рисуется одним `Canvas` — индексы, пипсы, туз, картинки.
/// Один слой на карту вместо десятка вложенных вью: на столе бывает 25–30 карт.
/// `Equatable` — чтобы SwiftUI не перерисовывал холст, пока карта и размер не меняются.
struct CardFaceCanvas: View, Equatable {
    let card: Card
    let metrics: CardMetrics
    let fourColor: Bool

    var body: some View {
        Canvas { context, _ in
            CardFacePainter(card: card, m: metrics, fourColor: fourColor).draw(context)
        }
    }
}

/// Рубашка карты одним `Canvas`: золотой орнамент (без него — ромбическая сетка с рамкой), медальон с «Д».
struct CardBackCanvas: View, Equatable {
    let metrics: CardMetrics
    let style: CardBackStyle

    var body: some View {
        Canvas { context, _ in
            CardBackPainter(m: metrics, style: style).draw(context)
        }
    }
}

// MARK: - Лицо

struct CardFacePainter {
    let card: Card
    let m: CardMetrics
    let fourColor: Bool

    private var ink: Color { Theme.suitColor(card.suit, fourColor: fourColor) }
    private var tint: Color { Theme.suitTint(card.suit, fourColor: fourColor) }
    private var soft: Color { Theme.suitSoft(card.suit, fourColor: fourColor) }
    private var isCourt: Bool { card.rank == .jack || card.rank == .queen || card.rank == .king }

    func draw(_ context: GraphicsContext) {
        if m.isCompact {
            drawCompactCenter(context)
        } else if card.rank == .ace {
            drawAce(context)
        } else if isCourt {
            drawCourt(context)
        } else if m.isLarge {
            // Крупный режим: вместо раскладки — одна средняя масть, чтобы не спорить с индексом.
            fill(context, SuitOutline.commands(card.suit, center: center, size: m.width * 0.30), ink)
        } else {
            drawPips(context)
        }

        drawIndex(context)
        if m.showsBottomIndex {
            drawIndex(rotated(context))
        }
    }

    private var center: CGPoint { CGPoint(x: m.width / 2, y: m.height / 2) }

    /// Контекст, повёрнутый на 180° вокруг центра карты.
    private func rotated(_ context: GraphicsContext) -> GraphicsContext {
        var c = context
        c.translateBy(x: m.width, y: m.height)
        c.rotate(by: .degrees(180))
        return c
    }

    private func fill(_ context: GraphicsContext, _ outline: [OutlineCommand], _ color: Color) {
        context.fill(Path(outline: outline), with: .color(color))
    }

    private func stroke(_ context: GraphicsContext, _ outline: [OutlineCommand], _ color: Color, _ width: CGFloat) {
        context.stroke(Path(outline: outline), with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    // MARK: Индекс

    /// Угловой индекс: ранг (с засечками), под ним масть, для козыря — золотая звезда.
    private func drawIndex(_ context: GraphicsContext) {
        let fontSize = m.rankFontSize(for: card.rank)
        let isTwoDigits = card.rank == .ten
        let text = Text(card.rank.symbol)
            .font(.system(size: fontSize, weight: .bold, design: .serif))
            .kerning(isTwoDigits ? -fontSize * 0.04 : 0)
        drawText(context, text, capCenter: CGPoint(x: m.indexX, y: m.rankCenterY),
                 capHeight: fontSize * 0.7, maxWidth: m.indexMaxWidth, color: ink)

        fill(context, SuitOutline.commands(card.suit, center: CGPoint(x: m.indexX, y: m.suitCenterY),
                                           size: m.suitSize), ink)

        if m.isTrump {
            let badgeCenter = CGPoint(x: m.indexX, y: m.trumpCenterY)
            let r = m.trumpSize / 2
            let disc = Path(outline: Outline.circle(center: badgeCenter, radius: r))
            context.fill(disc, with: .color(Theme.goldFill))
            context.stroke(disc, with: .color(Theme.goldDeep), lineWidth: m.hairline)
            fill(context, Outline.star(center: CGPoint(x: badgeCenter.x, y: badgeCenter.y + r * 0.06),
                                       radius: r * 0.72), Theme.ivory)
        }
    }

    /// Рисует текст так, чтобы центр прописных пришёлся в `capCenter`;
    /// слишком широкий текст («10») сжимается по горизонтали до `maxWidth`.
    private func drawText(_ context: GraphicsContext, _ text: Text, capCenter: CGPoint,
                          capHeight: CGFloat, maxWidth: CGFloat, color: Color) {
        var resolved = context.resolve(text)
        resolved.shading = .color(color)
        let bounds = CGSize(width: 10_000, height: 10_000)
        let size = resolved.measure(in: bounds)
        let baseline = resolved.firstBaseline(in: bounds)
        let top = capCenter.y + capHeight / 2 - baseline
        var c = context
        c.translateBy(x: capCenter.x, y: 0)
        if size.width > maxWidth, size.width > 0 {
            c.scaleBy(x: maxWidth / size.width, y: 1)
        }
        c.draw(resolved, at: CGPoint(x: 0, y: top), anchor: .top)
    }

    // MARK: Числовые карты

    private func drawPips(_ context: GraphicsContext) {
        var outline: [OutlineCommand] = []
        for pip in m.pips(for: card.rank) {
            outline += SuitOutline.commands(card.suit, center: pip.center, size: m.pipSize, inverted: pip.inverted)
        }
        fill(context, outline, ink)
    }

    // MARK: Туз

    private func drawAce(_ context: GraphicsContext) {
        if let rings = m.aceRingRadii {
            let w = m.width
            context.fill(Path(outline: Outline.circle(center: center, radius: rings.inner)), with: .color(tint))
            context.stroke(Path(outline: Outline.circle(center: center, radius: rings.outer)),
                           with: .color(Theme.goldDeep), lineWidth: max(0.6, w * 0.012))
            context.stroke(Path(outline: Outline.circle(center: center, radius: rings.inner)),
                           with: .color(Theme.goldDeep), lineWidth: max(0.5, w * 0.006))
            // Орнамент между кольцами: ромбики по сторонам света и бисер между ними.
            let radius = (rings.outer + rings.inner) / 2
            var ornament: [OutlineCommand] = []
            for i in 0..<24 {
                let angle = Double(i) * Double.pi / 12
                let p = CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                y: center.y + CGFloat(sin(angle)) * radius)
                if i % 6 == 0 {
                    ornament += SuitOutline.commands(.diamonds, center: p, size: w * 0.045)
                } else if w >= 70 {
                    ornament += Outline.circle(center: p, radius: w * 0.0065)
                }
            }
            fill(context, ornament, Theme.goldDeep)
        }
        fill(context, SuitOutline.commands(card.suit, center: center, size: m.aceSuitSize), ink)
    }

    // MARK: Упрощённый вид (узкие карты)

    private func drawCompactCenter(_ context: GraphicsContext) {
        let w = m.width
        if isCourt {
            let tile = Path(roundedRect: m.compactCourtTile, cornerRadius: w * 0.05, style: .continuous)
            context.fill(tile, with: .color(tint))
            context.stroke(tile, with: .color(Theme.goldDeep), lineWidth: max(0.75, w * 0.025))
            fill(context, SuitOutline.commands(card.suit, center: m.compactCenter, size: w * 0.34), ink)
        } else {
            let size = card.rank == .ace ? w * 0.5 : w * 0.44
            fill(context, SuitOutline.commands(card.suit, center: m.compactCenter, size: size), ink)
        }
    }

    // MARK: Картинки

    /// Картинка: рамка с вырезами под индексы, «перевязь» из полос цвета масти и золота,
    /// в каждой половине — портрет из ресурсов, а без него — убор (корона, диадема, берет) и крупная буква;
    /// в центре — медальон с мастью.
    private func drawCourt(_ context: GraphicsContext) {
        let w = m.width
        let frame = m.courtFrame()
        let framePath = Path(outline: Outline.roundedPolygon(frame, radius: w * 0.03))
        context.fill(framePath, with: .color(tint))

        var clipped = context
        clipped.clip(to: framePath)
        let portrait = CardArt.courtImageName(card)
        drawCourtHalf(clipped, portrait: portrait)
        drawCourtHalf(rotated(clipped), portrait: portrait)

        // Медальон.
        let medallion = Path(outline: Outline.circle(center: center, radius: m.medallionRadius))
        context.fill(medallion, with: .color(Theme.ivory))
        context.stroke(medallion, with: .color(Theme.goldDeep), lineWidth: max(0.75, w * 0.016))
        fill(context, SuitOutline.commands(card.suit, center: center, size: m.medallionRadius * 1.15), ink)

        // Рамка: золото снаружи, тонкая линия цвета масти внутри.
        context.stroke(framePath, with: .color(Theme.goldDeep), lineWidth: max(0.75, w * 0.016))
        let inner = Path(outline: Outline.roundedPolygon(Outline.inset(frame, by: w * 0.022), radius: w * 0.018))
        context.stroke(inner, with: .color(ink.opacity(0.55)), lineWidth: max(0.4, w * 0.006))
    }

    /// Половина картинки: портрет (если есть) или убор с буквой; снизу — «перевязь».
    private func drawCourtHalf(_ context: GraphicsContext, portrait: String?) {
        let w = m.width, mid = m.height / 2
        if let portrait {
            context.draw(Image(portrait), in: m.courtPortraitRect)
        }
        let left = m.courtMargin - 1, right = w - m.courtMargin + 1
        for band in m.courtBands {
            let rect = CGRect(x: left, y: mid - band.to, width: right - left, height: band.to - band.from)
            let color: Color
            switch band.role {
            case .ink: color = ink
            case .gold: color = Theme.goldFill
            case .soft: color = soft
            }
            context.fill(Path(rect), with: .color(color))
        }
        if portrait != nil { return }

        let half = m.courtHalf(for: card.rank)
        let line = max(0.5, w * 0.008)
        for part in CourtEmblem.parts(for: card.rank, center: half.emblemCenter, size: half.emblemSize) {
            switch part.role {
            case .gold:
                fill(context, part.commands, Theme.goldFill)
                stroke(context, part.commands, Theme.goldDeep, line)
            case .line:
                stroke(context, part.commands, Theme.goldDeep, line)
            case .jewel:
                fill(context, part.commands, ink)
            }
        }

        let text = Text(card.rank.symbol)
            .font(.system(size: half.letterFontSize, weight: .bold, design: .serif))
        drawText(context, text, capCenter: half.letterCenter, capHeight: half.letterCapHeight,
                 maxWidth: w * 0.5, color: ink)
    }
}

// MARK: - Рубашка

struct CardBackPainter {
    let m: CardMetrics
    let style: CardBackStyle

    func draw(_ context: GraphicsContext) {
        let w = m.width, h = m.height
        let colors = style.colors
        let margin = w * 0.055
        let field = CGRect(x: margin, y: margin, width: w - 2 * margin, height: h - 2 * margin)
        let fieldRadius = m.cornerRadius * 0.6
        let fieldPath = Path(roundedRect: field, cornerRadius: fieldRadius, style: .continuous)
        context.fill(fieldPath, with: .linearGradient(Gradient(colors: [colors.top, colors.bottom]),
                                                      startPoint: .zero, endPoint: CGPoint(x: w, y: h)))

        let gold = Theme.goldFill
        let ornament = w >= 16 ? CardArt.backOrnamentName : nil
        if let ornament {
            // Золотой орнамент (бараньи рога, ромбы, Эльбрус) с собственной рамкой поверх цвета рубашки.
            var art = context
            art.clip(to: fieldPath)
            art.draw(Image(ornament), in: field)
        } else {
            // Ромбическая сетка.
            var lattice = context
            lattice.clip(to: fieldPath)
            let step = max(w / 8, 4.5)
            var lines = Path()
            var k = -h
            while k < w + h {
                lines.move(to: CGPoint(x: k, y: 0))
                lines.addLine(to: CGPoint(x: k + h, y: h))
                lines.move(to: CGPoint(x: k, y: h))
                lines.addLine(to: CGPoint(x: k + h, y: 0))
                k += step
            }
            lattice.stroke(lines, with: .color(Color(red: 1, green: 0.925, blue: 0.78).opacity(0.16)),
                           lineWidth: m.hairline)

            // Золотая рамка поля.
            let inset = w * 0.045
            let frame = Path(roundedRect: field.insetBy(dx: inset, dy: inset), cornerRadius: fieldRadius * 0.6,
                             style: .continuous)
            context.stroke(frame, with: .color(gold.opacity(0.85)), lineWidth: max(0.6, w * 0.014))
        }

        // Медальон с монограммой «Д». С орнаментом — внутри его овала с бисерным кольцом
        // (овал занимает 0,28 × 0,47 ширины карты), без орнамента — крупный, с двойной золотой рамкой.
        let medallionSize = ornament != nil ? CGSize(width: w * 0.26, height: w * 0.44)
                                            : CGSize(width: w * 0.46, height: w * 0.58)
        let medallionRect = CGRect(x: (w - medallionSize.width) / 2, y: (h - medallionSize.height) / 2,
                                   width: medallionSize.width, height: medallionSize.height)
        let medallion = Path(ellipseIn: medallionRect)
        context.fill(medallion, with: .color(colors.bottom))
        if ornament == nil {
            context.stroke(medallion, with: .color(gold), lineWidth: max(0.6, w * 0.014))
        }
        let innerRect = medallionRect.insetBy(dx: w * 0.03, dy: w * 0.03)
        context.stroke(Path(ellipseIn: innerRect), with: .color(gold.opacity(0.6)), lineWidth: max(0.4, w * 0.006))

        let center = CGPoint(x: w / 2, y: h / 2)
        if w >= 36 {
            let fontSize = ornament != nil ? w * 0.22 : w * 0.30
            var monogram = context.resolve(Text("Д").font(.system(size: fontSize, weight: .bold, design: .serif)))
            monogram.shading = .color(gold)
            let bounds = CGSize(width: 10_000, height: 10_000)
            let baseline = monogram.firstBaseline(in: bounds)
            let capHeight = fontSize * 0.7
            context.draw(monogram, at: CGPoint(x: center.x, y: center.y + capHeight / 2 - baseline), anchor: .top)
        } else {
            context.fill(Path(outline: Outline.circle(center: center, radius: w * 0.07)), with: .color(gold))
        }
    }
}
