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

**The honest limit, stated up front: R3 holds only while the process lives.** If iOS
terminates the app while the person is away, every draft is gone, because the only cure is
writing half-typed secrets and passphrases to disk and this design will not. iOS shows the
same snapshot either way, so the person cannot be promised anything about what they will
find; what they can be promised is that the app never *chose* to discard their work.

## Why the shipped arrangement cannot deliver R3

The shipped lock swaps the root view: `LockScreenView` replaces the whole interface. That
was a deliberate fix for an older bug, a frame of the account list leaking at every locked
launch, and it has a property that was invisible until the vault added screens people type
into: **replacing the root destroys everything beneath it.**

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
phase.

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

**Bounds, unchanged from PR 16c:** inbox items older than ten minutes are swept unread,
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
   blank. Repeat several times; this is B3 and one leak is a failure.
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
