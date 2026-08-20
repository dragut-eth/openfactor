import Foundation
import Testing

@testable import OpenFactorCore

/// The phone's provisioning rules, which until now no test could reach.
///
/// **Every case below is a defect gate A4 found by reading `WatchKeyProvider`.** Five of them, in
/// one small object, across three rounds, none of them reachable by a suite. That is the argument
/// for this file existing rather than a claim about it.
@Suite("Provisioning desk")
struct ProvisioningDeskTests {

    private func request() throws -> (Data, Data) {
        let attempt = try WatchProvisioning.Attempt()
        let validated = try WatchProvisioning.validate(attempt.request)
        return (attempt.request, validated.requestNonce)
    }

    /// Records whether the vault question was ever asked. A class because the closure is
    /// `@Sendable`, which is the whole point: the question is a value the desk may or may not
    /// call, rather than an answer computed before it is wanted.
    private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var asked = false

        func record() { lock.withLock { asked = true } }
        var wasAsked: Bool { lock.withLock { asked } }
    }

    private let ready = ProvisioningDesk.Conditions(isFrontmost: true, hasVault: { true })

    // MARK: - Answering

    @Test("A request arriving on a ready phone is asked about")
    func aRequestIsAskedAbout() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()

        #expect(desk.received(request, when: ready) == .asking)
        #expect(desk.isAsking)
        #expect(desk.pendingNonce == nonce)
    }

    /// **The lie round one found.** The phone answered `.asking` for a request it then discarded,
    /// so the watch waited twenty five seconds for a question nobody was being shown.
    @Test("A second request is told the phone is busy, not that it is asking")
    func secondRequestIsToldBusy() throws {
        var desk = ProvisioningDesk()
        let (first, firstNonce) = try request()
        let (second, _) = try request()

        #expect(desk.received(first, when: ready) == .asking)
        #expect(desk.received(second, when: ready) == .busy)
        #expect(desk.pendingNonce == firstNonce, "and the question on screen did not change")
    }

    /// The reason the question does not change: a tap offered for one watch key must never seal
    /// the vault to whichever key arrived last.
    @Test("Approving after a second request releases to the first")
    func approvalFollowsTheQuestionOnScreen() throws {
        var desk = ProvisioningDesk()
        let (first, firstNonce) = try request()
        let (second, secondNonce) = try request()

        _ = desk.received(first, when: ready)
        _ = desk.received(second, when: ready)

        guard case let .release(released) = desk.approve() else {
            Issue.record("expected a release")
            return
        }
        #expect(released.requestNonce == firstNonce)
        #expect(released.requestNonce != secondNonce)
    }

    @Test("A phone in the background says so rather than asking nobody")
    func backgroundIsNeedsApp() throws {
        var desk = ProvisioningDesk()
        let (request, _) = try request()

        let conditions = ProvisioningDesk.Conditions(isFrontmost: false, hasVault: { true })
        #expect(desk.received(request, when: conditions) == .needsApp)
        #expect(!desk.isAsking, "and nothing is left on the desk")
    }

    @Test("A phone with no vault says so")
    func noVaultIsSaidSo() throws {
        var desk = ProvisioningDesk()
        let (request, _) = try request()

        let conditions = ProvisioningDesk.Conditions(isFrontmost: true, hasVault: { false })
        #expect(desk.received(request, when: conditions) == .noVault)
        #expect(!desk.isAsking)
    }

    @Test("Rubbish is refused before anything else is asked")
    func rubbishIsRefused() {
        var desk = ProvisioningDesk()
        #expect(desk.received(Data(repeating: 0, count: 40), when: ready) == .declined)
        #expect(!desk.isAsking)
    }

    // MARK: - The consent window

    @Test("A tap inside the window releases the key")
    func tapInsideTheWindowReleases() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()
        _ = desk.received(request, when: ready)

        guard case let .release(released) = desk.approve(now: .now.advanced(by: .seconds(119)))
        else {
            Issue.record("expected a release inside the window")
            return
        }
        #expect(released.requestNonce == nonce)
    }

    /// **The defect all three round-two reviews found**, in the shape the fix has to refuse: a
    /// clock reading from before the request was validated is not freshness.
    @Test("A tap past the window refuses, and so does one from a backward clock")
    func tapOutsideTheWindowRefuses() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()
        _ = desk.received(request, when: ready)

        #expect(desk.approve(now: .now.advanced(by: .seconds(121))) == .refuse(nonce: nonce))

        var backwards = ProvisioningDesk()
        _ = backwards.received(request, when: ready)
        #expect(backwards.approve(now: .now.advanced(by: .seconds(-3600))) == .refuse(nonce: nonce))
    }

    /// A refusal is still an answer: the desk is cleared either way, so a second tap on an alert
    /// that is somehow still up releases nothing.
    @Test("A second tap releases nothing")
    func secondTapReleasesNothing() throws {
        var desk = ProvisioningDesk()
        let (request, _) = try request()
        _ = desk.received(request, when: ready)

        _ = desk.approve()
        #expect(desk.approve() == .nothing)
        #expect(!desk.isAsking)
    }

    // MARK: - Refusing

    @Test("A refusal names the request it refuses")
    func refusalNamesItsRequest() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()
        _ = desk.received(request, when: ready)

        #expect(desk.decline() == nonce)
        #expect(!desk.isAsking)
    }

    @Test("A refusal with nothing on the desk names nothing")
    func refusalWithNothingPending() {
        var desk = ProvisioningDesk()
        #expect(desk.decline() == nil)
    }

    // MARK: - The deadline arriving on its own

    @Test("The deadline takes the question down")
    func deadlineTakesTheQuestionDown() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()
        _ = desk.received(request, when: ready)

        #expect(desk.expire(nonce, now: .now.advanced(by: .seconds(121))) == nonce)
        #expect(!desk.isAsking)
    }

    /// The three ways a timer can be wrong, all of which must do nothing.
    @Test("A deadline that fires early, late, or for the wrong request does nothing")
    func deadlineCannotMisfire() throws {
        let (first, firstNonce) = try request()
        let (second, secondNonce) = try request()

        // Early: the window has not passed.
        var early = ProvisioningDesk()
        _ = early.received(first, when: ready)
        #expect(early.expire(firstNonce, now: .now.advanced(by: .seconds(60))) == nil)
        #expect(early.isAsking, "the question is still up")

        // Wrong request: this timer belongs to one the desk no longer holds.
        var wrong = ProvisioningDesk()
        _ = wrong.received(first, when: ready)
        #expect(wrong.expire(secondNonce, now: .now.advanced(by: .seconds(121))) == nil)
        #expect(wrong.isAsking)

        // Answered already: the desk is empty, so there is nothing to take down.
        var answered = ProvisioningDesk()
        _ = answered.received(second, when: ready)
        _ = answered.approve()
        #expect(answered.expire(secondNonce, now: .now.advanced(by: .seconds(121))) == nil)
    }

    // MARK: - Gate A4 round four

    /// **The timer expired nothing, and two engines found the arithmetic.** It sleeps for exactly
    /// the window; `age` reported whole seconds; the comparison was inclusive. So it woke at the
    /// window plus a fraction, the fraction was rounded away, the request was still answerable,
    /// and the alert stayed up. The desk test that proved the deadline works asked at 121 seconds,
    /// which is a moment the timer never asks at.
    @Test("The deadline has passed at the instant the timer actually wakes")
    func theDeadlineHasPassedWhenTheTimerWakes() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()
        _ = desk.received(request, when: ready)

        // What `Task.sleep(for: .seconds(120))` produces: the window, plus however long it took
        // to wake up.
        let wake = desk.pendingInstant!.advanced(by: .milliseconds(120_001))
        #expect(desk.expire(nonce, now: wake) == nonce, "the question comes down")
        #expect(!desk.isAsking)
    }

    /// And a fraction inside the window is still inside it, so the fix did not simply move the
    /// boundary a second the other way.
    @Test("A fraction inside the window still releases")
    func aFractionInsideStillReleases() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()
        _ = desk.received(request, when: ready)

        // **Anchored on the request's own instant, not on a fresh clock read.** Reading `.now`
        // here measures 119.999 seconds plus however long passed between `received` stamping the
        // request and this line running, so a millisecond of scheduler stall on a loaded machine
        // turned a release into a refusal and the test red for no product reason. Round five
        // caught it before it ever flaked.
        let justInside = desk.pendingInstant!.advanced(by: .milliseconds(119_999))
        guard case let .release(released) = desk.approve(now: justInside) else {
            Issue.record("a request a millisecond inside the window still releases")
            return
        }
        #expect(released.requestNonce == nonce)
    }

    /// And a fraction outside refuses, which the truncating comparison could not tell apart.
    @Test("A fraction outside the window refuses")
    func aFractionOutsideRefuses() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()
        _ = desk.received(request, when: ready)

        let justOutside = desk.pendingInstant!.advanced(by: .milliseconds(120_500))
        #expect(desk.approve(now: justOutside) == .refuse(nonce: nonce))
    }

    /// **Exactly the window, which is the instant three engines argued about.** Two of them said
    /// `Task.sleep` can never produce it, because it waits at least its duration and the request
    /// is stamped before the sleep is scheduled. They are very likely right, and the comparison is
    /// strict anyway: a character is cheaper than a physics argument nobody can rerun, and this
    /// test is what makes the character permanent.
    @Test("At exactly the window, the request has expired")
    func exactlyAtTheWindowIsExpired() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()
        _ = desk.received(request, when: ready)

        let exactly = try #require(desk.pendingInstant).advanced(
            by: .seconds(ProvisioningDesk.consentWindow))

        #expect(desk.expire(nonce, now: exactly) == nonce, "the deadline has arrived")
        #expect(!desk.isAsking)
    }

    /// And the symmetric case the strict comparison creates: a tap at exactly the window refuses
    /// rather than releasing. Equally unreachable, and refusing is the safe side.
    @Test("At exactly the window, a tap refuses")
    func exactlyAtTheWindowATapRefuses() throws {
        var desk = ProvisioningDesk()
        let (request, nonce) = try request()
        _ = desk.received(request, when: ready)

        let exactly = try #require(desk.pendingInstant).advanced(
            by: .seconds(ProvisioningDesk.consentWindow))

        #expect(desk.approve(now: exactly) == .refuse(nonce: nonce))
    }

    /// **The key is not read until the desk has a reason to want one.** Building `Conditions` out
    /// of a `Bool` evaluated the vault question eagerly, so rubbish and background requests both
    /// caused a key read before anything had validated them.
    @Test("A malformed request never asks whether there is a vault")
    func rubbishDoesNotReachTheVaultQuestion() {
        var desk = ProvisioningDesk()
        let asked = Asked()

        let conditions = ProvisioningDesk.Conditions(
            isFrontmost: true, hasVault: { asked.record(); return true })
        _ = desk.received(Data(repeating: 0, count: 40), when: conditions)

        #expect(!asked.wasAsked, "refused on its length, before anything looked for a key")
    }

    @Test("A request arriving in the background never asks either")
    func backgroundDoesNotReachTheVaultQuestion() throws {
        var desk = ProvisioningDesk()
        let (request, _) = try request()
        let asked = Asked()

        let conditions = ProvisioningDesk.Conditions(
            isFrontmost: false, hasVault: { asked.record(); return true })
        #expect(desk.received(request, when: conditions) == .needsApp)
        #expect(!asked.wasAsked)
    }

    /// The full cycle, which every other test implies and none asserted: a desk that has answered
    /// one question takes the next.
    @Test("A desk that answered one request accepts the next")
    func theDeskTakesAnotherAfterAnswering() throws {
        var desk = ProvisioningDesk()
        let (first, firstNonce) = try request()
        let (second, secondNonce) = try request()

        #expect(desk.received(first, when: ready) == .asking)
        _ = desk.approve()

        #expect(desk.received(second, when: ready) == .asking, "not busy: the desk is clear")
        #expect(desk.pendingNonce == secondNonce)
        #expect(desk.pendingNonce != firstNonce)
    }
}
