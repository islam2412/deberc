import SwiftUI
import DebercKit

/// Рука человека: принимает касания. Сами карты рисует слой карт стола (`CardLayerView`)
/// по той же геометрии веера (`HandFan`), поэтому палец попадает именно в видимую карту.
///
/// Управление:
/// - касание выбирает карту (приподнимает), второе касание по ней — ход;
///   без «двойного касания» в настройках первое касание сразу ходит;
/// - можно вести пальцем по руке: поднимается карта под пальцем, отпускание оставляет её выбранной;
/// - потянуть карту вверх — она идёт за пальцем; бросок или отпускание над рукой — ход,
///   карта летит на стол с того места, где её отпустили; отпустить у руки — вернётся на место;
/// - долгое нажатие — рассмотреть карту крупно (ход не делается);
/// - VoiceOver: каждая карта — кнопка, действие «Сходить».
struct HandView: View {
    @EnvironmentObject private var store: GameStore

    let cards: [Card]
    let cardWidth: CGFloat
    let lift: CGFloat
    let trump: Suit?
    /// Ход человека в розыгрыше.
    let isActive: Bool
    let legal: Set<Card>
    let selected: Card?
    /// Видимая высота карты: на телефоне рука уходит за нижний край экрана.
    let visibleHeight: CGFloat
    /// Карта, которую тянут пальцем (её рисует слой карт).
    @Binding var drag: HandDrag?

    /// Где началось текущее касание (nil — касания нет). По нему узнаём новое касание, даже если
    /// прошлое система отменила без `onEnded` (жест «Домой», звонок, второй палец).
    @State private var touchStart: CGPoint?
    /// Карта под пальцем в начале касания.
    @State private var startCard: Card?
    /// Какая карта была выбрана до касания (второе касание по ней — ход).
    @State private var selectionAtStart: Card?
    /// Точка, от которой считается движение вверх: начало касания или место, где палец,
    /// ведя по руке, перешёл на другую карту.
    @State private var anchor: CGPoint?
    /// Карта в пальцах (касание стало броском вверх).
    @State private var liftedCard: Card?
    /// Ждём долгого нажатия (рассмотреть карту).
    @State private var pressTask: Task<Void, Never>?
    /// Карту рассматривают: до отпускания пальца ничего больше не происходит.
    @State private var previewing = false

    var body: some View {
        GeometryReader { geo in
            let centers = HandFan.centers(for: cards, width: geo.size.width, cardWidth: cardWidth)
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                    cardStrip(index: index, card: card, centers: centers)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(touchGesture(centers: centers))
        }
        .frame(height: visibleHeight + lift)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ваши карты")
    }

    // MARK: - Касания

    private func card(at x: CGFloat, _ centers: [CGFloat]) -> Card? {
        guard let index = HandFan.index(at: x, centers: centers, cardWidth: cardWidth),
              cards.indices.contains(index) else { return nil }
        return cards[index]
    }

    private func touchGesture(centers: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if touchStart != value.startLocation {
                    // Новое касание: прошлое могло быть отменено системой без onEnded.
                    touchStart = value.startLocation
                    anchor = value.startLocation
                    selectionAtStart = store.selectedCard
                    startCard = card(at: value.startLocation.x, centers)
                    liftedCard = nil
                    previewing = false
                    waitForLongPress(on: startCard)
                }
                if previewing { return }
                if hypot(value.translation.width, value.translation.height) > 8 {
                    pressTask?.cancel()
                }
                if let card = liftedCard {
                    follow(card, translation: value.translation)
                    return
                }
                let origin = anchor ?? value.startLocation
                let up = origin.y - value.location.y
                let across = abs(value.location.x - origin.x)
                if up > 12 && up > across * 0.8, let card = card(at: origin.x, centers) ?? startCard {
                    // Палец пошёл вверх — карта «взята» и идёт за ним.
                    liftedCard = card
                    follow(card, translation: value.translation)
                    return
                }
                // Ведение пальцем по руке поднимает карту под пальцем.
                if isActive, up < 28, let card = card(at: value.location.x, centers), card != store.selectedCard {
                    store.selectCard(card)
                    anchor = value.location
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let first = startCard
                let before = selectionAtStart
                let lifted = liftedCard
                let wasPreviewing = previewing
                touchStart = nil
                startCard = nil
                selectionAtStart = nil
                anchor = nil
                liftedCard = nil
                previewing = false
                pressTask?.cancel()
                pressTask = nil

                if wasPreviewing {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { drag = nil }
                    // Рассмотренная карта остаётся выбранной: следующее касание — ход.
                    if let first, isActive, legal.contains(first) {
                        store.selectCard(first)
                    }
                } else if let lifted {
                    release(lifted, translation: value.translation, predicted: value.predictedEndTranslation)
                } else if abs(dx) < 10 && abs(dy) < 10 {
                    if let first {
                        tap(first, selectedBefore: before)
                    } else if store.displayedTrick != nil {
                        store.collectTrick()
                    }
                }
                // Иначе — вели пальцем: выбранная карта остаётся приподнятой.
            }
    }

