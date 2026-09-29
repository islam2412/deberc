import SwiftUI
import DebercKit

// Единый слой карт стола. Все карты — рука, веера соперников, взятка, стопки взяток,
// колода, открытая и нижняя карта — рисуются в одном ZStack со стабильными id.
// Поэтому SwiftUI сам анимирует перелёт карты между зонами: из руки на стол,
// со стола в стопку победителя (с переворотом рубашкой вверх), из колоды в руки при раздаче.
// Слой не принимает касаний: касания ловит раскладка под ним (рука, центр, стопки).

/// Откуда карта прилетает, когда появляется на столе.
struct SpriteOrigin: Equatable {
    var position: CGPoint
    var rotation: Double = 0
    var scale: CGFloat = 1
    var faceUp = false
}

/// Одна карта на столе.
struct CardSprite: Identifiable, Equatable {
    var id: String
    /// nil — рубашка (карта соперника, колода, старые взятки).
    var card: Card?
    /// Ширина, в которой карта рисуется (видимый размер — `width * scale`).
    var width: CGFloat
    var position: CGPoint
    var rotation: Double = 0
    var scale: CGFloat = 1
    var faceUp = true
    var z: Double = 0
    var dimmed = false
    var highlighted = false
    var playable = false
    var isTrump = false
    var showsBottomIndex = true
    var origin: SpriteOrigin?
    /// Задержка прилёта (раздача веером).
    var delay: Double = 0
}

/// Всё, что нужно слою карт о партии.
struct TableScene: Equatable {
    var deal: Deal
    /// Номер сдачи: у карт новой сдачи новые id, и они прилетают из колоды, а не переезжают из стопок.
    var dealKey: Int
    var humanSeat: Int
    var displayedTrick: Trick?
    var selected: Card?
    var legal: Set<Card>
    /// Ход человека в розыгрыше.
    var humanActive: Bool
    var reduceMotion: Bool
    var metrics: TableMetrics
    /// Карта, которую тянут пальцем.
    var drag: HandDrag? = nil

    var playerCount: Int { deal.playerCount }

    /// Открытая карта и колода — в центре (торговля, обмен семёрки, пересдача).
    var heroPhase: Bool {
        switch deal.phase {
        case .bidding, .exchange: return true
        case .playing: return false
        case .finished: return deal.trump == nil
        }
    }

    func relative(_ seat: Int) -> Int {
        (seat - humanSeat + playerCount) % playerCount
    }

    /// Взятки, лежащие в стопках (без той, что ещё показывается на столе).
    var collectedTricks: [Trick] {
        TableScene.collected(deal: deal, displayed: displayedTrick)
    }

    func pileCount(_ seat: Int) -> Int {
        TableScene.pileCountFor(seat, deal: deal, displayed: displayedTrick)
    }

    /// Взяток в стопке места (без взятки, которая ещё лежит на столе).
    static func pileCountFor(_ seat: Int, deal: Deal, displayed: Trick?) -> Int {
        collected(deal: deal, displayed: displayed).filter { $0.winner == seat }.count
    }

    static func collected(deal: Deal, displayed: Trick?) -> [Trick] {
        var tricks = deal.tricks
        if displayed != nil, !tricks.isEmpty, tricks.last == displayed {
            tricks.removeLast()
        }
        return tricks
    }

    /// Это последняя взятка сдачи (за неё — ещё 10 очков): руки пусты, и взятка — последняя сыгранная.
    static func isLastTrick(_ trick: Trick, of deal: Deal) -> Bool {
        deal.tricks.last == trick && deal.hands.allSatisfy { $0.isEmpty }
    }
}

// MARK: - Раскладка карт

enum CardSprites {

    static func build(scene: TableScene, frames: [TableSlot: CGRect]) -> [CardSprite] {
        var builder = Builder(scene: scene, frames: frames)
        builder.build()
        return builder.sprites
    }

    private struct Builder {
        let scene: TableScene
        let frames: [TableSlot: CGRect]
        var sprites: [CardSprite] = []
        var used: Set<String> = []

        init(scene: TableScene, frames: [TableSlot: CGRect]) {
            self.scene = scene
            self.frames = frames
        }

