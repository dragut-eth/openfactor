import CommonCrypto
import Foundation

/// PBKDF2-HMAC-SHA256, the key derivation the backup format specifies.
///
/// **CommonCrypto rather than CryptoKit, because CryptoKit has no password based KDF.**
/// CryptoKit's `HKDF` is a key *expansion* function: it assumes its input is already a high
/// entropy secret and does no work factor at all. Using it here would look modern and
/// provide none of the thing a passphrase needs.
///
/// Why PBKDF2 rather than Argon2id is argued in `docs/BACKUP_FORMAT.md`, including the part
/// where the trade is paid in full on the custom passphrase path. The short version is that
/// an archive nobody else's software can open is not a backup, and PBKDF2 is in every
/// cryptographic library that exists while Argon2id is not.
enum PBKDF2 {

    /// Derives a key of `length` bytes.
    ///
    /// `password` is bytes rather than a `String` on purpose. The format is exact about
    /// which bytes reach the KDF, and two of the four attempts a reader makes differ only in
    /// their Unicode normalisation, so a `String` parameter here would put the one decision
    /// that matters somewhere it cannot be seen.
    ///
    /// - Returns: `nil` only if CommonCrypto reports a failure, which for these inputs means
    ///   a programming error rather than a bad archive.
    static func deriveKey(
        password: Data,
        salt: Data,
        iterations: Int,
        length: Int = 32
    ) -> Data? {
        var derived = Data(repeating: 0, count: length)

        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            password.withUnsafeBytes { passwordBytes -> Int32 in
                salt.withUnsafeBytes { saltBytes -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        length
                    )
                }
            }
        }

        return status == kCCSuccess ? derived : nil
    }
}
