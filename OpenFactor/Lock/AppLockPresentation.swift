import Foundation
import SwiftUI

/// Decides what stands between the interface and the world. Nothing else.
///
/// `AppLockEngine` decides *whether* the app is locked; this type decides what that looks
/// like, and it exists because every defect in the first attempt at PR 15b lived in
/// imperative glue making these decisions ad hoc. It is a value type in the engine's own
/// style: no clock, no UIKit, no LocalAuthentication. Events go in, three booleans come
/// out, and `docs/APP_LOCK.md` is the normative description of both.
///
/// **The three surfaces it drives:**
/// - `presentsRootLock`: the lock screen *is* the root view. Only for a lock that began at
///   launch, where no interface exists to preserve and where creating a window mid launch
///   transition once latched the wrong orientation.
/// - `lockWindowVisible`: the lock screen in a window above the interface. For every lock
///   of a running app, so the view tree beneath survives untouched: same screens, same
///   sheets, same half typed text after unlock.
/// - `coverVisible`: the blank surface the app switcher photographs. For an unlocked app
///   that is not active, because the photograph must never contain a code.
struct AppLockPresentation: Equatable {

    /// The lock decision itself, unchanged from PR 15 and separately tested.
    private var engine: AppLockEngine

    /// Whether the current locked spell began at launch. True from a locked launch until
    /// the first successful unlock, and never true again for the life of the process:
    /// every later lock finds an interface worth preserving, so every later lock is a
    /// window. A lock enabled mid run starts unlocked, so it is never cold either.
    private var coldLock: Bool

    /// An unlock succeeded while the scene was not yet active, and the cover must not
    /// fire in the gap. Face ID runs with the scene inactive, so the moment of success
    /// satisfies the naive cover condition, and the first attempt flashed the cover,
    /// black in dark mode, on every unlock.
    ///
    /// **Cleared by every departure event**, not only by settling. The first attempt's
    /// flag was cleared only by later phase events, and when it stuck, the next
    /// backgrounding silently skipped the cover and the switcher photographed the real
    /// interface. A stale flag here can cost one cosmetic frame; it can never cost the
    /// photograph. Sequence B3 in `docs/APP_LOCK.md`, and the reason this PR was
    /// specified before being rebuilt.
    private var settling = false

    /// Whether the unlock prompt has been offered for the current locked spell, so
    /// returning from the Face ID overlay does not immediately re-raise it. Reset when
    /// the app backgrounds, which is what makes the next locked return prompt again.
    private var hasPrompted = false

    /// Where the scene last was, tracked from events rather than read from SwiftUI,
    /// because the decisions below depend on it and a pure type cannot ask.
    private var phase: Phase

    enum Phase: Equatable {
        /// Launch, before any scene event. Not `inactive`: nothing has been shown yet,
        /// and the cover must not try to exist before the interface does.
        case launching
        case active
        case inactive
        case background
    }

    init(lockEnabled: Bool) {
        engine = AppLockEngine(enabled: lockEnabled)
        coldLock = lockEnabled
        phase = .launching
    }

    // MARK: - Outputs

    var isLocked: Bool { engine.isLocked }

    /// The lock screen as the root view. Cold locks only.
    var presentsRootLock: Bool { engine.isLocked && coldLock }

    /// The lock screen in a window above the untouched interface. Warm locks only.
    var lockWindowVisible: Bool { engine.isLocked && !coldLock }

    /// The blank surface for the app switcher. Never while locked, because the lock,
    /// root or window, is what belongs in the photograph and it has a button. Never
    /// while settling, see `settling`. Never at launch, because there is no interface
    /// to hide and no window scene to hang a cover on yet.
    var coverVisible: Bool {
        !engine.isLocked && !settling && phase != .active && phase != .launching
    }

    /// Whether the prompt should be raised without a tap, once per locked spell.
    var shouldAutoPrompt: Bool { engine.isLocked && !hasPrompted }

    // MARK: - Events

    /// The scene left `.active`. A departure, so any pending cover suppression ends now:
    /// whatever happens next, the switcher must get the cover, not the interface.
    mutating func willResignActive() {
        settling = false
        phase = .inactive
    }

    /// The scene reached `.background`. Also a departure, and the moment the engine
    /// starts counting time away.
    mutating func didEnterBackground(at date: Date) {
        engine.appDidBackground(at: date)
        settling = false
        hasPrompted = false
        phase = .background
    }

    /// The scene left `.background` on its way forward. Bookkeeping only: the lock
    /// decision waits for `.active`, because the grace period cannot be judged until
    /// the return is real.
    mutating func willEnterForeground() {
        phase = .inactive
    }

    /// SwiftUI reports both directions of `.inactive` as the same value. The type knows
    /// which it was, because it knows where the scene last stood, so the controller
    /// sends this and the right event fires. From `.active` it is a resignation; from
    /// `.background` it is a return in transit; at launch it is the launch transition,
    /// which is neither.
    mutating func sceneBecameInactive() {
        switch phase {
        case .active:
            willResignActive()
        case .background:
            willEnterForeground()
        case .launching, .inactive:
            break
        }
    }

    /// The scene reached `.active`. The one moment a lock can be added, never removed:
    /// the engine judges the time away, and an unlocked app that was gone long enough
    /// locks here. `coldLock` is untouched on purpose, in both directions. A cold lock
    /// that was never unlocked stays cold through any number of returns, because the
    /// interface still does not exist; and a warm app that locks here was unlocked a
    /// moment ago, so `coldLock` is already false.
    mutating func didBecomeActive(at date: Date, enabled: Bool, gracePeriod: TimeInterval) {
        engine.appWillForeground(at: date, enabled: enabled, gracePeriod: gracePeriod)
        settling = false
        phase = .active
    }

    /// The unlock prompt went up. Marked before anything awaits, so a second caller in
    /// the same runloop sees `shouldAutoPrompt` already false and one prompt is raised,
    /// not two.
    mutating func promptRaised() {
        hasPrompted = true
    }

    /// The person proved they are the owner. The cold spell, if this ended one, is over
    /// for the life of the process.
    ///
    /// **Settling is set only when the scene stands at `.inactive`**, which is the Face
    /// ID gap and nothing else. The first cut wrote `phase != .active`, and an
    /// adversarial review found the sequence that turns the difference into a leak: a
    /// success that lands after the app has already reached the background, a biometric
    /// match racing a swipe home, would have suppressed the cover and hidden the lock
    /// window while the app was photographable, with nothing behind it. A background
    /// unlock has no gap to bridge, so it gets the cover like any other departure.
    /// Sequence 10 in `docs/APP_LOCK.md`.
    ///
    /// The guard makes a second success idempotent. Two prompts can be in flight, the
    /// auto prompt and the button, and only the first outcome may move state: the
    /// second used to be able to re-arm `settling` with no apply behind it.
    mutating func unlockSucceeded() {
        guard engine.isLocked else { return }
        engine.unlock()
        coldLock = false
        settling = phase == .inactive
    }

    /// Cancelled or failed. Locked is already the right state; nothing changes.
    mutating func unlockFailed() {}
}
