# A4 round four, scope 4: what three engines found in the boundaries

Reviewed commit: `1bf4b26`, delivered as checkout `a90dd70`, which differs only in this round's
brief. Round three read `83e5cdd`. The brief is `A4-round-four-scope4.md`.

## The short version

**Two mediums, and the gate's severity goal is broken again.** Scope 4 came into this round with
three open lows and no mediums anywhere in the gate. It leaves with two mediums and twelve open
items.

**One of the two mediums was created by our own fix.** S4-23's remedy, routing the inbox read
through `BoundedFile`, turned a main-actor hang into a fast failure. The hang used to prevent a
`defer` from running. Now it runs.

**`BoundedFile` itself is the strongest change this scope has produced**, and all three engines
attacked the primitive as instructed rather than its callers. None found a defect in it. Fable's
words: one correct primitive genuinely replacing four divergent shapes.

**All three agree last wins is the right rule and none wants the queue back.** Two of the three say
the code does not implement the rule it states.

## S4-32 (medium): a failed take still runs the full sweep

Found by Grok. Verified here, and it is exact.

`InboxOpener.collect` opens with `defer { inbox.sweep() }` and then guards on `take` succeeding.
`sweep()` removes every name in the directory regardless of age. **The `defer` runs on the failure
path too.**

The sequence, which needs only the sibling-with-app-group-access this design already names:

1. The owner shares a transfer QR. The inbox holds one genuine item.
2. A sibling writes a second item that `take` will refuse: a FIFO, or a file one byte over
   `policyBytes`. Its mtime is newer, so `pending()` sorts it first.
3. The app comes forward, unlocked, vault open. `collect` runs.
4. `take` refuses the poison. `try?` becomes `nil`. `collect` returns `nil`.
5. The `defer` fires and deletes **every** name in the inbox, including the genuine QR.
6. The owner sees nothing, and the share is gone.

**Before `BoundedFile`, step 4 hung on the main actor and the `defer` never ran.** The genuine file
survived, and the app was wedged. Closing the hang is what made this reachable. That is the fourth
time in this gate that a fix has produced the next defect, and the first time the causal chain is
this short and this legible.

`sweep()`'s own comment says it runs "after a collection, where taking one item means the rest were
seen and not chosen". **That is false when nothing was taken.**

Grok's remedy is one rule: the full sweep may run only after a successful take.

## S4-33 (medium): the inbox is resolved by pathname, so the directory itself can be substituted

Found by ChatGPT. Verified here as structurally correct, with one caveat recorded below.

`SharedInbox.directory()` builds a URL by appending a component, and every operation on it
(`contentsOfDirectory(atPath:)`, `removeItem(at:)`) resolves that path afresh. **`O_NOFOLLOW` in
`BoundedFile` protects only the final component**, and none of the sweep paths go through
`BoundedFile` at all.

So a sibling that removes `Inbox` and recreates it as a symbolic link redirects the sweep.
`contentsOfDirectory` follows the link, the entries it finds are not names the sweep recognises,
and `removeItem` deletes each one, recursively for directories. **This turns the sibling's reach
from corrupting staging data into making OpenFactor delete a tree of the attacker's choosing.**

**The caveat, which is ours and not the reviewer's.** ChatGPT's worked example targets the app's
own private container, "whose exact path is assumed known". On iOS that path contains a random
UUID that another process does not get to learn, so that particular target is weaker than stated.
The app group container root is knowable, which keeps the finding alive at reduced blast radius.
Worth settling before the fix is scoped.

ChatGPT's remedy: open the directory once with `O_DIRECTORY | O_NOFOLLOW`, verify that descriptor,
and do the enumeration, reads, renames and deletions relative to it with `openat`, `renameat` and
non-recursive `unlinkat`. It notes explicitly that an `lstat` on the pathname followed by the
current Foundation calls would leave a replacement race.

## S4-34 (low): last wins is implemented for URLs and not for shares

Found by Fable and ChatGPT independently. Verified here.

The two entry points are asymmetric. `onOpenURL` sweeps the inbox and replaces `arrival`
unconditionally: a URL always wins. `collectWhatArrived` is guarded by `arrival == nil`: a share
never supersedes what is on screen.

