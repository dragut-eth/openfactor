# App Lock, and resuming where you left

**PR 15b. Written before the code, after the code went wrong.** PR 15 shipped a lock that
works and is tested; a first attempt at this design was then built in an afternoon, shipped
three defects to the maintainer's phone, regressed the one property the lock exists for, and
was reverted the same day. This page exists so the second attempt is an implementation of a
reviewed design rather than another afternoon of guessing, which is the same discipline
`docs/VAULT.md` and `docs/BACKUP_FORMAT.md` follow and for the same reason.

This document is normative. Where the code and this page disagree, the page is correct and
the code is a defect.

## What the lock is, honestly

A gate in front of the interface, not encryption. The secrets are protected by the vault and
the device Keychain whether the lock is on or off, and the scenario the lock defends is
exactly one: someone holding the phone while it is unlocked. `SECURITY.md` words this
carefully and nothing here implies more.

**The default configuration is the weakest one, and the two halves of that belong in one
sentence.** The lock is **off unless somebody turns it on**, and the app switcher can still show
an issuer and an account name for roughly a sixth of a second on the zoom out from the home
screen, measured in PR 15b and **accepted rather than fixed**. Neither is a defect alone: the
lock is not the confidentiality boundary, and the cache is brief and carries no code. Together
they mean the posture somebody gets without touching a setting is the one with the least in
front of it. A person deciding whether to turn the lock on is entitled to read that as one
thought instead of assembling it from two documents.

## The goal

Stated by Xavier as the ideal, and adopted as requirements:

- **R1, covered.** While locked, nothing sensitive is visible. The lock covers everything,
  including open sheets, which is why it cannot be an ordinary SwiftUI overlay: sheets
  present above those.
- **R2, blank snapshot.** The app switcher photograph never contains a code, an account
  name, or any interface. This already holds today and must survive unchanged.
  **R1 and R2 both assume one window scene.** The lock and the cover are single windows, so a
  second scene would have neither; multiple scenes are declared off in `OpenFactor-Info.plist`
  and CI enforces it. Supporting multiple windows means making both per scene first.
- **R3, resume exactly.** Leave the app at any point, come back past the grace period,
  unlock, and continue mid-sentence: same screen, same sheets, same navigation, same
  half-typed text. Like a native Apple app.
- **R4, clean transitions.** No frame of the screen that was left, no black flash, no
  visible swap. The sequence is: switcher, lock screen already in place, Face ID, the
  interface exactly as it was.
- **R5, arrivals win.** If a share, an opened file, or a scanned code arrived in the
  meantime, it takes precedence: whatever was open closes, and the import or add flow
  presents clean from the root.

  **Precedence includes another arrival: the newest one wins, in both directions.** A link
  opened while a shared image is waiting supersedes it, and the superseded share is removed from
  the inbox rather than left there. A share made while a link is open presents as soon as the
  link is dismissed, because the dismissal is itself a trigger to look; without that the rule
  would hold in one direction only and a deliberate share could wait unseen for an unrelated
  event. Two reviews filed the older version of this as a defect, and a queue holding two
  was built in answer; it produced two findings of its own in a file no test can reach, and it
  needed this page to carry an exception to its own rule. The queue is gone. What a person does
  is tap the newest thing, a superseded arrival costs a repeated gesture rather than an account,
  and against an app sending links repeatedly this is the safer rule, because first-wins lets
  whatever arrives first block a genuine share until it is dismissed.

**The honest limit, stated up front: R3 holds only while the process lives.** If iOS
terminates the app while the person is away, every draft is gone, because the only cure is
writing half-typed secrets and passphrases to disk and this design will not. iOS shows the
same snapshot either way, so the person cannot be promised anything about what they will
find; what they can be promised is that the app never *chose* to discard their work.

## Why the arrangement before this one could not deliver R3

**Historical, and kept because the reason still constrains the design.** Before the design
below, the lock swapped the root view: `LockScreenView` replaced the whole interface. That was a
deliberate fix for an older bug, a frame of the account list leaking at every locked launch, and
it had a property that was invisible until the vault added screens people type into: **replacing
the root destroys everything beneath it.**

## This file is the only description of the mechanism

**Nine sentences across six files once described it, three correction passes fixed six of them,
and three were still wrong afterwards**, including a pass that was about these sentences. Every
correction had been a partial sweep of a set nobody had enumerated, which is what a description
repeated in every dependent file guarantees.

So the mechanism is described here and nowhere else. **A file that depends on it states its own
local consequence and points here**, in the same shape the flag-and-class pairing rule was
collapsed to one function after it drifted across five sites.

Four casualties were found in the field, in one day, all the same bug:

1. The generated vault passphrase, while its owner was in a notes app writing it down.
2. A shared transfer image, collected and then destroyed with the view that held it.
3. A half-typed secret in manual entry, left to copy the key from an email.
4. The export flow's backup passphrase and acknowledgement.

Two were fixed by moving state above the lock, and that pattern works, but it taxes every
future screen with remembering it. The fix for the class is to stop destroying the tree.

## The design: three surfaces, one pure core

### Cold launch, locked: the root is the lock

Unchanged from PR 15. When the process starts locked there is no state to preserve, so the
lock screen **is** the root, exactly as shipped. Two scars justify keeping this path:

- The frame leak: whatever renders first is what the person sees first, so at launch the
  lock must be the root rather than arrive above it.
