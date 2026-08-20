# A4 round five, scope 2: the round the stop rule was written for

Round five read `9304d6c`. All three engines returned, and **they disagree about whether the scope
can close.**

| Engine | Verdict |
| --- | --- |
| Grok 4.6 | "Nothing above low. I am not calling a fix incomplete. Against the exit condition written for this round, this pass meets it" |
| Fable 5 | "This round returns no findings at low or above. Scope 2 passes, and my recommendation is to stop" |
| ChatGPT 5.6 Sol | "No medium or high findings, but three low findings mean the stop condition is not yet met" |

**The exit condition has two halves: nothing above low, and no fix called incomplete.** All three
agree on the first. The second is what splits them, and one of the two things ChatGPT calls
incomplete is a plain miss that a second engine confirmed.

## The disagreement that is settled by fact

**S2-17's fix was applied in one file and not the other.** Round four rejected the claim that what
stayed behind in the app targets is not a decision. I corrected it in `ProvisioningDesk`'s header
and left the same sentence standing in `WatchKeyProvider`, which is the file the extraction was
meant to empty.

Both ChatGPT and Grok found it. Grok's phrasing: *"this comment is the sentence round four
rejected, left in the file the extraction was meant to empty."*

That is not a matter of judgement. **The fix is incomplete**, and by the rule as written, this round
does not close the scope. ChatGPT reached the right conclusion, partly for a reason the other two
reject.

## The disagreement that is genuine

**Whether the exact consent boundary matters.** `isAnswerable` accepts `elapsed <= 120s`, so a wake
at exactly 120.000 seconds leaves the request answerable while the one-shot timer, having asked
once, never asks again.

- **ChatGPT** files it: make it `<`, and add a boundary test anchored on `validatedAt`.
- **Grok** walked the whole table and did not file it: `Task.sleep` waits *at least* the duration,
  and `validatedAt` is stamped before the sleep is scheduled, so the wake is always past the window
  by that gap plus scheduler slack. It notes it cannot make `Task.sleep` produce exactly 120.000.
- **Fable** calls it measure zero on a continuous clock, records it rather than filing it, and adds
  that `<` merely trades this for an equally measure-zero refusal of a perfectly timed tap.

Two say physics, one says change the character. Filed below as its own item so the decision is
recorded either way.

## What round five added

| # | Finding | Severity | Engines |
| --- | --- | --- | --- |
| S2-19 | the exact consent boundary is inclusive, so a wake at precisely the window expires nothing | low, disputed | ChatGPT files it, Grok and Fable record it |
| S2-21 | a malformed request is answered `declined` with no nonce, which two documents say means an old build | low | ChatGPT |
| S2-22 | the comment claiming only an answer can arrive on the reply path is false | low | Fable, Grok |
| S2-23 | a test anchors on a fresh clock read rather than `validatedAt`, so a stall can flake it red | low | Fable |

**S2-21 is the sharper of the four, and it is the same shape as S2-14.** The consolidation covered
standalone refusals: `refuse(naming:)` takes a non-optional nonce, so an unbound decline cannot be
built. The **direct reply** to a request was not covered — a forty byte piece of rubbish is answered
`["status": "declined"]` with no nonce, straight from the reply wrapper. ChatGPT is careful about
what this does and does not mean: it is not exploitable, because a reply is bound to its request's
reply handler and guarded by the watch's flow token. What is wrong is the documents: `VAULT.md` and
`SECURITY.md` both say a nonce-less decline identifies an older build, and a current build sends
one.

**S2-22 is a comment I wrote in this batch.** `phoneAnswered` says the only case that can arrive is
`.answer`. A current phone replies `declined` to a malformed request, which classifies as
`.decline` and lands in the else branch. The behaviour is right — both paths reach the same terminal
— but, as Fable put it, it is right by convergence of two paths rather than by the stated reasoning.

