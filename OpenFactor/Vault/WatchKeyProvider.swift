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
    /// **Every rule that used to live in this file is in there now**, in the core, where the test
    /// suite can reach it. Gate A4 found five defects in those rules across three rounds, each
    /// one by a person reading this file, because nothing else could. What is left here is the
    /// session, the alert, the key file and the sending.
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

        // The key is read before the decision is asked for, because a phone that cannot read its
        // own key has nothing to release whatever the desk says.
        guard let key = (try? keys.load()) ?? nil else {
            _ = desk.decline()
            return
        }

        switch desk.approve() {
        case let .release(request):
            guard let response = try? WatchProvisioning.respond(to: request, with: key) else {
                return
            }
            WCSession.default.sendMessage(
                [WatchProvisioning.MessageKey.response: response], replyHandler: nil,
                errorHandler: nil)

        case let .refuse(nonce):
            send(declineEchoing: nonce)

        case .nothing:
            break
        }
    }

    func decline() {
        defer { isAsking = desk.isAsking }
        send(declineEchoing: desk.decline())
    }

    /// Sends the refusal, naming the request it refuses when there is one to name.
    private func send(declineEchoing nonce: Data?) {
        var message: [String: Any] = [
            WatchProvisioning.MessageKey.status: WatchProvisioning.Answer.declined.rawValue
        ]
        if let nonce { message[WatchProvisioning.MessageKey.nonce] = nonce }

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
        let conditions = ProvisioningDesk.Conditions(
            isFrontmost: UIApplication.shared.applicationState == .active,
            hasVault: ((try? keys.load()) ?? nil) != nil)

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
            self.send(declineEchoing: expired)
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

        Task { @MainActor in
            replyHandler(
                    [WatchProvisioning.MessageKey.status: self.answer(to: request).rawValue])
        }
    }
}
