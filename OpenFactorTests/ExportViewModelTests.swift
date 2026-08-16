import Foundation
import Testing

@testable import OpenFactor
@testable import OpenFactorCore

/// Producing an archive, and the promises the screen makes while doing it.
///
/// The core suites prove the format. These prove the things only the app can get wrong: the
/// gate on writing a file, the freshness of the values that must never repeat, and that the
/// file does not outlive the screen.
@Suite("Export")
struct ExportViewModelTests {

    private func makeStore() -> KeychainSecretStore {
        KeychainSecretStore(service: "app.openfactor.tests.\(UUID().uuidString)")
    }

    private func account(_ issuer: String, secret: String) throws -> OTPAccount {
        OTPAccount(
            issuer: issuer,
            name: "octocat",
            secret: try Base32.decode(secret),
            generator: .totp(try TOTPConfiguration(algorithm: .sha1, digits: .six, period: 30))
        )
    }

    private func container(_ url: URL) throws -> [String: Any] {
        try #require(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
    }

    /// Walks the model to the point where a file can be written, skipping the biometric
    /// gate, which cannot be driven from a test and is one call to a system API.
    @MainActor
    private func ready(_ store: any SecretStore) async -> ExportViewModel {
        let model = ExportViewModel(store: store)
        await model.authenticate(for: .archive)
        model.hasSavedPassphrase = true
        return model
    }

    // MARK: - The gate on writing a file

    @Test("No file is written until the passphrase has been acknowledged")
    @MainActor
    func acknowledgementIsRequired() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = ExportViewModel(store: store)
        await model.authenticate(for: .archive)

        #expect(!model.canExport, "the file must not be available before it is acknowledged")

