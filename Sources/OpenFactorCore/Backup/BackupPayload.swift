import Foundation

/// The decrypted contents of an archive: the accounts themselves.
///
/// Two rules govern everything here, and they pull in opposite directions on purpose,
/// which is the whole design set at gate A1 and repeated in `docs/BACKUP_FORMAT.md`:
///
/// **Values that change a generated code are never guessed.** A missing or unrecognised
/// `algorithm`, `digits`, `period`, `counter` or `secret` refuses that account and names it.
/// Substituting a default produces codes that look correct and are rejected forever, and the
/// user finds out at a login rather than at the import.
///
/// **Cosmetic values fall back.** An unrecognised colour becomes the default and a missing
/// `sortIndex` places the account at the end, because losing an account over its card colour
/// would be absurd.
///
/// One account failing never fails the archive. A file of ten with one damaged record
/// imports nine and says which one did not come across.
enum BackupPayload {

    /// The exact spellings this format uses. Matched byte for byte in both directions: a
    /// writer emitting `sha1` produces an archive a strict reader refuses, permanently.
    private enum Key {
        static let accounts = "accounts"
        static let type = "type"
        static let secret = "secret"
        static let algorithm = "algorithm"
        static let digits = "digits"
        static let period = "period"
        static let counter = "counter"
        static let issuer = "issuer"
        static let name = "name"
        static let color = "color"
        static let sortIndex = "sortIndex"
    }

    /// RFC 4226's minimum key length. A secret shorter than this is refused rather than
    /// imported: without the rule an empty secret passes every other test and generates
    /// codes under an empty key, which look correct and never work.
    /// Read from `AccountLimits` so there is one definition rather than five. These were the
    /// original home of both rules, which is why three enrollment paths never applied them: a
    /// rule about what an account *is*, kept in the file that reads archives, is a rule the rest
    /// of the app has to remember to go and find.
    static let minimumSecretBytes = AccountLimits.minimumSecretBytes

    /// The largest `counter` a JSON number can hold exactly. A reader whose parser uses
    /// doubles must refuse anything beyond it rather than importing a silently corrupted
    /// counter, which is the same permanent failure as a truncated secret.
    static let maximumCounter = AccountLimits.maximumCounter

    // MARK: - Reading

