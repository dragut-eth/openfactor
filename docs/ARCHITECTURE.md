# Architecture

How OpenFactor is put together, and why. Written for someone auditing the project who has
never seen it before.

This document grows with the code. Sections describing something not yet built are marked
*planned*, so that nothing here is quietly untrue.

## The shape of it

```
OpenFactorCore  (Swift package, no UI, no dependencies)
      ^
      |  used by
      |
   App (iOS)        Watch (watchOS)
```

The split is the most important structural decision in the project. Everything security
sensitive is in `OpenFactorCore`: encoding, code generation, URI parsing, and secret
storage. It contains no SwiftUI, no view models, and no platform UI code, so an auditor
can read the part that matters, verify it against the RFCs, and stop, without wading
through interface code. The app targets are deliberately thin.

## OpenFactorCore

*`Base32`, `HOTP`, and `TOTP` exist as of PR 2. The rest arrives in PR 3 and PR 4.*

| Component | Responsibility |
| --- | --- |
| `Base32` | RFC 4648 decoding and encoding. Every secret arrives as Base32 text |
| `HOTP` | RFC 4226 counter based codes. SHA1, SHA256, SHA512 via CryptoKit |
| `TOTP` | RFC 6238 time based codes on top of `HOTP` |
| `OTPAuthURI` | Parsing and serializing `otpauth://` URIs |
| `SecretStore` | Reading and writing secrets, backed by the Keychain |

### Design decisions

**Time is passed in, never read.** Nothing in `TOTP` calls `Date()`. Every function takes
the moment to generate for as a parameter.

The roadmap originally called for injecting a clock protocol. A plain `Date` parameter
turned out to be strictly better: it is the same testability with no protocol, no
conformance, and no stored state, and it still leaves room for a correction for a skewed
device clock, which becomes an adjustment at the call site rather than a second
implementation of a clock. The interface layer owns the timer and therefore owns the
question of what time it is.

**The secret is not part of the configuration.** `TOTPConfiguration` holds the algorithm,
digit count, and period, all of which are stored and copied freely. The secret is a
parameter to the one function that needs it, read from the Keychain at the moment a code
is generated. No long lived object holds secret material, so no object can leak one by
being logged.

**A code is text, not a number.** `07081804` is a valid code, and an integer would lose
the leading zero. The generators return `String` throughout for that reason.

**Parsing is total.** `OTPAuthURI` either returns a fully valid account or a typed error.
It never returns a partially populated account, because a silently dropped algorithm
parameter produces codes that look right and never work.

**Secrets and metadata are stored separately.** Issuer, label, color, and sort index are
not secret and live apart from the secret itself, so drawing the account list never loads
secret material into memory.

**No hand rolled cryptography.** HMAC and the hash functions come from CryptoKit. The only
cryptographic code written here is the RFC 4226 dynamic truncation, which is arithmetic on
the HMAC output and is covered by the published vectors.

**Decoding is lenient about formatting and strict about content.** `Base32` accepts
lowercase, spaces, and hyphens, because that is how services actually print secrets and
how they land on the pasteboard. It rejects everything else with a specific error rather
than skipping the character, since skipping would decode a different secret than the user
believes they entered. The one deliberate exception is the handful of leftover bits at the
end of a secret whose length is not a multiple of 8 characters, which are discarded rather
than rejected. RFC 4648 section 3.5 permits rejecting them, but a 26 character secret
carries two such bits and real services set them, so rejecting would refuse secrets that
work everywhere else. The reasoning is repeated at the code.

## App targets

*Planned, arriving in PR 5 onward.* SwiftUI, with view models over `SecretStore` and the
generators. Screens and behavior are specified in [UI_SPEC.md](UI_SPEC.md).

**One timer for the whole list,** never one per row. Every visible code recomputes on a
single shared tick.

## Storage and sync

*Planned, arriving in PR 4 and PR 13.*

Secrets are Keychain items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` by default.
Turning on sync flips them to synchronizable, which puts them in iCloud Keychain, end to
end encrypted with keys Apple does not hold.

The watch reads the same synchronizable Keychain items rather than receiving secrets over
WatchConnectivity. A bespoke transfer channel is another place for secret material to
leak, and iCloud Keychain already solves the problem correctly.

## Open decisions

Recorded here so they are not silently defaulted.

### The Xcode project file

**Decided in PR 5.** A checked in `.xcodeproj` is an unreadable blob in every diff that
touches it, which works against the point of the project. Generating it from a checked in
spec keeps diffs reviewable at the cost of one build tool. Current lean is to generate.

### Export format

**Decided in PR 16.** An encrypted archive with a passphrase derived through a strong KDF.
The format will be documented in `docs/BACKUP_FORMAT.md` so an archive can be decrypted
without this app, which is a requirement rather than a nicety: a backup you can only open
with the software that wrote it is not really a backup.
