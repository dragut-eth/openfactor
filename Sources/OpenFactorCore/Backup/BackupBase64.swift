import Foundation

/// Base64 for the archive container, strict on the way out and lenient on the way in.
///
/// `docs/BACKUP_FORMAT.md` requires writers to emit standard RFC 4648 section 4 base64 with
/// padding, and requires readers to accept the URL safe alphabet, missing padding and
/// embedded whitespace. The asymmetry is deliberate and the reasoning is worth keeping next
/// to the code: none of those variations can change the decoded bytes, and this is the
/// recovery path. An archive that refuses to open because a mail client wrapped a line, or
/// because something along the way swapped `+` for `-`, has failed at the one job it has.
///
/// Leniency stops exactly there. A character that is not in either alphabet is an error,
/// because dropping it would decode different bytes than the file contains.
enum BackupBase64 {

    /// Standard alphabet, padded. What this app writes.
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
    }

    /// Decodes standard or URL safe base64, padded or not, whitespace or not.
    ///
    /// Foundation's `ignoreUnknownCharacters` is not enough on its own: it would silently
    /// drop the `-` and `_` of the URL safe alphabet rather than translating them, which is
    /// precisely the case where quietly ignoring a character decodes the wrong bytes. So the
    /// translation happens first and the decode is then strict.
    static func decode(_ text: String) -> Data? {
        var characters = ""
        characters.reserveCapacity(text.count)

        for character in text {
            switch character {
            case "-": characters.append("+")
            case "_": characters.append("/")
            case "\n", "\r", "\t", " ": continue
            default: characters.append(character)
            }
        }

        // Padding is restored rather than ignored, because the remainder tells the decoder
        // how many bits of the final group to keep.
        let remainder = characters.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 {
            characters.append(String(repeating: "=", count: 4 - remainder))
        }

        return Data(base64Encoded: characters)
    }
}
