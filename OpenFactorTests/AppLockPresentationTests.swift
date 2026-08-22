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
    /// **This test asserted the opposite until 2026-08-22, and the reversal is the fix.**
    ///
    /// It required the cover to stay down between a successful unlock and the scene becoming
    /// active, so that no cover flashed on every unlock. On a device that window is two to
    /// three seconds with the account list on screen, and a departure inside it produces no
    /// resignation at all, because an app that was never active cannot resign. The first signal
    /// is `didEnterBackground`, after the system has photographed the screen. **The flash this
    /// assertion prevented was the leak.**
    @Test("An unlock landing while inactive holds the cover until the scene is active")
    func unlockDuringFaceIDGapHoldsTheCover() {
        var p = returned(after: 300)
        #expect(p.lockWindowVisible)

        p.promptRaised()
        p.willResignActive()  // Face ID takes the scene.
        #expect(p.coverVisible, "covered beneath the lock window, which is what is seen")

        p.unlockSucceeded()  // Lands while the scene is inactive.
        #expect(!p.lockWindowVisible)
        #expect(p.coverVisible, "held: unlocked but not yet active, so nothing may be photographed")

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

    /// **The defect this suite could not see, and why.**
    ///
    /// `departureAfterUnlockAlwaysCovers` above calls `willResignActive()` directly and has
    /// always passed. The app could not reach it. SwiftUI reports scene phase *changes*, and
    /// after a Face ID unlock the scene is already `.inactive`; when the return to `.active` is
    /// not delivered, a real departure is not a change and **nothing arrives at all** until
    /// `.background`, which is after the system has photographed the screen.
    ///
    /// Measured on an iPhone 15 Pro on 2026-08-22: an unlock at t=42.139, no `.active` for six
    /// seconds, then `.background` as the first event. Two of three unlocks in that trace got
    /// their `.active` back and one did not, which is why it looked intermittent.
    ///
    /// **So the presentation was right and the delivery was wrong**, and a suite that only ever
    /// calls the presentation directly cannot tell the difference. This test pins the shape of
    /// the gap so that nobody removes the system notification on the grounds that scene phase
    /// already covers it.
    @Test("A departure inside the post unlock window needs no signal at all")
    func aDepartureNeedsNoSignalBecauseTheCoverNeverCameDown() {
        var p = returned(after: 300)

        // The Face ID dip, which puts the scene at inactive and keeps it there.
        p.sceneBecameInactive()
        p.promptRaised()
        p.unlockSucceeded()

        // The scene never returns to active, and the person leaves. What SwiftUI delivers is
        // the same value again, which is correctly treated as nothing. **It no longer matters**:
        // the cover has been up since the unlock, so there is no moment left to miss.
        p.sceneBecameInactive()
        #expect(p.coverVisible, "nothing to catch on the way out, because nothing was uncovered")
    }

    /// Sequence 9: the settle window closes on departure even when the scene never
    /// reached active in between. Unlock, then leave immediately.
    @Test("An unlock followed by an immediate background still covers")
    func unlockThenImmediateBackgroundCovers() {
        var p = returned(after: 300)
        p.promptRaised()
        p.willResignActive()
        p.unlockSucceeded()
        #expect(p.coverVisible, "held from the unlock, so leaving cannot outrun it")

        p.didEnterBackground(at: launch.addingTimeInterval(301))
        #expect(p.coverVisible, "and it is still up on the way out")
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

        // A hundred seconds away against a sixty second grace, so the return re-locks. Under
        // the one invariant that means still covered, beneath the lock window.
        p.didBecomeActive(at: launch.addingTimeInterval(400), enabled: true, gracePeriod: grace)
        #expect(p.isLocked)
        #expect(p.coverVisible, "re-locked on return, so covered under the lock window")
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
    /// **The "and not the cover" half was removed on 2026-08-22, and it was encoding a leak.**
    ///
    /// The cover and the lock window were treated as alternatives, so a locked return lowered
    /// one and raised the other in the same update, and whether anything showed depended on the
    /// lock window drawing in time. A device caught it not doing so: the codes were on screen
    /// between the app becoming active and the Face ID prompt appearing, which in one measured
    /// case was two and a half seconds. The lock window sits above the cover, so keeping both up
    /// looks identical and removes the window entirely.
    @Test("A locked return is a window rather than the root, and covered beneath it")
    func lockedReturnIsAWindow() {
        let p = returned(after: 300)
        #expect(p.lockWindowVisible)
        #expect(!p.presentsRootLock)
        #expect(p.coverVisible, "beneath the lock window, so nothing can show if it draws late")
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
        #expect(p.coverVisible, "the lock surface is what shows, with the cover behind it")
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
