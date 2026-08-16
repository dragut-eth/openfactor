import CryptoKit
import Foundation
import Security

/// The encrypted archive: reading one, and writing one.
///
/// `docs/BACKUP_FORMAT.md` is normative and was audited three times before this file
/// existed. Where the two disagree, this file is the defect.
///
/// **The most dangerous artefact this project produces.** Every secret, in one place,
/// outside the Keychain, protected only by a passphrase. None of the protections the rest of
/// the app leans on, the device passcode, the Secure Enclave, the protection class, apply
/// once bytes are in a file a person can email to themselves. That asymmetry is why the
/// format was written and audited before any of this code, and why the app generates the
/// passphrase rather than asking for one.
public enum BackupArchive {

    /// Bound as additional authenticated data, which is what stops a file being relabelled
    /// as a different version and still opening.
    public static let format = "openfactor.backup.v1"

    /// What writers use. Readers take whatever the file says, inside the range below, so an
    /// archive written today still opens when this number rises.
    public static let writeIterations = 600_000

    static let iterationRange = 100_000...10_000_000
    static let saltBytes = 32
    static let nonceBytes = 12
    static let tagBytes = 16

    /// Roughly fifty thousand accounts: far past any real archive, short of anything that
    /// hurts a phone.
    static let maximumPlaintextBytes = 8 * 1024 * 1024

    /// The base64 that encodes `maximumPlaintextBytes`, checked **before** decoding. A
    /// reader that has to decode in order to learn how much it decoded has already spent
    /// whatever the file asked it to spend.
    static let maximumCiphertextCharacters = 11_184_812

    /// A guard on the whole file, and **not one of the format's bounds.**
    ///
    /// The format bounds the ciphertext field, not the container, so this exists only so
    /// that an unbounded file is never handed to a JSON parser. It was originally set to
    /// `maximumCiphertextCharacters`, which was wrong in a way that took a review to see: a
    /// conforming archive at the top of the frozen ceiling is about three hundred and sixty
    /// bytes larger than its own ciphertext field once the field names, the key derivation
    /// and cipher objects and the whitespace are counted, so this reader refused a file the
    /// format declares valid. The bounds of version 1 are frozen, and a reader that narrows
    /// them has stopped implementing version 1.
    ///
    /// The slack is a whole mebibyte rather than the few hundred bytes that would do,
    /// because the format anticipates padding arriving later as an ignored unknown field. An
    /// archive padded past this is refused, which is this reader's own policy rather than
    /// the format's, and is said out loud here rather than left to be discovered.
    static let maximumFileBytes = maximumCiphertextCharacters + 1024 * 1024

    // MARK: - Reading

