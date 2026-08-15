# Gate A3, second pass: independent review of the post-A3 backup format

**Date:** 2026-08-15
**Scope:** `docs/BACKUP_FORMAT.md` on `main` at `b8b5889`. There is still no
implementation. Every finding is against the page. The page was not edited.
**Reviewer:** Grok 4.6. The decryptor, the attacks, and the findings below were written
before opening `docs/audits/A3.md`. A3 is a review of an earlier revision; this is a
review of the document as it stands after that revision. Overlap is marked per finding.
The decryptor lives in `/tmp` and was not written into this repository.

**The one sentence that matters.** The cryptographic core is sound and the published
test vector is correct, but this format is not yet safe to make permanent: the new
passphrase-mode rules are still not a unique algorithm, and a single unauthenticated
header bit can turn a correct passphrase into a brick.

## Method

A decryptor was written from this page alone, in Python (pycryptodome) and again in
Node (OpenSSL binding), starting from the passphrase as a user sees it,
`YZTR-THFW-WT6E-OXIV-73XD-QCDM`. Both derived the published key, both opened the
published ciphertext under the published tag and the AAD `openfactor.backup.v1`, both
re-encrypted the published plaintext to the same ciphertext and tag, and both refused
the same ciphertext when the AAD, the key, or the hyphen-stripping step was wrong.

Only after that, and after the findings were written down, was `docs/audits/A3.md`
read, so that "new" below means new against this revision, not "A3 missed this on
the old page."

## Verified by doing

These are measurements, not readings.

- **The published vector is internally consistent, and consistent with the rule.**
  From the displayed hyphenated string, after removing `U+002D` and taking UTF-8,
  PBKDF2-HMAC-SHA256 at 600,000 iterations with salt `00…1f` produces
  `7feefa76093f66f306e972be1d33e7fbdb38a84f193b3ab938c4ece73dd60959`. AES-256-GCM
  with nonce `a0…ab`, that key, and AAD `openfactor.backup.v1` decrypts the published
  ciphertext to the published 151-byte plaintext, and the tag verifies. Re-sealing
  those exact inputs reproduces the published ciphertext and tag byte-for-byte, in
  both Python and Node. The previous vector's defect, feeding the KDF the hyphens,
  is gone: the hyphenated UTF-8 derives
  `d8be07de133ca29bc91b82b1b13e1e71f293fcf7f924b7ef2a8ac09d25511d78`, under which
  the published ciphertext refuses.
- **The AAD binding is real.** The same key and ciphertext fail the tag with AAD
  `openfactor.backup.v2`, and with no AAD.
- **Lengths are as claimed.** Salt 32, nonce 12, tag 16, ciphertext 151, plaintext
  151. The tag is carried separately; it is not appended.
- **The entropy arithmetic holds.** 24 RFC 4648 Base32 characters are 120 bits
  with no padding. The current example, `YZTR-THFW-WT6E-OXIV-73XD-QCDM`, uses only
  `A–Z` and `2–7`. Canonicalising a correctly generated passphrase does not throw
  entropy away: the hyphens were never part of it, and the letters are already
  upper case.
- **600,000 is still the OWASP figure for PBKDF2-HMAC-SHA256**, checked against
  the Password Storage Cheat Sheet on 2026-08-15, not remembered.
- **The iteration ceiling is a real time bound, not a paper one.** On this machine,
  100,000 iterations of the vector's PBKDF2 took 27 ms, 600,000 took 167 ms, and
  10,000,000 took 2.8 s. The floor is about six times cheaper than the writer
  default. The ceiling is about seventeen times more expensive. Both are in the
  range the document's own recovery-path reasoning is reaching for.
- **Two Apple APIs already disagree about the new whitespace rule.**
  `Character.isWhitespace` is false for `U+200B` ZERO WIDTH SPACE;
  `CharacterSet.whitespaces` contains it. Neither treats `U+FEFF` as whitespace.
  Neither strips `U+2013` EN DASH. Swift `uppercased(with: Locale(identifier:
  "tr_TR"))` turns the `i` in the vector passphrase's lower-case form, `oxiv`,
  into `İ`. Those four measurements are the evidence under F33, F34, and F38.

