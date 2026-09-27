import XCTest
@testable import DebercKit

/// Короткая запись карты: "Вч" = валет червей, "10п" = десятка пик, "Тб" = туз бубен, "7т" = семёрка треф.
func c(_ text: String) -> Card {
    let suitChar = text.last!
    let rankText = String(text.dropLast())
    let suit: Suit
    switch suitChar {
    case "п": suit = .spades
    case "т": suit = .clubs
    case "б": suit = .diamonds
    case "ч": suit = .hearts
    default: fatalError("Неизвестная масть в \(text)")
    }
    let rank: Rank
    switch rankText {
    case "7": rank = .seven
    case "8": rank = .eight
    case "9": rank = .nine
    case "10": rank = .ten
    case "В": rank = .jack
    case "Д": rank = .queen
    case "К": rank = .king
    case "Т": rank = .ace
    default: fatalError("Неизвестное достоинство в \(text)")
    }
    return Card(rank, suit)
}

func cards(_ text: String) -> [Card] {
    text.split(separator: " ").map { c(String($0)) }
}

/// Собирает колоду так, чтобы при раздаче получились заданные руки.
/// Порядок раздачи: по 3 карты каждому (начиная со следующего после сдающего) два раза,
/// затем открытая карта, затем прикуп по 3 карты, затем остаток колоды.
func arrangedDeck(dealer: Int, hands: [[Card]], open: Card, prikup: [[Card]]) -> [Card] {
    let n = hands.count
    precondition(hands.allSatisfy { $0.count == 6 })
    precondition(prikup.count == n && prikup.allSatisfy { $0.count == 3 })
    let order = (1...n).map { (dealer + $0) % n }
    var deck: [Card] = []
    for pass in 0..<2 {
        for seat in order { deck += hands[seat][(pass * 3)..<(pass * 3 + 3)] }
    }
    deck.append(open)
    for seat in order { deck += prikup[seat] }
    let used = Set(deck)
    precondition(used.count == deck.count, "Карты повторяются")
    deck += Card.deck.filter { !used.contains($0) }
    return deck
}

/// Играет сдачу до конца, выбирая первую допустимую карту (для проверок подсчёта).
func playOutFirstLegal(_ match: inout Match) throws {
    while let deal = match.deal, deal.phase == .playing {
        let card = deal.legalCards(for: deal.turn)[0]
        try match.apply(.play(card))
    }
}
