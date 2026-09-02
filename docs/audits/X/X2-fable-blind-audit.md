# X2: a second blind, unscoped audit of the whole repository

**This is not gate A5**, for the same reason X1 was not: A5 is the diff since `audit-a4`, run
before each release, and it still wants doing. This was a cold pass over the entire repository at
one commit by a reader with no brief from this project and no sight of `docs/audits/`.

**Audited commit:** `c1c0e7b4c33edbb52fb93336b4be80628a3d4f0e`, 2026-08-29.
**Reviewer:** Claude Fable 5.1, with a read-only checkout, told not to modify anything.
**Reported:** 2026-09-01.

## The prompt, verbatim

X1's prompt, changed only where it names a checkout path and with one line added asking the
reviewer to record the commit. Kept comparable on purpose: two reports against the same
instructions are worth more than two reports against two.

> checkout https://github.com/dragut-eth/openfactor.git, in this directory: /tmp/x2-audit
> readonly
>
> Record the commit hash you audited.
>
> Perform an independent security audit of this repository. Start by reading the README and
> security/design documentation to understand the claimed security properties, then inspect the
> actual implementation, entitlements, and tests and try to falsify those claims. Do not assume
> the documentation is correct. Do not read docs/audits/ until you have completed and written down
> your own findings, to avoid being biased by previous reviews. Report each finding with severity,
> affected code, reasoning, and a concrete attack or failure scenario where possible. Also report
> important security claims you were able to verify and claims you could not verify. Do not modify
> any files.

**A clean clone rather than this working directory**, deliberately. The working directory is the
repository plus everything `/assets/` holds, which is gitignored precisely because it must not be
public. An auditor whose report is destined for this directory should see what a stranger sees and
nothing else.

## The independence caveat, which belongs at the top rather than in a footnote

**This reviewer shares a model family with the assistant that wrote parts of this codebase**,
including the image bound in `QRDecoder` added eight days earlier, which the report verified as a
strength and raised nothing about. That may well be correct. It is also exactly where correlated
authorship would hide, and a reader comparing X1 and X2 should know that X1's reviewer was from a
different lineage and X2's was not.

**This makes X2 a weaker independence claim than X1 and a stronger technical one.** It reproduced
all four published vectors from scratch, checked the AEAD bindings one at a time, and ran the core
suite. Take the verification section as the more valuable half, and discount the silences.

## Result

**No critical or high findings**, the second consecutive cold pass to say so. Four Low and four
Informational.

**All eight were confirmed against the source before being accepted, and none was withdrawn.**
That is the second consecutive report from a cold reader with no false positives.

**Seven of the eight are one defect wearing different clothes**: the code and the documents
disagree, and they disagree in the direction that is worse for the user. A comment promising a
warning nobody built; a normative "at no other time" that the import path violates; a CI step whose
name claims more than the check proves; an "Immediately" with a gap in it. This project has now
found that shape six times from three directions in August, and a cold reader found six more of it
in one pass.

## OF-A1, low: passphrase fields are plain text with password AutoFill

**Confirmed. Open.**

`VaultUnlockView` and `ImportView` take the two credentials that outrank everything else, the vault
passphrase and the backup passphrase, in a `TextField`. `ManualSetupView` takes the per-account
secret in a `SecureField` behind a reveal toggle, and its comment gives the reason: a plain field
"can reach the keyboard's learning, which is a copy of the secret in a place nobody audits". The
argument was applied to the smaller secret and not the larger ones. `.textContentType(.password)`
additionally offers to save the vault passphrase into iCloud Keychain, beside the wrapped record
it opens.

**Open because the fix is user facing and has a layout question inside it.** The reveal pattern
already exists and is better than the report knew: it is capture aware, so nothing reveals while
the screen is being recorded, and it already uses `.oneTimeCode`. But `VaultUnlockView`'s field is
`axis: .vertical` and a `SecureField` has no vertical axis, so a 24 character grouped passphrase
that currently wraps as it is typed would not. That is a design decision, not a swap.

## OF-A2, low: a Keychain writer can steer the owner into destroying their own vault

**Confirmed, and the best finding in the report. Partly addressed.**

