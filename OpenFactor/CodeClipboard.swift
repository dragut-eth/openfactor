import UIKit
import UniformTypeIdentifiers

/// Putting a code or a passphrase on the clipboard, which is the one place this app
/// deliberately hands secret-adjacent material to the rest of the system.
///
/// The clipboard is not private. Any app the user opens can read it, and with Universal
/// Clipboard turned on the contents can travel to their Mac and iPad. Everything here is
/// about narrowing that, and the two kinds of secret are narrowed differently on purpose.
enum CodeClipboard {

    /// Copies a code, expiring at a given moment.
    ///
    /// - Parameter expiry: when the system should clear it. Callers pass the moment the
    ///   code itself stops working, so the clipboard entry cannot outlive its own
    ///   usefulness. There is no point holding a code that no service will accept.
    ///
    /// ## Why this one is allowed to reach other devices
    ///
    /// It was `localOnly` at first, and that was reconsidered with Xavier after the
    /// behaviour was measured on real devices rather than argued about.
    ///
    /// **The consistency argument decided it.** This project already accepts exactly this
    /// bargain elsewhere: iCloud Keychain sync is Apple's transport, off by default, and
    /// enabled by the person who wants it, and `SECURITY.md` says so plainly rather than
    /// forbidding it. Universal Clipboard is the same shape. Forbidding one while
    /// documenting the other as acceptable is an inconsistency this project could not
    /// defend, and it overrides a choice its owner already made at the system level.
    ///
    /// **It also read as a fault rather than a protection.** Signing in on a Mac with the
    /// code on a phone is the single most common thing anybody does with an authenticator.
    /// Every comparable app lets that paste work, so a copy that silently refused to arrive
    /// looked like OpenFactor being broken, which is how it was first reported here.
    ///
    /// **The exposure that follows is named rather than waved away**, and it is not Apple's
    /// transit. macOS shows no paste notification and lets any app read the clipboard
    /// silently, and clipboard managers are common and keep history on disk. So a code can
    /// land in a searchable plaintext store and stay there after `expiry` has cleared it
    /// here, because whatever read it in the first second already has its own copy. That is
    /// an accepted cost for a six digit string that stops working in seconds and that the
    /// person is typing into that same Mac anyway. It would not be acceptable for a
    /// passphrase, which is why the function below is different.
    static func copy(_ code: String, expiring expiry: Date) {
        write(code, expiring: expiry, localOnly: rules(for: .code).localOnly)
    }

    /// What each kind of copied text is allowed to do, as a value rather than as an argument
    /// spelled out at two call sites.
    ///
    /// **Extracted because a review found the rule pinned by no test at all.** It is one boolean
    /// and it decides whether a backup passphrase may leave the device, so a future edit that
    /// makes the two calls consistent, which is the tidy-looking change, would hand somebody's
    /// recovery credential to Universal Clipboard. The rule is now something a test can hold.
    enum Kind: Equatable {
        /// Six digits that stop working in seconds.
        case code
        /// A recovery credential that never expires by itself.
        case passphrase
    }

    static func rules(for kind: Kind) -> (localOnly: Bool, lifetime: TimeInterval) {
        switch kind {
        // Allowed to reach a Mac, deliberately and after measuring it: the argument is in the
        // comment above `copy(_:expiring:)`.
        case .code: return (localOnly: false, lifetime: 30)
        // **Never leaves the device.** The expiry below does not travel, as measured, so on any
        // other device this would sit in the clipboard until something replaced it.
        case .passphrase: return (localOnly: true, lifetime: 120)
        }
    }

    /// Copies a backup passphrase, on its way to a password manager.
    ///
    /// **A different thing from copying a code, which is why it is a different function and
    /// keeps the stricter rule.** A code is six digits that stop working in seconds. A
    /// passphrase opens an archive holding every secret its owner has, it never expires on
    /// its own, and a clipboard manager that captured it would keep it in plaintext
    /// indefinitely. So this one stays on the device it was copied on.
    ///
    /// Two minutes is long enough to switch apps and paste, short enough that it is gone
    /// before the phone is put down. The alternative, not offering this at all, would push
    /// people to retype twenty four characters by hand into the one field where a typo is
    /// unrecoverable, or to screenshot it, which is worse than the clipboard in every way.
    static func copy(passphrase: String) {
        let rules = rules(for: .passphrase)
        write(
            passphrase, expiring: Date().addingTimeInterval(rules.lifetime),
            localOnly: rules.localOnly)
    }

    /// The one place either kind is actually written, so the two rules sit side by side and
    /// a future caller has to choose between them rather than inherit one by accident.
    private static func write(_ text: String, expiring expiry: Date, localOnly: Bool) {
        var options: [UIPasteboard.OptionsKey: Any] = [
            // The system clears it at this point even if nothing else is copied.
            //
            // **Measured: this applies to the originating device only.** A code that reached a
            // Mac through Universal Clipboard stays on that Mac's clipboard until something
            // replaces it. That is why the passphrase rule above is load bearing rather than
            // tidy: an expiry that does not travel is no protection at all for a secret that
            // never expires by itself.
            .expirationDate: expiry
        ]

        if localOnly {
            options[.localOnly] = true
        }

        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]], options: options)
    }
}
