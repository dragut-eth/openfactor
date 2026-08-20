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
