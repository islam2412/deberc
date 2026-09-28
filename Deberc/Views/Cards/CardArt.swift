import SwiftUI
import UIKit
import DebercKit

/// Растровые иллюстрации: портреты фигур, аватары соперников, орнамент рубашки.
/// Картинки лежат в каталоге ресурсов; если какой-то нет, рисуется прежний векторный вариант.
enum CardArt {
    /// Портрет верхней половины фигуры: `court-king-spades`. Нижняя половина — тот же портрет, повёрнутый на 180°.
    static func courtImageName(_ card: Card) -> String? {
        let rank: String
        switch card.rank {
        case .jack: rank = "jack"
        case .queen: rank = "queen"
        case .king: rank = "king"
        case .seven, .eight, .nine, .ten, .ace: return nil
        }
        return available("court-\(rank)-\(suitName(card.suit))")
    }

    /// Портрет персонажа: `avatar-sasha`.
    static func avatarImageName(_ persona: Persona) -> String? {
        available("avatar-\(persona.id)")
    }

    /// Золотой орнамент рубашки (одноцветный, поверх цветного поля).
    static var backOrnamentName: String? {
        available("back-ornament")
    }

    private static func suitName(_ suit: Suit) -> String {
        switch suit {
        case .spades: return "spades"
        case .clubs: return "clubs"
        case .diamonds: return "diamonds"
        case .hearts: return "hearts"
        }
    }

    /// Имя, если такая картинка есть в каталоге. Ответ запоминается: холсты карт перерисовываются часто.
    private static func available(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let known = cache[name] { return known ? name : nil }
        let exists = UIImage(named: name) != nil
        cache[name] = exists
        return exists ? name : nil
    }

    private static let lock = NSLock()
    private static var cache: [String: Bool] = [:]
}