    /// Палец задержался на карте — показать её крупно.
    private func waitForLongPress(on card: Card?) {
        pressTask?.cancel()
        guard let card else { return }
        pressTask = Task { @MainActor in
            // Дольше обычного «медленного» касания, чтобы нажатие с задержкой не стало просмотром.
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, touchStart != nil, liftedCard == nil else { return }
            previewing = true
            store.feelCardPreview()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                drag = HandDrag(card: card, translation: .zero, playable: false, preview: true)
            }
        }
    }

    /// Карта в пальцах: ходовая идёт за пальцем, остальные лишь чуть поддаются.
    private func follow(_ card: Card, translation t: CGSize) {
        let playable = store.throwableCards.contains(card)
        let shown = playable ? t : CGSize(width: t.width * 0.15, height: max(-16, t.height * 0.2))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag = HandDrag(card: card, translation: shown, playable: playable)
        }
    }

    /// Отпустили карту: бросок вверх или отпускание над рукой — ход; иначе карта возвращается.
    private func release(_ card: Card, translation t: CGSize, predicted: CGSize) {
        let thrown = t.height < -max(56, cardWidth * 0.55) || predicted.height < -cardWidth * 1.6
        guard thrown, store.throwableCards.contains(card) else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { drag = nil }
            // Бросили карту, которой ходить нельзя, — объяснить почему (или собрать взятку).
            if thrown { store.tapCard(card) }
            return
        }
        // Карта летит на стол с того места, где её отпустили.
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            drag = nil
            store.throwCard(card)
        }
    }

    /// Обычное касание карты.
    private func tap(_ card: Card, selectedBefore: Card?) {
        guard isActive, legal.contains(card), store.settings.confirmCardTap else {
            // Не ваш ход (соберёт взятку), недопустимая карта (скажет почему)
            // или ход без подтверждения — всё решает store.
            store.tapCard(card)
            return
        }
        if selectedBefore == card {
            // Второе касание по выбранной карте — ход.
            store.tapCard(card)
        } else if store.selectedCard != card {
            // Касание не успело выбрать карту (например, было очень коротким).
            store.tapCard(card)
        }
    }

    /// Сходить картой сразу (действие VoiceOver).
    private func playNow(_ card: Card) {
        if store.throwableCards.contains(card) {
            store.throwCard(card)
        } else {
            store.tapCard(card)
        }
    }

    // MARK: - VoiceOver

    /// Невидимая полоса карты: элемент VoiceOver ровно там, где видна карта.
    private func cardStrip(index: Int, card: Card, centers: [CGFloat]) -> some View {
        let left = centers[index] - cardWidth / 2
        let right = index + 1 < centers.count ? centers[index + 1] - cardWidth / 2 : centers[index] + cardWidth / 2
        let isSelected = selected == card
        let traits: AccessibilityTraits = isSelected ? [.isButton, .isSelected] : [.isButton]
        return Color.white.opacity(0.001)
            .frame(width: max(8, right - left), height: visibleHeight)
            .offset(x: left, y: lift)
            .accessibilityElement()
            .accessibilityLabel(spokenName(card))
            .accessibilityValue(spokenState(card, isSelected: isSelected))
            .accessibilityAddTraits(traits)
            .accessibilityAction { store.tapCard(card) }
            .accessibilityAction(named: "Сходить") { playNow(card) }
    }

    private func spokenName(_ card: Card) -> String {
        let name = CardView.spokenName(card)
        return trump == card.suit ? name + ", козырь" : name
    }

    private func spokenState(_ card: Card, isSelected: Bool) -> String {
        guard isActive else { return "" }
        if !legal.contains(card) { return "сейчас ходить нельзя" }
        return isSelected ? "выбрана, коснитесь ещё раз, чтобы сходить" : ""
    }
}
