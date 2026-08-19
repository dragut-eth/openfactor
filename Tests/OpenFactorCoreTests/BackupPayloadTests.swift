import Foundation
import Testing

@testable import OpenFactorCore

/// The accounts inside an archive, and the two rules that pull in opposite directions.
///
/// Values that change a generated code are never guessed. Cosmetic values fall back. Almost
/// every test here is one or the other, and the reason the distinction is worth this much
/// coverage is that both failures are invisible at import: a defaulted algorithm produces
/// codes that look exactly like working ones and are rejected forever, and the user finds
/// out at a login rather than here.
@Suite("Backup payload")
struct BackupPayloadTests {

    private func payload(_ accounts: String) -> Data {
        Data(#"{"accounts":[\#(accounts)]}"#.utf8)
    }

    private func account(
        secret: String = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
        extra: String = ""
    ) -> Data {
        payload(
            """
            {"type":"totp","secret":"\(secret)","algorithm":"SHA1","digits":6,"period":30\
            \(extra)}
            """
        )
    }

    private func read(_ data: Data) throws -> ImportResult {
        try #require(BackupPayload.read(data))
    }

    // MARK: - Secrets, lenient as to form and strict as to content

    @Test(
        "The same secret written four ways decodes to the same bytes",
        arguments: [
            "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            "gezdgnbvgy3tqojqgezdgnbvgy3tqojq",
            "GEZD GNBV GY3T QOJQ GEZD GNBV GY3T QOJQ",
            "GEZD-GNBV-GY3T-QOJQ-GEZD-GNBV-GY3T-QOJQ",
        ]
    )
    func acceptsEveryFormOfTheSameSecret(secret: String) throws {
        let result = try read(account(secret: secret))

        #expect(result.refusals.isEmpty)
        #expect(result.accounts.first?.account.secret == Data("12345678901234567890".utf8))
    }

    /// Each of these would otherwise produce an account that generates codes forever
    /// rejected by the service, which is worse than not importing it.
    @Test(
        "A secret that cannot be trusted refuses the account",
        arguments: [
            "",  // decodes to nothing and would generate codes under an empty key
            "GEZDGNBV1",  // 1 is not in the alphabet
            "GEZDGNBVG",  // nine characters, which no valid Base32 produces
            "GEZDGNBV",  // valid Base32, five bytes, under RFC 4226's ten byte minimum
        ]
    )
    func refusesUntrustworthySecrets(secret: String) throws {
        let result = try read(account(secret: secret))

        #expect(result.accounts.isEmpty)
        #expect(result.refusals.count == 1)

        // **The reason has to be true, not merely a refusal.** `secretNotBase32` was reported
        // for a secret that decodes perfectly and is only short, so gate A4 pointed out that
        // anybody debugging a refused restore was sent looking for an invalid character that
        // did not exist. Empty and short are the same kind of wrong and now say so.
        let expected: ImportRefusal.Reason =
            switch secret {
            case "", "GEZDGNBV": .secretTooShort
            default: .secretNotBase32
            }
        #expect(result.refusals.first?.reason == expected)
    }

    /// The rule the format spells out for the same reason the passphrase rule does: a
    /// locale aware uppercase turns `i` into `İ`, and a full Unicode one turns `ß` into
    /// `SS`, two characters that are in the alphabet. Either would decode a secret its
    /// owner never wrote.
    @Test("Case mapping is ASCII only, so a stray letter refuses rather than becoming one")
    func caseMappingIsASCIIOnly() throws {
        let result = try read(account(secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJß"))

        #expect(result.accounts.isEmpty)
        #expect(result.refusals.first?.reason == .secretNotBase32)
    }

    // MARK: - Never guessing what changes a code

    @Test("A missing setting that changes the code refuses the account by name")
    func refusesMissingSettings() throws {
        let cases: [(String, ImportRefusal.Reason)] = [
            (
                #"{"type":"totp","secret":"GEZDGNBVGY3TQOJQ","digits":6,"period":30}"#,
                .missingSetting(.algorithm)
            ),
            (
                #"{"type":"totp","secret":"GEZDGNBVGY3TQOJQ","algorithm":"SHA1","period":30}"#,
                .missingSetting(.digits)
            ),
            (
                #"{"type":"totp","secret":"GEZDGNBVGY3TQOJQ","algorithm":"SHA1","digits":6}"#,
                .missingSetting(.period)
            ),
        ]

        for (entry, expected) in cases {
            let result = try read(payload(entry))
            #expect(result.accounts.isEmpty)
            #expect(result.refusals.first?.reason == expected)
        }
    }

    @Test("An unrecognised enumerated value refuses rather than falling back")
    func refusesUnknownEnumerations() throws {
        let lowercased = payload(
            #"{"type":"totp","secret":"GEZDGNBVGY3TQOJQ","algorithm":"sha1","digits":6,"period":30}"#
        )
        #expect(try read(lowercased).refusals.first?.reason == .unsupportedAlgorithm("sha1"))

        let unknownType = payload(
            #"{"type":"steam","secret":"GEZDGNBVGY3TQOJQ","algorithm":"SHA1","digits":6,"period":30}"#
        )
        #expect(try read(unknownType).refusals.first?.reason == .unsupportedType("steam"))
    }

    /// A JSON parser that represents numbers as doubles reads 6.5 as 6 through `as? Int`,
    /// which is the silent corruption the format forbids. A counter is the field where that
    /// is unrecoverable: every code after it is rejected and nothing says why.
    @Test("A counter that is not an exact integer refuses the account")
    func refusesInexactCounters() throws {
        for counter in ["4.5", "9007199254740992", "-1", "true", #""8""#] {
            let entry = payload(
                """
                {"type":"hotp","secret":"GEZDGNBVGY3TQOJQ","algorithm":"SHA1","digits":6,\
                "counter":\(counter)}
                """
            )
            #expect(try read(entry).accounts.isEmpty, "counter \(counter) must be refused")
        }
    }

    @Test("The largest counter a JSON number holds exactly is accepted")
    func acceptsTheLargestExactCounter() throws {
        let entry = payload(
            """
            {"type":"hotp","secret":"GEZDGNBVGY3TQOJQ","algorithm":"SHA1","digits":6,\
            "counter":9007199254740991}
            """
        )

        #expect(
            try read(entry).accounts.first?.account.generator
                == .hotp(counter: 9_007_199_254_740_991, digits: .six, algorithm: .sha1)
        )
    }

    // MARK: - Cosmetic values fall back

    @Test("An unrecognised colour becomes the default rather than failing the account")
    func colourFallsBack() throws {
        let result = try read(account(extra: #","color":"chartreuse""#))

        #expect(result.refusals.isEmpty)
        #expect(result.accounts.first?.color == .default)
    }

    @Test("A missing sortIndex places the account where it appeared")
    func sortIndexFallsBack() throws {
        let two = Data(
            """
            {"accounts":[\
            {"type":"totp","secret":"GEZDGNBVGY3TQOJQ","algorithm":"SHA1","digits":6,"period":30},\
            {"type":"totp","secret":"JBSWY3DPEHPK3PXP","algorithm":"SHA1","digits":6,"period":30}]}
            """.utf8
        )

        #expect(try read(two).accounts.map(\.sortIndex) == [0, 1])
    }

    // MARK: - Everything else the format pins down

    @Test("An unknown field is ignored, not rejected")
    func ignoresUnknownFields() throws {
        let result = try read(account(extra: #","icon":"data:whatever","note":{"a":1}"#))

        #expect(result.refusals.isEmpty)
        #expect(result.accounts.count == 1)
    }

    /// Under the unknown fields rule these are not errors, and saying so here stops a future
    /// reader from being tightened into refusing them.
    @Test("A period on a counter based account, or a counter on a time based one, is ignored")
    func ignoresIrrelevantFields() throws {
        let hotp = payload(
            """
            {"type":"hotp","secret":"GEZDGNBVGY3TQOJQ","algorithm":"SHA1","digits":6,\
            "counter":3,"period":30}
            """
        )
        #expect(
            try read(hotp).accounts.first?.account.generator
                == .hotp(counter: 3, digits: .six, algorithm: .sha1))

        let totp = payload(
            """
            {"type":"totp","secret":"GEZDGNBVGY3TQOJQ","algorithm":"SHA1","digits":6,\
            "period":30,"counter":99}
            """
        )
        #expect(try read(totp).accounts.count == 1)
    }

    @Test("One bad account does not fail the file, and is reported by position")
    func oneBadAccountDoesNotFailTheFile() throws {
        let mixed = Data(
            """
            {"accounts":[\
            {"type":"totp","secret":"GEZDGNBVGY3TQOJQ","algorithm":"SHA1","digits":6,"period":30},\
            {"type":"totp","secret":"nope","algorithm":"SHA1","digits":6,"period":30},\
            {"type":"totp","secret":"JBSWY3DPEHPK3PXP","algorithm":"SHA1","digits":6,"period":30}]}
            """.utf8
        )

        let result = try read(mixed)

        #expect(result.accounts.count == 2)
        #expect(result.refusals.count == 1)
        #expect(result.refusals.first?.position == 2)
    }

    @Test("An account with no issuer and no name is reported by its position")
    func namelessAccountsAreReportedByPosition() throws {
        let result = try read(payload(#"{"type":"totp","secret":"nope"}"#))

        #expect(result.refusals.first?.label == nil)
        #expect(result.refusals.first?.position == 1)
    }

    @Test("An empty accounts array is valid and is not an error")
    func emptyIsValid() throws {
        let result = try read(Data(#"{"accounts":[]}"#.utf8))

        #expect(result.accounts.isEmpty)
        #expect(result.refusals.isEmpty)
    }

    @Test("Something that is not a payload is not read as an empty one")
    func rejectsNonPayloads() {
        #expect(BackupPayload.read(Data("not json".utf8)) == nil)
        #expect(BackupPayload.read(Data("{}".utf8)) == nil)
        #expect(BackupPayload.read(Data(#"{"accounts":{}}"#.utf8)) == nil)
    }

    // MARK: - Writing

    @Test("Written accounts read back as themselves")
    func writeRoundTrips() throws {
        let accounts = [
            ImportedAccount(
                account: OTPAccount(
                    issuer: "GitHub",
                    name: "octocat",
                    secret: try Base32.decode("GEZDGNBVGY3TQOJQ"),
                    generator: .totp(
                        try TOTPConfiguration(algorithm: .sha512, digits: .eight, period: 15))
                ),
                color: .pink,
                sortIndex: 7
            )
        ]

        let result = try read(try BackupPayload.write(accounts))

        #expect(result.accounts == accounts)
    }

    /// A writer emitting `sha1` produces an archive a conforming reader refuses,
    /// permanently, so the spellings are asserted rather than trusted to an enum's
    /// `rawValue` staying put.
    @Test("The writer emits the exact spellings the format lists")
    func writerEmitsExactSpellings() throws {
        let data = try BackupPayload.write([
            ImportedAccount(
                account: OTPAccount(
                    issuer: nil,
                    name: "",
                    secret: try Base32.decode("GEZDGNBVGY3TQOJQ"),
                    generator: .totp(
                        try TOTPConfiguration(algorithm: .sha256, digits: .six, period: 30))
                ),
                color: .gray,
                sortIndex: 0
            )
        ])

        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains(#""type":"totp""#))
        #expect(text.contains(#""algorithm":"SHA256""#))
        #expect(text.contains(#""color":"gray""#))
        // Omitted rather than written as null, which the format has no place for.
        #expect(!text.contains("issuer"))
    }
}
