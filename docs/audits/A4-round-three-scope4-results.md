# A4 round three, scope 4: what three engines found in the fixes

Round three of scope 4 read `83e5cdd`. All three engines returned.

**Eleven of the twelve items are closed, the twelfth turns out never to have been a defect, and
nothing new is high severity.** That is six review rounds in a row without a new high.

| Engine | Verdict |
| --- | --- |
| ChatGPT 5.6 Sol | One medium, five low. "I would run another round if these findings are changed" |
| Grok 4.6 | No new findings promoted. "I would not run a fourth round on this scope for the inbox lifecycle" |
| Fable 5 | Eleven closed, one plausible wedge at the SwiftUI seam, and a retraction of its own round-two finding |

## A reviewer retracted its own finding

**S4-22 was false, and Fable filed it.** At round two it reported that no test exercised the batch
field bound. `MigrationBatchBoundsTests` had covered all three fields in both directions since
`43103dc`, which is an ancestor of the commit round two reviewed. Its greps were piped through
`head` and truncated before the tests existed in the file.

Two consequences, both mine to carry. The two tests added this round **duplicate the existing ones
almost line for line**, harmlessly. And the commit message's claim that removing the guard makes
them trap rather than fail is true of the pre-existing `UInt64.max` reproducer and not of the
over-by-one tests this commit added, which would fail politely.

Recorded here rather than quietly dropped, because the same fault produced it that produces the
defects: a claim made from an incomplete read.

## The one disagreement, and it is a real one

**Whether the future-timestamp rule should tolerate a small skew.**

ChatGPT says the strict rule rejects a legitimate write, and gives the sequence: `sweepStale`
captures `now`, the extension completes its atomic rename a millisecond later, the listing sees the
new file, its honest timestamp is *after* the captured `now`, so it becomes `.distantPast` and the
same sweep deletes a share that was never stale. It wants a tolerated skew.

Grok says the opposite in as many words: a skew allowance would reopen a slice of the same attack,
because a plant stamped two seconds ahead would sort first and stay fresh for nearly the whole
window. Zero tolerance is correct and it would not add one.

Fable sides with Grok on the policy and notes the only real casualty is a share made just before a
backwards clock correction, which costs one re-share.

**The disagreement is smaller than it looks, and the sequence is real either way.** The defect
ChatGPT describes is not the policy but the ordering: `now` is captured *before* the directory and
its attributes are read, so a file that arrives during the read is compared against a moment that
has already passed. Reading the timestamp against an observation taken *after* the attributes
satisfies both positions without a tolerance window.

## What round three added

| # | Finding | Severity | Engines |
| --- | --- | --- | --- |
| S4-23 | `take` can block the main actor on a named pipe, and the deferred removal never runs | medium | ChatGPT |
| S4-24 | `now` is captured before attributes are read, so a share arriving mid-sweep is deleted | low | ChatGPT |
| S4-25 | the unknown-name sweep can delete an in-progress atomic write | low | ChatGPT, Fable, Grok unsure |
| S4-26 | collection's deferred sweep deletes items that arrived after its own snapshot | low | ChatGPT |
| S4-27 | the inbox never fills the queue's second slot, and nothing re-collects after promotion | low | ChatGPT, Grok |
| S4-28 | the queue's promotion rides a SwiftUI binding side effect and can wedge permanently | low to medium, plausible | Fable |
| S4-29 | the extension's preflight accepts a non-regular file representation | low | ChatGPT |
| S4-30 | `pending` accepts a lowercase UUID name that `take` cannot open | low | Fable |
| S4-31 | the documentation trails the code again, in four places | low | all three |
| S4-32 | S4-22 was false; its fix duplicates tests that already existed | informational | Fable |

**S4-23 is the only medium and it is a good one.** `take` was rewritten this round to open one
handle and read through it, which closed the skip and the race. It assumes the name identifies a
regular file. A sibling with access to the app group can create a UUID-named FIFO: `pending`
accepts it, scene activation calls collection synchronously on the main actor, and
`FileHandle(forReadingFrom:)` blocks until a writer appears. The app hangs, and the `defer` that
would remove the file never runs. The fix is to open non-blocking, `fstat` the same descriptor, and
require a regular file.

**S4-28 is the one Fable would carry to a device rather than another round.** Promotion happens as
a side effect of the sheet binding being set to `nil`, so the held arrival must present while the
previous sheet is still animating out. This repository already documents that exact situation in
`AccountListView`: presenting one sheet while another animates out is a request SwiftUI drops. If
it is dropped, `current` stays non-nil with nothing on screen, collection is blocked forever, and
the queue wedges for the life of the process. Fable says plainly it cannot confirm this without a
device, and proposes promoting from `onDisappear`, which is the signal every other sheet here
already uses.

**S4-25 and S4-26 are the cost of the sweep getting more aggressive.** Deleting unknown names on
sight was the fix for S4-20, and Foundation's atomic write stages a temporary file next to its
destination; if the sweep fires while the extension is mid-write, the share fails. Grok explicitly
declines to promote this, saying it did not verify whether Darwin stages in that directory or in
the system temporary directory, and names it as the one new behaviour it would want another pair of
eyes on. **That is the open question to settle by measurement rather than by argument.**

**S4-31 is the third consecutive round where the inbox prose trails the inbox code by one fix.**
`SECURITY.md` still says five minutes when the constant is now ten and the sweep runs on every
foreground transition. `SharedInbox`'s header is a broken splice left by my own edit, with the tail
of a deleted sentence hanging mid-paragraph. "An item lives for seconds" survives in `write` and in
`SECURITY.md` after being corrected in two other places. And `sweep()` is still documented as
"removes everything, for launch", which launch does not call.

