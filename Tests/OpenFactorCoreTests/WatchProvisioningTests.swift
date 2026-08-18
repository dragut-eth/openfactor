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
        let attempt = WatchProvisioning.Attempt()
        let response = try WatchProvisioning.respond(to: attempt.request, with: vaultKey())

        let recovered = try attempt.open(response)
        #expect(bytes(recovered) == bytes(vaultKey()))
    }

    /// The sizes gate E7 measured, asserted so a change to the layout is a failing test rather
    /// than a surprise on a wrist.
    @Test("The messages are the sizes the design states")
    func sizes() throws {
        let attempt = WatchProvisioning.Attempt()
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
            let attempt = WatchProvisioning.Attempt()
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
        let attempt = WatchProvisioning.Attempt()
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
        let first = WatchProvisioning.Attempt()
        let second = WatchProvisioning.Attempt()

        let forFirst = try WatchProvisioning.respond(to: first.request, with: vaultKey())

        #expect(throws: WatchProvisioning.ExchangeError.notForThisRequest) {
            try second.open(forFirst)
        }
    }

    @Test("An altered sealed payload does not open")
    func alteredPayloadFails() throws {
        let attempt = WatchProvisioning.Attempt()
        var response = try WatchProvisioning.respond(to: attempt.request, with: vaultKey())

        response[response.count - 1] ^= 0x01

        #expect(throws: WatchProvisioning.ExchangeError.couldNotOpen) {
            try attempt.open(response)
        }
    }

    @Test("A response of the wrong length is refused")
    func wrongLengthIsRefused() throws {
        let attempt = WatchProvisioning.Attempt()
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
        let attempt = WatchProvisioning.Attempt()
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
        let attempt = WatchProvisioning.Attempt()
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
    }

    @Test("The message keys on the wire are exactly these three strings")
    func messageKeysArePinned() {
        #expect(WatchProvisioning.MessageKey.request == "request")
        #expect(WatchProvisioning.MessageKey.response == "response")
        #expect(WatchProvisioning.MessageKey.status == "status")
    }

    /// A new answer is not a free addition: the watch switches over every case, so adding one
    /// without deciding what it shows would fail to build there rather than here. This asserts
    /// the set anybody reasoning about that switch is looking at.
    @Test("There are four answers, and no more")
    func theSetIsClosed() {
        #expect(WatchProvisioning.Answer.allCases.count == 4)
        #expect(
            Set(WatchProvisioning.Answer.allCases.map(\.rawValue))
                == ["asking", "needsApp", "noVault", "declined"])
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