- The orientation latch: a window created during a locked cold launch, mid transition, was
  measured drawing the lock screen sideways. Windows are only ever created while the app is
  settled and active.

Unlocking from a cold lock swaps the root to the interface, freshly built. One-time, no
state existed, shipped behavior.

### Lock on return: a window above everything

When a running app locks, nothing is torn down. The lock is a `UIWindow` above the
interface, the same mechanism the snapshot cover already uses, at a level above sheets and
alerts. The view tree underneath survives untouched, which is the whole of R3: every screen,
sheet, navigation stack and text field keeps its state because nothing happened to it.

### The snapshot cover: unchanged obligations

The cover exists for R2 and its rules do not change: it appears whenever the app leaves the
foreground unlocked, so the photograph is blank. While locked, the lock surface is what the
photograph shows, which is safe and has a button. What changes is only *when* the cover may
appear, specified by the core below, because the first attempt got exactly that wrong.

### The pure core: `AppLockPresentation`

Every defect in the first attempt lived in imperative glue reacting to scene phases. The
project already knows the cure, because `AppLockEngine` is a pure value type precisely so
lock decisions cannot hide bugs. The presentation decisions get the same treatment: a value
type consuming events and exposing three booleans, with the glue reduced to feeding events
in and applying answers out.

**Events**, fed by the app from scene transitions and the unlock controller:

```
launched(lockEnabled:)
willResignActive              the scene left .active
didEnterBackground(at:)
willEnterForeground           background, returning toward the foreground
didBecomeActive(at:, lockEnabled:, gracePeriod:)
promptRaised                  the unlock prompt went up
unlockSucceeded
unlockFailed
```

**State**: `isLocked`, `coldLock` (the current locked spell began at launch), `settling`
(an unlock succeeded and the scene has not settled to active yet), `backgroundedAt`,
`hasPrompted`, and the last phase seen.

**Outputs**, a pure function of state:

```
rootIsLock        = isLocked && coldLock
lockWindowVisible = isLocked && !coldLock
coverVisible      = !isLocked && !settling && lastPhase != .active
```

**Transitions:**

| Event | Effect |
| --- | --- |
| `launched(enabled)` | `isLocked = enabled`, `coldLock = enabled` |
| `willResignActive` | `settling = false` |
| `didEnterBackground` | records the earliest moment, `hasPrompted = false`, `settling = false` |
| `willEnterForeground` | phase bookkeeping only |
| `didBecomeActive` | locks if enabled and elapsed is negative or at least the grace period; **`coldLock` is untouched, in both directions**; always `settling = false`; forgets `backgroundedAt` |
| `promptRaised` | `hasPrompted = true` |
| `unlockSucceeded` | ignored if already unlocked; `isLocked = false`, `coldLock = false`, `settling = (lastPhase == .inactive)` |
| `unlockFailed` | nothing; locked is already correct |

Becoming active only ever adds a lock, never removes one. A negative elapsed time is
indistinguishable from clock tampering and locks, as the engine already does.

**A correction to this table, found in gate A4.** It said `didBecomeActive` sets
`coldLock = false`. The code deliberately does not, the reason is written above
`didBecomeActive`, and `coldLockStaysColdWithoutAnUnlock` pins the behaviour. Since this page
declares that where the code and the page disagree the page is correct and the code is a defect,
anybody obeying it would have "fixed" working code, broken a tested guarantee, and reinstated the
orientation latch this page exists to prevent. The rule stands; this row was wrong.

### Why `settling` exists, and why two events clear it

Face ID runs with the scene inactive, and a successful unlock lands while it still is. At
that moment the naive cover condition holds, locked is false and the scene is not active,
so the first attempt flashed the cover, black in dark mode, between the lock screen and the
interface on every unlock. `settling` suppresses the cover across exactly that gap.

The first attempt's flag was cleared only by later phase events, and if Face ID ever ran
without the scene dipping to inactive, nothing cleared it, and the **next** departure
silently skipped the cover: the switcher photographed the real interface. That is the R2
regression that ended the first attempt. Here the flag is cleared by **every** departure
event, `willResignActive` and `didEnterBackground`, before the cover decision is read, so a
stale flag can suppress one cosmetic frame but can never suppress the photograph. In the
normal Face ID sequence the resign arrives before the unlock outcome, so the suppression
set by the outcome survives exactly until the scene settles, which is the one window it is
for.

**Settling is keyed on the scene standing at inactive, never merely "not active".** The
first cut of the implementation wrote the looser condition, and the adversarial review this
document requires found the sequence that turns the difference into a leak before the build
reached a phone: an unlock landing after the app has already reached the background, a
biometric match racing a swipe home. The loose condition suppressed the cover and hid the
lock window with the app photographable and nothing behind it, and held that state through
the entire return transit. A background unlock has no Face ID gap to bridge, so it covers
like any other departure. A second unlock outcome is ignored outright, because two prompts
can be in flight and only the first may move state.

## Required regression sequences

Each is a unit test against the pure core before any interface work starts. The first three
are the first attempt's defects, kept as tests so they cannot return.

1. **The frame leak, B1.** Glue invariant, tested by hand: on a locked return, no frame of
   the prior screen. The window and its hosting controller are built once and kept, hidden
   rather than torn down; the first attempt rebuilt the content per lock and the first
   frame after unhiding rendered the interface beneath.
