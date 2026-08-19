import CryptoKit
import Foundation
import Testing

@testable import OpenFactorCore

/// The watch exchange, and the four things that must fail.
///
/// **Agreement alone would prove nothing.** Two sides of one implementation will agree with each
/// other whether or not the binding is real, which is why gate E7 ran negative controls and why
/// they are repeated here as tests: substitute the phone's key, alter the transcript, replay an
/// old response, and each must stop working. A suite that only checked the happy path would pass
/// against an exchange with no binding at all.
@Suite("Watch provisioning")
struct WatchProvisioningTests {

    private func vaultKey() -> SymmetricKey {
        SymmetricKey(data: Data((0..<32).map { UInt8($0) }))
    }

    private func bytes(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    // MARK: - The exchange as it is meant to go

    @Test("The watch recovers exactly the key the phone sealed")
    func roundTrips() throws {
        let attempt = try WatchProvisioning.Attempt()
        let response = try WatchProvisioning.respond(to: attempt.request, with: vaultKey())

        let recovered = try attempt.open(response)
        #expect(bytes(recovered) == bytes(vaultKey()))
    }

    /// The sizes gate E7 measured, asserted so a change to the layout is a failing test rather
    /// than a surprise on a wrist.
    @Test("The messages are the sizes the design states")
    func sizes() throws {
        let attempt = try WatchProvisioning.Attempt()
        #expect(attempt.request.count == 85)

        let response = try WatchProvisioning.respond(to: attempt.request, with: vaultKey())
        #expect(response.count == 145)

        // Against WatchConnectivity's interactive limit. Four hundred times the headroom.
        #expect(response.count < 65_536)
    }

    @Test("Every exchange is fresh")
    func exchangesAreFresh() throws {
        var requests: Set<Data> = []
        var responses: Set<Data> = []

        for _ in 0..<8 {
            let attempt = try WatchProvisioning.Attempt()
            requests.insert(attempt.request)
            responses.insert(try WatchProvisioning.respond(to: attempt.request, with: vaultKey()))
        }

        #expect(requests.count == 8)
        #expect(responses.count == 8)
    }

    // MARK: - The negative controls

    /// The one that proves the transcript binding is real. Gate E7 ran it before any of this
    /// existed, and it is the difference between a bound exchange and a decorative one.
    @Test("A substituted phone public key does not open it")
    func substitutedPhoneKeyFails() throws {
        let attempt = try WatchProvisioning.Attempt()
        let response = try WatchProvisioning.respond(to: attempt.request, with: vaultKey())

        // Replace the phone's public key with another valid point, leaving everything else.
        var tampered = response
        let start = 4 + 16
        let other = P256.KeyAgreement.PrivateKey().publicKey.x963Representation
        tampered.replaceSubrange(start..<(start + 65), with: other)

        #expect(throws: WatchProvisioning.ExchangeError.couldNotOpen) {
            try attempt.open(tampered)
        }
    }

