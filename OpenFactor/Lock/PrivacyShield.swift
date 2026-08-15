import SwiftUI
import UIKit

/// A window above every other window, for the two screens that must cover everything.
///
/// **Why a window and not an overlay.** The lock screen and the snapshot cover both have
/// to sit above whatever is showing, and "whatever is showing" includes sheets: settings,
/// the scanner, and manual entry, which has a secret in a text field. A SwiftUI overlay at
/// the root sits *under* presented sheets, so a lock drawn that way would leave an open
/// sheet readable, and the app switcher snapshot of a backgrounded app would keep whatever
/// the sheet was showing. A `UIWindow` at a raised level is the mechanism the system
/// itself uses for things that outrank the interface, and it is the only place in the app
/// that touches UIKit windows.
///
/// **The snapshot is why the cover exists at all, lock or no lock.** iOS photographs the
/// app as it leaves the foreground and shows that photograph in the app switcher to anyone
/// flicking through. Without the cover that photograph contains live codes and account
/// names. The cover is therefore not part of App Lock and does not check any setting: it
/// appears for everyone the moment the app stops being active.
@MainActor
enum PrivacyShield {

    private static var window: UIWindow?

    /// Covers everything with a blank surface, or uncovers it.
    ///
    /// Cover only: the lock screen is not drawn here. While locked, the lock screen is the
    /// app's root view, so there is nothing behind it to hide and no second copy to keep
    /// in step. This also killed a real bug: an earlier version created this window during
    /// a locked cold launch, mid transition, and the window latched the wrong orientation
    /// and drew the lock screen sideways. The cover has no such moment, because it is only
    /// ever shown by an app that was just active and settled.
    ///
    /// The window and its content are built once and kept, then hidden rather than torn
    /// down. Replacing the root controller per change with a clear background had a one
    /// frame gap during the swap where the interface showed through, which is exactly the
    /// flash this window exists to prevent.
    static func setCovered(_ covered: Bool) {
        guard covered else {
            window?.isHidden = true
            return
        }

        if window == nil {
            guard
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first
            else { return }

            let shield = UIWindow(windowScene: scene)
            // Above alerts, because an alert can carry account names in its title.
            shield.windowLevel = .alert + 1
            shield.rootViewController = UIHostingController(rootView: CoverView())
            window = shield
        }

        window?.isHidden = false
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
/// because it is also what the app switcher shows while locked.
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
