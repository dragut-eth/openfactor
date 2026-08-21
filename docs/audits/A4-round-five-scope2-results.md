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

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Grok:
1. Does each change address the finding it claims to?

S2-12, the timer that expired nothing — yes. isAnswerable no longer goes through age. It is elapsed >= .zero && elapsed <= .seconds(window) on the raw Duration. Whole-second truncation is gone.

I walked the bounds, not only the two new tests:

┌─────────────────────────────────┬──────────────────┬─────────────────────────────────────────────┐
│ Instant relative to validatedAt │ isAnswerable     │ Who asks                                    │
├─────────────────────────────────┼──────────────────┼─────────────────────────────────────────────┤
│ −3600 s                         │ false            │ approve (tested)                            │
├─────────────────────────────────┼──────────────────┼─────────────────────────────────────────────┤
│ 0                               │ true             │ first moment                                │
├─────────────────────────────────┼──────────────────┼─────────────────────────────────────────────┤
│ 119.999 s                       │ true             │ tested                                      │
├─────────────────────────────────┼──────────────────┼─────────────────────────────────────────────┤
│ 120.000 s                       │ true (inclusive) │ untested, and that is the window they chose │
├─────────────────────────────────┼──────────────────┼─────────────────────────────────────────────┤
│ 120.001 s                       │ false            │ expire at the timer’s wake (tested)         │
├─────────────────────────────────┼──────────────────┼─────────────────────────────────────────────┤
│ 120.500 s                       │ false            │ approve (tested)                            │
├─────────────────────────────────┼──────────────────┼─────────────────────────────────────────────┤
│ 121 s                           │ false            │ old expire test                             │
└─────────────────────────────────┴──────────────────┴─────────────────────────────────────────────┘

The production timer still sleeps .seconds(120) then calls expire with .now. That is not “wake at 120.000.” Task.sleep(for:) waits at least the duration, and validatedAt is stamped before the sleep is scheduled, so elapsed at wake is 120 s plus that gap plus any scheduler slack. That is past <= .seconds(120), so expire returns the nonce. The comment that claims this is describing that gap, not claiming 120.000 itself is expired.

A timer that woke at exactly validatedAt + 120.000 s would still no-op. I do not have a way to make Task.sleep do that.

S2-13, key read before validate / frontmost — yes. hasVault is a @Sendable () -> Bool. received is: parse, then isFrontmost, then hasVault(), then pending == nil. Rubbish and background tests record that the closure was not called.

It is called on the .busy path: a second well-formed request while the phone is frontmost loads the key and then returns .busy. That is after the two guards the finding named, once per received. It is not the old ordering.

The closure is not stored on the desk. Conditions dies when received returns. [keys] captures a VaultKeyStore (a directory getter), not the 32 bytes. Nothing in it outlives the request.

S2-14 and S2-15, unbound decline / silent load-fail — yes, and they really were one rule. One refuse(naming:) always sends status plus a 16-byte nonce. decline() returns without sending when the desk names nothing, which is the timer-versus-Not-now race. approve asks the desk first; a key is read only for .release; load or respond failure sends the same named refusal as expiry, using the nonce already taken off the desk.

A current build cannot emit the nonce-less decline the watch still honours as “old phone.”

S2-16 — yes for this phone. The reply handler runs WatchInbox.classify. This phone’s reply is only {status: …}. asking / busy / needsApp / noVault become .answer. {status: declined} (rubbish) becomes .decline(.absent), which the else treats as phoneAnswered(nil) — same terminal as before. An empty [:] reply is .unrecognised, also a refusal. This phone never puts a sealed payload in the reply; if it did, classify would prefer response and the reply path would now drop it. Fail closed. No build this app talks to sends that.

S2-17 — yes as documentation, not as a move. The overclaim is gone from ProvisioningDesk. The comment lists the timer arm and the watch cadence and says they were left on purpose. Agreed they produced no finding in this gate. The arming line is still the one whose deletion would leave every desk test green and auto-clear dead.

S2-18 — yes. responseWinsOverStatus pins classify order. theDeskTakesAnotherAfterAnswering pins asked–answered–asked.

Earlier-round rules I re-checked on this tree: first-wins pending, .busy non-terminal only while .waiting, releaseAttemptIfFinished follows flow.isAsking, isAnswerable fails closed on a backward now, decline nonce three-state, phoneDeclined still guarded, no re-ask on obsolete, approval still only the affirmative button, alert setter still a no-op, watchAsking still isAsking && !lock.isLocked.

