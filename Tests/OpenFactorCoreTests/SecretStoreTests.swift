import Foundation
import Testing

@testable import OpenFactorCore

/// Behaviour every store must have, run against each one that can run here.
///
/// Written against the protocol rather than against an implementation, so the Keychain
/// backed store is held to exactly the same contract as the in memory one the moment it
/// can be reached. See ``KeychainAvailability`` for when that is.
@Suite("SecretStore behaviour")
struct SecretStoreTests {

    private static func account(
        issuer: String? = "GitHub",
        name: String = "octocat",
        secret: Data = Data("12345678901234567890".utf8),
        generator: OTPGenerator = .totp(.standard)
    ) -> OTPAccount {
        OTPAccount(issuer: issuer, name: name, secret: secret, generator: generator)
    }

    // MARK: - Adding and listing

    @Test("A new store is empty", arguments: StoreUnderTest.testable)
    func startsEmpty(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        #expect(try store.records().readable.isEmpty)
    }

    @Test("An added account comes back in the list", arguments: StoreUnderTest.testable)
    func addsAndLists(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        let record = try store.add(Self.account(), color: .purple)
        let records = try store.records().readable

        #expect(records.count == 1)
        #expect(records.first == record)
        #expect(record.metadata.issuer == "GitHub")
        #expect(record.metadata.name == "octocat")
        #expect(record.metadata.color == .purple)
        #expect(record.metadata.generator == .totp(.standard))
    }

    /// The same service can legitimately be added twice, for two accounts at it, so
    /// nothing here may treat a repeat as a mistake.
    @Test("The same account can be added twice", arguments: StoreUnderTest.testable)
    func allowsDuplicates(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        let first = try store.add(Self.account(), color: .red)
        let second = try store.add(Self.account(), color: .red)

        #expect(first.id != second.id)
        #expect(try store.records().readable.count == 2)
    }

    @Test("New accounts go to the end of the list", arguments: StoreUnderTest.testable)
    func appendsInOrder(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        for index in 0..<5 {
            let record = try store.add(Self.account(name: "user\(index)"), color: .blue)
            #expect(record.metadata.sortIndex == index)
        }

        #expect(try store.records().readable.map(\.metadata.name) == ["user0", "user1", "user2", "user3", "user4"])
    }

    @Test("The list comes back in sort order", arguments: StoreUnderTest.testable)
    func sortsByIndex(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        var first = try store.add(Self.account(name: "first"), color: .blue)
        let second = try store.add(Self.account(name: "second"), color: .blue)

        first.metadata.sortIndex = second.metadata.sortIndex + 1
        try store.update(first)

        #expect(try store.records().readable.map(\.metadata.name) == ["second", "first"])
    }

    // MARK: - Secrets

    @Test("A secret comes back exactly as it went in", arguments: StoreUnderTest.testable)
    func storesSecretsExactly(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        let secret = Data((0..<64).map { UInt8(truncatingIfNeeded: $0 &* 41 &+ 3) })
        let record = try store.add(Self.account(secret: secret), color: .blue)

        #expect(try store.secret(for: record.id) == secret)
    }

    @Test("Asking for an unknown secret fails", arguments: StoreUnderTest.testable)
    func unknownSecretFails(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        #expect(throws: SecretStoreError.notFound) {
            try store.secret(for: UUID())
        }
    }

    /// The codes a store produces have to match the ones the generators produce directly,
    /// or something in storage is mangling the secret or the configuration.
    @Test("Stored accounts generate the RFC 6238 codes", arguments: StoreUnderTest.testable)
    func generatesKnownCodes(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        let configuration = try TOTPConfiguration(algorithm: .sha1, digits: .eight, period: 30)
        let record = try store.add(
            Self.account(secret: rfcSecret, generator: .totp(configuration)),
            color: .blue
        )

        let date = Date(timeIntervalSince1970: 59)
        #expect(try store.code(for: record.id, at: date) == "94287082")
    }

    @Test("A stored account can be rebuilt whole", arguments: StoreUnderTest.testable)
    func rebuildsAccounts(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        let original = Self.account()
        let record = try store.add(original, color: .blue)
        let rebuilt = try store.account(for: record.id)

        #expect(rebuilt == original)
    }

    // MARK: - Every generator survives storage

    /// Metadata goes through JSON on its way into the Keychain, so every shape of
    /// generator has to survive the trip. A mangled algorithm or period produces codes
    /// that look right and are rejected.
    @Test("Every generator configuration survives storage", arguments: StoreUnderTest.testable)
    func storesEveryGenerator(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        var generators: [OTPGenerator] = [
            .hotp(counter: 0, digits: .six, algorithm: .sha1),
            .hotp(counter: .max, digits: .eight, algorithm: .sha512),
        ]

        for algorithm in OTPAlgorithm.allCases {
            for digits in OTPDigits.allCases {
                generators.append(.totp(try TOTPConfiguration(algorithm: algorithm, digits: digits, period: 60)))
            }
        }

        for generator in generators {
            let record = try store.add(Self.account(generator: generator), color: .blue)
            let stored = try store.records().readable.first { $0.id == record.id }

            #expect(stored?.metadata.generator == generator)
        }
    }

    // MARK: - Updating

    @Test("Updating changes the metadata and leaves the secret alone", arguments: StoreUnderTest.testable)
    func updatesMetadataOnly(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        let secret = Data("12345678901234567890".utf8)
        var record = try store.add(Self.account(secret: secret), color: .blue)

        record.metadata.name = "renamed"
        record.metadata.issuer = "Elsewhere"
        record.metadata.color = .teal
        try store.update(record)

        let stored = try #require(try store.records().readable.first)
        #expect(stored.metadata.name == "renamed")
        #expect(stored.metadata.issuer == "Elsewhere")
        #expect(stored.metadata.color == .teal)
        #expect(try store.secret(for: record.id) == secret)
    }

    @Test("Updating an account that is gone fails", arguments: StoreUnderTest.testable)
    func updateUnknownFails(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        let record = AccountRecord(
            id: UUID(),
            metadata: AccountMetadata(
                issuer: nil,
                name: "ghost",
                generator: .totp(.standard),
                color: .blue,
                sortIndex: 0
            )
        )

        #expect(throws: SecretStoreError.notFound) {
            try store.update(record)
        }
    }

    // MARK: - Deleting

    @Test("Deleting removes the account and its secret", arguments: StoreUnderTest.testable)
    func deletesAccountAndSecret(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        let record = try store.add(Self.account(), color: .blue)
        try store.delete(id: record.id)

        #expect(try store.records().readable.isEmpty)
        #expect(throws: SecretStoreError.notFound) {
            try store.secret(for: record.id)
        }
    }

    @Test("Deleting one account leaves the others", arguments: StoreUnderTest.testable)
    func deleteIsPrecise(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        let kept = try store.add(Self.account(name: "kept"), color: .blue)
        let removed = try store.add(Self.account(name: "removed"), color: .blue)

        try store.delete(id: removed.id)

        #expect(try store.records().readable.map(\.id) == [kept.id])
    }

    @Test("Deleting an account that is gone fails", arguments: StoreUnderTest.testable)
    func deleteUnknownFails(kind: StoreUnderTest) throws {
        let store = kind.make()
        defer { store.cleanUp() }

        #expect(throws: SecretStoreError.notFound) {
            try store.delete(id: UUID())
        }
    }
}
