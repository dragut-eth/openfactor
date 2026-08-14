import Foundation

/// How a code is shown, and how it is read aloud.
///
/// Presentation only. The core returns the digits, and what happens to them visually is
/// none of its business.
enum CodeFormatting {

    /// Splits a code into groups for transcription.
    ///
    /// People copying a code by hand hold it in memory across the gap from screen to
    /// keyboard, and three or four digits survive that trip where six do not. Six splits
    /// evenly into two threes and eight into two fours. Seven is left alone, because an
    /// uneven split is worse than none.
    static func grouped(_ code: String) -> String {
        switch code.count {
        case 6: split(code, every: 3)
        case 8: split(code, every: 4)
        default: code
        }
    }

    /// What VoiceOver says.
    ///
    /// Digits separated by spaces, so they are read one at a time. Without this the
    /// system reads `751702` as "seven hundred fifty one thousand, seven hundred two",
    /// which is useless to someone typing it into a login form.
    static func spokenDigits(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }

    private static func split(_ code: String, every size: Int) -> String {
        var groups: [String] = []
        var index = code.startIndex

        while index < code.endIndex {
            let end = code.index(index, offsetBy: size, limitedBy: code.endIndex) ?? code.endIndex
            groups.append(String(code[index..<end]))
            index = end
        }

        // A thin space, not a regular one. Wide enough to group, narrow enough that the
        // code still reads as one number rather than two.
        return groups.joined(separator: "\u{2009}")
    }
}
