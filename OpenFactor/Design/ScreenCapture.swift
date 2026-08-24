import SwiftUI
import UIKit

/// Whether this screen is being recorded, mirrored, or shared, and what to do about it.
///
/// ## What this defends against
///
/// **Accidental broadcast, which is the only kind a defense like this can help with.** Somebody
/// sharing their screen in a meeting who hits a login and opens OpenFactor; a screen recording
/// that lands in Photos; a phone mirrored to a projector. Nobody in those situations has decided
/// to show anybody their secrets, and a paragraph in `SECURITY.md` reaches none of them. That is
/// exactly the shape of problem an automatic defense suits.
///
/// It is **not** a defense against somebody who wants to capture the screen. Screenshots cannot
/// be blocked through any supported interface, and a camera pointed at the phone defeats
/// everything here. See `ScreenshotWarning` for the one useful thing that can be done about
/// screenshots.
///
/// ## What it hides, and why the two are different
///
/// Codes are masked; a passphrase is withheld entirely and says so. A code is six digits that
/// stop working in seconds, so blanking it is worth doing and no disaster if it leaks. A vault
/// or backup passphrase never expires and opens every secret its owner has, and it is displayed
/// in large grouped monospace precisely so it can be transcribed, which is to say it is the most
/// legible thing in the app to a camera.
///
/// The account list is also hidden less thoroughly than it might be, and that is a judgment
/// rather than an oversight: the issuer names on those cards say which services somebody holds
/// accounts with, which does not expire the way a code does. Masking the digits while leaving
/// the cards is the compromise, so that mirroring the app for a legitimate reason still shows
/// something coherent.
@MainActor
@Observable
final class ScreenCaptureMonitor {

    /// Whether any screen showing this app's content is being captured.
    private(set) var isCaptured: Bool

    /// Kept for the life of the app rather than removed in `deinit`. A `deinit` cannot touch
    /// main-actor state, and this object lives as long as the scene does, so there is nothing
    /// to tidy up: the alternative is an unstructured teardown for an object that never goes
    /// away.
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// The live monitor, reading the screen's current state and following it.
    init() {
        isCaptured = UIScreen.screens.contains { $0.isCaptured }
        observer = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    /// For previews and tests, which have no screen to capture.
    init(captured: Bool) {
        isCaptured = captured
    }

    /// Re-reads every attached screen. **Every screen, not just the main one:** mirroring to an
    /// external display attaches a second screen, and asking only the first would miss the case
    /// the person is most likely to have forgotten about.
    func refresh() {
        isCaptured = UIScreen.screens.contains { $0.isCaptured }
    }
}

extension EnvironmentValues {
    /// Injected once by the app, so no view has to know how capture is detected and previews
    /// can show either state. `false` by default, which is the right answer for a preview and
    /// for any view rendered outside the app.
    @Entry var isScreenCaptured = false
}

/// The line shown in place of a passphrase while the screen is being captured.
///
/// **It replaces the passphrase rather than covering the whole screen.** A blank view reads as a
/// crash, and on the vault setup screen that is not merely untidy: somebody who thinks the screen
/// is broken may tap "Generate a different one" and replace a passphrase they have already
/// written down. The buttons stay, the layout stays, and only the characters go.
struct CapturedPassphrasePlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.medium) {
            Image(systemName: "eye.slash")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
                Text("Hidden while your screen is shared")
                    .font(.callout.weight(.semibold))
                Text(
                    """
                    Your screen is being recorded, mirrored, or shared. Stop that and the \
                    passphrase comes back.
                    """
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Warns when a screenshot is taken of a screen showing a passphrase.
///
/// **Only on those screens, and the reason is that only there is the warning actionable.** For a
/// code, saying "you screenshotted that" tells somebody nothing they can use: the code is dead in
/// seconds and the image is already written. For a passphrase it is the opposite. The screen they
/// were on told them it is shown once and never again, which is the single most reliable way to
/// make a person reach for a screenshot, and the consequence is one they cannot see: the image is
/// in Photos, it may already be syncing to their other devices through iCloud Photos, and
/// deleting it leaves it in Recently Deleted for thirty days.
///
/// That is the same argument that justified building the share extension, applied to something
/// worse than a transfer QR. It turns a mistake nobody knew they were making into one they can
/// fix, which is the whole of what detection is good for.
struct ScreenshotWarning: ViewModifier {

    /// Whether a passphrase is on screen right now. **Not merely whether this screen can show
    /// one.** The export flow has five stages and only one of them displays a passphrase, so a
    /// warning attached to the whole screen would fire while somebody screenshotted a file
    /// listing or an explanation. An alert that cries wolf is one people learn to dismiss
    /// without reading, which would cost exactly the moment it exists for.
    let isShowingPassphrase: Bool

    @State private var didScreenshot = false

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.userDidTakeScreenshotNotification)
            ) { _ in
                guard isShowingPassphrase else { return }
                didScreenshot = true
            }
            .alert("That screenshot holds your passphrase", isPresented: $didScreenshot) {
                Button("OK") { didScreenshot = false }
            } message: {
                Text(
                    """
                    It is now a photo on this device. If iCloud Photos is on it may already be \
                    on your other devices and reachable from iCloud.com, and deleting it keeps \
                    it in Recently Deleted for 30 days.

                    Write the passphrase down or put it in a password manager instead, then \
                    delete the screenshot from Recently Deleted as well.
                    """
                )
            }
    }
}

extension View {
    /// See `ScreenshotWarning`. `showing` must be true only while a passphrase is actually
    /// visible, not merely while the screen that can display one is up.
    func warnsAboutScreenshots(showing: Bool = true) -> some View {
        modifier(ScreenshotWarning(isShowingPassphrase: showing))
    }
}