───

2. Did any change introduce something new?

The consolidation is the place to look. Three callers now share refuse(naming:). If that method dropped the nonce, every refusal would become the S2-14 bug at once. Today every caller that reaches it already has a Data nonce, and the one that does not (desk.decline() == nil) does not call it.

hasVault() on .busy is a new wasted read, not a new leak. Parse and frontmost have already passed.

Treating a non-.answer reply as phoneAnswered(nil) is new on the reply path and matches the old “unknown status is a refusal” rule for everything this phone sends.

I do not see a new way to release without a tap, to overwrite pending, or to install a key from an unverified or abandoned attempt.

The last mile of S2-14 (guard let nonce = desk.decline() else { return }) still lives in WatchKeyProvider and still has no test. The desk returning nil is tested; not sending on nil is not. The code does the right thing when read. That is residue of the seam, not a broken fix.

───

3. Claims the code does not do

• WatchKeyProvider still says “every rule that used to live in this file is in there now” and “what is left here is the session, the alert, the key file and the sending.” The timer is armed here. refuse(naming:) lives here. ProvisioningDesk’s header is the accurate one; this comment is the sentence round four rejected, left in the file the extraction was meant to empty.
• phoneAnswered says “the only case that can arrive here is .answer.” {status: declined} classifies as .decline and takes the else. For this phone that is only the rubbish path, and it still ends the attempt. The sentence is too tight.
• docs/VAULT.md still says a decline’s nonce is present. That is now true of every decline this build sends. The mixed-version honour-absent rule remains for older phones.

SECURITY.md’s “echoes the nonce of the request being refused” matches refuse(naming:).

───

4. Is this converging?

Yes. This is the small residue round four enumerated, not a new family.

The timer is the third attempt at the same deadline. This time the test asks at the instant the sleep actually produces, and the comparison is the same type as the clock. I would not rewrite it a fourth time.

The extraction stood. These seven did not force another move. Cadence is still in the app by an explicit decision. The remaining untested last miles are one-liners (else { return }, if answer == .asking).

Nothing above low. I am not calling a fix incomplete. Against the exit condition written for this round, this pass meets it.

The cryptography and the 85/145 parsers were not touched. Approval is still a human tap. I did not find a way to seal to a request the owner is not being shown.

Fable:
Round five of Scope 2, same recorded asymmetry: this session holds rounds one through four. Reading the round-four results and the new diff.

Ran 6 commands, read A4-round-four-scope2-results.md
A4 round five, scope 2: the seven, reviewed

Commit reviewed: 9304d6c (checkout a7bc30a, differing only in the results file, verified). Round four read ae90bcb; the chain back to 74fe841 is unbroken. Standing asymmetry, recorded a final time: this session holds all four prior rounds, and three of the seven fixes respond to findings that were mine or partly mine.

Verdict in one paragraph: all seven fixes are complete, none is incomplete or cosmetic, and nothing new was introduced above the level of a comment that overclaims and a test anchor that could flake. I walked the four attack questions the account posed — the timer's boundaries, the closure's lifetime, the consolidated refusal, and the reply path's new reader — and all four hold. This round returns no findings at low or above. Against the gate's own exit condition — nothing above low, no fix called incomplete — scope 2 passes, and my recommendation is to stop.

Question 1: does each fix address its finding?

S2-12, the timer arithmetic — yes, at every boundary I could construct. isAnswerable now compares Duration directly, untruncated, and age() is demoted to display duty with a comment saying exactly that. The account asked for the boundaries beyond the two the batch tested, so: a wake at window-plus-any-fraction expires (tested at +1ms); a tap a fraction inside releases (tested at −1ms); a backward reading refuses (carried from round three, still pinned); and the one boundary left is exact equality — elapsed == 120.000… to attosecond precision keeps the request answerable while the one-shot timer, having asked its one question, never asks again. That case has measure zero on a continuous clock: Task.sleep guarantees at least the duration and scheduling latency is never exactly nothing, so the guard is physics rather than code. I record it rather than file it; if anyone ever wants it gone, < instead of <= trades it for an equally measure-zero refusal of a perfectly timed tap.

