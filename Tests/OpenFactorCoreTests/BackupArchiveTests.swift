import Foundation
import Testing

@testable import OpenFactorCore

/// Reading and writing whole archives, which is where the format's rules about refusing
/// live.
///
/// The vector suite proves the cryptography. This one proves the parts around it that a
/// vector cannot reach: what a reader refuses and in what order, that the `passphrase` field
/// changes performance and never outcome, and that an archive this app writes is one it can
/// read back.
@Suite("Backup archive")
struct BackupArchiveTests {

    /// Deliberately low, and legal. Every test here would otherwise pay 600,000 iterations
    /// several times over to prove something that has nothing to do with the work factor.
    /// The floor itself is asserted separately, with the real number.
    private static let iterations = 100_000

    private func account(
        _ issuer: String,
        secret: String = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
        color: AccountColor = .blue,
        sortIndex: Int = 0
    ) throws -> ImportedAccount {
        ImportedAccount(
            account: OTPAccount(
                issuer: issuer,
                name: "octocat",
                secret: try Base32.decode(secret),
                generator: .totp(
                    try TOTPConfiguration(algorithm: .sha256, digits: .eight, period: 60)
                )
            ),
            color: color,
            sortIndex: sortIndex
        )
    }

    private func archive(
        _ accounts: [ImportedAccount],
        passphrase: String = "YZTR-THFW-WT6E-OXIV-73XD-QCDM",
        mode: BackupPassphrase.Mode = .generated
    ) throws -> Data {
        try BackupArchive.write(
            accounts, passphrase: passphrase, mode: mode, iterations: Self.iterations
        )
    }

    private func container(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func rebuild(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Round trip

    @Test("An archive this app writes is one it can read")
    func roundTrips() throws {
        let accounts = [
            try account("GitHub", sortIndex: 0),
            try account("Fastmail", secret: "JBSWY3DPEHPK3PXP", color: .purple, sortIndex: 1),
        ]

        let result = try BackupArchive.read(
            try archive(accounts), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM"
        )

        #expect(result.refusals.isEmpty)
        #expect(result.accounts.count == 2)
        #expect(result.accounts.map(\.account.issuer) == ["GitHub", "Fastmail"])
        #expect(result.accounts.map(\.color) == [.blue, .purple])
        #expect(result.accounts.map(\.sortIndex) == [0, 1])
        #expect(result.accounts[0].account.secret == accounts[0].account.secret)
        #expect(result.accounts[0].account.generator == accounts[0].account.generator)
    }

    @Test("A counter based account keeps its counter across an archive")
    func roundTripsCounters() throws {
        let imported = ImportedAccount(
            account: OTPAccount(
                issuer: "Air Canada",
                name: "octocat",
                secret: try Base32.decode("GEZDGNBVGY3TQOJQ"),
                generator: .hotp(counter: 4_503_599_627_370_495, digits: .seven, algorithm: .sha512)
            ),
            color: .teal,
            sortIndex: 3
        )

        let result = try BackupArchive.read(
            try archive([imported]), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM"
        )

        #expect(result.accounts.first?.account.generator == imported.account.generator)
    }

    @Test("An empty archive is valid and imports nothing")
    func emptyArchiveIsValid() throws {
        let result = try BackupArchive.read(
            try archive([]), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM"
        )

        #expect(result.accounts.isEmpty)
        #expect(result.refusals.isEmpty)
    }

    @Test("A custom passphrase round trips without being canonicalised")
    func customPassphraseRoundTrips() throws {
        let passphrase = "  Correct Horse Battery Staple!  "
        let data = try archive([try account("GitHub")], passphrase: passphrase, mode: .custom)

        #expect(throws: Never.self) {
            try BackupArchive.read(data, passphrase: passphrase)
        }
        #expect(throws: BackupError.couldNotOpen) {
            try BackupArchive.read(data, passphrase: "CORRECTHORSEBATTERYSTAPLE")
        }
    }

    // MARK: - The hint orders attempts and decides nothing

    /// The property the whole ordering exists to preserve. An earlier revision of the format
    /// made this field authoritative, which meant one byte of unauthenticated cleartext,
    /// editable by anyone with a text editor, could permanently destroy the only copy of
    /// somebody's secrets.
    @Test("The passphrase hint changes performance, never outcome", arguments: [
        "custom", "GENERATED", "nonsense", "",
    ])
    func hintNeverDecides(hint: String) throws {
        var object = try container(try archive([try account("GitHub")]))
        object["passphrase"] = hint

        let result = try BackupArchive.read(
            try rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM"
        )
        #expect(result.accounts.count == 1)
    }

