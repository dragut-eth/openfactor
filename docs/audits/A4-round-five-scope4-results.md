# A4 round five, scope 4: the clock that was never moved

Reviewed commit: `4b8317f`, delivered as checkout `1ea2589`. Round four read `1bf4b26`, round
three `83e5cdd`, round one `74fe841`.

## The short version

**S4-24 was never fixed, and the comment above it describes the fix that was not made.** Two of
three engines found it. It is recorded here as medium.

I read each file's timestamp immediately before its own removal, which is half the remedy, and
compared it against `now`, which is still the function's default argument captured before the
enumeration began. **The comment I wrote says, in as many words, that judging files against a
clock taken earlier means a file written during the pass is measured against a moment before it
existed. The code then does exactly that.**

**The engines split three ways on the verdict**, and the split is about how much the structure
being right is worth against one comparison being wrong.

**Four more findings, all low**, including two the round five change created and two that S4-40
was supposed to have caught and missed.

## S4-41 (medium): the clock is captured before the enumeration

Found by Grok and ChatGPT independently. Verified here in both `pending` and `sweepStale`.

```
public func sweepStale(now: Date = Date()) {      // t0, before anything is listed
    for name in handle.names() {
        guard let modified = handle.modified(name) else { continue }
        let arrived = modified > now ? Date.distantPast : modified
```

The sequence:

1. `now` is bound at function entry.
2. The extension completes its atomic rename. The file's honest mtime is later than `now`.
3. This pass lists it and stats it.
4. `modified > now` is true, so `arrived` becomes `.distantPast`, the age is enormous, and the
   file is removed.

**The future-mtime branch exists to defeat a hostile writer stamping a file in 2090.** With the
clock sampled first, it cannot tell that writer apart from "we read the clock too early", and it
deletes on that inference. Grok's phrasing is the one to keep: the code infers attacker from
`modified > now`.

`pending` carries the same mapping, so a share appearing during the listing sorts last as
`.distantPast`. If `collect` then takes the genuine newest and supersedes the identifiers it read,
**the new share is in that set and is destroyed while an older one is presented.** Last wins,
inverted, in a window the length of a directory listing.

**The test does not reach it.** `agesAreReadPerFile` writes the file, then calls
`sweepStale(now: Date())`, so the clock is taken after the write and the file survives under the
broken code and the correct one alike. Move `Date()` back above the loop and it stays green. It is
the mtime clamp again: a test written alongside the fix, blind in the way the fix is blind.

**Both engines proposed the same remedy and it is one line of ordering.** For each entry, stat
first, then sample the clock, then compare. A concurrent write then has an mtime at or before that
sample and an age near zero. A plant stamped tomorrow is still in the future and still refused. No
skew window, no tolerance: sample after the observation.

ChatGPT adds a second half for `pending`: when metadata cannot be read at all, omit the candidate
rather than manufacture `.distantPast` for it, because a fabricated age is not evidence either.

**Fable read the same code and cleared it**, listing the stale sweep under evidence rather than
inference. That is worth recording plainly: Fable is the engine whose round four diagnosis this
whole change implements, and it accepted the sentence in the comment as a description of the code.

## S4-42 (low): a UUID-named directory can never be removed

Found by ChatGPT. Verified.

`pending` admits any entry whose name parses as a UUID, **without requiring it to be a regular
file**. A sibling can create a directory with a canonical UUID name.

`take` then opens it, `BoundedFile` correctly refuses it as not a regular file, and the deferred
`remove` calls `unlinkat(fd, name, 0)`, which deliberately refuses directories. `sweepStale` uses
the same removal, so it cannot collect it later either.

**The POSIX behaviour is right and the higher level assumption is wrong.** The refusal to recurse
is exactly what S4-33 was fixed to guarantee. What is wrong is the belief, stated in
`InboxOpener`'s own comment, that a refused candidate is thereby removed. **A UUID-named directory
accumulates permanently**, and shadows genuine items whenever its mtime is refreshed to sort
newest.

ChatGPT's remedy: admit only canonical UUID-named regular files into `pending`; optionally remove
empty directories with `AT_REMOVEDIR`; never restore recursive deletion. A hostile sibling's
non-empty directory may remain as an availability cost it already has, but it must never be an
import candidate.

## S4-43 (low): the exact directory entry is still not carried through

Found by ChatGPT. Previously filed as S4-30 and never closed; Fable's round four called it masked
rather than fixed.

`pending` converts a basename to a `UUID` and discards the original spelling. `take` and `sweep`
rebuild `id.uuidString`, which is canonical uppercase. **On a case-sensitive volume the entry
observed and the entry read or deleted are different names.** With both spellings present, the app
can choose on one entry's timestamp and act on the other.

This is deletion by inferred identity rather than by the entry that was read, which is the same
class as everything else in this round. iOS volumes are case-insensitive by default, which is why
it has survived two rounds; that is a property of the platform rather than of the code.

Remedy: require `name == id.uuidString`, or carry the validated basename through selection,
reading and deletion.

## S4-44 (low): the disclosed ordering bug has no regression test

Found by Fable.

The brief disclosed that the first `fstatat` read whole seconds, so two items written in the same
second sorted arbitrarily, which is the ordering the entire newest-wins rule depends on. **Nothing
under `Tests/` pins it.** Revert `modified()` to second resolution and nothing goes red;
`newestFirst` sleeps 1.1 seconds and would still pass.

There is no `InboxDirectoryTests` at all. The primitive is exercised only through `SharedInbox`,
which Fable names as the residual risk behind its own clearance of it: it verified the file by
reading, and no test stands behind that reading.

## S4-45 (low, documentation): seven claims, two of them made by this change

Recorded, not holding the scope open. Verified individually.

- `SharedInbox.swift:32` says the stale sweep cannot take the item somebody shared a moment ago.
  S4-41 is exactly that.
- `SharedInbox.swift:300` describes comparing against an entry-local observation. The code
  compares against the function's entry clock. **This is the fix's own comment describing the fix
  it did not make.**