        model.hasSavedPassphrase = true
        #expect(model.canExport)
    }

    /// The floor on the path away from the generator. A length is not a strength, so this is
    /// checked against the estimator rather than against a character count.
    @Test("A weak passphrase of your own cannot produce an archive")
    @MainActor
    func weakCustomPassphrasesAreRefused() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = await ready(store)
        model.choice = .own

        // Ticked after each one, because typing clears the acknowledgement. That is the
        // point of the other tests in this suite, and it means the only thing left refusing
        // these is the strength floor.
        for weak in ["short", "password1234", "aaaaaaaaaaaaaaaa", "1qaz2wsx3edc"] {
            model.ownPassphrase = weak
            model.hasSavedPassphrase = true
            #expect(!model.canExport, "\(weak) must not be accepted")
        }

        model.ownPassphrase = "voltage.ledger.mango.stairwell"
        model.hasSavedPassphrase = true
        #expect(model.canExport)
    }

    /// The screen's gate and the writer's gate are separate, and both must hold. The button
    /// being disabled is a courtesy; the writer refusing is the rule.
    @Test("Even if the screen let it through, the writer refuses")
    @MainActor
    func writerRefusesIndependentlyOfTheScreen() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(try account("GitHub", secret: "GEZDGNBVGY3TQOJQ"), color: .blue)

        let model = await ready(store)
        model.choice = .own
        model.ownPassphrase = "password1234"
        model.hasSavedPassphrase = true

        model.export()

        guard case let .failed(message) = model.stage else {
            Issue.record("expected a refusal, got \(model.stage)")
            return
        }
        #expect(message.contains("too easy to guess"))
    }

    // MARK: - The file

    @Test("The archive it writes is one it can read back")
    @MainActor
    func archiveRoundTrips() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(try account("GitHub", secret: "GEZDGNBVGY3TQOJQ"), color: .purple)
        try store.add(try account("Fastmail", secret: "JBSWY3DPEHPK3PXP"), color: .teal)

        let model = await ready(store)
        model.export()

        guard case let .ready(url) = model.stage else {
            Issue.record("expected a file, got \(model.stage)")
            return
        }
        defer { model.discardFile() }

        let result = try BackupArchive.read(
            try Data(contentsOf: url), passphrase: model.displayedPassphrase
        )

        #expect(result.accounts.count == 2)
        #expect(result.refusals.isEmpty)
        #expect(Set(result.accounts.map(\.account.issuer)) == ["GitHub", "Fastmail"])
    }

    /// The one writer mistake the format calls catastrophic rather than merely wrong.
    /// Re-exporting an unchanged list is a new archive and takes new values: a repeated
    /// nonce under the same key destroys the confidentiality of both files, and a person
    /// exporting twice in a minute is the normal case, not the unusual one.
    @Test("Two exports never share a salt or a nonce")
    @MainActor
    func everyExportIsFresh() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(try account("GitHub", secret: "GEZDGNBVGY3TQOJQ"), color: .blue)

        var salts: Set<String> = []
        var nonces: Set<String> = []

        let model = await ready(store)

        for _ in 0..<5 {
            model.export()
            guard case let .ready(url) = model.stage else {
                Issue.record("expected a file")
                return
            }

            let object = try container(url)
            let kdf = try #require(object["kdf"] as? [String: Any])
            let cipher = try #require(object["cipher"] as? [String: Any])

            salts.insert(try #require(kdf["salt"] as? String))
            nonces.insert(try #require(cipher["nonce"] as? String))

            model.discardFile()
        }

        #expect(salts.count == 5)
        #expect(nonces.count == 5)
    }

    @Test("The file does not outlive the screen that made it")
    @MainActor
    func fileIsDiscarded() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(try account("GitHub", secret: "GEZDGNBVGY3TQOJQ"), color: .blue)

        let model = await ready(store)
        model.export()

        guard case let .ready(url) = model.stage else {
            Issue.record("expected a file")
            return
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        model.discardFile()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// **This assertion is vacuous on the simulator, and saying so is the point.**
    ///
    /// The simulator does not implement data protection, so it reports no protection key at
    /// all and there is nothing here to compare. On a device it reports `.complete` and the
    /// check is real. A test that quietly passed either way would be the same mistake gate
    /// A2 found three times over: a check whose name promises more than it delivers. So the
    /// absent case is named rather than folded into the expectation, and anyone reading a
    /// green simulator run knows exactly what it did not prove.
    @Test("The file is written with the strongest protection iOS offers")
    @MainActor
    func fileIsProtected() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(try account("GitHub", secret: "GEZDGNBVGY3TQOJQ"), color: .blue)

        let model = await ready(store)
        model.export()

        guard case let .ready(url) = model.stage else {
            Issue.record("expected a file")
            return
        }
        defer { model.discardFile() }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

        guard let protection = attributes[.protectionKey] as? FileProtectionType else {
            #expect(
                ProcessInfo.processInfo.environment["SIMULATOR_UDID"] != nil,
                "a device must report a protection class for this file"
            )
            return
        }

        #expect(protection == .complete)
    }

    // MARK: - What the acknowledgement refers to

    /// The blocking finding of the security review, and the failure it describes is silent:
    /// the archive is written, the share sheet appears, everything looks right, and the
    /// passphrase on the piece of paper opens nothing. Nobody learns that until a restore.
    @Test("Generating a different passphrase clears the acknowledgement")
    @MainActor
    func regenerationClearsTheAcknowledgement() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = await ready(store)
        #expect(model.canExport)

        model.regenerate()

        #expect(!model.hasSavedPassphrase)
        #expect(!model.canExport, "the box referred to a passphrase that is gone")
    }

    @Test("Editing a custom passphrase clears the acknowledgement")
    @MainActor
    func editingCustomPassphraseClearsTheAcknowledgement() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = await ready(store)
        model.choice = .own
        model.ownPassphrase = "voltage.ledger.mango.stairwell"
        model.hasSavedPassphrase = true
        #expect(model.canExport)

        model.ownPassphrase = "voltage.ledger.mango.stairwells"
        #expect(!model.canExport)
    }

    @Test("Switching between a generated and a custom passphrase clears it too")
    @MainActor
    func switchingClearsTheAcknowledgement() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = await ready(store)
        #expect(model.canExport)

        model.choice = .own
        #expect(!model.hasSavedPassphrase)
    }

    /// The other half of "the file does not outlive the screen". `onDisappear` cannot run in
    /// a process that is no longer there, so a force quit or an out of memory kill on the
    /// Ready screen used to leave the file behind for good.
    @Test("A file left behind by a previous run is removed at launch")
    @MainActor
    func orphanedFilesAreSwept() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(try account("GitHub", secret: "GEZDGNBVGY3TQOJQ"), color: .blue)

        let model = await ready(store)
        model.export()

        guard case let .ready(url) = model.stage else {
            Issue.record("expected a file")
            return
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        // The process died here, so nothing called discardFile.
        ExportViewModel.discardOrphanedFiles()

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A generated passphrase is what the archive was actually sealed with")
    @MainActor
    func generatedPassphraseIsTheRealOne() async throws {
        let store = makeStore()
        defer { store.cleanUp() }
        try store.add(try account("GitHub", secret: "GEZDGNBVGY3TQOJQ"), color: .blue)

        let model = await ready(store)
        model.export()

        guard case let .ready(url) = model.stage else {
            Issue.record("expected a file")
            return
        }
        defer { model.discardFile() }

        let data = try Data(contentsOf: url)

        // Hyphens in, hyphens out, and the bare form: all of them open it, which is the
        // property that makes a transcribed passphrase safe to rely on.
        #expect(throws: Never.self) {
            try BackupArchive.read(data, passphrase: model.displayedPassphrase)
        }
        #expect(throws: Never.self) {
            try BackupArchive.read(data, passphrase: model.generated)
        }
        #expect(throws: Never.self) {
            try BackupArchive.read(data, passphrase: model.displayedPassphrase.lowercased())
        }
        #expect(throws: BackupError.couldNotOpen) {
            try BackupArchive.read(data, passphrase: "AAAA-BBBB-CCCC-DDDD-EEEE-FFFF")
        }
    }

    @Test("Asking for a different passphrase actually changes it")
    @MainActor
    func regenerationChangesThePassphrase() async throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let model = await ready(store)
        let first = model.generated
        model.regenerate()

        #expect(model.generated != first)
        #expect(model.generated.count == BackupPassphrase.generatedLength)
    }
}