    @Test("A missing or wrongly typed passphrase hint still opens the archive")
    func hintMayBeAbsent() throws {
        var object = try container(try archive([try account("GitHub")]))
        object.removeValue(forKey: "passphrase")
        #expect(throws: Never.self) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }

        object["passphrase"] = 42
        #expect(throws: Never.self) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }

    @Test("An unknown top level field is ignored, not refused")
    func unknownFieldsAreIgnored() throws {
        var object = try container(try archive([try account("GitHub")]))
        object["padding"] = String(repeating: "A", count: 128)
        object["writtenBy"] = ["app": "something else", "version": 9]

        #expect(throws: Never.self) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }

    // MARK: - What a reader must refuse

    @Test("A wrong passphrase is refused without claiming to know why")
    func wrongPassphraseIsRefused() throws {
        #expect(throws: BackupError.couldNotOpen) {
            try BackupArchive.read(
                try self.archive([try self.account("GitHub")]),
                passphrase: "AAAA-BBBB-CCCC-DDDD-EEEE-FFFF")
        }
    }

    @Test("A file that is not an archive is refused as one")
    func notAnArchive() {
        #expect(throws: BackupError.notAnArchive) {
            try BackupArchive.read(Data("not json".utf8), passphrase: "x")
        }
        #expect(throws: BackupError.notAnArchive) {
            try BackupArchive.read(Data("[1,2,3]".utf8), passphrase: "x")
        }
    }

    @Test("A format this reader does not implement is refused rather than attempted")
    func unknownFormatIsRefused() throws {
        var object = try container(try archive([try account("GitHub")]))
        object["format"] = "openfactor.backup.v2"

        #expect(throws: BackupError.unsupportedFormat("openfactor.backup.v2")) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }

    /// The format string is bound as additional authenticated data, so a reader that case
    /// folded this comparison would authenticate with the file's spelling and report a wrong
    /// passphrase for what is really an unknown version.
    @Test("The format string is compared byte for byte")
    func formatIsCaseSensitive() throws {
        var object = try container(try archive([try account("GitHub")]))
        object["format"] = "OpenFactor.Backup.V1"

        #expect(throws: BackupError.unsupportedFormat("OpenFactor.Backup.V1")) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }

    @Test("An algorithm this reader does not implement is named in the refusal")
    func unknownAlgorithmsAreRefused() throws {
        var object = try container(try archive([try account("GitHub")]))
        var kdf = try #require(object["kdf"] as? [String: Any])
        kdf["algorithm"] = "Argon2id"
        object["kdf"] = kdf

        #expect(throws: BackupError.unsupportedKeyDerivation("Argon2id")) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }

        object = try container(try archive([try account("GitHub")]))
        var cipher = try #require(object["cipher"] as? [String: Any])
        cipher["algorithm"] = "ChaCha20-Poly1305"
        object["cipher"] = cipher

        #expect(throws: BackupError.unsupportedCipher("ChaCha20-Poly1305")) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }

    @Test("An iteration count outside the frozen range is refused", arguments: [
        99_999, 10_000_001, 0, -1,
    ])
    func iterationsAreBounded(count: Int) throws {
        var object = try container(try archive([try account("GitHub")]))
        var kdf = try #require(object["kdf"] as? [String: Any])
        kdf["iterations"] = count
        object["kdf"] = kdf

        #expect(throws: BackupError.iterationsOutOfRange(count)) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }

    /// Both ends of the range are inside it. The floor is proved by opening an archive
    /// actually written at it. The ceiling is proved without deriving anything: `iterations`
    /// is checked before the field lengths are, so a ceiling value paired with a short tag
    /// must fail on the tag. Deriving four keys at ten million iterations to prove the same
    /// point would put the format's own denial of service into the test suite.
    @Test("The bounds of the range are inside it, not outside")
    func iterationBoundsAreInclusive() throws {
        var object = try container(try archive([try account("GitHub")]))
        #expect(object["kdf"].flatMap { ($0 as? [String: Any])?["iterations"] as? Int }
            == Self.iterations)
        #expect(throws: Never.self) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }

        var kdf = try #require(object["kdf"] as? [String: Any])
        kdf["iterations"] = 10_000_000
        object["kdf"] = kdf

        var cipher = try #require(object["cipher"] as? [String: Any])
        cipher["tag"] = BackupBase64.encode(Data(repeating: 0, count: 15))
        object["cipher"] = cipher

        #expect(throws: BackupError.wrongLength(field: "cipher.tag", expected: 16, found: 15)) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }

    @Test("A field of the wrong length is refused by name", arguments: [
        ("kdf", "salt", 32), ("cipher", "nonce", 12), ("cipher", "tag", 16),
    ])
    func lengthsAreChecked(group: String, field: String, expected: Int) throws {
        var object = try container(try archive([try account("GitHub")]))
        var section = try #require(object[group] as? [String: Any])
        section[field] = BackupBase64.encode(Data(repeating: 0, count: expected - 1))
        object[group] = section

        #expect(
            throws: BackupError.wrongLength(
                field: "\(group).\(field)", expected: expected, found: expected - 1)
        ) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }

    @Test("A required field that is missing or of the wrong type is refused", arguments: [
        "format", "kdf", "cipher", "ciphertext",
    ])
    func requiredFieldsAreRequired(field: String) throws {
        var object = try container(try archive([try account("GitHub")]))
        object.removeValue(forKey: field)

        #expect(throws: (any Error).self) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }

        object[field] = 12
        #expect(throws: (any Error).self) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }

    @Test("A file too large to be an archive is refused before it is parsed")
    func oversizeFilesAreRefused() {
        let huge = Data(repeating: UInt8(ascii: "A"), count: 12 * 1024 * 1024)
        #expect(throws: BackupError.tooLarge) {
            try BackupArchive.read(huge, passphrase: "x")
        }
    }

    // MARK: - Base64 leniency

    /// None of these can change the decoded bytes, and every one of them happens to a file
    /// that travelled through a mail client.
    @Test("A reader accepts base64 that a mail client has been through")
    func base64IsLenient() throws {
        var object = try container(try archive([try account("GitHub")]))
        let ciphertext = try #require(object["ciphertext"] as? String)

        let urlSafe = ciphertext
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        object["ciphertext"] = urlSafe
        #expect(throws: Never.self) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }

        object["ciphertext"] = ciphertext.enumerated().map { index, character in
            index % 64 == 0 ? "\n\(character)" : String(character)
        }.joined()
        #expect(throws: Never.self) {
            try BackupArchive.read(
                try self.rebuild(object), passphrase: "YZTR-THFW-WT6E-OXIV-73XD-QCDM")
        }
    }
}
