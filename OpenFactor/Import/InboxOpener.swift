import Foundation
import OpenFactorCore

/// Turning something the system handed the app into something a screen can use.
///
/// Two ways in. Files or Mail send a file URL through "Open in OpenFactor", and the share
/// extension leaves an image in the group container for the app to collect. There is no third
/// way: an extension cannot open its containing app, so nothing arrives by custom URL and the
/// app no longer declares a scheme for one.
enum InboxOpener {

    /// What arrived, or nothing if this URL was not for us.
    ///
    /// **The two cases go to different screens, and blurring them is a bug I shipped once.** An
    /// image carries a QR code and belongs to the add-account path, which decodes it. A file is
    /// an export or a backup and belongs to the import path, which parses it. Calling both of
    /// them "data" was enough to send a shared screenshot into the file importer, which reported,
    /// correctly and unhelpfully, that it could find no accounts in it.
    enum Arrival: Equatable {
        /// An image the share extension put in the group container. Already removed from it.
        case image(Data)
        /// A file somewhere else on the system, which the importer reads itself.
        case file(URL)
    }

    /// What the share extension left behind, if anything worth showing.
    ///
    /// **This is the only way an image arrives.** A share extension is not permitted to open its
    /// containing app, measured twice on a phone: `extensionContext.open` was refused from the
    /// completion handler of `completeRequest`, and refused again from a live button somebody had
    /// just tapped. So the app looks for itself instead.
    ///
    /// Takes the newest and **sweeps the rest**, so nothing accumulates. An item older than
    /// `SharedInbox.freshness` is swept unread rather than presented, because opening the app
    /// into an import sheet for something shared days ago would be a strange thing to do to
    /// somebody who was reaching for a code.
    static func collect(from inbox: SharedInbox = SharedInbox()) -> Arrival? {
        defer { inbox.sweep() }

        guard let newest = inbox.pending().first,
            newest.arrived.timeIntervalSinceNow > -SharedInbox.freshness,
            let data = try? inbox.take(newest.id)
        else { return nil }

        return .image(data)
    }

    /// A file the system handed us, from Files, Mail, or anywhere offering "Open in".
    ///
    /// **Nothing is parsed here.** This says where bytes came from and hands them on. Deciding
    /// what they mean is the importer's job, in one place, already fuzzed. A second reader of
    /// hostile input is a second attack surface for no gain.
    static func arrival(from url: URL) -> Arrival? {
        url.isFileURL ? .file(url) : nil
    }
}

/// `sheet(item:)` needs identity, and an arrival has none of its own: opening the same file twice
/// is two presentations. A fresh identifier per arrival is what makes the second one happen.
struct IdentifiedArrival: Identifiable {
    let id = UUID()
    let value: InboxOpener.Arrival
}
