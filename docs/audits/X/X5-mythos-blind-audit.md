# X5: a fifth blind audit, the first to cover behavior as well as security

**This is not gate A5**, for the same reason X1 to X4 were not. This was a cold pass over the
entire repository at one commit by a reader with no sight of `docs/audits/`.

**Audited commit:** `f35d7c0c11de6fde5a039a255f393a0f502427d6`, the head of `main` on 2026-10-06,
which is 1.1.2 (11) as shipped plus its records. **It is the first blind look at the add screen loop
fix**, and the first audit to run after a defect had passed all four earlier audits.
**Reviewer:** Claude Mythos 5.1, with a read-only checkout, told not to modify anything.
**Reported:** 2026-10-06.

**The lineage caveat, stated up front.** Mythos 5.1 shares its underlying model with Fable 5.1,
which ran X2, and it is the model the maintainer's own sessions have used since 2026-10-06. So this
is X2's family rather than a fifth independent one, and it is kin to the writer of much of the code.
Four independent lineages have already run. This pass was chosen for depth, not independence, and
it was run cold in a separate session, as every X pass has been.

## The prompt, verbatim

**The first X-series prompt to differ from X1's by more than the directory**, in two ways. A
preamble states who is asking and why, added so the reviewer does not hesitate over auditing a
security product. And a second pass asks for a behavior audit, which no earlier reviewer was asked
for: the add screen loop that passed X1 to X4 was not a security defect, and a reviewer working to a
security brief reads past a screen that will not close. The security paragraph is X1's unchanged, so
the five reports stay comparable where they overlap.

> I am Xavier Cany, the author and maintainer of OpenFactor, an open source two factor
> authentication app for iPhone and Apple Watch, published under my own developer account. I am
> asking you to perform a security and behavior audit of my own software, with my full
> authorization, so that defects can be found and fixed before anyone else finds them. The
> repository is public, and every previous audit of it has been published in it. Nothing you find
> will be used against anyone; it will be fixed and recorded.
>
> checkout https://github.com/dragut-eth/openfactor.git, in this directory: /tmp/x5-audit readonly
> Record the commit hash you audited.
> Perform an independent security audit of this repository. Start by reading the README and
> security/design documentation to understand the claimed security properties, then inspect the
> actual implementation, entitlements, and tests and try to falsify those claims. Do not assume
> the documentation is correct. Do not read docs/audits/ until you have completed and written down
> your own findings, to avoid being biased by previous reviews. Report each finding with severity,
> affected code, reasoning, and a concrete attack or failure scenario where possible. Also report
> important security claims you were able to verify and claims you could not verify. Do not modify
> any files.
>
> Then, as a second and separate pass, audit the app's behavior rather than its security. For
> every screen and sheet in the iPhone app and the watch app, list every way a person can arrive
> at it (a button, a shared image, an opened file, a URL scheme, an App Lock return, a cold launch)
> and every way they can leave it (Cancel, dismiss, confirm, a lock, the app being killed). For
> each combination, say what the code does, and report any path where a person can get stuck,
> lose something they typed, see a stale state, trigger a repeated action, or have something saved
> without confirming it. Pay particular attention to how SwiftUI rebuilds views that are already
> presented, and to state held in a view's initializer. Report each finding with the exact
> sequence of actions that reproduces it. Write your findings to /tmp/x5-audit-report.md.

## What is different about this reviewer

**It read everything and tabled it.** Every Swift file in every target, the entitlements, the
plists, CI and the project file, and then every screen and sheet on both devices with every way in
and every way out, 2.2 and 2.3 of its report. It ran the core suite on a scratch copy, 486 tests,
and said plainly what it did not run: the hosted suite, and anything on hardware. **Every finding
carries a basis label**, verified by reading, verified by running, or reasoned, which this record
keeps.

**It found the most of any pass, and the first High.** Thirteen security items, of which two are
Medium, and twenty behavior items. The earlier four passes found between two and eight each. The
difference is the brief, not the reader: the behavior pass found what four security briefs could
not be expected to, and the two Medium security items are also dead ends that a behavior reading
surfaces.