## Attacked by reading, and what yielded nothing

**PBKDF2, and the justification.** Against the generated 120-bit passphrase the
argument holds. At any iteration count, including one, 2^120 candidates are not a
practical attack, and Argon2id would not change that. Against a passphrase the user
invented, the argument overclaims; that is F37. The availability claim is still
the right reason to pick PBKDF2 for a format whose purpose is that a stranger can
open the file. 600,000 iterations is the current OWASP recommendation and is
adequate for 2026 on the generated path. It is not what will make a human
passphrase last.

**Nonce generation and reuse.** Sound. A fresh 32-byte salt per archive means a
fresh key per archive, so a repeated 12-byte nonce is harmless in practice, and
the document tells writers not to rely on that. The same nonce and key pair twice
requires the same salt, the same iterations, the same passphrase, and the same
nonce. That is not a probability worth writing down unless the CSPRNG is broken
or a writer caches. The writer section now says the right thing. Nothing found
beyond the test-vector values themselves becoming a published key if a writer
copies them, F42.

**Key separation.** One 32-byte PBKDF2 output, used once, as an AES-256-GCM key.
GCM is an AEAD, so there is no second MAC key to derive. Nothing found for
version 1. A later feature that reused this output for anything else would need
HKDF and a version bump; that is a note for a v2 author, not a defect.

**AAD binding.** It does what the document says, verified above: a file cannot be
relabelled as another version and still open, provided every future version binds
its own format string, which the versioning section now requires. It does not bind
the passphrase-mode field, the algorithm strings, or anything else in the header.
Salt and iterations are implicitly authenticated because they feed the key;
changing them fails the tag. Algorithm substitution is refused by the v1 reader
rules and is not exploitable against a v1-only reader. The unbound field that
does something is the mode bit, F35.

**Downgrade and version confusion.** A v1 reader refuses an unknown `format`
before it derives a key. A v2 reader that uses `openfactor.backup.v2` as AAD
cannot open a v1 ciphertext under a flipped label, because the tag was computed
under different AAD. Nothing found that lets a file open as the wrong version.

**Multi-target.** Unique 32-byte salts give unique keys even when many users share
a passphrase, so there is no rainbow table and no batch advantage that matters.
A million generated archives still cost on the order of 2^100 against "any one,"
which is not an attack. Custom archives are attacked one at a time at a few
thousand guesses per second per high-end GPU; that is F37, not a multi-target
defect.

**Parse, verify, decrypt.** The page is explicit: refuse the header before any
key is derived, verify the tag before the plaintext is parsed, and do not
distinguish a wrong passphrase from a wrong file. Key length is stated as 32
bytes. Nonce 12, tag 16, refused if not. Those are the classic wrong readings,
and the document no longer permits them. What it still permits is unbounded input
before those checks can fire, F39, and a missing or mistyped field, F41.

**The generated passphrase's 120 bits.** Delivered, if the writer does what the
page says. Encoding 15 CSPRNG bytes as RFC 4648 Base32, or drawing 24 independent
characters from that alphabet, are both 120 bits, and the decryptor never has to
know which. No finding.

## Findings

Numbered from F33 so they do not collide with A3's F22–F32. None of A3's
blocking findings are still true of this page; the new ones are almost all about
the mechanism A3 asked for and this revision invented.

### F33: "Unicode whitespace" is not an algorithm, and two conforming readers can already disagree

