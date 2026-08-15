# The OpenFactor backup format

Version 1. Written before the code, because gate A3 audits this document rather than an
implementation of it.

**A backup you can only open with the software that wrote it is not a backup.** Everything
here exists so that someone holding an `.openfactor` archive and this page, with no copy of
this app and no trust in its authors, can recover their secrets. The test vector at the end
is how they check they got it right.

This document is normative. Where the code and this page disagree, the page is correct and
the code is a defect.

## What an archive is for, and what it is not

An archive exists so a person can move to another device, another app, or back from a
disaster. It is a file the user chose to create and is responsible for storing.

**It is the single most dangerous artefact this project produces.** Every secret, in one
place, outside the Keychain, protected only by a passphrase. The Keychain protections the
rest of the app relies on, the device passcode, the Secure Enclave, the protection class,
none of them apply once bytes are in a file. That asymmetry is why the format is audited
before it exists, and why the app generates the passphrase rather than asking for one.

An archive is **not** a sync mechanism and not a second copy that maintains itself. It is a
snapshot, correct as of the moment it was written and stale immediately afterwards.

## The container

A UTF-8 JSON object. Whitespace and key order are not significant.

```json
{
  "format": "openfactor.backup.v1",
  "kdf": {
    "algorithm": "PBKDF2-HMAC-SHA256",
    "iterations": 600000,
    "salt": "<base64, 32 bytes>"
  },
  "cipher": {
    "algorithm": "AES-256-GCM",
    "nonce": "<base64, 12 bytes>",
    "tag": "<base64, 16 bytes>"
  },
  "ciphertext": "<base64>"
}
```

All base64 is standard, with padding, per RFC 4648 section 4. Not the URL safe alphabet.

`format` identifies the version and is the only field a reader must understand before
anything else. A reader that does not recognise the value must refuse the file and say so,
rather than attempt it.

### Deriving the key

```
key = PBKDF2-HMAC-SHA256(
          password   = the passphrase, as UTF-8 bytes, no normalisation, no trailing newline
          salt       = kdf.salt
          iterations = kdf.iterations
          length     = 32 bytes
      )
```

`iterations` is read from the file rather than assumed, so an archive written today still
opens when the recommended count rises. A reader **must** refuse a file whose `iterations`
is below 100,000: an attacker who can edit the header could otherwise hand a victim a file
that is cheap to crack, and honouring that instruction would be doing their work for them.

Writers use 600,000, which is the OWASP recommendation for PBKDF2-HMAC-SHA256 at the time
of writing.

### Decrypting the payload

```
plaintext = AES-256-GCM-Decrypt(
                key        = the derived key
                nonce      = cipher.nonce
                ciphertext = ciphertext
                tag        = cipher.tag
                aad        = the ASCII bytes of the format string, "openfactor.backup.v1"
            )
```

The authentication tag **must** be verified before the plaintext is parsed. A failure means
one of two things and the reader cannot tell which: the passphrase is wrong, or the file has
been altered. Say both, and never fall back to using unauthenticated plaintext.

Binding the format string as additional authenticated data means a file cannot be relabelled
as a different version and still open.

### Why PBKDF2 and not Argon2id

Argon2id is the better password hash and this format does not use it, deliberately.

The purpose of this document is that an archive can be opened by an implementation nobody
here wrote. PBKDF2 is in every cryptographic library in existence, including the standard
libraries of most languages. Argon2id and scrypt are not: Aegis chose scrypt for its
encrypted vault, and the consequence is that reading an Aegis vault requires finding a
scrypt implementation first. Choosing the weaker function with universal availability is a
deliberate trade of theoretical strength for real recoverability.

The trade is only defensible because of the passphrase. Against a human chosen passphrase,
Argon2id buys a few orders of magnitude and a determined attacker still wins eventually.
Against the 120 bit random passphrase this app generates, PBKDF2 at 600,000 iterations is
not the weak link and neither would anything else be. **The passphrase carries the security
of this format, not the KDF.** An archive protected by a passphrase the user invented is
weaker than one protected by a generated passphrase, and no choice of KDF changes that.

### The generated passphrase

The app generates 120 bits of entropy from the system CSPRNG, encoded in the RFC 4648
Base32 alphabet, and displayed in groups of four:

```
K7M2-9QXP-4RTV-8LZW-3NBY-6HFD
```

Base32 because that alphabet exists precisely to be transcribed by hand: it excludes `0`,
`1`, `8` and `9`, so there is no confusion with `O`, `I`, `B` or `g`.

**The hyphens are display only. They are not part of the passphrase** and are not passed to
the KDF. A reader accepting a typed passphrase should strip them, along with whitespace, and
should accept either case, because a person copying twenty six characters off a screen will
not reproduce the spacing.

The user may supply their own passphrase instead, which is used verbatim: exactly as typed,
with no stripping, no case folding, and no Unicode normalisation. Two different rules, and
the file does not record which was used, so a reader must try the passphrase as given.

## The payload

The decrypted plaintext is a UTF-8 JSON object.

