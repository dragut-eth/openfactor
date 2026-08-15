import Foundation
import Testing

@testable import OpenFactorCore

/// Reading an Aegis vault.
///
/// Unlike the labelled text reader, this one is strict: Aegis publishes its format, so an
/// unfamiliar value is a real disagreement rather than a document that got reworded.
@Suite("Aegis import")
struct AegisImportTests {

    private func vault(entries: String, header: String = #"{"slots": null, "params": null}"#) -> Data {
        Data("""
            {"version": 1, "header": \(header), "db": {"version": 3, "entries": [\(entries)]}}
            """.utf8)
    }

    private let github = """
        {"type":"totp","uuid":"a","name":"octocat","issuer":"GitHub","note":"","icon":null,
         "info":{"secret":"GEZDGNBVGY3TQOJQ","algo":"SHA1","digits":6,"period":30}}
        """

    @Test("A plain vault imports")
    func readsPlainVault() throws {
        let result = try AegisImport.read(vault(entries: github))

        #expect(result.accounts.count == 1)
        #expect(result.refusals.isEmpty)

        let account = try #require(result.accounts.first).account
        #expect(account.issuer == "GitHub")
        #expect(account.name == "octocat")
    }

    /// The refusal that matters, because the alternative is a dependency. It must name the
    /// fix rather than merely failing.
    @Test("An encrypted vault is refused with something the user can act on")
    func refusesEncryptedVault() {
        let encrypted = Data("""
            {"version":1,"header":{"slots":[{"type":1}],"params":{"nonce":"00","tag":"00"}},
             "db":"YmFzZTY0IGNpcGhlcnRleHQ="}
            """.utf8)

        #expect(throws: AegisImport.FileError.encrypted) {
            try AegisImport.read(encrypted)
        }
        #expect(AegisImport.FileError.encrypted.description.contains("encryption turned off"))
    }

    @Test("A file that is not an Aegis vault is refused as such")
    func refusesUnrelatedFiles() {
        #expect(throws: AegisImport.FileError.notAegis) {
            try AegisImport.read(Data("hello".utf8))
        }
        #expect(throws: AegisImport.FileError.notAegis) {
            try AegisImport.read(Data(#"{"unrelated": true}"#.utf8))
        }
    }

    @Test("A counter based entry keeps its counter")
    func readsHOTP() throws {
        let hotp = """
            {"type":"hotp","name":"a","issuer":"Bank",
             "info":{"secret":"GEZDGNBVGY3TQOJQ","algo":"SHA1","digits":6,"counter":42}}
            """
        let result = try AegisImport.read(vault(entries: hotp))
        let account = try #require(result.accounts.first).account

        guard case let .hotp(counter, _, _) = account.generator else {
            Issue.record("expected a counter based account")
            return
        }
        #expect(counter == 42)
    }

    /// Aegis supports kinds this app does not. Importing one as a plain TOTP account would
    /// generate codes the service rejects, so it is refused by name.
    @Test("A kind OpenFactor does not implement is refused by name")
    func refusesUnsupportedTypes() throws {
        let steam = """
            {"type":"steam","name":"a","issuer":"Steam",
             "info":{"secret":"GEZDGNBVGY3TQOJQ","algo":"SHA1","digits":5,"period":30}}
            """
        let result = try AegisImport.read(vault(entries: steam))

        #expect(result.accounts.isEmpty)
        #expect(result.refusals.first?.reason == .unsupportedType("steam"))
        #expect(result.refusals.first?.label == "Steam")
    }

    @Test("One bad entry does not fail the others")
    func refusesPerEntry() throws {
        let bad = """
            {"type":"totp","name":"b","issuer":"Broken",
             "info":{"secret":"1111","algo":"SHA1","digits":6,"period":30}}
            """
        let result = try AegisImport.read(vault(entries: "\(github), \(bad)"))

        #expect(result.accounts.count == 1)
        #expect(result.refusals.count == 1)
        #expect(result.refusals.first?.reason == .secretNotBase32)
        #expect(result.refusals.first?.position == 2)
    }

    @Test("An empty vault is read as empty rather than as an error")
    func readsEmptyVault() throws {
        let result = try AegisImport.read(vault(entries: ""))
        #expect(result.isEmpty)
    }

    @Test("Missing optional fields fall back to the usual defaults")
    func appliesDefaults() throws {
        let sparse = """
            {"type":"totp","name":"a","issuer":"Sparse","info":{"secret":"GEZDGNBVGY3TQOJQ"}}
            """
        let result = try AegisImport.read(vault(entries: sparse))
        let account = try #require(result.accounts.first).account

        guard case let .totp(configuration) = account.generator else {
            Issue.record("expected a time based account")
            return
        }
        #expect(configuration.algorithm == .sha1)
        #expect(configuration.digits == .six)
        #expect(configuration.period == 30)
    }
}
