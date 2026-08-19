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

    /// **The decisions live in `WatchProvisioningFlow`, in the core, where tests reach them.**
    /// An independent review found two races in them while they were scene state in this file,
    /// both reachable by walking away and coming back, and neither catchable by any test that
    /// existed. This type now carries out what that one decides.
    private var flow = WatchProvisioningFlow()

    /// The token of the attempt currently outstanding, carried into every callback that can
    /// outlive it. A callback holding an older token is ignored rather than believed.
    private var token: WatchProvisioningFlow.Token?

    var stage: WatchProvisioningFlow.Stage { flow.stage }


    private let keys: VaultKeyStore

    /// The half-finished exchange, holding the ephemeral private key the phone's answer is
    /// sealed to.
    ///
    /// **It outlives the two messages in every case but success**, which an earlier comment here
    /// denied. A timeout keeps it deliberately, because a slow answer is still a good answer; a
    /// send error, a refusal and an unreadable reply all clear it. `WatchProvisioning.Attempt.open`
    /// is non-mutating and enforces nothing about being used once, so the guarantee that a stale
    /// one cannot be spoken for is `flow.isCurrent`, not this property.
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
                flow.foundWorkingKey()
                return
            }

            // A fresh key was installed and these records still will not open, so a newer format
            // wrote them rather than a different key having sealed them. Asking again would
            // fetch the same key and produce the same result, forever.
            guard !hasReplacedStaleKey else {
                flow.foundKeyThatOpensNothing()
                return
            }
        }

        // Not while a request is already out, or raising the wrist twice would send two.
        guard flow.stage != .waiting else { return }
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
        guard flow.stage != .ready else { return }

        let attempt: WatchProvisioning.Attempt
        do {
            // Throws only if the system CSPRNG refuses, which must not degrade quietly into a
            // predictable nonce. Nothing to tell the wearer to go and do about it, so it reads
            // as the phone not answering, which is the screen with the button.
            attempt = try WatchProvisioning.Attempt()
        } catch {
            // Cleared, the same as every other synthesized failure. Without this the stale
            // attempt from a previous try survives with nothing outstanding in the flow, and a
            // very late response to it installs a key while the screen says the phone is not
            // answering. Found in gate A4, and it contradicted the comment on `attempt` above.
            self.attempt = nil
            self.token = nil
            flow.sendFailed(flow.beganAsking())
            return
        }

        self.attempt = attempt
        let token = flow.beganAsking()
        self.token = token

        // A spinner with nothing behind it is the worst of the states this screen can be in,
        // and it is reachable: the phone answers "asking", then the person walks away, or the
        // second message never arrives. After a while, say the thing that leads somewhere.
        //
        // **The token is what makes this safe.** This timer used to check only whether the
        // stage was still waiting, which is true again the instant a new attempt begins, so it
        // demoted the attempt that replaced it.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self else { return }
            self.flow.timedOut(token)
        }

        WCSession.default.sendMessage(
            [WatchProvisioning.MessageKey.request: attempt.request]
        ) { reply in
            Task { @MainActor in self.phoneAnswered(reply, token: token) }
        } errorHandler: { _ in
            // Not reachable, not paired, or the counterpart is not running. All of them mean
            // the same thing to somebody standing there: the phone is not answering.
            Task { @MainActor in self.sendFailed(token) }
        }
    }

    private func sendFailed(_ token: WatchProvisioningFlow.Token) {
        guard flow.isCurrent(token) else { return }
        attempt = nil
        self.token = nil
        flow.sendFailed(token)
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
    private func phoneAnswered(_ reply: [String: Any], token: WatchProvisioningFlow.Token) {
        guard flow.isCurrent(token) else { return }

        let status = reply[WatchProvisioning.MessageKey.status] as? String
        let answer = status.flatMap(WatchProvisioning.Answer.init(rawValue:))
        flow.phoneAnswered(answer, token: token)

        releaseAttemptIfFinished()
    }

    /// Drops the attempt's private key exactly when the flow says the attempt is over.
    ///
    /// **This used to be a second opinion, and it was wrong within a day of being written.** The
    /// rule here read `if answer != .asking`, which was true of the four answers that existed
    /// when it was written. `.busy` made a fifth, non-terminal one, `WatchProvisioningFlow` was
    /// taught to keep the attempt for it, and this line was not: the flow held an attempt the
    /// model had already destroyed. Two tests asserted the surviving attempt, both passed,
    /// because both test the flow and nothing can test this file.
    ///
    /// So it is no longer a rule. The flow owns whether an attempt is outstanding, and this asks
    /// it rather than re-deriving it from the answer. A sixth answer cannot split the two apart
    /// again, because there is only one definition left.
    private func releaseAttemptIfFinished() {
        guard !flow.isAsking else { return }
        attempt = nil
        token = nil
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
                token = nil

                // The key arrived. Whether it was the right one is a different question, and the
                // only honest way to answer it is to try reading with it.
                let opens = !keyOpensNothing
                if !opens { hasReplacedStaleKey = true }
                flow.installedKey(opensAccounts: opens)
            } catch let error as WatchProvisioning.ExchangeError {
                // **A response answering an older attempt is obsolete, not wrong.** It used to
                // land in one generic catch that cleared the attempt, so a late reply destroyed
                // the attempt still waiting and the genuine answer that followed had nothing to
                // open it with and was dropped in silence.
                let obsolete = error == .notForThisRequest
                if !obsolete {
                    self.attempt = nil
                    token = nil
                }
                flow.responseDidNotOpen(obsolete: obsolete)

                // **The attempt is kept and nothing is inferred.** An earlier fix asked again
                // here, reasoning that an obsolete response proved the phone's slot was free.
                // Round two showed the inference is invalid across an asynchronous channel: if
                // the response was merely delayed and the phone has since retained a newer
                // request, re-asking abandons the very request its alert is showing, and the
                // wearer approves into a loop of prompts.
                //
                // The phone answers `.busy` now instead of pretending to ask, so the watch has no
                // reason to guess. Waiting is correct: the answer to this attempt may still be
                // coming, and the timeout recovers if it is not.
            } catch {
                // Installing the key failed, which is this attempt's failure.
                self.attempt = nil
                token = nil
                flow.responseDidNotOpen(obsolete: false)
            }
            return
        }

        if message[WatchProvisioning.MessageKey.status] as? String
            == WatchProvisioning.Answer.declined.rawValue
        {
            // **A refusal has to say which request it refuses.** Every other message in this
            // protocol is bound to its attempt, by a token on the callbacks and by the nonce on
            // the sealed response. The decline was the one that carried nothing, so a refusal of
            // an abandoned attempt cleared the attempt that was still waiting, and the approval
            // that followed had nothing left to open it with. Gate A4 found it.
            //
            // A decline with no nonce comes from a build that predates this, and is honoured.
            // The reason written here first was that refusing it would leave a watch waiting
            // forever, and round two pointed out that is false: the twenty five second timeout
            // recovers. The real reason is smaller and still good enough. Honouring it ends the
            // wait now instead of in twenty five seconds, the cost of being wrong is one screen
            // that says to try again, and a decline releases nothing either way.
            // **Present but unreadable is not the same as absent.** `as? Data` alone conflated
            // them: a decline whose nonce arrived as a string, or as anything this build does not
            // expect, failed the cast and was honoured as though it carried no nonce at all,
            // which is the behaviour reserved for a phone too old to send one. A review asked
            // for the two cases to be told apart, and they are: a nonce that is there and cannot
            // be read is a message this build does not understand, so it is ignored.
            if let raw = message[WatchProvisioning.MessageKey.nonce] {
                guard let declined = raw as? Data else { return }
                if let attempt, !attempt.answers(declined) { return }
            }

            // The flow first, then release what it no longer needs. The old order cleared the
            // attempt before asking, which is how the answer and the holding of the attempt came
            // to be decided in two places.
            flow.phoneDeclined()
            releaseAttemptIfFinished()
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
