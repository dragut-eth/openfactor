import Foundation
import Testing

@testable import OpenFactorCore

/// Generating a passphrase, showing it, and deciding whether one somebody typed is enough.
@Suite("Backup passphrase")
struct BackupPassphraseTests {

    // MARK: - Generation

    @Test("A generated passphrase is 120 bits in the Base32 alphabet")
    func generatesTwentyFourCharacters() throws {
        let passphrase = try #require(BackupPassphrase.generate())

        #expect(passphrase.count == BackupPassphrase.generatedLength)
        #expect(passphrase.allSatisfy { "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".contains($0) })
    }

    /// Not a test of the CSPRNG, which cannot be tested from here. It catches the failure
    /// that actually happens, which is a generator seeded once or accidentally constant.
    @Test("Two generated passphrases are not the same passphrase")
    func generatesFreshValues() throws {
        let first = try #require(BackupPassphrase.generate())
        let rest = (0..<32).compactMap { _ in BackupPassphrase.generate() }

        #expect(rest.count == 32)
        #expect(!rest.contains(first))
        #expect(Set(rest).count == 32)
    }

    @Test("A generated passphrase is displayed in groups of four")
    func groupsForTranscription() {
        #expect(
            BackupPassphrase.grouped("YZTRTHFWWT6EOXIV73XDQCDM")
                == "YZTR-THFW-WT6E-OXIV-73XD-QCDM"
        )
    }

    /// The screen lays the groups out and the clipboard punctuates them, so both come from
    /// one splitter. Two implementations of "every four characters" that disagreed would be
    /// discovered by somebody typing a passphrase into an archive that then would not open.
    @Test("The laid out groups and the punctuated string are the same groups")
    func groupsAndStringAgree() {
        let passphrase = "YZTRTHFWWT6EOXIV73XDQCDM"
        let groups = BackupPassphrase.groups(passphrase)

        #expect(groups == ["YZTR", "THFW", "WT6E", "OXIV", "73XD", "QCDM"])
        #expect(groups.joined(separator: "-") == BackupPassphrase.grouped(passphrase))
        #expect(groups.joined() == passphrase)
    }

    /// The whole point of generating it this way. If a generated passphrase did not survive
    /// the round trip through the display form, every archive would be one transcription
    /// away from unrecoverable.
    @Test("A generated passphrase survives being displayed and typed back")
    func displayedFormCanonicalisesBack() throws {
        let passphrase = try #require(BackupPassphrase.generate())
        let displayed = BackupPassphrase.grouped(passphrase)

        #expect(
            String(decoding: BackupPassphrase.canonical(displayed), as: UTF8.self) == passphrase
        )
    }

    // MARK: - The two forms

    @Test("The canonical form keeps only the alphabet, whatever it arrives wrapped in")
    func canonicalStripsEverythingElse() {
        let expected = "YZTRTHFWWT6EOXIV73XDQCDM"

        for input in [
            "YZTR-THFW-WT6E-OXIV-73XD-QCDM",
            "yztr thfw wt6e oxiv 73xd qcdm",
            "\u{FEFF}YZTR\u{2013}THFW\u{2014}WT6E\u{00A0}OXIV\t73XD\nQCDM\r\n",
            "YZTR‑THFW‑WT6E‑OXIV‑73XD‑QCD\u{200B}M",
        ] {
            #expect(
                String(decoding: BackupPassphrase.canonical(input), as: UTF8.self) == expected
            )
        }
    }

    /// The `ß` case is the reason the mapping is written out rather than delegated. Swift's
    /// `uppercased()` turns it into `SS`, two characters that *are* in the Base32 alphabet,
    /// so an implementation using it would derive a different key from the same passphrase.
    @Test("Case mapping is ASCII, so a sharp s is dropped rather than becoming SS")
    func canonicalUsesASCIIMapping() {
        #expect(
            String(decoding: BackupPassphrase.canonical("AAAAßAAAA"), as: UTF8.self) == "AAAAAAAA"
        )
        #expect("AAAAßAAAA".uppercased() == "AAAASSAAAA", "the trap this avoids")
    }

    @Test("The verbatim form removes one byte order mark and trailing newlines, nothing else")
    func verbatimRemovesOnlyWhatItMust() {
        let text = { (data: Data) in String(decoding: data, as: UTF8.self) }

        #expect(text(BackupPassphrase.verbatim("  hello world  ")) == "  hello world  ")
        #expect(text(BackupPassphrase.verbatim("\u{FEFF}hello\r\n")) == "hello")
        #expect(text(BackupPassphrase.verbatim("\u{FEFF}\u{FEFF}hello")) == "\u{FEFF}hello")
        #expect(text(BackupPassphrase.verbatim("hello\n\n")) == "hello")
    }

    // MARK: - What a reader tries

    @Test("A clean passphrase costs one derivation, not four")
    func collapsesIdenticalForms() {
        #expect(BackupPassphrase.attempts(for: "YZTRTHFWWT6EOXIV73XDQCDM", hint: .generated).count == 1)
    }

    @Test("The hint puts its own form first and never removes the other")
    func hintOrdersWithoutExcluding() {
        let input = "correct horse battery staple"

        let generatedFirst = BackupPassphrase.attempts(for: input, hint: .generated)
        let customFirst = BackupPassphrase.attempts(for: input, hint: .custom)

        #expect(generatedFirst.first == BackupPassphrase.canonical(input))
        #expect(customFirst.first == BackupPassphrase.verbatim(input))
        #expect(Set(generatedFirst) == Set(customFirst))
    }

    /// Two keyboards encode the same passphrase differently, composed on one platform and
    /// decomposed on another: same glyphs, different bytes, different key. The format does
    /// not normalise the stored form, because that would silently change what somebody
    /// typed, so both are attempted instead.
    @Test("Both Unicode normalisations of a non-ASCII passphrase are attempted")
    func triesBothNormalisations() {
        let composed = "café passphrase"
        let attempts = BackupPassphrase.attempts(for: composed, hint: .custom)

        #expect(attempts.contains(Data(composed.precomposedStringWithCanonicalMapping.utf8)))
        #expect(attempts.contains(Data(composed.decomposedStringWithCanonicalMapping.utf8)))
    }

    @Test("Nothing is derived from an empty form")
    func skipsEmptyForms() {
        #expect(BackupPassphrase.attempts(for: "", hint: nil).isEmpty)
        // Nothing in the alphabet survives canonicalisation, so only the verbatim form runs.
        #expect(BackupPassphrase.attempts(for: "!!!!", hint: nil).count == 1)
    }

    // MARK: - Strength, on the custom path

    @Test("Something short is refused however clever it looks")
    func refusesShortPassphrases() {
        let assessment = PassphraseStrength.assess("Tr0ub4dor&3")

        #expect(!assessment.isAcceptable)
        #expect(assessment.advice != nil)
    }

    @Test("The passwords every guessing program tries first are refused by name", arguments: [
        "password1234", "Passw0rd!2024", "letmein12345", "qwertyuiop123",
        "correct horse battery staple",
    ])
    func refusesCommonPasswords(input: String) {
        #expect(!PassphraseStrength.assess(input).isAcceptable)
    }

    @Test("Cheap structure does not count as length", arguments: [
        "aaaaaaaaaaaaaaaa", "abcdefghijklmnop", "1234567890123456",
    ])
    func refusesCheapStructure(input: String) {
        let assessment = PassphraseStrength.assess(input)

        #expect(!assessment.isAcceptable)
        #expect(assessment.bits < PassphraseStrength.minimumBits)
    }

    @Test("A genuinely long, unrelated passphrase is accepted", arguments: [
        "voltage.ledger.mango.stairwell",
        "Ky7#mQp2LrVx9Tz",
        "the quick brown fox jumps",
    ])
    func acceptsRealPassphrases(input: String) {
        #expect(PassphraseStrength.assess(input).isAcceptable, "\(input)")
    }

    /// The bar is stated in bits rather than in characters because a length is not a
    /// strength, which is the sentence the format document uses and the reason this type
    /// exists at all.
    @Test("A generated passphrase clears the bar by a wide margin")
    func generatedPassphrasesAreStrong() throws {
        let passphrase = try #require(BackupPassphrase.generate())
        let assessment = PassphraseStrength.assess(BackupPassphrase.grouped(passphrase))

        #expect(assessment.isAcceptable)
        #expect(assessment.bits > 100)
    }
}