What is wrong: generated-mode step 1 says "remove every Unicode whitespace
character" and does not say which definition. Unicode White_Space (UAX #44),
General Category `Z*`, Swift `Character.isWhitespace`, Foundation
`CharacterSet.whitespaces`, Java `Character.isWhitespace`, and Python
`str.isspace()` are four different sets. Measured on this machine, on the current
Apple SDK: `Character.isWhitespace` is false for `U+200B` ZERO WIDTH SPACE and
`CharacterSet.whitespaces` contains it; `CharacterSet.whitespaces` does not
contain `U+000A` LINE FEED and `Character.isWhitespace` does. A reader that
filters on `isWhitespace` and a reader that strips `CharacterSet.whitespaces`
therefore produce different keys from the same paste the moment that paste
carries a zero-width space, which web copy and some messengers insert, or is
implemented against only the space-separator set and so leaves a trailing
newline in place.

Why it matters: the document's load-bearing sentence about the new field is
"This field is why two conforming readers cannot disagree about which archives
open." The field picks a rule. The rule is not unique. A TOTP secret cannot be
revoked, and a backup that one honest reader opens and another honest reader
refuses is lost at the only moment the format exists for. The official vector
has no whitespace in it, so both readers will certify against this page and
then diverge in the field.

What would fix it: cite one definition, preferably the Unicode White_Space
property by code point, listed, so no language's standard library is the spec.
Require generated-mode readers to strip at least that set plus `U+FEFF` and
`U+200B` (F34). Add vector rows whose typed form contains a trailing newline,
an internal space, and a zero-width space, all of which must produce the
published key.

**New relative to A3.** A3 F24 said there was no algorithm. This revision added
one. The algorithm is still not unique.

### F34: only `U+002D` is removed, so a generated passphrase copied through ordinary text is a different key

What is wrong: step 1 removes ASCII hyphen-minus and nothing hyphen-like.
`U+2013` EN DASH, `U+2014` EM DASH, `U+2010` HYPHEN, `U+2212` MINUS SIGN,
`U+FF0D` FULLWIDTH HYPHEN-MINUS, and `U+FEFF` BYTE ORDER MARK all survive
canonicalisation. Confirmed by running the specified algorithm against each.
iOS smart punctuation turns typed hyphens into en-dashes; Mail, Notes, and web
pages do the same; a UTF-8 file often begins with a BOM. None of those
characters appear in a correctly generated passphrase, so stripping them cannot
change the key of a clean input, and leaving them in changes the key of a
real paste.

Why it matters: the user typed or pasted the passphrase the app displayed. The
file refuses. The error the document requires is "wrong passphrase or the file
has been altered." At a recovery, with the phone gone, that is a permanent loss
of every secret the archive holds.

What would fix it: in generated mode, after the whitespace pass, remove the
common dash punctuation (`U+2010`–`U+2014`, `U+2212`, `U+FE63`, `U+FF0D`) and
leading `U+FEFF`, or, simpler, delete every character that is not in the RFC
4648 Base32 alphabet and then fold. The second rule is the one a human
transcribing a Base32 string actually needs, and it makes F33's whitespace
question go away. Custom mode stays verbatim.

**New relative to A3.**

### F35: the new `passphrase` field is an unauthenticated lockout bit

What is wrong: `generated` and `custom` select different inputs to the KDF, the
field sits in the clear, and it is not AAD. A conforming reader "must" apply
exactly the labelled rule. Flipping the one byte that distinguishes the two
values, by an editor, by bitrot, by a helpful "normaliser," or by a writer
that labels the archive `custom` after canonicalising, makes a conforming
reader feed the KDF different bytes than the writer did, for every generated
passphrase pasted the way the screen shows it. The tag then refuses. The
document already describes the writer-mislabel case and calls it "a file
nobody can open." The same file is produced by anyone who can edit JSON.

The field is not needed for the property the document says it provides. A
reader that derives once with the bytes as typed, and on tag failure derives
once with the generated canonicalisation, opens every archive a conforming
writer produced, labelled either way, and cannot open an archive under two
different plaintexts: the user has one input, and at most one of the two
derivations matches the key. Two such readers agree. The header is then a
hint, not a gate.

