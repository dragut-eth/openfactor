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
        if controller.lockWindowVisible {
            showLock(controller)
        }
        setCovered(controller.coverVisible)
        if !controller.lockWindowVisible {
            lock?.isHidden = true
        }
    }

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
    private static func setCovered(_ covered: Bool) {
        guard covered else {
            cover?.isHidden = true
            return
        }

        if cover == nil {
            guard let scene = foregroundScene else { return }

            let shield = UIWindow(windowScene: scene)
            shield.windowLevel = .alert + 1
            shield.rootViewController = UIHostingController(rootView: CoverView())
            cover = shield
        }

        cover?.isHidden = false
    }

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
