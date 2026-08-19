import Foundation

/// The bound on the two pieces of free text an account carries, its issuer and its name.
///
/// ## Why a bound exists at all
///
/// There was none, at any layer: not the text fields, not `AccountMetadata`, not the record
/// format, not the Keychain store. A label grew a stored record byte for byte, which was
/// measured rather than assumed: a hundred thousand character issuer produces about a
/// hundred kilobytes of metadata, sealed and written as a single Keychain item, and offered
/// to iCloud Keychain if sync is on.
///
/// **The interesting path is not somebody typing.** Typing a hundred thousand characters
/// takes deliberate effort, and the worst case is a paste accident. The path that matters is
/// an imported `otpauth-migration` payload or a restored backup, where the labels arrive from
/// a file rather than from a person and are bounded today only by the eight megabyte limit on
/// the file itself. That is not a compromise of anything, because nothing here is executed or
/// trusted, but it is a way to write junk into somebody's Keychain and their iCloud sync, and
/// the fix is one number.
///
/// So the bound lives here rather than in the text fields, and every route into storage
/// passes through it: manual entry, a scanned code, a transfer from another app, a restored
/// backup, and a rename.
///
/// ## The number
///
/// Sixty-four characters, which is far past any real service name. `GitHub` is six,
/// `AWS Production` is fourteen, and the longest issuer seen in any test fixture in this
/// repository is well under thirty. The point of the number is to be unreachable in normal
/// use while making the pathological case bounded, so it is generous on purpose.
///
/// ## Characters, not bytes
///
/// Counted in Swift `Character`s, which are grapheme clusters, so a label is never cut
/// through the middle of an emoji or a combining mark. That costs a little precision about
/// the eventual byte size, which is the right trade: the point is to bound the thing, and
/// sixty-four of even the most expensive graphemes is still trivially small.
public enum AccountLabel {

    /// The most characters an issuer or a name may carry into storage.
    public static let maximumCharacters = 64

    /// Cuts a label to the bound, leaving anything already within it untouched.
    ///
    /// **Truncates rather than rejects**, and that is deliberate for the import path. A
    /// restore that refused the whole file because one account had a long name would cost
    /// somebody every account in it, to protect against what is at worst an untidy label.
    /// A truncated label still names a working account.
    /// The most bytes a label may occupy once encoded, whatever it looks like on screen.
    ///
    /// **A character bound is not a storage bound**, which gate A4 found by writing one down: a
    /// Swift `Character` is an extended grapheme cluster, and a cluster may carry any number of
    /// combining marks. `"a"` followed by fifty thousand combining acute accents is **one**
    /// character and a hundred kilobytes, so the sixty four above passed it through untouched.
    /// A hostile import could plant an account whose metadata is megabytes, sealed, padded, and
    /// offered to iCloud in a single Keychain item, and recognisable ever after by its length.
    ///
    /// Four kilobytes, chosen by measuring rather than guessing. The most expensive graphemes a
    /// person actually types are joined emoji: a four person family is 25 bytes and a Scotland
    /// flag with its tag sequence is 28, so sixty four of the worst of them is 1,792 bytes. Four
    /// kilobytes clears that by more than double and still refuses the hundred kilobyte label
    /// above by a factor of twenty five.
    ///
    /// The first value written here was 1,024, which is below what sixty four family emoji
    /// occupy. The existing test for grapheme counting failed immediately, which is what that
    /// test is for.
    public static let maximumBytes = 4096

    public static func clamped(_ text: String) -> String {
        let byCharacters =
            text.count <= maximumCharacters ? text : String(text.prefix(maximumCharacters))
        guard byCharacters.utf8.count > maximumBytes else { return byCharacters }

        // Whole characters first, so an ordinary label is never cut through the middle of one.
        var kept = ""
        var bytes = 0
        for character in byCharacters {
            let size = String(character).utf8.count
            if bytes + size > maximumBytes { break }
            kept.append(character)
            bytes += size
        }

        // One grapheme larger than the entire budget, which is the hostile case rather than any
        // real one. Scalars are kept instead, so the result is still well formed text and still
        // bounded. What it renders as is not this type's problem: it is a label somebody built
        // to be a storage attack.
        if kept.isEmpty {
            for scalar in byCharacters.unicodeScalars {
                let size = String(scalar).utf8.count
                if bytes + size > maximumBytes { break }
                kept.unicodeScalars.append(scalar)
                bytes += size
            }
        }

        return kept
    }

    /// The optional form, for an issuer, which a URI may legitimately omit.
    public static func clamped(_ text: String?) -> String? {
        text.map(clamped)
    }
}