- `InboxOpener.swift:40` says a stale item is left for the stale sweep. Lines 64 to 65 supersede
  the whole set. **Also written by this change**, when the stale path was given the supersede to
  keep `staleIsDiscarded` green.
- `InboxOpener.swift:51` says `take` removes the item it refused. False for a directory, per
  S4-42.
- `SECURITY.md:558` says an ordinary fresh share is untouched.
- `OpenFactorApp.swift:41` still says App Lock swaps the root, and `AddAccountSession.swift:19`
  still says the lock unmounts the view tree. **S4-40 corrected three of these sentences and there
  were five.** The class that closed scope 2 after seven rounds, in a new file.
- `agesAreReadPerFile` and `sweepLeavesWhatArrivedLater` are named for writes during a sweep and
  during a decision. Both write before or after. The identity-set property is covered by another
  test; these two names overstate their evidence.

## What was confirmed sound

**`InboxDirectory` survived a direct attack by all three.** Fable read it as the single point of
failure the brief said it was and reported no memory, lifetime, double-close or recursion defect,
stating that plainly rather than manufacturing a finding. Every item on the brief's checklist was
walked: the `dup` before `fdopendir` is the correct ownership split with both failure branches
closing the duplicate; the `d_name` rebind is safe because `String(cString:)` stops at the
kernel-guaranteed NUL; the failable `init?` returns before assigning, so `deinit` never runs on a
half-formed value and `~Copyable` guarantees one close; `fstatat` with `AT_SYMLINK_NOFOLLOW` reads
the link's own mtime rather than a target's; and `unlinkat` without `AT_REMOVEDIR` is genuinely
non-recursive for every entry kind `readdir` can return.

**S4-32 is fixed at the root**, unanimously. The supersede left the `defer`, `take` removes its own
refused item, and the false comment round four quoted is gone.

**S4-26, S4-35 and S4-33 are closed.** All three checked that the identity-set supersede excludes
later arrivals, and that no deletion can leave `<group>/Inbox/` or recurse.

**The S4-20 reversal is right**, unanimously and with reasoning. Grok: a sibling can leave a
non-UUID file for ten minutes, and that sibling can already write UUID names, FIFOs and
directories, so ten minutes of a planted blob is cheaper than losing a share in flight.

**S4-34 introduces no loop.** Fable checked: the re-presented arrival is non-nil so the guard
blocks re-entry, and the transition is `nil` to item, which is the safe pairing rather than the
item-to-item swap S4-37 was about.

**The write-path concession is accepted by all three** under the stated threat model. Fable adds
one angle round four did not name: `isExcludedFromBackup` is set on the real directory, so a write
redirected elsewhere could re-open the backup exposure. It judges the condition stack deep enough
to leave the write checked rather than descriptor-bound, and says it should stay written down.

**S4-36 stands.** Grok will not relitigate it. ChatGPT still disagrees with the destructive half
but explicitly declines to reclassify it as a round five defect, now that it is documented as an
accepted trade rather than a false claim.

## The verdict, three ways

- **Fable: converging, and for the first time in this dimension.** The change implements the union
  of the three round four remedies rather than rewriting the area a fifth time. It found no new
  medium or high and says so directly, on the structural grounds that this change *subtracts*
  deletion authority instead of adding a cleanup, which is the opposite of the scope 1 shape on
  every axis.
- **Grok: the structure converged and one clock comparison did not.** It would fix the ordering and
  not run another architectural pass.
- **ChatGPT: the arrival and inbox dimension has been rewritten a fifth time and is still wrong.**
  It retains an accepted race, retains S4-30, and introduces the entry-kind mismatch. The scope
  stays open, with lows rather than the earlier mediums.

**All three agree on what to do next**, which matters more than the labels: fix the clock ordering,
tighten what `pending` admits, and do not touch the structure.

## On the measurement

Both engines that addressed E11 said four runs retire the observed one-in-four symptom for that
device and build and prove nothing about a rarer drop.

**Fable's point is the useful one and it is not about statistics.** A `sheet(item:)` identity swap
is an inherent bet on SwiftUI's mid-flight behaviour, and trial counts over a timing race age out
with every iOS release. The durable answer is to make the swap structural: route arrival
replacement through `nil` then item, dismissing and presenting on the cleared signal, which the
S4-34 `onChange` already provides the hook for. Short of that, item 11 is a checklist item re-run
per iOS version, which is a reasonable place to leave an untestable seam but is a mitigation and
not a proof.

## One process error, mine

ChatGPT reported that `A4-round-four-scope1-results.md` is absent from the checkout. It was: the
review copy was synced at `1ea2589`, and that file did not land until `b3e7e08`. **The round five
brief pointed reviewers at a file that was not there**, and one of the three worked around it by
using the brief's own description of the neighbouring finding. The other two did not mention it.
The sync should follow the brief rather than precede it.

## What was done: S4-41 only

**One medium, one commit.** The other four findings in this round are untouched.

`pending` and `sweepStale` take the clock as `@Sendable () -> Date` rather than a `Date`, and read
it **after** each entry's `fstatat` rather than once at entry. A share that lands mid-pass is then
at or before the reading that judges it and is ordinary; a plant stamped in 2090 is still ahead of
every reading and is still refused. **No tolerance window was added.** The fix is the order of two
calls, which is what both engines that filed it proposed.

`pending` also stops manufacturing an age. An entry whose `fstatat` fails used to become
`.distantPast`, which sorted it last and put it inside the identifier set a collection supersedes,
so it was deleted for an age nobody measured. It is now omitted, and `sweepStale` already skipped
it. **The cost is honest and worth stating: an entry nobody can stat now stays in the directory.**

### The test, and what it took to make it real

Written from the finding's own words before the fix existed, per the method decided after the
night this round came from.

**The first two attempts did not discriminate**, and both failures are worth recording because
they are the same failure this gate keeps finding. A clock returning a list of readings cannot tell
the versions apart, because the broken code's single read and the fixed code's first per-entry read
take the same value. A clock that writes the share and *then* returns `Date()` cannot either,
because the reading is taken after the write it is supposed to precede.