2. **The black flash, B2.** `locked → promptRaised → willResignActive → unlockSucceeded`:
   cover stays hidden through the inactive gap; `didBecomeActive` reaches the steady state.
3. **The snapshot leak, B3.** `locked → promptRaised → unlockSucceeded` with no resign, then
   `willResignActive`: cover **must** show. The stuck-flag sequence, the one that mattered.
4. Cold locked launch: `rootIsLock`, no window, no cover.
5. Locked return: background, foreground, active past grace: window visible, cover not.
6. Return within grace: no lock; cover hidden once active.
7. Clock moved backwards while away: locked.
8. Backgrounding mid-Face-ID, still locked: lock surface remains, cover stays off, the
   photograph is the lock screen. Documented stance, now asserted.
9. Unlock, then immediate background before active: cover shows. `settling` cleared by the
   departure.
10. `locked → promptRaised → willResignActive → didEnterBackground → unlockSucceeded`: the
    cover **must** show at the final step and hold through the return transit. The
    adversarial review's counterexample, found in the first cut before it reached a phone,
    and the reason the review is part of this design rather than a nicety.

**Glue invariants**, stated because the first attempt broke each one:

- Outputs are applied in order: lock window shown **before** the cover hides, so a locked
  return never has a gap between surfaces.
- The lock window is created once, on first use, while the app is active and settled. Never
  at launch.
- The kept lock view cannot re-raise Face ID from `.task`, which fires once per identity,
  so the auto-prompt is driven by the glue when the window becomes visible and
  `shouldAutoPrompt` allows, which is idempotent because the first call marks itself before
  anything awaits.

## Arrivals, and who wins

Three things arrive from outside: an image the share extension left in the group container,
an `otpauth://` or `otpauth-migration://` code from the Camera app or Photos, and a file
opened from Files or Mail. One rule for all three, Xavier's:

> An arrival takes precedence. Whatever was open closes, and the import presents clean from
> the root.

**When an arrival presents.** Only when the scene is active, the app is unlocked, the vault
is open, and nothing else is pending. An arrival that lands while locked **waits**: it is
held above the lock and presents after Face ID clears, never over the lock screen and never
lost to it. Unlocking is itself a trigger to look, because it does not change the scene
phase, and so is the dismissal of whatever was pending.

**"Nothing else is pending" is about presenting, not about precedence.** A link arriving over
an image supersedes it immediately, because a link arrives as an event this app can act on. A
share cannot announce itself, so the app finds it by looking, and looking while a sheet is up
would replace what somebody is reading mid-gesture. It waits for the dismissal instead, which
is the same rule reached by the only route available to it.

**What closing means.** Every presented sheet is dismissed through its presentation
binding: the add sheet, the settings sheet with anything nested inside it, and the edit
sheet. The bindings live above the lock so the app can reach them, which costs a small
hoist of booleans, not of content.

**A consequence to say out loud rather than discover:** an arrival closes the add sheet,
and closing it is a dismissal, and a dismissal discards the draft. Somebody halfway through
typing a secret who shares an image into the app loses the typed half. That is what "takes
precedence, back to root, clean" means, it matches the rule that only the lock preserves
and every deliberate act discards, and the sequence requires deliberately sharing while
mid-entry. Vetoable at review.

**Bounds:** inbox items older than `SharedInbox.staleAfter`, which is ten minutes and is the
same constant that decides whether an item is still worth presenting, are swept unread,
incoming code payloads are capped at eight kilobytes, and everything that is not the two
standard schemes or a file URL is refused.

## State ownership

With the tree surviving, per-screen hoisting stops being how state survives the lock. What
remains above the lock, and why each:

| Owned by the app | Why |
| --- | --- |
| The vault gate model | The passphrase being shown exists nowhere else |
| The pending arrival | Collecting is destructive; the item must outlive any view |
| `AddAccountSession` | Its dismissal-resets semantics; also the arrival's path to closing the add sheet |
| The settings sheet boolean | The arrival's path to closing settings and everything nested |

Nothing else moves. The hoists already shipped stay, because their semantics are about
dismissal versus lock, which is orthogonal to what survives a teardown that no longer
happens.

## What deliberately does not survive

- **Process death.** Drafts die with the process. Nothing half-typed is ever persisted.
- **Deliberate dismissal.** Cancel, swipe-down, and completion discard, exactly as today.
  Only the lock preserves, because only the lock is not the person's decision.

## What the cover cannot reach, measured

**iOS keeps more than one picture of the app, and the cover only reaches one of them.**
Accepted as a known limitation on 2026-08-18, after it was measured rather than argued.

The capture taken at backgrounding, which becomes the app switcher card, is covered and
reliably blank; checklist item 4 is what proves it and it passed every repeat. A second
cache exists, the one iOS uses for the zoom that plays when the app is opened from the home
screen, and it is written at a moment the cover is not up. A screen recording read frame by
frame showed the previous screen, an account's issuer and name legible, from 0.167s to
0.333s of a 2.2 second return, before the lock appeared.

**The evidence that it is not our window ordering** is the frame where the lock screen is
already drawn while that content is still fading out underneath it. Unhiding a window is
not animated, so a lock over our own live view would appear in one frame; a three frame
crossfade is the system dissolving its own snapshot into a live app that was already
locked. Our side was ready before the system finished its transition.

