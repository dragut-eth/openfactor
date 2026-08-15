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

    /// What the shield is showing.
    enum Content: Equatable {
        /// Blank surface, for the moment the system takes its snapshot.
        case cover
        /// The lock screen.
        case locked
    }

    private static var window: UIWindow?

    /// Shows the given content, or tears the window down when there is nothing to show.
    static func update(_ content: Content?, controller: AppLockController) {
        guard let content else {
            window?.isHidden = true
            window = nil
            return
        }

        let host = UIHostingController(
            rootView: ShieldView(content: content, controller: controller)
        )
        host.view.backgroundColor = .clear

        if window == nil {
            guard
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first
            else { return }

            let shield = UIWindow(windowScene: scene)
            // Above alerts, because an alert can carry account names in its title.
            shield.windowLevel = .alert + 1
            window = shield
        }

        window?.rootViewController = host
        window?.isHidden = false
    }
}

private struct ShieldView: View {
    let content: PrivacyShield.Content
    let controller: AppLockController

    var body: some View {
        switch content {
        case .cover:
            Tokens.Surface.background
                .ignoresSafeArea()

        case .locked:
            LockScreenView(controller: controller)
        }
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