Why it matters: this is a recovery format. The only attacker who benefits from
a flipped bit is the one who wanted the owner not to get their secrets back.
Confidentiality is unchanged; availability of the one copy is destroyed. A
TOTP secret that cannot be recovered is as gone as one that was stolen.

What would fix it: make the field a hint. Specify the reader as: try the
labelled rule first; if the tag refuses, try the other rule; then stop. Or
drop the field and always try exact then canonicalised, which is what A3 F24
proposed and which this revision rejected in favour of a header. Either
removes the lockout. Binding the field as AAD does not: a flip would still
fail the tag.

**New relative to A3.** A3's page had no such field. A3 recommended try-both
precisely because the file did not record the mode. This revision recorded
the mode and made it mandatory, which reintroduces a worse form of the
disagreement A3 was closing.

### F36: the mode field leaks the attack class, and the leak admission does not say so

What is wrong: the document admits that ciphertext length roughly reveals the
account count, and it is honest about that. It does not admit that
`"passphrase": "custom"` tells an attacker to run a wordlist and that
`"generated"` tells them not to bother. That bit is sitting next to the salt,
in the clear, on every archive. The same section also does not mention that
length leaks more than a count: issuer and name lengths ride along in the
151-bytes-per-account figure, so two archives with the same number of
accounts are distinguishable.

Why it matters: a leaked TOTP secret is permanent. Sorting a corpus of stolen
archives into "worth a GPU week" and "not" is exactly the help a cleartext
mode bit provides. The document's credibility on leaks is the thing it spent
A3 F28 repairing; a new field that classifies the passphrase should have
been added to the same bullet.

What would fix it: name the mode bit, and the exact length, in the leak
list. If F35's try-both lands, the field can be dropped and the classification
leak goes with it. Padding remains an additive option, as the page already
says.

**New relative to A3.** The field did not exist. The account-count sentence
A3 F28 objected to is gone.

### F37: the page claims the KDF does not matter for a user-chosen passphrase, and that is false

What is wrong: "An archive protected by a passphrase the user invented is
weaker than one protected by a generated passphrase, and no choice of KDF
changes that." The first clause is true. The second is not. PBKDF2-HMAC-SHA256
at 600,000 iterations is a few thousand guesses per second on a current
high-end GPU, on the order of 2,000 to 2,500 on a published RTX 4090 hashcat
benchmark for this exact work factor. A 14-million-word list is an hour. A
common human password is a minute. Argon2id at any of the OWASP memory
settings moves that attack off the GPU and two or three orders of magnitude
out. The user who overrides the generator is the one paying the price of
PBKDF2's availability, and the page tells them the price is zero.

There is also no writer rule for custom-mode strength. `"password"` is a
conforming archive. The 100,000-iteration floor makes a nonconforming writer
another six times cheaper and still does not matter against 120 bits, which
is why the floor's stated purpose is the right one; it is not a substitute
for a custom-mode floor on the passphrase itself.

Why it matters: version 1 is forever. Custom-plus-PBKDF2, with no minimum
entropy, is a permanent way to put every TOTP secret a person has behind a
password that a single card will finish. The generated default is the only
reason this is not the headline. The format should not also tell implementers
that the KDF is irrelevant once the user has opted out of that default.

What would fix it: retract the sentence. Say that PBKDF2 is the availability
trade, that it is paid in full on the custom path, and that a writer MUST
refuse a custom passphrase below a stated strength, or MUST NOT offer custom
at all. The generator remaining the default is necessary and not sufficient.