**What was tried.** `ignoreSnapshotOnNextApplicationLaunch()`, which is the only lever
Apple documents over that cache, called on backgrounding while the lock is enabled. It
changed nothing, which matches the general report of it, and it was removed rather than
left in place looking like protection.

**What the record says.** The behavior is documented from iOS 7 onward and still current:
snapshots live in `Library/SplashBoard/Snapshots/` and are known to serve stale content.
Apple's forum thread asking exactly how to cover sensitive interface on inactive versus
backgrounded has no replies, and a closely related thread about an intermittent privacy
blur drew a DTS engineer whose answer was to add logging and bisect. The only community
lever is deleting that directory from inside the container, which its own author frames as
a development time flag for a different bug, is reported as partial, and cannot stop iOS
from capturing a fresh one immediately.

**The exposure, stated plainly rather than minimized.** Roughly a sixth of a second of the
last screen, visible only to somebody already holding the phone in the moment before Face
ID challenges them, and nothing durable: the artifact anyone can browse to at leisure, the
switcher card, stays blank. Accepted on that basis.

**One idea remains untried**, for anyone tempted to reopen this: SwiftUI's `scenePhase` can
lag UIKit's own `willResignActive` notification, so raising the cover from the UIKit
notification might beat whatever moment that cache captures. It is speculative, two
speculative fixes were already spent here, and it touches code that has passed its
checklist.

**The recording stays out of this repository.** It shows real accounts. It is evidence, not
an artifact to publish, and no screen capture of a real vault belongs in a public repo.

### Open measurement: do other authenticators leak this too?

**Nobody has measured a peer, and two opposite claims are now on the record with no evidence
behind either.** A reviewer scoring this project wrote that an authenticator which fully blanks
its switcher snapshot has no such window, offering it as something OpenFactor does worse than its
peers. **It named no peer, and it described the wrong artifact**: this app's switcher card does
stay blank, as measured above. What leaks is a transient cache captured during the zoom out
animation, which is drawn by the system from the live layer rather than from the snapshot an app
controls. The maintainer's position is that this is system wide and that no peer does better.

**Both positions are unmeasured, and that is the only honest statement available today.**

**What would settle it**, and it is an afternoon rather than a day: install two or three other
authenticators on a real phone, put a distinctive account in each, and record the zoom out from
the home screen at high frame rate, the way PR 15b did here. Then say what was seen. **If peers
leak the same way, this stops being a deficit and becomes a platform property that belongs in the
threat model.** If they do not, there is a fix somebody has found and this project has not.

**Until that is run, nothing here claims peers do worse**, and no reviewer's claim that they do
better should be accepted either.

### The system lock half is now measured, and it goes against this app

**iOS's per-app Face ID lock removes this exposure completely, and from the first frame.**
Measured in `docs/audits/E/E14-the-system-lock-and-the-switcher.md` with this app's App Lock
switched off: the card carries Apple's own "Face ID Required" placeholder from the moment it starts
to expand, and no account content appears at any point. Sampled at sixty frames a second across the
transition, because the exposure being looked for spans about ten frames at that rate.

**So the honest statement is that the system does this job better than this app can**, and it does
it by replacing the snapshot rather than covering it afterwards. **An app's cover is necessarily a
reaction** to a lifecycle event, and the cache is captured on the system's schedule.

**What follows for this app, and what does not.** The system lock is off until somebody turns it
on, and **this app cannot enable it, prompt for it, or detect it**. The only thing available is to
say it exists, which is a change to the interface rather than to the mechanism. And the lock is a
gate on opening the app: it does nothing about the vault key, which is a separate question with its
own record.

## The switcher leak, found on hardware 2026-08-22

**The report was "the blackout is slow, and sometimes never comes".** It turned out to be two
separate defects and four wrong fixes, and the shape of the wrongness is the useful part.

### What it actually was

**After a Face ID unlock the scene stays inactive for two to three seconds**, with the account list
on screen, before `didBecomeActive` arrives. Leaving in that window produces **no resignation at
all**, because an app that was never active cannot resign. The first signal the app receives is
`didEnterBackground`, which is after the system has taken its photograph. Measured repeatedly: an
unlock at t=42.139 with nothing until background at t=48.507.

**And `settling` suppressed the cover across exactly that window.** It existed to stop a brief
cover flash on every unlock. The window it covered was the window the leak lived in.

### The four attempts that failed, and why each was the wrong shape

1. **Pre-build the cover window.** It was created lazily on the first departure. Real defect, real
   fix, wrong bug: the first departure was never the failing one.
2. **Observe `willResignActiveNotification`.** Sound reasoning, wrong premise. There is no
   resignation to observe when the app was never active.
3. **Observe `didEnterBackgroundNotification`.** The earliest remaining signal, and still after the
   photograph.
4. **Force a synchronous commit with `CATransaction.flush()`.** Correct for raising the cover, and
   **it introduced a second leak** by also forcing the lowering: on a locked return the cover came
   down synchronously while the lock window was still drawing, so the codes showed for as much as
   two and a half seconds before the Face ID prompt.

**All four tried to cover faster. The window cannot be won from behind.**

### What fixed it

**The maintainer tested a peer.** Google Authenticator waits two to three seconds after a Face ID
unlock before showing codes, and was robust where this was not. It is not winning the race. It is
refusing to run it: the content is simply not on screen until the app is active.

So the rule became one invariant, and everything else is a consequence of it:

