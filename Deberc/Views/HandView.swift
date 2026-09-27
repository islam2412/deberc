import SwiftUI
import DebercKit

/// Рука человека: принимает касания. Сами карты рисует слой карт стола (`CardLayerView`)
/// по той же геометрии веера (`HandFan`), поэтому палец попадает именно в видимую карту.
///
/// Управление:
/// - касание выбирает карту (приподнимает), второе касание по ней — ход;
///   без «двойного касания» в настройках первое касание сразу ходит;
/// - можно вести пальцем по руке: поднимается карта под пальцем, отпускание оставляет её выбранной;
/// - смахнуть карту вверх — сходить ею сразу;
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

    /// Где началось текущее касание (nil — касания нет). По нему узнаём новое касание, даже если
    /// прошлое система отменила без `onEnded` (жест «Домой», звонок, второй палец).
    @State private var touchStart: CGPoint?
    /// Карта под пальцем в начале касания.
    @State private var startCard: Card?
    /// Какая карта была выбрана до касания (второе касание по ней — ход).
    @State private var selectionAtStart: Card?

    private var cardHeight: CGFloat { cardWidth * CardView.aspectRatio }

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
        .frame(height: cardHeight + lift)
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
                    selectionAtStart = store.selectedCard
                    startCard = card(at: value.startLocation.x, centers)
                }
                // Ведение пальцем по руке поднимает карту под пальцем (пока это не смахивание вверх).
                if isActive, value.translation.height > -28, let card = card(at: value.location.x, centers) {
                    store.selectCard(card)
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let first = startCard
                let before = selectionAtStart
                touchStart = nil
                startCard = nil
                selectionAtStart = nil

                if dy < -40 && abs(dy) > abs(dx) {
                    // Смахнули вверх — ход выбранной (или взятой пальцем) картой.
                    if let card = store.selectedCard ?? first {
                        playNow(card)
                    }
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

    /// Сходить картой сразу (смахивание, действие VoiceOver).
    private func playNow(_ card: Card) {
        if store.displayedTrick != nil {
            store.collectTrick()
        }
        guard store.isHumanTurn else { return }
        if store.legalCards.contains(card) {
            store.perform(.play(card))
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
            .frame(width: max(8, right - left), height: cardHeight)
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
