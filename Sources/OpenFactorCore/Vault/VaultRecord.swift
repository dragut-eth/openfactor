import CryptoKit
import Foundation

/// One account, sealed. The exact bytes of `kSecValueData` for a vault item.
///
/// `docs/VAULT.md` is normative and specifies this layout to the byte. Where this file and that
/// page disagree, this file is the defect. The page is pinned because an external review pointed
/// out that a page calling itself normative while describing a record conceptually leaves **the
/// first implementation to become the specification by accident**.
///
/// ```
/// offset  size  field
/// 0       4     "OFV1"
/// 4       12    metadata nonce
/// 16      4     metadata sealed length, ciphertext plus 16 byte tag
/// 20      n     metadata sealed bytes
/// 20+n    12    secret nonce
/// 32+n    4     secret sealed length
/// 36+n    m     secret sealed bytes
/// ```
///
/// ## Why two halves rather than one blob
///
/// Today `KeychainSecretStore` sets `kSecReturnData` to false on every listing path, and says so
/// in its own header: listing accounts never decrypts a single secret, and only `secret(for:)`
/// asks for data, for one account, at the moment a code is generated.
///
/// Sealing an account as one blob would have ended that quietly. Drawing the list would decrypt
/// every secret into memory to render a screen that needs none of them. A reviewer caught the
/// design discarding a property it had never mentioned, which is worse than getting one wrong.
///
/// So the halves are sealed separately under the same key. ``openMetadata(_:id:key:)`` is what a
/// list costs; a secret's plaintext appears only in ``openSecret(_:id:key:)``.
///
/// The second consequence matters as much: ``replacingMetadata(in:with:id:key:)`` copies the
/// secret half **verbatim**, so a rename, a reorder or an HOTP counter advance rewrites an item
/// without the secret ever being decrypted, and without needing a fresh nonce for it.
public enum VaultRecord {

    static let magic = Data("OFV1".utf8)
    static let nonceSize = 12
    static let tagSize = 16

    /// Domain separation, so a metadata half cannot be substituted for a secret half. Without
    /// it both are ciphertext under one key with the same associated data, and swapping them
    /// would authenticate.
    private static let metadataTag: UInt8 = 0x6D  // 'm'
    private static let secretTag: UInt8 = 0x73  // 's'

    public enum RecordError: Error, Equatable {
        case notARecord
        case truncated
        case wrongKeyOrTampered
    }

    private static func aad(_ tag: UInt8, _ id: UUID) -> Data {
        var data = magic
        data.append(tag)
        data.append(contentsOf: withUnsafeBytes(of: id.uuid, Array.init))
        return data
    }

    // MARK: - Writing

    /// Seals a whole account. Used when an account is created, and never again: the secret half
    /// is written once and copied verbatim thereafter.
    public static func seal(
        metadata: Data,
        secret: Data,
        id: UUID,
        key: SymmetricKey
    ) throws -> Data {
        let sealedMetadata = try AES.GCM.seal(
            VaultPadding.pad(metadata), using: key, authenticating: aad(metadataTag, id))
        let sealedSecret = try AES.GCM.seal(
            VaultPadding.pad(secret), using: key, authenticating: aad(secretTag, id))

        var out = magic
        append(sealedMetadata, to: &out)
        append(sealedSecret, to: &out)
        return out
    }

    /// Rewrites the metadata half and copies the secret half byte for byte.
    ///
    /// **This is the method a rename, a colour change, a reorder and an HOTP counter go
    /// through**, and the reason none of them ever decrypts a secret. It also means the secret's
    /// nonce is not reused with different plaintext, because the plaintext is not re-sealed at
    /// all: the bytes are moved unexamined.
    public static func replacingMetadata(
        in record: Data,
        with metadata: Data,
        id: UUID,
        key: SymmetricKey
    ) throws -> Data {
        let parts = try split(record)

        let sealedMetadata = try AES.GCM.seal(
            VaultPadding.pad(metadata), using: key, authenticating: aad(metadataTag, id))

        // Nonce then length then body, the same order `seal` and `split` use. Writing the
        // length first here round tripped through neither, and the test that caught it is the
        // one asserting the layout rather than the round trip.
        var out = magic
        append(sealedMetadata, to: &out)
        out.append(parts.secretNonce)
        out.append(contentsOf: withUnsafeBytes(of: UInt32(parts.secret.count).bigEndian, Array.init))
        out.append(parts.secret)
        return out
    }

    private static func append(_ box: AES.GCM.SealedBox, to out: inout Data) {
        out.append(contentsOf: box.nonce)
        let body = box.ciphertext + box.tag
        out.append(contentsOf: withUnsafeBytes(of: UInt32(body.count).bigEndian, Array.init))
        out.append(body)
    }

    // MARK: - Reading

    /// What a list costs: the metadata half, and no secret anywhere.
    public static func openMetadata(_ record: Data, id: UUID, key: SymmetricKey) throws -> Data {
        let parts = try split(record)
        return try open(
            nonce: parts.metadataNonce, body: parts.metadata,
            aad: aad(metadataTag, id), key: key)
    }

    /// The only place a secret's plaintext exists, called when a code is generated.
    public static func openSecret(_ record: Data, id: UUID, key: SymmetricKey) throws -> Data {
        let parts = try split(record)
        return try open(
            nonce: parts.secretNonce, body: parts.secret,
            aad: aad(secretTag, id), key: key)
    }

    private static func open(
        nonce: Data, body: Data, aad: Data, key: SymmetricKey
    ) throws -> Data {
        guard body.count > tagSize else { throw RecordError.truncated }

        let opened: Data
        do {
            opened = try AES.GCM.open(
                AES.GCM.SealedBox(
                    nonce: try AES.GCM.Nonce(data: nonce),
                    ciphertext: body.dropLast(tagSize),
                    tag: body.suffix(tagSize)),
                using: key,
                authenticating: aad)
        } catch {
            throw RecordError.wrongKeyOrTampered
        }

        guard let unpadded = VaultPadding.unpad(opened) else { throw RecordError.truncated }
        return unpadded
    }

    // MARK: - Layout

    private struct Parts {
        let metadataNonce: Data
        let metadata: Data
        let secretNonce: Data
        let secret: Data
    }

    /// Every read is bounds checked against what is actually there. An item is attacker
    /// writable, so a length that claims more than exists is an ordinary input rather than an
    /// impossibility.
    private static func split(_ record: Data) throws -> Parts {
        let bytes = Data(record)
        guard bytes.count >= magic.count else { throw RecordError.notARecord }
        guard bytes.prefix(magic.count) == magic else { throw RecordError.notARecord }

        var offset = magic.count

        func take(_ count: Int) throws -> Data {
            guard count >= 0, bytes.count - offset >= count else { throw RecordError.truncated }
            let slice = bytes[bytes.startIndex + offset ..< bytes.startIndex + offset + count]
            offset += count
            return Data(slice)
        }

        func takeLength() throws -> Int {
            let raw = try take(4)
            let value = raw.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard value <= UInt32(bytes.count) else { throw RecordError.truncated }
            return Int(value)
        }

        let metadataNonce = try take(nonceSize)
        let metadata = try take(try takeLength())
        let secretNonce = try take(nonceSize)
        let secret = try take(try takeLength())

        return Parts(
            metadataNonce: metadataNonce, metadata: metadata,
            secretNonce: secretNonce, secret: secret)
    }
}
