import Foundation

/// The phone's side of provisioning: which request is being asked about, and what may be done
/// about it.
///
/// ## Why this is here rather than in the app
///
/// `WatchKeyProvider` held all of it, and `WatchKeyProvider` cannot be reached by any test this
/// package runs. Every defect this project has found in these rules was found by a person reading
/// that file, one at a time, which is a discovery method that does not scale and does not stay
/// fixed.
///
/// **This type never sees a key.** What stays in the app targets is the session, the alert,
/// reading the key file and sending bytes, along with rules no test here can reach: when the
/// expiry timer is armed, that a refusal the desk cannot name is not sent at all, that a failure
/// to read the key or build a response refuses by name rather than going quiet, and, on the
/// watch, the whole asking cadence.
///
/// Those are named because each is removable with this suite still green, which is what makes
/// them worth naming. It is not a claim that the list is complete.
///
/// `docs/audits/` carries how the split came to be, what was argued about it, and what was
/// rejected.
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
    /// **`hasVault` is a question rather than an answer, and it has to stay one.** Swift
    /// evaluates arguments eagerly, so a `Bool` here means the app reads its vault key *before*
    /// the desk has checked the request's length or whether anybody is looking at the screen. A
    /// forty byte piece of rubbish causes a key read, and so does a request arriving in the
    /// background. No key is sent either way, but the ordering is one that `docs/VAULT.md`,
    /// `SECURITY.md` and `docs/ARCHITECTURE.md` all describe the other way round: the phone
    /// validates and foregrounds first. Asking only when the answer matters is what keeps that
    /// true.
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

    /// The instant the pending request was validated at.
    ///
    /// **Exists so a test can anchor on the request rather than on a fresh clock read.** A test
    /// that builds "a millisecond inside the window" from `.now` is really measuring the window
    /// plus however long passed since the request was stamped, which a stall on a loaded machine
    /// turns into a failure with no product meaning. This suite is what every fix here is
    /// reverted against, so a test that can fail for no product reason is worse than no test.
    var pendingInstant: ContinuousClock.Instant? { pending?.validatedAt }

    /// Decides what to answer a request, and remembers it if the answer is a question.
    ///
    /// **The pending request is never overwritten while it is set.** If a second request could
    /// replace it silently, a tap offered for one watch key would seal the vault to whichever key
    /// arrived last. Under WatchConnectivity's routing exclusivity both come from the genuine
    /// watch, so no exploit follows from it today, but that exclusivity is load bearing and
    /// undocumented by Apple, and this is exactly the defect that would turn a weakening of it
    /// into key exfiltration.
    ///
    /// **And the watch is told the truth about it.** Answering `.asking` to a request this phone
    /// is about to drop leaves the watch waiting twenty five seconds for a question nobody is
    /// being shown. `.busy` says what happened.
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
    /// **Ask before reading the key.** Loading the key first and asking afterwards reads it for
    /// nothing on an expired request, a cleared desk, or a second tap. The caller reads a key
    /// only for `.release`.
    public mutating func approve(now: ContinuousClock.Instant = .now) -> Approval {
        guard let request = pending else { return .nothing }
        pending = nil

        // **Expiry is a refusal rather than silence.** Returning quietly leaves the alert up and
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
    /// **The refusal names the request it refuses.** Every message in this protocol is bound to
    /// its attempt. Unbound, a refusal of an abandoned attempt ends the one the watch is still
    /// waiting on.
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
