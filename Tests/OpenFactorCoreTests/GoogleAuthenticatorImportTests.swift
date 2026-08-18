import Foundation
import Testing

@testable import OpenFactorCore

/// Reading a Google Authenticator export.
///
/// The payloads here are built byte by byte with a small encoder rather than pasted in as
/// base64 blobs. Two reasons. A blob is unreadable, so a test written from one asserts
/// whatever the blob happened to contain and nobody can tell what was meant. And the encoder
/// lets the malformed cases be constructed deliberately: a length that lies, a varint that
/// never ends, a wire type nothing should send.
@Suite("Google Authenticator import")
struct GoogleAuthenticatorImportTests {

    // MARK: - A protobuf encoder, for building fixtures

    private func varint(_ value: UInt64) -> Data {
        var value = value
        var data = Data()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            data.append(byte)
        } while value != 0
        return data
    }

    private func varintField(_ number: Int, _ value: UInt64) -> Data {
        varint(UInt64(number) << 3 | 0) + varint(value)
    }

    private func bytesField(_ number: Int, _ payload: Data) -> Data {
        varint(UInt64(number) << 3 | 2) + varint(UInt64(payload.count)) + payload
    }

    private func parameters(
        secret: Data = Data("12345678901234567890".utf8),
        name: String = "octocat",
        issuer: String? = "GitHub",
        algorithm: UInt64 = 1,
        digits: UInt64 = 1,
        type: UInt64 = 2,
        counter: UInt64? = nil
    ) -> Data {
        var data = bytesField(1, secret) + bytesField(2, Data(name.utf8))
        if let issuer { data += bytesField(3, Data(issuer.utf8)) }
        data += varintField(4, algorithm) + varintField(5, digits) + varintField(6, type)
        if let counter { data += varintField(7, counter) }
        return data
    }

    private func payload(
        _ accounts: [Data],
        index: UInt64 = 0,
        size: UInt64 = 1,
        id: UInt64 = 7
    ) -> Data {
        accounts.reduce(Data()) { $0 + bytesField(1, $1) }
            + varintField(2, 1)
            + varintField(3, size)
            + varintField(4, index)
            + varintField(5, id)
    }

    private func uri(_ payload: Data) -> String {
        let encoded = payload.base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return "otpauth-migration://offline?data=\(encoded)"
    }

    private func read(_ payload: Data) throws -> GoogleAuthenticatorImport.Batch {
        try GoogleAuthenticatorImport.read(uri(payload))
    }

    // MARK: - What it reads

    /// **The secret is raw bytes, not Base32.** Decoding it would produce an account that
    /// generates entirely plausible codes that no service accepts, which is the worst shape
    /// an import bug can take: nothing looks wrong until a login fails.
    @Test("The secret is taken as bytes rather than decoded")
    func secretIsRaw() throws {
        let secret = Data("12345678901234567890".utf8)
        let batch = try read(payload([parameters(secret: secret)]))

        #expect(batch.result.accounts.first?.account.secret == secret)
    }

    @Test("An account arrives with everything the code carried")
    func readsAnAccount() throws {
        let batch = try read(
            payload([parameters(name: "octocat", issuer: "GitHub", algorithm: 2, digits: 2)])
        )
        let account = try #require(batch.result.accounts.first?.account)

        #expect(account.issuer == "GitHub")
        #expect(account.name == "octocat")
        #expect(
            account.generator
                == .totp(try TOTPConfiguration(algorithm: .sha256, digits: .eight, period: 30))
        )
    }

    /// There is no period field in the schema, and 30 is the value rather than a guess:
    /// Google Authenticator has no interface for changing it.
    @Test("Time based accounts get the period the format fixes")
    func periodIsThirty() throws {
        let batch = try read(payload([parameters()]))

        guard case let .totp(configuration) = batch.result.accounts.first?.account.generator else {
            Issue.record("expected a time based account")
            return
        }
        #expect(configuration.period == 30)
    }

    @Test("A counter based account keeps its counter")
    func readsCounters() throws {
        let batch = try read(payload([parameters(type: 1, counter: 41)]))

        #expect(
            batch.result.accounts.first?.account.generator
                == .hotp(counter: 41, digits: .six, algorithm: .sha1)
        )
    }

    @Test("Several accounts arrive in the order they were written")
    func readsSeveral() throws {
        let batch = try read(
            payload([
                parameters(name: "one", issuer: "First"),
                parameters(name: "two", issuer: "Second"),
                parameters(name: "three", issuer: "Third"),
            ])
        )

        #expect(batch.result.accounts.map(\.account.issuer) == ["First", "Second", "Third"])
        #expect(batch.result.accounts.map(\.sortIndex) == [0, 1, 2])
    }

    @Test("An account with no issuer keeps its name and nothing invented")
    func handlesMissingIssuer() throws {
        let batch = try read(payload([parameters(name: "octocat", issuer: nil)]))

        #expect(batch.result.accounts.first?.account.issuer == nil)
        #expect(batch.result.accounts.first?.account.name == "octocat")
    }

    // MARK: - Their enumerations are not ours

    /// Refused by name rather than guessed at. Google permits MD5; this app does not
    /// implement it, and importing it as SHA1 would produce codes rejected forever.
    @Test("An MD5 account is refused, and the refusal says MD5")
    func refusesMD5() throws {
        let batch = try read(payload([parameters(algorithm: 4)]))

        #expect(batch.result.accounts.isEmpty)
        #expect(batch.result.refusals.first?.reason == .unsupportedAlgorithm("MD5"))
        #expect(batch.result.refusals.first?.label == "GitHub")
    }

    @Test("An unspecified algorithm, digit count or type is refused rather than defaulted", arguments: [
        (UInt64(0), UInt64(1), UInt64(2)),
        (UInt64(1), UInt64(0), UInt64(2)),
        (UInt64(1), UInt64(1), UInt64(0)),
    ])
    func refusesUnspecifiedEnumerations(algorithm: UInt64, digits: UInt64, type: UInt64) throws {
        let batch = try read(
            payload([parameters(algorithm: algorithm, digits: digits, type: type)])
        )

        #expect(batch.result.accounts.isEmpty)
        #expect(batch.result.refusals.count == 1)
    }

    @Test("A secret below the RFC minimum is refused rather than imported")
    func refusesShortSecrets() throws {
        let batch = try read(payload([parameters(secret: Data("123456789".utf8))]))

        #expect(batch.result.accounts.isEmpty)
        #expect(batch.result.refusals.first?.reason == .secretNotBase32)
    }

    @Test("One bad account does not lose the rest of the code")
    func oneBadAccountDoesNotFailTheCode() throws {
        let batch = try read(
            payload([
                parameters(name: "good", issuer: "First"),
                parameters(name: "bad", issuer: "Second", algorithm: 4),
                parameters(name: "also good", issuer: "Third"),
            ])
        )

        #expect(batch.result.accounts.count == 2)
        #expect(batch.result.refusals.count == 1)
        #expect(batch.result.refusals.first?.position == 2)
    }

    // MARK: - Batches

    /// A person who scans one part of three and is told "12 accounts found" has been told
    /// something true and misleading at once.
    @Test("A code says which part of an export it is")
    func reportsItsPosition() throws {
        let batch = try read(payload([parameters()], index: 1, size: 3, id: 4242))

        #expect(batch.position == 2)
        #expect(batch.size == 3)
        #expect(batch.id == 4242)
        #expect(!batch.isComplete)
    }

    @Test("A single code export is complete on its own")
    func singleCodeIsComplete() throws {
        #expect(try read(payload([parameters()])).isComplete)
    }

    // MARK: - Hostile input

    @Test("Anything that is not a migration code is named as such")
    func rejectsOtherSchemes() {
        for text in [
            "otpauth://totp/GitHub:octocat?secret=GEZDGNBVGY3TQOJQ",
            "https://example.com",
            "",
            "hello",
        ] {
            #expect(!GoogleAuthenticatorImport.looksLikeMigration(text))
            #expect(throws: GoogleAuthenticatorImport.FileError.notAMigrationCode) {
                try GoogleAuthenticatorImport.read(text)
            }
        }
    }

    @Test("A migration code that is not readable says so rather than importing nothing")
    func rejectsMalformedCodes() {
        for text in [
            "otpauth-migration://offline",
            "otpauth-migration://offline?data=",
            "otpauth-migration://offline?data=!!!!not base64!!!!",
            "otpauth-migration://offline?data=aGVsbG8gd29ybGQ=",
        ] {
            #expect(throws: GoogleAuthenticatorImport.FileError.malformed) {
                try GoogleAuthenticatorImport.read(text)
            }
        }
    }

    /// The length prefix is the attacker's number. A reader that allocates to it is a reader
    /// that a four byte QR code can ask for four gigabytes from.
    @Test("A length that claims more than exists is refused, not allocated")
    func refusesLyingLengths() {
        // Field 1, length delimited, claiming 4 GiB, followed by nothing.
        let lying = Data([0x0A]) + varint(4 * 1024 * 1024 * 1024)

        #expect(throws: ProtobufReader.ReadError.truncated) {
            try ProtobufReader.fields(in: lying)
        }
    }

    @Test("A varint that never ends is refused")
    func refusesEndlessVarints() {
        let endless = Data([0x08]) + Data(repeating: 0xFF, count: 32)

        #expect(throws: ProtobufReader.ReadError.malformedVarint) {
            try ProtobufReader.fields(in: endless)
        }
    }

    /// Groups are the one wire type whose skip logic is recursive, which is the shape stack
    /// exhaustion arrives in. They are deprecated and nothing here sends them.
    @Test("A group is refused rather than skipped")
    func refusesGroups() {
        #expect(throws: ProtobufReader.ReadError.unsupportedWireType(3)) {
            try ProtobufReader.fields(in: Data([0x0B]))
        }
    }

    @Test("Field number zero is refused")
    func refusesFieldNumberZero() {
        #expect(throws: ProtobufReader.ReadError.malformedVarint) {
            try ProtobufReader.fields(in: Data([0x00, 0x01]))
        }
    }

    @Test("A truncated message is refused rather than half read")
    func refusesTruncatedMessages() throws {
        let complete = payload([parameters()])

        for length in 1..<complete.count {
            let truncated = complete.prefix(length)
            // Either it fails to parse, or it parses to something with no accounts in it.
            // What it must never do is produce an account, since half a secret is a secret
            // that generates wrong codes.
            if let batch = try? GoogleAuthenticatorImport.read(uri(Data(truncated))) {
                #expect(
                    batch.result.accounts.allSatisfy { $0.account.secret.count >= 10 },
                    "a truncated code produced an account at length \(length)"
                )
            }
        }
    }

    /// A newer writer is expected to send fields this reader has never heard of, and the
    /// wire format's whole compatibility story is that they are skipped.
    @Test("Unknown fields are skipped rather than refused")
    func skipsUnknownFields() throws {
        let withExtras =
            bytesField(1, parameters() + varintField(99, 1) + bytesField(98, Data("x".utf8)))
            + varintField(3, 1)
            + bytesField(97, Data(repeating: 0, count: 8))

        let batch = try read(withExtras)

        #expect(batch.result.accounts.count == 1)
    }
}

