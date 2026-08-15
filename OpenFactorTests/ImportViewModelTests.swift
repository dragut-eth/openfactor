import Foundation
import Testing

@testable import OpenFactor
@testable import OpenFactorCore

/// What the preview decides, which is every judgement the import makes.
///
/// The screen is thin on purpose: it draws what this produced. So these tests are the real
/// coverage for the behaviour that matters, which is that nothing reaches the Keychain
/// without the user seeing it first, and that the three dispositions are told apart
/// correctly.
@Suite("Import preview")
struct ImportViewModelTests {

    private func makeStore() -> KeychainSecretStore {
        KeychainSecretStore(service: "app.openfactor.tests.\(UUID().uuidString)")
    }

    private let secret = Data("12345678901234567890".utf8)

    private func account(
        _ issuer: String,
        secret: Data,
        period: Int = 30,
        digits: OTPDigits = .six
    ) throws -> OTPAccount {
        OTPAccount(
            issuer: issuer,
            name: "octocat",
            secret: secret,
            generator: .totp(
                try TOTPConfiguration(algorithm: .sha1, digits: digits, period: period)
            )
        )
    }

    /// Writes a file the way a user would hand one over, so `read` is exercised end to end
    /// rather than the classifier being called directly.
    private func write(_ contents: String, extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func aegisVault(secret: String, period: Int = 30, digits: Int = 6) -> String {
        """
        {"version":1,"header":{"slots":null,"params":null},"db":{"version":3,"entries":[
        {"type":"totp","name":"octocat","issuer":"GitHub",
         "info":{"secret":"\(secret)","algo":"SHA1","digits":\(digits),"period":\(period)}}]}}
        """
    }

    // MARK: - Nothing is written before the user agrees

    @Test("Reading a file writes nothing to the store")
    @MainActor
    func readingWritesNothing() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = ImportViewModel(store: store)
        model.read(try write(aegisVault(secret: "GEZDGNBVGY3TQOJQ"), extension: "json"))

        guard case let .reviewing(preview) = model.stage else {
            Issue.record("expected a preview, got \(model.stage)")
            return
        }

        #expect(preview.importable.count == 1)
        #expect(try store.records().readable.isEmpty, "the preview must not save anything")
    }

    @Test("Confirming writes exactly what the preview promised")
    @MainActor
    func confirmingWrites() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = ImportViewModel(store: store)
        model.read(try write(aegisVault(secret: "GEZDGNBVGY3TQOJQ"), extension: "json"))

        guard case let .reviewing(preview) = model.stage else {
            Issue.record("expected a preview")
            return
        }
        model.confirm(preview, includingConflicts: false)

