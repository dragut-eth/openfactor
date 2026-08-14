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

*Planned, arriving in PR 1 through PR 4.*

| Component | Responsibility |
| --- | --- |
| `Base32` | RFC 4648 decoding and encoding. Every secret arrives as Base32 text |
| `HOTP` | RFC 4226 counter based codes. SHA1, SHA256, SHA512 via CryptoKit |
| `TOTP` | RFC 6238 time based codes on top of `HOTP` |
| `OTPAuthURI` | Parsing and serializing `otpauth://` URIs |
| `SecretStore` | Reading and writing secrets, backed by the Keychain |

### Design decisions

**Time is injected.** `TOTP` takes a clock rather than calling `Date()` internally. That
makes every RFC test vector reproducible, and it leaves room for a clock skew correction
later without touching the generator.

**Parsing is total.** `OTPAuthURI` either returns a fully valid account or a typed error.
It never returns a partially populated account, because a silently dropped algorithm
parameter produces codes that look right and never work.

**Secrets and metadata are stored separately.** Issuer, label, color, and sort index are
not secret and live apart from the secret itself, so drawing the account list never loads
secret material into memory.

**No hand rolled cryptography.** HMAC and the hash functions come from CryptoKit. The only
cryptographic code written here is the RFC 4226 dynamic truncation, which is arithmetic on
the HMAC output and is covered by the published vectors.

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
