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

**Everything else is Low, Info or documentation**, listed below, and the list is long. By the rule
agreed for X2's verification round, the five Mediums are in scope this week and the rest waits for
the maintainer's word. **Three of the five are fixed, B1, S3 and S6 with B7 alongside**, in one
batch validated on the maintainer's phone; S1 and S2 follow. See "Fixes" at the end.

## The five Mediums

### B1: the camera stops reporting after its first payload until the scanner view leaves and returns

**Confirmed by reading.** `CameraScannerView` has a `hasReported` latch so one QR produces one
callback. It is reset only in `viewWillAppear`. `scanAgain()` and `resumeScanning()` return the
view model to `.scanning` without touching it, and neither the "That code could not be used" alert
nor the transfer preview sheet takes the scanner off screen, which the project's own comment relies
on. So after "Try again" on a wrong QR, or after canceling a transfer preview, the viewfinder is
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
- **B13.** A canceled Face ID on export leaves no message. Arguably correct.
- **B14.** "Done" on the export's Ready screen deletes a backup that was never shared, with no
  confirmation that nothing was saved.
- **B15.** Canceling during "Deriving the key" leaves up to four derivations running on a
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

## Fixes, 2026-10-07

**B1, S3 and S6 as one batch**, with B7 closed by S6's change, validated by the maintainer on the
iPhone 15 Pro. Core suite 486, hosted suite on the simulator, both green. Each fix was followed by a
search for its shape elsewhere, which is the lesson S3 records.

- **B1.** A `ScanLatch` type owns the camera's one-report-per-look rule, re-armed by a generation
  number the add screen's view model bumps on "Try again" and on closing a transfer preview. **Not
  a reset on every update**, which the report's first suggestion was: SwiftUI calls the camera's
  update every second under the account list, so that would have reported a held code once a
  second. Tests on the view model's two bumps and on the latch itself. **Shape search:** every
  one-shot flag in the app targets; the others are presentation toggles, intended one-time flags,
  or labels that clear themselves after two seconds.
- **S3.** Both `ImportView` initializers now only record what arrived; the read, the parse and the
  classify run once in `onAppear`, behind a flag kept in `@State`, as the add screen does since the
  loop. **Shape search:** every view initializer in both app targets, listed with any work it does.
  After this change every one only assigns.
  **The export screen's smaller instance is left as it was, deliberately, after a first attempt was
  reverted.** Moving passphrase generation from the initializer to authentication made three
  hosted tests fail, and the reason is the finding: the archive writer checks strength only for a
  custom passphrase, so a generated one is trusted to be non-empty, and that was guaranteed only
  because the initializer always made one. The move created a model state that could reach the
  writer with an empty passphrase. Unreachable from the screen, which reaches the writer only after
  authenticating, but a guarantee had become a precondition. One random passphrase generated and
  discarded each second, touching no secret, is a smaller cost than that. **Logged as a new Low:**
  the writer should refuse an empty passphrase in either mode, which would make the guarantee its
  own and the export fix safe to revisit.
- **S6 and B7.** `move` refuses while a search is active, which is the guard that does not depend on
  the screen. The list detaches its drag handler while searching, and edit mode ends when a search
  begins, which also closes B7. Two tests: a drag during a search changes neither the order nor the
  stored positions, and under an automatic sort it leaves the sort and the full list alone.

**S1, the same day, the smallest change that removes the dead end.** The lock screen shows the
Unlock button under the reason text instead of replacing it with the reason. `requestUnlock` checks
again on every tap, so with a passcode set the reason clears and the prompt appears; without one the
reason stays. Re-prompting on return was considered and declined by the maintainer: it is new logic
in the lock machinery, which has the most history of subtle defects in this project, for an edge case
with no safety consequence. **Shape search:** no other screen replaces its only action with a
message. Core 486 and hosted 1,240 green.

**Not reproduced, and the verification is left to the reviewer's round, by the maintainer's
decision.** The iOS 27 simulator behaves as if a device passcode is always set: with Face ID
unenrolled it still offers the passcode prompt, so the check that fails on a phone without a
passcode never fails there, and the dead end cannot be shown on the simulator. Reproducing it on the
phone means removing its passcode, which was not done.

**An observation from that attempt, recorded and not yet explained.** On the simulator, with App
Lock on: cancel the system passcode prompt, switch to another app, return. The app showed a blank
white screen rather than its lock screen, for several seconds, until it was quit and relaunched. It
may be the simulator's handling of its system passcode sheet, or it may be a second dead end beside
S1. **Checked on the 15 Pro the same day, on `546d230`, and not reproduced:** with App Lock on and
the delay at Immediately, Face ID made to fail and canceled, the home screen, five seconds, and
back, the app showed its lock screen with the Unlock button. **Read here as a simulator artifact,
and that reading was wrong**: see the verification round below, N1. The phone check was a warm lock
and the simulator run was a cold one, and cold versus warm is the variable.