**S2-23 is a flake waiting to happen**, and worth taking seriously in a suite this project leans on
for mutation checks. `aFractionInsideStillReleases` builds its instant from a fresh `.now` after
`received` stamped `validatedAt`, so the real elapsed time is 119.999 seconds plus whatever gap
separated the two reads. A one millisecond stall turns a release into a refusal and the test red for
no product reason. `ageIsMonotonic` already shows the robust pattern.

## What was verified rather than accepted

**Grok walked the whole boundary table** rather than the two instants the batch tested, and
confirmed the production timer's wake is always past the window.

**Both engines checked the closure's lifetime**, which was one of the four questions the brief
asked: `Conditions` is a parameter, used and dropped; the desk stores only the `ValidatedRequest`;
the capture is the key store, a directory getter, not the key.

**Fable enumerated every dictionary a phone this build can send as a direct reply** and traced each
through the new reader, which is how S2-22 surfaced.

**Both re-checked the earlier rounds' rules on this tree**: first-wins pending, `.busy` non-terminal
only while waiting, attempt lifetime following the flow, the backward-clock refusal, the three-state
decline nonce, the guarded `phoneDeclined`, no re-ask, approval still only the affirmative button.

**Two fixes were completed more broadly than asked.** A seal failure in `respond` now refuses
instead of going silent, which round four did not name, and the reply path gained a third pinning
test.

## Convergence, and the rule doing its job

All three say converging, and Fable's trajectory is the clearest summary:

> Round one found key-adjacent defects; round two found fixes fighting each other; round three
> found a fix implemented on one side of a seam; round four found wire hygiene and an inert timer;
> round five finds a comment clause and a test anchor.

**And the stop rule earned its keep on its first use.** Two engines were ready to close the scope.
The rule held it open, and the thing it held it open for was real: a correction applied to one file
and not to its twin, which is the exact failure mode this gate has now produced four times.

Fixing the four items above is perhaps an hour. A sixth round on that would be the one that closes
it, and both of the engines recommending a stop would presumably say so again.

---

# What was done

**The code under review is `1f7e65f`.** All five are fixed.

**S2-17**, the one that held the scope open. The claim now names the two decisions that genuinely
stayed in `WatchKeyProvider`: when to arm the expiry timer, and that a refusal it cannot name is not
sent at all. It also records that this copy was left behind when its twin was corrected, because the
pattern is the point.

**S2-19.** The comparison is strict, and both sides of that instant now have a test. Grok and Fable
are probably right that `Task.sleep` cannot produce it; the character costs less than an argument
nobody can rerun, and the tests make it permanent either way.

**S2-21.** The documents were wrong, not the code. A reply returns through the handler of the
message that asked, so it is bound by the channel rather than by a nonce, and a request that failed
to parse has none to echo. `VAULT.md` and `SECURITY.md` now distinguish a standalone refusal from a
reply, and the reply site says why.

**S2-22.** The comment says what actually arrives, including the `declined` reply that lands in the
branch the comment claimed nothing could reach.

**S2-23.** `ProvisioningDesk` exposes the pending request's instant, and the three window tests
anchor on it rather than on a fresh clock read.

Each was reverted individually where it had a test to revert against.

## For round six

**This is the round that can close the scope.** Round five failed the exit condition on one half
only, and that half was a sentence in a second file.

The four questions, and the honest places to attack:

**S2-19 was decided against two engines' advice.** If either still thinks the strict comparison is
wrong, or that it trades one unreachable instant for another that matters more, say so: it is one
character in either direction and the tests would move with it.

**S2-21 was answered by changing documents rather than code.** The argument is that the reply
channel binds the answer to its request, so the nonce adds nothing there. If that reasoning is
wrong, the fix is the opposite one and the wire changes.

**The `refuse(naming:)` consolidation now has three callers and one non-caller**, the reply
wrapper. That asymmetry is deliberate and freshly documented, which makes it the kind of thing worth
a second reading.

**Nothing else in this scope changed.** If this round finds nothing above low and calls no fix
incomplete, scope 2 meets the gate's exit condition and stops being reviewed.