```json
{
  "accounts": [
    {
      "type": "totp",
      "secret": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
      "algorithm": "SHA1",
      "digits": 6,
      "period": 30,
      "issuer": "GitHub",
      "name": "octocat",
      "color": "blue",
      "sortIndex": 0
    }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `type` | yes | `totp` or `hotp` |
| `secret` | yes | The shared secret, Base32, RFC 4648, padding optional |
| `algorithm` | yes | `SHA1`, `SHA256`, or `SHA512` |
| `digits` | yes | 6 to 8 |
| `period` | totp only | Seconds, 1 to 3600 |
| `counter` | hotp only | The next counter value |
| `issuer` | no | The service name |
| `name` | no | The account, usually an email address |
| `color` | no | A card colour, see below. Cosmetic |
| `sortIndex` | no | Position in the list. Cosmetic |

**Unknown fields must be ignored, not rejected.** A version 1 reader meeting a field added
later should import the account without it.

**Values that change a generated code are never guessed.** If `algorithm`, `digits`,
`period`, `counter` or `secret` is missing, malformed, or unrecognised, that account is
refused and named. Substituting a default there produces codes that look correct and are
rejected forever, and the user finds out at a login, not at the import.

**Cosmetic values fall back.** An unrecognised `color` becomes the default rather than
failing the account, and a missing `sortIndex` places the account at the end. This is the
same rule the stored metadata follows, set at gate A1: things that affect a code fail loudly,
things that affect appearance fail quietly.

Colours are `red`, `orange`, `yellow`, `green`, `teal`, `blue`, `indigo`, `purple`, `pink`,
`gray`. The default is `blue`.

**One account failing does not fail the archive.** A reader imports what it can and reports
what it could not, by name and by reason.

## Test vector

Reproducible: real values, produced by the reference implementation and verified by two
others that share no code with it. Salt and nonce are fixed here for reproducibility. **A
real archive generates both from the system CSPRNG and never reuses either.**

| | |
| --- | --- |
| Passphrase | `K7M2-9QXP-4RTV-8LZW-3NBY-6HFD` |
| Passphrase as fed to the KDF | `K7M29QXP4RTV8LZW3NBY6HFD`, hyphens stripped, 24 characters |
| Salt | bytes `00 01 02 ... 1f`, base64 `AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=` |
| Iterations | 600000 |
| Nonce | bytes `a0 a1 ... ab`, base64 `oKGio6Slpqeoqaqr` |
| AAD | `openfactor.backup.v1` |

Derived key, hex:

```
7d5178519bdb3187cb121b498f45529d36b5d8bcd41eca0df81eb0bdd078f9eb
```

Plaintext, 151 bytes, exactly as encrypted:

```json
{"accounts":[{"algorithm":"SHA1","digits":6,"issuer":"GitHub","name":"octocat","period":30,"secret":"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ","type":"totp"}]}
```

Ciphertext, base64:

```
EdXGm7XJ0UGj6GsM5pQYXpMOFj8uC7zvsnrdiJttSDGNhGJF+w4fCgqTMRsldxNDzeKRnW7LBlAJEGK6x7VhH9Vr6I6o0O0jaJptPag0A0CDQJVyTxt8kKAv4U85w6YLbNfObrKP6/hBFFtsaT9Zf4rqtsQJwog8mvSrOz85ww4vStI+o5imBAxsU82MnstHpEzd0Rc7uA==
```

Tag, base64:

```
h6pAEJ1CbGsZIxRJ3WD2HQ==
```

**Verified independently.** The key was derived by Apple's CommonCrypto and, separately, by
Python's `hashlib.pbkdf2_hmac`, which agree. The ciphertext was sealed by CryptoKit and
decrypted, with the tag verified and the AAD checked, by Node's OpenSSL binding. Three
implementations sharing no code. That is the claim this document makes, tested rather than
asserted.

An implementer should reach exactly these bytes before trusting their reader with anything
real.

## Unencrypted export

The app can also export a plain **Aegis compatible JSON** file, for moving to another app.
It is not this format and is not encrypted. It exists because an authenticator you cannot
leave is a trap, and because a file other apps genuinely import is a better escape hatch
than a list of URIs.

A raw `otpauth://` text export was considered and dropped. It offered no portability the
Aegis file does not, and a second plaintext path is a second thing to warn about, audit, and
get wrong.

## What this format deliberately does not do

- **No compression.** It would add a decompressor to the trusted path, and to an attacker
  controlled one, to save a few kilobytes.
- **No key file, no hardware key, no split secret.** Every one of them is a way to lose the
  archive, and this is a format whose purpose is recovery.
- **No metadata outside the ciphertext**, beyond what decryption needs. An archive should
  not reveal how many accounts it holds, or for which services, to someone who cannot open
  it. The only leak is length, which is inherent, and is why the payload is not padded to
  hide it either: pretending otherwise would be worse than saying so.
- **No timestamp and no device name.** Neither helps recovery, and both say something about
  the owner.

## Changing this format

Version 1 archives must open forever. A version 2 may exist; it does not retire version 1,
because someone has a file in a drawer.

Additive changes, new optional fields, do not need a new version, since readers ignore what
they do not know. Anything else does: a changed cipher, a changed KDF, a changed meaning for
an existing field, a newly required field.

The test vector above is part of the format. If a change breaks it, the change is wrong or
the version is new.
