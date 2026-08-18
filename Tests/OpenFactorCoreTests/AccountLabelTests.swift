import Foundation
import Testing

@testable import OpenFactorCore

/// The bound on issuer and name.
///
/// **The tests that matter are the routes, not the arithmetic.** Cutting a string at sixty-four
/// characters is not where this goes wrong; being enforced on one path and not another is. The
/// bound was added because an imported payload can carry labels of any length, so the import
/// route is asserted alongside the typed one, and so is assignment after the fact, which is how
/// a rename arrives and which an initializer alone would miss.
@Suite("Account label bound")
struct AccountLabelTests {

    private let long = String(repeating: "A", count: 500)

    @Test("A label within the bound is untouched")
    func shortLabelsSurvive() {
        #expect(AccountLabel.clamped("GitHub") == "GitHub")
        #expect(AccountLabel.clamped("") == "")
        #expect(AccountLabel.clamped(nil) == nil)

        let exact = String(repeating: "A", count: AccountLabel.maximumCharacters)
        #expect(AccountLabel.clamped(exact) == exact)
    }

    @Test("One character past the bound is cut, and only by one")
    func boundaryIsExact() {
        let over = String(repeating: "A", count: AccountLabel.maximumCharacters + 1)
        #expect(AccountLabel.clamped(over).count == AccountLabel.maximumCharacters)
    }

    /// The bound counts what a person would call a character, so a label is never cut through
    /// the middle of an emoji or a combining mark and left as broken text.
    @Test("Counting is by grapheme, so nothing is cut in half")
    func countsGraphemes() {
        let family = "👨‍👩‍👧‍👦"
        #expect(family.count == 1)

        let many = String(repeating: family, count: AccountLabel.maximumCharacters + 10)
        let clamped = AccountLabel.clamped(many)
        #expect(clamped.count == AccountLabel.maximumCharacters)
        // Every cluster is intact: re-splitting gives back whole families, not fragments.
        #expect(clamped.allSatisfy { String($0) == family })

        let combining = String(repeating: "e\u{0301}", count: AccountLabel.maximumCharacters + 5)
        #expect(AccountLabel.clamped(combining).unicodeScalars.count == AccountLabel.maximumCharacters * 2)
    }

    // MARK: - The routes

    @Test("An account parsed from outside is bounded before it is ever shown")
    func parsedAccountsAreBounded() {
        let account = OTPAccount(
            issuer: long, name: long,
            secret: Data("12345678901234567890".utf8), generator: .totp(.standard))

        #expect(account.issuer?.count == AccountLabel.maximumCharacters)
        #expect(account.name.count == AccountLabel.maximumCharacters)
    }

    @Test("Metadata is bounded at construction")
    func metadataIsBoundedAtInit() {
        let metadata = AccountMetadata(
            issuer: long, name: long, generator: .totp(.standard), color: .red, sortIndex: 0)

        #expect(metadata.issuer?.count == AccountLabel.maximumCharacters)
        #expect(metadata.name.count == AccountLabel.maximumCharacters)
    }

    /// The route an initializer alone would miss. A rename assigns to the property of an
    /// existing value rather than building a new one.
    @Test("Assignment after the fact is bounded too")
    func assignmentIsBounded() {
        var metadata = AccountMetadata(
            issuer: "GitHub", name: "octocat", generator: .totp(.standard), color: .red,
            sortIndex: 0)

        metadata.issuer = long
        metadata.name = long

        #expect(metadata.issuer?.count == AccountLabel.maximumCharacters)
        #expect(metadata.name.count == AccountLabel.maximumCharacters)
    }

    @Test("Clearing an issuer still works")
    func issuerCanStillBeCleared() {
        var metadata = AccountMetadata(
            issuer: "GitHub", name: "octocat", generator: .totp(.standard), color: .red,
            sortIndex: 0)

        metadata.issuer = nil
        #expect(metadata.issuer == nil)
    }

    /// What the bound is actually for: a record written to storage stays small, whatever the
    /// label arrived as. The number below is the measurement that motivated the bound, where an
    /// unbounded label grew the stored record byte for byte.
    @Test("A stored record stays small however long the label arrived")
    func storedRecordsStaySmall() throws {
        let store = InMemorySecretStore()
        let record = try store.add(
            OTPAccount(
                issuer: String(repeating: "A", count: 100_000),
                name: String(repeating: "B", count: 100_000),
                secret: Data("12345678901234567890".utf8), generator: .totp(.standard)),
            color: .red)

        let encoded = try JSONEncoder().encode(record.metadata)
        #expect(encoded.count < 1_024)
    }

    /// Records already in storage are left exactly as they are. Decoding deliberately does not
    /// clamp: an account saved before this bound existed belongs to its owner, and silently
    /// rewriting somebody's data on read is a worse behavior than an untidy label.
    @Test("An already stored label is not rewritten on read")
    func decodingDoesNotRewriteHistory() throws {
        // The shape comes from the encoder rather than a literal, so this cannot quietly stop
        // decoding and pass on the strength of having asserted nothing. A hand written JSON
        // literal here would rot the moment the record format changed.
        let placeholder = "ISSUER_PLACEHOLDER"
        let metadata = AccountMetadata(
            issuer: placeholder, name: "octocat", generator: .totp(.standard), color: .red,
            sortIndex: 0)

        let encoded = try JSONEncoder().encode(metadata)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(text.contains(placeholder), "the placeholder must survive to be swapped")

        let widened = text.replacingOccurrences(of: placeholder, with: long)
        let decoded = try JSONDecoder().decode(
            AccountMetadata.self, from: Data(widened.utf8))

        #expect(decoded.issuer?.count == 500)
    }
}