> **Content is uncovered only when the app is active and unlocked.**

`settling` is deleted. The cover and the lock window are no longer alternatives; the lock window
sits at `.alert + 2` above the cover at `.alert + 1`, so a locked return shows the lock screen with
the cover behind it and nothing can appear if one draws late. `CATransaction.flush()` is kept on
the raise, where there is a deadline, and removed from the lower, where there is not.

### What is left, and what it settles about App Lock

**A brief cover after every unlock, before the codes appear.** That is the two to three second
inactive window, and it is now visible rather than leaked across. Compared side by side on the same
device, **Google Authenticator behaves identically**, which is the useful measurement: a delay that
a team of full time engineers also ships is the platform's, not this app's.

**And that settles something this project had been careful about rather than certain of.** Gate E14
measured that the iOS per-app lock removes switcher exposure **completely, from the first frame**,
because the system draws it before the app is told anything. App Lock is an app racing a deadline
it does not own. This week showed how that race ends even when it is run well: four attempts, a
leak, a second leak introduced by one of the fixes, and a residual delay that the best funded peer
also has.

**So the advice dialog's recommendation is not a nicety.** "For stronger protection, iOS can lock
OpenFactor before it opens" is the accurate ordering, and App Lock is the fallback for people who
will not set the system one. `docs/MASVS.md` and `SECURITY.md` should say so in those terms.

### Two tests were protecting the bug

**`unlockDuringFaceIDGapSuppressesTheCover`** required the cover to stay down across the window,
and **`lockedReturnIsAWindow`** was named *"a window, not the root, and not the cover"*. Both were
green throughout. Both asserted the defect as a requirement.

**A third was green and unreachable.** `departureAfterUnlockAlwaysCovers` calls `willResignActive()`
directly, which is precisely the call the app could not make. The presentation was correct all
along and the delivery was broken, and a suite that only exercises the presentation cannot see the
difference.

### What made it findable

**A DEBUG-only trace of every lock event, readable on the device.** Three rounds of reasoning from
the source produced three different wrong answers; the first trace produced the right one in a
minute. It is in `OpenFactor/Lock/LockTrace.swift`, absent from Release builds, and verified absent
by searching the built Release binary rather than by trusting the `#if DEBUG`.

## The manual checklist

One pass on hardware when the implementation is complete, instead of live iteration. Every
item names its expected result; anything else is a finding.

1. Lock on, grace Immediately. Open manual entry, type into secret and issuer, open
   Advanced, change the algorithm. Switch to Mail, return, unlock. **Expected:** the manual
   screen, all fields intact, Advanced still open, no frame of it before the lock, no black
   flash after Face ID.
2. Same, but from the export passphrase screen with the acknowledgement on. **Expected:**
   same screen, same passphrase, toggle still on.
3. Same, from an open Settings sheet over the list. **Expected:** Settings still open.
4. Unlock, then immediately background and open the app switcher. **Expected:** the card is
   blank. This is B3 and one leak is a failure.

   **Run it with a realistic number of accounts, not three.** The leak found on 2026-08-22 was
   reported only once the list held real ones.

   **Do not wait between the unlock and the switch.** The failure window is the two to three
   seconds after a Face ID unlock, before the scene becomes active. Waiting three seconds passes
   this item while the defect is present, which is how it survived.

   **Force quit between repeats.** "Repeat several times" hid a first-of-process fault once
   already: four clean runs make the outlier read as a fluke rather than as the only honest
   measurement.

   **And repeat it on the locked return**, watching the moment between the app coming forward and
   the Face ID prompt appearing. That is a separate exposure with a separate cause.
5. Lock the phone itself while OpenFactor is foregrounded, unlock the phone. **Expected:**
   OpenFactor locked or not per grace, no leak, no flash.
6. Force quit, relaunch. **Expected:** lock screen as root, then a fresh interface. Drafts
   gone, and that is correct.
7. Share a QR image into OpenFactor while mid-manual-entry, then open the app and unlock.
   **Expected:** the add sheet closed, the import presented clean. The draft is gone, by
   the stated rule.
8. Share while OpenFactor is locked in the background, open, unlock. **Expected:** the
   arrival presents after unlock, never over the lock screen.
9. Scan a setup QR with the Camera app while OpenFactor is locked. **Expected:** same as 8,
   landing on the confirm screen.
10. Face ID cancel, then the button, then succeed. **Expected:** stays locked in between,
    one prompt at a time, no cover flashes.
11. Share a QR image in, wait for the import sheet to appear, and with it on screen open an
    `otpauth://` link from another app. **Expected:** the import closes and the add-account
    screen for the link presents. The share is not added, and is not waiting behind it.
    *(Measured 2026-08-19 on an iPhone 15 Pro against the build that ships, four runs out of
    four: the panel stays up and its contents change from the image's account to the link's.
    Recorded in `docs/audits/E/E11-two-arrivals-of-different-kinds.md`. An earlier four out of four
    was taken against the queue this replaced, which is a different pairing of sheets, and did not
    transfer.)*
12. Share a QR image in, and before opening OpenFactor, open an `otpauth://` link.
    **Expected:** the link presents, and the shared image is gone rather than appearing later.
    Measured 2026-08-19 against the previous rule, where the image was left in the inbox: it
    reappeared on one run in four, which is what decided this. Measured again the same day against
    the current build, where it passed, in `docs/audits/E/E11-two-arrivals-of-different-kinds.md`.

