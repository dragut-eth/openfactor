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

        for (index, entry) in database.entries.enumerated() {
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
        enum Database: Decodable {
            case plain(Contents)
            case encrypted

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let contents = try? container.decode(Contents.self) {
                    self = .plain(contents)
                } else {
                    self = .encrypted
                }
            }
        }

        struct Contents: Decodable {
            let entries: [Entry]
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
