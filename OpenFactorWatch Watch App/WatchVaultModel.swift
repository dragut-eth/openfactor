import Foundation
import OpenFactorCore
import SwiftUI
import WatchConnectivity

/// The watch's half of provisioning: asking its phone for the key, once.
///
/// **Provisioning needs the phone once. Operation never does.** After this the watch reads
/// accounts from iCloud Keychain as ciphertext and generates codes with the phone off, absent,
/// or out of range.
///
/// Every failure here is somebody else's state rather than a fault: the phone is in another
/// room, or locked, or has not been set up itself. So each one names what to go and do, and
/// none of them says "error".
@MainActor
@Observable
final class WatchVaultModel: NSObject {

    enum Stage: Equatable {
        /// Before anything has been read.
        case checking
        /// This watch has the key. The list can be drawn.
        case ready
        /// Nothing asked yet, or the wearer came back to try again.
        case needsPhone
        /// A request is out and the phone has not answered.
        case waiting
        /// The phone is not in range, or the app on it is not running.
        case unreachable
        /// The phone answered, but nobody is looking at it and its key file is locked.
        case openTheApp
        /// The phone has no vault of its own yet.
        case phoneNotSetUp
        /// The person said no, or something did not open.
        case notSetUp
    }

    private(set) var stage: Stage = .checking

    private let keys: VaultKeyStore

    /// Held between the two messages, and only then. The private key inside it is used once.
    private var attempt: WatchProvisioning.Attempt?

    init(keys: VaultKeyStore = VaultKeyStore()) {
        self.keys = keys
        super.init()
    }

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
        refreshAndAsk()
    }

    /// Re-reads whether this watch already has a key and, if it does not, asks.
    ///
    /// **Asking is automatic rather than a button.** Every message this screen can show ends by
    /// telling somebody to go and do something on their phone, and the natural next move is to
    /// raise the wrist again. Making that work is worth more than a tap that says "Try again"
    /// for a second time. The button stays for the case where nothing changed and somebody
    /// wants to poke it.
    func refreshAndAsk() {
        if ((try? keys.load()) ?? nil) != nil {
            stage = .ready
            return
        }

        // Not while a request is already out, or raising the wrist twice would send two.
        guard stage != .waiting else { return }
        ask()
    }

    // MARK: - Asking

    func ask() {
        guard stage != .ready else { return }

        let attempt = WatchProvisioning.Attempt()
        self.attempt = attempt
        stage = .waiting

        WCSession.default.sendMessage(["request": attempt.request]) { reply in
            Task { @MainActor in self.phoneAnswered(reply) }
        } errorHandler: { _ in
            // Not reachable, not paired, or the counterpart is not running. All of them mean
            // the same thing to somebody standing there: the phone is not answering.
            Task { @MainActor in self.stage = .unreachable }
        }
    }

    private func phoneAnswered(_ reply: [String: Any]) {
        switch reply["status"] as? String {
        case "asking": stage = .waiting
        case "needsApp": stage = .openTheApp
        case "noVault": stage = .phoneNotSetUp
        default: stage = .notSetUp
        }
    }

    /// The second message, carrying the sealed key or a refusal.
    ///
    /// **Every check lives in `WatchProvisioning.Attempt.open`**, including that the nonce is the
    /// one this attempt just sent, so a watch cannot install a key from a message it has not
    /// fully verified.
    private func phoneSent(_ message: [String: Any]) {
        if let response = message["response"] as? Data, let attempt {
            do {
                try keys.install(try attempt.open(response))
                self.attempt = nil
                stage = .ready
            } catch {
                self.attempt = nil
                stage = .notSetUp
            }
            return
        }

        if message["status"] as? String == "declined" {
            attempt = nil
            stage = .notSetUp
        }
    }
}

extension WatchVaultModel: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.phoneSent(message) }
    }
}