    static func read(_ data: Data) -> ImportResult? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data),
            let object = root as? [String: Any],
            let entries = object[Key.accounts] as? [Any]
        else {
            return nil
        }

        var accounts: [ImportedAccount] = []
        var refusals: [ImportRefusal] = []

        for (index, entry) in entries.enumerated() {
            guard let fields = entry as? [String: Any] else {
                refusals.append(
                    ImportRefusal(position: index + 1, label: nil, reason: .malformed)
                )
                continue
            }

            let label = (fields[Key.issuer] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (fields[Key.name] as? String).flatMap { $0.isEmpty ? nil : $0 }

            switch build(fields, sortIndex: index) {
            case let .success(imported):
                accounts.append(imported)
            case let .failure(reason):
                refusals.append(
                    ImportRefusal(position: index + 1, label: label, reason: reason)
                )
            }
        }

        // An empty `accounts` array is valid. It imports nothing and is not an error, so an
        // archive of no accounts must not be reported as a file that could not be read.
        return ImportResult(accounts: accounts, refusals: refusals)
    }

    private static func build(
        _ fields: [String: Any],
        sortIndex fallbackIndex: Int
    ) -> Result<ImportedAccount, ImportRefusal.Reason> {
        guard let type = fields[Key.type] as? String else {
            return .failure(.malformed)
        }
        guard type == "totp" || type == "hotp" else {
            return .failure(.unsupportedType(type))
        }

        guard let secretText = fields[Key.secret] as? String else {
            return .failure(.missingSecret)
        }
        let secret: Data
        do {
            secret = try Base32.decode(secretText)
        } catch {
            return .failure(.secretNotBase32)
        }
        // `secretTooShort`, not `secretNotBase32`. The old reason was false for exactly this
        // case: the secret decodes perfectly and is merely short, so anybody debugging a refused
        // restore went hunting for an invalid character that was not there.
        guard AccountLimits.isSecretLongEnough(secret) else {
            return .failure(.secretTooShort)
        }

        guard let algorithmText = fields[Key.algorithm] as? String else {
            return .failure(.missingSetting(.algorithm))
        }
        guard let algorithm = OTPAlgorithm(rawValue: algorithmText) else {
            return .failure(.unsupportedAlgorithm(algorithmText))
        }

        guard let digitsValue = integer(fields[Key.digits]) else {
            return .failure(.missingSetting(.digits))
        }
        guard let digits = OTPDigits(rawValue: Int(digitsValue)) else {
            return .failure(.unsupportedDigits(Int(digitsValue)))
        }

        let generator: OTPGenerator

        if type == "hotp" {
            // `period` on an hotp account is ignored under the unknown fields rule, not an
            // error. The counter is the field that must be exact.
            guard let counter = integer(fields[Key.counter]), counter >= 0 else {
                return .failure(.malformed)
            }
            guard UInt64(counter) <= maximumCounter else {
                return .failure(.malformed)
            }
            generator = .hotp(counter: UInt64(counter), digits: digits, algorithm: algorithm)
        } else {
            guard let period = integer(fields[Key.period]) else {
                return .failure(.missingSetting(.period))
            }
            do {
                generator = .totp(
                    try TOTPConfiguration(
                        algorithm: algorithm, digits: digits, period: Int(period)
                    )
                )
            } catch {
                return .failure(.unsupportedPeriod(Int(period)))
            }
        }

        let issuer = (fields[Key.issuer] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let account = OTPAccount(
            issuer: issuer,
            name: fields[Key.name] as? String ?? "",
            secret: secret,
            generator: generator
        )

        // Cosmetic, so both fall back rather than failing the account.
        let color = (fields[Key.color] as? String).flatMap(AccountColor.init(rawValue:)) ?? .default
        let sortIndex = integer(fields[Key.sortIndex]).map(Int.init) ?? fallbackIndex

        return .success(ImportedAccount(account: account, color: color, sortIndex: sortIndex))
    }

    /// A JSON number that is genuinely an integer.
    ///
    /// `as? Int` on an `NSNumber` holding 6.5 succeeds and yields 6, which is exactly the
    /// silent corruption the format forbids for `counter`. The value is checked for a
    /// fractional part and for the range a JSON number represents exactly, and a `true` is
    /// refused rather than read as 1, since `NSNumber` does not distinguish them by type.
    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }

        let double = number.doubleValue
        guard double == double.rounded(), double.magnitude <= Double(maximumCounter) else {
            return nil
        }
        return number.int64Value
    }

    // MARK: - Writing

    /// The accounts, as the bytes that get encrypted.
    ///
    /// Keys are sorted, which makes the output of two runs over the same accounts identical
    /// and makes a diff of two archives meaningful to whoever is auditing one. Slashes are
    /// not escaped, because `\/` is legal JSON that no reader needs and every human reading
    /// a hex dump has to decode by eye.
    /// - Throws: `BackupError.cannotStoreAccount` if any account violates the format's own
    ///   rules. **The writer refuses rather than emitting something the reader must reject**,
    ///   which is the whole point: an archive that cannot be restored is worse than no archive,
    ///   because its owner does not learn the difference until the originals are gone.
    ///
    ///   The enrollment paths refuse these values now, so a store should not contain one. Should
    ///   is not a guarantee: an account saved before those guards existed is still there, and
    ///   this is where it must be caught. Failing the whole export is deliberate and matches
    ///   `collectAccounts`, which already takes the position that a backup missing accounts is
    ///   worse than none.
    static func write(_ accounts: [ImportedAccount]) throws -> Data {
        for imported in accounts where !AccountLimits.isStorable(imported.account) {
            throw BackupError.cannotStoreAccount(
                label: imported.account.issuer ?? imported.account.name)
        }

        let entries: [[String: Any]] = accounts.map { imported in
            var fields: [String: Any] = [
                Key.secret: Base32.encode(imported.account.secret, padded: false),
                Key.name: imported.account.name,
                Key.color: imported.color.rawValue,
                Key.sortIndex: imported.sortIndex,
            ]

            if let issuer = imported.account.issuer { fields[Key.issuer] = issuer }

            switch imported.account.generator {
            case let .totp(configuration):
                fields[Key.type] = "totp"
                fields[Key.algorithm] = configuration.algorithm.rawValue
                fields[Key.digits] = configuration.digits.rawValue
                fields[Key.period] = configuration.period
            case let .hotp(counter, digits, algorithm):
                fields[Key.type] = "hotp"
                fields[Key.algorithm] = algorithm.rawValue
                fields[Key.digits] = digits.rawValue
                fields[Key.counter] = counter
            }

            return fields
        }

        return try JSONSerialization.data(
            withJSONObject: [Key.accounts: entries],
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }
}