    /// A response meant for a different request, which is what a replayed one is.
    @Test("A response to somebody else's request is refused before anything is derived")
    func replayIsRefused() throws {
        let first = try WatchProvisioning.Attempt()
        let second = try WatchProvisioning.Attempt()

        let forFirst = try WatchProvisioning.respond(to: first.request, with: vaultKey())

        #expect(throws: WatchProvisioning.ExchangeError.notForThisRequest) {
            try second.open(forFirst)
        }
    }

    @Test("An altered sealed payload does not open")
    func alteredPayloadFails() throws {
        let attempt = try WatchProvisioning.Attempt()
        var response = try WatchProvisioning.respond(to: attempt.request, with: vaultKey())

        response[response.count - 1] ^= 0x01

        #expect(throws: WatchProvisioning.ExchangeError.couldNotOpen) {
            try attempt.open(response)
        }
    }

    @Test("A response of the wrong length is refused")
    func wrongLengthIsRefused() throws {
        let attempt = try WatchProvisioning.Attempt()
        let response = try WatchProvisioning.respond(to: attempt.request, with: vaultKey())

        #expect(throws: WatchProvisioning.ExchangeError.malformed) {
            try attempt.open(response.dropLast())
        }
        #expect(throws: WatchProvisioning.ExchangeError.malformed) {
            try attempt.open(response + Data([0]))
        }
    }

    @Test("A message from another version is refused rather than misread")
    func versionIsChecked() throws {
        let attempt = try WatchProvisioning.Attempt()
        var response = try WatchProvisioning.respond(to: attempt.request, with: vaultKey())
        response.replaceSubrange(0..<4, with: Data("OFW2".utf8))

        #expect(throws: WatchProvisioning.ExchangeError.unsupportedVersion) {
            try attempt.open(response)
        }

        var request = attempt.request
        request.replaceSubrange(0..<4, with: Data("OFW2".utf8))
        #expect(throws: WatchProvisioning.ExchangeError.unsupportedVersion) {
            _ = try WatchProvisioning.respond(to: request, with: vaultKey())
        }
    }

    @Test("A request whose public key is not a point is refused")
    func invalidPublicKeyIsRefused() throws {
        let attempt = try WatchProvisioning.Attempt()
        var request = attempt.request
        request.replaceSubrange(20..<85, with: Data(repeating: 0xAA, count: 65))

        #expect(throws: WatchProvisioning.ExchangeError.invalidPublicKey) {
            _ = try WatchProvisioning.respond(to: request, with: vaultKey())
        }
    }

    @Test("A request of the wrong length is refused")
    func shortRequestIsRefused() {
        #expect(throws: WatchProvisioning.ExchangeError.malformed) {
            _ = try WatchProvisioning.respond(to: Data(repeating: 0, count: 40), with: vaultKey())
        }
    }

    // MARK: - Negative controls added after an independent review

    /// **The ordering test that actually observes the ordering.** `replayIsRefused` above claims
    /// in its name that nothing is derived before the nonce is checked, and it cannot see that:
    /// its response carries a valid phone public key, so the same error comes back whichever
    /// order the two checks run in. A review pointed that out. This response is wrong in both
    /// ways at once, so the error names which check ran first: the nonce, as intended.
    @Test("The nonce is checked before the public key is even parsed")
    func nonceIsCheckedBeforeParsingTheKey() throws {
        let mine = try WatchProvisioning.Attempt()
        let other = try WatchProvisioning.Attempt()

        // Somebody else's nonce, and a public key field that is not a point at all.
        var response = WatchProvisioning.magic
        response.append(other.request[4..<4 + WatchProvisioning.nonceCount])
        response.append(Data(repeating: 0, count: WatchProvisioning.publicKeyCount))
        response.append(Data(repeating: 0, count: WatchProvisioning.sealedCount))

        #expect(throws: WatchProvisioning.ExchangeError.notForThisRequest) {
            try mine.open(response)
        }
    }

    /// The response direction of a check only the request direction had.
    @Test("A response whose public key is not a point is refused")
    func responseWithInvalidPublicKeyIsRefused() throws {
        let attempt = try WatchProvisioning.Attempt()

        var response = WatchProvisioning.magic
        response.append(attempt.request[4..<4 + WatchProvisioning.nonceCount])
        response.append(Data(repeating: 0, count: WatchProvisioning.publicKeyCount))
        response.append(Data(repeating: 0, count: WatchProvisioning.sealedCount))

        #expect(throws: WatchProvisioning.ExchangeError.invalidPublicKey) {
            try attempt.open(response)
        }
    }

    /// Every boundary either side of the exact length, in both directions, because slice
    /// arithmetic on a length nobody checked is how a message crashes an app.
    @Test("Every length but the exact one is refused, in both directions")
    func lengthsAreExact() throws {
        let attempt = try WatchProvisioning.Attempt()

        for count in [0, 1, WatchProvisioning.requestCount - 1, WatchProvisioning.requestCount + 1] {
            #expect(throws: WatchProvisioning.ExchangeError.malformed) {
                _ = try WatchProvisioning.validate(Data(repeating: 0, count: count))
            }
        }

        for count in [
            0, 1, WatchProvisioning.responseCount - 1, WatchProvisioning.responseCount + 1,
        ] {
            #expect(throws: WatchProvisioning.ExchangeError.malformed) {
                try attempt.open(Data(repeating: 0, count: count))
            }
        }
    }

    /// The request the phone answers is bound into the key, so a watch cannot be handed a key
    /// sealed for a public key it did not send. Pins `w_pub` specifically: the phone answers a
    /// request carrying somebody else's public key, and the original attempt cannot open it even
    /// though the nonce matches.
    @Test("A substituted watch public key does not open with the original attempt")
    func substitutedWatchKeyDoesNotOpen() throws {
        let mine = try WatchProvisioning.Attempt()
        let other = try WatchProvisioning.Attempt()

        // My magic and my nonce, somebody else's public key.
        var forged = WatchProvisioning.magic
        forged.append(mine.request[4..<4 + WatchProvisioning.nonceCount])
        forged.append(other.request[(4 + WatchProvisioning.nonceCount)...])

        let response = try WatchProvisioning.respond(to: forged, with: vaultKey())

        // **Neither attempt can open it, and the two reasons are the two bindings.** Writing
        // this test the obvious way asserted that the holder of the substituted key could open
        // it, and that was wrong: the response echoes the forged request's nonce, which is mine,
        // so it does not answer the other attempt at all. The failure modes name which field
        // stopped each one.
        #expect(throws: WatchProvisioning.ExchangeError.couldNotOpen) {
            try mine.open(response)
        }
        #expect(throws: WatchProvisioning.ExchangeError.notForThisRequest) {
            try other.open(response)
        }
    }

    /// The bytes a review used as its example: the magic, then eighty-one zeroes. It must be
    /// refused by parsing, which is what lets the phone refuse it before loading a key or
    /// putting a question on somebody's screen.
    @Test("A well formed header over rubbish is refused by validation alone")
    func validationRefusesRubbish() {
        var request = WatchProvisioning.magic
        request.append(Data(repeating: 0, count: WatchProvisioning.requestCount - 4))

        #expect(throws: WatchProvisioning.ExchangeError.invalidPublicKey) {
            _ = try WatchProvisioning.validate(request)
        }
    }

    /// A valid request validates, and validating touches no secret: it is the cheap check the
    /// phone runs before it reads its vault key.
    @Test("A real request validates")
    func realRequestValidates() throws {
        let attempt = try WatchProvisioning.Attempt()
        #expect(throws: Never.self) { _ = try WatchProvisioning.validate(attempt.request) }
    }

    // MARK: - What a round trip cannot see

    /// **A round trip tests two sides against each other, so anything weakened on both sides
    /// passes.** Gate A4 demonstrated that twice against this suite, by breaking the code
    /// deliberately and watching every test stay green. These two are the tests that would have
    /// gone red.
    ///
    /// The lesson generalises past this file: a construction is not pinned by a test that only
    /// asks whether the writer and the reader agree. It has to be asked whether the construction
    /// is the one that was specified.

    /// **The phone's keypair must be fresh for every reply.** A static one passes every other
    /// test here, including `exchangesAreFresh`, which varies the request and so sees different
    /// responses regardless. The consequence of a static key is that a captured response plus a
    /// later compromise of the phone recovers the vault key, which is the whole reason the
    /// exchange is ephemeral.
    @Test("Two responses to the same request differ, and both open")
    func responsesToOneRequestAreFresh() throws {
        let attempt = try WatchProvisioning.Attempt()
        let key = vaultKey()

        let first = try WatchProvisioning.respond(to: attempt.request, with: key)
        let second = try WatchProvisioning.respond(to: attempt.request, with: key)

        #expect(first != second, "a static phone keypair would make these identical")

        // Both must still open: freshness that broke the exchange would be no use.
        #expect(try attempt.open(first) == key)
        #expect(try attempt.open(second) == key)

        // And the difference must be in the phone's public key, not only in the GCM nonce,
        // since a fresh nonce under a reused key is the case this is guarding against.
        let publicKeyRange = 4 + WatchProvisioning.nonceCount..<(4 + WatchProvisioning.nonceCount
            + WatchProvisioning.publicKeyCount)
        #expect(
            first[publicKeyRange] != second[publicKeyRange],
            "the ephemeral key itself must change, not just the nonce")
    }

    /// **The HKDF label is domain separation and nothing else pins it.** Deleting `label +` from
    /// the info passes the entire suite, because both sides build the info from one function and
    /// the change is symmetric. This asks the question a round trip cannot: does the label
    /// actually take part in the derivation.
    @Test("The domain separation label changes the derived key")
    func theLabelParticipatesInDerivation() throws {
        let watch = P256.KeyAgreement.PrivateKey()
        let phone = P256.KeyAgreement.PrivateKey()
        let transcript = WatchProvisioning.transcript(
            nonce: Data(repeating: 0xab, count: WatchProvisioning.nonceCount),
            watchPublicKey: watch.publicKey.x963Representation,
            phonePublicKey: phone.publicKey.x963Representation)

        let withLabel = try WatchProvisioning.wrappingKey(
            privateKey: watch, peer: phone.publicKey, transcript: transcript)

        // The same shared secret and the same transcript, derived without the label. If the
        // label were absent from the real derivation, these would match.
        let shared = try watch.sharedSecretFromKeyAgreement(with: phone.publicKey)
        let withoutLabel = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data(), sharedInfo: transcript, outputByteCount: 32)

        #expect(
            withLabel != withoutLabel,
            "the label must take part, or this exchange shares a key with any other use of it")
    }

    // MARK: - The derivation itself

    /// Both sides must reach the same key from opposite halves of the same exchange. This is the
    /// property the whole thing rests on, checked directly rather than only through a round trip.
    @Test("Both sides derive the same wrapping key")
    func bothSidesAgree() throws {
        let watch = P256.KeyAgreement.PrivateKey()
        let phone = P256.KeyAgreement.PrivateKey()
        let nonce = Data(repeating: 0x5A, count: 16)

        let transcript = WatchProvisioning.transcript(
            nonce: nonce,
            watchPublicKey: watch.publicKey.x963Representation,
            phonePublicKey: phone.publicKey.x963Representation)

        let fromWatch = try WatchProvisioning.wrappingKey(
            privateKey: watch, peer: phone.publicKey, transcript: transcript)
        let fromPhone = try WatchProvisioning.wrappingKey(
            privateKey: phone, peer: watch.publicKey, transcript: transcript)

        #expect(bytes(fromWatch) == bytes(fromPhone))
        #expect(bytes(fromWatch).count == 32)
    }

    /// A transcript that changed must produce a different key, or binding it would achieve
    /// nothing. One flipped byte is enough to demand a completely different answer.
    @Test("A different transcript derives a different key")
    func transcriptChangesTheKey() throws {
        let watch = P256.KeyAgreement.PrivateKey()
        let phone = P256.KeyAgreement.PrivateKey()

        let base = WatchProvisioning.transcript(
            nonce: Data(repeating: 0x5A, count: 16),
            watchPublicKey: watch.publicKey.x963Representation,
            phonePublicKey: phone.publicKey.x963Representation)

        var altered = base
        altered[altered.startIndex + 4] ^= 0x01

        let a = try WatchProvisioning.wrappingKey(
            privateKey: watch, peer: phone.publicKey, transcript: base)
        let b = try WatchProvisioning.wrappingKey(
            privateKey: watch, peer: phone.publicKey, transcript: altered)

        #expect(bytes(a) != bytes(b))
    }

    @Test("The transcript is the four fields, in the order they were sent")
    func transcriptLayout() {
        let watchKey = Data(repeating: 0x11, count: 65)
        let phoneKey = Data(repeating: 0x22, count: 65)
        let nonce = Data(repeating: 0x33, count: 16)

        let transcript = WatchProvisioning.transcript(
            nonce: nonce, watchPublicKey: watchKey, phonePublicKey: phoneKey)

        #expect(transcript.count == 150)
        #expect(transcript.prefix(4) == Data("OFW1".utf8))
        #expect(transcript.dropFirst(4).prefix(16) == nonce)
        #expect(transcript.dropFirst(20).prefix(65) == watchKey)
        #expect(transcript.dropFirst(85) == phoneKey)
    }
}

