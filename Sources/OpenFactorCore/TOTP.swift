import Foundation

/// Time based one time passwords, per
/// [RFC 6238](https://datatracker.ietf.org/doc/html/rfc6238).
///
/// TOTP is HOTP with the counter derived from the clock instead of from a stored tally,
/// so all of the cryptography lives in ``HOTP`` and everything here is arithmetic on
/// time.
///
/// **The time is always passed in, never read.** Nothing in this file calls `Date()`.
/// That makes every one of the published test vectors reproducible, keeps the whole type
/// free of hidden state, and leaves the choice of clock to the caller, which is what
/// makes a correction for a skewed device clock possible later without touching code
/// generation.
public enum TOTP {

    /// Generates the code valid at a given moment.
    ///
    /// - Parameters:
    ///   - secret: the shared key, already decoded from Base32.
    ///   - date: the moment to generate for. The caller supplies it, see the note above.
    ///   - configuration: algorithm, digit count, and period.
    public static func code(
        secret: Data,
        at date: Date,
        configuration: TOTPConfiguration = .standard
    ) -> String {
        HOTP.code(
            secret: secret,
            counter: counter(at: date, period: configuration.period),
            digits: configuration.digits,
            algorithm: configuration.algorithm
        )
    }

    /// The counter for a moment, which RFC 6238 section 4.2 calls T.
    ///
    /// It is the number of whole periods since the Unix epoch. Two devices agree on a
    /// code exactly when they agree on this number, which is why a phone with a badly
    /// wrong clock produces codes that are rejected everywhere.
    public static func counter(at date: Date, period: Int) -> UInt64 {
        // A clock set before 1970 is broken, and no code generated from it will work.
        // Clamping keeps the arithmetic defined rather than trapping on the conversion.
        let seconds = date.timeIntervalSince1970
        guard seconds >= 0 else { return 0 }

        return UInt64(seconds.rounded(.down)) / UInt64(period)
    }

    /// How long the current code stays valid, in seconds.
    ///
    /// Fractional, so the countdown ring can move smoothly, and so the interface layer
    /// decides how to round rather than having a rounding baked in here.
    ///
    /// The value is greater than zero and at most `period`. At the instant a code
    /// changes, the full period is returned rather than zero, because the freshly valid
    /// code does have a whole period left.
    public static func timeRemaining(at date: Date, period: Int) -> TimeInterval {
        let seconds = date.timeIntervalSince1970
        guard seconds >= 0 else { return TimeInterval(period) }

        let elapsed = seconds.truncatingRemainder(dividingBy: TimeInterval(period))
        return TimeInterval(period) - elapsed
    }

    /// When the current code expires.
    ///
    /// Convenient for scheduling a refresh, and derived from ``timeRemaining(at:period:)``
    /// so the two can never disagree.
    public static func expiry(at date: Date, period: Int) -> Date {
        date.addingTimeInterval(timeRemaining(at: date, period: period))
    }
}