S2-13, the eager key read — yes, and proven the right way. hasVault is a closure the desk consults only after the length check and the frontmost check, and the two new tests assert whether the question was asked, not what it answered — which is the only test shape that could have caught the original defect, and the account's own diagnosis of why rubbishIsRefused couldn't. The account's two specific worries, verified in code: the closure is called at most once (one guard, one call site, and the desk never stores Conditions — it is a parameter, used and dropped, so nothing captured in it outlives the received call; pending holds only the ValidatedRequest); and approve() was reordered to match, reading a key only on .release, so the desk's new doc comment ("the caller now reads a key only for .release") is true.

S2-14 and S2-15, the one refusal — yes, and structurally rather than by discipline. refuse(naming:) takes a non-optional nonce, so the class of unbound declines is closed by the type signature, not by three call sites remembering a rule. decline() on an empty desk now sends nothing, which is correct in the only sequence that reaches it (the expiry timer already sent the bound refusal; the watch needs exactly one). The no-key path refuses with the request's nonce, and the fix quietly covers a third case round four didn't name: a seal failure in respond now also refuses instead of going silent. On the consolidation worry — "how four entry points become wrong together" — the shared method is three lines building a two-key dictionary whose keys are pinned by messageKeysArePinned; there is no rule inside it left to be wrong.

S2-16, one reader for the vocabulary — yes, with one comment overclaim. I walked every dictionary a phone this build can talk to may send as the direct reply. Four of the five statuses classify as .answer and flow exactly as before; an unknown string classifies as .answer(nil) and lands on the refusal rule as before; a missing or non-string status is .unrecognised, into the else, refusal, as before. The interesting one is "declined": a current phone does send it as a direct reply — received answers .declined to a malformed request — and classify routes a declined status to .decline(...), not .answer(.declined), so it lands in the guard's else branch. The outcome is identical (phoneAnswered(nil) and phoneAnswered(.declined) reach the same case .declined, .none and the same release), so behavior is correct — but the new comment's claim that "the only case that can arrive here is .answer" is false: a nameable, current-build reply arrives there too, and is right by convergence of two paths rather than by the stated reasoning. One clause fixes it. A protocol-evolution footnote, not a finding: a hypothetical future phone replying with the sealed key in the reply would classify as .sealedResponse, fail the guard, and be treated as a refusal — no current or past build does this, and doing it would be a protocol change owning its own versioning.

S2-17 — yes. The claim is replaced by an enumeration that matches what I find in the files: the timer's arming condition and the watch's asking cadence, with the non-move reasoned in writing ("none of them produced a finding in this gate"), which is a position a review can disagree with rather than a claim it has to disprove. I don't disagree with it this round: four rounds of pressure on the cadence produced nothing, and moving code that has produced no findings is churn.

S2-18 — yes, both one-liners exist, plus a third (directReplyIsAnAnswer) that S2-16 needed.

Question 2: did the fixes introduce anything?

Nothing at finding level. Two things at note level:

A test anchor that can flake. aFractionInsideStillReleases builds its "just inside" instant from a fresh .now read after received stamped validatedAt, so the real elapsed time is 119.999s plus the gap between those two reads. A one-millisecond stall there — a preempted test process on a loaded CI machine — flips the release into a refusal and the test red for no product reason. ageIsMonotonic already shows the robust pattern: anchor on request.validatedAt itself, which @testable reaches. The two outside-the-window tests only benefit from the gap and cannot flake this way.
The phoneAnswered comment overclaim described under S2-16.
Question 3: claims vs. code

The S2-16 comment is the only false statement I found in the changed code. The desk's rewritten header, the Conditions.hasVault contract ("called at most once, and only after…"), the isAnswerable history note, and the age demotion note are all accurate against the code as it stands. The SECURITY.md changes in this commit belong to scope 4's inbox and make claims about SharedInbox constants, not about this scope.

Question 4: convergence, and the stop rule

The trajectory across five rounds, in one line each: round one found key-adjacent defects; round two found fixes fighting each other; round three found a fix implemented on one side of a seam; round four found wire hygiene and an inert timer; round five finds a comment clause and a test anchor. That is a defect surface shrinking in both size and kind, and this round's residue is the first that requires no code to change to keep the security story true.

Against the exit condition the results file states — nothing above low, and no fix called incomplete — this round passes both halves. All seven fixes are complete; two were completed more broadly than asked (the seal-failure refusal under S2-15, the third pinning test under S2-18); the four "look hardest" questions all resolve in the code's favor. What I would leave behind as the closing residue, none of it gating: fix the one comment clause, re-anchor the one test, and keep the two recorded non-findings (the measure-zero boundary, the sealed-response-in-a-reply footnote) in the audit record rather than in anyone's queue.

