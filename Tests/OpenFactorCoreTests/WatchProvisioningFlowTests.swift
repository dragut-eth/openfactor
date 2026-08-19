import Foundation
import Testing

@testable import OpenFactorCore

/// The watch's asking flow, and specifically the two races an independent review found in it.
///
/// **Both were unreachable by any test when they were written**, because this logic lived in the
/// watch app's view model and the only test target reaches the core. That is why it is a value
/// type now, and these are the sequences that failed before it was.
///
/// Neither needs an attacker, a malformed message, or a hostile phone. Both are ordinary
/// asynchronous reordering: an answer that takes longer than a person's patience.
@Suite("Watch provisioning flow")
struct WatchProvisioningFlowTests {

    // MARK: - The two races

    /// **The first race.** A timer started for attempt A used to check only that the stage was
    /// still `waiting`, which is true again the moment attempt B begins, so A's timer demoted B
    /// within a second of the wearer asking again.
    @Test("A timeout from an abandoned attempt cannot touch the current one")
    func staleTimeoutCannotDemoteANewAttempt() {
        var flow = WatchProvisioningFlow()

        let first = flow.beganAsking()
        flow.timedOut(first)
        #expect(flow.stage == .needsPhoneApp)

        // The wearer taps the button on that screen.
        let second = flow.beganAsking()
        #expect(flow.stage == .waiting)

        // Now the first attempt's timer, or its error handler, finally wakes up.
        flow.timedOut(first)
        flow.sendFailed(first)
        flow.phoneAnswered(.needsApp, token: first)

        #expect(flow.stage == .waiting, "the second attempt is still waiting, undisturbed")
        #expect(flow.isCurrent(second))
        #expect(!flow.isCurrent(first))
    }

    /// **The second race, and the worse one.** A response answering attempt A arrives while
    /// attempt B is outstanding. It fails to open, correctly, because its nonce is not B's. One
    /// generic catch then cleared the attempt, so the genuine answer to B arrived a moment later
    /// and found nothing to open it with. The watch could not be set up until the app restarted.
    @Test("An obsolete response leaves the waiting attempt alone")
    func obsoleteResponseDoesNotDestroyTheCurrentAttempt() {
        var flow = WatchProvisioningFlow()

        let first = flow.beganAsking()
        flow.timedOut(first)
        _ = flow.beganAsking()

        // The delayed response to the first attempt turns up and cannot open.
        flow.responseDidNotOpen(obsolete: true)

        #expect(flow.stage == .waiting, "still waiting for the answer to the current attempt")
        #expect(flow.isAsking, "and the attempt is still held, so that answer can be opened")

        // Which then arrives.
        flow.installedKey(opensAccounts: true)
        #expect(flow.stage == .ready)
    }

    /// The other half of the same distinction: a response that fails for any reason other than
    /// belonging to an older attempt is a real failure and must end this one.
    @Test("A response that genuinely fails to open ends the attempt")
    func realFailureEndsTheAttempt() {
        var flow = WatchProvisioningFlow()
        _ = flow.beganAsking()

        flow.responseDidNotOpen(obsolete: false)
        #expect(flow.stage == .notSetUp)
        #expect(!flow.isAsking)
    }

    // MARK: - Terminal answers end the attempt

    /// `.asking` and `.busy` are the two non-terminal answers, and they are excluded by name
    /// rather than by a property so that a fifth answer added later lands in this loop and has to
    /// be thought about.
    @Test("Every terminal answer stops the attempt being current")
    func terminalAnswersEndTheAttempt() {
        for answer in WatchProvisioning.Answer.allCases
        where answer != .asking && answer != .busy {
            var flow = WatchProvisioningFlow()
            let token = flow.beganAsking()
            flow.phoneAnswered(answer, token: token)
            #expect(!flow.isAsking, "\(answer) is terminal")
            #expect(flow.stage != .waiting)
        }
    }

    /// "Asking" is the one answer that is not terminal: the person is being asked, and the key
    /// may follow in a second message.
    @Test("Being asked keeps the attempt alive")
    func askingKeepsTheAttempt() {
        var flow = WatchProvisioningFlow()
        let token = flow.beganAsking()

        flow.phoneAnswered(.asking, token: token)
        #expect(flow.stage == .waiting)
        #expect(flow.isAsking)
        #expect(flow.isCurrent(token))
    }

    /// **The answer added in round two.** The phone used to reply `.asking` to a request it had
    /// already thrown away, so the watch waited twenty five seconds for a question nobody was
    /// being shown. `.busy` says the true thing, and the watch keeps waiting on purpose: the
    /// person is answering somebody else's request, and this one can be re-asked when the timeout
    /// arrives.
    @Test("Busy keeps the attempt alive rather than ending it")
    func busyKeepsTheAttempt() {
        var flow = WatchProvisioningFlow()
        let token = flow.beganAsking()

        flow.phoneAnswered(.busy, token: token)
        #expect(flow.stage == .waiting)
        #expect(flow.isAsking, "the attempt is held, so a later answer to it can still open")
        #expect(flow.isCurrent(token))
    }

