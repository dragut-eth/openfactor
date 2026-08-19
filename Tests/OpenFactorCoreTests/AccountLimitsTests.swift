import Foundation
import Testing

@testable import OpenFactorCore

/// The rules an account must satisfy to be stored, and the defect that came from four places
/// disagreeing about them.
///
/// **The failure this prevents was reproduced before it was fixed.** Enrol
/// `otpauth://totp/x?secret=GEZDGNBV`, valid Base32 decoding to five bytes: the account enrolled,
/// generated codes, was written into a backup, and was refused when that backup was restored.
/// Zero accounts came back. Discovered on a device that no longer had the originals, which is the
/// worst moment available.
@Suite("Account limits")
struct AccountLimitsTests {

    private func secret(_ count: Int) -> Data {
        Data(repeating: 0xA5, count: count)
    }

    // MARK: - The rules themselves

    @Test("The floor is RFC 4226's ten bytes")
    func theFloor() {
        #expect(!AccountLimits.isSecretLongEnough(secret(0)))
        #expect(!AccountLimits.isSecretLongEnough(secret(9)))
        #expect(AccountLimits.isSecretLongEnough(secret(10)))
        #expect(AccountLimits.isSecretLongEnough(secret(64)))
    }

    @Test("The ceiling is the largest integer JSON must represent exactly")
    func theCeiling() {
        #expect(AccountLimits.isCounterStorable(0))
        #expect(AccountLimits.isCounterStorable(AccountLimits.maximumCounter))
        #expect(!AccountLimits.isCounterStorable(AccountLimits.maximumCounter + 1))
        #expect(!AccountLimits.isCounterStorable(UInt64.max))
    }

    // MARK: - Every path that creates an account

    /// The point of the type. Four paths enforced four different things, and three of them
    /// enforced nothing, so this asserts the agreement rather than trusting it.
    @Test("Every enrollment path refuses a short secret")
    func everyPathRefusesAShortSecret() throws {
        // The URI parser, which is the scan and the URL scheme.
        #expect(throws: OTPAuthURIError.secretTooShort) {
            _ = try OTPAuthURI.account(from: "otpauth://totp/x?secret=GEZDGNBV")
        }

        // The Aegis reader, using the same vault shape its own suite uses.
        let entry = """
            {"type":"totp","uuid":"a","name":"octocat","issuer":"GitHub","note":"","icon":null,
             "info":{"secret":"GEZDGNBV","algo":"SHA1","digits":6,"period":30}}
            """
        let aegis = """
            {"version": 1, "header": {"slots": null, "params": null}, \
            "db": {"version": 3, "entries": [\(entry)]}}
            """
        let fromAegis = try AegisImport.read(Data(aegis.utf8))
        #expect(fromAegis.accounts.isEmpty)
        #expect(fromAegis.refusals.first?.reason == .secretTooShort)

        // The labelled text reader, using the labels it actually looks for.
        let labelled = """
            Account Name: GitHub
            Email Address or Username: octocat
            Secret Key: GEZDGNBV
            Hash Algorithm: SHA1
            Period: 30
            Digits: 6
            """
        let fromText = LabelledTextImport.read(labelled)
        #expect(fromText.accounts.isEmpty)
        #expect(fromText.refusals.first?.reason == .secretTooShort)
    }

    /// The reproduction, inverted. What used to enrol and vanish is now refused at the door, so
    /// the archive can no longer contain something the reader will turn away.
    @Test("An account the format cannot restore can no longer be enrolled")
    func theOriginalFailureIsClosed() {
        #expect(throws: OTPAuthURIError.secretTooShort) {
            _ = try OTPAuthURI.account(from: "otpauth://totp/x?secret=GEZDGNBV")
        }
        #expect(throws: OTPAuthURIError.invalidCounter("9007199254740992")) {
            _ = try OTPAuthURI.account(
                from: "otpauth://hotp/x?secret=GEZDGNBVGY3TQOJQ&counter=9007199254740992")
        }
    }

    // MARK: - The writer, for accounts that predate the guards

    /// **The guards above stop new ones; this stops the old ones being written silently.** An
    /// account saved before those checks existed is still in the store, and the export is where
    /// it must be caught, because the alternative is an archive whose owner discovers the
    /// problem only when they need it.
    @Test("The writer refuses an account the reader would turn away")
    func theWriterRefusesWhatTheReaderWould() {
        let short = ImportedAccount(
            account: OTPAccount(
                issuer: "GitHub", name: "octocat", secret: secret(5),
                generator: .totp(.standard)),
            color: .red, sortIndex: 0)

        #expect(throws: BackupError.cannotStoreAccount(label: "GitHub")) {
            _ = try BackupPayload.write([short])
        }

        let hugeCounter = ImportedAccount(
            account: OTPAccount(
                issuer: "Bank", name: "me", secret: secret(20),
                generator: .hotp(
                    counter: AccountLimits.maximumCounter + 1, digits: .six, algorithm: .sha1)),
            color: .red, sortIndex: 0)

        #expect(throws: BackupError.cannotStoreAccount(label: "Bank")) {
            _ = try BackupPayload.write([hugeCounter])
        }
    }

    /// And a storable account still writes, so the refusal is a bound rather than a ban.
    @Test("A storable account still writes and reads back")
    func aStorableAccountStillRoundTrips() throws {
        let fine = ImportedAccount(
            account: OTPAccount(
                issuer: "GitHub", name: "octocat", secret: secret(20),
                generator: .totp(.standard)),
            color: .red, sortIndex: 0)

        let payload = try BackupPayload.write([fine])
        let restored = BackupPayload.read(payload)
        #expect(restored?.accounts.count == 1)
        #expect(restored?.accounts.first?.account.secret == secret(20))
    }
}
