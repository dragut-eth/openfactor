# A4 verification: S4-41

**This is not a review round.** It asks two closed questions about one finding and nothing else.
It exists because review rounds in this gate have been generating more work than they close, and
the arithmetic is recorded in `HANDOFF.md`: on the night this finding came from, eleven items were
open where eight had been, and roughly eight of the eleven were defects in that day's own fixes.

So: **do not report low-severity findings. Do not review anything outside S4-41.** A thin answer is
the correct answer. If you find nothing, say so and say what you checked to be able to say it.

**The code under review is `c759ead`.** The finding was filed against `4b8317f` and is written up
in `A4-round-five-scope4-results.md`, which also carries all three round five returns in full.

Read-only. Do not build and do not run tests; keep the checkout clean.

## The finding, as filed

`SharedInbox.pending` and `SharedInbox.sweepStale` each took `now: Date = Date()`, bound at
function entry, before the directory was listed. Each entry's own timestamp was read later, just
before its own removal, but was compared against that earlier sample.

A share the extension lands during the pass therefore has an honest timestamp later than the
sample. That is the same shape as a plant stamped in 2090; the pass cannot tell them apart, and the
future-timestamp branch that exists to defeat the plant deletes the genuine share instead. In
`pending` the same mapping makes a share that lands during the listing sort as `.distantPast`,
which then places it inside the identifier set a collection supersedes.

Both engines that filed it proposed the same remedy: for each entry, stat first, then sample the
clock, then compare, with no tolerance window. One added that `pending` should omit an entry whose
metadata cannot be read rather than manufacture `.distantPast` for it.

## What was changed

`pending` and `sweepStale` take the clock as `@Sendable () -> Date` and read it after each entry's
`fstatat`. `pending` omits an entry it cannot stat instead of inventing an age for it. Nothing else
in the scope was touched: the other four round five findings are deliberately still open.

The tests are `aShareLandingDuringASweepSurvives` and
`aShareLandingDuringAListingIsNotAncient` in `SharedInboxTests.swift`. Their clock captures a
reading, writes a share, and returns the earlier reading, which is the race. Two earlier versions
of these tests did not discriminate and are described in the results file rather than hidden.

## The two questions

**1. Is S4-41 fixed? Yes or no.** If no, one sentence on what remains.

Judge the code, not the description above. In particular: is there any remaining path on which a
comparison clock is observed before the timestamp it judges, and does the future-timestamp branch
still refuse a genuine plant?

**2. Does the fix introduce a new high or medium? Yes or no.** If yes, name it and give the call
order.

The surfaces worth a look: the clock becoming a closure read many times per pass rather than once,
whether anything in either function needed a single consistent `now`; and `pending` now dropping an
entry it cannot stat, which means such an entry is neither presented nor swept.

Nothing else is in scope. Two answers and their reasoning is the whole deliverable.