    /// The other direction, and this test found a defect in the fix above rather than confirming
    /// it. A timed-out attempt stays claimable on purpose, so that a key arriving late still
    /// installs instead of being thrown away. That means a busy answer reaches this method after
    /// the timeout, and it used to put the spinner back up. The timer for that attempt has
    /// already fired, so nobody was coming to take it down again.
    @Test("Busy after a timeout leaves the dead-end screen up")
    func busyAfterTimeoutDoesNotRestoreTheSpinner() {
        var flow = WatchProvisioningFlow()
        let first = flow.beganAsking()
        flow.timedOut(first)
        #expect(flow.stage == .needsPhoneApp)

        flow.phoneAnswered(.busy, token: first)
        #expect(flow.stage == .needsPhoneApp, "the screen with a button on it stays")
        #expect(flow.isAsking, "and the attempt is still claimable, so a late key still installs")

        flow.installedKey(opensAccounts: true)
        #expect(flow.stage == .ready)
    }

    /// Gate A4 round two: `phoneDeclined` was the sibling of `responseDidNotOpen` and did not
    /// get the same guard, so a decline arriving after the watch was ready demoted it.
    @Test("A decline with nothing outstanding cannot demote a ready watch")
    func declineWithNothingOutstandingIsInert() {
        var flow = WatchProvisioningFlow()
        _ = flow.beganAsking()
        flow.installedKey(opensAccounts: true)

        flow.phoneDeclined()
        #expect(flow.stage == .ready, "a late decline must not unset a working watch")
    }

    @Test("An answer this build cannot read is treated as a refusal, not guessed at")
    func unknownAnswerIsARefusal() {
        var flow = WatchProvisioningFlow()
        let token = flow.beganAsking()

        flow.phoneAnswered(nil, token: token)
        #expect(flow.stage == .notSetUp)
        #expect(!flow.isAsking)
    }

    @Test("A declined second message ends it")
    func declinedSecondMessage() {
        var flow = WatchProvisioningFlow()
        _ = flow.beganAsking()

        flow.phoneDeclined()
        #expect(flow.stage == .notSetUp)
        #expect(!flow.isAsking)
    }

    /// Gate A4: this was the one transition carrying no guard of its own, so a call with
    /// nothing outstanding demoted any stage, including a watch that was already reading its
    /// accounts. Unreachable when it was found, and filed anyway, which is the right call for a
    /// type whose whole job is to be the place these guarantees are pinned.
    @Test("A failure with nothing outstanding cannot demote a ready watch")
    func failureWithNothingOutstandingIsInert() {
        var flow = WatchProvisioningFlow()
        _ = flow.beganAsking()
        flow.installedKey(opensAccounts: true)
        #expect(flow.stage == .ready)
        #expect(!flow.isAsking)

        flow.responseDidNotOpen(obsolete: false)
        #expect(flow.stage == .ready, "a late failure must not unset a working watch")
    }

    /// The same guard from the other side: a genuine failure while an attempt is outstanding
    /// must still end it, so the guard cannot be a blanket refusal.
    @Test("A failure while an attempt is outstanding still ends it")
    func failureWhileOutstandingStillEnds() {
        var flow = WatchProvisioningFlow()
        _ = flow.beganAsking()

        flow.responseDidNotOpen(obsolete: false)
        #expect(flow.stage == .notSetUp)
        #expect(!flow.isAsking)
    }

    // MARK: - The rest of the surface

    @Test("A key that arrives and opens nothing says so rather than claiming success")
    func installedKeyThatOpensNothing() {
        var flow = WatchProvisioningFlow()
        _ = flow.beganAsking()

        flow.installedKey(opensAccounts: false)
        #expect(flow.stage == .cannotRead)
        #expect(!flow.isAsking)
    }

    @Test("A working key found without asking goes straight to ready")
    func workingKeyWithoutAsking() {
        var flow = WatchProvisioningFlow()
        #expect(flow.stage == .checking)

        flow.foundWorkingKey()
        #expect(flow.stage == .ready)
        #expect(!flow.isAsking)
    }

    /// Asking again after a dead end is the way out of every screen this flow can show, so it
    /// has to work from all of them.
    @Test("Asking again works from every dead end")
    func askingAgainWorksFromAnywhere() {
        var flow = WatchProvisioningFlow()

        for reach in [
            { (f: inout WatchProvisioningFlow) in f.timedOut(f.beganAsking()) },
            { f in f.phoneAnswered(.needsApp, token: f.beganAsking()) },
            { f in f.phoneAnswered(.noVault, token: f.beganAsking()) },
            { f in f.phoneAnswered(.declined, token: f.beganAsking()) },
            { f in f.sendFailed(f.beganAsking()) },
            { f in _ = f.beganAsking(); f.responseDidNotOpen(obsolete: false) },
        ] {
            reach(&flow)
            #expect(flow.stage != .waiting, "reached a dead end")

            let token = flow.beganAsking()
            #expect(flow.stage == .waiting)
            #expect(flow.isCurrent(token))
        }
    }

    /// Tokens are not reused, so an answer to the fourth attempt cannot be mistaken for an
    /// answer to the first.
    @Test("Tokens are never reused")
    func tokensAreDistinct() {
        var flow = WatchProvisioningFlow()
        var tokens: [WatchProvisioningFlow.Token] = []

        for _ in 0..<8 { tokens.append(flow.beganAsking()) }

        for token in tokens.dropLast() {
            #expect(!flow.isCurrent(token))
        }
        #expect(flow.isCurrent(tokens.last!))
    }
}
