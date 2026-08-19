import Foundation
import OpenFactorCore
import SwiftUI
import UIKit
import WatchConnectivity

/// The phone's half of watch provisioning: answering a watch that is asking for the vault key.
///
/// **This is the only path by which the vault key leaves a device**, and the only reason the
/// phone talks to the watch at all. Accounts reach the watch as ciphertext through iCloud
/// Keychain and need nothing from here.
///
/// ## Why it answers twice
///
/// A reply handler cannot be held open while a person decides. So the first answer is only a
/// status, the phone puts the question on screen, and the sealed key travels in a second message
/// sent after the answer. That also gives the watch something honest to show while it waits.
///
/// ## The interactive channel only
///
/// `sendMessage` and nothing else. The queued transfer modes persist their payload to disk while
/// they wait for the other side, which is exactly what must never happen to key material.
/// `docs/VAULT.md` states this as an invariant.
@MainActor
@Observable
final class WatchKeyProvider: NSObject {

    /// Set when a watch has asked and the person has not answered yet. The app puts an alert up
    /// on whatever is on screen.
    private(set) var isAsking = false

    /// The request the alert on screen is asking about, parsed before it was ever shown.
    ///
    /// **Never overwritten while it is set.** A second request used to replace it silently, so a
    /// tap that had been offered for one watch key sealed the vault to whichever key arrived
    /// last. Under WatchConnectivity's routing exclusivity both come from the genuine watch, so
    /// no exploit follows today, but `SECURITY.md` states that exclusivity is load bearing and
    /// undocumented by Apple, and this is exactly the defect that would turn a weakening of it
    /// into key exfiltration. Found by an independent review.
    private var pendingRequest: WatchProvisioning.ValidatedRequest?

    private let keys: VaultKeyStore

    init(keys: VaultKeyStore = VaultKeyStore()) {
        self.keys = keys
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Answering

    /// Seals the vault key to the watch that asked, and sends it.
    ///
    /// **Only ever called from the person tapping the affirmative button.** Nothing else may call
    /// it, which is why it is not a general purpose method taking a request.
    /// How long a request stays answerable.
    ///
    /// **A consent prompt whose premise has expired is a weaker gate than the design claims.**
    /// A request arriving while App Lock is up is accepted and the alert suppressed until
    /// unlock, with nothing bounding how much later that is. Gate A4 found that somebody could
    /// be shown "Your Apple Watch is asking for the key to your accounts" hours after it stopped
    /// asking, and a tap would release the sealed key. The human tap is the one defence this
    /// design kept when the comparison string was removed, so it should be asked about something
    /// that is still true.
    ///
    /// Two minutes is comfortably longer than the watch's own retry cycle, so a live exchange is
    /// never cut off, and short enough that the question and the answer belong to each other.
    static let consentWindow: TimeInterval = 120

    func approve() {
        defer {
            pendingRequest = nil
            isAsking = false
        }

        guard let request = pendingRequest, let key = (try? keys.load()) ?? nil else { return }

        // **Measured on a clock that only goes forward.** The first version used `Date()`, and
        // all three round-two reviews found the same hole: a backward jump makes the elapsed
        // time negative, negative is less than the window, and the request stays answerable
        // indefinitely, which is the defect the window was added to close. `AppLockEngine`
        // already refuses to reason about a backward clock three files away, and this is the
        // same input.
        //
        // `ContinuousClock` rather than `SuspendingClock`, because a phone that sleeps for an
        // hour with an alert up has still let an hour pass for the person looking at it.
        //
        // **Expiry is a refusal, not silence.** The first version returned, which left the alert
        // on screen and the request in memory: the owner taps Approve, nothing happens, and
        // nothing tells them why. One review asked for the request and the alert to be cleared
        // when the deadline passes. Declining does that and says so on the wire, so the watch
        // stops waiting now instead of at its own timeout.
        guard request.age() <= Self.consentWindow else {
            decline()
            return
        }
        guard let response = try? WatchProvisioning.respond(to: request, with: key) else { return }

        WCSession.default.sendMessage(
            [WatchProvisioning.MessageKey.response: response], replyHandler: nil,
            errorHandler: nil)
    }

    func decline() {
        defer {
            pendingRequest = nil
            isAsking = false
        }

        // **The refusal names the request it refuses.** Without the nonce, a decline of an
        // attempt the watch has already abandoned ended the one it was still waiting on, and the
        // approval that followed had nothing left to open it with. Every other message here is
        // bound to its attempt; this was the one that carried nothing.
        var message: [String: Any] = [
            WatchProvisioning.MessageKey.status: WatchProvisioning.Answer.declined.rawValue
        ]
        if let pendingRequest {
            message[WatchProvisioning.MessageKey.nonce] = pendingRequest.requestNonce
        }

        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    /// Decides what to answer, and remembers the request if the answer is a question.
    ///
    /// The frontmost check is doing real work rather than being polite. The key file is
    /// `.complete` protected, so a phone woken in the background cannot read it; and nobody is
    /// looking at a screen, so nobody can agree to anything.
    /// **Parsed before anything else happens.** Rubbish is refused here rather than after the
    /// owner has been shown an alert and tapped it, which is what used to happen: the phone read
    /// its vault key, raised the question, and only found the request malformed afterwards, then
    /// sent nothing and left the watch waiting on a spinner.
    ///
    /// The order of the remaining checks is deliberate. The frontmost check does real work rather
    /// than being polite: the key file is `.complete` protected, so a phone woken in the
    /// background cannot read it, and nobody is looking at a screen to agree to anything.
    private func answer(to request: Data) -> WatchProvisioning.Answer {
        guard let validated = try? WatchProvisioning.validate(request) else { return .declined }
        guard UIApplication.shared.applicationState == .active else { return .needsApp }
        guard ((try? keys.load()) ?? nil) != nil else { return .noVault }

        // A question already on screen is not replaced by a later one, and the watch is told
        // that rather than being told it is being asked about. Answering `.asking` for a request
        // this phone is about to drop is the lie round one found: it left the watch waiting for
        // a message that could never arrive.
        guard pendingRequest == nil else { return .busy }

        pendingRequest = validated
        isAsking = true
        return .asking
    }
}

extension WatchKeyProvider: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(
        _ session: WCSession, didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let request = message[WatchProvisioning.MessageKey.request] as? Data else {
            replyHandler([:])
            return
        }

        Task { @MainActor in
            replyHandler(
                    [WatchProvisioning.MessageKey.status: self.answer(to: request).rawValue])
        }
    }
}
