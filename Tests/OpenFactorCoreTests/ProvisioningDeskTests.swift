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

    private let ready = ProvisioningDesk.Conditions(isFrontmost: true, hasVault: true)

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

        let conditions = ProvisioningDesk.Conditions(isFrontmost: false, hasVault: true)
        #expect(desk.received(request, when: conditions) == .needsApp)
        #expect(!desk.isAsking, "and nothing is left on the desk")
    }

    @Test("A phone with no vault says so")
    func noVaultIsSaidSo() throws {
        var desk = ProvisioningDesk()
        let (request, _) = try request()

        let conditions = ProvisioningDesk.Conditions(isFrontmost: true, hasVault: false)
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
}
