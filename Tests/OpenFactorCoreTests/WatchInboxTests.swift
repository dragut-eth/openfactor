import Foundation
import Testing

@testable import OpenFactorCore

/// Reading what the phone sent, and deciding whether to believe a refusal.
///
/// This lived in `WatchVaultModel`, which no test can reach, and the two rules below were each
/// wrong at least once: a nonce that was present but unreadable was treated as absent and
/// honoured, and a refusal naming somebody else's request was honoured whenever this watch
/// happened to be holding nothing.
@Suite("Watch inbox")
struct WatchInboxTests {

    // MARK: - Reading the message

    @Test("A sealed response is read as one")
    func sealedResponseIsRecognised() {
        let payload = Data(repeating: 9, count: 145)
        #expect(
            WatchInbox.classify([WatchProvisioning.MessageKey.response: payload])
                == .sealedResponse(payload))
    }

    @Test("A refusal carrying a nonce is read with it")
    func declineWithNonce() {
        let nonce = Data(repeating: 4, count: 16)
        let message: [String: Any] = [
            WatchProvisioning.MessageKey.status: "declined",
            WatchProvisioning.MessageKey.nonce: nonce,
        ]
        #expect(WatchInbox.classify(message) == .decline(.present(nonce)))
    }

    @Test("A refusal with no nonce is read as having none")
    func declineWithoutNonce() {
        #expect(
            WatchInbox.classify([WatchProvisioning.MessageKey.status: "declined"])
                == .decline(.absent))
    }

    /// **Absent and unreadable are different messages**, and merging them is what made a decline
    /// this build could not understand look like one from a phone too old to send a nonce.
    @Test("A nonce of the wrong type is unreadable, not absent")
    func declineWithAnUnreadableNonce() {
        let message: [String: Any] = [
            WatchProvisioning.MessageKey.status: "declined",
            WatchProvisioning.MessageKey.nonce: "not data at all",
        ]
        #expect(WatchInbox.classify(message) == .decline(.unreadable))
    }

    @Test("An answer this build knows is read, and one it does not is nil rather than guessed")
    func answersAreRead() {
        #expect(WatchInbox.classify(["status": "busy"]) == .answer(.busy))
        #expect(WatchInbox.classify(["status": "asking"]) == .answer(.asking))
        #expect(WatchInbox.classify(["status": "a status from a later version"]) == .answer(nil))
    }

    @Test("A message with nothing recognisable in it says so")
    func unrecognisedMessage() {
        #expect(WatchInbox.classify(["something": "else"]) == .unrecognised)
    }

    // MARK: - Believing a refusal

    /// The three cases, and the middle one is the judgment rather than the deduction.
    @Test("A refusal is believed only when it names this attempt, or names nothing at all")
    func decidingWhetherToBelieveARefusal() {
        // A phone built before the nonce existed. Honoured deliberately.
        #expect(WatchInbox.shouldHonourDecline(.absent, matchesCurrentAttempt: false))
        #expect(WatchInbox.shouldHonourDecline(.absent, matchesCurrentAttempt: true))

        // A nonce this build cannot read is a message it does not understand.
        #expect(!WatchInbox.shouldHonourDecline(.unreadable, matchesCurrentAttempt: false))
        #expect(!WatchInbox.shouldHonourDecline(.unreadable, matchesCurrentAttempt: true))

        // A nonce that names a request: believed when it names this one.
        let nonce = Data(repeating: 1, count: 16)
        #expect(WatchInbox.shouldHonourDecline(.present(nonce), matchesCurrentAttempt: true))
        #expect(!WatchInbox.shouldHonourDecline(.present(nonce), matchesCurrentAttempt: false))
    }

    /// **The case a review walked out.** With no attempt held, `matchesCurrentAttempt` is false,
    /// and a refusal meant for somebody else's request used to be honoured against whatever this
    /// watch was doing.
    @Test("A refusal naming a request is ignored when this watch holds none")
    func refusalIgnoredWithNoAttempt() {
        let nonce = Data(repeating: 7, count: 16)
        #expect(!WatchInbox.shouldHonourDecline(.present(nonce), matchesCurrentAttempt: false))
    }
}
