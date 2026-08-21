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

**Added afterwards: the dissent did not go away, and this section should not read as though it
did.** ChatGPT restated the objection in round five and has restated it since, on the same ground
each time: any app can supply the replacing URL, so visibility and destruction should not be one
decision. `A4-round-five-scope4-results.md` carries that in its own words, alongside its
acceptance that the behaviour is now honestly documented as a product trade rather than a false
implementation claim. Grok declined to relitigate and Fable found no unrecoverable loss at all.

**The rejection stands, and it stands as a decision rather than as a consensus.** One reviewer
still disagrees with it, and a reader deciding how much weight to give this section deserves to
know that from the section itself rather than from a later file.

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

**S4-37 was answered on a device, and it is closed.** Four runs out of four on an iPhone 15 Pro
carrying `4b8317f`: the panel stays on screen and its contents change from the image's account to
the link's. The swap does not drop in the pairing that ships. Recorded in
`../E/E11-two-arrivals-of-different-kinds.md`, and checklist item 11 now carries a measurement of the
build it describes rather than of the queue that was removed.

**The fourth run was a variant the tester improvised and it is worth more than the repeat.** The
image was shared and the app was not opened in between, so the link arrived over an item still
sitting uncollected in the inbox. That is checklist item 12 rather than 11, and it exercises
`onOpenURL` superseding a set it just read, which is the path `sweep(_:)` was rewritten for. It
passed on the first attempt.

Four runs is not proof that a race is impossible. The defect this replaced showed at one in four,
so four clean runs is evidence against a fault of that frequency and not against a rarer one.

469 core tests pass, the app suite passes, both targets build.

## Where the scope stands

**Nothing is open.** Both mediums are fixed and mutation tested, the three sweep races carried in
from round three are closed as one shape, the four lows this round added are fixed, S4-36 is
rejected with its reason recorded, and S4-37 is measured. The scope is ready for round five.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

