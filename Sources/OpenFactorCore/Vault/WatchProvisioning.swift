import CryptoKit
import Foundation

/// Handing the vault key to a paired watch, once.
///
/// Typing 24 characters on a wrist is not a design, so the watch asks its phone instead. Two
/// messages, no typing, and nothing persisted along the way.
///
/// ```
/// Watch                                          Phone
///
///  generate w_priv / w_pub and a 16 byte nonce
///  ── "OFW1" ‖ nonce ‖ w_pub ───────────────────►      85 bytes
///                                   generate p_priv / p_pub
///                                   shared     = ECDH(p_priv, w_pub)
///                                   transcript = "OFW1" ‖ nonce ‖ w_pub ‖ p_pub
///                                   kek        = HKDF-SHA256(shared, info: label ‖ transcript)
///                                   sealed     = AES-256-GCM(kek, vaultKey, aad: transcript)
///  ◄── "OFW1" ‖ nonce ‖ p_pub ‖ sealed ──────────    145 bytes
///  check the nonce is ours, derive, open, install
/// ```
///
/// ## What each piece is for
///
/// **Both sides need a private key.** An earlier draft of `docs/VAULT.md` said "ECDH, then HKDF,
/// then seal to the watch's public key" as though that were one primitive. ECDH needs a private
/// key on both sides; what that described was ECIES with half of it missing.
///
/// **The whole transcript is bound** into the HKDF info and the AEAD's additional data, so a
/// response carrying a substituted public key derives a different key and does not open. Gate E7
/// measured that rather than assuming it: swapping the phone's public key made the payload
/// unopenable, which is what makes the binding real rather than decorative.
///
/// **The nonce is what makes a replay detectable.** The watch refuses a response that does not
/// echo the nonce it just generated, so a captured older response cannot be handed back to it.
///
/// ## What this deliberately does not have, and what that costs
///
/// **There is no six digit comparison.** The design carried one so that WatchConnectivity's
/// routing would be defense in depth rather than the only defense. It is gone, and the honest
/// consequence is that **routing exclusivity is now load bearing**: this exchange is safe because
/// WatchConnectivity connects an iOS app to its own companion watch app and not to arbitrary
/// apps, which gate E5 measured for a same-team sibling and Apple does not document as a
/// guarantee. `docs/VAULT.md` and `SECURITY.md` say so in those words.
///
/// The judgement behind it: a rogue counterpart would have to ship inside OpenFactor's own
/// bundle, which is a malicious OpenFactor build and already out of scope, and a six digit
/// comparison on a wrist is a step people tap through rather than perform.
///
/// **The human gate is on the phone instead.** The vault key file is `.complete` protected, so
/// the phone must be unlocked and foregrounded to read it at all, and the app asks before it
/// answers. The key never moves because two apps happened to be open.
public enum WatchProvisioning {

    /// Format magic and version. A version 2 exchange changes these bytes rather than reusing
    /// them, so an old build refuses a new message instead of misreading it.
    static let magic = Data("OFW1".utf8)

    /// Bound into the derivation so a key derived here can never collide with one derived for
    /// another purpose from the same shared secret.
    static let label = Data("openfactor.vault.watch.v1".utf8)

    static let nonceCount = 16
    static let publicKeyCount = 65
    static let sealedCount = 60

    public static let requestCount = 4 + nonceCount + publicKeyCount
    public static let responseCount = requestCount + sealedCount

    /// What the phone tells a watch that asked, and the keys the two messages travel under.
    ///
    /// **Here rather than in either target, because both have to agree and only one of them
    /// can be wrong at a time.** The phone wrote these strings and the watch matched them with
    /// its own literals, in another module, with an unknown value falling through to "not set
    /// up". So a typo or a rename on one side would not fail to build and would not look
    /// broken: the watch would calmly tell somebody their watch was not set up when the real
    /// answer was that their phone had no vault, or that they had declined. A wrong answer that
    /// reads as a plausible one is the worst shape a bug can take on this screen.
    ///
    /// This is the same argument `SharedInbox.appGroup` makes about the app group identifier,
    /// and it is settled the same way: one declaration, both targets, and a test that pins the
    /// wire values so a rename cannot quietly change what goes over the air.
    public enum Answer: String, Sendable, CaseIterable {
        /// The phone is asking its owner now. The watch waits.
        case asking
        /// The app is not frontmost, so the key file is unreadable and nobody is looking at a
        /// screen to agree. The watch tells the wearer to open the app.
        case needsApp
        /// This phone has no vault of its own. Both devices replaced together, most likely.
        case noVault
        /// The person said no.
        case declined
        /// The phone is already asking about a different request and did not keep this one.
        ///
        /// **Added in round two of gate A4, after the watch-side fix alone proved insufficient.**
        /// The phone will not replace the request its alert is asking about, which is right. It
        /// used to answer a later one with `asking` anyway and then discard it, so the watch
        /// waited for a message that could never arrive. The first fix had the watch re-ask when
        /// an obsolete response arrived, which two reviewers independently showed was not enough:
        /// it does nothing when the phone declines instead of approving, and when a response is
        /// merely delayed it makes the watch abandon the very request the phone is asking about.
        ///
        /// Saying "busy" is what removes the guessing. The watch keeps its attempt and waits for
        /// the alert to be answered, rather than inferring anything about the phone's state.
        case busy
    }

