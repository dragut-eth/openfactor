# The OpenFactor backup format

Version 1. Written before the code, because gate A3 audits this document rather than an
implementation of it.

**A backup you can only open with the software that wrote it is not a backup.** Everything
here exists so that someone holding an `.openfactor` archive and this page, with no copy of
this app and no trust in its authors, can recover their secrets. The test vector at the end
is how they check they got it right.

This document is normative. Where the code and this page disagree, the page is correct and
the code is a defect.

**Revised after gate A3**, which found that the previous test vector was produced by
feeding the key derivation the displayed passphrase, hyphens included, contradicting this
document's own rule that hyphens are not part of it. Every implementation that had reached
those bytes would have contained the bug the rule exists to prevent. The vector below is
regenerated and the passphrase entry algorithm is now specified rather than described.

## What an archive is for, and what it is not

An archive exists so a person can move to another device, another app, or back from a
disaster. It is a file the user chose to create and is responsible for storing.

**It is the single most dangerous artefact this project produces.** Every secret, in one
place, outside the Keychain, protected only by a passphrase. The Keychain protections the
rest of the app relies on, the device passcode, the Secure Enclave, the protection class,
none of them apply once bytes are in a file. That asymmetry is why the format is audited
before it exists, and why the app generates the passphrase by default rather than asking
for one.

An archive is **not** a sync mechanism and not a second copy that maintains itself. It is a
snapshot, correct as of the moment it was written and stale immediately afterwards.

## The container

A UTF-8 JSON object. Whitespace and key order are not significant.

```json
{
  "format": "openfactor.backup.v1",
  "passphrase": "generated",
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

### What a reader must refuse

Refuse, with a message naming the reason, and before deriving any key:

- a `format` this reader does not implement
- a `passphrase` value other than `generated` or `custom`
- a `kdf.algorithm` other than `PBKDF2-HMAC-SHA256`
- a `cipher.algorithm` other than `AES-256-GCM`
- a `kdf.salt` that is not 32 bytes, a `cipher.nonce` that is not 12, a `cipher.tag` that
  is not 16
- a `kdf.iterations` outside 100,000 to 10,000,000 inclusive
- **any of these fields missing, null, or of the wrong JSON type.** Nothing here has a
  default. A reader that supplies one for `passphrase` in particular has silently chosen
  which rule to try first, which is a decision the file was supposed to make
- **a `ciphertext` longer than 8 MiB, or a decoded payload longer than 8 MiB.** Roughly
  fifty thousand accounts, far past any real archive and short of anything that hurts a
  phone. Every attacker controlled length needs a bound, not only the iteration count

These are checked rather than assumed even though a wrong value would fail the
authentication tag anyway, because a reader that ignores a field it consumes works by
accident, and because a future reader supporting more than one algorithm could otherwise be
steered by an edited field toward its weakest option.

### Passphrase entry, exactly

Two rules produce a key, and **a reader tries both**. The `passphrase` field says which one
the writer used, and it is a **hint that orders the attempts, never a gate that forbids
one**.

**Canonical form**, used for generated passphrases:

1. Uppercase using ASCII case mapping only, never a locale aware one, so that a Turkish
   locale cannot turn `i` into `İ`.
2. Keep only characters in the RFC 4648 Base32 alphabet, `A` to `Z` and `2` to `7`. Discard
   everything else.

That second step is the whole rule, and it is deliberately blunt. It removes hyphens,
whitespace under every competing definition of the word, en dashes and other dash lookalikes
that smart punctuation substitutes, byte order marks, and anything else a passphrase picks
up in transit. A correctly generated passphrase contains nothing but alphabet characters, so
discarding the rest can never change a clean input, and it rescues every mangled one.

**Verbatim form**, used for custom passphrases: the UTF-8 bytes of the input exactly as
given. No stripping, no case folding, no Unicode normalisation.

**The reader algorithm, which is not optional:**

```
try the form named by the passphrase field
if the tag verifies, done
try the other form
if the tag verifies, done
otherwise refuse
```

At most two derivations. The user supplies one input, so at most one of the two can match
the key, and there is no ambiguity to resolve. Two readers following this open exactly the
same set of archives whatever the header says.

**Why the field is a hint and not an instruction.** An earlier revision made it
authoritative, and that turned one byte of unauthenticated cleartext into a way to destroy
the only copy of somebody's secrets: flip `generated` to `custom` in any text editor, and a
conforming reader feeds the KDF different bytes than the writer did, forever. Authenticating
the field does not help, since a flipped bit would then fail the tag instead. The only
attacker served by that is one who wants the owner never to recover, and this is a recovery
format.

**Writers** set the field to match the rule they used, and canonicalise before deriving when
they generated the passphrase. A writer that mislabels merely costs a reader one extra
derivation.

**A hazard on the verbatim path.** Two keyboards can encode the same non-ASCII passphrase
differently, composed on one platform and decomposed on another, same glyphs and different
bytes, therefore a different key. This format does not normalise, because normalising would
silently change a passphrase a user typed. A writer should warn when a custom passphrase
contains non-ASCII characters, and a reader whose two attempts both fail **may** try the NFC
and NFD forms of the verbatim rule before refusing.

### Deriving the key

```
key = PBKDF2-HMAC-SHA256(
          password   = the passphrase bytes, produced exactly as specified above
          salt       = kdf.salt
          iterations = kdf.iterations
          length     = 32 bytes
      )
