import Foundation
import OpenFactorCore
import Testing

@testable import OpenFactor

/// A mistyped secret is the failure this screen exists to catch. It decodes to different
/// bytes, generates plausible codes, and every one is refused by the service, with nobody
/// finding out until a login fails and the enrollment page is long closed.
@MainActor
@Suite("Manual setup")
struct ManualSetupViewModelTests {

    /// The RFC 6238 seed in Base32, so a valid form can be checked against a published
    /// code rather than against whatever it happens to produce.
    private static let validSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    private func filledModel(store: any SecretStore = InMemorySecretStore()) -> ManualSetupViewModel {
        let model = ManualSetupViewModel(store: store)
        model.secretText = Self.validSecret
        model.issuer = "GitHub"
        model.name = "octocat"
        return model
    }

    // MARK: - Validation

    /// An untouched field should not be shouting at anyone.
    @Test("An empty form is quiet and cannot be saved")
    func emptyFormIsQuiet() {
        let model = ManualSetupViewModel(store: InMemorySecretStore())

        #expect(model.secretProblem == nil)
        #expect(model.canSave == false)
        #expect(model.previewCode(at: Date()) == nil)
    }

    @Test("A valid secret can be saved")
    func validSecretCanBeSaved() {
        #expect(filledModel().canSave)
        #expect(filledModel().secretProblem == nil)
    }

    /// The parser's errors already say precisely what is wrong, so they are surfaced
    /// rather than replaced with something vaguer.
    @Test(
        "A malformed secret says what is wrong",
        arguments: ["1111", "ABC!", "A", "========"]
    )
    func malformedSecretIsExplained(secret: String) {
        let model = ManualSetupViewModel(store: InMemorySecretStore())
        model.secretText = secret

        #expect(model.secretProblem != nil)
        #expect(model.canSave == false)
    }

    /// The same leniency the rest of the app has: services print secrets in groups, and
    /// that is what lands on the clipboard.
    @Test(
        "Secrets are accepted however they are printed",
        arguments: [
            "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            "gezdgnbvgy3tqojqgezdgnbvgy3tqojq",
            "GEZD GNBV GY3T QOJQ GEZD GNBV GY3T QOJQ",
            "GEZD-GNBV-GY3T-QOJQ-GEZD-GNBV-GY3T-QOJQ",
        ]
    )
    func acceptsRealWorldSecretFormatting(secret: String) {
        let model = ManualSetupViewModel(store: InMemorySecretStore())
        model.secretText = secret
        model.name = "someone"

        #expect(model.secretProblem == nil)
        #expect(model.canSave)
    }

    @Test("A counter that is not a number is refused")
    func refusesNonNumericCounter() {
        let model = filledModel()
        model.isCounterBased = true
        model.counterText = "seven"

        #expect(model.counterProblem != nil)
        #expect(model.canSave == false)
    }

    // MARK: - Preview

    /// The preview is what the user checks against the service, so it has to be the code
    /// the account will actually produce, not an approximation of one.
    @Test("The preview shows the published code for the published secret")
    func previewMatchesTheRFCVector() {
        let model = filledModel()
        model.digits = .eight

        #expect(model.previewCode(at: Date(timeIntervalSince1970: 59)) == "94287082")
    }

    @Test("Changing the period changes the countdown")
    func periodAffectsTheCountdown() {
        let model = filledModel()
        model.period = 60

        #expect(model.previewSecondsRemaining(at: Date(timeIntervalSince1970: 0)) == 60)
    }

    /// A counter based account has nothing to count down, so the preview offers no
    /// countdown for the card to draw.
    @Test("A counter based account previews without a countdown")
    func counterBasedPreviewHasNoCountdown() {
        let model = filledModel()
        model.isCounterBased = true
        model.counterText = "0"

        #expect(model.previewCode(at: Date()) == "755224", "RFC 4226 Appendix D, counter 0")
        #expect(model.previewSecondsRemaining(at: Date()) == nil)
    }

    // MARK: - Saving

