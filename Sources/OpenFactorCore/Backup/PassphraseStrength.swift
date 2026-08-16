import Foundation

/// Whether a passphrase somebody chose themselves is strong enough to protect every secret
/// they own, forever.
///
/// `docs/BACKUP_FORMAT.md` requires a writer to refuse a custom passphrase weaker than 2^40
/// guesses under an offline strength estimator, **or to not offer the custom path at all**.
/// This is that estimator, and the honest description of it comes first:
///
/// **It is a floor, not a guarantee.** It is a few hundred lines of pattern matching against
/// a short list, not zxcvbn and not a cracking rig. It will not recognise your dog's name,
/// your street, or a phrase from a song. What it does is refuse the passwords that are
/// finished in seconds, which is the failure this project can actually prevent without
/// taking a dependency on a wordlist nobody would audit.
///
/// The reason the bar is 2^40 rather than something more comfortable is in the format
/// document, stated plainly there after an earlier revision denied it: PBKDF2-HMAC-SHA256 at
/// 600,000 iterations runs at thousands of guesses per second on one consumer GPU, which
/// finishes a large wordlist in about an hour. The user who overrides the generator is
/// precisely the user paying for PBKDF2's universal availability.
///
/// **The real defence is that the generator is the default and stays the default.** This is
/// the guard rail on the path away from it.
public enum PassphraseStrength {

    /// Unicode scalar values, which is what the format counts. Alongside the strength test,
    /// never instead of it: `password1234` is twelve characters and finished in under a
    /// second.
    public static let minimumScalars = 12

    /// 2^40 guesses.
    public static let minimumBits = 40.0

    public struct Assessment: Sendable, Equatable {

        /// The estimate, in bits. Rounded down at the edges rather than up, on the principle
        /// that an estimator should be pessimistic about the thing it is guarding.
        public let bits: Double

        public let isAcceptable: Bool

        /// What to tell the person, when it is not acceptable. Written to be actionable
        /// rather than scolding: it names the pattern that made it cheap.
        public let advice: String?
    }

    public static func assess(_ passphrase: String) -> Assessment {
        let scalars = Array(passphrase.unicodeScalars)

        guard scalars.count >= minimumScalars else {
            return Assessment(
                bits: 0,
                isAcceptable: false,
                advice: """
                    A passphrase you choose yourself needs at least \(minimumScalars) \
                    characters. Length is what makes guessing expensive.
                    """
            )
        }

        // Two readings, because a common password wears its disguise in both directions.
        // `Passw0rd!2024` only looks like `password` once the substitutions are undone, and
        // `password1234` only looks like it once they are *not*: undoing them turns the
        // trailing digits into letters and hides the word that was there all along. Testing
        // both is cheaper than being clever about which applies.
        let letters = lettersOnly(passphrase, undoingSubstitutions: false)
        let substituted = lettersOnly(passphrase, undoingSubstitutions: true)

        // A third reading, collapsed. `trustno1trustno1` is a blocklisted word written
        // twice, and the prefix rule below does not reach that far: the doubled copy is
        // eight characters longer than the word, so it read as something original. Every
        // repeated unit collapses to one before the list is consulted.
        let readings = [letters, substituted].flatMap { [$0, collapsingRepeatedUnits($0)] }

        if let word = commonWords.first(where: { word in
            readings.contains { reading in
                reading == word
                    || (reading.hasPrefix(word) && reading.count <= word.count + 3)
            }
        }) {
            return Assessment(
                bits: 8,
                isAcceptable: false,
                advice: """
                    This is built on "\(word)", which is one of the first things any guessing \
                    program tries. Adding numbers to the end does not change that.
                    """
            )
        }

        // Walks across a keyboard are not sequences in code point order, so the run
        // collapsing below cannot see them: `1qaz2wsx3edc` steps down a column of the
        // keyboard and reads as twelve independent characters. They are matched as
        // substrings rather than as whole passphrases, since a walk padded with two
        // characters is still a walk, and only when the walk is most of what is there.
        let flattened = lowercasedASCII(passphrase)
        if let walk = keyboardWalks.first(where: {
            flattened.contains($0) && $0.count * 2 >= flattened.count
        }) {
            return Assessment(
                bits: 10,
                isAcceptable: false,
                advice: """
                    This traces a path across the keyboard ("\(walk)"), which guessing \
                    programs walk before they try anything else.
                    """
            )
        }

        // A repeated unit is priced as the unit plus the choice of how many times, not as
        // its full length. Collapsing it only for the blocklist was not enough: `asdfasdfasdf`
        // is not on any list and was reading as twelve independent characters.
        let (unit, repetitions) = repeatedUnit(scalars)
        let bits = estimateBits(unit) + (repetitions > 1 ? log2(Double(repetitions)) : 0)

        guard bits >= minimumBits else {
            return Assessment(
                bits: bits,
                isAcceptable: false,
                advice: """
                    This is too easy to guess offline. Four or five unrelated words, or \
                    letting OpenFactor generate one, both work.
                    """
            )
        }

        return Assessment(bits: bits, isAcceptable: true, advice: nil)
    }

