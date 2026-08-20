# A4 verification: S4-42 and S4-44

**This is not a review round.** It asks two closed questions and nothing else. Do not report
low-severity findings. Do not review anything outside these two items. **A thin answer is the
correct answer**, and an answer that says what was checked in order to conclude nothing is more
useful than one that manufactures a finding.

Both items are here together because both change `InboxDirectory`, and one of them changed it in a
way nobody asked for.

**The code under review is `cab3312`.** Both findings were filed against `4b8317f` and are written
up in `A4-round-five-scope4-results.md`, which also carries all three round five returns in full.
The previous verification round, on S4-41, is in `A4-verify-S4-41-results.md`.

Read-only. Do not build and do not run tests; keep the checkout clean.

## S4-42, as filed

`SharedInbox.pending` admitted any entry whose name parsed as a UUID, without requiring it to be a
regular file. A sibling can create a directory with a canonical UUID name. Admitted, it sorts by
its own timestamp and becomes what a collection reaches for; `take` opens it, the bounded read
refuses it as not a regular file, and the deferred removal is `unlinkat` without `AT_REMOVEDIR`,
which refuses directories. So a genuine share sits unseen behind something that can be neither
collected nor removed, and is hidden again on every attempt if the plant's timestamp is refreshed.

The filed remedy: admit only canonical UUID-named regular files; optionally remove empty
directories with `AT_REMOVEDIR`; never restore recursive deletion.

**What was changed.** `pending` now requires a regular file. `InboxDirectory.entry(_:)` returns the
timestamp and the kind from a single `fstatat`, and `modified(_:)` is that call with the kind
discarded. `sweepStale` deliberately still uses `modified`, so it keeps removing a stale leftover
whatever kind it is.

**The optional half was declined**, and this is the part most worth disagreeing with if you think
it is wrong. `AT_REMOVEDIR` was not added, because it adds deletion authority to a scope that has
produced a high and a medium by adding exactly that. The consequence is accepted and stated: a
planted directory stays forever, unlistable as an item and unremovable by the sweep.

## S4-44, as filed

The whole-seconds ordering bug disclosed during round five had no regression test, and
`InboxDirectory` had no direct test at all. It was exercised only through `SharedInbox`.

**What was changed.** `InboxDirectoryTests` was added. **On its first run it failed, and the
failure was a real defect in the primitive that all three of you cleared by reading.**

`names()` handed `fdopendir` a `dup` of the type's own descriptor, so that `closedir` would not
close the one the type keeps. A `dup` shares one file offset with the original, so reading the
stream to its end leaves that shared offset at the end: **a second listing through another `dup`
starts at the end and reports an empty directory, silently.** One round five return named this
mechanism and concluded that `dup` was why a second listing does not resume a consumed stream.

`names()` now opens `.` relative to its own descriptor, which gives an independent file offset.
Two callers exist and each lists once per handle, so nothing in the app reached this; the fix is
prophylactic and was made because the failure mode is silence rather than an error.

## The two questions

**1. Is each item fixed? Yes or no, for each of S4-42 and S4-44.** If no, one sentence on what
remains.

Judge the code rather than the description above. For S4-42, the thing to test is whether any
entry that is not a regular file can still become a candidate, and whether the sweep still removes
by age what it should. For S4-44, whether `openat(descriptor, ".", …)` genuinely yields an
independent offset, whether the new tests would actually fail against the defects they claim to
pin, and whether the ordering property now has coverage that whole-second resolution would break.

**2. Does either fix introduce a new high or medium? Yes or no.** If yes, name it and give the
call order.

The surfaces worth a look, named because they are where I am least sure:

- `entry(_:)` returning two values from one `stat`, and `modified(_:)` becoming a wrapper over it.
  Any caller that wanted the old behaviour for a non-regular entry.
- `names()` opening a new descriptor per listing rather than duplicating one: lifetime, the close
  path when `fdopendir` fails, and whether `.` can be anything other than the directory the
  descriptor already names.
- The asymmetry itself: the reading side now insists on a regular file and the sweeping side does
  not. Say if that split is wrong.
- The declined `AT_REMOVEDIR`, and whether a permanently unremovable directory in the group
  container is worse than the deletion authority that removing it would require.

Nothing else is in scope. Two answers and their reasoning is the whole deliverable.