    @Test("Saving stores exactly what the form described")
    func savesTheDescribedAccount() throws {
        let store = InMemorySecretStore()
        let model = filledModel(store: store)
        model.algorithm = .sha256
        model.digits = .eight
        model.period = 60

        #expect(model.save())

        let saved = try #require(try store.records().readable.first)
        #expect(saved.metadata.issuer == "GitHub")
        #expect(saved.metadata.name == "octocat")
        #expect(
            saved.metadata.generator
                == .totp(try TOTPConfiguration(algorithm: .sha256, digits: .eight, period: 60))
        )
        #expect(try store.secret(for: saved.id) == (try Base32.decode(Self.validSecret)))
    }

    @Test("Saving a counter based account keeps its starting counter")
    func savesTheStartingCounter() throws {
        let store = InMemorySecretStore()
        let model = filledModel(store: store)
        model.isCounterBased = true
        model.counterText = "42"

        #expect(model.save())

        let saved = try #require(try store.records().readable.first)
        #expect(saved.metadata.generator == .hotp(counter: 42, digits: .six, algorithm: .sha1))
    }

    @Test("Saving an incomplete form does nothing")
    func doesNotSaveAnIncompleteForm() throws {
        let store = InMemorySecretStore()
        let model = ManualSetupViewModel(store: store)
        model.issuer = "GitHub"

        #expect(model.save() == false)
        #expect(try store.records().readable.isEmpty)
    }

    /// Whitespace around a pasted name is invisible and would otherwise be stored, sorted
    /// on, and searched against.
    @Test("Names and issuers are trimmed")
    func trimsNamesAndIssuers() throws {
        let store = InMemorySecretStore()
        let model = filledModel(store: store)
        model.issuer = "  GitHub  "
        model.name = "  octocat  "

        #expect(model.save())

        let saved = try #require(try store.records().readable.first)
        #expect(saved.metadata.issuer == "GitHub")
        #expect(saved.metadata.name == "octocat")
    }

    @Test("An account with no issuer is allowed")
    func allowsNoIssuer() throws {
        let store = InMemorySecretStore()
        let model = filledModel(store: store)
        model.issuer = ""

        #expect(model.save())
        #expect(try store.records().readable.first?.metadata.issuer == nil)
    }
}

@MainActor
@Suite("Advancing from the list")
struct AccountListCounterTests {

    private func store() throws -> (InMemorySecretStore, AccountRecord) {
        let store = InMemorySecretStore()
        let record = try store.add(
            OTPAccount(
                issuer: "Example",
                name: "counter",
                secret: Data("12345678901234567890".utf8),
                generator: .hotp(counter: 0, digits: .six, algorithm: .sha1)
            ),
            color: .blue
        )
        return (store, record)
    }

    @Test("Asking for the next code advances the row and the store")
    func advancesRowAndStore() throws {
        let (store, _) = try store()
        let model = AccountListViewModel(store: store)
        model.load(at: Date(timeIntervalSince1970: 0))

        #expect(model.rows.first?.code == "755224")

        model.advanceCounter(for: try #require(model.rows.first))

        #expect(model.rows.first?.code == "287082")
        #expect(
            try store.records().readable.first?.metadata.generator
                == .hotp(counter: 1, digits: .six, algorithm: .sha1)
        )
    }

    @Test("A counter based row still has no countdown after advancing")
    func advancingLeavesNoCountdown() throws {
        let (store, _) = try store()
        let model = AccountListViewModel(store: store)
        model.load(at: Date(timeIntervalSince1970: 0))

        model.advanceCounter(for: try #require(model.rows.first))

        #expect(model.rows.first?.secondsRemaining == nil)
        #expect(model.rows.first?.card.fractionRemaining == nil)
    }

    /// Ticking must not disturb a counter based row. Its code changes only when asked for.
    @Test("Time passing does not change a counter based code")
    func tickingDoesNotAdvance() throws {
        let (store, _) = try store()
        let model = AccountListViewModel(store: store)
        model.load(at: Date(timeIntervalSince1970: 0))

        for second in 1...120 {
            model.tick(at: Date(timeIntervalSince1970: TimeInterval(second)))
        }

        #expect(model.rows.first?.code == "755224")
    }
}