    // MARK: - The estimate

    /// Search space of the character classes present, over a length with the cheap structure
    /// taken out of it.
    ///
    /// Repeats and runs are collapsed because `aaaaaaaaaaaa` and `abcdefghijkl` are both
    /// twelve characters and neither costs twelve characters to guess. This is the crudest
    /// possible version of what a real estimator does, and it is deliberately crude rather
    /// than subtly wrong: every rule here is one somebody can read and check.
    private static func estimateBits(_ scalars: [Unicode.Scalar]) -> Double {
        var pool = 0
        if scalars.contains(where: { $0.value >= 0x61 && $0.value <= 0x7A }) { pool += 26 }
        if scalars.contains(where: { $0.value >= 0x41 && $0.value <= 0x5A }) { pool += 26 }
        if scalars.contains(where: { $0.value >= 0x30 && $0.value <= 0x39 }) { pool += 10 }
        if scalars.contains(where: { $0.value < 0x80 && !isAlphanumeric($0) }) { pool += 33 }
        // Anything outside ASCII is counted conservatively. A single accented letter does
        // not buy the whole of Unicode.
        if scalars.contains(where: { $0.value >= 0x80 }) { pool += 100 }

        guard pool > 1 else { return 0 }

        var effective = 0.0
        var index = 0

        while index < scalars.count {
            var run = 1

            // A repeat of the same scalar, or a run stepping by one in either direction.
            let step = index + 1 < scalars.count
                ? Int(scalars[index + 1].value) - Int(scalars[index].value)
                : Int.max

            if step == 0 || step == 1 || step == -1 {
                while index + run < scalars.count,
                    Int(scalars[index + run].value) - Int(scalars[index + run - 1].value) == step {
                    run += 1
                }
            }

            // The first character of a run costs what a character costs. The rest of it is
            // one more guess between them, not one more each.
            effective += 1 + (run > 1 ? log2(Double(run)) / log2(Double(pool)) : 0)
            index += run
        }

        return effective * log2(Double(pool))
    }

    /// The same collapse over scalars, with how many times the unit repeats.
    private static func repeatedUnit(
        _ scalars: [Unicode.Scalar]
    ) -> (unit: [Unicode.Scalar], repetitions: Int) {
        guard scalars.count > 1 else { return (scalars, 1) }

        for length in 1...(scalars.count / 2) where scalars.count % length == 0 {
            let unit = Array(scalars[0..<length])
            if stride(from: 0, to: scalars.count, by: length)
                .allSatisfy({ Array(scalars[$0..<($0 + length)]) == unit }) {
                return (unit, scalars.count / length)
            }
        }

        return (scalars, 1)
    }