`SECURITY.md` and `docs/VAULT.md` already concede that a same-team sibling can delete or replay
Keychain items and that the container tripwire is unbuilt. What no document described is that the
sibling does not have to delete anything. A substituted wrapped record is indistinguishable from
the real one, the unlock screen then blames the person's typing, and the only exit from that screen
is "Start over", which erases every account from every device on the Apple Account.

**The composition is the finding.** Both halves were accepted risks. Nobody had written down that
together they make the app's own recovery advice into the deletion mechanism.

**What was changed, part one: the ceiling.** `WrappedVaultKey.iterationRange` was
`100_000...10_000_000` and is now `100_000...2_000_000`. `unlock` tries every candidate record it
can see, so a planted record could demand ten million PBKDF2 rounds per attempt on the recovery
path, where the delay reads as a mistyped passphrase.

**That number was the archive's, arrived at by copying rather than by reasoning**, and the two
records are not alike. An archive is an interchange format whose bounds `BACKUP_FORMAT.md` freezes
for version 1, so narrowing it would mean this build had stopped implementing version 1. The
wrapped record is written only by this app, never leaves the Apple Account, and has never carried
anything but 600,000. The remaining headroom exists so a future build raising the write count does
not produce records this one refuses. A test pins both ceilings and the gap between them.

**What was changed, part two: the sentence.** The unlock failure now splits on whether this device
holds a vault key. No key keeps the old text, because on a fresh install a typo really is the
likeliest cause. A key present gets a different sentence, because that device opened these accounts
before, and it points at another device rather than at "Start over".

**What is still open: the anchor**, and it is open for a reason rather than for want of time. The
report proposes a container resident record that a vault exists here plus a digest of the last
wrapped record this device wrote or accepted, and it is right that this is the first half of the
tripwire `docs/VAULT.md` already calls for.

**The difficulty nobody in the exchange raised is that the anchor is per device and the record is
shared.** Every legitimate rewrap from another device makes every other device's anchor mismatch,
so the mechanism cannot say "this was tampered with", only "this is not the record this device last
saw", which is equally true of a passphrase change made on the phone while the watch was in a
drawer. Two constraints follow and both have to be designed in rather than discovered: the wording
must inform rather than accuse, and the anchor must update on every successful unwrap so a device
warns once and then heals. Otherwise it becomes a warning people learn to dismiss, which this
project already reasoned about for the screenshot alert.

## OF-A3, low: losing the wrapped record on a working device is silent

**Confirmed. Open, and joined to OF-A2.**

`Vault.state()` answers `.open` as soon as a key file exists and never asks whether a wrapped
record still exists. No caller checks, on a provisioned device, that `candidates()` is non-empty.
So a device can keep generating codes for months while the record that would let its owner recover
is gone, and the person is holding a passphrase that opens nothing.

**The reviewer's own follow-up observation is adopted: this is the same fix as OF-A2.** One anchor
answers both questions, because a device that knows a record used to exist can notice that it does
not any more.

**The detection is shared; the remediation is not**, which is why they stay separate entries. A2
needs a sentence and a non-destructive exit. A3 needs a persistent warning and a way to write a
fresh record, and `prepareReplacementPassphrase` and `replacePassphrase(with:)` are built and
tested but deliberately have no interface. Giving them one voids the premise of the S1-33 waiver,
so that decision has to be revisited and recorded before any such screen ships. The mechanism
`docs/VAULT.md` names for it is the compare and swap token measured in E12.

## OF-A4, low: no-passcode devices skip identity confirmation and the promised warning does not exist

**Confirmed. Open, and the project departs from the recommendation.**

`AppLockAvailability.authenticate` returns `true` when no passcode is set. Its own comment says
**"The caller warns instead. Decided with Xavier during PR 16 planning."** Neither caller warns.
`docs/MASVS.md` downgrades MASVS-AUTH-3 to partial on the strength of a mitigation that was never
built, and the comment has been vouching for it since.

**The decision was real and only half of it was implemented.** That is the finding, and it is the
repository testifying against itself.

**Where this project disagrees with the recommendation.** The report frames the whole thing as one
choice: build the warning, or delete the sentence and let `MASVS.md` carry the truth. That is right
for **export**, where the original reasoning holds: refusing would deny somebody a backup, or the
ability to wipe a phone they are selling, on a device already open to anyone holding it.

