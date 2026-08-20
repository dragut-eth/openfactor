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

    /// Which request is being asked about, and what may be done about it.
    ///
    /// **The message-handling rules moved into it, and the cadence stayed here.** Gate A4 found
    /// five defects in those rules across three rounds, each one by a person reading this file,
    /// because nothing else could reach them.
    ///
    /// What is left here: the session, the alert, the key file, the sending, **and two decisions**.
    /// This file decides when to arm the expiry timer, on `answer == .asking`, and deleting that
    /// line would leave every desk test green while auto-clearing quietly died. It also decides
    /// that a refusal it cannot name is not sent at all.
    ///
    /// The sentence that used to stand here claimed every rule had moved. Round four rejected it,
    /// `ProvisioningDesk`'s header was corrected, **and this copy was left behind** — which round
    /// five found, in two returns, in the file the extraction was meant to empty.
    private var desk = ProvisioningDesk()

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
    ///
    /// The value lives on `ProvisioningDesk`, which is what enforces it. This is here so nothing
    /// that referred to it has to learn a new name.
    static let consentWindow = ProvisioningDesk.consentWindow

    func approve() {
        defer { isAsking = desk.isAsking }

        // **The desk is asked first, and a key is read only when there is something to release.**
        // This used to load the key before asking, so an expired request, an empty desk, or a
        // second tap on a lingering alert all read it for nothing.
        switch desk.approve() {
        case let .release(request):
            // **A phone that cannot read its own key refuses, rather than going quiet.** The
            // silence was faithful to the version before the extraction and a review found it
            // sitting three lines from the expired path, which answers the identical situation by
            // telling the watch. Two answers to one question, in the file no test can reach.
            guard let key = (try? keys.load()) ?? nil,
                let response = try? WatchProvisioning.respond(to: request, with: key)
            else {
                return refuse(naming: request.requestNonce)
            }

            WCSession.default.sendMessage(
                [WatchProvisioning.MessageKey.response: response], replyHandler: nil,
                errorHandler: nil)

        case let .refuse(nonce):
            refuse(naming: nonce)

        case .nothing:
            break
        }
    }

    func decline() {
        defer { isAsking = desk.isAsking }

        // **A refusal this phone cannot name is not sent at all.** `decline()` used to send
        // whatever the desk gave it, including nothing, so a build that binds every refusal could
        // emit an unbound one: the expiry timer and a tap on Not now race, the timer wins and
        // clears the desk, and the queued tap then sends a decline naming no request. The watch
        // honours a nonce-less decline **because it can only have come from a phone built before
        // the field existed**, so that stray ends whatever attempt the watch is holding. That is
        // the exact class the nonce was added to close. Found in round four.
        guard let nonce = desk.decline() else { return }
        refuse(naming: nonce)
    }

    /// The one place a refusal is sent, so the three callers cannot answer differently.
    ///
    /// **The refusal names the request it refuses.** Every other message in this protocol is bound
    /// to its attempt; this was the one that carried nothing, so a refusal of an abandoned attempt
    /// ended the one the watch was still waiting on.
    private func refuse(naming nonce: Data) {
        WCSession.default.sendMessage(
            [
                WatchProvisioning.MessageKey.status: WatchProvisioning.Answer.declined.rawValue,
                WatchProvisioning.MessageKey.nonce: nonce,
            ],
            replyHandler: nil, errorHandler: nil)
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
        // **The vault question is a closure, so the key is read only if the desk gets that far.**
        // Building this out of a `Bool` read the key before the request had been parsed and before
        // the frontmost check, which a review found restored an ordering this project had already
        // fixed once.
        let conditions = ProvisioningDesk.Conditions(
            isFrontmost: UIApplication.shared.applicationState == .active,
            hasVault: { [keys] in ((try? keys.load()) ?? nil) != nil })

        let answer = desk.received(request, when: conditions)
        isAsking = desk.isAsking

        if answer == .asking, let nonce = desk.pendingNonce { expireConsent(nonce) }
        return answer
    }

    /// Takes the question down when nobody has answered it in time.
    ///
    /// **The window used to be checked only when the button was pressed.** Two reviews said the
    /// same thing about that: the alert can sit on screen for hours, and the first the person
    /// hears of the deadline is a tap that refuses.
    ///
    /// Whether the deadline has actually passed for the request still on the desk is the desk's
    /// decision, not this timer's. All this does is wake up and ask.
    private func expireConsent(_ nonce: Data) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(ProvisioningDesk.consentWindow))
            guard let self else { return }
            guard let expired = self.desk.expire(nonce) else { return }

            self.isAsking = self.desk.isAsking
            self.refuse(naming: expired)
        }
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

        // **A reply is bound to its request by the channel, not by a nonce.** Round five found a
        // malformed request being answered `declined` with no nonce, which two documents said
        // could only come from a build too old to send one. The documents were wrong rather than
        // the code: this answer travels back through the reply handler of the very message that
        // asked, so the watch already knows which request it belongs to, and the nonce that binds
        // a *standalone* refusal has nothing to add here. There is also no nonce to send, because
        // a request that did not parse has none.
        //
        // `docs/VAULT.md` and `SECURITY.md` now draw that distinction rather than claiming every
        // decline carries a nonce.
        Task { @MainActor in
            replyHandler(
                    [WatchProvisioning.MessageKey.status: self.answer(to: request).rawValue])
        }
    }
}