What works is a clock that captures its reading, then lands the share, then returns the earlier
reading. That is the race exactly: the pass has its clock, and the extension writes a moment later.
Under the broken ordering the share is listed, its stamp is later than the sample, and it is
removed. Under the fixed ordering the listing happens before any clock read, so the share is not in
that pass at all.

**Mutation tested by hoisting the read back above the listing at both sites**, verified applied
rather than assumed: both tests go red, one reporting the share deleted and the other reporting its
arrival recorded as `.distantPast`.

### Two of S4-45's claims are now true without being edited

`SharedInbox`'s header says the sweep cannot take the item somebody shared a moment ago, and
`SECURITY.md` says the ordinary share is untouched. Both were false because of S4-41 and both are
true now. They were not rewritten; the code came to meet them.

472 core tests pass, the app suite passes, both targets build.

## What was done: S4-44, and the defect it found

**The test found a defect in the primitive on its first run**, which is the whole argument for
writing it.

`InboxDirectory.names()` handed `fdopendir` a `dup` of its own descriptor, so that `closedir`
would not close the one the type keeps. **A `dup` shares one file offset with the original.**
Reading the stream to its end leaves that shared offset at the end, so a second listing through
another `dup` starts where the first stopped and reports an **empty directory**, silently.

All three engines cleared this file by reading, and one of them named this exact mechanism and
reached the opposite conclusion: that `dup` is why a second listing does not resume a consumed
stream. It is not. `dup` protects the descriptor from being closed and shares its offset.

**Not reachable in production today**: `pending` and `sweepStale` are the only callers and each
lists once per handle. The fix is prophylactic, and the silent-empty failure mode is why it was not
left alone. `names()` now opens `.` relative to its own descriptor, which gives an independent
offset and re-opens the directory the type already holds rather than a path anybody can move.

**So this commit is not test-only, and I said it would be.** That claim was wrong within the hour.

### The tests

`InboxDirectoryTests` is the primitive's first direct coverage. Three mutations, each verified to
apply before the run:

- **Dropping `tv_nsec` from `modified`** reddens the sub-second ordering test, which is S4-44 as
  filed: two files written twenty milliseconds apart must carry distinguishable timestamps in the
  right order, and the existing ordering test sleeps 1.1 seconds so it cannot see this.
- **Passing `AT_REMOVEDIR` to `unlinkat`** reddens the suite through the file-removal tests, since
  that flag refuses ordinary files. Stated precisely: the new directory test pins **non-recursion**,
  that nothing inside a directory is reachable by a removal, which is the property S4-33 rests on.
  It does not pin the flag's exact value; the suite as a whole does.
- **Returning to `dup`** reddens the repeatability test, which is the defect above.

The rest covers what the other engines verified by reading: listing excludes `.` and `..`, a
missing name has no timestamp, a file does not open as a directory, and a symbolic link does not
open whatever it points at.

481 core tests pass, the app suite passes, both targets build.

## What was done: S4-42

**The candidate is what should never have existed.** Every refusal downstream was already correct:
the bounded read refuses a directory because it is not a regular file, and `unlinkat` refuses it
because it does not take directories. `pending` now asks whether an entry is a regular file before
offering it as an item.

**Both answers come from one `fstatat`.** `InboxDirectory.entry(_:)` returns the timestamp and the
kind together, so the two cannot describe different states of the directory, and `modified(_:)` is
now that call with the kind discarded. **The sweep deliberately keeps using `modified`**: what it
removes is decided by age, and a leftover under a foreign name is worth removing whether it is a
file, a link or a socket. Only the reading side insists on a regular file, because only the reading
side offers the thing to somebody.

**The optional half of the filed remedy was declined.** Removing empty directories with
`AT_REMOVEDIR` would add deletion authority to a scope that has produced a high and a medium by
adding exactly that, and the property `InboxDirectoryTests` now pins is that nothing inside a
directory is reachable by a removal. A planted directory therefore stays, unlistable as an item and
unremovable by the sweep, which is an accumulation a hostile sibling can already cause directly and
which the filing engine accepted as an availability cost. Anything else that sibling plants, a link
or a pipe or a socket, is not an item and is still swept by age.

Two tests, both red before the change and mutation tested after: a directory with a UUID name is
never offered as an item, and, at the app level, a planted directory does not hide a genuine share.
The second is the consequence the core test cannot show, since a directory sorts by its own
timestamp and is therefore what a collection reaches for first.

482 core tests pass, the app suite passes, both targets build.

## What was done: S4-43

**The entry read and the entry acted on are now the same one.** `pending` required only that a name
parse as a `UUID`, and then threw the spelling away; `take` and `sweep` rebuilt the path from
`id.uuidString`, which is canonical uppercase. On a case-sensitive volume those are two different
names, so an item chosen on one entry's timestamp was read and removed at another.

`pending` now requires `name == id.uuidString`. **That can only ever turn away a name somebody else
wrote**, because this app writes `id.uuidString` and nothing else, which is what makes the narrow
form of the remedy sufficient rather than a partial one.

The fuller remedy the finding also offered, carrying the validated basename through `Pending`,
`take` and `sweep`, was not taken. It ripples through four files and two suites to reach the same
property, and this scope has been burned by changes larger than their findings.

**iOS volumes are case-insensitive by default**, which is why this survived three rounds. That is a
property of the platform rather than of the code, and the code no longer depends on it.

Red before the change, and mutation verified applied: removing the spelling check reddens it.

483 core tests pass, the app suite passes, both targets build.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Grok:
Scope 4, round five

Code: 4b8317f
Checkout: 1ea2589 (hardware record and this brief only)
Prior rounds: 74fe841 → 83e5cdd → 1bf4b26

I wrote the round-four finding that a failed take still ran the full sweep. I am not treating that as authority. The question this round asked first is whether anything still deletes on inference.

───

Finding — Medium

S4-24 is not closed. The timestamp is read later; the clock it is judged against is not.

Where

• SharedInbox.sweepStale(now:) lines 294–317
• SharedInbox.pending(now:) lines 207–226
• Test that does not cover it: agesAreReadPerFile in SharedInboxTests.swift

What the fix claimed

