import CryptoKit
import Foundation
import Testing

@testable import OpenFactorCore

/// The published test vector, run against this implementation.
///
/// `docs/BACKUP_FORMAT.md` is normative and says so: where the page and the code disagree,
/// the code is the defect. This suite is how that claim is kept true rather than asserted.
/// Every number here is copied from the page, not produced by this code, so a change that
/// breaks the format fails here before it reaches anybody's archive.
///
/// The page's own history is why this is not a formality. Three independent reviews each
/// found a defect in this exact section, and each repair introduced the next one: a vector
/// built by feeding the KDF the hyphenated passphrase while the text said strip it, then a
/// fix that made the `passphrase` field authoritative and turned one editable byte into a
/// lockout, then a fix for *that* which rested on AES-GCM committing to its key, which it
/// does not.
@Suite("Backup format test vector")
struct BackupVectorTests {

    // MARK: - The published values

    static let displayed = "YZTR-THFW-WT6E-OXIV-73XD-QCDM"
    static let canonical = "YZTRTHFWWT6EOXIV73XDQCDM"

    static let salt = Data((0..<32).map(UInt8.init))
    static let nonce = Data((0xA0...0xAB).map(UInt8.init))
    static let iterations = 600_000

    static let generatedKeyHex =
        "7feefa76093f66f306e972be1d33e7fbdb38a84f193b3ab938c4ece73dd60959"

    static let plaintext = """
        {"accounts":[{"algorithm":"SHA1","digits":6,"issuer":"GitHub","name":"octocat",\
        "period":30,"secret":"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ","type":"totp"}]}
        """

    static let generatedCiphertext = """
        LQbc+Ku8Xw1jJEsA9V+waNf0luWbZStsdzfebd88iuTZaTr4FXtT4sEEMYt5ZLebsi6do6nGL5suyhvS\
        4vjFcU3/TV41rvHc2tcCo/eh1htRhs5S4czcbinvrq8GQeudGE8GWWMC4ixMOhpO83rYH3hFZiQOQz6t\
        0ripJP/SeRSFRC3ae/AEh9OOsyiOEXK06+7wsk4KbQ==
        """
    static let generatedTag = "9rCMg60+9TYAwqaTdsgr6A=="

    static let customPassphrase = "correct horse battery staple"
    static let customKeyHex =
        "613a4c3411394e24fffe6c51994307724572e574bcd98ea8cf457c64899bfbfe"
    static let customCiphertext = """
        jxXW2I3FDYM2CqyCTNDj+b3Zuav2PAhE3rf17Q/9cRSx+jrk3SiK3h0ZOtTAi8cTT+EScWhxe58X6vLU\
        7CvcKd5Pv/JeJguw0+X7U+/fkrcm289T3U/bEZ1xy2sV6WUoUW/hnNNnBuEXcwP8ALK/NZo15TyalQMC\
        o7AvjCIQbUP7rbgakKY7PSU8qMtrUHcxa605jtifCA==
        """
    static let customTag = "9OArOIi1DKg5MhDvaxBUpw=="