GPT:
Reviewed exact commit 1bf4b2688003521264155a8823d3e64dff121dbb. I did not build or run tests, and the checkout remains clean.
Findings
Medium — Inbox sweeps can escape the App Group through a directory symlink
[SharedInbox.swift (line 292)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:292), also sweep() at line 259.
O_NOFOLLOW in BoundedFile protects only the final path component. Every inbox operation still resolves the attacker-writable Inbox directory by pathname.
Concrete sequence:
A sibling with App Group access removes group.dev.openfactor/Inbox.
It creates Inbox as a symbolic link to OpenFactor’s private container, whose exact path is assumed known.
OpenFactor comes forward and calls sweepStale().
contentsOfDirectory follows the link. Private-container entries such as Library, Documents, and tmp are not UUID names.
Lines 307–308 call removeItem on each. Because those entries are real directories at the end of a symlinked intermediate path, Foundation can recursively remove them.
This expands the sibling’s access from corrupting staging data to making OpenFactor recursively delete its own private container. It can remove Application Support/vault.key, preferences, and other private files. Keychain account records themselves are outside this filesystem and survive, but they become unreadable locally until the vault is recovered—and unrecoverable if the passphrase is unavailable.
Smallest robust fix: open Inbox once with O_DIRECTORY | O_NOFOLLOW, verify that descriptor, and perform enumeration, reads, renames, and deletion relative to it with openat/renameat/unlinkat. Use non-recursive unlinkat for entries. A pathname lstat followed by the current Foundation operations would leave another replacement race.
This is a fourth shape beyond S4-24/25/26: substitution of the directory capability itself.
Low — “Newest arrival wins” is implemented only when the newer arrival is a URL
[OpenFactorApp.swift (line 301)](OpenFactor/OpenFactorApp.swift:301).
Concrete reverse-order sequence:
A URL arrival is currently displayed.
The person subsequently shares image B and opens OpenFactor.
Scene activation invokes collectWhatArrived(), but line 305 refuses while arrival != nil.
Dismissing the URL clears arrival, but no arrival-change handler calls collectWhatArrived; collection is triggered only by scene, lock, or gate changes.
B therefore waits for an unrelated future event or is swept after ten minutes.
The URL-after-share direction is last-wins because onOpenURL explicitly sweeps and replaces. The share-after-URL direction is first-wins. This is the reverse half of S4-27, so the claim that deleting the queue closed the class is incomplete.
Smallest fix: give every arrival an observation time, inspect the inbox even when an arrival is current, and replace only when the staged item is newer. Collection should also run when the current arrival is dismissed. This needs an integration test or reverse-order hardware checklist item; the present checklist tests only URL-after-share.
Low — Destructive last-wins can erase the only recoverable copy of a pending import
[OpenFactorApp.swift (line 253)](OpenFactor/OpenFactorApp.swift:253), [InboxOpener.swift (line 43)](OpenFactor/Import/InboxOpener.swift:43).
Concrete sequence:
The share extension receives a dynamically generated or one-time QR from an NSItemProvider.
OpenFactor collects it. take deletes the inbox file, leaving arrival as OpenFactor’s only copy.
Before confirmation, any app sends a syntactically accepted otpauth:// URL.
onOpenURL replaces arrival; the image Data is released.
The provider’s temporary representation is already gone, and the source app is not required to retain or regenerate that QR.
The statement that an image “can be shared again” is therefore customary, not guaranteed. Saved vault accounts are unaffected, but the pending transfer can be irrecoverable.
I agree that the newest deliberate action should become the visible one. I do not agree that visibility and destruction should be the same decision, particularly when any app may deliver the replacing URL. The hostile-sender argument does not distinguish the policies: an attacker can block under first-wins or continually replace under last-wins.
The smallest safe policy is newest-visible with bounded retention of the superseded arrival until the replacement is confirmed or explicitly dismissed, or a user-visible replacement decision. No secret needs to be persisted to disk.
The three acknowledged sweep races
S4-24, S4-25, and S4-26 affect items still in the App Group staging directory. They cannot directly delete an account already committed to Keychain. After take, the image is in memory; after confirmation, the account is stored outside the inbox.
They should not receive three unrelated timing guards. There is no safe time to assume the extension cannot be writing. The useful invariant is one cross-process transaction:
The writer stages and publishes while holding a shared coordination lock.
Collection holds the same lock across snapshot, take, and deletion of only that snapshot.
Temporary writes live in a separate staging directory and are never targets of normal sweeping.
The observation time is taken after attributes are read.
A new entry not in the snapshot is never deleted by that collection.
A process-shared flock would release automatically after a crash. The stable directory descriptor described in the medium finding remains necessary against a non-cooperating sibling.
BoundedFile
The actual bounded read is correct for all four current callers:
Import: ImportLimits.largestAcceptableBytes
Share extension: the 8 MiB image policy
Shared inbox: the 8 MiB image policy
Vault key: 32 bytes
It opens nonblocking, checks the opened descriptor with fstat, stops after at most limit + 1, and distinguishes exactly-at-limit from one-byte-over. File replacement after opening cannot change which inode is read, and growth or in-place mutation cannot bypass the memory bound. The FIFO hang and final-component symlink cases are closed.
There are two overstatements in [BoundedFile.swift (line 3)](Sources/OpenFactorCore/Import/BoundedFile.swift:3):
“cannot be raced” is broader than reality: an opened regular inode can still be mutated while being read, and intermediate path components can be symlinks.
Line 48 says bytes past the limit “were never held”; the implementation appends the limit + 1 byte before throwing.
Those are comment-only findings. At the current constant limits, the unchecked limit + 1 arithmetic is also safe; the public primitive would trap if a future caller passed Int.max, but no current input controls a limit.
Other false claims
[APP_LOCK.md (line 42)](docs/APP_LOCK.md:42) says one rule applies to all arrivals and the newest wins, while line 233 says an arrival presents only when nothing else is pending. The implementation has both contradictory behaviors depending on arrival type.
[AddAccountSession.swift (line 4)](OpenFactor/Scanning/AddAccountSession.swift:4), [OpenFactorApp.swift (line 23)](OpenFactor/OpenFactorApp.swift:23), and [AccountListView.swift (line 26)](OpenFactor/AccountListView.swift:26) still explain state ownership in terms of a warm App Lock replacing or unmounting the root. The current normative design uses a window above the surviving tree; only a cold launch uses the lock as root.
These documentation/comment defects do not independently hold the scope open.
Verdict
The lock, clipboard, capture handling, backup-exclusion failure path, and core bounded reader are converging. I found no new defect in those mechanisms.
The inbox and arrival area is still moving defects around. Its bulk sweep continues to treat a concurrently mutable pathname as a stable collection, and removing a hardware-verified queue has both reopened destructive loss and failed to implement the replacement rule symmetrically.
My direct answer on the reversal: newest-visible is reasonable; newest-destructively-erases-previous is not. It costs an unfinished draft or pending import, saved vault accounts remain intact, and the claim that every lost import is repeatable is false.