```

`iterations` is read from the file rather than assumed, so an archive written today still
opens when the recommended count rises.

**Why the range is enforced, stated correctly.** The KDF parameters are implicitly
authenticated: salt and iteration count both feed the key, so any edit yields a wrong key
and the tag refuses before plaintext exists. An attacker therefore cannot make an existing
archive cheaper to attack by editing its header, and the attacker's own offline cost is
fixed by whatever count was used at encryption, whatever the file claims. The floor exists
to refuse archives from writers that are nonconforming or hostile, not to defend the tag's
job. The ceiling exists because the one direction that does cost something is upward: an
`iterations` of two billion makes a phone grind for an hour before printing the same refusal
message, which is a free denial of service on precisely the recovery path. Ten million
leaves writers sixteen times the current headroom.

Writers use 600,000, the OWASP recommendation for PBKDF2-HMAC-SHA256 at the time of writing.

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

## Writing an archive

The obligations of an encryptor, gathered here rather than left implicit, because the one
mistake that breaks AES-GCM catastrophically is a writer's mistake and not a reader's.

- **A fresh 32 byte salt and a fresh 12 byte nonce from the system CSPRNG, for every
  archive written.** Not per session, not per device, not per set of accounts. Re-exporting
  an unchanged list of accounts is a new archive and takes new values. Reusing a nonce under
  the same key destroys the confidentiality of both archives.
- The fresh salt is what makes nonce reuse across archives harmless in practice, since a
  different salt yields a different key. Do not rely on that: generate both.
- `iterations` at 600,000, and within the range readers enforce.
- Set `passphrase` to match the rule actually applied.
- Never write an archive whose passphrase the user has not been shown and has not confirmed
  they have stored.

### Why PBKDF2 and not Argon2id

Argon2id is the better password hash and this format does not use it, deliberately.

The purpose of this document is that an archive can be opened by an implementation nobody
here wrote. PBKDF2 is in every cryptographic library in existence, including the standard
libraries of most languages. Argon2id and scrypt are not: Aegis chose scrypt for its
encrypted vault, and the consequence is that reading an Aegis vault requires finding a
scrypt implementation first. Choosing the weaker function with universal availability is a
deliberate trade of theoretical strength for real recoverability.

The trade is only defensible because of the generated passphrase. Against 120 bits of
entropy, PBKDF2 at 600,000 iterations is not the weak link, and neither would Argon2id be.

**On the custom path the trade is paid in full, and an earlier revision of this page denied
it.** It said no choice of KDF changes the weakness of a human chosen passphrase. That is
false. PBKDF2-HMAC-SHA256 at this work factor runs at thousands of guesses per second on one
current consumer GPU, which finishes a large wordlist in about an hour and a common password
in about a minute. Argon2id at standard memory settings moves that attack off the GPU
entirely, two to three orders of magnitude out. The user who overrides the generator is
precisely the user paying for PBKDF2's universal availability, and telling them the price is
zero was the kind of comfortable sentence this project exists to avoid.

Two consequences, both binding on writers:

- **The generator is the default and stays the default.** Necessary, and not sufficient.
- **A writer must refuse a custom passphrase below a stated strength**, or must not offer
  the custom path at all. `"password"` is otherwise a conforming archive holding every
  secret its owner has, permanently, because version 1 is forever. OpenFactor requires at
  least 12 characters and refuses passphrases on a common-password list; another
  implementation may set a different bar, but it must set one.

### The generated passphrase

The app generates 120 bits of entropy from the system CSPRNG, encoded in the RFC 4648
Base32 alphabet, and displayed in groups of four:

```
YZTR-THFW-WT6E-OXIV-73XD-QCDM
```

Twenty four characters, five bits each, one hundred and twenty bits. Base32 because that
alphabet exists precisely to be transcribed by hand: it excludes `0`, `1`, `8` and `9`, so
there is no confusion with `O`, `I`, `B` or `g`. Every character of a generated passphrase
is drawn from `A` to `Z` and `2` to `7`, and nothing else.

The hyphens are display only, are not part of the passphrase, and are removed by the
canonicalisation above before the key is derived.

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
| `counter` | hotp only | The next counter value, 0 to 2^53 - 1 |
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
what it could not, by name and by reason. An account with neither `issuer` nor `name` is
reported by its position in the array, counting from one.

### The cases an implementer would otherwise have to guess

- `period` on an `hotp` account, or `counter` on a `totp` account, is **ignored**, under the
  unknown fields rule. It is not an error.
- `secret` is decoded leniently as to form and strictly as to content: lower case is
  accepted, internal spaces and hyphens are ignored, `=` padding is optional. Any character
  outside the Base32 alphabet refuses the account.
- An empty `accounts` array is **valid**. It imports nothing and is not an error.
- `counter` must be an integer from 0 to 2^53 - 1. A reader whose JSON parser represents
  numbers as doubles must refuse any value it cannot hold exactly, rather than importing a
  silently corrupted counter, which produces codes that are rejected forever.

## Test vector

Reproducible: real values, produced by the reference implementation and verified by two
others that share no code with it. Salt and nonce are fixed here for reproducibility. **A
real archive generates both from the system CSPRNG and never reuses either**, as required
above.

| | |
| --- | --- |
**This passphrase is published in a public document. Never use it to protect anything.**
It exists so implementations can check themselves.

| `passphrase` mode | `generated` |
| Passphrase, as displayed to the user | `YZTR-THFW-WT6E-OXIV-73XD-QCDM` |
| Passphrase, canonicalised, and this is what the KDF receives | `YZTRTHFWWT6EOXIV73XDQCDM`, 24 characters |
| Salt | bytes `00 01 02 ... 1f`, base64 `AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=` |
| Iterations | 600000 |
| Nonce | bytes `a0 a1 ... ab`, base64 `oKGio6Slpqeoqaqr` |
| AAD | `openfactor.backup.v1` |

**Start from the displayed form.** An implementation that derives a key from
`YZTR-THFW-WT6E-OXIV-73XD-QCDM` without removing the hyphens will not reach these bytes,
and that is deliberate: the previous version of this document published a vector with
exactly that mistake baked in, so the check now exercises the canonicalisation rather than
bypassing it.

Derived key, hex:

```
7feefa76093f66f306e972be1d33e7fbdb38a84f193b3ab938c4ece73dd60959
```

Plaintext, 151 bytes, exactly as encrypted:

```json
{"accounts":[{"algorithm":"SHA1","digits":6,"issuer":"GitHub","name":"octocat","period":30,"secret":"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ","type":"totp"}]}
```

Ciphertext, base64:

```
LQbc+Ku8Xw1jJEsA9V+waNf0luWbZStsdzfebd88iuTZaTr4FXtT4sEEMYt5ZLebsi6do6nGL5suyhvS4vjFcU3/TV41rvHc2tcCo/eh1htRhs5S4czcbinvrq8GQeudGE8GWWMC4ixMOhpO83rYH3hFZiQOQz6t0ripJP/SeRSFRC3ae/AEh9OOsyiOEXK06+7wsk4KbQ==
```

Tag, base64:

```
9rCMg60+9TYAwqaTdsgr6A==
```

### Inputs that must all reach the same key

A vector with one clean input certifies a reader that only handles clean input. Each of
these is a way a real person hands the passphrase back, and **every one must produce the
generated key above**. A reader that opens the archive from the first line and refuses any
of the rest has implemented a different format.

| Input | Why it happens |
| --- | --- |
| `YZTR-THFW-WT6E-OXIV-73XD-QCDM` | As displayed |
| `yztr-thfw-wt6e-oxiv-73xd-qcdm` | Copied through something that lowercased it. Also the Turkish locale trap: an implementation uppercasing with a locale turns this `i` into `İ` and fails |
| `YZTR<en dash>THFW<en dash>WT6E<en dash>OXIV<en dash>73XD<en dash>QCDM` | iOS smart punctuation replaces typed hyphens with `U+2013` |
| `<BOM>YZTR-THFW-WT6E-OXIV-73XD-QCDM<newline>` | Saved to a UTF-8 file and read back |
| `YZTR-THFW-WT6E-OXIV-73XD-QCD<U+200B>M` | Pasted through a web page or messenger that inserts a zero width space |
| `YZTR THFW WT6E OXIV 73XD QCDM` | Retyped with spaces instead of hyphens |
| `YZTRTHFWWT6EOXIV73XDQCDM` | Already canonical |

### A second vector, for the verbatim path

Same salt, nonce, AAD and plaintext. Only the passphrase rule differs, and **this one is not
canonicalised**: an implementation that applies the Base32 filter here will strip the spaces
and the lower case and reach the wrong key.

| | |
| --- | --- |
| `passphrase` mode | `custom` |
| Passphrase, used exactly as written | `correct horse battery staple` |

Derived key, hex:

```
613a4c3411394e24fffe6c51994307724572e574bcd98ea8cf457c64899bfbfe
```

Ciphertext, base64:

```
jxXW2I3FDYM2CqyCTNDj+b3Zuav2PAhE3rf17Q/9cRSx+jrk3SiK3h0ZOtTAi8cTT+EScWhxe58X6vLU7CvcKd5Pv/JeJguw0+X7U+/fkrcm289T3U/bEZ1xy2sV6WUoUW/hnNNnBuEXcwP8ALK/NZo15TyalQMCo7AvjCIQbUP7rbgakKY7PSU8qMtrUHcxa605jtifCA==
```

Tag, base64:

```
9OArOIi1DKg5MhDvaxBUpw==
```

This passphrase is deliberately weak, to demonstrate the rule rather than the policy. A
conforming writer would refuse it under the custom-mode strength requirement above.

### What must fail

A reader that only proves it can open things has proved half of what matters.

- The generated ciphertext under the **custom** key, and the custom ciphertext under the
  **generated** key: both must fail the tag.
- Either ciphertext with the **AAD omitted** or set to any other string: must fail.
- Either ciphertext with **any single byte altered**, in the ciphertext or the tag: must
  fail.
- The generated passphrase **with the hyphens left in**, fed verbatim: must fail, and this
  is the one that matters, because an earlier revision of this document published a vector
  that made exactly that mistake pass.

**Verified independently, three implementations sharing no code.** Both keys were derived by
Apple's CommonCrypto and by Python's `hashlib.pbkdf2_hmac`, which agree to the byte. Both
ciphertexts were sealed by CryptoKit and opened, with tags verified and AAD checked, by
Node's OpenSSL binding. The seven inputs above were each run through the canonicalisation
and confirmed to reach the same key.

An implementer should reach exactly these bytes, pass every row of the table, and see every
item under "what must fail" actually fail, before trusting their reader with anything real.

## Unencrypted export

*Non-normative. This section describes intent; PR 16 specifies the output and this document
will be updated to pin it.*

The app can also export a plain **Aegis compatible JSON** file, for moving to another app.
It is not this format and is not encrypted. It exists because an authenticator you cannot
leave is a trap, and because a file other apps genuinely import is a better escape hatch
than a list of URIs.

When PR 16 lands, this section must state the Aegis vault database version emitted and cite
the Aegis format documentation at a fixed revision. Aegis is another project's format and a
moving target, and "compatible" without a version is the same unverifiable claim this
document exists to avoid.

A raw `otpauth://` text export was considered and dropped. It offered no portability the
Aegis file does not, and a second plaintext path is a second thing to warn about, audit, and
get wrong.

