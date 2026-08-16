# A3, second half: the implementation

Gate A3 reviewed `docs/BACKUP_FORMAT.md` three times before any of it was written, which is
the right order and leaves an obvious hole: **a document that survives three reviews says
nothing about the code that claims to implement it.** The published test vector closes part
of that hole and not the interesting part. It proves this implementation reaches the same
bytes as three others; it cannot see a nonce reused between two exports, a temporary file
that outlives its screen, or an acknowledgement that refers to a passphrase which no longer
exists.

So the implementation was reviewed separately, by a different model from the one that wrote
it, in two passes with no contact between them:

- **The cryptography and its conformance to the normative document.** Every "must" and every
  numeric bound in the page, checked against the code.
- **The handling around it.** Where secret material comes from, how long it is held, which
  paths delete the file, what the gates actually gate.

Both were told to try to refute their own findings before reporting, and that false findings
are expensive. Every finding below was then verified independently before anything was
changed. Five were real. All five are fixed.

## F1. The whole file was bounded by the ciphertext's bound. **Blocking.**

`BackupArchive.read` opened with:

```swift
guard data.count <= maximumCiphertextCharacters else { throw .tooLarge }
```

The format bounds the `ciphertext` **string field** at 11,184,812 characters, checked before
decoding, and the decoded ciphertext at 8 MiB. It does not bound the container. That guard
applied the field's bound to the whole file, so a conforming archive at the top of the range
was refused by roughly the size of its own field names: the key derivation and cipher
objects, the salt, nonce and tag, and the whitespace come to about three hundred and sixty
bytes more than the ciphertext it holds.

The format is explicit that this is not a reader's choice to make:

> The bounds above are frozen for version 1. A future version may widen them; a version 1
> reader that widens them on its own has stopped implementing version 1.

Narrowing is the same offence in the other direction, and the direction that loses data. It
takes about fifty thousand accounts to reach, which is why nothing caught it, and it would
have been permanent for whoever did.

**Fixed** by separating `maximumFileBytes` from `maximumCiphertextCharacters` and giving it a
mebibyte of slack, so no archive whose ciphertext is inside the frozen ceiling can be refused
for the size of its container. The slack is generous on purpose: the format anticipates
padding arriving later as an ignored unknown field. The guard is now documented as this
reader's own policy on a quantity the format does not bound, which is a different thing from
one of the format's bounds.

## F2. The acknowledgement did not refer to the passphrase. **Blocking.**

The export screen has a toggle, "I have saved this passphrase", and it gates the file. The
format requires it:

> Never write an archive whose passphrase the user has not been shown and has not confirmed
> they have stored.

Nothing cleared it when the passphrase changed. Tick the box, then tap "Generate a different
one", and the archive was sealed with a passphrase that had never been on screen while the
box was ticked. The same held for editing a custom passphrase after ticking, and for
switching between the two kinds.

The failure is entirely silent. The archive is written, the share sheet appears, everything
looks right, and the passphrase on the piece of paper opens nothing. Nobody learns this at
export time. They learn it at a restore, on a device that no longer has the originals.

**Fixed.** The acknowledgement is cleared by `regenerate()`, by a change of kind, and by any
edit to a custom passphrase.

## F3. The strength floor lived in a disabled button. **Major.**

The format states the obligation on **writers**:

> A writer must refuse a custom passphrase weaker than 2^40 guesses under an offline strength
> estimator, or must not offer the custom path at all.

`BackupArchive.write` did not check. The only thing enforcing it was `.disabled(!canExport)`
on one SwiftUI button. A rule that lives in a view is a rule that a second caller, a keyboard
path, or a refactor removes by accident, and what it produces is a permanent archive holding
every secret its owner has behind something finished in a minute.

**Fixed.** The writer refuses, and returns `BackupError.passphraseTooWeak`. The button stays
disabled as a courtesy; the writer is the rule. Asserted from both directions, including a
test that drives the model past the screen's gate and watches the writer refuse anyway.

## F4. The estimator accepted things it should not have. **Major.**

Concrete inputs, verified against the shipped code before the fix:

| Input | What it is | Estimated |
| --- | --- | --- |
| `1qaz2wsx3edc` | a column walk down a keyboard | 53 bits |
| `qazwsxedcrfv` | the same walk, no digits | 49 bits |
| `qwertasdfgzx` | a row walk | 53 bits |
| `asdfasdfasdf` | four characters, three times | 56 bits |
| `trustno1trustno1` | a blocklisted word, written twice | 66 bits |

Two blind spots. Run collapsing only saw a repeated single character or a step of one in code
point order, so a repeated *unit* was priced as if every character were independent. And a
keyboard walk is not a sequence in code point order at all, so nothing saw it.

`trustno1trustno1` is the one worth remembering: `trustno` was already on the blocklist, and
writing it twice defeated the list entirely, because the prefix tolerance did not stretch
eight characters.

**Fixed.** Repeated units are collapsed before both the estimate and the blocklist, and
priced as the unit plus the choice of how many times. Keyboard walks are matched as
substrings when the walk is most of what is there. All five inputs are refused, and they are
in the suite by name.

## F5. A file could outlive the process. **Major.**

The temporary file is deleted in `onDisappear`, which covers every way the screen goes away
and not the case where the process does not: a force quit from the app switcher, or an out of
memory kill, while the file is on screen. Nothing revisited it afterwards.

For the encrypted archive that is a file nobody can open without the passphrase. For the
plain Aegis vault it is every secret in the clear, sitting in the container until the app is
deleted. `docs/BACKUP_FORMAT.md` promised deletion "whichever way it went away", and this was
the way the screen could not cover.

**Fixed.** Exports are written into one directory, which is removed at launch before the
interface exists.

## What the reviews confirmed rather than found

Worth recording, because a review that only produces findings tells you nothing about what it
looked at and did not object to.

- A fresh salt and a fresh nonce from the system CSPRNG on every write, independent of
  session, device and account set. This is the writer mistake the format calls catastrophic.
- The four derivation attempt algorithm, its ordering, and the property that the `passphrase`
  hint changes performance and never outcome.
- The requirement that the plaintext must **parse** and not merely authenticate, which is the
  defence against the AES-GCM key commitment collision demonstrated against an earlier
  revision of the format.
- Byte for byte comparison of the format string, and the AAD always taken from the constant
  rather than the file.
- Every JSON integer boundary the document names, including `2^53 - 1`, `2^53`, booleans,
  fractional values and strings, all correctly refused for `counter`.
- ASCII case mapping in both the passphrase canonicalisation and the Base32 secret decoder.
- No path reaching file creation without authentication succeeding.
- No logging anywhere in the export, import or backup code.
- An account that cannot be read fails the whole export rather than producing an archive
  quietly missing it.

## What neither review could reach

- **Whether Aegis accepts the plain vault this app writes.** That is one person, one import,
  once per format change, and no amount of review substitutes for it.
- **The file protection class on a device.** The simulator does not implement data
  protection, so the test that checks it is vacuous there and says so in its own text.
- **Whether a sheet dismissal path exists that neither review enumerated.** Both worked from
  the code rather than from a device.
