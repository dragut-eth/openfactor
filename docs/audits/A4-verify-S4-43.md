# A4 verification: S4-43

**This is not a review round.** Two closed questions and nothing else. Do not report low-severity
findings beyond answering these. Do not review anything outside S4-43. **A thin answer is the
correct answer.**

**The code under review is `a16e5fe`.** S4-43 was filed in `A4-round-five-scope4-results.md`, which
carries all three round five returns in full. The verification rounds for this scope are
`A4-verify-S4-41-results.md` and `A4-verify-S4-42-S4-44-results.md`.

Read-only. Do not build and do not run tests; keep the checkout clean.

**Already open, so do not report it:** S4-45, the remaining false claims, is filed and untouched.

## The finding, as filed

`SharedInbox.pending` converted a basename to a `UUID` and discarded the original spelling, while
`take` and `sweep` rebuilt the path from `id.uuidString`, which is canonical uppercase. On a
case-sensitive volume those name two different files: the entry observed and selected is not the
entry read or deleted, and with both spellings present the app can choose on one entry's timestamp
and act on the other.

The filed remedy offered two forms: require `name == id.uuidString` before returning a `Pending`, or
retain the exact validated basename through selection, reading and deletion.

## What was changed

The narrow form. `pending` requires `name == id.uuidString`.

**The reasoning for the narrow form**: this app writes `id.uuidString` and nothing else, so the
requirement can only ever turn away a name somebody else wrote. The fuller form ripples through
four files and two suites to reach the same property, and this scope has repeatedly been damaged by
changes larger than their findings.

## The two questions

**1. Is S4-43 fixed? Yes or no.** If no, one sentence on what remains.

Judge the code. Is there any remaining path on which the entry observed and the entry acted on can
differ? Does every write in this app really produce `id.uuidString` exactly, including the
extension's? And is the narrow form genuinely sufficient, or does discarding the basename still
matter somewhere the guard does not reach?

**2. Does the fix introduce a new high or medium?** Yes or no. If yes, name it and give the call
order.

The surfaces where the author is least confident:

- **What now happens to a non-canonical name.** It is no longer an item, so it is never presented
  and never superseded by a collection. `sweepStale` still ages it out, because that path judges by
  age and not by name. Confirm that, and say whether anything can now accumulate that could not
  before.
- **The interaction with S4-42's regular-file requirement.** Both guards sit in the same `compactMap`
  and both narrow what becomes a candidate. Say whether they compose or whether one masks the other.
- **iOS volumes are case-insensitive by default**, which is why this survived three rounds. The claim
  being made is that the code no longer depends on that. Say if it still does somewhere.

Nothing else is in scope. Two answers and their reasoning is the whole deliverable.