Fable:
Scope 4, round four — the app's boundaries

Verdict. The file-reading rewrite (BoundedFile) is the strongest change this scope has seen: one correct primitive genuinely replacing four divergent shapes, well-tested, closing the pipe-hang, the symlink, the file-kind and stat-then-read holes at once. The reversal to last-wins is a defensible product decision but its implementation does not match the rule it claims, and it re-introduces an unmeasured SwiftUI-swap wedge. The sweep-vs-writer race class is not only still open — this round added a fourth site to it. Crucially, and this is the reassuring half: I found no path by which any sweep or read destroys something unrecoverable, and none that reaches the vault or Keychain. The entire blast radius is the Inbox staging directory, whose only contents are transfer-QR images that still exist in the app that sent them.

I take the round at its word that retracting earlier conclusions is in scope, and I retract nothing from round three except to sharpen it below.

Q5 — the reversal, answered directly

Is last-wins right? As a rule, yes; as shipped, it is only half-built.

The reasoning in the commit and in OpenFactorApp.swift:44-61 is sound: a superseded arrival costs a repeated gesture, not an account (a link re-opens, a transfer QR re-shares); first-wins is genuinely the worse rule against a link-spamming app because it lets the first thing block a genuine share; and the normative page always said an arrival takes precedence. Nothing here is relitigating a settled question — the decision is well-argued and I agree with it.

But the code does not implement "the newest one wins." It implements "a URL supersedes; a share defers." The two entry points are asymmetric:

onOpenURL (:253) calls SharedInbox().sweep() then replaces arrival. A URL always wins, and it destroys any pending inbox share to do so.
collectWhatArrived (:301) is guarded by arrival == nil. A share never supersedes what is on screen; it waits.

So consider the newest arrival actually being a share: a URL sheet is up, the user leaves to another app, shares a transfer QR, and returns. On return scenePhase → active runs sweepStale() (the share is fresh, survives) and collectWhatArrived() (blocked, arrival is the URL). The user dismisses the URL. Nothing re-runs collection — collectWhatArrived fires only on scenePhase, lock.isLocked, and gate.stage changes, and dismissing a sheet changes none of them. The share sits in the inbox and presents only if some unrelated event later trips a collection, exactly the intermittent behaviour the round-three hardware test filed as S4-27 — reproduced here in the opposite ordering, in the build that claims to have closed it. docs/APP_LOCK.md R5 now reads "Precedence includes another arrival: the newest one wins"; for a share arriving after a URL, the newest one does not win and may not appear at all.