Round three: now is captured, then attributes are read, so a share that arrives during the pass has an honest mtime after that now, is mapped to .distantPast, and is deleted as stale. The stated remedy was to compare each file against a clock taken after its own stat.

What shipped: each modified(name) is read immediately before remove. now is still the default argument, captured once at the start of the function.

    public func sweepStale(now: Date = Date()) {
        ...
        for name in handle.names() {
            guard let modified = handle.modified(name) else { continue }
            let arrived = modified > now ? Date.distantPast : modified
            guard now.timeIntervalSince(arrived) > Self.staleAfter else { continue }
            handle.remove(name)
        }
    }

Call order

1. now ← Date() (start of the pass).
2. Extension finishes an atomic rename. The file’s mtime is now + ε.
3. This pass stats it. modified > now is true.
4. That is the same branch as a sibling plant stamped tomorrow: arrived = .distantPast, age is huge, remove.

A future mtime from a hostile writer and a future mtime from “we sampled the clock too early” are not distinguishable if now is sampled first. The code infers attacker from modified > now and deletes. That is the inference.

pending(now:) uses the same mapping. A file that appears during the listing is sorted last. If collect then takes the previous “newest” and sweeps the identifiers it read, the new share is in that set and is destroyed while an older one is presented. Last-wins, inverted, in a window the length of a directory listing.

The test

agesAreReadPerFile writes a file, then calls sweepStale(now: Date()). Date() is taken after the write, so modified < now and the file survives. That is true of the broken code and the claimed fix. It does not write during the pass. It would not go red if you moved Date() back above the loop.

This is the mtime-clamp failure again: a test written with the fix, blind in the way the fix is blind. Scope 1’s round four high was “a correct fix plus a cleanup that deleted on an inference.” Here the cleanup is the modified > now → distantPast rule applied to a clock that is not evidence about this file.

Smallest fix

For each name, stat first, then let now = Date(). A concurrent write then has mtime ≤ now and age ≈ 0. A plant at now + 1 day is still in the future and still .distantPast. Do not add a skew window. Sample after the observation.

The same order belongs in pending, per item, if collect is going to sweep that set.

───

1. Does each change address the finding it claims to?

S4-32. Yes. collect no longer defers a full wipe. Failed take returns without sweep(_:). take still removes the poison itself. afailedTakeLeavesTheRest plants an oversized newest file next to a genuine share and checks the share remains. Put the supersede back in a defer and that test is the one they named.

Stale path (“newest is stale ⇒ all of them are”). Holds for honest timestamps: pending is newest-first, so if the first is past freshness, every later row is older. It does not hold for a file classified as .distantPast because now was early — that file is treated as oldest and is in the set that gets swept. That is the finding above, not a second hole in the “all older than newest” arithmetic.

S4-26 / S4-35. Yes, as identity-vs-directory. Callers pass the UUIDs they listed. A name that appears after that list is not deleted. collectingLeavesALaterArrival and the onOpenURL path (sweep(pending().map(\.id))) match. They do not protect a name that made it into the list with a “future” mtime. Same finding.

S4-25 / S4-20 reversal. Right, and I would keep it. In a group whose members are this app and its share extension, a name that is not a UUID is almost always Data.write(.atomic)’s temp. Deleting those on sight was the race. Age-gating them costs this: a sibling can leave a non-UUID file in the group for ten minutes. That sibling can already write UUID-named files, FIFOs, and directories. Ten minutes of a planted blob is cheaper than losing a share in flight. unknownNamesSurviveWhileFresh / unknownNamesAreSweptWhenStale pin both sides.

S4-33 / InboxDirectory. The capability change holds.

• open(..., O_DIRECTORY | O_NOFOLLOW) refuses a symlink at Inbox. aSymlinkedDirectoryIsRefused plants a file outside, points Inbox at it, and checks it survives pending, write, sweepStale, and sweep(_:). Dropping O_NOFOLLOW is what they say reddens the last expectation.
• dup then fdopendir is the right ownership split: fdopendir would consume the fd; the type keeps its own. Failed fdopendir closes the duplicate. deinit closes the original. ~Copyable stops a second close.
• fstatat(..., AT_SYMLINK_NOFOLLOW) stats the name, not a target.
• unlinkat(..., 0) does not pass AT_REMOVEDIR. A directory entry fails with EISDIR and is left. That is non-recursive for every kind readdir can return. A sibling-created subdirectory can therefore accumulate. That is the correct cost of not running removeItem on a tree. It cannot make this app delete the sibling’s chosen directory the way path-based removeItem could.
• Reads are openat + the same BoundedFile.read(descriptor:limit:) loop. One implementation remains.

Nanoseconds. st_mtimespec with tv_nsec is the right field. Two writes in one second no longer tie. I did not find another whole-field truncation. Residual: Date/TimeInterval cannot represent every nanosecond at current Unix time (~100 ns). Irrelevant for two human shares. Residual: newestFirst still sleeps 1.1 s, so reverting to whole seconds would still pass. Coverage of the bug they disclosed, not a bug in the code.

Write path, checked not bound. Stated in the type and in SharedInbox.write. Open the directory, then Data.write by path. A substitution between those two steps writes the image through the path (into whatever Inbox names now) while later sweeps/reads use a new open of whatever Inbox is then. Confidentiality: the sibling could already read the group. Availability: the extension can report success and the app can then see an empty real directory. I would not put the write on the descriptor unless they are willing to replace Data.write(.atomic) with openat/renameat. For this threat I accept the concession. It is not deleting on inference; it is failing to bind the write.

S4-34. Yes. .onChange(of: arrival?.id) collects only when the id becomes nil. A URL replacing an image changes id to another UUID and does not collect (correct). Dismissing collects. APP_LOCK.md now says the two directions are reached differently because a link is an event and a share has to be looked for.

S4-37 / E11. Four runs, four times the panel stayed up and showed the link. The fourth run was the uncollected-inbox path, which is sweep(_:) rather than the sheet swap. Four runs is the same budget that showed the 1-in-4 defect once in expectation. It is evidence against a fault of that frequency, not against a rarer drop. The checklist measured against this build is the right ongoing instrument. I would not hold the scope on it.