Scope 2 is done being reviewed. The state machine that produced five defects in its first three rounds has now survived two consecutive rounds of directed attack with nothing above a nit, its rules live where tests reach them, and the last prediction this gate made about it — that the next defect would be in the app files — has finally come up empty. Stopping here is not fatigue; it is the stop rule doing what it was written to do.

ChatGPT:
Reviewed 9304d6c; the checkout is a7bc30a and differs only in the stated results document. I found no medium or high findings, but three low findings mean the stop condition is not yet met.
Findings
Low — the exact consent deadline still does not expire
[WatchProvisioning.swift (line 318)](Sources/OpenFactorCore/Vault/WatchProvisioning.swift:318) still considers elapsed == 120 seconds answerable because the comparison is inclusive. [`ProvisioningDesk.expire` (line 148)](Sources/OpenFactorCore/Vault/ProvisioningDesk.swift:148) consequently returns nil at that instant, and [`expireConsent` (line 171)](OpenFactor/Vault/WatchKeyProvider.swift:171) is one-shot.
Concrete order: validation and timer arming receive the same reported clock instant; Task.sleep(for: .seconds(120)) resumes exactly at its deadline; elapsed is exactly 120; isAnswerable returns true; the task ends without clearing the alert. The new tests cover 119.999, 120.001, and 120.500 seconds, but omit exactly 120.000.
Smallest fix: make freshness elapsed < .seconds(window), so expiration begins at >= window, and add an exact-boundary test based on validatedAt.

Low — a current phone can still send the nonce-less decline claimed to identify an old build
A 40-byte Data request makes [`ProvisioningDesk.received` (line 99)](Sources/OpenFactorCore/Vault/ProvisioningDesk.swift:99) return .declined. The reply wrapper at [WatchKeyProvider.swift (line 197)](OpenFactor/Vault/WatchKeyProvider.swift:197) then sends only:
["status": "declined"]
This bypasses the consolidated refuse(naming:) method and carries no nonce. That contradicts [docs/VAULT.md (line 354)](docs/VAULT.md:354) and [SECURITY.md (line 308)](SECURITY.md:308), which say a nonce-less decline comes from an older build.
This does not reopen the stale unsolicited-decline exploit: the direct reply is tied to the request’s reply handler and guarded by the watch’s flow token. The smallest fix is therefore to document the distinction explicitly: standalone refusals are nonce-bound, while a malformed request may receive a callback-bound nonce-less negative reply. Alternatively, stop encoding malformed-request replies as "declined".

Low — the extraction claim rejected in round four remains in the app target
[WatchKeyProvider.swift (line 34)](OpenFactor/Vault/WatchKeyProvider.swift:34) still says “Every rule that used to live in this file is in there now” and that only session/alert/key-file/sending remain. But the same file still decides whether to arm the timer at [line 159 (line 159)](OpenFactor/Vault/WatchKeyProvider.swift:159), whether a failed key load becomes a refusal, and whether an unnamed refusal is suppressed.
ProvisioningDesk received the corrected, narrower description, but this duplicate claim was not removed. Smallest fix: give this comment the same “message-handling rules moved; cadence and adapter policy remain” wording.

Four-question assessment
Do the changes address their findings? S2-13, S2-14/S2-15’s exploitable race, S2-16, and S2-18 are complete. S2-12 remains incomplete at exact equality. S2-17 remains incomplete because the rejected extraction claim survives in WatchKeyProvider.
Did the changes introduce anything new? Nothing above low. The lazy hasVault closure is called once, after parsing and foreground checks, is not retained by the desk, and captures the store rather than key material. The shared reply reader preserves every historical/current phone status.
False claims? The nonce-less-decline compatibility claim and the remaining “every rule moved” comment are false as written.
Is this converging? Yes. The security-relevant surface is shrinking, and the cryptography, parsers, state ownership, lazy key read, and unsolicited refusal binding are stable. But the exit rule requires both “nothing above low” and “no fix called incomplete.” This round passes only the first half, so Scope 2 should not stop yet.
No tests were run because doing so would create build artifacts, contrary to the read-only requirement. The repository remained clean.


5:20 PM