## Result

**Thirty-three items, every one confirmed against the source before being accepted, none
withdrawn.** Five consecutive cold readers, no false positives. Confirmed means the code does what
the report says; the two items the report labels reasoned, S1 and S3, are confirmed by reading and
the mechanism of S3 is the one the maintainer measured on hardware on 2026-10-02.

**Five items this project rates Medium, with the reviewer's own ratings beside them.** The
reviewer used two scales, one per pass; this record uses the project's one.

| ID | Theirs | This project's reading |
| --- | --- | --- |
| B1 | High | Medium: the camera goes deaf on an ordinary path, but Cancel and reopen recovers it and nothing is lost |
| S1 / B2 | Medium / High | Medium: a dead end that only a force quit ends, behind a rare precondition |
| S2 | Medium | Medium: a dead end on the watch in exactly the case the documents claim is handled |
| S3 / B3 | Low / Medium | Medium: the add screen loop's own pattern, in the import screen, decrypting every secret once a second |
| S6 / B6 | Low / Medium | Medium: the stored order is rewritten wrongly and syncs |

**Everything else is Low, Info or documentation**, listed below, and the list is long. **Nothing
has been changed yet.** By the rule agreed for X2's verification round, the five Mediums are in
scope this week and the rest waits for the maintainer's word.

## The five Mediums

### B1: the camera stops reporting after its first payload until the scanner view leaves and returns

**Confirmed by reading.** `CameraScannerView` has a `hasReported` latch so one QR produces one
callback. It is reset only in `viewWillAppear`. `scanAgain()` and `resumeScanning()` return the
view model to `.scanning` without touching it, and neither the "That code could not be used" alert
nor the transfer preview sheet takes the scanner off screen, which the project's own comment relies
on. So after "Try again" on a wrong QR, or after cancelling a transfer preview, the viewfinder is
live and deaf until the add screen is closed and reopened or manual entry is pushed and popped.

**Why Medium and not the reviewer's High.** Nothing is lost and nothing is saved, and the way out
is Cancel. It is still the most likely of the five for a person to hit, since scanning the wrong QR
first is ordinary, and a camera that looks live and does nothing is the kind of failure that gets
an app deleted. **Fix shape:** a reset token on `CameraScannerView` that the view model's two
return-to-scanning paths bump, applied in `updateUIViewController`.

### S1 / B2: App Lock becomes a dead end after the passcode is removed and then set again

**Confirmed by reading.** `requestUnlock()` sets `unlockImpossibleReason` when the device cannot
evaluate the policy. `LockScreenView` draws that reason **instead of** the Unlock button. The only
callers that can clear it are the button, which is now gone, the lock view's `.task`, which ran
once, and the shield's `showLock`, which prompts only when the lock window was hidden, and it never
hid. Setting the passcode again and returning does nothing. `SECURITY.md` says the app fails closed
with an explanation; the explanation tells the person to do the one thing that then does not work.

**Why Medium.** The precondition is removing the device passcode with App Lock on, which is rare,
and a force quit recovers. But it is a dead end with an instruction that lies. **Fix shape:** keep
the Unlock button under the reason, or clear the reason and re-prompt on the next `.active` while it
is set. The engine needs no change.

### S2: a provisioned watch never re-asks after the phone replaces the vault

**Confirmed by reading.** `refreshAndAsk` does the right detection: a key is present, it opens
nothing, and no fresh key has been tried, so it falls through to `ask()`. `ask()` opens with
`guard flow.stage != .ready`, and a watch that was showing accounts a moment ago is `.ready`.
`WatchProvisioningFlow` leaves `.ready` only through a new attempt, which is what the guard refuses.
The list then shows every record as unreadable, filters them, and says "No accounts yet" with the
line about sync being slow, which is wrong on both counts, until watchOS kills the process.

