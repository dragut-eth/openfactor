import Foundation

/// Reads an Aegis Authenticator vault.
///
/// Unlike the labelled text reader, this **is** a published interchange format with a
/// specification, so this reader is strict rather than best effort.
///
/// **Encrypted vaults are refused, by name.** Aegis encrypts with scrypt, which this
/// project cannot provide without taking a dependency, and taking one would break the rule
/// that every dependency is code a user has to trust without choosing to. So the refusal
/// says what to do instead, export unencrypted from Aegis, rather than failing with
/// something the user cannot act on.
///
/// The shape, when unencrypted, is `header.slots` and `header.params` both null and `db` an
/// object holding `entries`.
public enum AegisImport {

    /// Why a whole file could not be read, as opposed to a single account.
    public enum FileError: Sendable, Equatable, Error {
        case encrypted
        case notAegis

        public var description: String {
            switch self {
            case .encrypted:
                """
                This vault is encrypted. OpenFactor cannot open Aegis encrypted vaults, \
                because they use a key derivation this app does not include. In Aegis, \
                export again with encryption turned off.
                """
            case .notAegis:
                "This file is not an Aegis vault."
            }
        }
    }

    public static func read(_ data: Data) throws(FileError) -> ImportResult {
        let vault: Vault
        do {
            vault = try JSONDecoder().decode(Vault.self, from: data)
        } catch {
            throw .notAegis
        }

        // An encrypted vault carries key slots and a base64 string where the database
        // should be. Detected before anything else so the message is the useful one.
        guard case let .plain(database) = vault.db else { throw .encrypted }
        if vault.header.slots != nil { throw .encrypted }

        var accounts: [ImportedAccount] = []
        var refusals: [ImportRefusal] = []

        for (index, lenient) in database.entries.enumerated() {
            guard let entry = lenient.entry else {
                refusals.append(
                    ImportRefusal(position: index + 1, label: lenient.label, reason: .malformedEntry))
                continue
            }
            let label = entry.issuer?.isEmpty == false ? entry.issuer : entry.name

            switch build(entry) {
            case let .success(imported):
                accounts.append(imported)
            case let .failure(reason):
                refusals.append(
                    ImportRefusal(position: index + 1, label: label, reason: reason)
                )
            }
        }

        return ImportResult(accounts: accounts, refusals: refusals)
    }

    private static func build(
        _ entry: Entry
    ) -> Result<ImportedAccount, ImportRefusal.Reason> {
        // Aegis supports kinds this app does not implement. Refusing by name beats
        // importing something that will not generate the codes the service expects.
        guard ["totp", "hotp"].contains(entry.type.lowercased()) else {
            return .failure(.unsupportedType(entry.type))
        }

        guard let rawSecret = entry.info.secret, !rawSecret.isEmpty else {
            return .failure(.missingSecret)
        }

        let secret: Data
        do {
            secret = try Base32.decode(rawSecret)
        } catch {
            return .failure(.secretNotBase32)
        }

        // **The floor the backup format requires, applied where accounts arrive.** Gate A4 found
        // three of the four enrollment paths admitting secrets the format refuses to restore, so
        // an account could work every day and vanish from the backup that was supposed to save
        // it. See `AccountLimits`.

        guard AccountLimits.isSecretLongEnough(secret) else {
            return .failure(.secretTooShort)
        }

        // Defaulting is correct here and wrong in the labelled text reader, which is worth
        // stating because the two look inconsistent side by side. Aegis publishes a schema
        // with documented defaults, so an absent field means the default. The other format
        // is a human readable report that always writes every field, so an absent one means
        // the parse failed.
        let algorithmText = entry.info.algo ?? "SHA1"
        guard let algorithm = OTPAlgorithm(rawValue: algorithmText.uppercased()) else {
            return .failure(.unsupportedAlgorithm(algorithmText))
        }

        let digitsValue = entry.info.digits ?? 6
        guard let digits = OTPDigits(rawValue: digitsValue) else {
            return .failure(.unsupportedDigits(digitsValue))
        }

        let generator: OTPGenerator

        if entry.type.lowercased() == "hotp" {
            guard let counter = entry.info.counter else { return .failure(.malformed) }
            // Same ceiling as every other path. See `AccountLimits`.
            guard AccountLimits.isCounterStorable(counter) else { return .failure(.malformed) }
            generator = .hotp(counter: counter, digits: digits, algorithm: algorithm)
        } else {
            let period = entry.info.period ?? 30
            do {
                generator = .totp(
                    try TOTPConfiguration(
                        algorithm: algorithm, digits: digits, period: period
                    )
                )
            } catch {
                return .failure(.unsupportedPeriod(period))
            }
        }

        let account = OTPAccount(
            issuer: entry.issuer?.isEmpty == false ? entry.issuer : nil,
            name: entry.name ?? "",
            secret: secret,
            generator: generator
        )

        // Aegis has no colour concept that maps onto ours, so every imported account gets
        // the default rather than a guess derived from its name.
        return .success(ImportedAccount(account: account, color: .default))
    }

    // MARK: - The vault, as Aegis writes it

    private struct Vault: Decodable {
        let header: Header
        let db: Database

        struct Header: Decodable {
            let slots: [JSONAny]?
        }

        /// `db` is an object when the vault is unencrypted and a base64 string when it is
        /// not, so the difference is visible here rather than as a decoding failure.
        ///
        /// **Decided by the shape of `db`, and by nothing inside it.** This used to try the
        /// plain decode and call any failure "encrypted", so one entry with a string where a
        /// number belongs made a whole plaintext file report as encrypted, with advice to turn
        /// encryption off that cannot help a file that has none. Audit X3, OF-X3-05. A string is
        /// encrypted. An object is plain, and what its entries contain is each entry's own
        /// problem, reported per entry below.
        enum Database: Decodable {
            case plain(Contents)
            case encrypted

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if (try? container.decode(String.self)) != nil {
                    self = .encrypted
                    return
                }
                self = .plain(try container.decode(Contents.self))
            }
        }

        struct Contents: Decodable {
            let entries: [LenientEntry]
        }
    }

    /// One entry, decoded on its own so a malformed one is a refusal and not a verdict on the
    /// file. `ImportResult` promises that a file of ten where one is unusable yields nine, and
    /// the per-entry loop in `read` kept that promise only for entries that decoded.
    private struct LenientEntry: Decodable {
        let entry: Entry?
        /// Whatever name the malformed entry still carries, so its refusal can be labelled.
        let label: String?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let entry = try? container.decode(Entry.self) {
                self.entry = entry
                self.label = nil
            } else {
                self.entry = nil
                let names = try? container.decode(Names.self)
                self.label = names?.issuer?.isEmpty == false ? names?.issuer : names?.name
            }
        }

        private struct Names: Decodable {
            let name: String?
            let issuer: String?
        }
    }

    private struct Entry: Decodable {
        let type: String
        let name: String?
        let issuer: String?
        let info: Info

        struct Info: Decodable {
            let secret: String?
            let algo: String?
            let digits: Int?
            let period: Int?
            let counter: UInt64?
        }
    }

    /// Present only so `slots` can be detected without describing a structure this app has
    /// no use for. Decodes anything and keeps nothing.
    private struct JSONAny: Decodable {
        init(from decoder: any Decoder) throws {
            _ = try decoder.singleValueContainer()
        }
    }
}