S4-36. I still agree with the rejection. Destroying the superseded copy is the rule. The unrecoverable case is a pending import whose source cannot reproduce the image. Nothing in the vault. I will not relitigate it.

───

2. Did any change introduce something new?

The incomplete S4-24 fix is the new (or unfixed) deletion: it uses the future-mtime branch, which was added to stop a plant, as evidence that a file that arrived during the pass is old.

I did not find a second cleanup of the scope-1 kind — a successful path that then deletes extra records it did not prove were wrong. Failed take no longer wipes the rest. Identity sweep no longer empties the directory.

unlinkat failing on directories means a sibling can leave a directory in Inbox/ forever. That is stopping a deletion for lack of evidence, which is the safe direction.

───

3. Comments and documents

Recorded, not holding the scope open.

• AddAccountSession still says a lock “unmounts the view tree.” Warm lock does not. S4-40 was supposed to have caught this.
• agesAreReadPerFile’s comment describes a write during the pass; the test does not perform one.
• collectWhatArrived still says “a second look would discard the first,” which is now the looking-vs-event split, easy to read as old first-wins.

SECURITY.md leftover paragraph now says every foreground and staleAfter / ten minutes. APP_LOCK.md R5 matches the two directions.

───

4. Converging?

The structure converged. One clock comparison did not.

Two operations plus a directory descriptor is the right shape, analogous to BoundedFile. This is not a fifth rewrite of the same guess. Failed-take wipe, empty-directory supersede, and delete-unknown-on-sight are gone as rules.

What remains is the same inference that created the clamp defect: mtime > now means attacker, with now taken before the stat. Until that comparison is ordered after the observation, the inbox still deletes a share for being too new, which is the thing this entire sweep thread was trying to stop.

I would fix that clock order and not run another architectural pass.

───

5. Every deletion, and what it rests on

┌───────────────────────────┬────────────────────────────────────────┬────────────────────────────────────────────────────────────────────┐
│ Deletion                  │ Evidence                               │ Enough?                                                            │
├───────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ take’s defer { remove(    │ We opened this name to read it         │ Yes. Poison and success both remove the one item judged.           │
│ name) }                   │                                        │                                                                    │
├───────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ collect sweep(waiting     │ Those ids were listed, and we took the │ Yes for names not in the list. No for a name in the list only      │
│ .ids) after successful    │ newest                                 │ because now was early (finding).                                   │
│ take                      │                                        │                                                                    │
├───────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ collect sweep(waiting     │ Newest-first ⇒ all listed are at least │ Yes for honest mtimes. Same finding for .distantPast forced by an  │
│ .ids) when newest is      │ that old                               │ early now.                                                         │
│ stale                     │                                        │                                                                    │
├───────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ Failed take               │ No sweep(_:)                           │ Yes. Leaves what was not judged.                                   │
├───────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ onOpenURL sweep(pending() │ Last-wins; those were the uncollected  │ Yes as policy (S4-36). Same early-now caveat.                      │
│ .ids)                     │ UUID names at the moment of the link   │                                                                    │
├───────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ sweepStale                │ That file’s own mtime, age >           │ Not enough while now is from the start of the pass. That is        │
│                           │ staleAfter                             │ deleting on “this file is from the future relative to a clock I    │
│                           │                                        │ already held.”                                                     │
├───────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ Unknown names             │ Same age rule, not “not a UUID”        │ Yes, given the S4-20 reversal.                                     │
├───────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ unlinkat on a directory   │ Kernel refuses                         │ We stop. Correct.                                                  │
├───────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ Vault key / Keychain      │ Untouched by every path above          │ Confirmed again: InboxDirectory only operates under the opened     │
│                           │                                        │ inbox fd.                                                          │
└───────────────────────────┴────────────────────────────────────────┴────────────────────────────────────────────────────────────────────┘

The one deletion that still rests on inference rather than evidence is modified > now ⇒ distantPast when now was not observed after modified.

Fable:
Scope 4, round five — the sweep split and the inbox as a descriptor

Verdict. This is the first round in this scope where the change implements the diagnosis all three engines converged on in round four rather than patching another symptom. The sweep split, per-file timestamps, the age-gated foreign-name rule, and InboxDirectory together close S4-24/25/26/32/33/34 as one shape, and they do it by removing deletion authority, not adding it. I attacked the new raw-POSIX file directly, as the brief asked, and found no memory, lifetime, double-close, or recursion defect in it. I did not find a new medium or high. The two things worth recording are a missing regression test for the ordering bug the work itself disclosed, and the write-path TOCTOU the code already concedes, which has one backup-exclusion nuance round four did not name. The deletion story is the strongest it has been in five rounds: no deletion can leave <group>/Inbox/, none recurses, and exactly one rests on inference — the one the reviewers asked to loosen.

I take the brief's standing invitation seriously and retract nothing, but I sharpen round four below where the record needs it.

Q5 — the deletion question, answered directly

Every deletion this scope performs, and the evidence under it:

Site	What it deletes	Evidence	Sound?
take defer (SharedInbox.swift:239)	the one id the caller named	the caller chose to consume (or refuse) that exact id	evidence
sweep(_ ids:) (:270)	exactly the passed ids	the caller read those ids and decided against them; a later arrival is not in the set	evidence
collect post-take (InboxOpener.swift:71)	the read snapshot, after a successful take	the rest were enumerated and not chosen	evidence
collect stale path (:65)	the whole read snapshot	newest = max arrived; if it is past freshness, all are, by sort order	evidence, and I checked the proof
sweepStale UUID names (:316)	names older than staleAfter	that file's own mtime, read immediately before its own removal	evidence
sweepStale foreign names (:299-316)	unrecognised names older than staleAfter	location + age, not authorship	inference
onOpenURL (OpenFactorApp.swift:274)	pending() read one line earlier	snapshot set; later arrivals excluded	evidence