        #expect(try store.records().readable.count == 1)
        if case let .finished(added, _) = model.stage {
            #expect(added == 1)
        } else {
            Issue.record("expected a finished stage")
        }
    }

    // MARK: - The three dispositions

    @Test("An account already stored, identically, is a duplicate rather than a new one")
    @MainActor
    func detectsDuplicates() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(account("GitHub", secret: Base32.decode("GEZDGNBVGY3TQOJQ")), color: .blue)

        let model = ImportViewModel(store: store)
        model.read(try write(aegisVault(secret: "GEZDGNBVGY3TQOJQ"), extension: "json"))

        guard case let .reviewing(preview) = model.stage else {
            Issue.record("expected a preview")
            return
        }

        #expect(preview.duplicates.count == 1)
        #expect(preview.importable.isEmpty)
        #expect(preview.conflicts.isEmpty)
    }

    /// The distinction gate A3's second review insisted on. The secret alone is not the
    /// account: the same secret with a different period generates different codes, so
    /// collapsing them silently would lose one of the two.
    @Test("The same secret with different settings is a conflict, not a duplicate")
    @MainActor
    func detectsConflicts() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(
            account("GitHub", secret: Base32.decode("GEZDGNBVGY3TQOJQ"), period: 30),
            color: .blue
        )

        let model = ImportViewModel(store: store)
        model.read(try write(aegisVault(secret: "GEZDGNBVGY3TQOJQ", period: 60), extension: "json"))

        guard case let .reviewing(preview) = model.stage else {
            Issue.record("expected a preview")
            return
        }

        #expect(preview.conflicts.count == 1)
        #expect(preview.duplicates.isEmpty)
        #expect(preview.importable.isEmpty)
    }

    @Test("A conflict is skipped unless the user asks for it")
    @MainActor
    func conflictsAreOptional() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(
            account("GitHub", secret: Base32.decode("GEZDGNBVGY3TQOJQ"), period: 30),
            color: .blue
        )

        let model = ImportViewModel(store: store)
        model.read(try write(aegisVault(secret: "GEZDGNBVGY3TQOJQ", period: 60), extension: "json"))

        guard case let .reviewing(preview) = model.stage else {
            Issue.record("expected a preview")
            return
        }

        model.confirm(preview, includingConflicts: false)
        #expect(try store.records().readable.count == 1, "the conflict must not be added")

        model.confirm(preview, includingConflicts: true)
        #expect(try store.records().readable.count == 2, "and must be added when asked for")
    }

    /// A renamed account keeps its secret, so it is the same authenticator and must not
    /// arrive as a second card generating identical codes.
    @Test("A renamed account is still recognised as the same one")
    @MainActor
    func recognisesRenamedAccounts() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(
            account("Old name", secret: Base32.decode("GEZDGNBVGY3TQOJQ")),
            color: .blue
        )

        let model = ImportViewModel(store: store)
        model.read(try write(aegisVault(secret: "GEZDGNBVGY3TQOJQ"), extension: "json"))

        guard case let .reviewing(preview) = model.stage else {
            Issue.record("expected a preview")
            return
        }
        #expect(preview.duplicates.count == 1)
    }

    // MARK: - Files

    /// The extension is a hint. A Step Two export saved as .txt is still one, and a .json
    /// that is not a vault must not be read as one.
    @Test("The format is decided by contents, not by the file extension")
    @MainActor
    func detectsFormatFromContents() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let stepTwo = """
            {\\rtf1\\ansi Account Name: GitHub\\uc0\\u8232 Secret Key: GEZDGNBVGY3TQOJQ\\u8232 }
            """

        let model = ImportViewModel(store: store)
        model.read(try write(stepTwo, extension: "txt"))

        guard case let .reviewing(preview) = model.stage else {
            Issue.record("expected a preview, got \(model.stage)")
            return
        }
        #expect(preview.source == "Step Two")
    }

    @Test("An encrypted Aegis vault fails with the message that names the fix")
    @MainActor
    func explainsEncryptedVaults() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let encrypted = """
            {"version":1,"header":{"slots":[{"type":1}],"params":{"nonce":"00","tag":"00"}},
             "db":"YmFzZTY0"}
            """

        let model = ImportViewModel(store: store)
        model.read(try write(encrypted, extension: "json"))

        guard case let .failed(message) = model.stage else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.contains("encryption turned off"))
    }

    @Test("A file that is neither format fails rather than importing nothing quietly")
    @MainActor
    func rejectsUnrelatedFiles() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = ImportViewModel(store: store)
        model.read(try write("just some notes", extension: "txt"))

        guard case .failed = model.stage else {
            Issue.record("expected a failure, got \(model.stage)")
            return
        }
    }

    /// A file the user picked is untrusted input, and the importer should not be the thing
    /// that decides how much memory to spend.
    @Test("An implausibly large file is refused before it is parsed")
    @MainActor
    func refusesHugeFiles() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let huge = String(repeating: "A", count: 9 * 1024 * 1024)
        let model = ImportViewModel(store: store)
        model.read(try write(huge, extension: "txt"))

        guard case let .failed(message) = model.stage else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.contains("too large"))
    }

    /// Refusals belong in the preview, not swallowed, so the user learns which account did
    /// not come across while it is still in the other app.
    @Test("Refused records reach the preview with a reason")
    @MainActor
    func surfacesRefusals() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = ImportViewModel(store: store)
        model.read(try write(aegisVault(secret: "111111"), extension: "json"))

        guard case let .reviewing(preview) = model.stage else {
            Issue.record("expected a preview")
            return
        }

        #expect(preview.refusals.count == 1)
        #expect(preview.refusals.first?.reason == .secretNotBase32)
        #expect(preview.importable.isEmpty)
    }
}