**S2, the same day, without hardware by the maintainer's choice, and failing first.** Reproducing it
on a device means replacing the vault on the only iPhone, which holds the maintainer's real
accounts, and two simulators cannot deliver records to a running watch app. So the decision was
moved where a test can reach it. The watch's "should I ask?" logic left its view model, in a target
no test builds, for `WatchProvisioningFlow.keyRead`, in the core, unchanged, the bug included. Six
tests were written against it and run: **the two describing S2 failed**, a ready watch whose key
opens nothing and a ready watch whose key is gone both refused to ask, and the four pinning what
must not change passed. Then the fix, in the flow: a ready watch leaves `.ready` for `.checking`
before asking. All six pass, the flow suite is 22, the core suite 492, the hosted suite green, and
the watch app compiles for hardware. The watch model's own `ask` still refuses while ready, which is
now correct, since the flow leaves ready first and the Try again button is never drawn there.
**The key-gone case is a widening, stated here**: the report named the stale key only; the same
guard blocked a ready watch whose key file had vanished, and it now asks too, which is what a
watch with no key always does.

**All five Mediums are fixed.** None is shipped. The next step is one verification round by the
reviewer over all five, the export decision, the new Low, and S1's untested state.

## Verification round, 2026-10-07

The same reviewer, a fresh read-only checkout at `a7b967b`, the "Fixes" section opened to it, asked
to falsify all five. It ran the core suite, 492, and compiled the lock's presentation logic on its
own with `swiftc` to drive it through a cold lock. It did not build the hosted suite or the watch.

**B1, S3, S6 with B7, and S2 hold**, each checked against every caller and every path back, with no
missed path found. **No change since `f35d7c0` introduced a defect.** Two notes it recorded, neither a
defect: with the unusable QR still in frame, "Try again" reports it again at once, which is what a
scanner that is not deaf does; and the watch model's own `.ready` guard in `ask` is now unreachable.

**The export decision: sound, and the logged Low is narrower than the gap.** Refusing an empty
passphrase closes the case the tests hit. But in generated mode the writer accepts any string at all,
so `write(accounts, passphrase: "abc", mode: .generated)` seals every secret under `ABC`. The mode's
promise is 120 bits from the CSPRNG, and the writer can own it in one line: in generated mode, require
the canonical passphrase to be exactly the generated length. **The Low is widened to that.**
Unreachable from the screen today, for the reason this record already gives.

### N1, medium: on a cold lock, the snapshot cover hides the lock screen

**Confirmed by reading, and by the reviewer's probe.** `AppLockPresentation.coverVisible` is true
whenever the app is active and locked. For a warm lock that is harmless: the lock window sits at
`.alert + 2`, above the cover at `.alert + 1`. **For a cold lock there is no lock window.** The lock
screen is the root view in the app's main window, below the cover, and the cover is opaque
`systemBackground`. So once a cold-locked app becomes active, its own lock screen, lock mark,
message and Unlock button included, is under a blank surface. The cold launch test asserts
"not covered" only before the app becomes active, which is why no test saw it. The doc comment above
the property still says "never while locked, because the lock, root or window, is what belongs in
the photograph", which is what the code did before `4b183ff`.

**Since `4b183ff`, 2026-08-22, so in every shipped version.** Not caused by the S1 fix and not found
by X5. **Surfaced by this project's own simulator observation, which this record then misread as an
artifact.** The phone check that "did not reproduce" it was a warm lock.

**What a person sees.** App Lock on, the app force quit or killed by iOS, then opened: the system
prompt appears over a blank background. Authenticate and everything is normal, which is why months of
daily use never showed it. Cancel the prompt and the app is a blank screen with no button and no
message; leaving and returning does not change it; only a force quit and a successful prompt get out.
**The cold half of S1 is this dead end**, worse than X5 described: no reason text, no button.

**Reproduced on hardware by the maintainer, the same day**, on the 15 Pro with the build of
`546d230`: App Lock on, the app swiped away in the switcher, opened again, Face ID made to fail and
canceled. The blank screen, with no button. In his words, the difference is a cold boot of the app.

**Fix shape, from the reviewer, not yet applied:** leave the cover down while the lock screen is the
root view, since the root lock is itself opaque, safe to photograph, and has its button, which was
the documented stance before `4b183ff`. Two lines in `coverVisible`, the cold launch test extended
past `didBecomeActive`, a sequence test for cancel, home and back, and the manual checklist's force
quit item re-run on the phone with the prompt canceled once.

