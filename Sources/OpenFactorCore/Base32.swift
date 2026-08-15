import Foundation

/// Base32 as defined by [RFC 4648, section 6](https://datatracker.ietf.org/doc/html/rfc4648#section-6).
///
/// Every TOTP secret arrives as Base32 text, whether it is scanned from a QR code or
/// typed in by hand, so this is the first thing that touches secret material and the
/// first thing worth auditing.
///
/// Base32 packs 5 bytes into 8 characters, 5 bits per character, most significant bit
/// first.
public enum Base32 {
    /// The RFC 4648 section 6 alphabet, in value order. Index is the 5 bit value.
    ///
    /// The digits 0, 1, and 8 are absent on purpose, because they are easily confused
    /// with O, I, and B when a secret is read off a screen.
    static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Reverse of `alphabet`, character to 5 bit value.
    private static let values: [Character: UInt8] = {
        var table: [Character: UInt8] = [:]
        for (value, character) in alphabet.enumerated() {
            table[character] = UInt8(value)
        }
        return table
    }()

    // MARK: - Decoding

    /// Decodes Base32 text into the bytes it represents.
    ///
    /// The input is normalized before decoding, see ``normalize(_:)`` for exactly what
    /// that permits. Padding is optional: services publish secrets both ways and both
    /// are accepted.
    ///
    /// - Throws: ``Base32Error`` describing precisely what is wrong. This function never
    ///   returns partial output, because a secret that is silently truncated produces
    ///   codes that look correct and never work.
    public static func decode(_ text: String) throws(Base32Error) -> Data {
        let body = try stripPadding(normalize(text))

        // 8 characters carry 5 bytes. A final partial group of 7, 5, 4, or 2 characters
        // carries 4, 3, 2, or 1 bytes. Any other remainder means characters were lost.
        guard [0, 2, 4, 5, 7].contains(body.count % 8) else {
            throw Base32Error.invalidLength(body.count)
        }

        var bytes = Data(capacity: body.count * 5 / 8)
        var buffer: UInt16 = 0
        var bitsInBuffer = 0

        for (offset, character) in body.enumerated() {
            guard let value = values[character] else {
                throw Base32Error.invalidCharacter(character, offset: offset)
            }

            buffer = (buffer << 5) | UInt16(value)
            bitsInBuffer += 5

            if bitsInBuffer >= 8 {
                bitsInBuffer -= 8
                bytes.append(UInt8(truncatingIfNeeded: buffer >> UInt16(bitsInBuffer)))
            }
        }

        // Whatever is left in the buffer is fewer than 8 bits and belongs to no byte.
        //
        // RFC 4648 section 3.5 says a decoder may reject input whose leftover bits are
        // not zero. We accept it instead. A 26 character secret carries 16 bytes plus 2
        // spare bits, and services that build a secret by drawing 26 random characters,
        // rather than by encoding 16 random bytes, leave those bits set most of the time.
        // Rejecting would refuse secrets that work correctly everywhere else, so the
        // spare bits are discarded, which is what every other authenticator does.

        return bytes
    }

    // MARK: - Encoding

    /// Encodes bytes as Base32 text.
    ///
    /// Used by the export path, and by tests to check that decoding round trips.
    ///
    /// - Parameter padded: whether to pad the final group out to 8 characters with `=`.
    ///   Defaults to `true`, which is the canonical form in RFC 4648.
    public static func encode(_ bytes: Data, padded: Bool = true) -> String {
        var text = ""
        text.reserveCapacity((bytes.count + 4) / 5 * 8)

        var buffer: UInt16 = 0
        var bitsInBuffer = 0

        for byte in bytes {
            buffer = (buffer << 8) | UInt16(byte)
            bitsInBuffer += 8

            while bitsInBuffer >= 5 {
                bitsInBuffer -= 5
                text.append(alphabet[Int((buffer >> UInt16(bitsInBuffer)) & 0b11111)])
            }
        }

        // Pad the leftover bits out to a full character with zeros on the right.
        if bitsInBuffer > 0 {
            text.append(alphabet[Int((buffer << UInt16(5 - bitsInBuffer)) & 0b11111)])
        }

        if padded && text.count % 8 != 0 {
            text.append(String(repeating: "=", count: 8 - text.count % 8))
        }

        return text
    }

    // MARK: - Normalization

    /// Prepares text for decoding, tolerating how secrets are actually presented.
    ///
    /// Three allowances, each for a real reason:
    ///
    /// - **Lowercase is uppercased, by ASCII mapping only.** RFC 4648 section 6 defines the
    ///   alphabet as uppercase, but plenty of services print secrets in lowercase. The
    ///   mapping is written out rather than delegated to `uppercased()`, which performs full
    ///   Unicode case mapping: `ß` becomes `SS`, two characters that *are* in the alphabet,
    ///   so a secret containing it would decode to different bytes depending on which
    ///   uppercase function an implementation happened to call. `docs/BACKUP_FORMAT.md`
    ///   requires ASCII mapping here for that reason, and it is the right rule everywhere
    ///   else too: a stray character should refuse a secret, never silently become one.
    /// - **Whitespace is removed.** Secrets are commonly displayed in groups of four,
    ///   like `abcd efgh ijkl`, and that is what lands on the pasteboard.
    /// - **Hyphens are removed,** for the services that group with dashes instead.
    ///
    /// Nothing else is tolerated. Any other stray character is an error rather than
    /// something to quietly skip, because skipping it would decode a different secret
    /// than the user believes they entered.
    static func normalize(_ text: String) -> [Character] {
        var characters: [Character] = []
        characters.reserveCapacity(text.count)

        for scalar in text.unicodeScalars {
            if scalar == "-" || Character(scalar).isWhitespace { continue }

            let value = scalar.value
            let mapped = (value >= 0x61 && value <= 0x7A) ? value - 0x20 : value
            characters.append(Character(Unicode.Scalar(mapped) ?? scalar))
        }

        return characters
    }

    /// Validates and removes trailing `=` padding.
    private static func stripPadding(_ characters: [Character]) throws(Base32Error) -> [Character] {
        guard let firstPadding = characters.firstIndex(of: "=") else {
            return characters
        }

        // Once padding starts it runs to the end.
        guard characters[firstPadding...].allSatisfy({ $0 == "=" }) else {
            throw Base32Error.invalidPadding
        }

        // Padded text is always a whole number of 8 character groups.
        guard characters.count % 8 == 0 else {
            throw Base32Error.invalidPadding
        }

        return Array(characters[..<firstPadding])
    }
}
