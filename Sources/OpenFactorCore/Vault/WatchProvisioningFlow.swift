import Foundation

/// Decides what a watch shows while it asks its phone for the vault key, and which of the
/// callbacks still in flight are allowed to speak.
///
/// ## Why this is a value type in the core
///
/// It used to be scene state inside the watch's view model, which is in the watch target,
/// which no test can reach. An independent review then found two races in it that no test
/// could have caught for exactly that reason, both reachable by walking away from a phone and
/// coming back. The lock's presentation decisions were pulled out for the same reason after
/// the same kind of failure, and `AppLockPresentation` says so in the same words.
///
/// ## The races, and what stops them now
///
/// **A callback belongs to the attempt that started it.** Asking issues a token. Every
/// callback that can outlive its attempt, the timeout, the reply handler, and the send error
/// handler, carries the token it was created with, and this type ignores any of them that is
/// not the current attempt. Before that, a timer started for attempt A checked only whether
/// the stage was still `waiting`, so it happily demoted attempt B a second after it began.
///
/// **A message that answers an older attempt is not a failure of the current one.** A response
/// that fails to open because its nonce belongs to a previous attempt is obsolete, not wrong,
/// and it must leave the current attempt alone. Before that, one generic catch cleared the
/// attempt on any error at all, so a late response destroyed the attempt that was still
/// waiting, and the genuine response that followed found nothing to open it with and was
/// dropped in silence. That is the whole bug: two ordinary taps and the watch could not be
/// set up again until the app was restarted.
///
/// Note which mechanism covers which path, because they are not interchangeable. Tokens
/// protect the callbacks, since those capture a moment and fire later. The obsolete
/// distinction protects the response, since the phone's second message arrives as a fresh
/// message carrying no token of ours and can only be judged by whether it answers the
/// attempt we are holding.
public struct WatchProvisioningFlow: Equatable, Sendable {

    /// What the wearer is looking at.
    public enum Stage: Equatable, Sendable {
        /// Before anything has been decided. Draws nothing rather than a spinner.
        case checking
        /// A request is out and an answer is expected.
        case waiting
        /// This watch has a key that opens its accounts.
        case ready
        /// Every way the phone can fail to answer, which all have one remedy.
        case needsPhoneApp
        /// The phone has no vault of its own yet.
        case phoneNotSetUp
        /// Declined, or something did not open.
        case notSetUp
        /// A key arrived, was installed, and still opens nothing.
        case cannotRead
    }

    /// Identifies one attempt. Opaque on purpose: it is a token to carry, not a number to
    /// reason about.
    public struct Token: Equatable, Sendable {
        fileprivate let value: Int
    }

    public private(set) var stage: Stage = .checking

    private var issued = 0
    private var outstanding: Int?

    public init() {}

    /// Whether an attempt is still expecting an answer.
    public var isAsking: Bool { outstanding != nil }

    /// Whether this token belongs to the attempt currently outstanding. The watch's model
    /// reads this to decide whether it may still touch the stored attempt.
    public func isCurrent(_ token: Token) -> Bool { outstanding == token.value }

    // MARK: - Deciding without asking

    /// A key is present and opens the accounts.
    public mutating func foundWorkingKey() {
        outstanding = nil
        stage = .ready
    }

    /// A key is present, a fresh one has already been fetched once, and it still opens
    /// nothing. Asking again would fetch the same key and give the same answer forever.
    public mutating func foundKeyThatOpensNothing() {
        outstanding = nil
        stage = .cannotRead
    }

    // MARK: - Asking

    /// Begins an attempt and returns the token every callback for it must carry.
    ///
    /// The previous attempt, if any, stops being current here. That is the single line that
    /// makes a stale timer harmless.
    public mutating func beganAsking() -> Token {
        issued += 1
        outstanding = issued
        stage = .waiting
        return Token(value: issued)
    }

    /// The wait has gone on long enough to say something that leads somewhere.
    ///
    /// **The attempt stays outstanding.** A slow answer is still a good answer, and the phone
    /// may yet reply; this only changes what the wearer is looking at while they wait. If they
    /// ask again instead, that new attempt supersedes this one and any answer to this one
    /// becomes obsolete.
    public mutating func timedOut(_ token: Token) {
        guard outstanding == token.value, stage == .waiting else { return }
        stage = .needsPhoneApp
    }

    /// The message could not be sent: not reachable, not paired, or nothing running to
    /// receive it. All the same thing to somebody standing there.
    public mutating func sendFailed(_ token: Token) {
        guard outstanding == token.value else { return }
        outstanding = nil
        stage = .needsPhoneApp
    }

    /// The phone's answer to the first message. `nil` for anything this build cannot read,
    /// which is treated as a refusal rather than guessed at.
    public mutating func phoneAnswered(_ answer: WatchProvisioning.Answer?, token: Token) {
        guard outstanding == token.value else { return }

        switch answer {
        case .asking:
            // Still outstanding: the person is being asked, and the key may follow.
            stage = .waiting
        case .needsApp:
            outstanding = nil
            stage = .needsPhoneApp
        case .noVault:
            outstanding = nil
            stage = .phoneNotSetUp
        case .busy:
            // The attempt stays outstanding. The phone is asking its owner about somebody
            // else's request, and when that is answered its slot frees and this watch's own
            // timeout or its wearer will ask again. Guessing at the phone's state from here is
            // what produced the race round two found.
            //
            // **Only while still waiting.** A timed-out attempt is deliberately still claimable,
            // so a busy answer arriving after the timeout passed this method's guard and put the
            // spinner back up. Its timer has already fired and will not fire again, so that is a
            // spinner with nothing behind it. The dead-end screen is the honest one: it has a
            // button. Found by the test written for the answer this same review added.
            guard stage == .waiting else { return }
            stage = .waiting

        case .declined, .none:
            outstanding = nil
            stage = .notSetUp
        }
    }

    // MARK: - The second message

    /// A key arrived and was installed. Whether it is the right key is a separate question,
    /// and the only honest way to answer it is to try reading with it.
    public mutating func installedKey(opensAccounts: Bool) {
        outstanding = nil
        stage = opensAccounts ? .ready : .cannotRead
    }

    /// A response arrived and did not open.
    ///
    /// **`obsolete` is the whole point.** A response whose nonce belongs to an earlier attempt
    /// is answering a question this watch has stopped asking, and it must change nothing: the
    /// attempt still waiting is still valid, and the answer to it may be one message behind.
    /// Anything else is a real failure of the current attempt.
    public mutating func responseDidNotOpen(obsolete: Bool) {
        guard !obsolete else { return }
        // **Guarded like every sibling transition.** Without this, a call with nothing
        // outstanding demotes any stage, including `.ready`, so a watch showing its accounts
        // would revert to "Not set up". No caller does that today. The guard is here because
        // this type exists to be the place those guarantees are tested, and every sibling
        // carries one.
        guard outstanding != nil else { return }
        outstanding = nil
        stage = .notSetUp
    }

    /// The phone said no, in the second message.
    public mutating func phoneDeclined() {
        // **The same guard as its sibling, which round two found missing here.** Item 6 of round
        // one added it to `responseDidNotOpen` and not to this method three lines away, so a
        // decline arriving after a successful install demoted a watch that was already reading
        // its accounts to "Not set up". All three engines found it.
        guard outstanding != nil else { return }
        outstanding = nil
        stage = .notSetUp
    }
}
