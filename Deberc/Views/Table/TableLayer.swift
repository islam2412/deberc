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
    /// Номер сдачи и цель партии — для вертикальной надписи у края стола.
    var dealNumber = 0
    var target = 0
    /// Крупное объявление в центре стола (козырь).
    var announcement: TableAnnouncement?
    /// Подначка соперника.
    var taunt: TableTaunt?
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
            TableDecorations(model: model, frames: frames, size: size)
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Реплики и отметки у мест, счётчики взяток, подпись взятки, подпись открытой карты, сообщение.
struct TableDecorations: View {
    let model: TableLayerModel
    let frames: [TableSlot: CGRect]
    /// Размер слоя (всего стола): отметки у мест не выходят за его края.
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cardAppearance) private var appearance
    @Environment(\.dynamicTypeSize) private var typeSize

    private var scene: TableScene { model.scene }
    private var deal: Deal { scene.deal }

    var body: some View {
        // Порядок — снизу вверх: надпись у края — фон; «печать» — поверх карт и подписей;
        // сообщение — поверх всего («Так сейчас нельзя» не должно прятаться под печатью).
        ZStack(alignment: .topLeading) {
            matchLabel
            ForEach(opponentSeats, id: \.self) { seat in
                seatNote(seat)
            }
            ForEach(0..<scene.playerCount, id: \.self) { seat in
                pileBadge(seat)
            }
            trickNotes
            heroCaption
            bottomCardLabel
            announcementLayer
            bannerLayer
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
            let note = noteRect(seat, area: area)
            let chatter = chatterRect(note: note)
            place(chatter, noteAlignment(seat)) {
                VStack(spacing: 6) {
                    ZStack {
                        if let text = model.bubbles[seat] {
                            SpeechBubble(text: text)
                                .id("bubble-\(seat)-\(text)")
                                .transition(noteTransition)
                        } else if let items = model.declarations[seat], !items.isEmpty {
                            // Две комбинации и бэла карточками — ≈ 340 pt; не помещаются — словами.
                            ViewThatFits(in: .horizontal) {
                                DeclarationRow(items: items, rules: model.rules, tileHeight: scene.metrics.tileHeight)
                                DeclarationRow(items: items, rules: model.rules, compact: true)
                            }
                            .transition(noteTransition)
                        }
                    }
                    // Заявки и отметки — в своём месте, даже когда подначке отдана вся ширина стола.
                    .frame(width: chatter == note ? nil : note.width)
                    .offset(x: note.midX - chatter.midX)
                    // Подначка — своим облачком, под репликой торговли (если та ещё видна).
                    if let taunt = model.taunt, taunt.seat == seat,
                       !tauntCoversTrick(taunt, width: chatter.width) {
                        SpeechBubble(text: taunt.text, chatter: true)
                            .id("taunt-\(taunt.id)")
                            .transition(noteTransition)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.bubbles[seat])
                .animation(.easeOut(duration: 0.25), value: model.declarations[seat] ?? [])
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.taunt)
            }
        }
    }

    /// Место под реплики и отметки соперника: под его местом и не за краями стола. Вдвоём — шириной
    /// не меньше 240 pt (соперник один, посередине); втроём — в ширину места, чтобы отметки двух соперников
    /// не наезжали друг на друга (а на iPad сбоку — и на центр).
    private func noteRect(_ seat: Int, area: CGRect) -> CGRect {
        let m = scene.metrics
        let alignment = noteAlignment(seat)
        let width = min(size.width - 2 * m.gutter + 8,
                        scene.playerCount == 3 ? area.width + 8 : max(area.width + 8, 240))
        let x: CGFloat
        if alignment == .topLeading {
            x = area.minX - 4
        } else if alignment == .topTrailing {
            x = area.maxX + 4 - width
        } else {
            x = area.midX - width / 2
        }
        let minX = m.gutter - 4
        let maxX = size.width - m.gutter + 4 - width
        return CGRect(x: max(minX, min(maxX, x)), y: area.maxY + 6, width: width, height: 120)
    }

    /// Место под подначку. Вдвоём — вся ширина стола: в 240 pt шутка переносится на две строки
    /// и закрывает верх карты соперника во взятке. Втроём — то же, что под заявки.
    private func chatterRect(note: CGRect) -> CGRect {
        guard scene.playerCount == 2 else { return note }
        let m = scene.metrics
        return CGRect(x: m.gutter - 4, y: note.minY, width: max(note.width, size.width - 2 * m.gutter + 8),
                      height: note.height)
    }

    /// Вдвоём шутка не помещается в строку, а карта соперника лежит во взятке: облачко закрыло бы её.
    /// Такую подначку показываем после сбора взятки (если она к тому времени не погасла).
    private func tauntCoversTrick(_ taunt: TableTaunt, width: CGFloat) -> Bool {
        guard scene.playerCount == 2 else { return false }
        let trick = scene.displayedTrick ?? deal.currentTrick
        guard trick.card(of: taunt.seat) != nil else { return false }
        return TableTextMetrics(typeSize: typeSize).width(taunt.text, .label) + 24 > width
    }

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
            // Подпись — когда последняя карта уже легла, а не пока она летит.
            TrickCaption(text: winnerCaption, prominent: true)
                .position(point)
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.2).delay(reduceMotion ? 0 : model.flight)),
                    removal: .opacity.animation(.easeOut(duration: 0.15))))
        }
    }

    private var winnerCaption: String {
        guard let trick = scene.displayedTrick, let winner = trick.winner else { return "" }
        // За последнюю взятку сдачи — ещё 10 очков: иначе они видны только в сумме в итогах.
        if TableScene.isLastTrick(trick, of: deal) {
            return winner == scene.humanSeat ? "Последняя — ваша · +10" : "Последняя — \(model.name(winner)) · +10"
        }
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

    /// «низ» на нижней карте колоды — поверх карты, целиком внутри неё у нижнего края (свисая за карту,
    /// золотая метка почти касалась золотой рамки своей плашки под колодой). Шрифт — подписи стола:
    /// 13 pt и крупнее с размером текста и в крупном режиме — не мельче остальных подписей стола.
    @ViewBuilder
    private var bottomCardLabel: some View {
        if deal.bottomCardVisible, deal.bottomCard != nil, let slot = frames[.deck] {
            let w = scene.metrics.deckCardWidth
            let point = DeckGeometry.bottomCenter(slot, cardWidth: w)
            let width = DeckGeometry.bottomWidth(cardWidth: w)
            let height = width * CardView.aspectRatio
            Text("низ")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.onGold)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.gold))
                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                .padding(.bottom, 3)
                .frame(width: width, height: height, alignment: .bottom)
                .position(x: point.x, y: point.y)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Объявление

    /// «Печать» назначенного козыря в центре стола: крупная масть, «Козырь — бубны», кто играет.
    /// Стоит у верха центра, под полосой реплик: своя карта во взятке (она ниже центра взятки) остаётся
    /// видна, если сходить во время печати, а сообщение внизу центра не прячется под ней.
    @ViewBuilder
    private var announcementLayer: some View {
        if let center = frames[.center] {
            let rect = CGRect(x: center.minX, y: center.minY + TrickGeometry.topInset, width: center.width,
                              height: max(1, center.height - TrickGeometry.topInset))
            place(rect, .top) {
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
                                      owner: seat == model.humanSeat ? "Вы" : model.name(seat),
                                      points: points, senior: senior,
                                      tileHeight: scene.metrics.roomy ? 56 : 44)
                                .id(announcement.id)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Цель партии

    /// «СДАЧА 3 · ДО 701» — вертикально у правого края стола. Сплошным второстепенным цветом (≈ 5:1 к сукну —
    /// полупрозрачный текст пожилым не прочесть) и кеглем по крупному режиму и iPad. Вписывается в отрезок от отметок
    /// соперников (втроём правый соперник говорит у самого края — ниже его реплик) до низа центра:
    /// не помещается — только «до 701», совсем тесно — не показывается. Висячие очки и пересдачи —
    /// горизонтально (`PotChip`: под козырем, а с ушками у выреза — справа от веера соперника, в левом ушке
    /// или числом на уголке козыря), их важно прочесть сразу. Рисуется первой — под всем остальным.
    @ViewBuilder
    private var matchLabel: some View {
        if !scene.metrics.wide, model.target > 0, let center = frames[.center] {
            let size = scene.metrics.matchLabelSize
            let notes: CGFloat = scene.playerCount == 3 && !scene.metrics.sideSeats ? 80 : TrickGeometry.topInset
            let top = center.minY + notes
            let bottom = center.maxY - 8
            ViewThatFits(in: .horizontal) {
                matchLabelText(dealNumber: model.dealNumber, size: size)
                matchLabelText(dealNumber: 0, size: size)
                Color.clear.frame(width: 0, height: 0)
            }
            .frame(width: max(0, bottom - top))
            .rotationEffect(.degrees(-90))
            .position(x: center.maxX - (size * 0.6 + 2), y: (top + bottom) / 2)
            .accessibilityHidden(true)
        }
    }

    /// Строка надписи; `dealNumber` 0 — без номера сдачи.
    private func matchLabelText(dealNumber: Int, size: CGFloat) -> some View {
        HStack(spacing: (size * 0.7).rounded()) {
            if dealNumber > 0 {
                Text("сдача \(dealNumber)")
            }
            Text("до \(model.target)")
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .textCase(.uppercase)
        .tracking(size * 0.25)
        .foregroundStyle(Theme.tableSecondaryText)
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - Открытая карта во время торговли

    /// Подпись под открытой картой. Пока внизу центра сообщение (совет, «Ход отменён»), подпись прячется:
    /// они стоят в одном месте, и сообщение важнее — оно гаснет само, и подпись возвращается.
    @ViewBuilder
    private var heroCaption: some View {
        if scene.heroPhase, let center = frames[.center], let text = heroText {
            let w = HeroGeometry.cardWidth(center: center, handCardWidth: scene.metrics.handCardWidth)
            let top = HeroGeometry.captionTop(center, cardWidth: w)
            // Высота — до низа центра, а не ровно под две строки мелкого текста: при крупном тексте
            // двухстрочная подпись 2-го круга иначе обрезалась бы.
            let rect = CGRect(x: center.minX + 12, y: top, width: max(40, center.width - 24),
                              height: max(HeroGeometry.captionSpace - 6, center.maxY - 4 - top))
            place(rect, .top) {
                Text(TableText.styled(text, onLight: false, fourColor: appearance.fourColor))
                    .accessibilityLabel(Narrator.spoken(text))
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.tableText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .opacity(model.banner == nil ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: model.banner == nil)
            }
        }
    }

    /// Круг торговли и «все пас» — в индикаторе вверху, «Все спасовали — пересдача» — в сообщении:
    /// здесь их не повторяем, чтобы одно и то же не было на экране дважды.
    private var heroText: String? {
        switch deal.phase {
        case .bidding(let round):
            if round == 1 {
                return "Открыта \(TableText.short(deal.openCard))"
            }
            return "2-й круг · любая масть, кроме \(TableText.suitGenitive(deal.openCard.suit))"
        case .exchange:
            return "Обмен козырной семёрки"
        case .finished, .playing:
            return nil
        }
    }

    // MARK: - Сообщение

    @ViewBuilder
    private var bannerLayer: some View {
        if let center = frames[.center] {
            // Втроём колода лежит внизу слева центра — сообщение ставим правее неё, чтобы не закрывать
            // открытую и нижнюю карту (если место есть; иначе — во всю ширину).
            let left: CGFloat = {
                guard scene.playerCount == 3, let deck = frames[.deck] else { return center.minX + 12 }
                let edge = DeckGeometry.footprint(deck, cardWidth: scene.metrics.deckCardWidth)
                    .reduce(deck.minX) { max($0, $1.maxX) } + 8
                return center.maxX - edge >= 220 ? edge : center.minX + 12
            }()
            let rect = CGRect(x: left, y: center.minY, width: max(1, center.maxX - 12 - left),
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
