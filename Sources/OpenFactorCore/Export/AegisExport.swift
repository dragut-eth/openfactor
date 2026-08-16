import Foundation

/// Writing an Aegis compatible vault, unencrypted.
///
/// **This is the escape hatch, and it is plaintext.** It exists because an authenticator you
/// cannot leave is a trap, and because a file other apps genuinely import is a better way
/// out than a list of URIs nobody accepts. Everything in it is readable by anything that can
/// open a text file: every secret, in the clear, with the issuer beside it.
///
/// The encrypted archive is the backup. This is the door.
///
/// ## What is emitted, and against which version
///
/// Vault version 1, database version 3, per the Aegis vault format documentation at
/// [`f91b6f0`](https://github.com/beemdevelopment/Aegis/blob/f91b6f04667b99977ed9739a0e15b8d1837f73e8/docs/vault.md),
/// dated 1 March 2024. The revision is pinned rather than named as "current" because Aegis
/// is another project's format and a moving target, and "compatible" without a version is
/// exactly the unverifiable claim `docs/BACKUP_FORMAT.md` exists to avoid. If Aegis moves,
/// this comment is how the next person knows what this was written against.
///
/// Only `totp` and `hotp` entries are written, because they are the only kinds this app
/// holds. Aegis also defines `steam`, `motp` and `yandex`, and a writer that emitted one of
/// those without generating those codes would be lying about what it exported.
public enum AegisExport {

    public static let vaultVersion = 1
    public static let databaseVersion = 3

    public static func write(_ accounts: [ImportedAccount]) throws -> Data {
        let entries: [[String: Any]] = accounts.map { imported in
            var info: [String: Any] = [
                "secret": Base32.encode(imported.account.secret, padded: false)
            ]

            let type: String

            switch imported.account.generator {
            case let .totp(configuration):
                type = "totp"
                info["algo"] = configuration.algorithm.rawValue
                info["digits"] = configuration.digits.rawValue
                info["period"] = configuration.period
            case let .hotp(counter, digits, algorithm):
                type = "hotp"
                info["algo"] = algorithm.rawValue
                info["digits"] = digits.rawValue
                info["counter"] = counter
            }

            return [
                "type": type,
                // Aegis identifies entries by a version 4 UUID. A fresh one is minted per
                // entry per export, because this app has no identifier to carry across:
                // the record's own id is a device local thing that the encrypted archive
                // deliberately does not carry either, and deriving one from the secret
                // would be a habit worth not forming even where it is harmless.
                "uuid": UUID().uuidString.lowercased(),
                "name": imported.account.name,
                "issuer": imported.account.issuer ?? "",
                // Written with neutral values rather than omitted. They are part of the
                // shape Aegis documents, and a reader that expects them is likelier than
                // one that objects to them.
                "note": "",
                "favorite": false,
                "icon": NSNull(),
                "info": info,
            ]
        }

        let vault: [String: Any] = [
            "version": vaultVersion,
            // Null slots and null params are what marks a vault as unencrypted. This is the
            // same pair the importer checks in the other direction.
            "header": ["slots": NSNull(), "params": NSNull()],
            "db": [
                "version": databaseVersion,
                "entries": entries,
            ],
        ]

        return try JSONSerialization.data(
            withJSONObject: vault,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }
}
