import QuartzCore
import SwiftUI
import UIKit

/// The two windows above every other window: the snapshot cover, and the lock screen for
/// a lock that arrives while the app is running.
///
/// **Why windows and not overlays.** Both surfaces have to sit above whatever is showing,
/// and "whatever is showing" includes sheets: settings, the scanner, and manual entry,
/// which has a secret in a text field. A SwiftUI overlay at the root sits *under*
/// presented sheets, so a lock drawn that way would leave an open sheet readable, and the
/// app switcher snapshot of a backgrounded app would keep whatever the sheet was showing.
/// A `UIWindow` at a raised level is the mechanism the system itself uses for things that
/// outrank the interface, and this is the only place in the app that touches UIKit
/// windows.
///
/// **The snapshot is why the cover exists at all, lock or no lock.** iOS photographs the
/// app as it leaves the foreground and shows that photograph in the app switcher to
/// anyone flicking through. Without the cover that photograph contains live codes and
/// account names. The cover is therefore not part of App Lock and checks no setting.
///
/// **The lock window is why typed text survives a lock.** A lock used to replace the root
/// view, which destroyed every screen, sheet, and half typed field beneath it; four
/// losses were found in the field in one day, all that one cause. A window above the
/// interface locks just as thoroughly and destroys nothing. Cold launches still lock as
/// the root, because no interface exists yet and because a window created mid launch
/// transition was measured latching the wrong orientation. `docs/APP_LOCK.md` is the
/// design; `AppLockPresentation` makes the decisions; this enum only applies them.
@MainActor
enum PrivacyShield {

    private static var cover: UIWindow?
    private static var lock: UIWindow?

    /// Applies the presentation's decisions to the two windows, in the one order that is
    /// safe: **whatever must be visible is shown before anything is hidden.** On a locked
    /// return the lock window goes up and the cover comes down in the same update, and
    /// hiding first would leave a gap with the live interface visible in it, which is the
    /// exact frame leak these windows exist to prevent.
    ///
    /// Every call site goes through here rather than touching a window directly, because
    /// the ordering is an invariant and an invariant spread across call sites is how the
    /// first attempt at PR 15b shipped its frame leak.
    static func apply(_ controller: AppLockController) {
        #if DEBUG
            controller.debugTrace("apply IN", coverWindow: debugCoverState)
        #endif
        if controller.lockWindowVisible {
            showLock(controller)
        }
        setCovered(controller.coverVisible)
        if !controller.lockWindowVisible {
            lock?.isHidden = true
        }
        #if DEBUG
            controller.debugTrace("apply OUT", coverWindow: debugCoverState)
        #endif
    }

    #if DEBUG
        /// What the cover window actually is at this instant, which no other type can see.
        ///
        /// **`none` on the first departure of a process is worth watching for**, because the
        /// window and its hosting controller are built lazily here, and the sibling lock window's
        /// comment records that a freshly built hosting controller's first frame can land after
        /// the system has already taken its photograph.
        static var debugCoverState: String {
            guard let cover else { return "none" }
            if cover.isHidden { return "hidden" }
            return cover.alpha > 0 ? "shown" : "clear"
        }
    #endif

    /// Shows the lock window, creating it on first use.
    ///
    /// **Created here and never at launch**, which is safe by construction: the only
    /// event that makes `lockWindowVisible` true is a lock decided at `.active`, so the
    /// scene is settled and the orientation latch cannot recur. The window and its
    /// hosting controller are built once and kept, hidden rather than torn down;
    /// rebuilding per lock is what leaked one frame of the interface in the first
    /// attempt, because a fresh hosting controller's first frame landed after the
    /// window was already visible.
    ///
    /// The auto prompt is driven from here, on the transition to visible, because the
    /// kept view's `.task` fires once per identity and the identity never changes
    /// again. `shouldAutoPrompt` is checked inside the task, on the main actor, and
    /// `requestUnlock` marks itself before anything awaits, so this and the root lock
    /// screen's own `.task` can never raise two prompts between them.
    private static func showLock(_ controller: AppLockController) {
        if lock == nil {
            guard let scene = foregroundScene else { return }

            let window = UIWindow(windowScene: scene)
            // Above the cover, so if an ordering slip ever shows both, the surface with
            // the button wins. Both outrank alerts, which can carry account names.
            window.windowLevel = .alert + 2
            window.rootViewController = UIHostingController(
                rootView: LockScreenView(controller: controller))
            lock = window
        }

        guard let lock else { return }
        let wasHidden = lock.isHidden
        lock.isHidden = false

        if wasHidden {
            Task {
                if controller.shouldAutoPrompt {
                    await controller.requestUnlock()
                }
            }
        }
    }