## Invariants

- The vault key, the accounts, and every stored secret are indifferent to the lock. The
  lock is presentation.
- No draft, passphrase, or typed secret is ever written to disk by the lock or for it.
- The app switcher photograph never contains interface content. Every change to the cover's
  conditions must re-run checklist item 4.
- The lock window never holds state of its own beyond the lock screen it draws.
- A locked arrival waits; it is never presented over the lock and never discarded by it.

## What must be proven before implementation

Nothing remains unmeasured. Every mechanism here ran on hardware during the first attempt,
including the failures; the orientation scar and the frame leak are from PR 15's own
record. The risk in this PR is regression, not the unknown, which is why the required
sequences ship as tests before the interface work starts and the checklist runs once at the
end.

## PR 15c: what the app says about locking

**Specified before implementation, and agreed line by line.** PR 15b's entry records what happened
the last time this area was changed without a design. Every string below was reviewed and revised
by Xavier before anything was built.

**Normative. Nothing is built until the text below is agreed**, because the text is most of what
this pull request is. PR 15b's entry records what happened the last time this area was built
without a design: three defects, a regressed snapshot, reverted the same day.

#### What this changes, and what it does not

**No security mechanism changes.** No key wrapping, no change to the vault, no change to what App
Lock does when it is on, no change to when the snapshot cover is raised, and no change to what it
looks like.

**This pull request is four pieces of text**, and the whole of it is that somebody is told the
choice exists rather than left to find it in Settings.

**One piece of state, named because an earlier draft of this section claimed there was none.**
Popup one fires once, which means remembering that it has fired. That is a stored flag and it
should be called one. **It is a different kind of thing from the claim this design refused to
store**: this app sets it, this app reads it, and it cannot quietly become false the way a
self-reported iOS lock would. Nothing else is persisted, and nothing at all is recorded about which
button anybody pressed.

#### The finding this answers

**All three reviewers of gate A4 landed on the same posture**, by three different routes: the lock
is off unless you turn it on, and somebody holding your unlocked phone sees your codes.

**E14 then measured something that changes the honest answer.** iOS's per-app Face ID lock removes
the app switcher exposure completely and from the first frame, which this app's cover cannot do,
because a cover is raised in reaction to a lifecycle event while the system replaces the snapshot
outright. **So the most useful thing this app can do about that attacker is say the system lock
exists.** That is a measurement, not a preference, and it is why two of the four texts below
recommend something this app does not own.

#### The cover stays unconditional, and that was not the first answer

**It is raised exactly as it is today**, for every departure, whatever anybody has turned on. No new
state, no preference, nothing to record.

**A version of this design tied the cover to a choice**, so that somebody using the iOS lock would
not get two covers. It was measured, then argued, then dropped. **The record is kept because the
next reviewer will reach for the same idea.**

**What the measurement found.** The iOS lock does **not** re-arm on a switcher peek: swiping up and
back without leaving the app keeps the card live. In a recording made on 21 August the launch
frames carry Apple's placeholder with its text, while the switcher frames carry a plain black card
with none, which is this app's own cover and not the system's. **The first version of the rule
would have opened that hole itself.**

**What the argument found, and it went the other way.** Reaching that window needs somebody watching
during roughly half a second of transit, and **the same person, one moment earlier, was watching ten
to twenty seconds of the account list at full size**, which this app does not cover and cannot: an
authenticator that hides codes from the person using it is not one. So the transit is a smaller
instance of an exposure the design already accepts on every use, and dropping the cover there would
have been defensible.

**Why it is kept anyway.** Acting on the iOS lock means recording a claim **no API can verify**, and
that claim goes stale silently the moment somebody turns the lock off or replaces a phone. **The
simplification was not worth introducing the only unverifiable state in the design**, and keeping
the cover removes a settings row, a consent flow, and a staleness problem along with it.

**What would reopen it.** An API that lets an app observe the per-app lock, which would make the
rule rest on a fact rather than a claim.

---

### The text, agreed

**Shorter than the first draft**, because the app no longer acts on any of these answers. Nothing
here records a preference or changes behaviour; it is advice, and advice can be brief.

**Every string is final unless something in the app contradicts it.** The place that will is length
on a small screen at an accessibility type size, which is worth checking before these are called
done.

#### 1. The Settings footer, under the App Lock toggle

> **App Lock**
>
> App Lock asks for Face ID, Touch ID, or your passcode before showing codes. Your accounts are
> encrypted whether App Lock is on or off.
>
> For stronger protection, iOS can lock OpenFactor before it opens. Hold the OpenFactor icon on the
> Home Screen and choose Require Face ID.

**When the device has no passcode**, replacing the second paragraph:

> App Lock requires a device passcode. Set one in iOS Settings first.

**An earlier draft added "it is a gate in front of the screen, not encryption".** It was cut as
redundant: the first sentence says what App Lock does and the second says what it is not, and a
third saying the same thing in security language reads as documentation rather than as a footer.

#### 2. Popup one, when the first account is added

**Not at first launch on an empty list.** With nothing stored the sentence is abstract, and a dialog
at that moment is dismissed without being read. It fires the first time this app holds something
worth the question, and once only.

> **Protect your codes**
>
> Your accounts are encrypted, but anyone using your unlocked phone can see your codes.
>
> For stronger protection, iOS can lock OpenFactor before it opens. Or you can use App Lock.