**Where the round found the record wrong:** the "simulator artifact" reading, and "the variant that
went through another app was not run", where the variable that matters is cold versus warm. Both are
corrected above.

### N1 fixed, 2026-10-07

**`coverVisible` leaves the cover down while the lock screen is the root view**, the reviewer's two
lines, and both comments that described the cover wrongly now say what it does. Failing first: the
cold launch test was extended past `didBecomeActive`, and a new sequence test covers cold start,
prompt canceled, home and back. **Both failed before the fix and pass after.** A third test pins the
protection N1's fix must not undo, the reason the cover exists at all: after a cold unlock, while the
app is still inactive behind the prompt, the interface is on screen and must be covered until the app
is active. It passed before the fix and passes after. The lock presentation suite is 18, all green.

**Shape search:** the cover is driven by `coverVisible` alone, and it can hide something with its own
button in exactly one state, the root lock. A warm lock is a window above the cover; an unlocked
active app has the cover down.

**Validated on the 15 Pro by the maintainer**, the sequence that reproduced it: App Lock on, the app
swiped away, opened, Face ID made to fail and canceled. The lock screen with its Unlock button, and
Unlock brought Face ID back. **This also closes the cold half of S1**: the always-shown button is now
visible on a cold lock too.

**The Low, as widened by the round, stays logged and open:** in generated mode the archive writer
should require the canonical passphrase to be exactly the generated length.

## Closing check, 2026-10-07

The same reviewer, a fresh read-only checkout at `b09bc99`, asked to verify N1's fix and answer three
questions. It compiled `AppLockPresentation` unchanged from that commit and drove it again: the cover
stays down with the root lock up through a cold launch, a canceled prompt, home and back, and goes
up the moment a cold unlock lands while inactive, and in the background-unlock sequence. It found the
three tests assert what this record says and the two comments describe the code, and it confirmed
that the root lock screen, now what the switcher photographs on a cold lock, shows no codes or names.

**Its three answers, quoted and not adopted:** "N1 is closed." "All five X5 Mediums are closed at this
commit", "S1 now for cold locks too." "No change since `f35d7c0` introduced a defect."

**One residual, to measure, not a defect.** The fix moved the cold-unlock path from "cover already up"
to "cover raised at the unlock". The code raises it in the same update as the unlock, inside the two
to three seconds of inactivity the cover exists for, but that is reasoned, not measured, and the
manual checklist's item 4, the switcher card right after an unlock, is the measurement this window has
needed before. **To be re-run from a cold launch on the 15 Pro before 1.1.3 ships**, with the item's
own rules: real accounts, no wait between the unlock and the switcher, a force quit between repeats.

**Re-run by the maintainer the same day, on the build of `b09bc99`, and passed:** every switcher card
was blank, from a cold launch, with his real accounts, opened the instant Face ID succeeded, force
quit between repeats. X5 is closed.

## The tail, 2026-10-07 onward

**The maintainer's call: fix everything before 1.1.3**, since no open item puts a current user at
risk and a complete release beats a quick one.

**The archive writer Low, as widened by the verification round, fixed, failing first.** In generated
mode `BackupArchive.write` now requires the canonical passphrase to be exactly the generated length,
and refuses anything else with a new `notAGeneratedPassphrase`. The test runs four inputs, an empty
string, "abc", a short grouped string and 23 characters: **before the fix the writer sealed a 604 byte
archive with every one of them**, the empty string included, and after it refuses all four. The test
for a real generated passphrase passes both ways. Core 493.

**Documentation drift, corrected:**
- `README.md` no longer carries a version beside the store link, so it cannot drift again.
- `docs/UI_SPEC.md`: codes on the clipboard are not `localOnly`, by the recorded decision, and
  passphrases are; both passphrase fields are masked with a reveal; the watch shows one message for
  every way the phone fails to answer, the one the code shows; and only the alert's two buttons
  answer the watch's question, any other dismissal leaving it pending.
- `docs/APP_LOCK.md`: the settings sheet boolean is removed from the "owned by the app" table, with
  a note that it is `@State` on the list and why that suffices.
- `docs/ARCHITECTURE.md`: the shared inbox is swept by age, ten minutes, on every scene phase change.

**Still open from the documentation items:** S7, one sentence for `SECURITY.md`'s threat model, which
is public and waits for the maintainer's approved wording; and S12, "a Release binary is checked",
which waits for his choice between automating the check and rewording the claim.

