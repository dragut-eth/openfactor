import Foundation
import OpenFactorCore

/// Turning something the system handed the app into bytes the importer can look at.
///
/// Two ways in, one answer out. The share extension sends `openfactor://inbox?item=<uuid>`, and
/// Files or Mail send a file URL through "Open in OpenFactor". Both end at the same import
/// screen, which is the one place that parses anything.
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

    static let scheme = "openfactor"

    /// What the share extension left behind, if anything worth showing.
    ///
    /// **This is how an item actually arrives.** The extension sends
    /// `openfactor://inbox?item=<uuid>` as well, and that is kept because it costs nothing and
    /// is the better experience where it works, but a share extension is not permitted to open
    /// its containing app: on a phone the sheet simply closes and the app is never told. So the
    /// app looks for itself, every time it becomes active.
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

    /// **Nothing is parsed here.** This decides where bytes came from and hands them on. Deciding
    /// what they mean is the importer's job, in one place, already fuzzed. A second reader of
    /// hostile input is a second attack surface for no gain.
    static func arrival(from url: URL, inbox: SharedInbox = SharedInbox()) -> Arrival? {
        guard url.scheme == scheme else {
            // A file, from Files, Mail, or anywhere else that offers "Open in".
            return url.isFileURL ? .file(url) : nil
        }

        guard url.host == "inbox",
            let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "item" })?.value,
            let id = UUID(uuidString: item),
            let data = try? inbox.take(id)
        else {
            // A malformed or stale link is silence rather than an error. The person did not type
            // it, so there is nothing for them to correct, and the only thing an alert would
            // tell them is that something they never saw did not work.
            return nil
        }

        return .image(data)
    }
}

/// `sheet(item:)` needs identity, and an arrival has none of its own: opening the same file twice
/// is two presentations. A fresh identifier per arrival is what makes the second one happen.
struct IdentifiedArrival: Identifiable {
    let id = UUID()
    let value: InboxOpener.Arrival
}