    /// The shortest unit this text is a whole number of repetitions of, or the text itself.
    ///
    /// `asdfasdfasdf` costs what `asdf` costs plus the choice of how many times, not what
    /// twelve independent characters cost.
    private static func collapsingRepeatedUnits(_ text: String) -> String {
        let characters = Array(text)
        guard characters.count > 1 else { return text }

        for length in 1...(characters.count / 2) where characters.count % length == 0 {
            let unit = characters[0..<length]
            if stride(from: 0, to: characters.count, by: length)
                .allSatisfy({ Array(characters[$0..<($0 + length)]) == Array(unit) }) {
                return String(unit)
            }
        }

        return text
    }

    private static func lowercasedASCII(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (scalar.value >= 0x41 && scalar.value <= 0x5A)
                ? Unicode.Scalar(scalar.value + 0x20)! : scalar
        }))
    }

    /// Paths across a QWERTY keyboard, in both directions, which are what a person reaches
    /// for when told to use letters, digits and symbols. Short on purpose, like the word
    /// list: these are the ones that appear at the top of every breach corpus.
    private static let keyboardWalks: [String] = [
        "1qaz2wsx", "2wsx3edc", "1qaz2wsx3edc", "qazwsx", "qazwsxedc", "zaqxsw", "zaq12wsx",
        "qwerty", "qwertyui", "qwertyuiop", "asdfgh", "asdfghjkl", "zxcvbn", "zxcvbnm",
        "qwertasdfg", "qweasdzxc", "1q2w3e4r", "1q2w3e4r5t", "123qweasd", "poiuyt",
        "lkjhgf", "mnbvcxz", "azerty", "azertyuiop", "qsdfgh", "wxcvbn",
    ]

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (value >= 0x30 && value <= 0x39)
            || (value >= 0x41 && value <= 0x5A)
            || (value >= 0x61 && value <= 0x7A)
    }

    /// The ASCII letters of a passphrase, lower cased, with digits and symbols either
    /// translated back into the letters they stand in for or dropped.
    private static func lettersOnly(
        _ passphrase: String,
        undoingSubstitutions: Bool
    ) -> String {
        var result = ""

        for scalar in passphrase.unicodeScalars {
            let lowered = (scalar.value >= 0x41 && scalar.value <= 0x5A)
                ? Unicode.Scalar(scalar.value + 0x20)! : scalar

            if undoingSubstitutions {
                switch lowered {
                case "@", "4": result.append("a"); continue
                case "0": result.append("o"); continue
                case "1", "!", "|": result.append("i"); continue
                case "3": result.append("e"); continue
                case "5", "$": result.append("s"); continue
                case "7": result.append("t"); continue
                default: break
                }
            }

            if lowered.value >= 0x61 && lowered.value <= 0x7A {
                result.unicodeScalars.append(lowered)
            }
        }

        return result
    }

    /// Short on purpose. A wordlist long enough to be thorough is a wordlist nobody reads,
    /// and this project's rule is that its source is auditable by a person. These are the
    /// patterns that show up at the top of every breach corpus, plus the ones this app in
    /// particular invites.
    private static let commonWords: [String] = [
        "password", "passwort", "motdepasse", "letmein", "welcome", "monkey", "dragon",
        "qwerty", "qwertyuiop", "azerty", "asdfgh", "zxcvbn", "iloveyou", "princess",
        "sunshine", "football", "baseball", "superman", "batman", "trustno", "master",
        "shadow", "michael", "jennifer", "jordan", "harley", "ranger", "hunter",
        "buster", "soccer", "hockey", "killer", "george", "andrew", "charlie", "thomas",
        "robert", "daniel", "matthew", "joshua", "admin", "administrator", "root",
        "changeme", "secret", "abcdef", "abcabc", "computer", "internet", "samsung",
        "google", "apple", "amazon", "facebook", "twitter", "whatever", "nothing",
        "openfactor", "authenticator", "twofactor", "backup", "recovery", "keychain",
        "correcthorsebatterystaple",
    ]
}