The stale-path reasoning the brief flagged holds. pending() sorts descending by arrived, so waiting.first carries the maximum. If that maximum is older than freshness, every other member is too, and sweeping the whole set deletes only genuinely-stale items. The future-timestamp clamp does not break this: a future-stamped plant becomes .distantPast and sorts last, so it can never masquerade as the newest and force the stale path while a real fresh share is present (:222-223). And because pending() only admits names that parse as a UUID, collect's sweeps never touch a foreign name at all — collection deletes only what it enumerated as a valid pending item.

The one deletion on inference is the foreign-name stale sweep, and it is the S4-20 walk-back. When sweepStale deletes a name it did not write, its only evidence is "this sits in <group>/Inbox/ and is older than ten minutes." There is no positive evidence the app authored it. I judge this acceptable, and more defensible than the S4-20 rule it replaces, for four reasons that are all properties the design already commits to: the subdirectory is OpenFactor's by construction; the group is conceded to be a non-confidentiality boundary in docs/VAULT.md; the blast radius is provably files-only and non-recursive (below); and the cost to a hostile sibling that plants a name on purpose is losing its own file after ten minutes, which is availability harm to the attacker, not the user. Against the atomic-write collision S4-20 created, age is the right separator: an in-progress temp is seconds old and survives, a genuine leftover is old on the next pass and goes. The test unknownNamesSurviveWhileFresh pins exactly that and reddens if the age gate is removed.

Compare the scope-1 shape I was sent to study. That was a correct fix with an unrequested cleanup stapled on, and the cleanup deleted data on an inference it had no evidence for. This round is the opposite on every axis. The "cleanup" (splitting sweep) is the fix; it deletes strictly less than before (identity-set instead of whole-directory, age-gate instead of on-sight); and the single inference-deletion is a deliberate, reviewer-requested loosening in the safe direction. This round does not repeat the scope-1 shape.

Nothing any deletion reaches is unrecoverable or outside the inbox. Every removal goes through unlinkat(dirfd, name, 0) on a descriptor opened O_DIRECTORY | O_NOFOLLOW (InboxDirectory.swift:41,94). unlinkat without AT_REMOVEDIR removes a single non-directory link and fails on a directory, so it cannot recurse whatever it is pointed at, and the descriptor cannot be redirected by a path swap after it is opened. The vault key file and the Keychain records live elsewhere and are unreachable from any of this. Round four's S4-33 (a symlinked Inbox turning a sweep into an arbitrary-tree delete) is now closed structurally, not guarded — the regression test aSymlinkedDirectoryIsRefused plants a file outside the inbox and proves it survives.