Fable's suggestion for ending that cycle is the useful one: **a CI check tying the number in
`SECURITY.md` to the constant in the code**, since the pattern says these edits are being made from
the fix account rather than by re-reading the files touched.

## Convergence, and whether to run a fourth round

All three say the surface is shrinking. They disagree on what to do next, and the disagreement is
worth keeping rather than averaging away.

**ChatGPT: run another round.** The inbox and arrival area itself has not converged, because its
third rewrite still treats a concurrently changing directory as a static collection: timestamps
compared against an earlier observation, unknown files deleted without distinguishing active
staging from leftovers, and collection sweeping names that arrived after selection.

**Grok: do not.** The three areas rewritten three times each landed on the construction the reviews
specified rather than on a new guess. It would fix the `SECURITY.md` paragraph, "because a document
that still says five minutes after the code stopped doing that is the rot this gate keeps paying
for", and stop.

**Fable: the pure cores are done, and the remaining risk has migrated to the one boundary no test
in this repository can reach.** The next real defect in this scope, if there is one, will be found
on a device rather than in the suite, and the instrument that closes it is the manual checklist.

The three are not really in conflict about the code. They are in conflict about whether the
cross-process races ChatGPT lists are worth a fourth source round, or whether they are the kind of
thing only a device settles.

---

# Measured on hardware, 2026-08-19

Two of round three's findings were about behaviour no test in this repository can reach, and both
were checked by hand on an iPhone 15 Pro running the build from `83e5cdd`, which is the commit that
introduced `ArrivalQueue`.

## S4-28 does not reproduce

**Four runs, four times the held arrival presented.** The procedure is now item 11 of the manual
checklist in `docs/APP_LOCK.md` so it can be re-run: share a QR image, wait for the import sheet to
appear, open an `otpauth://` link from another app while it is up, return, dismiss the import, and
watch for the add-account screen.

Fable's reasoning for filing it was sound and is worth keeping even though the conclusion did not
hold: promotion happens as a side effect of the sheet binding being set to `nil`, so the held
arrival must present while the previous sheet is animating out, and `AccountListView`'s own comment
records SwiftUI dropping that kind of request. **It does not drop this one.** That comment was
written about a different pairing of sheets, which is the difference.

The second shape it named, SwiftUI writing `nil` twice for one dismissal and silently discarding
the held arrival, would have shown as nothing appearing. It did not appear in four runs either.

**What this measurement does not cover:** one device, one iOS version, four trials, and a timing
dependent behaviour. The checklist item is the guard against that rather than this paragraph.

## S4-27 reproduces, and it is the one that bit

The sequence tried first was a different one: share an image, then open a link **before** OpenFactor
comes forward. The URL takes the arrival slot, `collectWhatArrived` refuses to run while anything is
current, and the shared image is never collected at all. It is not destroyed; it sits in the inbox
for `staleAfter` and presents only if some unrelated event triggers a collection later.

**On one run in four the image did appear after the link was cancelled**, which is exactly what the
finding predicts: cancelling clears the arrival, and any subsequent scene, lock or gate change
runs a collection that picks the image up. **The intermittency is the defect**, not an
observational error. Whether your share survives depends on whether an unrelated event happens to
fire.

That turns S4-27 from a reading of the code into a reproduced observation, and it raises a product
question the code has never actually answered: whether the newer arrival should win outright, or
whether the queue should hold both. The behaviour today is neither.

---

# The arrival rule was decided rather than fixed

**S4-7, S4-15, S4-27 and S4-28 were all about the same question, and the code had never answered
it.** Round one filed a second link destroying a waiting arrival. Round two filed the fix for that
silently dropping the second instead. Round three filed the queue built in answer as unable to fill
its own second slot from the inbox, and as possibly wedging at the SwiftUI seam.

Four findings, one unanswered question: **when two things arrive, which one does the person get?**

## What was decided, 2026-08-19

**The newest arrival wins, and the superseded one is swept.** The queue is removed.

The reasoning, in the order it actually weighed:

**The normative page already said so.** `docs/APP_LOCK.md` has always stated that an arrival takes
precedence and whatever was open closes. The queue was the thing that contradicted it, and building
the queue required amending that page to carry an exception to its own rule.

**The queue was more surface in the place this gate keeps finding defects.** S4-28 exists only
because the queue exists, and so does S4-27. Two findings in the app target no test can reach,
created by a mechanism whose purpose was to avoid losing something recoverable.

**Neither loss is a loss.** A superseded link can be tapped again; a superseded share can be shared
again. Nothing is added without a tap under either rule.

**First-wins is the worse rule against a hostile sender**, which is the opposite of the assumption
behind it. Under first-wins, whatever arrives first occupies the slot and blocks a genuine share
until it is dismissed. That is precisely the sequence reproduced on hardware.

## What this reverses, deliberately

**S4-7 and S4-15 are closed by decision rather than by code.** A second arrival destroying a pending
one was filed as a defect twice, by reviewers reasoning from the code with no rule to check it
against. There is a rule now, it is written in the normative page and in the source, and the
behaviour follows it.

**A reviewer may well file it again**, and that is expected rather than a problem. The answer is
this section: it is a decision with reasons, taken by the person whose app it is, after using it on
a phone.

**S4-28's measurement stands and is now moot.** Four runs out of four showed the queue promoting
correctly. That measurement is what proved the queue worked, and the queue was removed anyway,
because working was never the question.

**S4-27 is closed by the sweep.** The intermittent reappearance was the superseded share sitting in
the inbox waiting for an unrelated event. It is taken off the device at the moment it is
superseded.
