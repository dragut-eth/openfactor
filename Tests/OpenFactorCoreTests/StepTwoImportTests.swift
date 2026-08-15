import Foundation
import Testing

@testable import OpenFactorCore

/// Reading Step Two's export.
///
/// The fixture is synthesised rather than copied from a real export, which would have been
/// gitignored and taken the tests with it when it moved. It reproduces the constructs that
/// actually break a reader: both spellings of the `U+2028` separator, an RTF hex escape in
/// an accented label, a lower case secret, a period and digit count that are not the
/// defaults, and one secret containing characters Base32 excludes.
@Suite("Step Two import")
struct StepTwoImportTests {

    /// Loaded through `#filePath` rather than `Bundle.module`, because these sources are
    /// compiled into the app test target as well, where `Bundle.module` does not exist.
    private var fixture: String {
        get throws {
            let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            let file = here.appendingPathComponent("Fixtures/StepTwoExport.rtf")
            return try String(contentsOf: file, encoding: .utf8)
        }
    }

    @Test("Four of the five accounts import, and the fifth is named")
    func readsTheFixture() throws {
        let result = StepTwoImport.read(try fixture)

        #expect(result.accounts.count == 4)
        #expect(result.refusals.count == 1)
    }

    /// The whole account list is one RTF paragraph separated by `U+2028`, so a reader that
    /// splits on newlines sees a single enormous line and finds one account or none.
    @Test("The U+2028 separators are understood, not treated as one line")
    func splitsOnLineSeparators() throws {
        let issuers = StepTwoImport.read(try fixture).accounts.map(\.account.issuer)
        #expect(issuers == ["GitHub", "Fastmail", "Café Central", "Proton"])
    }

    /// An accented label arrives as `\'e9`. A scanner that does not decode it renames the
    /// account, which is silent and permanent.
    @Test("An RTF escaped accent survives the read")
    func decodesRTFEscapes() throws {
        let result = StepTwoImport.read(try fixture)
        #expect(result.accounts.contains { $0.account.issuer == "Café Central" })
    }

    /// Refusing the whole file for one bad record punishes the user for someone else's
    /// data. Dropping it silently is worse: an authenticator with a hole in it.
    @Test("The unusable secret is refused by name, and the rest still import")
    func refusesOnlyTheBadAccount() throws {
        let result = StepTwoImport.read(try fixture)
        let refusal = try #require(result.refusals.first)

        #expect(refusal.label == "Okta")
        #expect(refusal.reason == .secretNotBase32)
        #expect(!result.accounts.contains { $0.account.issuer == "Okta" })
    }

    /// "30 seconds" is prose. A reader that expects a number gets nothing, and one that
    /// substitutes a default silently produces codes that are rejected forever.
    @Test("Period and digits are read, including values that are not the defaults")
    func readsNonDefaultConfiguration() throws {
        let result = StepTwoImport.read(try fixture)
        let proton = try #require(result.accounts.first { $0.account.issuer == "Proton" })

        guard case let .totp(configuration) = proton.account.generator else {
            Issue.record("expected a time based account")
            return
        }

        #expect(configuration.period == 60)
        #expect(configuration.digits == .eight)
        #expect(configuration.algorithm == .sha256)
    }

    @Test("A default period and digit count are read too")
    func readsDefaultConfiguration() throws {
        let result = StepTwoImport.read(try fixture)
        let github = try #require(result.accounts.first { $0.account.issuer == "GitHub" })

        guard case let .totp(configuration) = github.account.generator else {
            Issue.record("expected a time based account")
            return
        }

        #expect(configuration.period == 30)
        #expect(configuration.digits == .six)
        #expect(configuration.algorithm == .sha1)
    }

    /// Their palette names overlap ours, so an import can carry someone's colours across
    /// rather than turning every card blue.
    @Test("Colours map across where the names coincide, and fall back where they do not")
    func mapsColours() throws {
        let accounts = StepTwoImport.read(try fixture).accounts
        let byIssuer = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.account.issuer ?? "", $0.color) }
        )

        #expect(byIssuer["Fastmail"] == .indigo)
        #expect(byIssuer["Café Central"] == .yellow)
        #expect(byIssuer["Proton"] == .teal)
        // "Default color" is not one of ours, and cosmetic values fall back rather than
        // failing the account.
        #expect(byIssuer["GitHub"] == .default)
    }

    /// Base32 is lenient about case by design, and real exports contain lower case.
    @Test("A lower case secret decodes")
    func acceptsLowercaseSecrets() throws {
        let result = StepTwoImport.read(try fixture)
        let fastmail = try #require(result.accounts.first { $0.account.issuer == "Fastmail" })
        #expect(!fastmail.account.secret.isEmpty)
    }

    @Test("The account label is read, not just the issuer")
    func readsAccountLabels() throws {
        let result = StepTwoImport.read(try fixture)
        let github = try #require(result.accounts.first { $0.account.issuer == "GitHub" })
        #expect(github.account.name == "octocat@example.com")
    }

    /// The document's prose, its headings, and the Settings section at the end must not
    /// become accounts. Only known labels are read, which is what keeps them out.
    @Test("Prose and the settings section are not mistaken for accounts")
    func ignoresEverythingElse() throws {
        let result = StepTwoImport.read(try fixture)
        #expect(result.accounts.count + result.refusals.count == 5)
    }

    // MARK: - Files that are not a Step Two export

    @Test("An unrelated file yields nothing rather than failing")
    func ignoresUnrelatedFiles() {
        #expect(StepTwoImport.read("hello, world").isEmpty)
        #expect(StepTwoImport.read("").isEmpty)
        #expect(StepTwoImport.read("{\\rtf1\\ansi nothing to see}").isEmpty)
    }

    /// A localised export is the known limitation of reading a document written for humans.
    /// It must produce nothing rather than something wrong.
    @Test("A localised export yields nothing rather than wrong accounts")
    func ignoresLocalisedExports() {
        let french = """
            {\\rtf1\\ansi Nom du compte: GitHub\\uc0\\u8232 Cl\\'e9 secr\\'e8te: \
            AAAAAAAAAAAAAAAA\\u8232 }
            """
        #expect(StepTwoImport.read(french).isEmpty)
    }

    @Test("A record with no secret is refused rather than imported blank")
    func refusesMissingSecret() {
        let rtf = "{\\rtf1\\ansi Account Name: GitHub\\uc0\\u8232 Digits: 6\\u8232 }"
        let result = StepTwoImport.read(rtf)

        #expect(result.accounts.isEmpty)
        #expect(result.refusals.first?.reason == .missingSecret)
        #expect(result.refusals.first?.position == 1)
    }

    /// Their export cannot currently contain these, but the file is not a contract, so an
    /// unfamiliar value must be refused rather than guessed at.
    @Test("An algorithm OpenFactor does not implement is refused by name")
    func refusesUnknownAlgorithm() {
        let rtf = """
            {\\rtf1\\ansi Account Name: X\\uc0\\u8232 Secret Key: AAAAAAAAAAAAAAAA\\u8232 \
            Hash Algorithm: md5\\u8232 }
            """
        let result = StepTwoImport.read(rtf)
        #expect(result.refusals.first?.reason == .unsupportedAlgorithm("md5"))
    }
}
