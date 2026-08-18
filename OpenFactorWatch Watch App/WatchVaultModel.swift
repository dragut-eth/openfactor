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
        /// A request is out and the phone has not answered.
        case waiting
        /// The phone did not answer, or answered from the background where it can do nothing.
        ///
        /// **One state rather than three**, because the remedy is identical and naming the cause
        /// sent people to check the wrong thing. "Not reachable" also fires when the phone is on
        /// the table with OpenFactor closed, which reads as a distance problem and is not one.
        case needsPhoneApp
        /// The phone has no vault of its own yet.
        case phoneNotSetUp
        /// The person said no, or something did not open.
        case notSetUp
        /// This watch has a key, asked again, and still cannot read anything.
        case cannotRead
    }

    private(set) var stage: Stage = .checking

    private let keys: VaultKeyStore

    /// Held between the two messages, and only then. The private key inside it is used once.
    private var attempt: WatchProvisioning.Attempt?

    /// The store, so the model can tell a key that works from one that merely exists.
    private var store: (any SecretStore)?

    /// Set only once a **fresh key has actually been installed and still opens nothing**.
    ///
    /// It used to be set at the moment of asking, which was wrong in a way that showed up
    /// immediately on a wrist: the first attempt fired, did not complete because nobody was
    /// looking at the phone, and the next check found the flag already set and declared that the
    /// records needed a newer version of OpenFactor. That is a frightening sentence and it was
    /// not true. Asking is not evidence; a key that arrived and did not help is.
    private var hasReplacedStaleKey = false

    init(keys: VaultKeyStore = VaultKeyStore()) {
        self.keys = keys
        super.init()
    }

    func activate(in store: any SecretStore) {
        self.store = store
        WCSession.default.delegate = self
        WCSession.default.activate()
        refreshAndAsk()
    }

    /// Re-reads whether this watch can actually read its accounts, and asks if it cannot.
    ///
    /// **Having a key is not the same as having the right one**, and the difference is a dead
    /// end that shipped in the first version of this screen. Replace the vault on the phone,
    /// which is what "forget everything" and a fresh setup do, and this watch keeps the old key
    /// while every record that arrives is sealed under the new one. The gate saw a key, said
    /// ready, and handed the list a shelf of accounts it could not open. The list then reported
    /// zero accounts, correctly and uselessly, with nothing offering a way back.
    ///
    /// **Asking is automatic rather than a button.** Every message this screen can show ends by
    /// telling somebody to go and do something on their phone, and the natural next move is to
    /// raise the wrist again. The button stays for when nothing changed and somebody wants to
    /// poke it.
    func refreshAndAsk() {
        if ((try? keys.load()) ?? nil) != nil {
            guard keyOpensNothing else {
                stage = .ready
                return
            }

            // A fresh key was installed and these records still will not open, so a newer format
            // wrote them rather than a different key having sealed them. Asking again would
            // fetch the same key and produce the same result, forever.
            guard !hasReplacedStaleKey else {
                stage = .cannotRead
                return
            }
        }

        // Not while a request is already out, or raising the wrist twice would send two.
        guard stage != .waiting else { return }
        ask()
    }

    /// The rule itself lives in `StoredRecords.suggestsAWrongKey`, where it can be tested. A
    /// decision about whether a device throws its key away does not belong in a view model that
    /// no test can reach.
    private var keyOpensNothing: Bool {
        guard let store, let records = try? store.records() else { return false }
        return records.suggestsAWrongKey
    }

    // MARK: - Asking

    func ask() {
        guard stage != .ready else { return }

        let attempt = WatchProvisioning.Attempt()
        self.attempt = attempt
        stage = .waiting

        // A spinner with nothing behind it is the worst of the states this screen can be in,
        // and it is reachable: the phone answers "asking", then the person walks away, or the
        // second message never arrives. After a while, say the thing that leads somewhere.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, self.stage == .waiting else { return }
            self.stage = .needsPhoneApp
        }

        WCSession.default.sendMessage(
            [WatchProvisioning.MessageKey.request: attempt.request]
        ) { reply in
            Task { @MainActor in self.phoneAnswered(reply) }
        } errorHandler: { _ in
            // Not reachable, not paired, or the counterpart is not running. All of them mean
            // the same thing to somebody standing there: the phone is not answering.
            Task { @MainActor in self.stage = .needsPhoneApp }
        }
    }

    /// **The vocabulary is `WatchProvisioning.Answer`, not string literals**, so the phone and
    /// this switch cannot drift apart without the compiler saying so. They used to be two sets
    /// of hand written strings in different modules, where a rename would have degraded in
    /// silence to the "not set up" branch, which reads as a plausible answer and is the wrong
    /// one.
    ///
    /// Anything unrecognised still lands on "not set up", deliberately. A watch that cannot
    /// understand the answer has, as far as its wearer is concerned, not been set up, and the
    /// remedy that screen offers is to try again.
    private func phoneAnswered(_ reply: [String: Any]) {
        let status = reply[WatchProvisioning.MessageKey.status] as? String
        switch status.flatMap(WatchProvisioning.Answer.init(rawValue:)) {
        case .asking: stage = .waiting
        case .needsApp: stage = .needsPhoneApp
        case .noVault: stage = .phoneNotSetUp
        case .declined, .none: stage = .notSetUp
        }
    }

    /// The second message, carrying the sealed key or a refusal.
    ///
    /// **Every check lives in `WatchProvisioning.Attempt.open`**, including that the nonce is the
    /// one this attempt just sent, so a watch cannot install a key from a message it has not
    /// fully verified.
    private func phoneSent(_ message: [String: Any]) {
        if let response = message[WatchProvisioning.MessageKey.response] as? Data,
            let attempt
        {
            do {
                try keys.install(try attempt.open(response))
                self.attempt = nil

                // The key arrived. Whether it was the right one is a different question, and the
                // only honest way to answer it is to try reading with it.
                if keyOpensNothing {
                    hasReplacedStaleKey = true
                    stage = .cannotRead
                } else {
                    stage = .ready
                }
            } catch {
                self.attempt = nil
                stage = .notSetUp
            }
            return
        }

        if message[WatchProvisioning.MessageKey.status] as? String
            == WatchProvisioning.Answer.declined.rawValue
        {
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
