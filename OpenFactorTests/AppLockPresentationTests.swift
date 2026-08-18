import Foundation
import Testing

@testable import OpenFactor

/// The presentation decisions, walked through the sequences `docs/APP_LOCK.md` requires.
///
/// The first three tests are the first attempt's defects, kept as tests so they cannot
/// return: the frame leak is a glue invariant and lives on the manual checklist, but the
/// black flash and the snapshot leak were both decisions, and both are decidable here
/// without a simulator. **Test three is the one that matters.** Its failure photographed
/// the real interface into the app switcher, which is the exact property the lock exists
/// to protect, and it is the reason this PR was specified before being rebuilt.
@Suite("App lock presentation")
struct AppLockPresentationTests {

    private let launch = Date(timeIntervalSince1970: 1_000_000)
    private let grace: TimeInterval = 60

    /// A presentation that launched unlocked and settled to active.
    private func activeUnlocked(enabled: Bool = true) -> AppLockPresentation {
        var p = AppLockPresentation(lockEnabled: false)
        p.sceneBecameInactive()
        p.didBecomeActive(at: launch, enabled: enabled, gracePeriod: grace)
        return p
    }

    /// Walks an unlocked, active presentation through a real departure and a return
    /// after `away` seconds, and hands it back at the moment of `.active`.
    private func returned(after away: TimeInterval, enabled: Bool = true) -> AppLockPresentation {
        var p = activeUnlocked(enabled: enabled)
        p.willResignActive()
        p.didEnterBackground(at: launch)
        p.willEnterForeground()
        p.didBecomeActive(at: launch.addingTimeInterval(away), enabled: enabled, gracePeriod: grace)
        return p
    }

    // MARK: - The first attempt's defects, as required regressions

    /// Sequence B2: the black flash. Face ID runs with the scene inactive, so a
    /// successful unlock lands before `.active`, and the naive cover condition holds in
    /// the gap. The cover must not fire there, and must reach the steady state once the
    /// scene settles.
    @Test("An unlock landing while inactive never shows the cover in the gap")
    func unlockDuringFaceIDGapSuppressesTheCover() {
        var p = returned(after: 300)
        #expect(p.lockWindowVisible)

        p.promptRaised()
        p.willResignActive()  // Face ID takes the scene.
        #expect(!p.coverVisible, "the lock is still the surface while the prompt is up")

        p.unlockSucceeded()  // Lands while the scene is inactive.
        #expect(!p.lockWindowVisible)
        #expect(!p.coverVisible, "the flash: unlocked and inactive, but settling")

        p.didBecomeActive(at: launch.addingTimeInterval(301), enabled: true, gracePeriod: grace)
        #expect(!p.coverVisible)
        #expect(!p.isLocked)
    }

    /// Sequence B3, the one that mattered. An unlock with no inactive dip leaves the
    /// suppression armed, and if a departure does not clear it, the next backgrounding
    /// skips the cover and the switcher photographs the real interface. Every departure
    /// clears it, so the cover can never be skipped on the way out.
    @Test("A departure after any unlock always shows the cover")
    func departureAfterUnlockAlwaysCovers() {
        var p = returned(after: 300)
        p.promptRaised()
        p.unlockSucceeded()  // No resign first: Face ID without the dip.

        p.willResignActive()
        #expect(p.coverVisible, "the snapshot leak: this exact read is what regressed")

        // And the same holds when the departure goes all the way to background.
        p.didEnterBackground(at: launch.addingTimeInterval(302))
        #expect(p.coverVisible)
    }

    /// Sequence 9: the settle window closes on departure even when the scene never
    /// reached active in between. Unlock, then leave immediately.
    @Test("An unlock followed by an immediate background still covers")
    func unlockThenImmediateBackgroundCovers() {
        var p = returned(after: 300)
        p.promptRaised()
        p.willResignActive()
        p.unlockSucceeded()
        #expect(!p.coverVisible, "settling")

        p.didEnterBackground(at: launch.addingTimeInterval(301))
        #expect(p.coverVisible, "the departure ends the settle window")
    }