What it costs, stated plainly: a share the user deliberately made can silently fail to present, recoverable only by re-sharing. Low severity — recoverable, and the sequence is narrow — but it is a real behavioural gap in the exact mechanism this round is about, not a doc nit. The one-line intent-preserving fix is to re-run collectWhatArrived() when arrival returns to nil (an onChange(of: arrival?.id) in the app, or driving collection from the arrival sheet's dismissal), which is the symmetry the stated rule promises.

Is anything destroyed unrecoverably? No. I checked every deletion path. onOpenURL's sweep(), collect's deferred sweep(), and sweepStale() all operate only on the Inbox subdirectory (SharedInbox.swift:259,281), and take/BoundedFile only ever read from it. The vault key file, the Keychain records, and the wrapped-key record live elsewhere and are untouched by any of it. The inbox by invariant holds only extension-written transfer images, and a transfer QR is generated on demand by the source authenticator — so "superseded" always means "re-obtainable." That is the finding this round asked for, and the answer is that it does not exist here.

Q1/Q2 — BoundedFile, the primitive under four callers

I attacked the primitive rather than the callers, as instructed. It is correct.

Off-by-one: ceiling = limit + 1, the loop stops at data.count == ceiling, and the post-check is data.count <= limit (:79-94). A file of exactly limit bytes reads limit, tries one more, hits EOF, and is accepted; a file of limit+1 fills ceiling and is refused; a file of limit+1000 is read only to ceiling and refused. It never holds more than limit+1 bytes. Correct in all three cases.
The kind check is on the descriptor, not the path: fstat on the opened fd (:76), so it cannot be raced by a swap after the check. O_NONBLOCK makes the FIFO open return instead of hanging (the round-three medium, S4-23), and fstat then rejects S_IFIFO; O_NOFOLLOW rejects a final-component symlink with ELOOP. The pipe test uses a real mkfifo under a one-minute time limit, which is the right way to prove non-blocking.
The four limits all fit what they read: ImportViewModel.read passes largestAcceptableBytes (the archive ceiling — a picked file may legitimately be an OpenFactor archive) :103; ShareViewController.firstImage and SharedInbox.take pass policyBytes (8 MiB — both read images, and the tighter bound is correct, closing round two's "10 MB materialised before the check") :240; VaultKeyStore.load passes keySize (32), then re-checks count == keySize exactly :88,:100. None is wrong, so the single-point-of-failure risk the round flagged does not bite.

Two small things, neither blocking:

O_NOFOLLOW guards only the last path component. An intermediate symlink is still traversed. The inbox path is app-constructed and its parent is the app-group root, so this is not reachable in practice, but the doc comment "a link is a way of naming a file this app did not intend to open" slightly overstates what the flag delivers.
VaultKeyStore.load maps .unreadable to nil (absent) via the catch-all :96-97. A present-but-unreadable key file therefore reads as "no key yet." This is benign because the gate distinguishes locked (ciphertext present) from introducing (nothing present) by record presence, not by this return — so an unreadable key on a device that has records still lands on the unlock screen, not on "create a new vault." Worth a comment; not a defect.
Test coverage gap: BoundedFileTests pins one-byte-past, empty, pipe, directory, symlink, missing — but not "a file of exactly limit is accepted" nor "a file far past the limit is read no further than limit+1." Both hold in my trace; neither is asserted.
Q1 — does each other change address its finding?
Pipe hang (S4-23): closed by the primitive; SharedInbox.take now routes through BoundedFile, and a matching pipe test lives in SharedInboxTests. Confirmed.
Lowercase-UUID name (S4-30): the take path no longer stats-then-reads, but the underlying asymmetry — pending() accepts any string UUID(uuidString:) parses, while take rebuilds the path from id.uuidString (uppercase) — is unchanged. It is now masked rather than fixed: an unknown-cased name misses the ages dictionary and is swept on sight (:307), so the sweep-first ordering on activation usually removes it before collect can trip on it. On the lock.isLocked/gate.stage collection paths, which run no sweep first, a narrow window remains. Low, unchanged from round three.
Header splice (S4-31): the mangled paragraph is repaired and the front-page comment now parses. Good.
Queue removal: clean — no dangling ArrivalQueue references anywhere in the tree, tests and source both gone.
Q2 — did the reversal introduce something new?

Yes: it re-creates the S4-28 wedge, now through a sheet(item:) identity swap, and the hardware measurement offered for it does not cover it.

With the queue gone, a URL arriving over a shown image sheet changes arrival directly from the image identity to the URL identity. AccountListView presents both through the single sheet(item: presentedArrival) (AccountListView.swift:163), and arrivalChanged() only engages its canPresentArrival deferral when another kind of sheet (add/settings/edit/recolour) is open — an image→URL arrival swap bypasses it and relies on SwiftUI cleanly swapping one sheet item for another mid-flight. That is precisely the mid-animation sheet transition this scope has repeatedly found SwiftUI drops, and the code's own canPresentArrival comment (:34-40) documents the drop. If it is dropped here, arrival stays non-nil with nothing on screen and collectWhatArrived is blocked for the life of the process — the wedge, reachable now with no queue at all.

The new checklist item 11 in docs/APP_LOCK.md asserts the expected result for this swap, but its own parenthetical says the 4/4 measurement was taken "against the queue this replaced" — i.e. of the removed dismiss-then-promote path, not of the shipped image→URL swap. Round three's own record notes that SwiftUI's drop behaviour depends on the specific pairing of sheets, so the queue's clean 4/4 cannot be transferred to a different pairing. The shipped behaviour is unverified. Fable's round-three instinct — this is settled on a device, not in the suite — applies unchanged, and this is the item I would carry to hardware before trusting item 11.

The class question — is the sweep-vs-writer race bigger than S4-24/25/26?

It is bigger by one, and the round-four commit is what widened it. onOpenURL now calls SharedInbox().sweep() (:260) — the unconditional sweep, no age gate at all — as a fourth site racing the extension's atomic write. If a URL arrives while the extension is mid-write, sweep() deletes the staging temp (a non-UUID name) and the share write fails. It is the most aggressive of the four sweep sites and the newest.

But the more useful answer is about the shape of the class, and here I can be definite: every member is confined to the staging directory and none can reach accepted data. S4-24 (now captured before attributes), S4-25 (unknown-name-on-sight deleting an atomic temp), S4-26 (deferred sweep() after collection), and the new onOpenURL sweep are one root cause — the sweep treats a concurrently-written directory as a static snapshot and deletes on a listing that is already stale when the removal executes. The remedy is one rule, not three guards, not four: never remove a file younger than staleAfter, measured from that file's own attributes read immediately before the removal, unknown names included. That single invariant collapses all four:

S4-24 dissolves because age is read per-file at delete time, not against a now captured before the listing.
S4-25 and the new onOpenURL race dissolve because an in-progress atomic temp is by definition seconds old and falls under the floor.
S4-26 dissolves because a file that arrived after the snapshot is young and is spared.

The unknown-name-on-sight rule (the S4-20 fix) is the specific thing to walk back: age-gating it, rather than deleting foreign names with zero tolerance, keeps S4-20's intent (a genuinely old leftover is still removed) while removing the atomic-write conflict it created. Given the group group.dev.openfactor has only OpenFactor's own targets as members, the "foreign name" it deletes on sight is almost always the extension's own temp — so the aggressive rule mostly hurts the app it was meant to protect.

Q3 — claims the code does not do (recorded, not blocking, per the scoring note)
docs/APP_LOCK.md R5: "the newest one wins" — false for a share arriving after a URL (Q5 above); this one is behavioural, not merely prose.
SharedInbox.write comment (:117) now openly narrates that "lives for seconds" "survived two rounds after the lifecycle it described stopped being true" — which is honest, but the surrounding sentence still frames the exposure window as "seconds" before conceding it. The exclusion-and-read-back makes the security consequence moot regardless, so this is cosmetic.
The scoring note is right to down-weight these. I did not hunt further; the comment corrections in this file are now doing more narrating of their own history than describing the code, which is the pattern the note exists to stop.
Q4 — converging or moving around?

Split, and the split is the useful answer. The file-reading dimension has converged and should be considered done: four shapes became one correct, well-tested primitive, and its callers pass sane limits. That is consolidation, not churn.

The arrival/inbox dimension has not converged. It has now been rewritten four times — destroy, guard-drop, queue, last-wins — and the fourth rewrite is a sound product decision wrapped around an implementation that (a) is asymmetric, so the rule it states is not the rule it runs; (b) re-introduces the wedge the queue was measured against, now unmeasured; and (c) adds a fourth site to an open race class while three prior sites stay open. This is the area to stop patching shape-by-shape. Two single decisions would end the cycle: one collision rule applied symmetrically at both arrival entry points, and one sweep invariant (age-gate every deletion, per-file, at delete time). Until those land, the next defect in this scope will be another instance of the same two roots — and, as all three engines have now said in three different rounds, the wedge specifically will be found on a device or not at all.

Grok:
Scope 4, round four

Commit: 1bf4b26
Round three read: 83e5cdd
Files read from that commit, not from the later checkout.

───

5. Last wins — answered first

Yes. Last wins is the right rule. Round one and round two treated “the first arrival is destroyed” as a defect because the code had no rule. docs/APP_LOCK.md already had one: an arrival takes precedence and whatever was open closes. The queue was the exception, and it existed only to avoid losing something you can tap or share again. Against a sender that can fire otpauth:// at will, first-wins is the worse security property: the first link occupies the slot and a real share waits behind it. That is the sequence measured on hardware. Last-wins is the same rule the rest of the screen already uses (a new arrival closes settings, the add sheet, a half-typed secret). I would not put the queue back.

What it costs

onOpenURL does two things: SharedInbox().sweep() (the whole directory, every age), then arrival = the new value.

┌────────────────────────────────┬────────────────────────────────┬───────────────────────────────────────────────────────────────────────┐
│ What was pending               │ What happens                   │ Recoverable?                                                          │
├────────────────────────────────┼────────────────────────────────┼───────────────────────────────────────────────────────────────────────┤
│ Unconfirmed .image(Data)       │ Replaced in memory; inbox copy │ Only from the sending app (Messages, Mail, AirDrop source).           │
│ already taken from the inbox   │ was already gone               │ OpenFactor has no second copy. Nothing is in the vault: they had not  │
│                                │                                │ confirmed.                                                            │
├────────────────────────────────┼────────────────────────────────┼───────────────────────────────────────────────────────────────────────┤
│ Uncollected files still in the │ Deleted immediately, including │ Re-share, if the source still has the image                           │
│ inbox                          │ shares never shown             │                                                                       │
├────────────────────────────────┼────────────────────────────────┼───────────────────────────────────────────────────────────────────────┤
│ A previous otpauth://          │ Replaced                       │ Tap the link again                                                    │
├────────────────────────────────┼────────────────────────────────┼───────────────────────────────────────────────────────────────────────┤
│ A file opened from Files/Mail  │ Binding replaced; the system   │ Open the file again                                                   │
│                                │ copy is not in the inbox       │                                                                       │
├────────────────────────────────┼────────────────────────────────┼───────────────────────────────────────────────────────────────────────┤
│ Anything already saved in the  │ Untouched                      │ —                                                                     │
│ vault                          │                                │                                                                       │
└────────────────────────────────┴────────────────────────────────┴───────────────────────────────────────────────────────────────────────┘

The unrecoverable case is real and narrow: a transfer QR shared from a source that no longer holds the image (AirDrop from a phone that has left, a one-time display they did not keep). Last-wins then deletes OpenFactor’s only copy of an import that was never confirmed. That is an import, not an account. I would not call it a defect in the rule. I would call it the price of the rule, and it should stay written down, which checklist items 11 and 12 now do.

The rule is not what two shares do. Collection still requires arrival == nil. A second image shared while the first is on screen does not take the screen; it sits in the inbox until the first is dismissed and some later scene/lock/gate event collects. The comment on collectWhatArrived says that is deliberate: collection is noticing something earlier, not a fresh arrival. APP_LOCK.md R5 describes a link superseding a share, which is what onOpenURL implements. If the product sentence is “the person who shares a second QR means the second one,” the code does not do that until they dismiss and come forward again. That is a product mismatch, not a vault-loss path. A URL arriving in the meantime will sweep that waiting second share. That is last-wins applied to disk, and it is consistent with the decision.

I do not treat S4-7 / S4-15 as still open.

───

Finding — Medium

A failed take still runs collection’s full sweep, so a poison newest item wipes every real share. Round three’s hang fix is what makes this reachable.

Where

• InboxOpener.collect (lines 44–50): defer { inbox.sweep() } then try? inbox.take(newest.id)
• SharedInbox.take maps .notARegularFile and .unreadable to .notFound
• BoundedFile.read now returns on a FIFO instead of blocking

Call order

1. Owner shares a transfer QR. Inbox holds Inbox/<genuine-uuid>.
2. Sibling in the app group (the writer this design already names) creates Inbox/<other-uuid> as a FIFO, or as a file of policyBytes + 1. Its mtime is newer, so pending() sorts it first.
3. App becomes active, unlocked, vault open. collectWhatArrived → collect.
4. take of the poison: BoundedFile refuses the pipe (or .tooLarge). try? becomes nil. collect returns nil.
5. defer { sweep() } deletes every name in Inbox/, including the genuine QR.
6. Owner sees nothing. The share is gone. They had not confirmed it. The vault is untouched.

Before BoundedFile, step 4 hung on the main actor and the defer never ran, so the genuine file survived (and the app was stuck). S4-23’s fix is what lets step 5 happen.

The comment on sweep() says this path runs “after a collection, where taking one item means the rest were seen and not chosen.” That is false when take fails. Nothing was chosen.

This is a fourth shape of the sweep-versus-writer class, not a restatement of S4-24/25/26:

┌──────┬─────────────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────┐
│      │ When                                                                    │ What dies                                              │
├──────┼─────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────┤
│ S4-  │ now captured before attributes                                          │ a share that arrived during this sweep                 │
│ 24   │                                                                         │                                                        │
├──────┼─────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────┤
│ S4-  │ unknown-name delete vs atomic temp                                      │ an in-progress write                                   │
│ 25   │                                                                         │                                                        │
├──────┼─────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────┤
│ S4-  │ successful collect, then sweep() of names that arrived after the        │ a share that arrived during collect                    │
│ 26   │ snapshot                                                                │                                                        │
├──────┼─────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────┤
│ This │ failed take, then the same sweep()                                      │ every remaining inbox item, including ones already     │
│      │                                                                         │ there                                                  │
└──────┴─────────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────┘

None of these can reach the vault. sweep / sweepStale only touch Inbox/ in the app group. VaultKeyStore lives in the private container. Last-wins and these races destroy unconfirmed staging, not stored accounts.

One rule, not three guards: the full directory sweep may run only after a successful take. On failure, leave the rest (the failed name is already removed in take’s defer, or was never a file this app wrote). Stale sweep should keep running on activation; it should not be used as “delete everything we didn’t pick.” That single change closes this shape and S4-26’s “arrived after the snapshot” half of a failed-or-racy collect. S4-24 is ordering of now. S4-25 is “do not delete names we did not finish writing,” which is a different rule (don’t sweep temps / don’t sweep while a writer is live).

───

1. Does each change address the finding it claims to?

BoundedFile (S4-23, S4-29, and the four bound shapes). Yes, as a class. One open(O_RDONLY | O_NONBLOCK | O_NOFOLLOW), fstat on that fd, S_IFREG or refuse, then limit + 1 bytes. A FIFO is refused without blocking (tested, with a time limit, and the comment honestly says the blocking version was not run). A symlink is ELOOP → .notARegularFile (tested). A directory is refused (tested). Missing is distinct from unreadable (tested). One byte past the limit is .tooLarge (tested). Empty file is a file (tested). The descriptor cannot be swapped for a pipe between fstat and read.

Callers’ limits are the right ones:

┌────────────────────────────────┬────────────────────────┬─────────────────────────────────────────────────────┐
│ Caller                         │ Limit                  │ Why                                                 │
├────────────────────────────────┼────────────────────────┼─────────────────────────────────────────────────────┤
│ SharedInbox.take               │ policyBytes (8 MiB)    │ inbox holds images                                  │
├────────────────────────────────┼────────────────────────┼─────────────────────────────────────────────────────┤
│ ShareViewController.firstImage │ policyBytes            │ same, and no copy step                              │
├────────────────────────────────┼────────────────────────┼─────────────────────────────────────────────────────┤
│ ImportViewModel.read           │ largestAcceptableBytes │ may be an archive; format bound applied after sniff │
├────────────────────────────────┼────────────────────────┼─────────────────────────────────────────────────────┤
│ VaultKeyStore.load             │ keySize (32)           │ a larger file is damaged                            │
└────────────────────────────────┴────────────────────────┴─────────────────────────────────────────────────────┘

isWorthLoading still exists and is unused by these four; leftover, not a skippable bound.

The off-by-one is correct for every limit these callers pass. let ceiling = limit + 1 traps or wraps if limit == Int.max. None of the four pass that. I would still refuse a non-positive or overflowing limit in the primitive; I am not calling the current callers broken.

Comment: “The bytes past it were never held.” The function holds limit + 1 bytes, then throws and drops them. Recorded; not a code defect.

VaultKeyStore.load maps .unreadable to nil (absent). .tooLarge and .notARegularFile are .damaged. A key file that exists but fails open/read is reported as no key. In a private container that is unlikely. If it happened, the UI would offer setup/unlock as if the key were missing. I am not promoting it.

Last-wins addresses S4-27’s intermittency: the superseded inbox copy is taken off the device at the URL, not left to reappear. It addresses S4-28 by deleting the queue. It does not implement last-wins for a second share while the first is on screen (see above).

SharedInbox otherwise: future mtime → .distantPast still holds; staleAfter == freshness still holds; unknown names still swept on sight (S4-25 still the cost); backup exclusion still fail-closed.

───

2. Did any change introduce something new?

Yes: the finding above. BoundedFile made a poison FIFO a fast failure, and collect’s deferred full sweep was written on the assumption that take either hung or succeeded.

Last-wins on URL is new destruction of uncollected inbox items. That is the decision, not a sneak defect.

I did not find a BoundedFile bug that is wrong in four places at once. The primitive is the first time this class has one shape.

───

3. Comments and documents

Recorded, not holding the scope open.

• SECURITY.md still opens the leftover paragraph with “Leftovers are swept at launch” after the code started sweeping on every foreground. The duration is now correctly staleAfter / ten minutes.
• collectWhatArrived still says a second look would discard the first; collection still refuses to run when arrival != nil. True of collection, easy to read as the old first-wins rule for everything.
• BoundedFile’s “bytes past it were never held.”

APP_LOCK.md R5 and checklist 11–12 match the URL behaviour.

───

4. Converging or moving around?

BoundedFile is converging. Four wrong shapes became one primitive with tests that fail if you take the guards out. That is the right end of that thread.

Arrivals are a decision, not another guess. The queue worked on a phone and was removed because the behaviour was judged wrong. That is not the same loop as the mtime clamp.

The sweep is the area that has been rewritten three times and still has a class. Launch sweep, then stale sweep plus unknown names, then last-wins full sweep on URL, and collection still full-sweeps on a failed take. The three open races and this fourth shape are one fact: this code treats a directory another process writes to as a snapshot. The remedy is when a full sweep is allowed to run, not a fourth special case.

I would not reopen last-wins. I would change collect so sweep() runs only after a successful take. That is one rule, and it is the one that matches the comment they already wrote.