**The small behavior batch, B9, B10 and B20, fixed and validated.** Failing first for the two that
tests can reach: a wrong-passphrase message survived onto the setup screen after the record
disappeared (B10), and "There is nothing on this iPhone to unlock" left the typed passphrase in the
field (B9). Both tests failed before the fix and pass after. The gate model now clears a message when
a re-read moves it to a different screen, leaving a message set together with its new screen alone,
and clears the field on that branch. B20: the watch list loads only when the screen is active, so a
read failing while the wrist is down no longer flashes the failure line; the watch target has no
tests, and the device build compiles it. Hosted suite 1,254. Neither B9 nor B10 can be triggered on
one iPhone and B20 is a flash, so the maintainer's pass was that daily use on the phone and the watch
is unchanged, which it is.

**Three items from that batch turned out not small, and are recommended for acceptance, awaiting the
maintainer's word:**
- **S5.** The proposed fix shows "Your vault cannot be read" for an unreadable key file instead of the
  passphrase screen. That screen offers only "Try again" and a restart, so a key file that stays
  unreadable would leave no way in, where today the passphrase screen rewrites the file. A correct
  fix needs the watch's "once is a moment, twice is a state" counter in the gate. The window is
  narrow and the current behavior recovers.
- **B15.** Stopping a derivation on Cancel means making the core's archive reader cancelable between
  its attempts. The cost of not doing it is a few seconds of work finishing on a discarded screen,
  and only a deliberately hostile archive makes it more than one.
- **B16.** Showing a failed "Add account" means moving the error alert, whose title, "That code could
  not be used", is wrong for a save failure. It needs new text, so it joins B14 and S8 for the
  maintainer's review.

**S12, S7, a CI rule, and the changelog, 2026-10-08.**
- **S12.** A step in CI's Release build job searches the built app for five Debug-only strings, from
  the two Debug-only Settings rows, the reset they call, and the lock trace. Run locally with the
  exact command before it was added: none is in the Release build, and all five are in the Debug
  build, so the step can fail. `docs/VAULT.md` and `docs/UI_SPEC.md` now say CI checks it.
- **S7.** `SECURITY.md`'s section on an attacker with an unlocked device now carries the
  maintainer's sentence, verbatim: on an iPhone without a passcode, plaintext export and account
  erasure proceed without an identity check.
- **A CI rule against work in a view's initializer**, `scripts/check-view-initializers.py`, run in the
  style job. It flags a method called on an object the initializer just built, and a newly built
  object stored in a `@Bindable` or `@ObservedObject` property. Checked against the add screen and
  the import screen as they were before their fixes: it flags both. The current tree is clean.
- **`CHANGELOG.md`**, from the release records and the commits between them, 1.0 to 1.1.2 and the
  unreleased 1.1.3.
- **Spelling.** The maintainer asked for American English from 2026-10-03; this record and the
  comments, tests and documents written since then had drifted British in about twenty lines, and
  those lines are corrected. Text he entered himself, and the hash script's output format, are left
  as they are.


**The first CI run of both new checks passed**, on `7e35bf9`: each printed its pass line, "No view
initializer does work on an object it builds." and "No Debug-only strings in the Release build."

**The maintainer's decisions on the rest, 2026-10-09:**

| Item | Decision | Why |
| --- | --- | --- |
| **B17** | Fixed | Manual entry's period stepper now covers the scanner's range, 1 to 3600: 1, then 5, then steps of 5. A code that can be scanned can be typed. Plain steps of 5 from 1 gave 6, 11 and 16; the maintainer saw that on the phone and asked for 1 to go straight to 5, which he then validated on the phone. A test pins the sequence; hosted suite 1,255, core 493. No new text |
| **S4** | Kept, document corrected | `docs/APP_LOCK.md` said the sequence needs a deliberate share. Any foreground app can open an `otpauth://` link; the rule stays, for the reason now written there |
| **B14** | Accepted | "Done" removes the backup file, never the vault. Making it again takes seconds, and every fix considered changes the screen |
| **S8** | Accepted | The watch asks again on the next raise, which is the recovery |
| **S5** | Accepted | For the reason above: the fix as proposed could leave no way in, and today's behavior recovers |
| **B15** | Accepted | For the reason above: a few seconds of work on a discarded screen |
| **S9** | Accepted | Only a sibling app in the access group can plant the item, which the threat model already allows, and it holds none of the person's secrets |
| **S11** | Accepted | `.oneTimeCode` is what stops iOS offering to save the vault passphrase beside the record it opens (X2). Its side effect is a suggestion above the keyboard, which the fields refuse. Removing it is unverified and could bring back what X2 fixed |
| **B18** | Accepted | The edit sheet keeping the record it opened with is how an edit sheet should behave |
| **B19** | Accepted | The watch asking on every raise until it is set up is by design, and is S8's recovery |
| **S10** | Open | The maintainer wants to think it through first |
| **B16** | Open | It needs error text he approves |