    /// The dictionary keys the two messages travel under, shared for the same reason.
    public enum MessageKey {
        /// The watch's opening message, carrying its half of the exchange.
        public static let request = "request"
        /// The phone's second message, carrying the sealed key.
        public static let response = "response"
        /// An `Answer`, in either message.
        public static let status = "status"
        /// The nonce a refusal refuses, so a stale decline cannot end a live attempt. Absent
        /// from a build older than this, which the watch honours rather than ignoring.
        public static let nonce = "nonce"
    }

    public enum ExchangeError: Error, Equatable, Sendable {
        /// The system refused to produce randomness. Nothing proceeds on a predictable nonce.
        case noRandomness
        /// The message is not the length this version defines.
        case malformed
        /// The magic did not match. Another version, or not ours at all.
        case unsupportedVersion
        /// The bytes in the public key position are not a P-256 point.
        case invalidPublicKey
        /// The nonce is not the one this watch just sent. A replayed or misdelivered response.
        case notForThisRequest
        /// The payload did not open. A substituted transcript, or an altered message.
        case couldNotOpen
    }

    // MARK: - The watch's side

    /// The watch's half of the exchange, holding the ephemeral private key between the two
    /// messages.
    ///
    /// **Used once and discarded.** It exists only for as long as the exchange, which is why it
    /// is a value the caller holds rather than anything written down.
    public struct Attempt: Sendable {

        private let privateKey: P256.KeyAgreement.PrivateKey
        private let nonce: Data

        /// The bytes to send to the phone. 85 of them.
        public let request: Data

        /// **Throws rather than shipping a predictable nonce.** The result of
        /// `SecRandomCopyBytes` used to be discarded, and the buffer it writes into starts as
        /// sixteen zero bytes, so a refusal produced an all-zero nonce and claimed it was fresh.
        /// `VaultKeyStore.create` checks the same call in the same situation, so the project
        /// disagreed with itself; found by an independent review of this file.
        ///
        /// No exploit was demonstrated from the zero nonce alone, because a fresh ephemeral key
        /// changes both the shared secret and the transcript on every attempt. That is an
        /// argument for it being survivable, not for it being correct, and it is the shape of
        /// thing that becomes a break the moment something upstream reuses a key.
        public init() throws(ExchangeError) {
            let privateKey = P256.KeyAgreement.PrivateKey()
            var nonce = Data(count: WatchProvisioning.nonceCount)
            let status = nonce.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
            }
            guard status == errSecSuccess else { throw .noRandomness }
            self.init(privateKey: privateKey, nonce: nonce)
        }

        /// The deterministic seam, for test vectors only. Nothing in the app may call this: a
        /// reused keypair or nonce would make two provisionings indistinguishable.
        init(privateKey: P256.KeyAgreement.PrivateKey, nonce: Data) {
            self.privateKey = privateKey
            self.nonce = nonce

            var request = WatchProvisioning.magic
            request.append(nonce)
            request.append(privateKey.publicKey.x963Representation)
            self.request = request
        }

        /// Whether a bare nonce is this attempt's own.
        ///
        /// For the refusal message, which carries no sealed payload to authenticate and so can
        /// only be matched this way. **This is not authentication and does not pretend to be:**
        /// a decline releases nothing, and the worst a forged one can do is end an exchange the
        /// wearer can start again. The sealed response is bound by the transcript instead.
        public func answers(_ candidate: Data) -> Bool {
            guard candidate.count == nonce.count else { return false }

            // Constant time out of habit rather than need, since neither side is secret. Habit
            // is the point: the next thing compared here might be.
            var difference: UInt8 = 0
            for (a, b) in zip(candidate, nonce) { difference |= a ^ b }
            return difference == 0
        }