**It is not right for the locked screen's "Start over".** That action erases every account from
every device on the Apple Account, it is reachable before unlocking, and on a passcode-less phone
it currently runs with no identity check at all. The proportionate answer there is a gate rather
than a sentence, and the screen's own footer already says the action is irreversible across
devices. Splitting A4 into an export half and a Start-over half is a policy change to a decision
made in PR 16, so it waits on an explicit call rather than being folded into a wording fix.

## OF-A5, informational: import preview decrypts every stored secret

**Confirmed. Addressed as documentation; the code is unchanged and that is deliberate.**

`ImportViewModel.classify` opens every stored secret to match incoming accounts against existing
ones, and it runs before anybody has confirmed an import: choosing any file, scanning any transfer
code, or receiving an `otpauth-migration://` URL is enough. `docs/VAULT.md` said the secret's
plaintext appears when a code is generated "and at no other time". `SecretStore` says there is
deliberately no call that returns every account with its secret "because the interface never needs
one".

**The claim was wrong, not the code.** Matching on the secret is what makes a re-enrolment a
different account and a rename the same one, which is the behaviour the preview exists to provide.
`VAULT.md` now names all the places a secret is opened in bulk, including this one, and says that
it runs before confirmation.

**The report's alternative is better than the documentation fix and is not being taken yet.**
Sealing a keyed fingerprint of the secret into the metadata half at write time would let duplicate
detection compare fingerprints and open no secret at all. That is a format change to the record,
which is a larger thing than the finding, and it belongs to a version that is changing the record
for other reasons.

## OF-A6, informational: App Lock "Immediately" does not cover inactive-only excursions

**Confirmed. Addressed as documentation; the lock is unchanged, deliberately.**

Time away is counted from `appDidBackground` alone. Control Centre, Notification Centre, the
switcher without choosing another app, a call banner and the Face ID sheet all leave the scene
inactive without backgrounding it, so no lock decision is made on return however long the excursion
lasted. The preference's comment said zero "means any time away at all", which was more than the
code does.

**Where this project disagrees with the recommendation.** The report offers arming the timer on
resignation as well, or rewording. This takes the rewording, for two reasons that are worth stating
rather than implying.

The exposure is bounded rather than open: the cover hides the interface throughout such an
excursion, and the device's own auto-lock backgrounds the app, so any phone that locks itself
closes the window. And this is the code where three separately reasoned fixes were each wrong
before a device trace settled it, where a `CATransaction.flush()` on the wrong side introduced a
second leak, and where two tests had been asserting the bug as a requirement. Arming on resignation
would also add a Face ID prompt after every Face ID sheet. Changing that machinery to close a gap
the cover already covers is a bad trade at this distance from the last incident.

`docs/APP_LOCK.md` and the preference now describe the gap, name the excursions, and record why it
is not being closed.

## OF-A7, informational: "cannot reach the Keychain" is overstated

**Confirmed. Addressed.**

An extension with no `keychain-access-groups` still gets the default group derived from its bundle
identifier, and on iOS the declared app group doubles as a Keychain access group. The property that
actually holds is that the extension cannot reach `<TEAMID>.dev.openfactor.shared`, where the
accounts live. The app writes to neither of the groups the extension can use, so nothing was ever
exposed.

**Only the sentence was wrong, and it was wrong in the two places an auditor is told to look**: the
name of the CI step that enforces the entitlement, and the comment in the entitlements file that
invites the check. `VERIFYING.md` has carried the accurate version all along, which is the useful
detail: the project already knew, in the document written for people verifying claims, and the
stronger sentence survived everywhere else.

The CI step is now "The share extension has no Keychain access group", and both comments say what
the extension can and cannot reach.

## OF-A8, informational: an unreadable vault key file becomes "no key"

**Confirmed. Open.**

`VaultKeyStore` folds `BoundedFile.ReadError.unreadable` into `nil`, exhaustively and on purpose,
so a future error case has to be classified rather than silently becoming "no key". The fold is
reasoned for the phone, where the passphrase path re-derives and overwrites.

