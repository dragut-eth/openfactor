import Foundation

/// The `otpauth://` URI format, which is how accounts move between authenticators.
///
/// There is no RFC for it. It is a de facto standard, originally documented by Google,
/// and every service implements it slightly differently, so this file is written to be
/// generous about form and strict about meaning.
///
/// **Parsing is total.** Every input produces either a fully valid ``OTPAccount`` or a
/// typed ``OTPAuthURIError``. There is no partially populated result and no silent
/// default for a value that changes the codes, because a wrongly imported account does
/// not fail at import. It fails later, at a login, as codes that look correct and are
/// rejected, and by then the enrollment page is gone.
///
/// Shape of the thing:
///
///     otpauth://totp/Issuer:name@example.com?secret=JBSWY3DP&issuer=Issuer&digits=6
///     \_____/   \__/ \____/ \_____________/  \__________________________________/
///     scheme    type  issuer   account name              parameters
public enum OTPAuthURI {

    // MARK: - Parsing

    /// Reads an `otpauth://` URI.
    ///
    /// - Throws: ``OTPAuthURIError`` naming exactly what is wrong.
    public static func account(from text: String) throws(OTPAuthURIError) -> OTPAccount {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == "otpauth",
            let host = components.host?.lowercased().nilIfEmpty
        else {
            throw OTPAuthURIError.notAnOTPAuthURI
        }

        // The kind of account is settled before anything else is read, so that a URI for
        // something this app does not support is reported as exactly that, rather than as
        // whichever parameter happened to be missing from it.
        guard let type = URIType(rawValue: host) else {
            throw OTPAuthURIError.unsupportedType(host)
        }

        let parameters = parameters(from: components)
        let label = label(from: components)

        return OTPAccount(
            issuer: parameters["issuer"]?.trimmed.nilIfEmpty ?? label.issuer,
            name: label.name,
            secret: try secret(from: parameters),
            generator: try generator(ofType: type, from: parameters)
        )
    }

    /// The kinds of account the format defines, which are also the two ``OTPGenerator``
    /// cases. Parsing the host into this once means the switch that builds a generator is
    /// exhaustive, with no unreachable branch for a type that was already rejected.
    private enum URIType: String {
        case totp
        case hotp
    }

    /// Collects the query parameters, lowercasing names.
    ///
    /// The format specifies lowercase names, and services mostly comply, but matching
    /// case insensitively costs one call and saves refusing an otherwise valid account.
    ///
    /// Where a name repeats, the first wins. Any choice is arbitrary, so it is written
    /// down rather than left to the order a dictionary happens to build in. Unrecognised
    /// parameters are ignored, since services add their own and none of them change how a
    /// code is computed.
    private static func parameters(from components: URLComponents) -> [String: String] {
        var parameters: [String: String] = [:]

        for item in components.queryItems ?? [] {
            let name = item.name.lowercased()
            guard parameters[name] == nil, let value = item.value else { continue }
            parameters[name] = value
        }

        return parameters
    }

    // MARK: - The label

    /// Splits the path into an issuer and an account name.
    ///
    /// The path is `issuer:name`, or just `name`. The separator is the first colon, which
    /// may be written literally or percent encoded as `%3A`, and a space after it is
    /// conventional. The work happens before percent decoding, so that a colon inside a
    /// name, which arrives encoded, is not mistaken for the separator.
    ///
    /// An issuer here is the weaker source. The `issuer` parameter wins where both exist,
    /// which is what the format documentation asks for and what other authenticators do.
    private static func label(from components: URLComponents) -> (issuer: String?, name: String) {
        let encoded = components.percentEncodedPath.drop { $0 == "/" }

        guard let separator = firstLabelSeparator(in: encoded) else {
            return (nil, decode(encoded).trimmed)
        }

        return (
            decode(encoded[..<separator.lowerBound]).trimmed.nilIfEmpty,
            decode(encoded[separator.upperBound...]).trimmed
        )
    }