Attacking InboxDirectory directly (Q2's most likely home)

The brief is right that one bug here is a bug in every inbox operation, so I read it as the single point of failure. Each item on its checklist:

dup before fdopendir (:54-60): correct and necessary. fdopendir takes ownership and closedir closes the duplicate; the instance keeps its own descriptor. Enumerating from a fresh DIR* each call is why dup is needed — a second names() would otherwise resume a consumed stream. Both failure branches close the duplicate. No leak, no double-close.
d_name rebind (:64-68): safe. Source and destination types are both CChar, so the rebind is a reinterpret; String(cString:) stops at the kernel-guaranteed NUL well inside the buffer. The stated capacity NAME_MAX + 1 (256) is smaller than Darwin's actual d_name array, which is cosmetically wrong but cannot cause an over-read because String(cString:) is bounded by the NUL, not the capacity.
Descriptor lifetime vs ~Copyable deinit: correct. The failable init? returns before assigning descriptor when open fails, so deinit never runs on a half-formed value and there is no fd to leak. Non-copyability guarantees one owner and one close. In take, the defer { handle.remove } borrows handle and is sequenced before the deinit, so the unlinkat runs while the directory fd is still open.
fstatat with AT_SYMLINK_NOFOLLOW (:82): correct — a symlink entry reports the link's own mtime, not a followed target, so a planted symlink cannot borrow a fresh target's timestamp to look young.
unlinkat without AT_REMOVEDIR on every entry kind: genuinely non-recursive. It removes files, symlinks, FIFOs, sockets, device nodes; it fails on a directory. A foreign subdirectory is therefore left in place rather than recursed into — the conservative outcome.
read via openat + BoundedFile.read(descriptor:): O_NONBLOCK stops a FIFO hanging the open, O_NOFOLLOW refuses a symlinked final component, and the descriptor fstat then rejects anything that is not S_IFREG. The bounded loop is the same one round four cleared; splitting out read(descriptor:) keeps one implementation.

I could not construct a memory, lifetime, or recursion defect. That is a real result about a file the brief correctly singled out as high-leverage, and I state it plainly rather than manufacture a finding to satisfy "assume it did."

Q1 — each change against its finding
S4-32 (failed take ran the full sweep): fixed at the root. The supersede left the defer and now runs only after a successful take or a stale rejection; take removes its own refused item via its defer, so a poison item is cleaned up while its neighbours survive. afailedTakeLeavesTheRest reddens if the supersede returns to a defer. The false comment round four quoted ("taking one item means the rest were seen and not chosen") is gone.
S4-24 / S4-25: each timestamp is read immediately before its own removal, and the foreign-name deletion is age-gated. agesAreReadPerFile and unknownNamesSurviveWhileFresh cover both, mutation-style.
S4-26 / S4-35: both callers pass the ids they read; a file written after the read is not in the set. sweepLeavesWhatArrivedLater and collectingLeavesALaterArrival pin it. onOpenURL now supersedes what it read rather than emptying the directory.
S4-33: done as capability, verified above.
S4-34 (last-wins asymmetry — my own round-four low): fixed. onChange(of: arrival?.id) { if id == nil { collectWhatArrived() } } (OpenFactorApp.swift:260) re-runs collection when the panel clears, so a share made behind a link presents on dismissal. I checked it introduces no loop (the re-presented arrival is non-nil, so the guard blocks re-entry) and no unsafe swap: the transition is nil→item, the safe pairing, not the item→item swap that S4-37 worried about.
Q2 — did it introduce something new?

I assumed yes and hunted. What I found, in descending order of substance:

The write-path TOCTOU, with a backup-exclusion nuance (low, and disclosed). write opens InboxDirectory as a check, then does a path-based Data.write (:151-155); a sibling that swaps Inbox for a symlink between the check and the write redirects where the QR image lands. The code concedes this, and it is acceptable for the reason it gives: a sibling authorised into the group can already read the real item, so redirection buys confidentiality it already has. The one angle round four did not name: isExcludedFromBackup is set on the real directory, so a write redirected to a different, non-excluded location could re-open the backup exposure the exclusion closes — but only for an authorised hostile sibling that also wins the race and also supplies a target both writable by the extension and backup-eligible. That is a deep enough condition stack that I agree with leaving the write path checked rather than descriptor-bound; it should stay written down, which it is.
Denial-of-presentation by a hostile sibling (not a finding). A sibling that plants a fresh poison item before every collection keeps a genuine share from ever being presented (the poison always sorts newest, take refuses it, the genuine share is left for a later pass that meets the same poison). This is strictly weaker than the delete-the-file-directly capability the same sibling already has, so it adds no exposure.
No new data-loss, wedge, or memory defect. The onChange re-collection, the onOpenURL set-supersede, and InboxDirectory are each clean. I say this directly: unlike two of the last three rounds, I do not believe this round's fix produced the next defect. The reason is structural — the change subtracts deletion authority instead of adding a cleanup.
Q3 — comments and documents (recorded, not holding the scope open)
modified()'s "Nanoseconds included" (:83) slightly overstates. The stamp is assembled as Double(tv_sec) + Double(tv_nsec)/1e9 at epoch magnitude (~1.7×10⁹), where Double resolves to roughly a quarter-microsecond, not a nanosecond. This is entirely adequate for human-paced shares and fixes the same-second bug that was disclosed — but the comment implies full nanosecond fidelity the representation does not carry.
BoundedFile header (round four's S4-39): addressed. It no longer claims the read "cannot be raced," documents what O_NOFOLLOW covers and what it does not, and its "What it does not promise" section is accurate. The round-by-round narration is gone.
The SharedInbox, InboxDirectory, and sweep(_:)/sweepStale doc comments all match the code as written. The ownership comments in OpenFactorApp/AccountListView now describe the warm lock as a window above a surviving tree (round four's S4-40).
A missing test worth having (low)

The ordering bug the work itself disclosed — whole-second fstatat sorting two same-second items arbitrarily — has no committed regression test. Grep confirms nothing under Tests/ references mtimespec, nsec, or same-second ordering, and there is no direct InboxDirectoryTests file at all; the POSIX primitive is exercised only through SharedInbox. Revert modified() to seconds resolution and nothing goes red, even though newest-wins — the rule the whole arrival design turns on — depends on it. A test that writes two items a few milliseconds apart and asserts the later sorts first would pin the disclosed bug and is the one piece of coverage this otherwise strongly mutation-tested change is missing. The primitive being untested directly is also the residual risk behind my "found no defect in InboxDirectory": I verified it by reading, and there is no test standing behind that reading.

Q4 — converging?

Yes, this round, and for the first time in this dimension. Round four's split verdict was that file-reading had converged and the arrival/inbox dimension had not, having been rewritten four times, with all three engines giving the same diagnosis: the sweep treated a directory another process mutates as a static snapshot. This round does not rewrite the area a fifth time and leave it wrong — it implements the union of the three proposed remedies: identity-sets for supersession, per-file timestamps, age-gated foreign names, and the directory descriptor that makes the whole thing capability-based rather than path-based. The collision rule is now symmetric across both entry points. That is convergence onto the shared diagnosis, not motion. The file-reading dimension remains converged, now with a clean second caller sharing one implementation.

Two honest caveats on that convergence: it rests on a new raw-POSIX file that no test exercises directly, and it leaves the write path deliberately un-hardened. Neither reopens the scope. If a defect surfaces here again it will be in the write TOCTOU or on a device, not in the deletion logic, which is now decided by evidence at every site but one — and that one was loosened on purpose, in the safe direction.

On the measurement (the brief asked)

Four runs do not settle S4-37, and E11 is right to say so. Four clean runs is evidence against a fault of the ~1-in-4 frequency the queue version showed; it says almost nothing about a 1-in-50 fault, and the improvised fourth run (a different path, item 12) is one trial, not reassurance about the first. The durable answer is not more trials — a sheet(item:) identity swap is an inherent bet on SwiftUI's mid-flight behaviour, and statistics over a timing race age out with every iOS release. What would settle it is making the swap structural: route arrival replacement through nil→item (dismiss, then present on the cleared signal, which the S4-34 onChange already provides the hook for) so the presentation no longer depends on SwiftUI cleanly swapping one live sheet item for another. Short of that, item 11 stays a hardware checklist item re-run per iOS version, which is a reasonable place to leave a genuinely untestable seam — but it is a mitigation, not a proof, and the doc is honest that the earlier four-of-four did not transfer.

GPT:
Findings
Low — S4-24 is not fixed: a share arriving during enumeration is still classified as ancient and deleted
[SharedInbox.pending (line 207)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:207) and [SharedInbox.sweepStale (line 294)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:294) both capture now before enumerating and inspecting entries.
Concrete sequence:
pending() or sweepStale() captures now = t0.
The extension finishes its atomic rename at t1, where t1 > t0.
The ongoing enumeration includes the new file.
Its legitimate mtime is later than now.
Lines 223 or 314 replace that timestamp with .distantPast.
InboxOpener.collect treats the item as stale and sweeps it, or sweepStale unlinks it directly.
Reading each mtime later did not change what it is compared against. The comparison clock is still the earlier observation that caused S4-24.
The new test does not reproduce the race: [agesAreReadPerFile (line 342)](Tests/OpenFactorCoreTests/SharedInboxTests.swift:342) writes the item before calling sweepStale(now: Date()).
Smallest fix: after each successful fstatat, take a fresh comparison time and compare that entry against it. In pending, do not manufacture .distantPast when metadata cannot be read; omit the candidate until there is evidence of its age.
Low — A UUID-named directory is an unremovable inbox poison
[SharedInbox.pending (line 211)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:211) accepts any entry whose name parses as a UUID, without requiring a regular file. A sibling can create a directory named with a canonical UUID and give it the newest mtime.
take opens the directory, BoundedFile correctly rejects it as non-regular, and its deferred [InboxDirectory.remove (line 92)](Sources/OpenFactorCore/Inbox/InboxDirectory.swift:92) calls unlinkat(..., 0). That call deliberately refuses directories. The stale sweep uses the same removal and therefore cannot collect it later.
The raw POSIX behavior is safe and genuinely non-recursive; the defect is the higher-level assumption that every failed candidate is thereby removed. A directory can accumulate forever and can repeatedly shadow genuine items when its mtime is refreshed.
Smallest fix: admit only canonical UUID-named regular files into pending. Empty directories may optionally be removed with AT_REMOVEDIR; do not restore recursive deletion. A malicious nonempty directory can remain as an availability cost of the already-hostile App Group member, but it must never become an import candidate.
Low — S4-30 remains: the caller does not pass the exact identity it read
At [SharedInbox.pending (line 211)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:211), a basename is converted to UUID, discarding its original spelling. take and sweep reconstruct id.uuidString, which is canonical uppercase.
On a case-sensitive volume, a lowercase UUID filename is therefore observed and selected, but the subsequent read and deletion target a different uppercase name. Alone, the lowercase entry causes a failed collection and remains until the age sweep. If both spellings exist, the app can choose based on the lowercase entry’s timestamp while reading and deleting the uppercase entry instead.
This is deletion based on inferred identity rather than the exact directory entry read. It is the previously reported S4-30, not a new round-five defect.
Smallest fix: require name == id.uuidString before returning a Pending, or retain the exact validated basename through selection, reading, and deletion.
The five requested answers
Do the changes address their findings?
S4-26 and S4-35: yes for the legitimate writer’s unique canonical UUIDs. A later distinct UUID is outside the supplied set and survives.
S4-32: fixed for regular oversized files, FIFOs, sockets, symlinks, and other removable entries. It does not close the class because directories and noncanonical UUID names are not removed as claimed.
S4-24: no; the earlier comparison clock remains.
S4-25: the age gate is the right reversal. It protects Foundation’s in-progress atomic temporary file. Its cost is that a hostile sibling can preserve arbitrary names by refreshing their mtimes; that sibling already has direct storage-availability power.
S4-33: the catastrophic pathname/redirection and recursive-deletion class is closed. The dup/fdopendir ownership, d_name lifetime, ~Copyable descriptor lifetime, fstatat no-follow behavior, and nonrecursive unlinkat are sound. The directory-entry mismatch above is the remaining application bug.
The path-based write concession is acceptable under the stated threat model: a hostile App Group sibling already controls the confidentiality, integrity, and availability of staged data. Descriptor-relative atomic writing would be cleaner, but the remaining race does not expose vault or Keychain material.
S4-34: the source-level trigger on arrival == nil addresses the reported behavior.
Nanosecond timestamps: the implementation is correct, but no test forces two entries into the same second, so the discovered regression is not pinned.

Did the changes introduce something new?
Yes: safe nonrecursive deletion introduced the UUID-directory accumulation case because candidate discovery was not tightened to match the new deletion capability. S4-24 and S4-30 are older defects that remain.

False code/document claims
[SharedInbox.swift (line 32)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:32) says the stale sweep cannot take a moment-old share; the stale-clock race does exactly that.
[SharedInbox.swift (line 300)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:300) describes comparing against an entry-local observation, but the implementation compares against function-entry now.
[InboxOpener.swift (line 40)](OpenFactor/Import/InboxOpener.swift:40) says stale items are left for the stale sweep; lines 64–65 immediately supersede the whole set.
[InboxOpener.swift (line 51)](OpenFactor/Import/InboxOpener.swift:51) says take removes every refused obstruction, which is false for directories and noncanonical UUID names.
[SECURITY.md (line 558)](SECURITY.md:558) says an ordinary fresh share is untouched, which S4-24 disproves.
[OpenFactorApp.swift (line 41)](OpenFactor/OpenFactorApp.swift:41) still describes a warm App Lock as swapping the root; the normative design says the warm lock is a separate window.
The tests named “during a sweep” and “while it was deciding” perform their writes before and after those operations, respectively. The identity-set property is covered by another test, but those two comments overstate their evidence.

Is this converging?
The file-reading, lock, clipboard, and capture dimensions remain converged. The directory capability is a substantial improvement and removes the worst recursive-deletion class.
The arrival/inbox dimension has now been rewritten a fifth time and is still wrong. It retains an accepted race, retains S4-30, and introduces an entry-kind mismatch. The scope remains open, although only with lows rather than the earlier medium failures.

Deletion evidence

Deletion	Evidence used	Sufficient?
take’s deferred removal	Caller supplied a UUID and attempted a bounded read	Only for an exact canonical regular entry; current discovery does not establish that
sweep(ids)	UUID identities from the caller’s snapshot	Yes for unique canonical writer output; no after basename normalization
Stale branch in collect	Sorted newest entry is stale, therefore every entry is stale	Mathematically sound only when every age is real; stale now and .distantPast fabricated for missing metadata break the premise
sweepStale	Exact enumerated name plus that entry’s mtime	Correct shape, but compared with an obsolete clock; fresh arrivals can be deleted
URL supersession	A valid newer URL arrived and product policy says it wins	Evidence of supersession, not evidence that the discarded image is recoverable


I still disagree with S4-36’s destructive aspect: any app can supply the replacing URL, while the superseded image may genuinely be a one-time source. That is now honestly documented as an accepted product trade rather than a false implementation claim, so I would not reclassify it as a new round-five code defect.
Four successful E11 runs are enough to retire the observed one-in-four S4-37 symptom for that device and build, but not to prove the SwiftUI transition. A hardware stress loop across supported iOS versions, with instrumentation asserting that the new arrival actually reaches the presented sheet, would provide stronger evidence. An explicit presentation acknowledgment with retry would settle the state-machine property more robustly than any finite run count.
One review-input gap: A4-round-four-scope1-results.md is absent from the checkout and Git history; only A4-round-four-scope1.md exists. I used the round-five brief’s full description of the neighboring finding’s shape.