So with a URL sheet up, a deliberately shared QR waits. **And nothing re-runs collection when the
URL is dismissed.** `collectWhatArrived` fires on `scenePhase`, `lock.isLocked` and `gate.stage`,
and dismissing a sheet changes none of them. The share sits until some unrelated event trips a
collection, or until it goes stale.

**That is S4-27's intermittency, reproduced in the opposite ordering, in the build that closed
it.** `docs/APP_LOCK.md` R5 says the newest one wins; for a share arriving after a URL, it does
not, and may never appear at all.

Fable's one-line remedy: re-run `collectWhatArrived()` when `arrival` returns to nil.

Grok reads the same code and calls it a product mismatch rather than a defect, noting the
`collectWhatArrived` comment says the deferral is deliberate. The comment and the normative
document contradict each other, which is S4-38.

## S4-35 (low): a fourth sweep site, added by this round

Found by Fable.

`onOpenURL` now calls `SharedInbox().sweep()`, the unconditional sweep with no age gate at all.
**It is a fourth site racing the extension's atomic write, and the most aggressive of the four.**
If a URL arrives while the extension is mid-write, the sweep deletes the staging temp and the
share fails.

## S4-36 (low): the supersede destroys the only copy of a pending import

Found by ChatGPT. Grok reaches the same case and scores it differently.

After `take`, the inbox copy is gone and `arrival` is OpenFactor's only copy. A URL arriving before
confirmation replaces it and releases the image. If the source cannot produce the QR again, a
one-time display, an AirDrop from a phone that has left, a dynamically generated code, the import
is unrecoverable.

**Nothing in the vault is affected.** All three engines checked this independently and all three
say the same: every deletion path touches only the inbox directory, and the vault key file and the
Keychain records live elsewhere.

- **ChatGPT:** newest-visible is reasonable; newest-destructively-erases-previous is not. Visibility
  and destruction should not be the same decision when any app can deliver the replacing URL. It
  proposes bounded retention of the superseded arrival until the replacement is confirmed.
- **Grok:** real and narrow, and the price of the rule rather than a defect in it. It should stay
  written down, which the checklist now does.
- **Fable:** no unrecoverable loss, because a transfer QR is generated on demand by the source
  authenticator, so superseded always means re-obtainable.

**The disagreement is about how often the source cannot reproduce the image**, which is a factual
question none of the three can settle by reading.

## S4-37 (low): the wedge returns through the sheet swap, and the measurement does not cover it

Found by Fable. This is the sharpest thing in the round.

With the queue gone, a URL arriving over a shown image sheet changes `arrival` from one identity to
another. `AccountListView` presents both through a single `sheet(item:)`, and `arrivalChanged()`
only engages its `canPresentArrival` deferral when a *different kind* of sheet is open. **An
image-to-URL arrival swap bypasses the deferral** and relies on SwiftUI cleanly swapping one sheet
item for another mid-flight, which is exactly the transition this scope has repeatedly found
SwiftUI drops, and which the code's own comment documents as dropped.

If it is dropped, `arrival` stays non-nil with nothing on screen, and `collectWhatArrived` is
blocked for the life of the process. That is the wedge, reachable with no queue at all.

**The hardware measurement does not transfer.** Checklist item 11's own parenthetical says the four
runs of four were taken against the queue this replaced, which is a different sheet pairing. Round
three's record notes that SwiftUI's drop behaviour depends on the specific pairing. **The shipped
behaviour is unverified**, and this is the item to carry to hardware.

## The documentation findings, recorded and not holding the scope open

**S4-38.** `docs/APP_LOCK.md:42` says precedence includes another arrival and the newest one wins.
Line 233 says an arrival presents only when nothing else is pending. **The implementation has both
behaviours, depending on arrival type**, so this is a behavioural contradiction wearing
documentation clothes rather than a prose nit.

**S4-39.** `BoundedFile`'s header says the read "cannot be skipped, raced, or hung". Raced
overstates it: an opened inode can still be mutated while being read, and intermediate path
components can be symlinks. `ReadError.tooLarge` says the bytes past the limit "were never held";
the implementation appends the `limit + 1` byte and then throws. **The header is also organised as
one sentence per round of this gate**, which is the class scope 2 has just been cleaned of.

