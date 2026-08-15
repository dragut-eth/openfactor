import Foundation

/// Enough RTF to read a document that happens to be written in it.
///
/// **This is not an RTF parser and must not grow into one.** The exports this reads are
/// reports for a human that happen to be saved as RTF, and all this needs to do is recover
/// the text. `NSAttributedString` would read it properly, and is the wrong tool here: it is a
/// large rich text engine, and handing an attacker supplied file to one in an app that
/// holds second factors buys a great deal of attack surface to read a list of labels.
///
/// So this handles exactly the constructs that appear in such a document and ignores the
/// rest:
///
/// - `\uN` for a Unicode code point, in signed decimal, which is how the field separator
///   `U+2028` arrives, and `\ucN` for how many following characters to skip after one
/// - `\'XX` for a byte in the document's code page, which is how an accented letter in an
///   account name arrives, and how the curly apostrophe in the prose does
/// - `\\`, `\{`, `\}` for literals, and `\par` and `\line` for breaks
/// - groups, with `{\fonttbl ...}`, `{\colortbl ...}` and `{\* ...}` skipped whole, since
///   their contents are markup rather than text
///
/// Every other control word is dropped along with its parameter. That is the right default
/// for this job: an unrecognised control word is formatting, and formatting is exactly what
/// we are trying to get rid of.
enum RichTextReader {

    /// Recovers the plain text of an RTF document.
    ///
    /// Never throws. A file that is not RTF at all yields whatever text it contains, and
    /// the caller finds no accounts in it, which is the correct outcome for "the user
    /// picked the wrong file".
    static func plainText(from rtf: String) -> String {
        var out = ""
        let characters = Array(rtf)
        var index = 0

        /// How many characters follow a `\uN` that represent it for readers that cannot
        /// handle Unicode. Set by `\ucN`, one by default.
        var unicodeSkip = 1

        /// Depth of groups being skipped whole, such as the font table.
        var skippingDepth = 0
        var depth = 0

        while index < characters.count {
            let character = characters[index]

            switch character {
            case "{":
                depth += 1
                index += 1

                // A group is skipped whole when it opens with a destination whose contents
                // are markup. Looking one control word ahead is enough to tell.
                if skippingDepth == 0, isSkippableDestination(characters, from: index) {
                    skippingDepth = depth
                }

            case "}":
                if skippingDepth == depth { skippingDepth = 0 }
                depth -= 1
                index += 1

            case "\\":
                let (emitted, next, skipAfter) = readControl(
                    characters, from: index + 1, unicodeSkip: unicodeSkip
                )
                if let skipAfter { unicodeSkip = skipAfter }
                if skippingDepth == 0, let emitted { out.append(emitted) }
                index = next

            default:
                if skippingDepth == 0 { out.append(character) }
                index += 1
            }
        }

        return out
    }

    /// Whether the group starting here is one whose contents are markup rather than text.
    private static func isSkippableDestination(_ characters: [Character], from index: Int) -> Bool {
        guard index < characters.count, characters[index] == "\\" else { return false }

        // `{\*\anything}` is by definition a destination a reader may ignore.
        if index + 1 < characters.count, characters[index + 1] == "*" { return true }

        var word = ""
        var cursor = index + 1
        while cursor < characters.count, characters[cursor].isLetter, word.count < 20 {
            word.append(characters[cursor])
            cursor += 1
        }

        return ["fonttbl", "colortbl", "stylesheet", "info", "pict", "expandedcolortbl"]
            .contains(word)
    }

    /// Reads one control sequence and says what it produced, where to continue, and
    /// whether it changed the Unicode skip count.
    private static func readControl(
        _ characters: [Character],
        from index: Int,
        unicodeSkip: Int
    ) -> (emitted: Character?, next: Int, skipAfter: Int?) {
        guard index < characters.count else { return (nil, index, nil) }

        let first = characters[index]

        // \' followed by two hex digits: one byte in the document's code page.
        if first == "'" {
            let start = index + 1
            guard start + 1 < characters.count,
                let value = UInt8(String(characters[start...(start + 1)]), radix: 16)
            else {
                return (nil, index + 1, nil)
            }
            return (codePage1252(value), start + 2, nil)
        }

        // An escaped literal, which is how a backslash or a brace appears in text.
        guard first.isLetter else {
            return (first, index + 1, nil)
        }

        var word = ""
        var cursor = index
        while cursor < characters.count, characters[cursor].isLetter, word.count < 32 {
            word.append(characters[cursor])
            cursor += 1
        }

        var parameter = ""
        if cursor < characters.count, characters[cursor] == "-" {
            parameter.append("-")
            cursor += 1
        }
        while cursor < characters.count, characters[cursor].isNumber, parameter.count < 12 {
            parameter.append(characters[cursor])
            cursor += 1
        }

        // A single space after a control word delimits it and is not text.
        if cursor < characters.count, characters[cursor] == " " { cursor += 1 }

        switch word {
        case "u":
            guard var value = Int(parameter) else { return (nil, cursor, nil) }
            // RTF writes code points as signed 16 bit, so anything above U+7FFF arrives
            // negative.
            if value < 0 { value += 65_536 }
            let scalar = UnicodeScalar(value).map(Character.init)
            // Skip the substitution characters that follow, which are there for readers
            // that cannot handle the code point itself.
            return (scalar, cursor + max(0, unicodeSkip), nil)

        case "uc":
            return (nil, cursor, Int(parameter) ?? 1)

        case "par", "line":
            return ("\n", cursor, nil)

        case "tab":
            return ("\t", cursor, nil)

        default:
            return (nil, cursor, nil)
        }
    }

    /// The handful of Windows-1252 bytes that differ from Latin-1, plus the direct mapping
    /// for everything else. Present because `\'92`, a curly apostrophe, appears in the
    /// prose of a real export, and `\'e9` appears in any account name with an accent.
    private static func codePage1252(_ byte: UInt8) -> Character? {
        let high: [UInt8: UnicodeScalar] = [
            0x80: "\u{20AC}", 0x82: "\u{201A}", 0x83: "\u{0192}", 0x84: "\u{201E}",
            0x85: "\u{2026}", 0x86: "\u{2020}", 0x87: "\u{2021}", 0x88: "\u{02C6}",
            0x89: "\u{2030}", 0x8A: "\u{0160}", 0x8B: "\u{2039}", 0x8C: "\u{0152}",
            0x8E: "\u{017D}", 0x91: "\u{2018}", 0x92: "\u{2019}", 0x93: "\u{201C}",
            0x94: "\u{201D}", 0x95: "\u{2022}", 0x96: "\u{2013}", 0x97: "\u{2014}",
            0x98: "\u{02DC}", 0x99: "\u{2122}", 0x9A: "\u{0161}", 0x9B: "\u{203A}",
            0x9C: "\u{0153}", 0x9E: "\u{017E}", 0x9F: "\u{0178}",
        ]

        if let scalar = high[byte] { return Character(scalar) }
        return Character(UnicodeScalar(byte))
    }
}
