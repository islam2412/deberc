import SwiftUI
import DebercKit

/// Рука человека: принимает касания. Сами карты рисует слой карт стола (`CardLayerView`)
/// по той же геометрии веера (`HandFan`), поэтому палец попадает именно в видимую карту
/// (с учётом подъёма и наклона карт).
///
/// Управление:
/// - короткое касание выбирает карту (приподнимает), второе короткое касание по ней — ход;
///   без «двойного касания» в настройках первое короткое касание сразу ходит;
/// - можно вести пальцем по руке влево-вправо: карта под пальцем чуть приподнимается (любая, и не в свой ход);
///   в свой ход допустимая карта под пальцем выбирается, отпускание оставляет её выбранной;
/// - потянуть карту вверх — она идёт за пальцем; бросок или отпускание над рукой — ход,
///   карта летит на стол с того места, где её отпустили; отпустить у руки — вернётся на место;
/// - долгое нажатие — рассмотреть карту крупно. Долгое нажатие никогда не делает ход:
///   ходом считается только короткое касание почти без сдвига пальца;
/// - VoiceOver: каждая карта — кнопка, действие «Сходить».
struct HandView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// Касание дольше этого — уже не «касание», а удержание (просмотр карты).
    static let pressDelay: TimeInterval = 0.5
    /// Сдвиг пальца больше этого — не касание (и не просмотр): вели пальцем.
    static let tapSlop: CGFloat = 12
    /// Палец ушёл вверх больше чем на столько — карта «взята» и идёт за пальцем.
    static let liftThreshold: CGFloat = 20

    /// Палец на руке. Сбрасывается сам и тогда, когда система отменила касание без `onEnded`.
    @GestureState private var touching = false
    /// Где началось текущее касание (nil — касания нет).
    @State private var touchStart: CGPoint?
    @State private var touchStartedAt = Date.distantPast
    /// Наибольший сдвиг пальца от начала касания.
    @State private var maxDistance: CGFloat = 0
    /// Карта под пальцем в начале касания.
    @State private var startCard: Card?
    /// Какая карта была выбрана до касания (второе касание по ней — ход).
    @State private var selectionAtStart: Card?
    /// Точка и карта, от которых считается движение вверх: начало касания или место,
    /// где палец, ведя по руке, перешёл на другую карту.
    @State private var anchor: CGPoint?
    @State private var anchorCard: Card?
    /// Карта в пальцах (касание стало броском вверх) и точка, где её взяли.
    @State private var liftedCard: Card?
    @State private var liftOrigin: CGPoint = .zero
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
        .onChange(of: touching) { active in
            // Касание отменила система (звонок, Пункт управления, второй палец) — onEnded не придёт.
            guard !active, let token = touchStart else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                if touchStart == token { cancelTouch() }
            }
        }
        .onChange(of: cards) { hand in
            // Карта ушла из руки (ход, автоход, новая сдача) — не держать её «в пальцах».
            if let card = drag?.card, !hand.contains(card) { drag = nil }
            if let card = liftedCard, !hand.contains(card) { liftedCard = nil }
        }
        .onDisappear(perform: cancelTouch)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ваши карты")
    }

    // MARK: - Касания

    /// Верхние кромки карт руки — как их рисует слой карт (выбранная выше, карта под пальцем ещё выше).
    private var tops: [CGFloat] {
        cards.map { card in
            let isLegal = legal.contains(card)
            var top = HandFan.rise(selected: selected == card, legal: isLegal, active: isActive, lift: lift)
            if let drag, drag.hover, drag.card == card {
                top -= HandFan.hoverRise(legal: isLegal, active: isActive, lift: lift)
            }
            return top
        }
    }

    private func card(at point: CGPoint, _ centers: [CGFloat]) -> Card? {
        guard let index = HandFan.index(at: point, centers: centers, tops: tops, cardWidth: cardWidth),
              cards.indices.contains(index) else { return nil }
        return cards[index]
    }

    private func touchGesture(centers: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                if touchStart != value.startLocation {
                    beginTouch(at: value.startLocation, centers: centers)
                }
                if previewing { return }
                maxDistance = max(maxDistance, hypot(value.translation.width, value.translation.height))
                if maxDistance > Self.tapSlop {
                    pressTask?.cancel()
                }
                if let card = liftedCard {
                    follow(card, offset: offset(value.location, from: liftOrigin))
                    return
                }
                let origin = anchor ?? value.startLocation
                let up = origin.y - value.location.y
                let across = abs(value.location.x - origin.x)
                // Порог повыше дрожания пальца: карту «берут» уверенным движением вверх.
                if up > Self.liftThreshold && up > across, let card = anchorCard ?? startCard {
                    // Палец пошёл вверх — карта под ним «взята» и идёт за пальцем от точки, где её взяли.
                    liftedCard = card
                    liftOrigin = origin
                    pressTask?.cancel()
                    follow(card, offset: offset(value.location, from: origin))
                    return
                }
                // Ведение пальцем по руке: карта под пальцем приподнимается, в свой ход — выбирается.
                let under = card(at: value.location, centers)
                if under != anchorCard {
                    anchorCard = under
                    anchor = value.location
                    if isActive, let under, legal.contains(under), under != store.selectedCard {
                        store.selectCard(under)
                    }
                }
                hover(under)
            }
            .onEnded { value in
                let duration = Date().timeIntervalSince(touchStartedAt)
                let first = startCard
                let before = selectionAtStart
                let lifted = liftedCard
                let origin = liftOrigin
                let wasPreviewing = previewing
                let isTap = !wasPreviewing && lifted == nil
                    && duration < Self.pressDelay && maxDistance < Self.tapSlop
                resetTouch()

                if wasPreviewing {
                    animate(.spring(response: 0.32, dampingFraction: 0.8)) { drag = nil }
                    // Рассмотренная карта остаётся выбранной: следующее короткое касание — ход.
                    if let first, isActive, legal.contains(first) {
                        store.selectCard(first)
                    }
                } else if let lifted {
                    release(lifted, offset: offset(value.location, from: origin),
                            predicted: offset(value.predictedEndLocation, from: origin))
                } else if isTap {
                    if let first, cards.contains(first) {
                        tap(first, selectedBefore: before)
                    } else if first == nil {
                        store.collectTrick(byUser: true)
                    }
                }
                // Иначе — вели пальцем или долго держали без просмотра: хода нет.

                // Палец ушёл — приподнятая «под пальцем» карта опускается. После хода: если карта уже
                // на столе, это ничего не меняет, а раньше хода — карта на миг провалилась бы к руке.
                if drag?.hover == true {
                    animate(.easeOut(duration: 0.15)) { drag = nil }
                }
            }
    }

    private func offset(_ point: CGPoint, from origin: CGPoint) -> CGSize {
        CGSize(width: point.x - origin.x, height: point.y - origin.y)
    }

    private func beginTouch(at point: CGPoint, centers: [CGFloat]) {
        // Новое касание: прошлое могло быть отменено системой без onEnded.
        touchStart = point
        touchStartedAt = Date()
        maxDistance = 0
        anchor = point
        selectionAtStart = store.selectedCard
        startCard = card(at: point, centers)
        anchorCard = startCard
        liftedCard = nil
        previewing = false
        store.setHandTouch(true)
        hover(startCard)
        waitForLongPress(on: startCard)
    }

    private func resetTouch() {
        touchStart = nil
        startCard = nil
        selectionAtStart = nil
        anchor = nil
        anchorCard = nil
        liftedCard = nil
        previewing = false
        maxDistance = 0
        pressTask?.cancel()
        pressTask = nil
        store.setHandTouch(false)
    }

    /// Касание прервано: всё вернуть на место без хода.
    private func cancelTouch() {
        guard touchStart != nil || drag != nil else { return }
        resetTouch()
        animate(.easeOut(duration: 0.2)) { drag = nil }
    }

    private func animate(_ animation: Animation, _ body: () -> Void) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : animation, body)
    }

    /// Карта под пальцем чуть приподнимается (nil — палец ушёл с руки).
    private func hover(_ card: Card?) {
        guard drag?.card != card || drag?.hover != true else { return }
        animate(.easeOut(duration: 0.12)) {
            drag = card.map { HandDrag(card: $0, translation: .zero, playable: false, hover: true) }
        }
    }

    /// Палец задержался на карте — показать её крупно.
    private func waitForLongPress(on card: Card?) {
        pressTask?.cancel()
        guard let card else { return }
        pressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.pressDelay * 1_000_000_000))
            guard !Task.isCancelled, touchStart != nil, liftedCard == nil,
                  maxDistance <= Self.tapSlop, cards.contains(card) else { return }
            previewing = true
            store.feelCardPreview()
            animate(.spring(response: 0.35, dampingFraction: 0.78)) {
                drag = HandDrag(card: card, translation: .zero, playable: false, preview: true)
            }
        }
    }

    /// Карта в пальцах: ходовая идёт за пальцем, остальные лишь чуть поддаются.
    private func follow(_ card: Card, offset t: CGSize) {
        let playable = store.throwableCards.contains(card)
        let shown = playable ? t : CGSize(width: t.width * 0.15, height: max(-16, t.height * 0.2))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag = HandDrag(card: card, translation: shown, playable: playable)
        }
    }

    /// Отпустили карту: бросок вверх или отпускание над рукой — ход; иначе карта возвращается.
    private func release(_ card: Card, offset t: CGSize, predicted: CGSize) {
        let thrown = t.height < -max(56, cardWidth * 0.55) || predicted.height < -cardWidth * 1.6
        guard thrown, store.throwableCards.contains(card) else {
            animate(.spring(response: 0.32, dampingFraction: 0.7)) { drag = nil }
            // Бросили карту, которой ходить нельзя, — объяснить почему.
            if thrown { store.explainCard(card) }
            return
        }
        // Карта летит на стол с того места, где её отпустили. Сначала ход, потом сброс «карты в пальцах»:
        // если сбросить раньше, карта на кадр вернётся к руке и полетит на стол с «провалом».
        let played = withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.84)) {
            store.throwCard(card)
        }
        if played {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { drag = nil }
        } else {
            animate(.spring(response: 0.32, dampingFraction: 0.7)) { drag = nil }
        }
    }

    /// Обычное (короткое) касание карты.
    private func tap(_ card: Card, selectedBefore: Card?) {
        guard isActive, legal.contains(card), store.settings.confirmCardTap else {
            // Не ваш ход (соберёт взятку или скажет, чей ход), недопустимая карта (скажет почему)
            // или ход без подтверждения — всё решает store.
            store.tapCard(card)
            return
        }
        if selectedBefore == card {
            // Второе касание по выбранной карте — ход.
            store.tapCard(card)
        } else if store.selectedCard != card {
            // Карта ещё не выбрана — выбрать (store: первое касание при «двойном касании» только выбирает).
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
            .accessibilityValue(spokenState(card))
            .accessibilityHint(spokenHint(card, isSelected: isSelected))
            .accessibilityAddTraits(traits)
            .accessibilityAction { store.tapCard(card) }
            .accessibilityAction(named: "Сходить") { playNow(card) }
    }

    private func spokenName(_ card: Card) -> String {
        let name = CardView.spokenName(card)
        return trump == card.suit ? name + ", козырь" : name
    }

    /// Только запрет: выбранную карту VoiceOver и так называет «Выбрано» (трейт `.isSelected`),
    /// а что сделает касание — в подсказке.
    private func spokenState(_ card: Card) -> String {
        isActive && !legal.contains(card) ? "сейчас ходить нельзя" : ""
    }

    /// Что сделает двойное касание VoiceOver (обычное касание под VoiceOver только наводит фокус).
    private func spokenHint(_ card: Card, isSelected: Bool) -> String {
        guard isActive, legal.contains(card) else { return "" }
        if isSelected || !store.settings.confirmCardTap { return "Коснитесь дважды, чтобы сходить" }
        return "Коснитесь дважды, чтобы выбрать, или выберите действие «Сходить»"
    }
}
