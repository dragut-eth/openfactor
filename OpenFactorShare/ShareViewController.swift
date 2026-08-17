import Foundation
import OpenFactorCore
import UIKit
import UniformTypeIdentifiers

/// Taking a transfer QR out of Messages or Mail without it ever resting in Photos.
///
/// ## Why this target exists
///
/// A transfer QR is every secret its owner has, in the clear, in one image. Without this the only
/// route into OpenFactor is to save it to Photos first, and Photos is not one copy: on a default
/// iPhone it replicates to every Mac, iPad, iPhone and Apple TV on the account, is reachable from
/// a browser, is processed server-side for indexing, and survives deletion for thirty days in a
/// folder most people do not know exists. That is an exposure surface nobody can audit, holding
/// the most sensitive thing this app handles.
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
/// **It writes bytes and a name.** The image goes into the group container with complete file
/// protection, and the only thing that leaves this process is
/// `openfactor://inbox?item=<uuid>`. A URL can be logged, can appear in handoff, and can end up
/// in a diagnostic bundle, so it carries a name that reveals nothing rather than a payload.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // No interface of its own. There is one thing to do and no decision to offer, so a
        // sheet asking somebody to confirm what they already chose in the share sheet would be
        // a step for its own sake.
        view.backgroundColor = .clear

        Task { await run() }
    }

    private func run() async {
        guard let data = await firstImage() else {
            return finish(opening: nil)
        }

        // Bounded here as well as in the app. This process is handed whatever somebody shares,
        // and an extension is a poor place to decide how much memory to spend.
        guard data.count <= 8 * 1024 * 1024 else {
            return finish(opening: nil)
        }

        guard let id = try? SharedInbox().write(data) else {
            return finish(opening: nil)
        }

        finish(opening: URL(string: "openfactor://inbox?item=\(id.uuidString)"))
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

    /// Closes the sheet, then asks the system to open the app.
    ///
    /// **The order matters and the second half may not be granted.** Opening the containing app
    /// from a share extension is not something Apple documents as supported, so this is written
    /// to be correct when it silently does nothing: the app sweeps the inbox at launch, so an
    /// item nobody came for is removed rather than left waiting. A person who is not taken to the
    /// app has to share again, which is a worse experience and not a worse outcome.
    private func finish(opening url: URL?) {
        extensionContext?.completeRequest(returningItems: nil) { _ in
            guard let url else { return }

            // The documented API first. The responder chain walk that some apps use instead
            // reaches for `UIApplication` from a process that is not supposed to have one, and a
            // security tool should not be teaching itself that habit to save a tap.
            self.extensionContext?.open(url, completionHandler: nil)
        }
    }
}