        /// The nonce this attempt sent, for the phone to echo in a refusal.
        public var sentNonce: Data { nonce }

        /// Opens the phone's reply and returns the vault key it carries.
        ///
        /// Every check that can fail is here rather than in the caller, so a watch cannot install
        /// a key from a message it did not fully verify.
        public func open(_ response: Data) throws(ExchangeError) -> SymmetricKey {
            guard response.count == WatchProvisioning.responseCount else { throw .malformed }

            var index = response.startIndex
            func take(_ count: Int) -> Data {
                defer { index += count }
                return response[index..<index + count]
            }

            guard take(4) == WatchProvisioning.magic else { throw .unsupportedVersion }

            // Before anything is derived. A response that is not answering this request is
            // rejected on that ground alone, which is what the nonce is for.
            guard take(WatchProvisioning.nonceCount) == nonce else { throw .notForThisRequest }

            let phonePublicKeyBytes = take(WatchProvisioning.publicKeyCount)
            let sealed = take(WatchProvisioning.sealedCount)

            let phonePublicKey: P256.KeyAgreement.PublicKey
            do {
                phonePublicKey = try P256.KeyAgreement.PublicKey(
                    x963Representation: phonePublicKeyBytes)
            } catch {
                throw .invalidPublicKey
            }

            let transcript = WatchProvisioning.transcript(
                nonce: nonce,
                watchPublicKey: privateKey.publicKey.x963Representation,
                phonePublicKey: phonePublicKeyBytes)

            let wrappingKey: SymmetricKey
            do {
                wrappingKey = try WatchProvisioning.wrappingKey(
                    privateKey: privateKey, peer: phonePublicKey, transcript: transcript)
            } catch {
                throw .couldNotOpen
            }

            do {
                let box = try AES.GCM.SealedBox(combined: sealed)
                let opened = try AES.GCM.open(
                    box, using: wrappingKey, authenticating: transcript)
                return SymmetricKey(data: opened)
            } catch {
                throw .couldNotOpen
            }
        }
    }

    // MARK: - The phone's side

    /// Seals the vault key for the watch that sent this request.
    ///
    /// **Call this only after the person has agreed.** Nothing here asks, because a type in the
    /// core cannot; the obligation is stated in `docs/VAULT.md` and met by the phone's screen.
    public static func respond(
        to request: Data, with vaultKey: SymmetricKey
    ) throws(ExchangeError) -> Data {
        try respond(to: request, with: vaultKey, phonePrivateKey: P256.KeyAgreement.PrivateKey())
    }

    /// A request that has been parsed and found well formed.
    ///
    /// **It exists so the phone can refuse rubbish before it loads a key or asks a human.** The
    /// phone used to hand raw bytes straight to its owner: it read the vault key, put an alert on
    /// screen, and only discovered the request was malformed after the tap, at which point it
    /// silently sent nothing and left the watch on a spinner. An independent review found it.
    /// Nothing here proves the sender is the paired watch, which no parse can do; it proves only
    /// that the bytes are a request this version understands.
    public struct ValidatedRequest: Sendable {
        let nonce: Data
        let watchPublicKeyBytes: Data
        let watchPublicKey: P256.KeyAgreement.PublicKey

        /// Echoed in a refusal so the watch can tell a decline of this request from a decline
        /// of one it has already abandoned.
        public var requestNonce: Data { nonce }

        /// When this request was parsed, on a clock that cannot be moved.
        ///
        /// **Not a `Date`.** Wall time can go backwards, and a negative elapsed value passes any
        /// "less than the window" test forever, which is precisely the hole the window exists to
        /// close. Round two of gate A4 found it in all three reviews.
        let validatedAt: ContinuousClock.Instant

        /// How long this request has been waiting for an answer, in seconds.
        ///
        /// Never negative under the default argument, which is the only way the app calls it: a
        /// clock that cannot go backwards cannot produce one. A test that hands it an earlier
        /// instant does get a negative, on purpose, because that is how the wall-clock failure is
        /// pinned. The first version of this sentence said "never negative" flatly and its own
        /// test contradicted it.
        /// `validatedAt` stays internal so the app cannot compare it against a `Date` of its
        /// own, which is the mistake this replaced. The only thing outside the package can ask
        /// for is an elapsed time that has already been measured correctly.
        public func age(now: ContinuousClock.Instant = .now) -> TimeInterval {
            let elapsed = now - validatedAt
            return TimeInterval(elapsed.components.seconds)
        }
    }

    /// Parses a request, or refuses it. Cheap, and touches no secret.
    public static func validate(_ request: Data) throws(ExchangeError) -> ValidatedRequest {
        guard request.count == requestCount else { throw .malformed }

        var index = request.startIndex
        func take(_ count: Int) -> Data {
            defer { index += count }
            return request[index..<index + count]
        }

        guard take(4) == magic else { throw .unsupportedVersion }
        let nonce = take(nonceCount)
        let watchPublicKeyBytes = take(publicKeyCount)

        let watchPublicKey: P256.KeyAgreement.PublicKey
        do {
            watchPublicKey = try P256.KeyAgreement.PublicKey(
                x963Representation: watchPublicKeyBytes)
        } catch {
            throw .invalidPublicKey
        }

        return ValidatedRequest(
            nonce: nonce, watchPublicKeyBytes: watchPublicKeyBytes,
            watchPublicKey: watchPublicKey, validatedAt: ContinuousClock.now)
    }

    /// The deterministic seam, for test vectors only.
    static func respond(
        to request: Data, with vaultKey: SymmetricKey,
        phonePrivateKey: P256.KeyAgreement.PrivateKey,
        sealNonce: AES.GCM.Nonce? = nil
    ) throws(ExchangeError) -> Data {
        try respond(
            to: try validate(request), with: vaultKey, phonePrivateKey: phonePrivateKey,
            sealNonce: sealNonce)
    }

    /// Seals for a request that has already been parsed and approved.
    public static func respond(
        to request: ValidatedRequest, with vaultKey: SymmetricKey
    ) throws(ExchangeError) -> Data {
        try respond(
            to: request, with: vaultKey, phonePrivateKey: P256.KeyAgreement.PrivateKey())
    }

    static func respond(
        to request: ValidatedRequest, with vaultKey: SymmetricKey,
        phonePrivateKey: P256.KeyAgreement.PrivateKey,
        sealNonce: AES.GCM.Nonce? = nil
    ) throws(ExchangeError) -> Data {
        let nonce = request.nonce
        let watchPublicKeyBytes = request.watchPublicKeyBytes
        let watchPublicKey = request.watchPublicKey

        let phonePublicKeyBytes = phonePrivateKey.publicKey.x963Representation
        let transcript = transcript(
            nonce: nonce,
            watchPublicKey: watchPublicKeyBytes,
            phonePublicKey: phonePublicKeyBytes)

        let wrappingKey: SymmetricKey
        do {
            wrappingKey = try Self.wrappingKey(
                privateKey: phonePrivateKey, peer: watchPublicKey, transcript: transcript)
        } catch {
            throw .couldNotOpen
        }

        let sealed: Data
        do {
            let keyBytes = vaultKey.withUnsafeBytes { Data($0) }
            let box = try AES.GCM.seal(
                keyBytes, using: wrappingKey, nonce: sealNonce, authenticating: transcript)
            guard let combined = box.combined else { throw ExchangeError.couldNotOpen }
            sealed = combined
        } catch {
            throw .couldNotOpen
        }

        var response = magic
        response.append(nonce)
        response.append(phonePublicKeyBytes)
        response.append(sealed)
        return response
    }

    // MARK: - Shared derivation

    /// Everything both sides agreed on, in one buffer, in the order it was sent.
    ///
    /// It goes into the HKDF info **and** the AEAD's additional data. Either alone would bind it;
    /// both is cheap and means a future change to one does not silently unbind the other.
    static func transcript(nonce: Data, watchPublicKey: Data, phonePublicKey: Data) -> Data {
        var transcript = magic
        transcript.append(nonce)
        transcript.append(watchPublicKey)
        transcript.append(phonePublicKey)
        return transcript
    }

    /// **Empty salt, deliberately.** HKDF's salt and info both bind context; the whole transcript
    /// is already in `info`, so a salt would add a second place to get the same job wrong.
    static func wrappingKey(
        privateKey: P256.KeyAgreement.PrivateKey,
        peer: P256.KeyAgreement.PublicKey,
        transcript: Data
    ) throws -> SymmetricKey {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: label + transcript,
            outputByteCount: 32)
    }
}