    /// Sequence 10: an unlock that lands after the app has already reached the
    /// background, a biometric match racing a swipe home. Found by adversarial review
    /// before this build reached a phone: with `settling` keyed on "not active" instead
    /// of "inactive", this sequence suppressed the cover and hid the lock window while
    /// the app was photographable, with nothing behind it. A background unlock has no
    /// Face ID gap to bridge, so it must cover like any other departure, and the cover
    /// must hold through the return transit.
    @Test("An unlock landing after backgrounding covers immediately")
    func unlockLandingInBackgroundCovers() {
        var p = returned(after: 300)
        p.promptRaised()
        p.willResignActive()  // Face ID takes the scene.
        p.didEnterBackground(at: launch.addingTimeInterval(301))  // Person leaves mid prompt.
        #expect(p.lockWindowVisible, "still locked, the lock is the photograph")

        p.unlockSucceeded()  // The success lands late.
        #expect(!p.isLocked)
        #expect(!p.lockWindowVisible)
        #expect(p.coverVisible, "the counterexample: this read is what the review caught")

        p.willEnterForeground()
        #expect(p.coverVisible, "and it holds through the return transit")

        p.didBecomeActive(at: launch.addingTimeInterval(400), enabled: true, gracePeriod: grace)
        #expect(!p.coverVisible)
    }

    /// A second success may not move state. Two prompts can be in flight, the auto
    /// prompt and the button, and the late outcome used to be able to re-arm the cover
    /// suppression with nothing applying the result.
    @Test("A second unlock outcome changes nothing")
    func secondUnlockOutcomeIsInert() {
        var p = returned(after: 300)
        p.promptRaised()
        p.willResignActive()
        p.unlockSucceeded()
        p.didBecomeActive(at: launch.addingTimeInterval(301), enabled: true, gracePeriod: grace)

        let settled = p
        p.willResignActive()
        var late = p
        late.unlockSucceeded()  // The straggler resolves after the scene moved on.
        #expect(late == p)
        #expect(late.coverVisible == true)
        #expect(settled != p, "the resign itself was a real event; only the straggler is inert")
    }

    // MARK: - The two kinds of lock

    /// Sequence 4: a lock that begins at launch is the root, not a window. There is no
    /// interface to preserve and no settled scene to hang a window on.
    @Test("A cold launch locks as the root")
    func coldLaunchIsRootLock() {
        var p = AppLockPresentation(lockEnabled: true)
        #expect(p.presentsRootLock)
        #expect(!p.lockWindowVisible)
        #expect(!p.coverVisible)

        // The launch transition changes nothing about that.
        p.sceneBecameInactive()
        p.didBecomeActive(at: launch, enabled: true, gracePeriod: grace)
        #expect(p.presentsRootLock)
        #expect(!p.lockWindowVisible)
    }

    /// A cold lock that was never unlocked stays the root through any number of
    /// returns. The interface has still never existed, so there is nothing for a
    /// window to preserve.
    @Test("A cold lock stays the root across a background and return")
    func coldLockStaysColdWithoutAnUnlock() {
        var p = AppLockPresentation(lockEnabled: true)
        p.sceneBecameInactive()
        p.didBecomeActive(at: launch, enabled: true, gracePeriod: grace)
        p.willResignActive()
        p.didEnterBackground(at: launch)
        p.willEnterForeground()
        p.didBecomeActive(at: launch.addingTimeInterval(600), enabled: true, gracePeriod: grace)

        #expect(p.presentsRootLock)
        #expect(!p.lockWindowVisible)
    }

    /// Sequence 5: a lock on return is a window over the untouched interface, and the
    /// cover is not also up, because the lock is what belongs in the photograph.
    @Test("A locked return is a window, not the root, and not the cover")
    func lockedReturnIsAWindow() {
        let p = returned(after: 300)
        #expect(p.lockWindowVisible)
        #expect(!p.presentsRootLock)
        #expect(!p.coverVisible)
    }