    // MARK: - Helpers

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func key(from password: Data) throws -> Data {
        try #require(
            PBKDF2.deriveKey(
                password: password, salt: Self.salt, iterations: Self.iterations
            )
        )
    }

    private func base64(_ text: String) throws -> Data {
        try #require(BackupBase64.decode(text))
    }

    // MARK: - The keys

    @Test("The generated passphrase reaches the published key")
    func generatedKey() throws {
        let derived = try key(from: BackupPassphrase.canonical(Self.displayed))
        #expect(hex(derived) == Self.generatedKeyHex)
    }

    @Test("The custom passphrase reaches the published key, uncanonicalised")
    func customKey() throws {
        let derived = try key(from: BackupPassphrase.verbatim(Self.customPassphrase))
        #expect(hex(derived) == Self.customKeyHex)
    }

    /// The one the page calls out as mattering most, because an earlier revision published a
    /// vector with exactly this mistake baked into it and every implementation checking
    /// itself against that vector inherited the bug.
    @Test("Feeding the hyphenated passphrase verbatim does not reach the key")
    func hyphensMustNotReachTheKey() throws {
        let derived = try key(from: Data(Self.displayed.utf8))
        #expect(hex(derived) != Self.generatedKeyHex)
    }

    /// Each of these is a way a real person hands the passphrase back. A reader that opens
    /// the archive from the first line and refuses any of the rest has implemented a
    /// different format.
    @Test(
        "Every way a person returns the passphrase reaches the same key",
        arguments: [
            "YZTR-THFW-WT6E-OXIV-73XD-QCDM",
            "yztr-thfw-wt6e-oxiv-73xd-qcdm",
            "YZTR\u{2013}THFW\u{2013}WT6E\u{2013}OXIV\u{2013}73XD\u{2013}QCDM",
            "\u{FEFF}YZTR-THFW-WT6E-OXIV-73XD-QCDM\n",
            "YZTR-THFW-WT6E-OXIV-73XD-QCD\u{200B}M",
            "YZTR THFW WT6E OXIV 73XD QCDM",
            "YZTRTHFWWT6EOXIV73XDQCDM",
        ]
    )
    func everyInputReachesTheSameKey(input: String) throws {
        #expect(String(decoding: BackupPassphrase.canonical(input), as: UTF8.self) == Self.canonical)

        let derived = try key(from: BackupPassphrase.canonical(input))
        #expect(hex(derived) == Self.generatedKeyHex)
    }

    // MARK: - The ciphertexts

    @Test("The published plaintext is the length the page states")
    func plaintextLength() {
        #expect(Data(Self.plaintext.utf8).count == 151)
    }

    @Test("Sealing the published plaintext reproduces the published ciphertext and tag")
    func sealingReproducesTheVector() throws {
        let derived = try key(from: BackupPassphrase.canonical(Self.displayed))

        let sealed = try AES.GCM.seal(
            Data(Self.plaintext.utf8),
            using: SymmetricKey(data: derived),
            nonce: try AES.GCM.Nonce(data: Self.nonce),
            authenticating: Data(BackupArchive.format.utf8)
        )

        #expect(sealed.ciphertext == (try base64(Self.generatedCiphertext)))
        #expect(sealed.tag == (try base64(Self.generatedTag)))
    }

    @Test("The published ciphertext opens to the published plaintext")
    func openingReproducesThePlaintext() throws {
        let derived = try key(from: BackupPassphrase.canonical(Self.displayed))

        let opened = try AES.GCM.open(
            try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: Self.nonce),
                ciphertext: try base64(Self.generatedCiphertext),
                tag: try base64(Self.generatedTag)
            ),
            using: SymmetricKey(data: derived),
            authenticating: Data(BackupArchive.format.utf8)
        )

        #expect(String(decoding: opened, as: UTF8.self) == Self.plaintext)
    }

    @Test("The custom vector seals to its published bytes")
    func customVectorSeals() throws {
        let derived = try key(from: BackupPassphrase.verbatim(Self.customPassphrase))

        let sealed = try AES.GCM.seal(
            Data(Self.plaintext.utf8),
            using: SymmetricKey(data: derived),
            nonce: try AES.GCM.Nonce(data: Self.nonce),
            authenticating: Data(BackupArchive.format.utf8)
        )

        #expect(sealed.ciphertext == (try base64(Self.customCiphertext)))
        #expect(sealed.tag == (try base64(Self.customTag)))
    }

    // MARK: - What must fail

    /// A reader that only proves it can open things has proved half of what matters.
    @Test("The generated ciphertext refuses the custom key, and the reverse")
    func keysDoNotCross() throws {
        let generatedKey = try key(from: BackupPassphrase.canonical(Self.displayed))
        let customKey = try key(from: BackupPassphrase.verbatim(Self.customPassphrase))

        #expect(
            throws: (any Error).self,
            performing: {
                try AES.GCM.open(
                    try AES.GCM.SealedBox(
                        nonce: try AES.GCM.Nonce(data: Self.nonce),
                        ciphertext: try self.base64(Self.generatedCiphertext),
                        tag: try self.base64(Self.generatedTag)
                    ),
                    using: SymmetricKey(data: customKey),
                    authenticating: Data(BackupArchive.format.utf8)
                )
            })

        #expect(
            throws: (any Error).self,
            performing: {
                try AES.GCM.open(
                    try AES.GCM.SealedBox(
                        nonce: try AES.GCM.Nonce(data: Self.nonce),
                        ciphertext: try self.base64(Self.customCiphertext),
                        tag: try self.base64(Self.customTag)
                    ),
                    using: SymmetricKey(data: generatedKey),
                    authenticating: Data(BackupArchive.format.utf8)
                )
            })
    }

    @Test("A different additional authenticated data fails", arguments: ["", "openfactor.backup.v2"])
    func aadIsBinding(aad: String) throws {
        let derived = try key(from: BackupPassphrase.canonical(Self.displayed))

        #expect(
            throws: (any Error).self,
            performing: {
                try AES.GCM.open(
                    try AES.GCM.SealedBox(
                        nonce: try AES.GCM.Nonce(data: Self.nonce),
                        ciphertext: try self.base64(Self.generatedCiphertext),
                        tag: try self.base64(Self.generatedTag)
                    ),
                    using: SymmetricKey(data: derived),
                    authenticating: Data(aad.utf8)
                )
            })
    }

    @Test("Any single altered byte fails, in the ciphertext or the tag")
    func alterationsFail() throws {
        let derived = try key(from: BackupPassphrase.canonical(Self.displayed))
        let ciphertext = try base64(Self.generatedCiphertext)
        let tag = try base64(Self.generatedTag)

        func open(ciphertext: Data, tag: Data) throws -> Data {
            try AES.GCM.open(
                try AES.GCM.SealedBox(
                    nonce: try AES.GCM.Nonce(data: Self.nonce),
                    ciphertext: ciphertext,
                    tag: tag
                ),
                using: SymmetricKey(data: derived),
                authenticating: Data(BackupArchive.format.utf8)
            )
        }

        // Every byte, rather than a sample. The whole file is the attacker's to edit, and a
        // spot check would leave the untested positions as the ones to try.
        for index in ciphertext.indices {
            var altered = ciphertext
            altered[index] ^= 0x01
            #expect(throws: (any Error).self) { try open(ciphertext: altered, tag: tag) }
        }

        for index in tag.indices {
            var altered = tag
            altered[index] ^= 0x01
            #expect(throws: (any Error).self) { try open(ciphertext: ciphertext, tag: altered) }
        }
    }
}
