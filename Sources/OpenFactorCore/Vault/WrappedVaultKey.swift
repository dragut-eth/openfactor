import CryptoKit
import Foundation

/// The vault key, sealed under a passphrase. The exact bytes of the one Keychain item that
/// makes recovery on another device possible.
///
/// ```
/// offset  size  field
/// 0       4     "OFK1"
/// 4       32    PBKDF2 salt
/// 36      4     PBKDF2 iterations
/// 40      12    nonce
/// 52      48    the 32 byte vault key sealed, plus its 16 byte tag
/// ```
///
/// **One record, not two.** The first draft of `docs/VAULT.md` put the salt "beside" the wrapped
/// key, and a reviewer pointed at this project's own measurements: iCloud Keychain delivers one
/// item at a time and took close to half an hour for seven. Two records mean a device can hold
/// one and not the other, and a correct passphrase then fails indistinguishably from a wrong
/// one. Salt, iterations and ciphertext travel together or the recovery story has a hole in it.
///
/// **The salt and iteration count sit outside the seal and inside the additional data.** They
/// have to be readable to derive the key at all, so they cannot be encrypted; binding them means
/// a writer cannot alter them undetected. Given the clamp below the damage would be denial
/// rather than weakening, and binding costs nothing.
public enum WrappedVaultKey {

    static let magic = Data("OFK1".utf8)
    static let saltSize = 32
    static let nonceSize = 12
    static let sealedSize = 48  // 32 byte key plus a 16 byte tag
    static let recordSize = 4 + saltSize + 4 + nonceSize + sealedSize

    /// What a writer uses. The archive's number, and the same reasoning.
    public static let writeIterations = 600_000

    /// The range a reader accepts. **Deliberately narrower than the archive's**, and the
    /// difference is the point: an archive is an interchange format whose bounds
    /// `docs/BACKUP_FORMAT.md` freezes for version 1, while this record is written only by this
    /// app, never leaves the Apple Account, and has never carried anything but
    /// `writeIterations`.
    ///
    /// **The ceiling is a denial of service bound, and it was set by copying a number that did
    /// not apply.** `unlock` tries every candidate record it can see, so a record planted by
    /// anything that can write this Keychain group could ask for ten million rounds each, on the
    /// recovery path, where a worried person is already waiting and the failure reads as a
    /// mistyped passphrase. Nothing legitimate needs more than a few times the write count, and
    /// the headroom that is left exists so a future build raising `writeIterations` does not
    /// produce records this build refuses. Found by audit X2 as OF-A2.
    static let iterationRange = 100_000...2_000_000

    public enum WrapError: Error, Equatable {
        case notAWrappedKey
        case iterationsOutOfRange(Int)
        case wrongPassphrase
        case derivationFailed
    }

    private static func aad(salt: Data, iterations: Int) -> Data {
        var data = magic
        data.append(salt)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(iterations).bigEndian, Array.init))
        return data
    }

    // MARK: - Writing

    /// Seals the vault key under a passphrase, with a fresh salt and nonce every time.
    ///
    /// Fresh on **every** call, not only at creation. A passphrase change rewraps, and reusing
    /// either value across rewraps is the writer mistake this project's format documents call
    /// catastrophic rather than merely wrong.
    public static func wrap(
        vaultKey: SymmetricKey,
        passphrase: String,
        iterations: Int = writeIterations
    ) throws -> Data {
        var salt = Data(repeating: 0, count: saltSize)
        let status = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, saltSize, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw WrapError.derivationFailed }

        return try wrap(
            vaultKey: vaultKey, passphrase: passphrase, iterations: iterations,
            salt: salt, nonce: AES.GCM.Nonce())
    }

    /// The same, with the salt and nonce supplied. **Only the published vectors call this**, for
    /// the reason `VaultRecord`'s equivalent seam gives.
    static func wrap(
        vaultKey: SymmetricKey,
        passphrase: String,
        iterations: Int,
        salt: Data,
        nonce: AES.GCM.Nonce
    ) throws -> Data {
        guard iterationRange.contains(iterations) else {
            throw WrapError.iterationsOutOfRange(iterations)
        }

        guard
            let wrapping = PBKDF2.deriveKey(
                password: BackupPassphrase.canonical(passphrase),
                salt: salt, iterations: iterations)
        else {
            throw WrapError.derivationFailed
        }

        let sealed = try AES.GCM.seal(
            vaultKey.withUnsafeBytes { Data($0) },
            using: SymmetricKey(data: wrapping),
            nonce: nonce,
            authenticating: aad(salt: salt, iterations: iterations))

        var out = magic
        out.append(salt)
        out.append(contentsOf: withUnsafeBytes(of: UInt32(iterations).bigEndian, Array.init))
        out.append(contentsOf: sealed.nonce)
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    // MARK: - Reading

    /// Recovers the vault key, or says which of the two things went wrong.
    ///
    /// **The passphrase is canonicalised, never taken verbatim.** The vault passphrase is always
    /// generated, so exactly one form is ever derived. That is deliberate: trying several
    /// candidate derivations of one input against one ciphertext is the shape that produced the
    /// key commitment collision in `docs/BACKUP_FORMAT.md`, and the fix there, requiring the
    /// plaintext to parse, has no equivalent for 32 opaque bytes.
    public static func unwrap(_ record: Data, passphrase: String) throws -> SymmetricKey {
        let bytes = Data(record)
        guard bytes.count == recordSize, bytes.prefix(4) == magic else {
            throw WrapError.notAWrappedKey
        }

        let salt = Data(bytes[4..<(4 + saltSize)])
        let iterations = Int(
            bytes[(4 + saltSize)..<(8 + saltSize)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })

        guard iterationRange.contains(iterations) else {
            throw WrapError.iterationsOutOfRange(iterations)
        }

        let nonceStart = 8 + saltSize
        let nonce = Data(bytes[nonceStart..<(nonceStart + nonceSize)])
        let body = Data(bytes[(nonceStart + nonceSize)...])

        guard
            let wrapping = PBKDF2.deriveKey(
                password: BackupPassphrase.canonical(passphrase),
                salt: salt, iterations: iterations)
        else {
            throw WrapError.derivationFailed
        }

        do {
            let opened = try AES.GCM.open(
                AES.GCM.SealedBox(
                    nonce: try AES.GCM.Nonce(data: nonce),
                    ciphertext: body.dropLast(16),
                    tag: body.suffix(16)),
                using: SymmetricKey(data: wrapping),
                authenticating: aad(salt: salt, iterations: iterations))
            return SymmetricKey(data: opened)
        } catch {
            throw WrapError.wrongPassphrase
        }
    }
}