        var m: TableMetrics { scene.metrics }
        var deal: Deal { scene.deal }
        var renderWidth: CGFloat { m.renderCardWidth }

        var trickWidth: CGFloat {
            guard let center = frames[.center] else { return m.handCardWidth }
            return TrickGeometry.cardWidth(center: center, playerCount: scene.playerCount,
                                           metrics: m, deck: frames[.deck])
        }

        var heroWidth: CGFloat {
            guard let center = frames[.center] else { return m.handCardWidth }
            return HeroGeometry.cardWidth(center: center, handCardWidth: m.handCardWidth)
        }

        /// Ключ карты: в пределах сдачи карта — одна и та же вьюха, где бы она ни лежала.
        /// При «уменьшении движения» зона входит в ключ: вместо полёта — смена на месте.
        func key(_ card: Card, zone: String) -> String {
            let base = "\(scene.dealKey).c\(card.id)"
            return scene.reduceMotion ? base + "." + zone : base
        }

        /// Где сейчас колода и какой она видимой ширины.
        var stockSpot: (point: CGPoint, width: CGFloat)? {
            if scene.heroPhase, let center = frames[.center] {
                let w = heroWidth
                return (HeroGeometry.stockPoint(center, cardWidth: w), w)
            }
            if let deck = frames[.deck] {
                return (DeckGeometry.stockCenter(deck, cardWidth: m.deckCardWidth), m.deckCardWidth)
            }
            return nil
        }

        /// Прилёт из колоды при раздаче для карты, нарисованной в ширину `width`.
        /// `hasFace` — у карты есть лицо (карта человека): летит рубашкой вверх и переворачивается.
        func fromStock(width: CGFloat, hasFace: Bool) -> SpriteOrigin? {
            guard !scene.reduceMotion, let spot = stockSpot else { return nil }
            return SpriteOrigin(position: spot.point, rotation: -3, scale: spot.width / max(width, 1),
                                faceUp: !hasFace)
        }

        mutating func add(_ sprite: CardSprite) {
            guard !used.contains(sprite.id) else { return }
            used.insert(sprite.id)
            sprites.append(sprite)
        }

        mutating func build() {
            addStockAndOpenCard()
            addBottomCard()
            addHand()
            addFans()
            addTrick()
            addPiles()
        }

        // MARK: Колода и открытая карта

        mutating func addStockAndOpenCard() {
            let hero = scene.heroPhase
            let open = deal.openCard
            if hero, let center = frames[.center] {
                let w = heroWidth
                let render = m.heroRenderWidth
                let scale = w / render
                if !deal.stock.isEmpty {
                    let point = HeroGeometry.stockPoint(center, cardWidth: w)
                    for k in 0..<3 {
                        let d = CGFloat(k) * 1.5
                        add(CardSprite(id: "\(scene.dealKey).s\(k).h", card: nil, width: render,
                                       position: CGPoint(x: point.x - d, y: point.y - d),
                                       rotation: -3, scale: scale, z: Double(10 + k)))
                    }
                }
                var sprite = CardSprite(id: "\(scene.dealKey).o\(open.id).h", card: open, width: render,
                                        position: HeroGeometry.openPoint(center, cardWidth: w),
                                        rotation: 2, scale: scale, z: 20)
                sprite.isTrump = deal.trump == open.suit
                if !scene.reduceMotion {
                    // Открывается на глазах: из колоды, переворачиваясь.
                    sprite.origin = SpriteOrigin(position: HeroGeometry.stockPoint(center, cardWidth: w),
                                                 rotation: -3, scale: scale, faceUp: false)
                    sprite.delay = 0.35
                }
                add(sprite)
            } else if let deck = frames[.deck] {
                // Колода у левого края: рубашки лёжа, из-под них уголком выглядывает открытая карта.
                let w = m.deckCardWidth
                var sprite = CardSprite(id: "\(scene.dealKey).o\(open.id).d", card: open, width: w,
                                        position: DeckGeometry.openCenter(deck, cardWidth: w),
                                        rotation: 90, z: 11)
                sprite.isTrump = deal.trump == open.suit
                sprite.showsBottomIndex = false
                if !scene.reduceMotion, let center = frames[.center] {
                    // Переезжает из центра, где лежала во время торговли.
                    let hw = heroWidth
                    sprite.origin = SpriteOrigin(position: HeroGeometry.openPoint(center, cardWidth: hw),
                                                 rotation: 2, scale: hw / w, faceUp: true)
                }
                add(sprite)
                if !deal.stock.isEmpty {
                    let stockPoint = DeckGeometry.stockCenter(deck, cardWidth: w)
                    for k in 0..<3 {
                        let d = CGFloat(k) * 1.3
                        var sprite = CardSprite(id: "\(scene.dealKey).s\(k).d", card: nil, width: w,
                                                position: CGPoint(x: stockPoint.x + d, y: stockPoint.y - d),
                                                rotation: 90, z: Double(12 + k))
                        if !scene.reduceMotion, let center = frames[.center] {
                            // После торговли колода переезжает из центра к краю стола.
                            let hw = heroWidth
                            sprite.origin = SpriteOrigin(position: HeroGeometry.stockPoint(center, cardWidth: hw),
                                                         rotation: -3, scale: hw / w, faceUp: true)
                        }
                        add(sprite)
                    }
                }
            }
        }

