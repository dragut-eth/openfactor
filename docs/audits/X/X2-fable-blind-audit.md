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

**Confirmed. Addressed.**

`VaultUnlockView` and `ImportView` took the two credentials that outrank everything else, the vault
passphrase and the backup passphrase, in a `TextField`. `ManualSetupView` took the per-account
secret in a `SecureField` behind a reveal toggle, and its comment gave the reason: a plain field
"can reach the keyboard's learning, which is a copy of the secret in a place nobody audits". The
argument was applied to the smaller secret and not the larger ones. `.textContentType(.password)`
additionally offered to save the vault passphrase into iCloud Keychain, beside the wrapped record
it opens.

**What was changed.** Both fields are now `SecureField` behind the same reveal the manual secret
field uses, capture aware, so neither will show its contents while the screen is being recorded and
the eye is disabled rather than hidden so the reason is visible. `.textContentType(.password)` is
gone in favour of `.oneTimeCode`, which suppresses the AutoFill offer that put the passphrase
next to the record it opens.

**The old reasoning was not wrong, and the reveal is what retires it.** Both fields carried a
comment arguing that these are 24 machine generated characters copied off a card, that hiding them
means a mistyped character cannot be seen, and that this is the one string where the app has
already admitted it cannot tell a typo from a wrong passphrase. That argument stands on its own.
What it did not account for is that the same screen can offer both, exactly as the manual secret
field had been doing since round two of an earlier gate. The defect was never the visibility. It
was that one screen had solved this and two had not.

**The class is closed rather than the two instances.** Every secret bearing input in the app is now
masked with a reveal, `.textContentType(.password)` appears nowhere, and the plain fields that
remain are issuer names, account names, the HOTP counter and the typed erase confirmation, none of
which is a secret.

**One consequence, seen on hardware before it was accepted.** A `SecureField` has no vertical axis,
so the hidden state is a single scrolling line where the old field wrapped to two, and the box
changes height when the eye is tapped. Judged on a simulator against the real screens and accepted.

**What has no test.** The toggle is view state, and this project's rule is that anything a screen
owes belongs in a view model test. The security relevant half is not the toggle but the refusal to
reveal while the screen is captured, and that is guaranteed by the code reading correctly and by
nothing else. `ManualSetupView` has carried the same gap since it was written, so this is not new,
but it is now three screens rather than one.

## OF-A2, low: a Keychain writer can steer the owner into destroying their own vault

**Confirmed, and the best finding in the report. Addressed as far as it is going to be, with the rest recorded.**

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

**Decided, 2026-09-03: the anchor is not being built, and the reason is recorded rather than the
task being left open.** It cannot help the report's headline scenario, a replacement phone, which
has no anchor and can make no claim; that case is covered by the ceiling and the message above, and
by nothing else. What it would detect is a substituted record on a device that lost its key file
but kept its container, a state nobody could name a realistic path to. Against that, it is a new
persistent file, a write inside `unlock`, a decision table and three messages, for a finding the
report rated Low. That is the second decimal place, and the design is written into
`docs/VAULT.md`'s tripwire section with its reopening condition: a device ever showing a vanished or
substituted record on hardware, or a passphrase change screen shipping, which forces the S1-33 and
E12 work regardless.

## OF-A3, low: losing the wrapped record on a working device is silent

**Confirmed. Addressed by detection alone, and the anchor turned out not to be needed for it.**

`Vault.state()` answers `.open` as soon as a key file exists and never asks whether a wrapped
record still exists. No caller checks, on a provisioned device, that `candidates()` is non-empty.
So a device can keep generating codes for months while the record that would let its owner recover
is gone, and the person is holding a passphrase that opens nothing.

**The anchor the report proposed is not needed to detect this, and finding that out is what
closed it.** On an iPhone a vault key can only have come from `create`, which writes a record, or
from `unlock`, which opened one. So a key with no wrapped record under either sync flag is not
ambiguous: the record existed and is gone. The key file is the anchor. `Vault.recoveryRecordIsMissing`
asks exactly that, in two calls that already existed, and a read that fails answers `false`, for the
same reason `State.unavailable` refuses to guess: a warning that fires on a transient Keychain error
is one people learn to ignore.

**What was changed: detect and point, nothing more.** Settings asks the question whenever it
refreshes and, when the answer is yes, shows one line in the Sync section, in the slot the sync
failure already uses:

> The recovery record for your vault is missing from the Keychain. This iPhone keeps working, but
> your passphrase would not open your accounts on a new device. Make an encrypted export now, and
> check your other devices.

It offers no button. The moment it offered one it would be the passphrase replacement screen,
`prepareReplacementPassphrase` and `replacePassphrase(with:)` are built and tested but deliberately
have no interface, and giving them one voids the premise of the S1-33 waiver. That decision is left
exactly where `docs/VAULT.md` keeps it, with E12's compare and swap token as the named mechanism if
it is ever reopened. The export is two rows down on the same screen, which is why the line can
point rather than act.

**A test pins all four states** without a Keychain: no key, key and record, key and no record, and
a failed read. Only the third is `true`.