    /// Once a cold lock is unlocked, the cold spell is over for the life of the
    /// process. Every later lock finds an interface worth preserving.
    @Test("After the first unlock, every lock is a window")
    func everyLockAfterTheFirstUnlockIsWarm() {
        var p = AppLockPresentation(lockEnabled: true)
        p.sceneBecameInactive()
        p.didBecomeActive(at: launch, enabled: true, gracePeriod: grace)
        p.promptRaised()
        p.unlockSucceeded()

        p.willResignActive()
        p.didEnterBackground(at: launch.addingTimeInterval(10))
        p.willEnterForeground()
        p.didBecomeActive(at: launch.addingTimeInterval(700), enabled: true, gracePeriod: grace)

        #expect(p.lockWindowVisible)
        #expect(!p.presentsRootLock)
    }

    // MARK: - The engine's decisions, reaching the surfaces

    /// Sequence 6: within grace nothing locks, and the cover drops once active.
    @Test("A return within grace does not lock, and uncovers on arrival")
    func returnWithinGraceStaysOpen() {
        var p = activeUnlocked()
        p.willResignActive()
        p.didEnterBackground(at: launch)
        #expect(p.coverVisible)

        p.willEnterForeground()
        #expect(p.coverVisible, "still covered in transit")

        p.didBecomeActive(at: launch.addingTimeInterval(5), enabled: true, gracePeriod: grace)
        #expect(!p.isLocked)
        #expect(!p.coverVisible)
    }

    /// Sequence 7: a clock that moved backwards while the app was away locks, exactly
    /// as the engine already promises. Asserted here because the presentation is now
    /// what turns that promise into a visible surface.
    @Test("A clock moved backwards locks the return")
    func clockBackwardsLocks() {
        var p = activeUnlocked()
        p.willResignActive()
        p.didEnterBackground(at: launch)
        p.willEnterForeground()
        p.didBecomeActive(at: launch.addingTimeInterval(-3600), enabled: true, gracePeriod: grace)

        #expect(p.isLocked)
        #expect(p.lockWindowVisible)
    }

    /// Sequence 8: backgrounding mid Face ID, still locked. The lock surface remains
    /// and the cover stays off, so the photograph is the lock screen, which is safe and
    /// has a button. The documented stance, now asserted.
    @Test("Backgrounding while still locked keeps the lock as the photograph")
    func backgroundingWhileLockedKeepsTheLockSurface() {
        var p = returned(after: 300)
        p.promptRaised()
        p.willResignActive()  // Face ID up, person leaves instead.
        p.didEnterBackground(at: launch.addingTimeInterval(301))

        #expect(p.isLocked)
        #expect(p.lockWindowVisible)
        #expect(!p.coverVisible)
    }

    /// The lock disabled means no lock and an ordinary cover, whatever the timing.
    @Test("Disabled, a long absence covers and never locks")
    func disabledNeverLocks() {
        var p = returned(after: 100_000, enabled: false)
        #expect(!p.isLocked)
        #expect(!p.lockWindowVisible)
        #expect(!p.presentsRootLock)
        #expect(!p.coverVisible, "active again, so uncovered")
    }

    // MARK: - The prompt

    /// One prompt per locked spell, and marking is synchronous: the second caller in
    /// the same runloop sees it already marked.
    @Test("The prompt is offered once per locked spell")
    func promptOncePerSpell() {
        var p = returned(after: 300)
        #expect(p.shouldAutoPrompt)

        p.promptRaised()
        #expect(!p.shouldAutoPrompt)

        // A cancelled prompt does not re-arm within the spell.
        p.unlockFailed()
        #expect(!p.shouldAutoPrompt)

        // A new departure and locked return is a new spell.
        p.promptRaised()
        p.unlockSucceeded()
        p.willResignActive()
        p.didEnterBackground(at: launch.addingTimeInterval(400))
        p.willEnterForeground()
        p.didBecomeActive(at: launch.addingTimeInterval(1000), enabled: true, gracePeriod: grace)
        #expect(p.shouldAutoPrompt)
    }

    /// Nothing at launch shows a cover: there is no interface to hide and no window
    /// scene yet to hang one on.
    @Test("Launch never shows the cover")
    func launchNeverCovers() {
        let locked = AppLockPresentation(lockEnabled: true)
        #expect(!locked.coverVisible)

        var unlocked = AppLockPresentation(lockEnabled: false)
        #expect(!unlocked.coverVisible)
        unlocked.sceneBecameInactive()
        #expect(!unlocked.coverVisible, "the launch transition is not a departure")
    }
}