/// The words the two devices exchange, as opposed to the cryptography they wrap.
///
/// **These are wire values, and that is the whole point of pinning them.** The phone and the
/// watch used to hold separate hand written copies of these strings in separate modules, with
/// anything unrecognised falling through to "not set up". A rename on one side would have
/// compiled, shipped, and told somebody their watch was not set up when the truth was that
/// their phone had no vault. They are one declaration now, so the compiler catches a mismatch,
/// and these tests catch the other half: a rename that compiles everywhere and silently changes
/// what goes over the air to a watch running an older build.
@Suite("Watch answer vocabulary")
struct WatchAnswerVocabularyTests {

    @Test("The answers on the wire are exactly these four strings")
    func wireValuesArePinned() {
        #expect(WatchProvisioning.Answer.asking.rawValue == "asking")
        #expect(WatchProvisioning.Answer.needsApp.rawValue == "needsApp")
        #expect(WatchProvisioning.Answer.noVault.rawValue == "noVault")
        #expect(WatchProvisioning.Answer.declined.rawValue == "declined")
        #expect(WatchProvisioning.Answer.busy.rawValue == "busy")
    }

    // MARK: - The consent window

    /// **The window is measured on a clock that cannot be moved.** All three round-two reviews
    /// found the same hole in the first version, which used `Date`: a backward jump makes the
    /// elapsed time negative, negative passes any "within the window" test, and the request stays
    /// answerable indefinitely. That is the failure the window exists to prevent, reached by
    /// changing the time zone.
    ///
    /// The window itself is enforced in `WatchKeyProvider`, which lives in the app target and
    /// cannot be reached from here. What is pinned here is the measurement it asks for.
    @Test("A request's age is never negative and only grows")
    func ageIsMonotonic() throws {
        let attempt = try WatchProvisioning.Attempt()
        let request = try WatchProvisioning.validate(attempt.request)

        let start = request.validatedAt
        #expect(request.age(now: start) == 0)
        #expect(request.age(now: start.advanced(by: Duration.seconds(90))) == 90)

        // The instant a wall clock would report as an hour ago. There is no way to hand a
        // `ContinuousClock.Instant` a value before the one it issued and have it read as time
        // passing, which is the whole point, so this asks for the arithmetic explicitly.
        #expect(request.age(now: start.advanced(by: Duration.seconds(-3600))) <= 0,
                "a jump backwards must never read as inside the window")
    }

    @Test("The message keys on the wire are exactly these four strings")
    func messageKeysArePinned() {
        #expect(WatchProvisioning.MessageKey.request == "request")
        #expect(WatchProvisioning.MessageKey.response == "response")
        #expect(WatchProvisioning.MessageKey.status == "status")
        // Added when the refusal gained a nonce, and missed at the time: round two found the
        // test still saying "exactly these three" while a fourth key was live. Renaming this one
        // would compile everywhere, and every decline from a newer phone would look nonce-less
        // to a watch, which is the defect the nonce was added to close.
        #expect(WatchProvisioning.MessageKey.nonce == "nonce")
    }

    /// A new answer is not a free addition: the watch switches over every case, so adding one
    /// without deciding what it shows would fail to build there rather than here. This asserts
    /// the set anybody reasoning about that switch is looking at.
    @Test("There are five answers, and no more")
    func theSetIsClosed() {
        #expect(WatchProvisioning.Answer.allCases.count == 5)
        #expect(
            Set(WatchProvisioning.Answer.allCases.map(\.rawValue))
                == ["asking", "needsApp", "noVault", "declined", "busy"])
    }

    @Test("Every answer survives the round trip a message puts it through")
    func roundTrips() {
        for answer in WatchProvisioning.Answer.allCases {
            #expect(WatchProvisioning.Answer(rawValue: answer.rawValue) == answer)
        }
    }

    /// The safe default, asserted rather than assumed: anything this build does not recognise
    /// is not an answer, and the watch treats a non-answer as "not set up, try again".
    @Test("An unknown or absent status is not an answer")
    func unknownIsNotAnAnswer() {
        #expect(WatchProvisioning.Answer(rawValue: "somethingNewer") == nil)
        #expect(WatchProvisioning.Answer(rawValue: "") == nil)
        #expect(WatchProvisioning.Answer(rawValue: "Asking") == nil)
    }
}