Buttons: **Show Me How**, **Turn On App Lock**, **Not Now**

**"Turn On App Lock" turns App Lock on**, rather than opening Settings to a switch. A button that
named an action and then delivered a screen would be the kind of label this project spends its
effort avoiding. **It is offered only where it can be honoured**: a device with no passcode cannot
authenticate, the settings toggle already refuses there, and on such a device this button is
absent rather than dead.

> **Open, found 2026-08-22 on hardware, deferred to the round after 1.0.** The rule above is
> honoured for one case and not the other. **The dialog is offered without regard to whether App
> Lock is already on**, because the guard reads
> `!isEmpty, !hasOfferedLockAdvice, arrival == nil` and nothing else; `appLockEnabled` reaches
> `LockAdvice` only so the button can set it. Found by setting the lock on a fresh install and
> then adding an account.
>
> **The spec anticipated "cannot be turned on" and not "already on".** Same principle, one case
> further along.
>
> **The dialog should still appear.** Its real advocacy is the iOS system lock, which gate E14
> established is strictly stronger than App Lock because it removes switcher exposure from the
> first frame, and somebody who has already switched App Lock on is exactly who would want that.
> **What is wrong is the button and one sentence**: "Turn On App Lock" should be absent when it is
> already on, the same treatment a passcode-less device gets, and "Or you can use App Lock" reads
> as nonsense to somebody already using it.
>
> **Consequence today: a redundant button, not a dead one.** Tapping it writes a value that is
> already true and closes the dialog. Nothing breaks and nothing looks stuck, which is why this
> did not hold the 1.0 submission.
>
> **No checklist item covered it**, and that is the more useful half. The twelve items exercise
> the lock's behaviour and the advice dialog's interaction with other presentations. None of them
> asks whether the advice is *appropriate* given the settings it is advising about. A thirteenth
> belongs here when this is fixed.

**The title says what the dialog is for rather than what is wrong.** An earlier draft opened with
the exposure itself, which is accurate and reads as an alarm. The fact still appears, one line
down, where it explains the choice instead of announcing a problem.

**"Not Now" is a real answer and nothing is recorded about it.** Choosing it changes nothing about
how the app behaves. The only thing stored is that this dialog has been shown at all, which is the
same whichever button is pressed.

#### 3. Popup two, every time App Lock is switched on in Settings

**Not gated to the first time.** It is a recommendation attached to an action rather than an
onboarding step, and somebody turning the lock on is exactly somebody who cares about this.

> **For stronger protection**
>
> App Lock protects your codes after OpenFactor opens. iOS can also lock OpenFactor before it
> opens.

Buttons: **Show Me How**, **Done**

**The before and after distinction is the whole message**, and it is the shortest true statement of
what the two locks do differently.

**Neither button changes anything.** App Lock stays on down both paths, so the dismissal is "Done"
rather than anything implying a choice. An earlier draft said "Turn On App Lock", which is wrong on
a dialog that only appears because they just did.

#### 4. The instructions sheet, shown by both "Show Me How" buttons

> **Lock OpenFactor with iOS**
>
> 1. Go to the Home Screen and hold the OpenFactor icon.
> 2. Choose **Require Face ID**.
>
> iOS will ask for Face ID or your passcode before OpenFactor opens.

Button: **Done**

**No "I've done it".** The app records nothing and acts on nothing, so there is nothing to confirm.

**Reached through the settings screen's existing single sheet, never a second `.sheet` modifier.**
Two presentations on sibling sections of one `Form` tear each other down: the second takes the
settings sheet with it and drops the person back on the account list. That is recorded at the top
of `SettingsView` because it has happened before, and it happened again in the first build of this
section, which is why it is repeated here where somebody adding a third dialog will meet it.

**From popup one, closing this sheet brings the question back.** Every alert button dismisses its
alert, so "Show Me How" ends the dialog, and without this the person had asked for help, received
it, and landed on the list unable to tell whether anything had been switched on. **Asking for help
is not answering the question.**

**And the question comes back wearing different buttons**, because offering "Show Me How" to
somebody who has just read it is the tell that nobody was listening:

> Buttons on return: **I Did It**, **Turn On App Lock**

**"I Did It" closes and records nothing.** It is an acknowledgement rather than a claim: this app
cannot tell whether the iOS lock was turned on and stores no answer either way. **It replaces "Not
Now" rather than joining it**, because two buttons that do the same thing in different words are
two buttons.

**One sheet, one button label.** Both popups reach this by a button reading **Show Me How**, because
two labels for one destination is the kind of drift that took three passes to clean out of this
feature's documentation.

### What must be proven before implementation

**Honoured before a line is written**, which `docs/VAULT.md` records not happening once already.

1. ~~**Where the double cover actually shows.**~~ **Run on 21 August, and it changed the design.**
   The launch path carries Apple's placeholder only, so this app's cover never appears there. The
   switcher carries this app's cover, because the iOS lock does not re-arm on a peek. That result
   is what the section above is built on.