    /// Finds the separator in the still encoded path.
    ///
    /// A bare colon wins over an encoded one wherever both appear, and only if there is
    /// no bare colon at all does an encoded `%3A` count as the separator.
    ///
    /// The order matters. A writer that puts a colon inside an issuer or a name has to
    /// encode it, and leaves only the separator bare, so `Company%3A%20Ltd:alice` means
    /// issuer `Company: Ltd` and name `alice`. Taking the first colon of either kind
    /// would read it as issuer `Company` and name `Ltd:alice`, quietly renaming the
    /// account on import. Services that encode the separator itself have exactly one
    /// colon in the label, so the fallback still reads them correctly.
    private static func firstLabelSeparator(in encoded: Substring) -> Range<Substring.Index>? {
        if let colon = encoded.firstIndex(of: ":") {
            return colon..<encoded.index(after: colon)
        }

        var index = encoded.startIndex
        while index < encoded.endIndex {
            if encoded[index] == "%",
                let end = encoded.index(index, offsetBy: 3, limitedBy: encoded.endIndex),
                encoded[index..<end].uppercased() == "%3A"
            {
                return index..<end
            }

            index = encoded.index(after: index)
        }

        return nil
    }

    /// Percent decodes, falling back to the raw text if the encoding is malformed.
    ///
    /// Falling back rather than failing is deliberate. A stray `%` in a display name
    /// costs nothing and refusing the whole account over it would cost the user a login.
    /// Nothing security relevant is decoded here: the secret arrives as a parameter.
    private static func decode(_ text: Substring) -> String {
        String(text).removingPercentEncoding ?? String(text)
    }

    // MARK: - The secret

    private static func secret(from parameters: [String: String]) throws(OTPAuthURIError) -> Data {
        guard let raw = parameters["secret"]?.trimmed.nilIfEmpty else {
            throw OTPAuthURIError.missingSecret
        }

        let bytes: Data
        do {
            bytes = try Base32.decode(raw)
        } catch {
            throw OTPAuthURIError.malformedSecret(error)
        }

        // Base32 that is entirely padding decodes to nothing. It is syntactically fine and
        // useless, and HMAC would accept the empty key and produce codes that never work.
        guard !bytes.isEmpty else {
            throw OTPAuthURIError.emptySecret
        }

        return bytes
    }

    // MARK: - The generator

    private static func generator(
        ofType type: URIType,
        from parameters: [String: String]
    ) throws(OTPAuthURIError) -> OTPGenerator {
        let algorithm = try algorithm(from: parameters)
        let digits = try digits(from: parameters)

        switch type {
        case .totp:
            // Read outside the `do` below, so that the only error it can catch is the one
            // TOTPConfiguration throws.
            let seconds = try period(from: parameters)

            do {
                return .totp(
                    try TOTPConfiguration(algorithm: algorithm, digits: digits, period: seconds)
                )
            } catch {
                // The range belongs to TOTPConfiguration, so the rule is not repeated here.
                throw OTPAuthURIError.invalidConfiguration(error)
            }

        case .hotp:
            return .hotp(
                counter: try counter(from: parameters),
                digits: digits,
                algorithm: algorithm
            )
        }
    }

    private static func algorithm(from parameters: [String: String]) throws(OTPAuthURIError) -> OTPAlgorithm {
        guard let raw = parameters["algorithm"]?.trimmed.nilIfEmpty else {
            return .default
        }

        // Services write it as SHA1, sha1, and SHA-1. All three mean the same hash.
        let normalized = raw.uppercased().replacingOccurrences(of: "-", with: "")

        guard let algorithm = OTPAlgorithm(rawValue: normalized) else {
            throw OTPAuthURIError.unsupportedAlgorithm(raw)
        }

        return algorithm
    }

    private static func digits(from parameters: [String: String]) throws(OTPAuthURIError) -> OTPDigits {
        guard let raw = parameters["digits"]?.trimmed.nilIfEmpty else {
            return .default
        }

        guard let value = Int(raw), let digits = OTPDigits(rawValue: value) else {
            throw OTPAuthURIError.unsupportedDigits(raw)
        }

        return digits
    }

    private static func period(from parameters: [String: String]) throws(OTPAuthURIError) -> Int {
        guard let raw = parameters["period"]?.trimmed.nilIfEmpty else {
            return TOTPConfiguration.standard.period
        }

        guard let value = Int(raw) else {
            throw OTPAuthURIError.invalidPeriod(raw)
        }

        return value
    }

    private static func counter(from parameters: [String: String]) throws(OTPAuthURIError) -> UInt64 {
        guard let raw = parameters["counter"]?.trimmed.nilIfEmpty else {
            throw OTPAuthURIError.missingCounter
        }

        guard let value = UInt64(raw) else {
            throw OTPAuthURIError.invalidCounter(raw)
        }

        return value
    }
}

// MARK: - Small helpers

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
