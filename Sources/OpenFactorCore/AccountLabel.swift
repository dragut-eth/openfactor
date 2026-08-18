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
    public static func clamped(_ text: String) -> String {
        text.count <= maximumCharacters ? text : String(text.prefix(maximumCharacters))
    }

    /// The optional form, for an issuer, which a URI may legitimately omit.
    public static func clamped(_ text: String?) -> String? {
        text.map(clamped)
    }
}