2. **Four items from the manual checklist, not all of them, and the four are named.** This pull
   request changes no lock behaviour, so most of that list cannot be affected by it. What it does
   add is **two alerts and two sheet paths onto screens the lock sits above**, and this feature's
   whole history is presentations interfering with each other.

   **Item 3**, locking from an open Settings sheet, because Settings now carries an alert that can
   be on screen when the lock arrives. **Run on 22 August against the shipping build: passed.**
   Settings came back open and intact after Face ID, with no flash.

   **Item 6**, force quit and relaunch, **and this was the one expected to fail**. The advice dialog
   fires when the account list stops being empty, with `initial: true`. On a cold locked launch the
   list loads behind the lock window, so the alert may fire underneath it, and if it did **the
   one-time flag would be spent on a dialog nobody saw**.

   **Run on 22 August on an iPhone 15 Pro: passed.** Face ID as root, then a fresh interface with
   the drafts gone. **The dialog did not appear, and on that device it could not have**, because the
   flag was answered there weeks ago, so the run confirms the lock behaviour and says nothing about
   the advice. The advice half is settled below instead.

   **Closed on 22 August, statically, and it did not need hardware.** `hasOffered` is assigned in
   exactly three places, all of them inside button handlers: "I Did It", "Turn On App Lock" and
   "Not Now". Presenting the dialog does not touch it, and neither does the arrival teardown that
   closes it. **So an alert that fires under the lock and is never answered leaves the flag unspent
   and is offered again next launch.** That is what "the flag is spent when somebody answers, not
   when the app asks" was for; the guarantee is structural and a grep proves it.

   **An attempt was made to run it on hardware first, and the attempt is the more useful finding.**
   The state this item describes, App Lock on with the flag unspent, **cannot be reached on a device
   that syncs.** Turning App Lock on requires Settings; Settings is behind the account list; and on
   a fresh install the list is either empty because the vault is locked, in which case
   `VaultUnlockView` is a deliberate dead end with no route to Settings, or populated the instant
   the passphrase is entered, in which case the advice dialog is modal and every one of its buttons
   spends the flag. **The only door out of that dialog that does not spend it is force quitting.**

   So the path requires turning App Lock on while the list is empty *and* Settings is reachable,
   which happens only on a device with no vault to restore. That is a real path, a new user who
   sets up their lock before importing anything, but it is **much narrower than the paragraph above
   implied**, and the prediction was written without checking whether its own precondition was
   reachable.

   **Items 8 and 9**, an arrival presenting after unlock, because there is now another thing
   competing to present at that moment.

   **Item 8 was run and found a real defect, and it took three attempts to fix.** Recorded because
   the two failed attempts were both worse than the bug.

   **What it found.** A share arriving on the same launch as the advice dialog: the dialog flashed
   and **the import never presented at all.** The cause was that PR 15c's alert and sheet were not
   in `somethingElseIsPresented`, the register of presentations an arrival must close. Every other
   presentation on that screen is in it.

   **First attempt, worse.** Enrolling them made the arrival wait for them to close, but
   `sheetDidClose()` is only called from sheet `onDisappear` handlers and **an alert has none**, so
   the arrival would have waited forever and the import would never have presented.

   **Second attempt, also worse.** With that wired, the dialog was opened and then torn down inside
   one update. On hardware it still flashed, still lost the import, **and left SwiftUI's
   presentation state wedged so that Settings would not open afterwards.**

   **What actually works: do not open it, rather than open it and close it.** The dialog is never
   offered while an arrival is pending. The teardown path stays for the reverse ordering, where a
   share lands while the dialog is already up, and only touches those bindings when they are
   actually set, because writing over a binding that is already false is what churns the state.

   **And the flag is spent when somebody answers, not when the app asks**, so an offer that was
   never shown is made again next launch rather than lost.

   **One more thing fell out of it.** The body stopped type checking once it carried six sheets,
   two alerts and a change handler, which fails with no error worth reading. The advice
   presentations are a `LockAdvice` modifier at file scope now, which is better than what was
   committed and happened only because the compiler refused.

   **The list has twelve items, not ten.** An earlier version of this section said ten, copied from
   PR 15b's entry, which was true when it was written and stopped being true when items 11 and 12
   were added out of E11. A count in prose that no longer matches the thing it counts is the drift
   this document exists to prevent, and it happened here.

### Out of scope, named rather than forgotten

**The vault key.** Neither lock changes that it is readable by the process whenever the device is
unlocked. That is the separate finding from gate A4, its remedy is costed in `docs/MASVS.md` under
MASVS-CRYPTO-2, and it is not this pull request.

**The watch**, which holds its own copy of the key after one tap and has no equivalent gate.

**The peer comparison.** Whether other authenticators leak the way this one does with no lock set is
still unmeasured, and the argument about it stays open in `docs/APP_LOCK.md`.

**The cover's appearance, which is where this pull request started.** The black rectangle reads as
a broken app rather than a protected one, and it cannot be picked out of the switcher by looking.
Both are real and both stay. **Painting anything on that window means touching the one thing in
this area that already works**, in a feature whose last unplanned change shipped three defects and
was reverted the same day, and the whole point of keeping the cover unconditional was to avoid
introducing a problem in exchange for tidiness.

**So the complaint that opened this design is the one thing it does not fix**, and that is a
decision rather than an oversight. What the design found on the way is worth more: that the iOS
lock does not re-arm on a peek, that it removes the exposure completely when it does, and that the
app had never once told anybody either fact.

**App Lock's default.** It stays off. PR 15 gave three reasons and none of them has changed; what
changes here is that the choice is surfaced once rather than left buried in Settings.