    /// Opens an archive, or explains why it cannot.
    ///
    /// Everything a reader must refuse is refused **before any key is derived**, so a
    /// malformed file costs no work factor at all.
    public static func read(
        _ data: Data,
        passphrase: String
    ) throws(BackupError) -> ImportResult {
        guard data.count <= maximumFileBytes else { throw .tooLarge }

        guard
            let root = try? JSONSerialization.jsonObject(with: data),
            let object = root as? [String: Any]
        else {
            throw .notAnArchive
        }

        // Byte for byte, and the reason is subtle enough to be worth stating: the same
        // string is bound as additional authenticated data, so a reader that case folds this
        // comparison and then authenticates with the file's own spelling fails the tag with
        // a message about the passphrase.
        guard let claimedFormat = object["format"] as? String else {
            throw .malformedField("format")
        }
        guard claimedFormat == format else {
            throw .unsupportedFormat(claimedFormat)
        }

        guard let kdf = object["kdf"] as? [String: Any] else { throw .malformedField("kdf") }
        guard let cipher = object["cipher"] as? [String: Any] else {
            throw .malformedField("cipher")
        }

        guard let kdfAlgorithm = kdf["algorithm"] as? String else {
            throw .malformedField("kdf.algorithm")
        }
        guard kdfAlgorithm == "PBKDF2-HMAC-SHA256" else {
            throw .unsupportedKeyDerivation(kdfAlgorithm)
        }

        guard let cipherAlgorithm = cipher["algorithm"] as? String else {
            throw .malformedField("cipher.algorithm")
        }
        guard cipherAlgorithm == "AES-256-GCM" else {
            throw .unsupportedCipher(cipherAlgorithm)
        }

        guard let iterationsNumber = kdf["iterations"] as? NSNumber,
            CFGetTypeID(iterationsNumber) != CFBooleanGetTypeID(),
            iterationsNumber.doubleValue == iterationsNumber.doubleValue.rounded()
        else {
            throw .malformedField("kdf.iterations")
        }
        let iterations = iterationsNumber.intValue
        guard iterationRange.contains(iterations) else {
            throw .iterationsOutOfRange(iterations)
        }

        let salt = try bytes(kdf["salt"], field: "kdf.salt", expected: saltBytes)
        let nonce = try bytes(cipher["nonce"], field: "cipher.nonce", expected: nonceBytes)
        let tag = try bytes(cipher["tag"], field: "cipher.tag", expected: tagBytes)

        guard let ciphertextText = object["ciphertext"] as? String else {
            throw .malformedField("ciphertext")
        }
        guard ciphertextText.count <= maximumCiphertextCharacters else { throw .tooLarge }
        guard let ciphertext = BackupBase64.decode(ciphertextText) else {
            throw .malformedField("ciphertext")
        }
        guard ciphertext.count <= maximumPlaintextBytes else { throw .tooLarge }

        // Advisory, and never a gate. An absent, misspelled, differently cased or wrongly
        // typed value orders the attempts differently and changes nothing else.
        let hint = (object["passphrase"] as? String).flatMap(BackupPassphrase.Mode.init(rawValue:))

        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertext,
                tag: tag
            )
        } catch {
            throw .malformedField("cipher")
        }

        let aad = Data(format.utf8)

        for password in BackupPassphrase.attempts(for: passphrase, hint: hint) {
            guard
                let key = PBKDF2.deriveKey(
                    password: password, salt: salt, iterations: iterations
                )
            else {
                throw .derivationFailed
            }

            guard
                let plaintext = try? AES.GCM.open(
                    sealed, using: SymmetricKey(data: key), authenticating: aad
                )
            else {
                continue
            }

            // **The parse is load bearing, not a convenience.** AES-GCM does not commit to
            // its key: given two keys, one ciphertext and tag that authenticate under both
            // can be constructed by solving a linear equation, and that was demonstrated
            // against an earlier revision of the format with a working archive. Since this
            // loop derives more than one key from one typed input, an attacker who authors a
            // file can make it verify twice. Requiring the plaintext to parse as a payload
            // reduces the attack to producing two plaintexts that are both valid payloads,
            // which the keystream difference makes infeasible.
            guard let result = BackupPayload.read(plaintext) else { continue }

            return result
        }

        throw .couldNotOpen
    }

    /// A required base64 field of an exact length.
    private static func bytes(
        _ value: Any?,
        field: String,
        expected: Int
    ) throws(BackupError) -> Data {
        guard let text = value as? String else { throw .malformedField(field) }
        guard let decoded = BackupBase64.decode(text) else { throw .malformedField(field) }
        guard decoded.count == expected else {
            throw .wrongLength(field: field, expected: expected, found: decoded.count)
        }
        return decoded
    }

    // MARK: - Writing

    /// Seals the accounts into an archive.
    ///
    /// **A fresh salt and a fresh nonce, every time, from the system CSPRNG.** Not per
    /// session, not per device, not per set of accounts. Re-exporting an unchanged list is a
    /// new archive and takes new values, because reusing a nonce under the same key destroys
    /// the confidentiality of both archives. The fresh salt is what makes reuse harmless in
    /// practice, since a different salt yields a different key, and it is not a reason to
    /// skip the fresh nonce.
    public static func write(
        _ accounts: [ImportedAccount],
        passphrase: String,
        mode: BackupPassphrase.Mode,
        iterations: Int = writeIterations
    ) throws -> Data {
        // **The writer refuses a weak custom passphrase here, rather than upstream.** The
        // format states this as an obligation on writers, and until a review pointed it out
        // the only thing enforcing it was a disabled button on one screen. A rule that lives
        // in a view is a rule a second caller, a keyboard path or a refactor removes by
        // accident, and what it would produce is a permanent archive holding every secret
        // its owner has, behind something an offline attack finishes in a minute.
        if mode == .custom, !PassphraseStrength.assess(passphrase).isAcceptable {
            throw BackupError.passphraseTooWeak
        }

        let plaintext = try BackupPayload.write(accounts)

        let salt = try randomBytes(saltBytes)
        let nonce = try AES.GCM.Nonce(data: try randomBytes(nonceBytes))

        let password =
            mode == .generated
            ? BackupPassphrase.canonical(passphrase)
            : BackupPassphrase.verbatim(passphrase)

        guard
            let key = PBKDF2.deriveKey(password: password, salt: salt, iterations: iterations)
        else {
            throw BackupError.derivationFailed
        }

        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: nonce,
            authenticating: Data(format.utf8)
        )

        let container: [String: Any] = [
            "format": format,
            "passphrase": mode.rawValue,
            "kdf": [
                "algorithm": "PBKDF2-HMAC-SHA256",
                "iterations": iterations,
                "salt": BackupBase64.encode(salt),
            ],
            "cipher": [
                "algorithm": "AES-256-GCM",
                "nonce": BackupBase64.encode(Data(nonce)),
                "tag": BackupBase64.encode(sealed.tag),
            ],
            "ciphertext": BackupBase64.encode(sealed.ciphertext),
        ]

        return try JSONSerialization.data(
            withJSONObject: container,
            options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        )
    }

    /// Bytes from the system CSPRNG, and no fallback.
    ///
    /// A failure here is thrown rather than worked around. There is no acceptable second
    /// choice of randomness for a salt or a nonce, and the failure modes of getting it wrong
    /// are silent.
    private static func randomBytes(_ count: Int) throws -> Data {
        var data = Data(repeating: 0, count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw BackupError.derivationFailed }
        return data
    }
}
