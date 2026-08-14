import Foundation

/// Everything that can go wrong while decoding Base32 text.
///
/// The cases are deliberately specific. A secret that fails to decode is one of the most
/// confusing failures a user of an authenticator can hit, because the app otherwise
/// happily produces codes that simply never work. The interface layer turns each case
/// into a message that says what is actually wrong.
public enum Base32Error: Error, Equatable, Sendable {
    /// A character outside the RFC 4648 alphabet, after separators were removed.
    ///
    /// The offset counts characters in the normalized text, not in what the user typed,
    /// so it is useful for a message but not for positioning a cursor.
    case invalidCharacter(Character, offset: Int)

    /// The number of characters cannot be produced by any input.
    ///
    /// Base32 turns 5 bytes into 8 characters, so a group can only be 8, 7, 5, 4, or 2
    /// characters long. A group of 1, 3, or 6 means characters were lost in transit.
    case invalidLength(Int)

    /// Padding appeared somewhere other than the end, or the wrong amount of it.
    case invalidPadding
}

extension Base32Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidCharacter(character, offset):
            return """
                Base32 does not allow the character "\(character)" (position \(offset + 1)). \
                Secrets use the letters A to Z and the digits 2 to 7.
                """
        case let .invalidLength(count):
            return "A Base32 secret cannot be \(count) characters long. Some characters are missing."
        case .invalidPadding:
            return "The padding at the end of this secret is malformed."
        }
    }
}
