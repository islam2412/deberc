import SwiftUI
import DebercKit

/// Что показывает слой поверх раскладки (кроме самих карт).
struct TableLayerModel {
    var scene: TableScene
    var flight: Double
    /// Имена для подписей: «Вы» для человека.
    var names: [String]
    /// Реплики торговли по местам.
    var bubbles: [Int: String]
    /// Постоянные отметки у мест соперников (комбинации, бэла, обмен семёрки).
    var declarations: [Int: [DeclItem]]
    var rules: RuleSet
    var banner: String?
    var bannerUrgent: Bool
    /// Сдачу только что раздали (стол открылся на ней) — раздача видна с первого кадра.
    var freshDeal: Bool
    /// Номер сдачи, цель партии, висячие очки и пересдачи подряд — для вертикальной надписи у края стола.
    var dealNumber = 0
    var target = 0
    var pot = 0
    var redeals = 0
    var forcedAfter = 0
    /// Крупное объявление в центре стола (козырь).
    var announcement: TableAnnouncement?
    var humanSeat = 0

    func name(_ seat: Int) -> String {
        names.indices.contains(seat) ? names[seat] : ""
    }
}

/// Слой поверх раскладки стола: карты и всё, что должно лежать поверх карт.
/// Касаний не принимает; кадры мест приходят из раскладки (`TableSlot`).
struct TableLayer: View {
    let model: TableLayerModel
    let frames: [TableSlot: CGRect]
    let size: CGSize

    var body: some View {
        let sprites = CardSprites.build(scene: model.scene, frames: frames)
        ZStack(alignment: .topLeading) {
            CardLayerView(sprites: sprites, flight: model.flight, size: size, animateOnAppear: model.freshDeal)
                .animation(.easeOut(duration: 0.2), value: model.scene.humanActive)
            TableDecorations(model: model, frames: frames)
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Реплики и отметки у мест, счётчики взяток, подпись взятки, подпись открытой карты, сообщение.
struct TableDecorations: View {
    let model: TableLayerModel
    let frames: [TableSlot: CGRect]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cardAppearance) private var appearance

    private var scene: TableScene { model.scene }
    private var deal: Deal { scene.deal }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(opponentSeats, id: \.self) { seat in
                seatNote(seat)
            }
            ForEach(0..<scene.playerCount, id: \.self) { seat in
                pileBadge(seat)
            }
            trickNotes
            heroCaption
            bottomCardLabel
            matchLabel
            bannerLayer
            announcementLayer
        }
    }

    private var opponentSeats: [Int] {
        (0..<scene.playerCount).filter { $0 != scene.humanSeat }
    }

    /// Ставит содержимое в прямоугольник с выравниванием.
    private func place<V: View>(_ rect: CGRect, _ alignment: Alignment, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: max(1, rect.width), height: max(1, rect.height), alignment: alignment)
            .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Места соперников

    /// Область места: плашка, веер и стопка вместе.
    private func seatArea(_ seat: Int) -> CGRect? {
        let parts = [frames[.seat(seat)], frames[.fan(seat)], frames[.pile(seat)]].compactMap { $0 }
        guard var area = parts.first else { return nil }
        for rect in parts.dropFirst() {
            area = area.union(rect)
        }
        return area
    }

    private func noteAlignment(_ seat: Int) -> Alignment {
        guard scene.playerCount == 3, !scene.metrics.sideSeats else { return .top }
        return scene.relative(seat) == 1 ? .topLeading : .topTrailing
    }

    @ViewBuilder
    private func seatNote(_ seat: Int) -> some View {
        if let area = seatArea(seat) {
            let rect = CGRect(x: area.minX - 4, y: area.maxY + 6, width: area.width + 8, height: 70)
            place(rect, noteAlignment(seat)) {
                ZStack {
                    if let text = model.bubbles[seat] {
                        SpeechBubble(text: text)
                            .id("bubble-\(seat)-\(text)")
                            .transition(noteTransition)
                    } else if let items = model.declarations[seat], !items.isEmpty {
                        DeclarationRow(items: items, rules: model.rules, tileHeight: tileHeight)
                            .transition(noteTransition)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.bubbles[seat])
                .animation(.easeOut(duration: 0.25), value: model.declarations[seat] ?? [])
            }
        }
    }

    private var tileHeight: CGFloat { scene.metrics.roomy ? 32 : 24 }

    private var noteTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
    }

    // MARK: - Стопки взяток