**Not shown on hardware.** A simulator's Keychain cannot be edited from outside, so the line was
reviewed with the flag forced in a throwaway build, reverted before commit, the same way the OF-A4
refusal was. Reaching it honestly needs a device whose wrapped record has actually gone, which is
the event this exists to catch and not one worth manufacturing on a real vault.

## OF-A4, low: no-passcode devices skip identity confirmation and the promised warning does not exist

**Confirmed. Addressed, and the project departs from the recommendation in both directions.**

`AppLockAvailability.authenticate` returns `true` when no passcode is set. Its own comment says
**"The caller warns instead. Decided with Xavier during PR 16 planning."** Neither caller warns.
`docs/MASVS.md` downgrades MASVS-AUTH-3 to partial on the strength of a mitigation that was never
built, and the comment has been vouching for it since.

**The decision was real and only half of it was implemented.** That is the finding, and it is the
repository testifying against itself.

**What was changed: the false claim, and nothing else.** The comment no longer says a caller warns,
and it records that the behaviour is unchanged and why the decision is still open. Removing a claim
is not the same as fixing what it claimed, and doing only the first is deliberate here: the second
is a policy question below.

**Where the report is wrong, and it matters because it points at the wrong document.** It says a
reader "of the comment, or of MASVS.md" believes the person is told. `docs/MASVS.md` never claimed
that. It downgrades MASVS-AUTH-3 to partial precisely because a sensitive operation carries no
additional authentication on such a device, and it says so in those words. The false claim lived in
the source comment alone, and the document a reviewer would check was right all along.

**One real defect was found while checking that, which the report did not see.** The MASVS row
cited `OpenFactor/Lock/AppLockController.swift:141` for the reasoning. Line 141 is now a debug
`defer` block; the reasoning moved to line 238 when the App Lock fix landed in August. A line number
in a document is a claim with a short life, and this was the only one in `docs/`. It now cites
`AppLockAvailability.authenticate` by name, which cannot drift.

**Where this project disagrees with the recommendation, and what was decided.** The report frames
the whole thing as one choice: build the warning, or delete the sentence. It is two questions, and
they got opposite answers.

**Export and the Settings erase keep the current behaviour, with no warning added.** The original
reasoning holds and the decision was reaffirmed: refusing would deny somebody a backup, or the
ability to wipe a phone they are selling, on a device already open to anyone holding it. No
sentence was added either. Somebody running an iPhone with no passcode has been told what that
means by the operating system, and this app's job is not to repeat it.

**"Start over" on the unlock screen is now refused outright when no passcode is set.** The button
is disabled and the footer says to set one. That reverses the PR 16 decision for this one action.

**The distinction that decided it is worth keeping, because it is not "destructive actions get
more gates".** On export, the identity check guards data the holder can already read: they are in
front of an unlocked phone with the app open, and the prompt delays them rather than stopping them.
On this screen the device has no key, so whoever is holding it cannot read a single account, and
the check is the only thing preventing an action they otherwise cannot perform at all. It is also
the one action in the app that reaches devices that are not in the room, since it removes the
accounts from iCloud and therefore from the other iPhone and the watch.

**The cost was accepted with its eyes open.** Somebody with no passcode who has genuinely lost
their vault passphrase cannot reset the app from inside it, and must set a passcode first. That is
a real imposition on a small number of people, and the remedy is thirty seconds in Settings.

**This branch cannot be tested on a simulator**, which is a limitation worth recording rather than
discovering twice: simulators always report that device authentication is available, so
`canEvaluatePolicy` returns true and the refusal never renders. It was reviewed by forcing the flag
false in a throwaway build, and reaching it honestly needs a physical iPhone with no passcode.

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

**Confirmed. Addressed, with the hardware half still unmeasured.**

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

**What was changed.** `VaultKeyStore.load` now throws `unreadable` instead of returning `nil` for
a file that is present and cannot be read, and `WatchVaultModel.refreshAndAsk` returns without
asking when it sees that. Everything else is untouched.

**No phone path changed, and that is the point rather than an accident.** Every caller on the
phone reads through `try?` and still sees `nil`, so the fold the report describes remains in force
where it was reasoned for: the gate reads `locked`, the passphrase re-derives the same key and
overwrites the file, and the state heals on the path the interface offers anyway. The single call
site the fold was wrong for is the one that turns `nil` into a request for the vault key.

**Returning without asking is the whole remedy.** `refreshAndAsk` runs on every wrist raise and on
a button, so "try again later" arrives by itself and costs the owner nothing. The alternative,
surfacing the failure on the watch, would report a fault for something that is usually a moment.

**A test covers the distinction**, using file permissions, because that is the reachable way to
make a real file unreadable in a test. The case that actually happens is the `.complete` class key
not being available for a moment after a wrist raise, which no test on any host can produce.

**Still true, and still recorded: the end to end path cannot be exercised in a simulator.** What is
covered here is that `load` tells the two apart and that phone callers are unaffected. That a
genuine transient read failure on a watch no longer raises a prompt on the phone is reasoned, not
measured, and it joins the provisioning items this project already lists as unproven on hardware.

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