        mutating func addBottomCard() {
            guard deal.bottomCardVisible, let bottom = deal.bottomCard, let slot = frames[.deck] else { return }
            let w = DeckGeometry.bottomWidth(cardWidth: m.deckCardWidth)
            var sprite = CardSprite(id: "\(scene.dealKey).b\(bottom.id)", card: bottom, width: w,
                                    position: DeckGeometry.bottomCenter(slot, cardWidth: m.deckCardWidth),
                                    rotation: -4, z: 14)
            sprite.isTrump = deal.trump == bottom.suit
            if !scene.reduceMotion {
                // Открывается на глазах: из колоды, переворачиваясь.
                sprite.origin = SpriteOrigin(position: DeckGeometry.stockCenter(slot, cardWidth: m.deckCardWidth),
                                             rotation: 90, faceUp: false)
            }
            add(sprite)
        }

        // MARK: Рука человека

        mutating func addHand() {
            guard let frame = frames[.hand] else { return }
            let seat = scene.humanSeat
            let cards = deal.hands[seat].sortedForDisplay(trump: deal.trump)
            let hw = m.handCardWidth
            let centers = HandFan.centers(for: cards, width: frame.width, cardWidth: hw)
            let cardHeight = hw * CardView.aspectRatio
            let lift = m.handLift
            let render = renderWidth
            let scale = hw / render
            for (index, card) in cards.enumerated() {
                let isLegal = scene.legal.contains(card)
                let isSelected = scene.selected == card
                let rise = HandFan.rise(selected: isSelected, legal: isLegal, active: scene.humanActive, lift: lift)
                let arc = HandFan.arc(index: index, count: cards.count, cardWidth: hw)
                var sprite = CardSprite(id: key(card, zone: "h"), card: card, width: render,
                                        position: CGPoint(x: frame.minX + centers[index],
                                                          y: frame.minY + rise + cardHeight / 2 + arc.dy),
                                        rotation: arc.angle, scale: scale, z: Double(100 + index))
                sprite.dimmed = scene.humanActive && !isLegal
                sprite.playable = scene.humanActive && isLegal && !isSelected
                sprite.highlighted = isSelected
                sprite.isTrump = deal.trump == card.suit
                sprite.showsBottomIndex = index == cards.count - 1
                sprite.origin = fromStock(width: render, hasFace: true)
                sprite.delay = Double(index) * 0.05
                if let drag = scene.drag, drag.card == card, drag.hover {
                    // Палец на карте: чуть выше соседей и чуть крупнее — видно, какая под пальцем
                    // (недопустимая в ваш ход — едва-едва, чтобы не спорить с подсветкой допустимых).
                    let hover = HandFan.hoverRise(legal: isLegal, active: scene.humanActive, lift: lift)
                    sprite.position.y -= hover
                    sprite.scale = scale * (hover > lift * 0.3 ? 1.03 : 1)
                } else if let drag = scene.drag, drag.card == card, drag.preview {
                    // Карту рассматривают: крупно, ровно, над серединой руки.
                    let big = min(hw * 1.8, render * 1.3)
                    sprite.position = CGPoint(x: frame.midX, y: frame.minY - big * CardView.aspectRatio * 0.42)
                    sprite.rotation = 0
                    sprite.scale = big / render
                    sprite.z = 700
                    sprite.highlighted = false
                    sprite.playable = false
                    sprite.dimmed = false
                    sprite.showsBottomIndex = true
                } else if let drag = scene.drag, drag.card == card {
                    // Карта в пальцах: над всеми, чуть крупнее, наклон — по движению руки.
                    sprite.position.x += drag.translation.width
                    sprite.position.y += drag.translation.height
                    sprite.rotation = drag.playable
                        ? max(-14, min(14, Double(drag.translation.width) * 0.08))
                        : arc.angle
                    sprite.scale = scale * (drag.playable ? 1.08 : 1)
                    sprite.z = 600
                    sprite.highlighted = drag.playable
                    sprite.playable = false
                    sprite.showsBottomIndex = true
                }
                add(sprite)
            }
        }