**Related to A3, and a disagreement with it.** A3 attacked the same paragraph
on the previous page, put numbers on the custom path, and filed no finding
against the argument. This revision made the claim sharper ("no choice of KDF
changes that") and made custom a labelled, first-class, permanent mode. That
is enough to file it.

### F38: a decryptor can pass the official vector and still be the wrong program

What is wrong: the vector now exercises hyphen removal if, and only if, the
implementer starts from the displayed form rather than from the already
canonical 24 characters printed next to it. It does not exercise:

- lower case, so a Java `String.toUpperCase()` in a Turkish locale, which
  turns the `i` in `oxiv` into `İ`, passes the official vector and fails on
  a real paste of the same passphrase;
- any whitespace, so F33's two readers both pass;
- custom mode at all;
- a wrong passphrase, a tampered ciphertext, a missing AAD, or a truncated
  tag, so the refuse paths are uncertified;
- a payload `secret` that needs padding, or is lower case, or has internal
  spaces, so the "lenient as to form" rule is uncertified.

The document itself names the Turkish `i` and tells implementers to start
from the displayed form because the previous vector certified the hyphen bug.
The new vector does not certify the fix for the next bug of the same shape.

Why it matters: this page's premise is that the vector is how a stranger
checks they got it right. A stranger who got the header-parse and the happy
path right, and who folded with the platform default, will ship. Their reader
will refuse archives at recovery, or accept a payload the never-guess rule
meant to reject. The last time this happened, A3 caught it only because the
published bytes contradicted the page. This time the bytes agree with the
page and still do not pin the algorithm.

What would fix it: keep the current vector, it is correct. Add rows, not
prose: lower-case displayed form; displayed form plus a trailing newline;
displayed form with internal spaces; a `custom` archive whose passphrase is
exactly `hello-world` and must not open under generated canonicalisation;
the same ciphertext with one tag bit flipped, which must refuse; a secret
`gezd gnbv gy3t qojq gezd gnbv gy3t qojq` with optional padding, which must
import. An implementer who reaches all of those bytes cannot be only
accidentally right.

**New relative to A3.** A3 F22 was "the vector contradicts the rule." That is
fixed. A3 F24 asked for typed-form rows. They were not added.

### F39: every attacker-controlled field except `iterations` is unbounded

What is wrong: the document's own reason for the ten-million ceiling is that
an edited header should not be allowed to park a phone on the recovery path
for an hour. The same file can carry a gigabyte of base64 in `ciphertext`,
or in `kdf.salt` before the "not 32 bytes" check runs, or a megabyte of
typed passphrase into PBKDF2. There is no maximum encoded length, no
maximum decoded ciphertext, no maximum passphrase length, no maximum
`accounts` array, no maximum string inside an account. AES-GCM will
authenticate a huge ciphertext before anyone gets to refuse it. PBKDF2 of a
huge custom passphrase is a cheap denial of service on some implementations
that pre-hash on every iteration, which OWASP notes specifically.

Why it matters: this is the recovery path. A hostile or merely corrupted
file should fail fast and name the reason, which is the standard the refuse
list already set. Unbounded decode is how that standard is escaped.

What would fix it: refuse, before any decode or KDF, an archive larger than
a stated byte budget, a base64 field whose encoded length cannot represent
the expected decoded length (salt 44 characters, nonce 16, tag 24), a
ciphertext above a stated decoded maximum, and a passphrase above a stated
UTF-8 byte maximum. Those are reader rules. They change no archive a
conforming writer produces.

**New relative to A3.** A3 F26 asked for the iterations ceiling. This
revision added it and did not apply its own rationale anywhere else.

### F40: the iteration bounds are not pinned to version 1, so "opens forever" is not quite a guarantee

What is wrong: writers use 600,000. Readers accept 100,000 to 10,000,000.
The page says iterations are read from the file "so an archive written today
still opens when the recommended count rises." That is true of a new reader
facing an old 600,000-iteration file. It is not true of a new writer facing
an old reader if the writer count is raised above ten million, and it is
not true of a future well-meaning reader that raises the floor above
600,000. Either change, applied in the name of this same paragraph, makes a
version 1 archive unopenable. The versioning section never says the v1
bounds are frozen.

Why it matters: "Version 1 archives must open forever" is the reason this
review exists. A floor bump in 2030, shipped as a security fix, would be
the most plausible way to break it.

What would fix it: state that version 1 readers MUST keep this floor and
this ceiling, that a higher writer count requires a new version, and that
a v2 reader opening a v1 file uses the v1 bounds.

**New relative to A3.**

### F41: missing and mistyped header fields are not in the refuse list

What is wrong: the refuse list names wrong values for `format`,
`passphrase`, the two algorithm strings, the three lengths, and the
iteration range. It does not name a missing `passphrase`, a
`passphrase` of the wrong JSON type, `iterations` as a string or a
non-integer, a missing `ciphertext`, or invalid base64. Payload unknown
fields are ignored, and the versioning section says readers ignore what
they do not know, but the container never says that extra keys are
ignored rather than refused. A reader that defaults a missing
`passphrase` to `generated`, which is the path a boolean check written
against `"custom"` takes, applies the wrong rule to a custom archive
and locks it.

Why it matters: the new mode field only works if everyone treats absence
and garbage the same way. Defaulting is the subtly-wrong reading the
prompt asked about: the decryptor appears to work on the official
vector, which has every field present and well typed, and fails on a
file a stricter reader would have named a reason for.

What would fix it: refuse, by name, a missing required field, a field of
the wrong JSON type, and a non-integer `iterations`. State that unknown
container keys are ignored, matching the payload rule and the versioning
rule.

**Related to A3 F27**, which asked for algorithm and length refusal.
Those landed. The remaining holes are the ones the new field created
and the types the list never mentioned.

### F42: the test-vector passphrase is a published password

What is wrong: `YZTR-THFW-WT6E-OXIV-73XD-QCDM`, the salt `00…1f`, and
the derived key are in this document, on the public internet. Nothing
says a real archive MUST NOT use them. A user who copies the example,
or a writer who copies the vector's salt "for now," produces a file
whose key is already computed.

Why it matters: one PBKDF2, not 2^120 of them. The previous example was
replaced because it was not in the alphabet. The replacement is a real
generated passphrase in every respect except that the whole world knows
it.

What would fix it: one sentence next to the vector, that these values
are fixtures, that a writer MUST draw salt and nonce from the CSPRNG,
and that a writer MUST refuse this passphrase. The existing "real
archives generate both from the system CSPRNG" sentence almost does
the salt half and does not do the passphrase half.

**New relative to A3.**

## The unencrypted export

The section is marked non-normative and defers the Aegis version pin to
PR 16, which is what A3 F30 asked for. Nothing here can be implemented,
and the page says so. That is acceptable for a holding paragraph.

Two things it still claims more than it can back, neither worth a
numbered finding against a non-normative section. "The app's copy is
deleted as soon as the share sheet completes" does not delete the copy
the share target kept, or the one the user saved to Files, and the
share sheet's completion handler is not a reliable destructor. "The
strongest file protection class iOS offers" is `NSFileProtectionComplete`,
which does not apply while the device is unlocked and the user is
exporting. The warning text the paragraph requires is the part that
matters; the lifecycle story should not sound more closed than iOS is.

## Versioning, after A3's repairs

The additive rule, the "new enum values are additive" sentence, and the
obligation on every future version to bind its own format string as AAD
are all present and correct. Version 1 archives open forever if, and
only if, v2 readers keep a v1 implementation and nobody raises the v1
iteration floor. The second half is F40. The rest of this section
yielded nothing.

## Prior A3 findings, read after the above was written

A3 reviewed an earlier page, at `a14d255`. On `b8b5889` those findings
stand as follows. This is a status check, not a second review of them.

| A3 | Status on this page |
| --- | --- |
| F22 vector derived from the hyphenated passphrase | Fixed. The published key is the stripped one. Verified above. |
| F23 example passphrase contained `8` and `9` | Fixed. The current example is in the RFC 4648 alphabet. |
| F24 passphrase entry unspecified | Replaced by a specified algorithm and a mode field. The algorithm is F33/F34; the field is F35/F36. |
| F25 writer rules buried in the vector caveat | Fixed. There is a writing-an-archive section. |
| F26 floor justification wrong, no ceiling | Fixed. The implicit-authentication rationale and the ten-million ceiling are both on the page. |
| F27 no refusal of algorithms and lengths | Fixed. They are in the refuse list. |
| F28 claimed the archive hid its account count | Fixed. The page now says the length reveals the approximate count. |
| F29 Unicode lockout on custom passphrases | Fixed. Warning plus optional NFC/NFD retry. |
| F30 Aegis export unspecified | Marked non-normative, as asked. |
| F31 versioning omitted AAD and enum rules | Fixed. Both sentences are there. |
| F32 payload edge cases | Fixed. The "cases an implementer would otherwise have to guess" list is there. |

A3's verdict was that the design could freeze once the vector and the
entry algorithm were repaired. The vector was repaired. The entry
algorithm was written, and it is the part that is not yet freezeable.

## Disposition

| Finding | Severity | Why it blocks a freeze, or does not |
| --- | --- | --- |
| F33 whitespace is not unique | Blocking | Two conforming readers, two keys |
| F34 only `U+002D` is stripped | Blocking | Ordinary paste of a correct passphrase refuses |
| F35 mode field is a lockout bit | Blocking | One cleartext edit bricks recovery |
| F36 mode bit leaks the attack class | Medium | Honesty about leaks; goes away if F35 drops the field |
| F37 KDF-does-not-matter overclaim | High | Makes the weak permanent path sound free |
| F38 vector does not pin the new rules | Blocking | The last vector certified the last bug |
| F39 unbounded attacker-controlled sizes | Medium | Recovery-path DoS, same rationale as the ceiling |
| F40 iteration bounds not frozen for v1 | Medium | The plausible way "forever" fails |
| F41 missing and mistyped fields | Medium | Defaulting the new field is a silent wrong reading |
| F42 published vector passphrase | Low | One sentence |

Housekeeping, unnumbered. The "Verified independently" paragraph is now
true of the bytes; this review is a third check, with no shared code.
CryptoKit still has no PBKDF2, so the day an implementation lands,
`SECURITY.md`'s "All cryptography comes from CryptoKit" becomes false,
which A3 already noted.

The bottom line restated: do not freeze this. The construction can be
frozen. The passphrase-entry rules cannot, not as written, not with
one happy-path vector, not with a header bit that can throw away the
only copy. Tighten the generated-mode alphabet to "keep Base32, drop
everything else," make the mode field a hint or delete it, say that
custom-plus-PBKDF2 is the expensive trade rather than a free one, and
extend the vector until a wrong reader cannot hide. Then the format
is fit to become permanent.

## Sources consulted

- This page, `docs/BACKUP_FORMAT.md` at `b8b5889`, and nothing else in
  the repository, until the findings were written. Then
  `docs/audits/A3.md`, only to mark novelty.
- RFC 4648 §4 and §6, already cited by the document: standard base64
  with padding; Base32 alphabet `A–Z` and `2–7`.
- OWASP Password Storage Cheat Sheet,
  cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html,
  fetched 2026-08-15: PBKDF2-HMAC-SHA256 remains 600,000 iterations;
  Argon2id remains the preferred password hash.
- Unicode White_Space, UAX #44 PropList, as the definition the page
  does not pick.
- Apple documentation for `CharacterSet.whitespaces` (general category
  `Zs` plus `U+0009`, and not newlines) and empirical behaviour of
  `Character.isWhitespace` and `CharacterSet.whitespaces` on the
  current macOS SDK, 2026-08-15, including that they disagree on
  `U+200B`.
- Empirical verification, 2026-08-15: PBKDF2 and AES-256-GCM in Python
  3.9 `hashlib` + pycryptodome, and independently in Node 26's OpenSSL
  binding. Key, plaintext, ciphertext, and tag agreed pairwise with
  the published vector and with each other. The scripts were not
  committed.
- Published hashcat-class figures for PBKDF2-HMAC-SHA256 at 600,000
  iterations on an RTX 4090, used only as order of magnitude under
  F37, not as a bench of this machine.
