import Foundation

/// Whether bytes are meant to be JSON, decided before any reader is chosen.
///
/// ## Why this is in the core
///
/// It was a private method on a view model, where no test could reach it, and it had two defects
/// that a reviewer had to find by reading. That is the pattern gate A4 kept producing, so the
/// decision moved and the app calls it.
///
/// ## What it got wrong, twice
///
/// **A byte order mark hid the file.** A UTF-8 BOM begins `EF BB BF`, which is neither whitespace
/// nor `{`, so a BOM-prefixed OpenFactor archive was routed to the labelled-text reader and its
/// holder was told no accounts were found, never asked for a passphrase. The layer below strips
/// exactly that mark, deliberately, because recovery files get mangled in transit. **A sniff that
/// is stricter than the reader it guards is worse than no sniff**, because it decides which reader
/// never gets a chance to be lenient.
///
/// **Whitespace walked an RTF file past the guard.** The check for `{\rtf` ran before whitespace
/// was skipped, so a single newline in front of it defeated the check and the file was handed to a
/// JSON parser.
public enum JSONSniff {

    /// The bytes with a leading byte order mark removed, or empty when this is not JSON.
    ///
    /// The stripped bytes are returned rather than a yes or no, because `JSONSerialization`
    /// refuses a leading mark too: recognising the file and then handing the untouched bytes to
    /// the parser would trade one silent failure for another.
    public static func body(of data: Data) -> Data {
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) { body = body.dropFirst(3) }

        // Order matters, and this is the order: drop the mark, drop the whitespace, then decide.
        let head = body.prefix(512).drop(while: \.isASCIIWhitespaceByte)

        if head.starts(with: Array("{\\rtf".utf8)) { return Data() }
        guard head.first == UInt8(ascii: "{") else { return Data() }

        return Data(body)
    }
}

extension UInt8 {
    /// Space, tab, newline, carriage return, form feed and vertical tab.
    var isASCIIWhitespaceByte: Bool {
        self == 0x20 || (0x09...0x0D).contains(self)
    }
}