        // MARK: Веера соперников

        mutating func addFans() {
            let w = m.fanCardWidth
            for seat in 0..<scene.playerCount where seat != scene.humanSeat {
                guard let frame = frames[.fan(seat)] else { continue }
                let count = deal.hands[seat].count
                guard count > 0 else { continue }
                let step = count > 1 ? min(w * 0.45, (frame.width - w) / CGFloat(count - 1)) : 0
                let total = w + step * CGFloat(count - 1)
                let startX = frame.midX - total / 2 + w / 2
                let mid = Double(count - 1) / 2
                for slot in 0..<count {
                    let spread = Double(slot) - mid
                    var sprite = CardSprite(id: "\(scene.dealKey).f\(seat).\(slot)", card: nil, width: w,
                                            position: CGPoint(x: startX + CGFloat(slot) * step,
                                                              y: frame.midY + CGFloat(abs(spread)) * 0.8),
                                            rotation: spread * 2.5, z: Double(50 + slot))
                    sprite.origin = fromStock(width: w, hasFace: false)
                    sprite.delay = Double(slot) * 0.05 + 0.03 * Double(scene.relative(seat))
                    add(sprite)
                }
            }
        }

        // MARK: Взятка

        mutating func addTrick() {
            guard let center = frames[.center] else { return }
            let trick = scene.displayedTrick ?? deal.currentTrick
            let tw = trickWidth
            let render = renderWidth
            for (order, play) in trick.plays.enumerated() {
                let relative = scene.relative(play.seat)
                let (point, angle) = TrickGeometry.point(relative: relative, playerCount: scene.playerCount,
                                                          center: center, cardWidth: tw)
                let isWinner = scene.displayedTrick != nil && trick.winner == play.seat
                var sprite = CardSprite(id: key(play.card, zone: "t"), card: play.card, width: render,
                                        position: point, rotation: angle,
                                        scale: tw / render * (isWinner ? 1.06 : 1),
                                        z: Double(200 + order) + (isWinner ? 10 : 0))
                sprite.highlighted = isWinner
                sprite.isTrump = deal.trump == play.card.suit
                sprite.origin = trickOrigin(seat: play.seat, render: render)
                add(sprite)
            }
        }

        /// Карта соперника прилетает из его веера рубашкой вверх и переворачивается.
        func trickOrigin(seat: Int, render: CGFloat) -> SpriteOrigin? {
            guard !scene.reduceMotion else { return nil }
            if seat == scene.humanSeat {
                guard let hand = frames[.hand] else { return nil }
                return SpriteOrigin(position: CGPoint(x: hand.midX, y: hand.midY),
                                    scale: m.handCardWidth / render, faceUp: true)
            }
            guard let from = frames[.fan(seat)] ?? frames[.seat(seat)] else { return nil }
            return SpriteOrigin(position: CGPoint(x: from.midX, y: from.midY),
                                scale: m.fanCardWidth / render, faceUp: false)
        }

