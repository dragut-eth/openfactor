import Foundation

/// The phone's side of provisioning: which request is being asked about, and what may be done
/// about it.
///
/// ## Why this is here rather than in the app
///
/// `WatchKeyProvider` held all of this, and `WatchKeyProvider` cannot be reached by any test this
/// package runs. Everything below was found by a reviewer reading it: that the phone answered
/// "asking" to a request it had already dropped, that a second request silently replaced the one
/// the alert was about, that consent had no deadline, that the deadline was measured on a clock
/// that can move backwards, and that expiry returned in silence leaving the alert up. Five
/// defects in one small object, none reachable by the suite.
///
/// **What stayed behind is the session, the alert, reading the key file, and sending bytes.** This
/// type never sees a key.
///
/// The sentence here used to say that what stayed behind is "everything that is not a decision",
/// and all three engines of round four rejected it in their own words. What is still resident in
/// the app targets, and still unreachable by any test here:
///
/// - the condition that arms the expiry timer, whose removal would leave every test below passing
///   and auto-clearing dead
/// - on the watch, the whole asking cadence: when to ask, `keyOpensNothing`, and the
///   `hasReplacedStaleKey` latch, which its own comment records as having been wrong once
///
/// Those are decisions. They predate this extraction and none of them produced a finding in this
/// gate, which is the reason they were not moved and not a claim that they could not be. The
/// honest description is that the extraction moved the message-handling rules and left the cadence
/// rules.
public struct ProvisioningDesk: Sendable {

    /// How long a request may wait for an answer, in seconds.
    ///
    /// Comfortably longer than the watch's own twenty five second timeout, so a live exchange
    /// cannot be cut off by it, and short enough that the question and the answer belong to each
    /// other.
    public static let consentWindow: TimeInterval = 120

    /// What the phone knows about itself when a request arrives.
    ///
    /// **`isFrontmost` is doing real work rather than being polite.** The key file is `.complete`
    /// protected, so a phone woken in the background cannot read it, and nobody is looking at a
    /// screen to agree to anything.
    ///
    /// **`hasVault` is a question rather than an answer, and that is the fix for a defect the
    /// extraction introduced.** Swift evaluates arguments eagerly, so building this out of a
    /// `Bool` meant the app read its vault key *before* the desk had checked the request's length
    /// or whether anybody was looking at the screen. A forty byte piece of rubbish caused a key
    /// read; so did a request arriving in the background. No key was ever sent, but it restored an
    /// ordering this project had already fixed once and contradicted three documents that say the
    /// phone validates and foregrounds first. Asking only when the answer matters restores it.
    public struct Conditions: Sendable {
        public let isFrontmost: Bool

        /// Asked, not told. Called at most once, and only after the request has parsed and the
        /// app is known to be frontmost.
        public let hasVault: @Sendable () -> Bool

        public init(isFrontmost: Bool, hasVault: @escaping @Sendable () -> Bool) {
            self.isFrontmost = isFrontmost
            self.hasVault = hasVault
        }
    }

    /// What a tap on the affirmative button should cause.
    public enum Approval: Sendable {
        /// Seal the key to this request and send it.
        case release(WatchProvisioning.ValidatedRequest)
        /// Refuse, echoing this nonce, because the window has passed.
        case refuse(nonce: Data)
        /// Nothing was pending. A tap that arrives twice, or after the question is gone.
        case nothing
    }

    /// The request the alert on screen is asking about, parsed before it was ever shown.
    private var pending: WatchProvisioning.ValidatedRequest?

    public init() {}

    /// Whether a question is on screen.
    public var isAsking: Bool { pending != nil }

    /// The nonce of the request being asked about, for a caller that needs to tell two apart.
    public var pendingNonce: Data? { pending?.requestNonce }

    /// Decides what to answer a request, and remembers it if the answer is a question.
    ///
    /// **The pending request is never overwritten while it is set.** A second request used to
    /// replace it silently, so a tap offered for one watch key sealed the vault to whichever key
    /// arrived last. Under WatchConnectivity's routing exclusivity both come from the genuine
    /// watch, so no exploit follows today, but that exclusivity is load bearing and undocumented
    /// by Apple, and this is exactly the defect that would turn a weakening of it into key
    /// exfiltration.
    ///
    /// **And the watch is told the truth about it.** The answer to a request this phone is about
    /// to drop used to be `.asking`, which left the watch waiting twenty five seconds for a
    /// question nobody was being shown. `.busy` says what happened.
    public mutating func received(
        _ request: Data, when conditions: Conditions
    ) -> WatchProvisioning.Answer {
        guard let validated = try? WatchProvisioning.validate(request) else { return .declined }
        guard conditions.isFrontmost else { return .needsApp }
        guard conditions.hasVault() else { return .noVault }
        guard pending == nil else { return .busy }

        pending = validated
        return .asking
    }

    /// The person tapped the affirmative button.
    ///
    /// Clears the desk whatever the outcome: the question has been answered, and a second tap on
    /// a lingering alert must not release anything.
    ///
    /// **Ask before reading the key.** The app used to load the key first and ask afterwards, so
    /// an expired request, a cleared desk, or a second tap all read it for nothing. The caller
    /// now reads a key only for `.release`.
    public mutating func approve(now: ContinuousClock.Instant = .now) -> Approval {
        guard let request = pending else { return .nothing }
        pending = nil

        // **Expiry is a refusal rather than silence.** Returning quietly left the alert up and
        // the request in memory: the owner taps, nothing is sent, and nothing says why.
        guard request.isAnswerable(within: Self.consentWindow, now: now) else {
            return .refuse(nonce: request.requestNonce)
        }
        return .release(request)
    }

    /// The person tapped the refusing button, or the deadline arrived on its own.
    ///
    /// - Returns: the nonce to echo, or `nil` when there was nothing to refuse.
    ///
    /// **The refusal names the request it refuses.** Every other message in this protocol is
    /// bound to its attempt; this was the one that carried nothing, so a refusal of an abandoned
    /// attempt ended the one the watch was still waiting on.
    public mutating func decline() -> Data? {
        defer { pending = nil }
        return pending?.requestNonce
    }

    /// Takes the question down if nobody answered it in time.
    ///
    /// - Returns: the nonce to echo when the deadline has genuinely passed for the request still
    ///   on the desk, and `nil` in every other case, including a window that elapses after the
    ///   person already answered or after a different request took the slot.
    public mutating func expire(
        _ nonce: Data, now: ContinuousClock.Instant = .now
    ) -> Data? {
        guard let request = pending, request.requestNonce == nonce else { return nil }
        guard !request.isAnswerable(within: Self.consentWindow, now: now) else { return nil }

        pending = nil
        return nonce
    }
}

/// Compared by the nonce of the request each names, because a `ValidatedRequest` holds a `P256`
/// public key that does not conform to `Equatable`, and the nonce is what identifies a request
/// anyway. Written out rather than synthesised so a test can say what it means.
extension ProvisioningDesk.Approval: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.release(a), .release(b)): return a.requestNonce == b.requestNonce
        case let (.refuse(a), .refuse(b)): return a == b
        case (.nothing, .nothing): return true
        default: return false
        }
    }
}
