import Foundation

extension OTPAuthURI {

    /// Writes an account as an `otpauth://` URI.
    ///
    /// Used by the export path, and by the tests that prove parsing round trips.
    ///
    /// The URI is built by hand rather than through `URLComponents`, because
    /// `URLComponents` makes its own decisions about which characters in a query value
    /// need escaping, and those decisions have changed between releases. Here the rule is
    /// visible: everything outside the RFC 3986 unreserved set is percent encoded, and
    /// the only structural characters left bare are the ones this function writes itself.
    ///
    /// **Every parameter is written out, including the ones that match the defaults.** A
    /// URI that omits `algorithm` is relying on whoever reads it next to assume the same
    /// default, and readers do not reliably agree. Eight characters of output is a cheap
    /// price for an exported account that generates the same codes wherever it lands.
    public static func uri(for account: OTPAccount) -> String {
        var text = "otpauth://\(account.generator.uriType)/\(label(for: account))?"
        text += query(for: account).map { "\($0.name)=\($0.value)" }.joined(separator: "&")
        return text
    }

    // MARK: - Label

    private static func label(for account: OTPAccount) -> String {
        let name = account.name.trimmed

        guard let issuer = account.issuer?.trimmed.nilIfEmpty else {
            // With no issuer, a colon inside the name would look exactly like the
            // separator to any reader, this one included, and the name would come back
            // split in two. An empty issuer prefix removes the ambiguity: the first colon
            // is the separator, and everything before it is nothing.
            return name.contains(":") ? ":\(encode(name))" : encode(name)
        }

        return "\(encode(issuer)):\(encode(name))"
    }

    // MARK: - Parameters

    private static func query(for account: OTPAccount) -> [(name: String, value: String)] {
        var items: [(name: String, value: String)] = []

        // Unpadded, because trailing `=` in a query value is legal, ambiguous to read, and
        // decodes identically either way.
        items.append((name: "secret", value: Base32.encode(account.secret, padded: false)))

        if let issuer = account.issuer?.trimmed.nilIfEmpty {
            items.append((name: "issuer", value: encode(issuer)))
        }

        items.append((name: "algorithm", value: account.generator.algorithm.rawValue))
        items.append((name: "digits", value: String(account.generator.digits.rawValue)))

        switch account.generator {
        case let .totp(configuration):
            items.append((name: "period", value: String(configuration.period)))
        case let .hotp(counter, _, _):
            items.append((name: "counter", value: String(counter)))
        }

        return items
    }

    // MARK: - Encoding

    /// The RFC 3986 unreserved set, the characters that never need escaping anywhere in a
    /// URI. Everything else is escaped, which is stricter than necessary and never wrong.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}
