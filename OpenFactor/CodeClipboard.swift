import UIKit
import UniformTypeIdentifiers

/// Putting a code on the clipboard, which is the one place this app deliberately hands
/// secret-adjacent material to the rest of the system.
///
/// The clipboard is not private. Any app the user opens can read it, and by default the
/// contents travel to their Mac and iPad through Universal Clipboard. A six digit code is
/// short lived and single use, so this is a smaller exposure than a password, but it is
/// still the widest surface in the app and the two options below are what narrow it.
enum CodeClipboard {

    /// Copies a code, local to this device, expiring at a given moment.
    ///
    /// - Parameter expiry: when the system should clear it. Callers pass the moment the
    ///   code itself stops working, so the clipboard entry cannot outlive its own
    ///   usefulness. There is no point holding a code that no service will accept.
    static func copy(_ code: String, expiring expiry: Date) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: code]],
            options: [
                // Stays on this device. Without it the code appears in the clipboard of
                // every Mac and iPad signed into the same Apple Account, which is a
                // sync of secret material that nobody asked for.
                .localOnly: true,

                // The system clears it at this point even if nothing else is copied.
                .expirationDate: expiry,
            ]
        )
    }

    /// Copies a backup passphrase, on its way to a password manager.
    ///
    /// **A different thing from copying a code, which is why it is a different function.** A
    /// code is short lived and single use; a passphrase opens an archive holding every
    /// secret its owner has, and it does not expire on its own. The same two narrowings
    /// apply and matter more: local to this device, and cleared by the system shortly.
    ///
    /// Two minutes is long enough to switch apps and paste, short enough that it is gone
    /// before the phone is put down. The alternative, not offering this at all, would push
    /// people to retype twenty four characters by hand into the one field where a typo is
    /// unrecoverable, or to screenshot it, which is worse than the clipboard in every way.
    static func copy(passphrase: String) {
        copy(passphrase, expiring: Date().addingTimeInterval(120))
    }
}
