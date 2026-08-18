import Foundation
import OpenFactorCore
import UIKit
import UniformTypeIdentifiers

/// Taking a transfer QR out of Messages or Mail without it ever resting in Photos.
///
/// ## Why this target exists
///
/// A transfer QR may contain every OTP secret in the vault, in the clear, in one image. Without
/// this the only route into OpenFactor is to save it to Photos first, which writes it to a
/// persistent store: with iCloud Photos enabled the image can be synced through iCloud to the
/// owner's other devices and reached from iCloud.com, and deleting it retains it in Recently
/// Deleted for up to 30 days. Avoiding that copy is the whole reason this target exists.
///
/// ## What this is not allowed to do, which is most of the design
///
/// **No Keychain entitlement.** The same rule the watch complication follows. This process cannot
/// read an account and cannot write one, enforced by the system rather than promised here.
/// `OpenFactorShare.entitlements` has exactly one key, and it should stay that way.
///
/// **It does not parse.** It does not decode the QR, does not read protobuf, does not touch
/// `otpauth-migration`. All of that stays in the app, in one place, already fuzzed. A second
/// process reading hostile input is a second attack surface for no gain, and this one runs
/// automatically on whatever somebody shares.
///
/// **It writes bytes and says so.** The image goes into the group container with complete file
/// protection, and the app collects it the next time it comes forward.
///
/// **It cannot open the app, and that was measured rather than assumed.** `extensionContext.open`
/// was tried twice: once inside the completion handler of `completeRequest`, which failed and
/// could be explained away as calling it during teardown, and once from a button on this screen
/// with the extension alive and somebody having just asked for it. Refused both times. There is
/// no supported route, so this screen tells the person what to do instead of pretending.
///
/// The responder chain walk that some apps use is deliberately absent. It reaches for
/// `UIApplication` from a process the sandbox keeps away from it, and an app whose argument is
/// "check the claims against the source" should not answer "how did you launch yourself" with
/// "we went around it".
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    /// The app's own mark, so the sheet says which app it belongs to before the words do.
    ///
    /// A copy of the icon artwork rather than a reference to the app's, because an extension is a
    /// separate bundle and cannot read the containing app's assets. Two copies of one picture is
    /// the cost; reaching up out of the bundle to avoid it would be worse.
    private let mark = UIImageView(image: UIImage(named: "Mark"))
    private let titleLabel = UILabel()
    private let detail = UILabel()
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        Task { await run() }
    }

    private func run() async {
        guard let data = await firstImage() else {
            return show(title: "Nothing to import", detail: "That does not look like an image.")
        }

        // Bounded here as well as in the app. This process is handed whatever somebody shares,
        // and an extension is a poor place to decide how much memory to spend.
        guard data.count <= 8 * 1024 * 1024 else {
            return show(title: "That image is too large", detail: "Share a smaller one.")
        }

        guard (try? SharedInbox().write(data)) != nil else {
            return show(
                title: "Could not save it",
                detail: "OpenFactor could not reach its own storage.")
        }

        show(
            title: "Ready in OpenFactor",
            detail: "Open OpenFactor to add the account.")
    }

    // MARK: - The one screen

    /// **A silent close is indistinguishable from nothing happening.** That is what this target
    /// did first, and the only reason anybody knew it had worked was being told so. The screen
    /// exists to say what happened, and the button exists because it may be able to do better.
    private func show(title: String, detail: String) {
        titleLabel.text = title
        self.detail.text = detail
    }

    @objc private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// The image the person shared, as bytes, without loading it as a `UIImage`.
    ///
    /// **Deliberately not decoded.** Turning the attachment into an image and back would re-encode
    /// it through this process, and image decoders are among the most attacked code on the
    /// platform. These bytes are carried, not read.
    private func firstImage() async -> Data? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []

        for item in items {
            for provider in item.attachments ?? [] {
                guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                    continue
                }

                let data: Data? = await withCheckedContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
                        data, _ in
                        continuation.resume(returning: data)
                    }
                }

                if let data { return data }
            }
        }

        return nil
    }

    private func buildInterface() {
        view.backgroundColor = .systemBackground

        mark.contentMode = .scaleAspectFit
        mark.layer.cornerRadius = 16
        mark.layer.cornerCurve = .continuous
        mark.clipsToBounds = true
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.isAccessibilityElement = false

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = "Saving to OpenFactor"

        detail.font = .preferredFont(forTextStyle: .body)
        detail.adjustsFontForContentSizeCategory = true
        detail.textAlignment = .center
        detail.numberOfLines = 0
        detail.textColor = .secondaryLabel

        var close = UIButton.Configuration.plain()
        close.title = "Close"
        closeButton.configuration = close
        closeButton.addTarget(self, action: #selector(complete), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [mark, titleLabel, detail, closeButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(20, after: mark)
        stack.setCustomSpacing(24, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 72),
            mark.heightAnchor.constraint(equalTo: mark.widthAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }
}