/// The batch header's three integers, which arrive from a QR code or from any app on the device
/// through the `otpauth-migration://` scheme.
///
/// **Gate A4 found a crash here and this suite is the reason it can only happen once.** The
/// fields were read with `Int(clamping:)`, so `UInt64.max` became `Int.max`, and `Batch.position`
/// then added one to it and trapped while a SwiftUI sheet was being built. The payload below is
/// the one the review used, reproduced exactly.
@Suite("Migration batch bounds")
struct MigrationBatchBoundsTests {

    /// `0a 00` is an empty account record, so the message parses; `20 ff…01` is field 4,
    /// `batch_index`, carrying `UInt64.max`.
    private var theCrashingPayload: String {
        let bytes: [UInt8] = [
            0x0a, 0x00, 0x20, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
        ]
        let encoded = Data(bytes).base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return "otpauth-migration://offline?data=" + encoded
    }

    @Test("The payload that crashed the app is refused")
    func theCrashingPayloadIsRefused() {
        #expect(throws: GoogleAuthenticatorImport.FileError.malformed) {
            _ = try GoogleAuthenticatorImport.read(theCrashingPayload)
        }
    }

    /// The property that trapped. Reading it must be safe for anything that parsed, which is
    /// what the refusal above buys.
    @Test("Position is safe for every batch that parses")
    func positionIsSafeForAnythingThatParses() throws {
        let batch = try GoogleAuthenticatorImport.read(theOrdinaryPayload)
        #expect(batch.position == batch.index + 1)
    }

    /// A batch field one past the accepted range is malformed, not clamped. Checked for all
    /// three fields, because two of them were clamped the same way and only one was reachable
    /// from the reported crash.
    @Test("Every batch field is refused above the bound")
    func everyFieldIsBounded() {
        for field: UInt8 in [0x18, 0x20, 0x28] {  // size, index, id
            var bytes: [UInt8] = [0x0a, 0x00, field]
            bytes.append(contentsOf: varint(UInt64(GoogleAuthenticatorImport.maximumBatchField) + 1))
            let encoded = Data(bytes).base64EncodedString()
                .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

            #expect(throws: GoogleAuthenticatorImport.FileError.malformed) {
                _ = try GoogleAuthenticatorImport.read(
                    "otpauth-migration://offline?data=" + encoded)
            }
        }
    }

    /// And the bound itself is accepted, so the refusal is a bound rather than a ban.
    @Test("A batch field at the bound is accepted")
    func theBoundItselfIsAccepted() throws {
        var bytes: [UInt8] = [0x0a, 0x00, 0x20]
        bytes.append(contentsOf: varint(UInt64(GoogleAuthenticatorImport.maximumBatchField)))
        let encoded = Data(bytes).base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

        let batch = try GoogleAuthenticatorImport.read(
            "otpauth-migration://offline?data=" + encoded)
        #expect(batch.index == GoogleAuthenticatorImport.maximumBatchField)
        #expect(batch.position == GoogleAuthenticatorImport.maximumBatchField + 1)
    }

    private var theOrdinaryPayload: String {
        let bytes: [UInt8] = [0x0a, 0x00, 0x20, 0x02]
        let encoded = Data(bytes).base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return "otpauth-migration://offline?data=" + encoded
    }

    private func varint(_ value: UInt64) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7f)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }
}
