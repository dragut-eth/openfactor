# A4 round five, scope 4: the sweep split, and the directory as a capability

**The code under review is `4b8317f`**, with `9df180c` adding the hardware record and this brief on
top. Round four read `1bf4b26`, round three `83e5cdd`, round one `74fe841`. Every prior round's
results are in `docs/audits/`, with all three returns in full.

**Files:** as round four, in `A4-round-four-scope4.md`, plus
`Sources/OpenFactorCore/Inbox/InboxDirectory.swift`, which is new.

Read-only. Do not build and do not run the test suite; keep the checkout clean.

## Scoring, unchanged from round four

A finding that lives only in a comment or a document is recorded but does not hold the scope open.
Report false claims; do not treat hunting them as the job.

## Read this before anything else

**Round four's worst finding was created by round three's fix, and the scope has just done it
again in a neighbouring scope.**

S4-32 was reachable only because closing the named-pipe hang turned a blocking read into a fast
failure, so a `defer` that had never run before started running. In the same session, scope 1's
round four returned a high with the identical shape: a correct fix for the finding, plus a cleanup
nobody asked for stapled to it, and the cleanup deleted data on an inference it had no evidence
for. All three engines found that one. It is written up in `A4-round-four-scope1-results.md` and it
is worth reading before you start here, because **this round's changes are largely about deciding
what to delete.**

So the question this round most wants answered is not whether the fixes address their findings. It
is: **does anything here delete, or stop deleting, something on the strength of an inference rather
than evidence?**

## What changed

**`sweep` became two operations, because it was two ideas under one name.** `sweepStale` collects
garbage and decides by age. `sweep(_:)` supersedes a set the caller has already chosen against and
decides by identity. Both callers now pass the identifiers they read, so a file written after that
reading is not in the set.

That closed S4-26 and S4-35. Attack the split itself: is "the caller passes what it read" actually
sound when the caller's reading is stale by the time the deletion runs, and is there a case where
the set is right but incomplete in a way that lets something accumulate forever?

**S4-32.** The supersede moved out of the `defer` onto the paths where something was judged: a
successful take, or a set the freshness rule rejected. A failed take now leaves everything except
the item that failed, which `take` removes itself. **Check the stale path specifically**: it
supersedes the whole set on the reasoning that every item read is at least as old as the newest.
Say whether that reasoning holds.

**S4-24 and S4-25.** Each timestamp is read immediately before its own removal. The unknown-name
deletion is age gated rather than immediate, **which deliberately walks back S4-20, a finding this
gate accepted**, on the grounds that in a group whose only members are this app's own targets, the
foreign name being deleted on sight is almost always our own atomic write in progress. Say whether
that reversal is right, and what it costs against a sibling that plants names on purpose.

**S4-33, done as capability rather than as timing.** `InboxDirectory` opens the inbox once with
`O_DIRECTORY | O_NOFOLLOW` and does enumeration, timestamps, reads and deletions relative to that
descriptor. Deletion is `unlinkat` without `AT_REMOVEDIR`. Reads go through `openat` into the same
bounded primitive, which was split so there is still one implementation of the bounded read.

**This file is new, unreviewed, and is raw POSIX in a project that otherwise uses Foundation.**
Attack it directly: the `dup` before `fdopendir`, the `d_name` rebind, the descriptor's lifetime
against the `~Copyable` deinit, `fstatat` with `AT_SYMLINK_NOFOLLOW`, and whether `unlinkat`
without `AT_REMOVEDIR` is genuinely non-recursive on every entry kind. **One bug in this file is a
bug in every inbox operation at once**, which is the same single-point-of-failure argument round
four applied to `BoundedFile` and cleared.

The write path is checked rather than bound: it opens the directory first and refuses if that
fails, which does not cover a substitution between the check and the write. The code says so. Say
whether that concession is acceptable or whether the write needs the same treatment.

**A bug in this file was found by the tests during the work and is disclosed here rather than left
to be discovered**: the first `fstatat` read whole seconds only, so two items written in the same
second sorted arbitrarily, which is the ordering the whole newest-wins rule depends on. It now
includes nanoseconds. Look for anything else of that kind.

**S4-34.** Collection re-runs when the arrival clears, so a share made while a link was open
presents on dismissal rather than waiting for an unrelated event.

## What was rejected, and what was measured

**S4-36 is rejected.** A superseded arrival stays destroyed. The reasoning is the maintainer's:
sharing two codes at once is a person doing something unusual, and retention means keeping a
transfer QR, every secret in one image, alive longer than the design allows, to insure against a
sequence somebody would have to construct on purpose. Two of three engines already landed near
this. What was conceded is the claim rather than the policy: "it can be shared again" is customary
rather than guaranteed, and that is now written down.

**Argue with the rejection if you disagree.** It is a product decision and it is recorded so that
it can be, not to close the question.

**S4-37 was measured, four runs out of four, on an iPhone 15 Pro carrying this build**, and is
recorded in `E11-two-arrivals-of-different-kinds.md`. The three outcomes were named before the runs.
The fourth run was a variant the tester improvised: the app was not opened between the share and
the link, so the link superseded an item still uncollected in the inbox, which is a different path
and the one `sweep(_:)` was rewritten for.

**Four runs is not proof, and E11 says so.** The defect it replaced showed at one in four. Say
whether you think four runs settles it, and if not, what would.

## Nothing is open

Unlike round four, this round is not carrying known findings. Every item round four produced is
fixed, rejected in writing, or measured.

## What to answer

1. **Does each change address the finding it claims to?** A fix that moves a check without changing
   what is checked, or that handles the case while leaving the class open, is a finding.

2. **Did any change introduce something new?** Two of the last three rounds in this scope answered
   yes, and the most recent one in the neighbouring scope answered yes with a high. Assume this
   round did too and go looking.

3. **Is anything claimed in a comment or document that the code does not do?** Recorded, weighed as
   above.

4. **Is this converging?** Round four's verdict was split: the file-reading dimension had converged
   and the arrival and inbox dimension had not, having been rewritten four times. Say where it
   stands now, and say plainly if the answer is that it has been rewritten a fifth time and is
   still wrong.

5. **The deletion question, answered directly.** Every deletion this scope performs: what evidence
   does it rest on, and is that evidence sufficient? Name anything deleted on inference.

You are not bound by any previous round's conclusion, including your own. This gate has had a
reviewer retract its own finding, has rejected fixes that came with passing tests written by
whoever wrote the fix, and has just had a high filed against a mechanism its own author proposed.
**Saying that an earlier conclusion was wrong is in scope.**