**S4-40.** `AddAccountSession.swift:4`, `OpenFactorApp.swift:23` and `AccountListView.swift:26`
still explain state ownership in terms of a warm App Lock replacing or unmounting the root; the
normative design is now a window above a surviving tree, with the lock as root only on a cold
launch. `SECURITY.md` still opens with leftovers being swept at launch. `collectWhatArrived`'s
comment reads as the old first-wins rule.

## What was confirmed sound

**`BoundedFile`.** Attacked as the primitive by all three. The off-by-one is right in all three
cases: a file of exactly `limit` is accepted, `limit + 1` is refused, and a much larger file is
read no further than `limit + 1`. The kind check is on the descriptor, so it cannot be raced by a
swap. `O_NONBLOCK` makes the FIFO open return, and `fstat` then rejects it. All four callers pass a
limit that fits what they read.

Two gaps, neither promoted: `BoundedFileTests` does not assert that a file of exactly the limit is
accepted, nor that a much larger file is read no further than the ceiling. And `ceiling = limit + 1`
would trap on `Int.max`, which no caller passes and no input controls.

**The lock, the clipboard, the capture handling and the backup-exclusion failure path.** ChatGPT
found no new defect in any of them. Grok and Fable did not either.

**The queue removal is clean.** No dangling references anywhere in the tree.

## Three engines, three different single rules

All three reject three separate timing guards for the sweep races. **All three propose one rule
instead, and the three rules are different.**

- **Fable:** never remove a file younger than `staleAfter`, measured from that file's own
  attributes read immediately before the removal, unknown names included. It walks back the
  delete-unknown-names-on-sight rule, observing that in a group whose only members are this app's
  own targets, the foreign name being deleted on sight is almost always the extension's own temp.
- **Grok:** the full sweep may run only after a successful take. Stale sweeping continues on
  activation; the full sweep stops being used as "delete everything we did not pick".
- **ChatGPT:** one cross-process transaction. The writer stages and publishes under a shared
  `flock`; collection holds the same lock across snapshot, take and deletion of only that snapshot;
  temporary writes live in a separate directory that ordinary sweeping never targets.

Fable's and Grok's rules each dissolve a different subset. ChatGPT's covers the writer race that
neither of the others addresses, and its directory-descriptor point is orthogonal to all three.
**This is the decision the next block of work turns on**, and it is not a case where picking the
cheapest is obviously right.

## Converging?

**Split, and all three said so in almost the same terms.**

The file-reading dimension has converged and should be considered done. Four shapes became one
correct primitive with tests that fail when the guards are removed.

**The arrival and inbox dimension has not.** It has been rewritten four times: destroy, guard-drop,
queue, last wins. Grok's framing is that the sweep treats a directory another process writes to as
a snapshot, and the remedy is when a full sweep may run rather than a fourth special case. Fable's
is that two single decisions would end the cycle: one collision rule applied symmetrically at both
entry points, and one sweep invariant. ChatGPT's is that the bulk sweep keeps treating a
concurrently mutable pathname as a stable collection.

**Three independent readers, one diagnosis.**

## What was done

### S4-36 is rejected, with the reason

**A superseded arrival is destroyed, and it stays that way.** ChatGPT proposed bounded retention of
the superseded item until the replacement is confirmed. That is refused, and the reasoning is the
maintainer's rather than a reviewer's:

**Sharing two codes at once is a person doing something unusual, not the app doing something
wrong.** The behaviour it costs is a repeated gesture. Holding the superseded item to protect
against it means keeping a transfer QR, which is every secret its owner has in one image, alive in
memory for longer than the design says anything of that kind may live, in order to insure against a
sequence somebody would have to construct on purpose.

Two of the three engines already land near this. Grok calls it the price of the rule rather than a
defect in it, and says the price should stay written down. Fable finds no unrecoverable loss at
all, on the grounds that a transfer QR is generated on demand by the source authenticator.

**What is conceded is the honesty of the claim, not the policy.** ChatGPT is right that "it can be
shared again" is customary rather than guaranteed: a one-time display, or an AirDrop from a phone
that has left, cannot be reproduced. The unrecoverable case is a pending import, never an account,
and it is written down here rather than described as impossible.

