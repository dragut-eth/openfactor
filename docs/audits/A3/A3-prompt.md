# Gate A3 prompt

Paste the block below into a **fresh session**, with no memory of the document being
audited. Recommended: Fable 5, effort High.

**A3 is different from A1 and A2, and the difference is the point.** Those reviewed code
that could be changed in an update. This reviews a format that cannot: the moment a user
holds an archive, version 1 has to open forever. The document is the artefact under audit,
and it exists before the implementation on purpose.

If a paid human review of the cryptography can be funded, this is the gate to spend it on.
Run the model review regardless.

---

You are auditing a backup format specification for OpenFactor, an open source iOS and
watchOS two factor authentication app, at `/Users/<you>/OpenFactor`,
on branch `pr-16-backup-format` *(path redacted, visibly; nothing else changed)*. You did not write any of it.

The artefact is `docs/BACKUP_FORMAT.md`. **There is no implementation yet, and that is
deliberate.** The format is being audited before it is built, because an archive in a
user's hands makes the format permanent: a version 2 can be added, but every version 1
archive still has to open. A defect found here costs an edit. The same defect found after
release cannot be fixed, only lived with.

Weigh everything against what an archive is: every TOTP secret the user owns, in one file,
outside the Keychain, protected only by a passphrase. A TOTP secret cannot be revoked.
Anyone holding one generates valid codes forever, without the phone and without the owner
knowing.

## The task that matters most

**Write a decryptor from `docs/BACKUP_FORMAT.md` alone and see whether it reaches the test
vector's exact bytes.** Do not read the reference implementation first; there isn't one, and
that is the opportunity. Use any language with a mainstream crypto library. This is the real
test of whether the document is complete, and it is worth doing before the critical reading,
because every ambiguity you have to guess at is a finding.

Note precisely where you had to infer rather than read. Candidates the author already
worried about, and which you should verify are actually pinned down: whether the passphrase
is normalised or fed as typed, whether hyphens are part of it, what exactly the AAD bytes
are, base64 alphabet and padding, byte order and lengths, and whether the tag is appended to
the ciphertext or carried separately.

Then answer the harder question: could a competent implementer, reading only this page,
build something that *appears* to work but is subtly wrong? Silently truncating a key,
reusing a nonce across archives, verifying the tag after parsing rather than before. If the
document permits that reading, the document is at fault, not the implementer.

## Then the cryptography itself

1. **The PBKDF2 decision, argued in the document rather than assumed.** The claim is that
   universal availability beats theoretical strength because the format's purpose is
   recovery by a stranger's implementation, and that the generated 120 bit passphrase, not
   the KDF, carries the security. Attack that argument. Is 600,000 iterations right for
   2026? Does the reasoning survive a user who ignores the generator and types their own
   passphrase, which the format explicitly allows?
2. **AES-256-GCM as specified.** Nonce generation, the 12 byte length, the consequences of
   reuse, whether anything in this design could ever produce the same nonce twice under the
   same key. Confirm the AAD binding does what the document says it does.
3. **The minimum iteration floor.** A reader must refuse an archive claiming fewer than
   100,000 iterations, so a tampered header cannot make a file cheap to crack. Is that the
   right defence, the right threshold, and are there other header fields an attacker could
   edit to a victim's cost?
4. **The generated passphrase.** 120 bits from the system CSPRNG in RFC 4648 Base32,
   displayed in groups of four. Check the entropy claim arithmetically. Consider what
   happens to it in a screenshot, a password manager, a photograph.
5. **What the format admits it leaks**, which is length, and refuses to pad. Agree or
   disagree, and say what padding would actually buy.

## Then the payload rules

The document inherits a rule from gate A1: values that change a generated code are never
guessed, cosmetic values fall back quietly. Check that the required and optional fields are
split along exactly that line, that unknown fields are ignored rather than rejected, and
that one bad account cannot fail an archive or, worse, be imported wrong.

## Also in scope

- **The unencrypted Aegis compatible export**, and the decision to drop a plain
  `otpauth://` export in its favour.
- **The decision to refuse Aegis encrypted vaults** rather than support scrypt.
- **The versioning rules.** Are they sufficient to guarantee version 1 archives open
  forever, and is the boundary between additive and breaking changes drawn correctly?
- **The threat model of the archive**, as stated in the document's opening. Is anything
  claimed there stronger than the facts?

## How to work

- `SECURITY.md` holds the app's threat model, and `docs/audits/A1.md` and `A2.md` are the
  previous gates. A2's re-verification section is worth reading for the standard applied:
  most of its findings were sentences the project asserted that the code could not back.
- The test vector claims independent verification by CommonCrypto, Python's `hashlib`, and
  Node's OpenSSL binding. Re-derive it yourself rather than trusting that.
- Where you cannot establish something, write down that it is unestablished and what would
  settle it. Do not resolve it by assuming.

## What to produce

Write `docs/audits/A3.md`, following the shape of `docs/audits/A2.md`. Findings numbered
continuing from A2's last, each with what is wrong, why it matters given that a leaked TOTP
secret is permanent, and what would fix it. Separate what you verified from what you could
not. Say plainly if a section yielded nothing rather than manufacturing a finding.

State clearly at the top whether, in your judgement, **this format is safe to make
permanent.** That is the decision this gate exists to inform.

Do not write the implementation. Do not change `docs/BACKUP_FORMAT.md`; propose changes in
your report and let the author apply them, so the diff between the audited document and the
shipped one is visible.