        // MARK: Стопки взяток

        mutating func addPiles() {
            let tricks = scene.collectedTricks
            let pw = m.pileCardWidth
            let render = renderWidth
            for seat in 0..<scene.playerCount {
                guard let frame = frames[.pile(seat)] else { continue }
                let won = tricks.filter { $0.winner == seat }
                guard let last = won.last else { continue }
                let layers = min(4, won.count - 1)
                let base = CGPoint(x: frame.midX, y: frame.midY)
                // Старые взятки — просто слои рубашек.
                for k in 0..<layers {
                    let d = CGFloat(k) * 1.5
                    add(CardSprite(id: "\(scene.dealKey).p\(seat).\(k)", card: nil, width: pw,
                                   position: CGPoint(x: base.x + d, y: base.y - d),
                                   rotation: 90 + Double(k % 2 == 0 ? -2 : 2), z: Double(60 + k)))
                }
                // Последняя взятка места — те самые карты, что только что лежали на столе.
                let top = CGFloat(layers) * 1.5
                for (index, play) in last.plays.enumerated() {
                    let jitter = Double(index) * 4 - 4
                    let sprite = CardSprite(id: key(play.card, zone: "p"), card: play.card, width: render,
                                            position: CGPoint(x: base.x + top, y: base.y - top),
                                            rotation: 90 + jitter, scale: pw / render, faceUp: false,
                                            z: Double(70 + index))
                    add(sprite)
                }
            }
        }
    }
}

// MARK: - Вьюхи слоя

/// Переворот карты: до 90° видно лицо, дальше — рубашку.
struct CardFlip: ViewModifier, Animatable {
    var angle: Double
    let width: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let showBack = angle > 90
        return ZStack {
            content
                .opacity(showBack ? 0 : 1)
            if showBack {
                CardView(card: nil, width: width)
                    .scaleEffect(x: -1, y: 1)
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}

/// Одна карта слоя. Новая карта сначала стоит в точке `origin` (колода, веер соперника),
/// а затем летит на своё место.
struct CardSpriteView: View {
    let sprite: CardSprite
    /// Анимировать прилёт (false — при первом показе стола карты сразу на местах).
    let animateArrival: Bool
    let flight: Double

    @State private var arrived = false

    var body: some View {
        let origin: SpriteOrigin? = (!arrived && animateArrival) ? sprite.origin : nil
        let position = origin?.position ?? sprite.position
        let rotation = origin?.rotation ?? sprite.rotation
        let scale = origin?.scale ?? sprite.scale
        let faceUp = origin?.faceUp ?? sprite.faceUp
        CardView(card: sprite.card, width: sprite.width, dimmed: sprite.dimmed,
                 highlighted: sprite.highlighted, isTrump: sprite.isTrump,
                 showsBottomIndex: sprite.showsBottomIndex, playable: sprite.playable)
            .modifier(CardFlip(angle: faceUp ? 0 : 180, width: sprite.width))
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .position(position)
            .onAppear(perform: arrive)
    }

    private func arrive() {
        guard !arrived else { return }
        guard animateArrival, sprite.origin != nil else {
            arrived = true
            return
        }
        let duration = flight
        let delay = sprite.delay
        // Первый кадр — в точке вылета, дальше — полёт.
        Task { @MainActor in
            withAnimation(.easeInOut(duration: duration).delay(delay)) {
                arrived = true
            }
        }
    }
}

/// Все карты стола.
struct CardLayerView: View {
    let sprites: [CardSprite]
    let flight: Double
    let size: CGSize

    /// Карты, появившиеся при первом показе стола, не летят — кроме свежей раздачи.
    @State private var ready: Bool

    init(sprites: [CardSprite], flight: Double, size: CGSize, animateOnAppear: Bool = false) {
        self.sprites = sprites
        self.flight = flight
        self.size = size
        _ready = State(initialValue: animateOnAppear)
    }

    var body: some View {
        ZStack {
            ForEach(sprites) { sprite in
                CardSpriteView(sprite: sprite, animateArrival: ready, flight: flight)
                    .zIndex(sprite.z)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            ready = true
        }
    }
}
