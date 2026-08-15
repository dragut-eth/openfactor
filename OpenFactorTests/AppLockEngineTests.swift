import Foundation
import Testing

@testable import OpenFactor

/// The lock decisions, walked through every sequence that matters.
///
/// The engine is pure so these can be exhaustive: no simulator, no biometrics, no clock.
/// Time is a parameter, which is the same discipline `TOTP` is tested with. What cannot be
/// tested here, the Face ID prompt and the shield window, is kept thin enough to read.
@Suite("App lock engine")
struct AppLockEngineTests {

    private let launch = Date(timeIntervalSince1970: 1_700_000_000)

    private func after(_ seconds: TimeInterval) -> Date {
        launch.addingTimeInterval(seconds)
    }

    @Test("A cold launch starts locked when the lock is enabled")
    func coldLaunchLocks() {
        #expect(AppLockEngine(enabled: true).isLocked)
        #expect(!AppLockEngine(enabled: false).isLocked)
    }

    @Test("Returning within the grace period stays unlocked")
    func graceHolds() {
        var engine = AppLockEngine(enabled: false)
        engine.appDidBackground(at: after(10))
        engine.appWillForeground(at: after(40), enabled: true, gracePeriod: 60)

        #expect(!engine.isLocked)
    }

    @Test("Returning after the grace period locks")
    func graceExpires() {
        var engine = AppLockEngine(enabled: false)
        engine.appDidBackground(at: after(10))
        engine.appWillForeground(at: after(100), enabled: true, gracePeriod: 60)

        #expect(engine.isLocked)
    }

    /// The boundary belongs to the lock. Exactly the grace period away is away.
    @Test("Returning exactly at the grace period locks")
    func boundaryLocks() {
        var engine = AppLockEngine(enabled: false)
        engine.appDidBackground(at: after(10))
        engine.appWillForeground(at: after(70), enabled: true, gracePeriod: 60)

        #expect(engine.isLocked)
    }

    /// "Immediately" means any time away at all, including none: a zero grace period
    /// locks even if background and foreground carry the same timestamp.
    @Test("A zero grace period locks on any background at all")
    func immediatelyMeansImmediately() {
        var engine = AppLockEngine(enabled: false)
        engine.appDidBackground(at: after(10))
        engine.appWillForeground(at: after(10), enabled: true, gracePeriod: 0)

        #expect(engine.isLocked)
    }

    /// A clock that moved backwards while the app was away is indistinguishable from
    /// tampering, so it locks. The cost of being wrong is one unlock prompt.
    @Test("A clock that went backwards locks")
    func rewoundClockLocks() {
        var engine = AppLockEngine(enabled: false)
        engine.appDidBackground(at: after(100))
        engine.appWillForeground(at: after(10), enabled: true, gracePeriod: 300)

        #expect(engine.isLocked)
    }

    @Test("Disabled means never locked, whatever happens")
    func disabledNeverLocks() {
        var engine = AppLockEngine(enabled: false)
        engine.appDidBackground(at: after(10))
        engine.appWillForeground(at: after(100_000), enabled: false, gracePeriod: 0)

        #expect(!engine.isLocked)
    }

    /// Enabling mid session does not lock the person who just enabled it. The lock takes
    /// hold at the next background, which is the first moment the phone could have changed
    /// hands.
    @Test("Enabling mid session locks at the next background, not at once")
    func enablingMidSessionWaitsForBackground() {
        var engine = AppLockEngine(enabled: false)
        #expect(!engine.isLocked)

        engine.appDidBackground(at: after(10))
        engine.appWillForeground(at: after(20), enabled: true, gracePeriod: 0)

        #expect(engine.isLocked)
    }

    /// The earliest background wins when the system reports more than one, because the
    /// user has been away since the first.
    @Test("Repeated background events keep the earliest moment")
    func earliestBackgroundWins() {
        var engine = AppLockEngine(enabled: false)
        engine.appDidBackground(at: after(0))
        engine.appDidBackground(at: after(50))
        engine.appWillForeground(at: after(60), enabled: true, gracePeriod: 60)

        #expect(engine.isLocked)
    }

    @Test("Unlocking unlocks, and the next cycle can lock again")
    func unlockThenRelock() {
        var engine = AppLockEngine(enabled: true)
        #expect(engine.isLocked)

        engine.unlock()
        #expect(!engine.isLocked)

        engine.appDidBackground(at: after(10))
        engine.appWillForeground(at: after(20), enabled: true, gracePeriod: 0)
        #expect(engine.isLocked)
    }

    /// A foreground with no background before it, which is what the first activation of a
    /// cold launch looks like, decides nothing: the launch state already did.
    @Test("Foreground without a background changes nothing")
    func foregroundAloneIsInert() {
        var engine = AppLockEngine(enabled: false)
        engine.appWillForeground(at: after(10), enabled: true, gracePeriod: 0)

        #expect(!engine.isLocked)
    }
}
