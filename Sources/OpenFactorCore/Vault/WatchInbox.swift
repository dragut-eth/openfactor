import Foundation

/// What arrived from the phone, and what the watch should conclude from it.
///
/// ## Why this is here rather than in the watch app
///
/// Every defect gate A4 found in scope 2 lived in `WatchVaultModel` or `WatchKeyProvider`, and
/// every one was found by a person reading, because the package's test suite cannot reach either
/// file. Round one found two races there. Round two found a re-ask whose reasoning was unsound and
/// a consent window on a wall clock. Round three found `.busy` handled in the core and not in the
/// model, with two tests asserting a property the shipped watch did not have.
///
/// Three reviewers, across three rounds, said the same thing about that pattern: the defect
/// surface is not moving around, it is pooling where the tests cannot go. This is the answer,
/// and it is the third time this project has given it: `WatchProvisioningFlow` and
/// `AppLockPresentation` were the first two.
///
/// **The rule for what belongs here is that a decision belongs here.** Reading a dictionary,
/// comparing a nonce, and choosing whether to believe a message are decisions. Sending, drawing,
/// and holding a private key are not, and stay where they are.
public enum WatchInbox {

    /// A nonce on a decline, in the three states it can genuinely be in.
    ///
    /// **Absent and unreadable are different messages and must not be merged.** `as? Data` alone
    /// merged them, so a decline whose nonce arrived as anything unexpected was treated as one
    /// from a phone too old to send one, and honoured. A review separated them; this makes the
    /// separation something a test can hold onto.
    public enum Nonce: Equatable, Sendable {
        /// No nonce key at all: a phone built before the field existed.
        case absent
        /// The key is there and this build cannot read it.
        case unreadable
        case present(Data)
    }

    /// What a message from the phone turned out to be.
    public enum Message: Equatable, Sendable {
        /// The direct reply to a request.
        case answer(WatchProvisioning.Answer?)
        /// The second message, carrying the sealed key.
        case sealedResponse(Data)
        /// The second message, refusing.
        case decline(Nonce)
        /// Nothing this build recognises.
        case unrecognised
    }

    /// Reads a WatchConnectivity dictionary without deciding anything about it.
    ///
    /// The order matters and is the order the protocol sends in: a sealed response is the
    /// generous case and is checked first, then a refusal, then a direct answer.
    public static func classify(_ message: [String: Any]) -> Message {
        if let response = message[WatchProvisioning.MessageKey.response] as? Data {
            return .sealedResponse(response)
        }

        if let status = message[WatchProvisioning.MessageKey.status] as? String {
            if status == WatchProvisioning.Answer.declined.rawValue {
                return .decline(nonce(in: message))
            }
            return .answer(WatchProvisioning.Answer(rawValue: status))
        }

        return .unrecognised
    }

    private static func nonce(in message: [String: Any]) -> Nonce {
        guard let raw = message[WatchProvisioning.MessageKey.nonce] else { return .absent }
        guard let data = raw as? Data else { return .unreadable }
        return .present(data)
    }

    /// Whether a refusal should end the attempt this watch is holding.
    ///
    /// - Parameter matchesCurrentAttempt: whether the nonce is this attempt's own. False when
    ///   there is no attempt, which is the case a review walked out: with nothing held, a decline
    ///   meant for somebody else's request was being honoured against whatever this watch was
    ///   doing.
    ///
    /// **A nonce-less decline is honoured, and that is a judgment rather than a deduction.** It
    /// comes from a phone built before the field existed, refusing it costs one screen that says
    /// to try again, and a refusal releases nothing either way. The reason first written down for
    /// it was that refusing would leave a watch waiting forever, which is false: the timeout is
    /// twenty five seconds and then there is a button.
    public static func shouldHonourDecline(_ nonce: Nonce, matchesCurrentAttempt: Bool) -> Bool {
        switch nonce {
        case .absent: return true
        case .unreadable: return false
        case .present: return matchesCurrentAttempt
        }
    }
}