**On the watch it means something else.** A `nil` key makes the watch request provisioning, and the
phone raises a "Set up your Apple Watch?" alert over whatever is on screen. So a transient read
failure, the `.complete` class key not yet available for a moment after a wrist unlock, or an
`EACCES` during a container move, is indistinguishable from a watch that was never provisioned, and
the owner is asked to release the vault key. The key goes to the genuine watch, so this is not a
leak. It is a consent prompt raised for a request the design did not intend, on the one exchange
the documents call load bearing.

**Open.** The fix the report proposes, distinct results for missing and unreadable with the watch
treating unreadable as "try again later", is right and small. It touches the provisioning path,
which is the one thing in this project that cannot be tested end to end in a simulator, so it wants
a hardware pass rather than a quick edit.

## What the audit verified

Reproduced here because, as with X1, it is more useful than the findings, and because this reviewer
did more of it than X1 did.

Recomputed from scratch in independent code: the `OFV1` and `OFK1` records and both archive
vectors, PBKDF2 keys via `hashlib`, every AES-GCM open via the `cryptography` package, including
both halves of the 324 byte account vector, with the metadata half correctly refused under the
secret half's AAD.

Checked one at a time: account halves domain separated by tag and UUID; the wrapped record binding
salt and iteration count as AAD; the watch exchange binding version, nonce and both public keys
into HKDF info and AEAD AAD, with the nonce compared before any derivation and a fresh P-256 key
per attempt on each side; the single derivation rule for the wrapped record, so the key commitment
problem the archive solves by parsing does not arise there.

Checked at source and configuration level: no third party dependencies, no `Package.resolved`, no
remote package references; the vault key written only into Application Support under a directory
excluded from backup before any key bytes exist, at complete protection, never into the Keychain or
an app group or a queued transfer; Keychain items carrying ciphertext with a UUID account and a
constant service, `kSecAttrGeneric` never written; every archive refusal happening before
derivation and in the documented order; untrusted input bounded before allocation everywhere,
`BoundedFile` using `O_NOFOLLOW` and `fstat`, the inbox working through a directory descriptor with
non-recursive `unlinkat`, images bounded in pixels and downsampled, the protobuf reader capping
varints and refusing groups; the share extension holding one entitlement and carrying bytes without
decoding them; multiple scenes off and no background modes; DEBUG-only tooling structurally inside
`#if DEBUG`; the erase gates requiring the typed word then identity; the passphrase clipboard copy
local-only with a two minute expiry; every live code surface masking under capture and both
passphrase screens withholding and warning; App Lock failing closed when the passcode is removed
under an enabled lock; `replacePassphrase` having no caller, so the S1-33 waiver's premise holds at
this commit; and the provenance record naming a commit that is an ancestor of the audited one.

**And the core suite: 466 tests in 41 suites at the audited commit, run and passing.** The
count is 467 after this entry's own changes, which added one test for the ceiling in OF-A2.

## What it could not verify

Every hardware measurement the confidentiality boundary rests on: E1, E4, E5, E6, E14 and E15. It
had no device, and it says so rather than reasoning around it.

The rogue counterpart direction of WatchConnectivity routing, which this project already records as
load bearing and shipped unproven. The reviewer agreed with that characterisation and added the
observation that OF-A2 style substitutions do not need it.

That complete protection is genuinely applied to `vault.key`, and that backup exclusion survives a
restore or Quick Start. The macOS test host cannot observe either, which the project states.

The hosted Keychain tests and the CI binary symbol check, both of which need Xcode and a simulator.
The canonical hashes, which need the exact toolchain and a device target. What iOS learns from a
`.password` field, which is the empirical half of OF-A1 and was reasoned rather than measured.
iCloud Keychain conflict resolution for a twin pair of wrapped records, and HOTP counter behaviour
with two writing phones, which is the two-writer case this project has listed as untested since A2.
And the correspondence between the App Store binary and this source, which cannot be checked on
stock iOS.

## What this cost and what it caught

**A ceiling that was seventeen times higher than anything this app has ever written**, a recovery
screen that blamed the user for an attack, four documents that claimed more than the code does, and
two silent failure modes on the paths people reach only when something has already gone wrong.

**The two-writer case is now named by three consecutive reviews as unmeasured**, and the hardware
to close it exists: two iPhones and a watch. It has outlived its excuse.
