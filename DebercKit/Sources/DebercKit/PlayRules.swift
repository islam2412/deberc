import Foundation

public enum PlayRules {

    /// Карты, которыми можно ходить. `trick` — уже лежащие во взятке карты по порядку.
    public static func legalCards(hand: [Card], trick: [Card], trump: Suit, rules: RuleSet) -> [Card] {
        guard let led = trick.first?.suit else { return hand }
        let highestTrump = trick.filter { $0.suit == trump }.map { $0.power(trump: trump) }.max()

        let sameSuit = hand.filter { $0.suit == led }
        if !sameSuit.isEmpty {
            if led == trump, rules.overtrump != .never, let highestTrump {
                let higher = sameSuit.filter { $0.power(trump: trump) > highestTrump }
                if !higher.isEmpty { return higher }
            }
            return sameSuit
        }

        let trumps = hand.filter { $0.suit == trump }
        if rules.mustTrump && !trumps.isEmpty {
            if rules.overtrump == .always, let highestTrump {
                let higher = trumps.filter { $0.power(trump: trump) > highestTrump }
                if !higher.isEmpty { return higher }
            }
            return trumps
        }
        return hand
    }

    /// Бьёт ли карта `card` текущую старшую карту взятки `best` при масти хода `led`.
    public static func beats(_ card: Card, _ best: Card, led: Suit, trump: Suit) -> Bool {
        if card.suit == best.suit { return card.power(trump: trump) > best.power(trump: trump) }
        if card.suit == trump { return true }
        return false
    }

    /// Номер карты во взятке, которая её берёт.
    public static func winningIndex(_ trick: [Card], trump: Suit) -> Int {
        precondition(!trick.isEmpty)
        let led = trick[0].suit
        var bestIndex = 0
        for i in 1..<trick.count where beats(trick[i], trick[bestIndex], led: led, trump: trump) {
            bestIndex = i
        }
        return bestIndex
    }

    public static func points(of cards: [Card], trump: Suit) -> Int {
        cards.reduce(0) { $0 + $1.points(trump: trump) }
    }
}
