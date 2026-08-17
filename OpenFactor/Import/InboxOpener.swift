import Foundation
import OpenFactorCore

/// Turning something the system handed the app into bytes the importer can look at.
///
/// Two ways in, one answer out. The share extension sends `openfactor://inbox?item=<uuid>`, and
/// Files or Mail send a file URL through "Open in OpenFactor". Both end at the same import
/// screen, which is the one place that parses anything.
enum InboxOpener {

    /// What arrived, or nothing if this URL was not for us.
    enum Arrival: Equatable {
        /// An image the share extension put in the group container. Already removed from it.
        case data(Data)
        /// A file somewhere else on the system, which the importer reads itself.
        case file(URL)
    }

    static let scheme = "openfactor"

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

        return .data(data)
    }
}

/// `sheet(item:)` needs identity, and an arrival has none of its own: opening the same file twice
/// is two presentations. A fresh identifier per arrival is what makes the second one happen.
struct IdentifiedArrival: Identifiable {
    let id = UUID()
    let value: InboxOpener.Arrival
}