**Why Medium.** The precondition is a vault replacement, an erase and re-create or a Start over on
another device, which is rare. But `docs/VAULT.md` and `docs/UI_SPEC.md` both state this case is
handled, and it is not. **Fix shape:** move the flow out of `.ready` before asking when the key
opens nothing, or drop the `.ready` guard and keep the double-ask rule on `.waiting` alone, with a
flow test for ready, stale key, waiting.

### S3 / B3: the import preview decrypts every stored secret once a second for as long as it is open

**Confirmed by reading, mechanism measured.** Both `ImportView` initializers do their work in the
initializer: `read(url)` or `read(result)` for an arrival, `present(batch)` for a transfer. Each runs
`classify`, which reads every stored secret to build the duplicate map. Both views are presented
from sheet closures on views that redraw every second for their codes, so the initializer runs
every second and SwiftUI discards every model but the first. The same measurement that found the
add screen loop applies: the work is done, then thrown away, once a second, for as long as the
preview, the passphrase screen or the finish screen is up. `docs/VAULT.md` names the import preview
as a place that needs every secret once. `ExportView` has a smaller instance: a passphrase is
generated from the CSPRNG once a second while the export screen is open.

**Why Medium and not the reviewer's Low.** It is the exact pattern that shipped the loop, found two
weeks after the loop was fixed in `AddAccountView` and not generalized. The maintainer's fix on
2026-10-02 touched `AddAccountView` only, and the X4 fix on 2026-09-22 added a case to this very
initializer without seeing the shape. Fifty accounts is fifty Keychain reads and fifty AES-GCM opens
a second with the plaintext allocated and released each time, and for a `.file` arrival a security
scope re-entered and up to 12 MB re-read a second. **Fix shape:** the same as the loop's, do the
one-shot work in `onAppear` behind a `@State` flag, in both `ImportView` initializers and in
`ExportView`.

### S6 / B6: reordering while searching writes the wrong positions to the Keychain

**Confirmed by reading.** `canReorder` is false while searching, but it only hides the toolbar
button. `.onMove` stays attached to the filtered `visibleRows`, and `move` applies its offsets to the
full `rows`, so dragging the one visible row moves a different account and writes a `sortIndex` for
every row that shifted. With an automatic sort order active, `move` first replaces `rows` with the
filtered subset until the next load. The written positions are wrong, persist, and sync. B7 rides
with it: "Done editing" is hidden while searching too, so edit mode cannot be left without clearing
the search.

**Why Medium.** Stored data is changed without consent. It is only the order, and only on a path
that needs edit mode, a search and a drag together. **Fix shape:** leave edit mode when a search
begins, or map filtered offsets to identifiers before moving.

## Low, Info and documentation, logged

**Low, code:**

- **S4 / B4.** An `otpauth://` link from any foreground app closes every sheet, which resets an
  add draft and deletes an unshared export file. The rule is `docs/APP_LOCK.md`'s, written for a
  deliberate share; the trigger set is wider than that page says. Design decision; consider sparing
  an export in `.ready` and an add session with typed text.
- **S5 / B8.** `Vault.state()` folds an unreadable key file into "no key", so a transient read
  failure shows the passphrase screen and tears down whatever was presented. The watch already
  treats one unreadable read as a moment; the phone could return `.unavailable` as the record half
  does. Narrow window, cheap fix.
- **S8 / B5.** Releasing the key to the watch uses `sendMessage` with no error handler; a failed
  send shows nothing on the phone. The watch asks again on the next raise.
- **B7.** Edit mode cannot be left while a search is active. Same fix as S6.
- **B9, B10.** `.nothingToUnlock` moves to the intro screen without clearing the typed passphrase
  or the failure text, so both can reappear later.
- **B11.** Presenting a sheet from an alert button may be dropped, the class this project has
  already recorded. Unverified by the reviewer; two sites.
- **B12.** The sync toggle does one Keychain update per account synchronously in its binding.
- **B13.** A cancelled Face ID on export leaves no message. Arguably correct.
- **B14.** "Done" on the export's Ready screen deletes a backup that was never shared, with no
  confirmation that nothing was saved.