### The rest of the class, fixed as one shape

**`sweep` is now two operations because it was always two ideas.** `sweepStale` collects garbage
and decides by age. `sweep(_:)` supersedes a set the caller has already chosen against and decides
by identity. Writing the second as "empty the directory" is what made it delete the arrival that
turned up while the caller was deciding.

- **S4-32.** The supersede moved out of the `defer` and onto the paths where something was
  actually judged: a successful take, or a set the freshness rule rejected. A failed take now
  leaves everything except the item that failed, which `take` removes itself. Reverting it to a
  `defer` reddens `afailedTakeLeavesTheRest`.
- **S4-26 and S4-35.** Both callers pass the identifiers they read. A file written after that
  reading is not in the set and survives. `onOpenURL` supersedes what it just read rather than
  emptying the directory.
- **S4-24.** Each timestamp is read immediately before its own removal, through `fstatat` on the
  directory descriptor, so a file written during a pass is judged by its own clock.
- **S4-25.** The unknown-name deletion is age gated like everything else. **This walks back S4-20,
  which was an accepted finding**, and that is deliberate: `Data.write(options: .atomic)` puts a
  temporary file beside the real one and renames it, and that temporary name is exactly a name
  this app did not write. In a group whose only members are this app's own targets, the foreign
  name being deleted on sight is almost always our own half-finished write. Age still removes a
  genuine leftover on the next pass.
- **S4-34.** Collection re-runs when the arrival clears, so a share made while a link was open
  presents on dismissal instead of waiting for an unrelated event. `docs/APP_LOCK.md` now says
  the rule holds in both directions and why the two directions are reached differently.

### S4-33, done as capability rather than as timing

`InboxDirectory` opens the inbox once with `O_DIRECTORY | O_NOFOLLOW` and does the enumeration, the
timestamps, the reads and the deletions relative to that descriptor. **Deletion is `unlinkat`
without `AT_REMOVEDIR`, so nothing it does can recurse**, whatever it is pointed at. Reads go
through `openat` into the same bounded primitive, which was split so there is still exactly one
implementation of the bounded read.

Dropping `O_NOFOLLOW` from the directory open reddens `aSymlinkedDirectoryIsRefused`, which plants
a file outside the inbox and proves it is still there afterwards.

**The write path is checked rather than bound, and that is stated in the code.** It opens the
directory first and refuses if that fails, which catches a directory already substituted, and does
not catch a substitution made between the check and the write.

**The cross-process lock was refused.** Coordination protects cooperating processes from each
other. The threat here is a hostile sibling, against whom a lock this app holds buys nothing, since
that sibling can delete the files directly. The threat it appears to answer is the one the
directory descriptor actually answers. There is also a lifetime objection: the share extension is
killed at the system's convenience, and a writer that dies holding a lock is a new wedge shape in a
scope that has spent four rounds on wedges.

### The documentation findings

**S4-38.** `docs/APP_LOCK.md` said the newest wins on one page and that an arrival presents only
when nothing else is pending on another. Both are now true and the page says why they are reached
differently: a link arrives as an event, a share has to be found by looking, and looking while a
sheet is up would replace what somebody is reading mid-gesture.

**S4-39.** `BoundedFile` no longer claims the read cannot be raced. It says what `O_NOFOLLOW`
covers, which is the last path component, and points at the descriptor-based read for a caller
whose directory can be substituted. `tooLarge` says the `limit + 1` byte is read and dropped. The
header no longer narrates the gate round by round.

**S4-40.** The three ownership comments now describe the lock as it is: the root on a locked cold
launch, a window above the surviving tree on a warm one. `SECURITY.md` no longer says leftovers are
swept at launch.

### What is not closed

**S4-37 needs a device.** The wedge is not a sweep problem and no test in this repository can
answer it. What has to be watched is an image sheet on screen, a link opened over it, and whether
SwiftUI swaps one sheet item for the other or drops the transition. The four-of-four measurement
recorded against checklist item 11 was taken against the queue that no longer exists, which is a
different sheet pairing, so it does not transfer.

469 core tests pass, the app suite passes, both targets build.