**The temporary file has a lifecycle, and it is part of the design.** A plaintext export is
written only when the user explicitly asks for it, with the strongest file protection class
iOS offers while it exists, and the app's copy is deleted as soon as the share sheet
completes or is cancelled. No history of plaintext exports is kept. The warning shown before
it is produced says what the file is: reusable authentication secrets, in the clear.

## What this format deliberately does not do

- **No compression.** It would add a decompressor to the trusted path, and to an attacker
  controlled one, to save a few kilobytes.
- **No key file, no hardware key, no split secret.** Every one of them is a way to lose the
  archive, and this is a format whose purpose is recovery.
- **No metadata outside the ciphertext**, beyond what decryption needs. No account names, no
  issuers, no colours. Two things are visible to anyone holding the file and unable to open
  it. **The length reveals the approximate number of accounts**, at roughly 150 bytes each,
  and the format does not pad to hide it. **The `passphrase` field reveals which kind of
  passphrase protects it**, which tells an attacker whether guessing is worth attempting at
  all: `custom` is a human's choice and possibly cheap, `generated` is 120 bits and never
  worth trying. That is a real signal and it is the price of the field being there;
  it stays because a reader that tries the likely rule first is faster for everyone, and
  because the field is only a hint, so removing it would change nothing an attacker cannot
  work out by trying. Saying it hides the count
  would be a claim the file cannot back. Padding remains available later as an additive
  change, since an unknown field is ignored by existing readers.
- **No timestamp and no device name.** Neither helps recovery, and both say something about
  the owner.

## Changing this format

Version 1 archives must open forever. A version 2 may exist; it does not retire version 1,
because someone has a file in a drawer.

Additive changes, new optional fields, do not need a new version, since readers ignore what
they do not know. **A new value for an existing enumerated field is also additive**: a
future `type` or `algorithm` is refused by a version 1 reader under the never-guess rule,
which is the correct behaviour and not a compatibility break.

Anything else needs a new version: a changed cipher, a changed KDF, a changed meaning for an
existing field, a newly required field.

**The bounds above are frozen for version 1.** The iteration range, the field lengths and
the size limits are part of what a version 1 archive means, not a reader's local policy. A
future version may widen them; a version 1 reader that widens them on its own has stopped
implementing version 1, and "every version 1 archive opens forever" quietly stops being
true. Raising the recommended write count inside the existing range is fine and needs no
new version.

**Every future version must bind its own format string as additional authenticated data**,
exactly as version 1 binds `openfactor.backup.v1`. The guarantee that a file cannot be
relabelled as another version depends on every version doing this, and it is lost the moment
one does not.

The test vector above is part of the format. If a change breaks it, the change is wrong or
the version is new.
