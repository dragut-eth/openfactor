import Foundation
import Testing

@testable import OpenFactorCore

/// Writing a vault another app can read.
///
/// **What these tests can and cannot prove, stated first.** They prove the file has the
/// shape the Aegis vault documentation describes at the revision this writer was pinned to,
/// and that this project's own reader takes it back unchanged. They cannot prove Aegis
/// itself accepts it: that is one person, one import, once per format change, and no test
/// here substitutes for it.
///
/// So the assertions are deliberately literal. They check the spellings and the version
/// numbers against the document rather than against the writer's own constants, because a
/// test that compares the code to itself would pass through any rename and prove nothing.
@Suite("Aegis export")
struct AegisExportTests {

    private func account(
        _ issuer: String?,
        name: String = "octocat",
        secret: String = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
        generator: OTPGenerator? = nil
    ) throws -> ImportedAccount {
        ImportedAccount(
            account: OTPAccount(
                issuer: issuer,
                name: name,
                secret: try Base32.decode(secret),
                generator: try generator
                    ?? .totp(TOTPConfiguration(algorithm: .sha1, digits: .six, period: 30))
            ),
            color: .blue,
            sortIndex: 0
        )
    }

    private func vault(_ accounts: [ImportedAccount]) throws -> [String: Any] {
        try #require(
            try JSONSerialization.jsonObject(with: try AegisExport.write(accounts))
                as? [String: Any]
        )
    }

    private func entries(_ accounts: [ImportedAccount]) throws -> [[String: Any]] {
        let db = try #require(try vault(accounts)["db"] as? [String: Any])
        return try #require(db["entries"] as? [[String: Any]])
    }

    // MARK: - The shape the format documents

    /// Vault version 1, database version 3, per the Aegis vault documentation at
    /// `f91b6f04667b99977ed9739a0e15b8d1837f73e8`, dated 1 March 2024. Written as literals
    /// here on purpose: if somebody changes the constants in the writer, this fails, which
    /// is the whole point of pinning a version.
    @Test("The vault declares the versions the pinned documentation describes")
    func declaresPinnedVersions() throws {
        let vault = try vault([try account("GitHub")])
        let db = try #require(vault["db"] as? [String: Any])

        #expect(vault["version"] as? Int == 1)
        #expect(db["version"] as? Int == 3)
    }

    /// Null slots and null params are what marks a vault as unencrypted, and it is the same
    /// pair this project's own reader checks in the other direction.
    @Test("The header says unencrypted the way the format says it")
    func headerMarksItUnencrypted() throws {
        let header = try #require(try vault([try account("GitHub")])["header"] as? [String: Any])

        #expect(header["slots"] is NSNull)
        #expect(header["params"] is NSNull)
    }

    @Test("A time based entry carries a period and no counter")
    func timeBasedEntries() throws {
        let entry = try #require(
            try entries([
                try account(
                    "GitHub",
                    generator: .totp(
                        try TOTPConfiguration(algorithm: .sha256, digits: .eight, period: 60))
                )
            ]).first
        )
        let info = try #require(entry["info"] as? [String: Any])

        #expect(entry["type"] as? String == "totp")
        #expect(info["algo"] as? String == "SHA256")
        #expect(info["digits"] as? Int == 8)
        #expect(info["period"] as? Int == 60)
        #expect(info["counter"] == nil)
    }

    @Test("A counter based entry carries a counter and no period")
    func counterBasedEntries() throws {
        let entry = try #require(
            try entries([
                try account(
                    "Air Canada",
                    generator: .hotp(counter: 41, digits: .seven, algorithm: .sha512)
                )
            ]).first
        )
        let info = try #require(entry["info"] as? [String: Any])

        #expect(entry["type"] as? String == "hotp")
        #expect(info["algo"] as? String == "SHA512")
        #expect(info["digits"] as? Int == 7)
        #expect(info["counter"] as? Int == 41)
        #expect(info["period"] == nil)
    }

    @Test("Every entry carries the fields the format lists, including the empty ones")
    func entriesCarryTheDocumentedFields() throws {
        let entry = try #require(try entries([try account("GitHub")]).first)

        #expect(entry["name"] as? String == "octocat")
        #expect(entry["issuer"] as? String == "GitHub")
        #expect(entry["note"] as? String == "")
        #expect(entry["favorite"] as? Bool == false)
        #expect(entry["icon"] is NSNull)

        let uuid = try #require(entry["uuid"] as? String)
        #expect(UUID(uuidString: uuid) != nil)
        #expect(uuid == uuid.lowercased())
    }

    @Test("An account with no issuer writes an empty string rather than null")
    func missingIssuerBecomesEmpty() throws {
        let entry = try #require(try entries([try account(nil)]).first)

        #expect(entry["issuer"] as? String == "")
    }

    @Test("Every entry gets its own identifier")
    func identifiersAreDistinct() throws {
        let written = try entries([
            try account("GitHub"),
            try account("Fastmail", secret: "JBSWY3DPEHPK3PXP"),
            try account("Air Canada", secret: "GEZDGNBVGY3TQOJQ"),
        ])

        #expect(Set(written.compactMap { $0["uuid"] as? String }).count == 3)
    }

    @Test("An empty list writes a valid vault holding nothing")
    func emptyVaultIsValid() throws {
        #expect(try entries([]).isEmpty)
        #expect(try vault([])["version"] as? Int == 1)
    }

    // MARK: - Round trip

    /// Internal consistency, which is the strongest thing a test can assert here. It would
    /// catch a writer and reader drifting apart, and it says nothing about Aegis.
    @Test("A vault this app writes is one it reads back unchanged")
    func roundTripsThroughOurOwnReader() throws {
        let accounts = [
            try account("GitHub"),
            try account(
                "Fastmail",
                name: "someone@fastmail.com",
                secret: "JBSWY3DPEHPK3PXP",
                generator: .totp(try TOTPConfiguration(algorithm: .sha512, digits: .eight, period: 15))
            ),
            try account(
                "Air Canada",
                secret: "GEZDGNBVGY3TQOJQ",
                generator: .hotp(counter: 9, digits: .seven, algorithm: .sha256)
            ),
        ]

        let result = try AegisImport.read(try AegisExport.write(accounts))

        #expect(result.refusals.isEmpty)
        #expect(result.accounts.map(\.account.issuer) == ["GitHub", "Fastmail", "Air Canada"])
        #expect(result.accounts.map(\.account.name) == accounts.map(\.account.name))
        #expect(result.accounts.map(\.account.secret) == accounts.map(\.account.secret))
        #expect(result.accounts.map(\.account.generator) == accounts.map(\.account.generator))
    }

    /// Aegis has no colour concept that maps onto this app's, so the round trip loses it.
    /// Asserted rather than left as a surprise: a person moving out and back would otherwise
    /// find their cards rearranged and have no idea which step did it.
    @Test("Colour does not survive a plain vault, and that is the format's limit")
    func colourIsNotCarried() throws {
        let account = ImportedAccount(
            account: try self.account("GitHub").account, color: .pink, sortIndex: 4
        )

        let result = try AegisImport.read(try AegisExport.write([account]))

        #expect(result.accounts.first?.color == .default)
    }
}
