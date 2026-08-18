import Foundation
import OpenFactorCore

/// Turning something the system handed the app into something a screen can use.
///
/// Three ways in. Files or Mail send a file URL through "Open in OpenFactor". The share extension
/// leaves an image in the group container for the app to collect, because an extension cannot
/// open its containing app. And the Camera app or Photos hands over an `otpauth://` or
/// `otpauth-migration://` URL when it finds one in a QR code, which is the only reason this app
/// declares a scheme at all: it declares the two standard ones and none of its own.
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
        /// A setup or transfer code the system read out of a QR, verbatim.
        ///
        /// **Not parsed here.** The payload names its own format and the add screen already
        /// tells one account from a transfer, so this carries the string and decides nothing.
        case code(String)
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

    /// The two standard authenticator schemes, which iOS offers this app when the Camera or
    /// Photos finds one in a QR code.
    static let codeSchemes: Set<String> = ["otpauth", "otpauth-migration"]

    /// **A code that arrived by URL may be no larger than one that could have arrived by QR.**
    ///
    /// Every other untrusted input in this app is bounded: an imported file and a shared image
    /// both cap at 8MB. The scanned path never needed a bound, because its only sources were a
    /// camera frame and a decoded image, and a QR code physically cannot hold more than about
    /// three kilobytes. Declaring a URL scheme removed that ceiling without replacing it: another
    /// app can hand over a string of any length, and a migration payload is base64 decoded and
    /// parsed before anything decides it is nonsense.
    ///
    /// The parser will not come to harm, because it refuses to allocate on a length the input
    /// claims and that was fuzzed. This is about not doing unbounded work on an attacker's say
    /// so. Eight kilobytes is comfortably above a QR code's alphanumeric capacity of 4,296
    /// characters, so no code that could really have been scanned is refused.
    static let longestCode = 8 * 1024

    /// A file the system handed us, or a code it read out of a QR.
    ///
    /// **Nothing is parsed here.** This says what kind of thing arrived and hands it on.
    /// Deciding what it means is the add screen's job or the importer's, each in one place and
    /// already fuzzed. A second reader of hostile input is a second attack surface for no gain.
    ///
    /// **Anything else is refused.** A declared scheme is an entry point every app on the device
    /// can use, so what is accepted is exactly the two schemes declared and file URLs, and
    /// nothing arriving this way is ever saved without somebody confirming it on screen.
    static func arrival(from url: URL) -> Arrival? {
        if url.isFileURL { return .file(url) }

        guard let scheme = url.scheme?.lowercased(), codeSchemes.contains(scheme) else {
            return nil
        }

        let payload = url.absoluteString
        guard payload.utf8.count <= longestCode else { return nil }
        return .code(payload)
    }
}

/// `sheet(item:)` needs identity, and an arrival has none of its own: opening the same file twice
/// is two presentations. A fresh identifier per arrival is what makes the second one happen.
struct IdentifiedArrival: Identifiable {
    let id = UUID()
    let value: InboxOpener.Arrival
}
