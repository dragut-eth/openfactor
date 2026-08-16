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

    public enum ExchangeError: Error, Equatable, Sendable {
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

        public init() {
            let privateKey = P256.KeyAgreement.PrivateKey()
            var nonce = Data(count: WatchProvisioning.nonceCount)
            nonce.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
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

    /// The deterministic seam, for test vectors only.
    static func respond(
        to request: Data, with vaultKey: SymmetricKey,
        phonePrivateKey: P256.KeyAgreement.PrivateKey,
        sealNonce: AES.GCM.Nonce? = nil
    ) throws(ExchangeError) -> Data {
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
            watchPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: watchPublicKeyBytes)
        } catch {
            throw .invalidPublicKey
        }

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