    @ViewBuilder
    private func pileBadge(_ seat: Int) -> some View {
        let count = scene.pileCount(seat)
        if count > 0, let pile = frames[.pile(seat)] {
            Text("\(count)")
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.onGold)
                .frame(minWidth: 22, minHeight: 22)
                .background(Circle().fill(Theme.gold))
                .overlay(Circle().strokeBorder(Theme.goldDeep.opacity(0.7), lineWidth: 1))
                .position(x: pile.maxX - 4, y: pile.minY + 4)
        }
    }

    // MARK: - Взятка

    @ViewBuilder
    private var trickNotes: some View {
        if let center = frames[.center], let point = winnerCaptionPoint(center) {
            TrickCaption(text: winnerCaption, prominent: true)
                .position(point)
                .transition(.opacity)
        }
    }

    private var winnerCaption: String {
        guard let winner = scene.displayedTrick?.winner else { return "" }
        return winner == scene.humanSeat ? "Ваша взятка" : "Берёт \(model.name(winner))"
    }

    /// Подпись победителя — прямо на его карте, ближе к низу: не выходит за пределы взятки
    /// и не спорит с сообщением внизу центра.
    private func winnerCaptionPoint(_ center: CGRect) -> CGPoint? {
        guard let displayed = scene.displayedTrick, let winner = displayed.winner,
              displayed.plays.contains(where: { $0.seat == winner }) else { return nil }
        let width = TrickGeometry.cardWidth(center: center, playerCount: scene.playerCount,
                                            metrics: scene.metrics, deck: frames[.deck])
        let placed = TrickGeometry.point(relative: scene.relative(winner), playerCount: scene.playerCount,
                                         center: center, cardWidth: width)
        return CGPoint(x: placed.0.x, y: placed.0.y + width * CardView.aspectRatio * 0.3)
    }

    // MARK: - Нижняя карта колоды

    /// «низ» на нижней карте колоды — поверх карты, у её нижнего края.
    @ViewBuilder
    private var bottomCardLabel: some View {
        if deal.bottomCardVisible, deal.bottomCard != nil, let slot = frames[.deck] {
            let w = scene.metrics.deckCardWidth
            let point = DeckGeometry.bottomCenter(slot, cardWidth: w)
            let height = DeckGeometry.bottomWidth(cardWidth: w) * CardView.aspectRatio
            Text("низ")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onGold)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.gold))
                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                .position(x: point.x, y: point.y + height / 2 - 4)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Объявление

    /// «Печать» назначенного козыря в центре стола: крупная масть, «Козырь — бубны», кто играет.
    @ViewBuilder
    private var announcementLayer: some View {
        if let center = frames[.center] {
            ZStack {
                if let announcement = model.announcement {
                    switch announcement.kind {
                    case .trump(let seat, let suit, let forced):
                        TrumpStamp(suit: suit,
                                   title: (forced ? "Обязы — " : "Козырь — ") + suit.name,
                                   subtitle: seat == model.humanSeat ? "играете вы" : "играет \(model.name(seat))")
                            .id(announcement.id)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    case .melds(let seat, let melds, let points, let senior):
                        MeldStamp(melds: melds, rules: model.rules,
                                  owner: seat == model.humanSeat ? "у вас" : "у \(model.name(seat))",
                                  points: points, senior: senior,
                                  tileHeight: scene.metrics.roomy ? 56 : 44)
                            .id(announcement.id)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
            }
            .position(x: center.midX, y: TrickGeometry.clusterCenter(center).y)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Цель партии

    /// «ДО 701 · ВИСЯТ 40» — вертикально у правого края стола, полупрозрачно, чтобы не спорить с картами;
    /// висячие очки и пересдачи — золотом, ярче.
    @ViewBuilder
    private var matchLabel: some View {
        if !scene.metrics.wide, model.target > 0, let center = frames[.center] {
            HStack(spacing: 10) {
                if model.dealNumber > 0 {
                    Text("сдача \(model.dealNumber)")
                        .foregroundStyle(Theme.tableText.opacity(0.32))
                }
                Text("до \(model.target)")
                    .foregroundStyle(Theme.tableText.opacity(0.5))
                if model.pot > 0 {
                    Text("висят \(model.pot)")
                        .foregroundStyle(Theme.gold.opacity(0.85))
                } else if model.redeals > 0 && model.forcedAfter > 0 {
                    Text("пересдач \(model.redeals)")
                        .foregroundStyle(Theme.gold.opacity(0.85))
                }
            }
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .textCase(.uppercase)
            .tracking(4)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .position(x: center.maxX - 11, y: center.midY)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Открытая карта во время торговли

    @ViewBuilder
    private var heroCaption: some View {
        if scene.heroPhase, let center = frames[.center], let text = heroText {
            let w = HeroGeometry.cardWidth(center: center, handCardWidth: scene.metrics.handCardWidth)
            let point = HeroGeometry.captionPoint(center, cardWidth: w)
            Text(TableText.styled(text, onLight: false, fourColor: appearance.fourColor))
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.tableText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(width: max(40, center.width - 24))
                .position(point)
        }
    }

    private var heroText: String? {
        switch deal.phase {
        case .bidding(let round):
            if round == 1 {
                return "Открыта \(TableText.short(deal.openCard)) · 1-й круг"
            }
            return "2-й круг · любая масть, кроме \(TableText.suitGenitive(deal.openCard.suit))"
        case .exchange:
            return "Обмен козырной семёрки"
        case .finished:
            return deal.allPassed ? "Все спасовали — пересдача" : nil
        case .playing:
            return nil
        }
    }

    // MARK: - Сообщение

    @ViewBuilder
    private var bannerLayer: some View {
        if let center = frames[.center] {
            let rect = CGRect(x: center.minX + 12, y: center.minY, width: max(1, center.width - 24),
                              height: max(1, center.height - 6))
            place(rect, .bottom) {
                ZStack {
                    if let banner = model.banner {
                        BannerView(text: banner, urgent: model.bannerUrgent)
                            .id(banner)
                            .transition(bannerTransition)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: model.banner)
            }
        }
    }

    /// Новое сообщение всплывает чуть снизу, старое гаснет на месте — не наезжая на полосу игрока под ним.
    /// (Отдельная анимация с задержкой внутри перехода не годится: сообщение, пришедшее во время
    /// другой анимации стола, могло так и остаться невидимым.)
    private var bannerTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity)
    }
}

/// Подпись у карты взятки: «Берёт Саша», «заход».
struct TrickCaption: View {
    let text: String
    let prominent: Bool

    var body: some View {
        Text(text)
            .font(prominent ? Theme.Typography.label : Theme.Typography.caption)
            .foregroundStyle(prominent ? Theme.onGold : Theme.tableText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(prominent ? Theme.gold : Color.black.opacity(0.55))
            )
            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
    }
}
