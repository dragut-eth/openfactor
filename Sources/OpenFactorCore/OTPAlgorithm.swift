import Foundation

/// The hash function underneath the one time password.
///
/// The raw values are the spellings used in `otpauth://` URIs, so PR 3 parses straight
/// into this type.
public enum OTPAlgorithm: String, Sendable, Equatable, CaseIterable, Codable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    /// What almost every service uses, and the only algorithm RFC 4226 defines.
    ///
    /// SHA1 is broken for collision resistance, which is why CryptoKit files it under
    /// `Insecure`. HMAC does not rely on collision resistance, and HMAC-SHA1 has no
    /// practical attack against it. More to the point, the choice is not ours: the
    /// algorithm is fixed when the account is enrolled, and a service that issued a SHA1
    /// secret needs SHA1 codes back. Refusing it would mean refusing most accounts that
    /// exist.
    public static let `default` = OTPAlgorithm.sha1
}