    /// Covers everything with a blank surface, or uncovers it.
    ///
    /// The window and its content are built once and kept, then hidden rather than torn
    /// down. Replacing the root controller per change with a clear background had a one
    /// frame gap during the swap where the interface showed through, which is exactly
    /// the flash this window exists to prevent. It is only ever shown by an app that
    /// was just active and settled, so it has no launch moment to get wrong.
    /// Builds the cover window before it is first needed, and does nothing if it exists.
    ///
    /// **The first departure of a process used to pay for this**, and it is the one moment that
    /// cannot afford it: a `UIWindow`, a `UIHostingController`, and a first layout pass, all
    /// racing a photograph the system takes on its own schedule. The sibling lock window is
    /// already built once and kept for exactly this reason, and its comment records that a fresh
    /// hosting controller's first frame landed after the system had finished. The cover never
    /// got the same treatment.
    ///
    /// Called when the scene settles at active, never at launch: a window created mid launch
    /// transition was measured latching the wrong orientation.
    static func prepareCover() {
        guard cover == nil, let scene = foregroundScene else { return }

        let shield = UIWindow(windowScene: scene)
        shield.windowLevel = .alert + 1
        shield.rootViewController = UIHostingController(rootView: CoverView())

        // **Visible from the moment it is built, and transparent.** `isHidden = false` is not a
        // free operation: it orders the window in and schedules a render, and the render is what
        // has to have happened before the system photographs the screen. A window that is
        // already in the hierarchy and already drawn needs only an opacity change, which the
        // render server can do without laying anything out.
        //
        // **Sits below the lock window**, which is `.alert + 2`, so a locked app still shows the
        // lock screen rather than this.
        //
        // Touches pass through, because a permanently visible window that swallowed them would
        // be a far worse bug than the one this is fixing.
        shield.alpha = 0
        shield.isUserInteractionEnabled = false
        shield.isHidden = false
        cover = shield
    }

    private static func setCovered(_ covered: Bool) {
        guard covered else {
            // **Lowered without forcing a commit, and that asymmetry is the point.** Raising has
            // a deadline set by the system's photograph. Lowering has none, and flushing it
            // committed the cover's removal on its own instead of in the same transaction as
            // whatever replaces it. On a locked return that replacement is the lock window, and
            // a measured sequence on 2026-08-22 had two and a half seconds between the app
            // becoming active and the Face ID prompt appearing, with the codes on screen for it.
            //
            // A cover that leaves one frame late costs nothing. A cover that leaves one frame
            // early costs the thing this file exists for.
            cover?.alpha = 0
            return
        }

        // Still built here if it somehow does not exist, because a cover that is late is
        // better than a cover that never comes. `prepareCover` is what makes that rare.
        prepareCover()
        cover?.alpha = 1

        // **Committed now rather than at the end of the run loop.** Everything above only
        // schedules work. The system takes its photograph on its own schedule, and a measured
        // sequence on 2026-08-22 had the cover raised at `didEnterBackground` and the switcher
        // still holding the interface, which is what an uncommitted change looks like.
        //
        // This is the one place in the app that forces a commit, and it is here because it is
        // the one place where being one frame late is the whole failure.
        CATransaction.flush()
    }

    /// **This assumes the app has exactly one window scene, and that assumption is enforced
    /// elsewhere rather than hoped for.**
    ///
    /// Taking `.first` of a set is meaningless if there can be two. Gate A4 found the app
    /// shipping with `UIApplicationSupportsMultipleScenes = true` while this enum kept one lock
    /// and one cover: on an iPad with two OpenFactor windows, the second had no cover in the app
    /// switcher and no lock over it, contradicting `SECURITY.md` and `docs/APP_LOCK.md` in their
    /// own words.
    ///
    /// Multiple scenes are now declared `false` in `OpenFactor-Info.plist`, which says why, and
    /// CI fails if that ever flips back. **If you are re-enabling multiple windows, this is the
    /// code that breaks**, and the fix is a lock and a cover per scene keyed by scene identity,
    /// with lifecycle events routed per scene and teardown on disconnect.
    private static var foregroundScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }
}

/// The blank surface the app switcher photographs.
private struct CoverView: View {
    var body: some View {
        Tokens.Surface.background
            .ignoresSafeArea()
    }
}

/// The lock screen. A surface, a mark, and the one button.
///
/// It draws nothing that was behind it and names nothing the owner would recognise,
/// because it is also what the app switcher shows while locked. Used in two places: as
/// the root view for a cold lock, where its `.task` runs the auto prompt, and inside the
/// kept lock window, where the `.task` fires only once and `PrivacyShield` prompts on
/// each later show instead. Both paths check `shouldAutoPrompt` first, so they cannot
/// both fire.
struct LockScreenView: View {
    let controller: AppLockController

    var body: some View {
        ZStack {
            Tokens.Surface.background
                .ignoresSafeArea()

            VStack(spacing: Tokens.Spacing.large) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                if let reason = controller.unlockImpossibleReason {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Tokens.Spacing.large)
                } else {
                    Button("Unlock") {
                        Task { await controller.requestUnlock() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task {
            if controller.shouldAutoPrompt {
                await controller.requestUnlock()
            }
        }
    }
}
