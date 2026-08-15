import Foundation
import Security

/// Turning what a person typed into the exact bytes the key derivation receives.
///
/// This is the smallest file in the backup path and the one most likely to lock somebody
/// out of their own secrets, because every mistake here is silent: a wrong rule does not
/// throw, it derives a different key and reports a wrong passphrase forever.
///
/// The rules are `docs/BACKUP_FORMAT.md`, which is normative. Where this file and that page
/// disagree, this file is the defect.
public enum BackupPassphrase {

    /// Which rule produced the bytes a writer used.
    ///
    /// Stored in the archive as a **hint that orders attempts, never a gate**. An earlier
    /// revision of the format made it authoritative, which turned one byte of
    /// unauthenticated cleartext into a way to destroy somebody's only copy: flip
    /// `generated` to `custom` in any text editor and a conforming reader feeds the KDF
    /// different bytes than the writer did, permanently.
    public enum Mode: String, Sendable, Equatable {
        case generated
        case custom
    }

    // MARK: - The two forms

    /// The canonical form, used for generated passphrases.
    ///
    /// ASCII case mapping and then the Base32 alphabet, nothing else kept.
    ///
    /// **Not `uppercased()`.** Swift's is locale independent but still performs full Unicode
    /// case mapping, which differs from ASCII mapping at seventeen code points. The one that
    /// bites here is `ß`, which maps to `SS`: two characters that *are* in the alphabet, so
    /// the filter would keep them and the derived key would depend on which uppercase
    /// function an implementation happened to call.
    ///
    /// The filter afterwards is deliberately blunt. It removes hyphens, every competing
    /// definition of whitespace, the en dashes iOS smart punctuation substitutes for typed
    /// hyphens, byte order marks, and zero width spaces picked up from a web page. A
    /// correctly generated passphrase is nothing but alphabet characters, so discarding the
    /// rest cannot change a clean input and rescues every mangled one.
    public static func canonical(_ input: String) -> Data {
        var bytes = Data()
        bytes.reserveCapacity(input.utf8.count)

        for scalar in input.unicodeScalars {
            var value = scalar.value
            if value >= 0x61 && value <= 0x7A { value -= 0x20 }

            let isLetter = value >= 0x41 && value <= 0x5A
            let isDigit = value >= 0x32 && value <= 0x37

            if isLetter || isDigit { bytes.append(UInt8(value)) }
        }

        return bytes
    }

    /// The verbatim form, used for custom passphrases: the UTF-8 bytes as given.
    ///
    /// With exactly two removals, and no others. A custom passphrase saved to a file and
    /// read back acquires a leading byte order mark or a trailing newline, and the verbatim
    /// rule cannot rescue what the canonical filter would have stripped. Neither can be a
    /// deliberate part of a passphrase in a way any editor would preserve, and the
    /// alternative is an everyday, ASCII only, permanent lockout.
    ///
    /// **Scalars rather than `Character`s**, and the reason is a trap this got caught in.
    /// Swift treats `\r\n` as a **single** `Character`, so comparing the last character
    /// against `"\r"` and against `"\n"` is false for both and a Windows line ending
    /// survived. A passphrase saved to a file on one platform and read back would then have
    /// derived a key nobody could reproduce: the everyday, ASCII only, permanent lockout the
    /// format document names, arrived at through a grapheme cluster.
    public static func verbatim(_ input: String) -> Data {
        var scalars = Array(input.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        while let last = scalars.last, last == "\r" || last == "\n" { scalars.removeLast() }
        return Data(String(String.UnicodeScalarView(scalars)).utf8)
    }

    // MARK: - What a reader tries

    /// Every form a reader derives a key from, in the order the hint suggests.
    ///
    /// At most four, and only a wrong passphrase reaches the fourth. Identical forms are
    /// collapsed, which is the usual case: for an already canonical input the canonical and
    /// verbatim rules produce the same bytes and there is nothing to gain from deriving the
    /// same key twice at 600,000 iterations.
    ///
    /// Two readers following this open exactly the same set of archives, whatever the hint
    /// says and whether or not it is present. That is the property the whole ordering exists
    /// to preserve, and it is why an absent or misspelled hint changes performance and never
    /// outcome.
    public static func attempts(for input: String, hint: Mode?) -> [Data] {
        let plain = verbatim(input)
        let composed = Data(String(decoding: plain, as: UTF8.self).precomposedStringWithCanonicalMapping.utf8)
        let decomposed = Data(String(decoding: plain, as: UTF8.self).decomposedStringWithCanonicalMapping.utf8)

        let ordered: [Data] =
            hint == .custom
            ? [plain, canonical(input), composed, decomposed]
            : [canonical(input), plain, composed, decomposed]

        var seen: [Data] = []
        for candidate in ordered where !candidate.isEmpty && !seen.contains(candidate) {
            seen.append(candidate)
        }
        return seen
    }

    // MARK: - Generating one

    /// How many characters a generated passphrase has, before the display hyphens.
    public static let generatedLength = 24

    /// A fresh passphrase, 120 bits from the system CSPRNG, in the Base32 alphabet.
    ///
    /// Base32 because that alphabet exists to be transcribed by hand: it has no `0`, `1`,
    /// `8` or `9`, so nothing is confusable with `O`, `I`, `B` or `g`. Fifteen bytes encode
    /// to exactly twenty four characters with no padding and no leftover bits, which is why
    /// the size is 15 and not a rounder looking number.
    ///
    /// - Returns: `nil` if the system CSPRNG fails, which must be surfaced rather than
    ///   worked around. There is no acceptable fallback source of randomness for this.
    public static func generate() -> String? {
        var bytes = Data(repeating: 0, count: 15)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { return nil }

        return Base32.encode(bytes, padded: false)
    }

    /// The passphrase as it is shown to a person, in groups of four.
    ///
    /// The hyphens are display only. They are not part of the passphrase and the canonical
    /// rule removes them before the key is derived, which is exactly what the published test
    /// vector checks: it starts from this form, so an implementation that forgets to strip
    /// them cannot reach the published key.
    public static func grouped(_ passphrase: String) -> String {
        groups(passphrase).joined(separator: "-")
    }

    /// The same groups, unjoined, for a screen that lays them out rather than punctuating
    /// them. One splitter for both, so a grid and a string can never disagree about where a
    /// group ends, which is the sort of difference somebody only discovers while typing a
    /// passphrase back into an archive that will not open.
    public static func groups(_ passphrase: String) -> [String] {
        stride(from: 0, to: passphrase.count, by: 4)
            .map { offset -> String in
                let start = passphrase.index(passphrase.startIndex, offsetBy: offset)
                let end = passphrase.index(start, offsetBy: 4, limitedBy: passphrase.endIndex)
                return String(passphrase[start..<(end ?? passphrase.endIndex)])
            }
    }
}