- **B15.** Cancelling during "Deriving the key" leaves up to four derivations running on a
  discarded model.
- **B16.** A failed "Add account" on the confirm screen is silent: the problem alert is attached to
  the scanner, which is not rendered while confirming. A Keychain write failure shows nothing.
  Rare, and the cheapest fix on this list.
- **B17.** Manual entry's period stepper allows 5 to 300; a scanned code may carry 1 to 3600.
- **B20.** The watch list loads on every scene phase, so a read that fails while the wrist is down
  can flash the failure line before `.active` clears it.

**Info:** S9, a sibling-planted non-UUID item survives erase, which the threat model already
allows; S10, `vault.key` is protection-repaired on every read, which is every code, where once per
launch would do; S11, `.oneTimeCode` on the passphrase and secret fields invites SMS-code AutoFill,
already noted in X2; B18, the edit sheet keeps the record it opened with, which is expected; B19,
the watch asks on every raise while unprovisioned, by design.

**Documentation, S12 and S13, every one confirmed:**

- `docs/VAULT.md` and `docs/UI_SPEC.md` say a Release binary "is checked" to contain neither
  debug-only string. Nothing automates it. The CI job that builds Release and runs `nm` could, in
  one line.
- `docs/UI_SPEC.md` says codes are written `localOnly`; they are not, by a recorded decision. It says
  both passphrase fields show what you type; both are secure fields since X2. Its watch table lists
  two messages the watch no longer shows. It says dismissing the phone's alert counts as declining;
  the code deliberately leaves the question pending.
- `docs/APP_LOCK.md`'s ownership table says the app owns the settings sheet boolean; it is `@State`
  on the list.
- `docs/ARCHITECTURE.md` says the shared inbox is swept whole at launch; it is swept by age on every
  phase change.
- **`README.md` says "version 1.0" beside the store link.** Written on 2026-09-16 for the first
  release and not updated for 1.1, 1.1.1 or 1.1.2. This project's own drift rule caught in its own
  README, by a reviewer rather than by the maintainer's sessions.
- **S7.** `SECURITY.md` says App Lock cannot be enabled without a passcode, but its unlocked-device
  section does not say that plaintext export and Settings erase proceed with no identity check on
  such a device. `docs/MASVS.md` records the decision; the threat model should carry one sentence.

## What it verified

The longest verified list of the five, and the first to pin the formats against their documents
byte for byte: the vault record and wrapped key layouts, the archive reader's refusal order, the
watch exchange's transcript binding, the enrollment limits in every parser, the bounded reads at
every file boundary, the inbox lifecycles including X4's, the export file lifecycle, the clipboard
rules, capture masking on every screen, the switcher cover, the erase ordering, the required-reason
APIs, the privacy manifest, and the release script's handling of credentials. Its "also checked and
found sound" list in 2.4 is worth reading on its own.

## What it could not verify

Nothing on hardware; the hosted suite, read but not run; the two UIKit behaviors B1 and S3 rest on,
reasoned from documented platform behavior and this project's own measurement; that Aegis imports
the written vault; that CryptoKit rejects off-curve points beyond the one case the tests pin; the
App Lock manual checklist.

## What this pass says about the four before it

**The brief decides what is found.** Four security briefs, four lineages, zero false positives, and
not one of them reported a dead end, a deaf camera or a draft lost to a link, because none was asked
to. One behavior brief found all of those on its first run. The project's answer to the loop, that
the tests and the audits were looking elsewhere, is now measured rather than argued, and the
behavior pass belongs in the method from here.

**The loop's pattern was still in the tree.** S3 is the same mistake as the loop, in a file the
maintainer's sessions edited on 2026-09-22 and read again on 2026-10-02 while fixing the loop
elsewhere. The fix was applied where the symptom was, and the shape was not searched for. That is
the finding this record most wants kept.

**Nothing has been changed yet.** Analysis and record first; the fixes wait for a decision.
