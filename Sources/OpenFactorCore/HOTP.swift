import CryptoKit
import Foundation

/// Counter based one time passwords, per
/// [RFC 4226](https://datatracker.ietf.org/doc/html/rfc4226).
///
/// This is the whole of the code generation. ``TOTP`` is a thin wrapper that turns a
/// clock reading into a counter and calls straight into here.
///
/// The only cryptography written by hand in this project is the truncation step below.
/// Everything else is CryptoKit.
public enum HOTP {

    /// Generates the code for one counter value.
    ///
    /// - Parameters:
    ///   - secret: the shared key, already decoded from Base32.
    ///   - counter: the moving factor. RFC 4226 section 5.1 sends it as an 8 byte value,
    ///     most significant byte first.
    ///   - digits: how many digits the service expects back.
    ///   - algorithm: the hash the service enrolled with.
    /// - Returns: the code as a string, padded with leading zeros to `digits` characters.
    ///   A code is text, never a number: `07081804` is a valid code and an `Int` would
    ///   lose the leading zero.
    public static func code(
        secret: Data,
        counter: UInt64,
        digits: OTPDigits = .default,
        algorithm: OTPAlgorithm = .default
    ) -> String {
        let message = Data(withUnsafeBytes(of: counter.bigEndian) { Array($0) })
        let hash = authenticationCode(for: message, key: SymmetricKey(data: secret), algorithm: algorithm)

        return format(truncate(hash), digits: digits)
    }

    // MARK: - Truncation

    /// Dynamic truncation, RFC 4226 section 5.3.
    ///
    /// The low 4 bits of the final byte pick a starting offset, and the 4 bytes from that
    /// offset become a 31 bit number. The top bit is masked off so the result is the same
    /// whether a platform reads it as signed or unsigned.
    ///
    /// Every hash this is called with is at least 20 bytes, and an offset drawn from 4
    /// bits is at most 15, so the 4 byte read is always in bounds.
    static func truncate(_ hash: Data) -> UInt32 {
        let bytes = Array(hash)
        let offset = Int(bytes[bytes.count - 1] & 0x0F)

        return (UInt32(bytes[offset] & 0x7F) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    /// Reduces the truncated value to the requested number of digits, zero padded.
    private static func format(_ value: UInt32, digits: OTPDigits) -> String {
        String(format: "%0\(digits.rawValue)u", value % digits.modulus)
    }

    // MARK: - HMAC

    /// Wraps CryptoKit so the algorithm can be chosen at run time.
    ///
    /// CryptoKit picks the hash through a generic parameter, which is a compile time
    /// choice, so the switch is unavoidable. It is the entire adaptation.
    private static func authenticationCode(
        for message: Data,
        key: SymmetricKey,
        algorithm: OTPAlgorithm
    ) -> Data {
        switch algorithm {
        case .sha1:
            // Insecure.SHA1 is CryptoKit's name for it. See the note on OTPAlgorithm.default
            // for why HMAC-SHA1 is both safe here and not optional.
            Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256:
            Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512:
            Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
    }
}
