# A4 round six, scope 2: what three cold readers found in the five

Reviewed commit: `1f7e65f`, delivered as checkout `a644d88` (the same tree plus the round five
results file). Round five read `9304d6c`. The chain from `74fe841` is unbroken.

Sent to Fable, ChatGPT and Grok. All three read the same five fixes: S2-17, S2-19, S2-21, S2-22,
S2-23.

## The short version

**No code defect.** Nothing above low. The entire code delta this round reviewed is one comparison
character, one internal accessor, comments, and test re-anchoring, and all three engines read all
of it rather than sampling.

**Two new low findings, both false claims in comments, both found independently.** They are
recorded below as S2-24 and S2-25.

**The engines split on the exit condition**, which is the interesting part of the round.

## S2-24 (low): the seam header counts two decisions and there are three

Found by Fable and ChatGPT independently. Verified here.

`WatchKeyProvider.swift:38` says what stayed in the app target is "the session, the alert, the key
file, the sending, **and two decisions**": arming the expiry timer on `answer == .asking`, and not
sending a refusal it cannot name.

There is a third, in `approve()`'s release path at `WatchKeyProvider.swift:87-93`. A phone that
cannot read its own key, or cannot build a response, sends a named refusal rather than going quiet.
That is a policy choice with a wire consequence, it was itself finding S2-15 once, and it meets the
header's own stated bar for what must be listed: delete the `refuse` call from that guard and every
test in the package stays green while the S2-15 silence returns.

Fable adds a second half. `ProvisioningDesk`'s twin header at `ProvisioningDesk.swift:18-30`
enumerates what stayed behind as the timer arming and the watch's asking cadence, and names neither
refusal rule, under an intro line that reads as complete. **The two headers now disagree with each
other**, which is the same shape as the finding that held this scope open in round five: a sentence
corrected in one file and not its twin.

Nothing in the code is wrong. Each of the three decisions is correctly documented at its own site.
What is wrong is a count, and a second enumeration that does not match it.

## S2-25 (low): the core's decline comments still say "an old phone"

Found by ChatGPT. Verified here.

`VAULT.md` and `SECURITY.md` were corrected in round five to distinguish a standalone refusal, which
always carries a nonce, from a direct reply to a request that failed to parse, which carries none
and needs none. **That distinction was not propagated into the core.** Four comments still state the
pre-correction rule without qualification:

- `WatchInbox.swift:30`, `Nonce.absent`: "a phone built before the field existed"
- `WatchInbox.swift:43`, `Message.decline`: "The second message, refusing"
- `WatchInbox.swift:81`, `shouldHonourDecline`: a nonce-less decline comes from an old phone
- `WatchProvisioning.swift:116`, `MessageKey.nonce`: the same unqualified compatibility claim

The path that makes them false is current, not hypothetical: a malformed request makes
`ProvisioningDesk.received` return `.declined`, the phone replies `["status": "declined"]`, and
`WatchInbox.classify` reads that as `.decline(.absent)`. So `.absent` and `.decline` now describe a
current direct reply and not only an old phone's standalone second message.

**The behaviour stays correct**, and all three engines checked this rather than assuming it. The
reply lands in `phoneAnswered`, which is bound to its own attempt's token by the reply closure and
guards `flow.isCurrent(token)` before anything else, and which never consults
`shouldHonourDecline` at all. A nonce-less decline on that path can only ever end the attempt that
asked for it.

## The five, as each engine scored them

**S2-17**: the false sentence is gone from `WatchKeyProvider` and the history is recorded in the
file. The two decisions it names are real and accurately described. The replacement miscounts, which
is S2-24. Grok scored it complete. Fable filed the miscount as a finding but declined to score the
fix incomplete. ChatGPT scored it incomplete.

**S2-19**: complete, unanimously, and Fable withdrew its round five abstention. The comparison is
strict, both sides of the exact instant are pinned by tests anchored on the request's own instant,
and the comment states the trade honestly: a tap at exactly the window now refuses, which is equally
unreachable and is the fail-closed side. Grok still believes the instant is unreachable and still
does not ask for `<=` back. Both callers were checked: approve at the window refuses, expire at the
window fires.

**S2-21**: the reasoning survived the attack the brief invited. All three engines verified in code
rather than accepting the claim, and reached the same place: the reply channel binds a declined
answer to its request at least as strongly as a nonce would, resting on the same delivery guarantee
the exchange already declares load bearing. Changing the wire would mean inventing a nonce for a
request that failed to parse and has none. The documents were the right thing to fix. ChatGPT scores
the documentation half incomplete because the correction stopped at the two markdown files, which is
S2-25.

**S2-22**: complete, unanimously. The comment names the declined reply, explains why the outcome is
right by rule rather than by coincidence, and carries the sealed-key footnote.

**S2-23**: complete, unanimously. `pendingInstant` is internal and read only, exposes nothing that
was not already internal, and all five window tests now anchor on it. The flake path is gone.

## Nothing was introduced

All three engines looked and none found anything. The `OpenFactorApp` changes visible in the diff
are scope 1 and scope 4 work landing in a file this scope reads, and Fable checked the specific
dependency: the watch alert block, its `isAsking && !lock.isLocked` binding, and the
`scenePhaseChanged` to `PrivacyShield.apply` ordering ahead of it are untouched, and the reconcile
call added to the scene phase handler runs after the shield is applied.

## The exit condition, and where the engines part

The rule as written: a scope closes when a round returns nothing above low **and** no fix is called
incomplete.

- **Grok: stop.** Against the rule as written, this pass meets it.
- **Fable: close, contingent on the correction being made in both files.** Its argument is that the
  rule exists to stop unreviewed substantial change from shipping, that the remedy here is a
  documentation edit with no code path and no wire byte, and that holding three engines open for a
  count would be the rule serving its letter against its purpose. It states plainly that if the
  maintainer reads the rule more strictly, round seven is a review of one sentence, and it is
  willing to be the engine that says so now.
- **ChatGPT: do not close.** Two fixes are incomplete, therefore the second half of the rule fails.

So the rule as written does not clear. One engine called two fixes incomplete, and the fact that
the incompleteness is a count in a comment does not change what the rule says.

## The trajectory

Six rounds, twenty six accepted findings. The state machine has produced no code defect since the
extraction. Round four found a false claim about what stayed in the app target. Round five found the
same claim uncorrected in its twin file. Round six found a count in the corrected replacement and a
correction that stopped at the markdown and did not reach the core.

**The defect class this scope now returns is a sentence corrected in one place and not the other.**
That is the fourth consecutive round in that family, and it is the reason any remedy here has to be
applied to both headers at once and checked, rather than to the one the finding names.

## What was fixed

Both findings, and both headers together, because the class is the twin.

**S2-24.** `WatchKeyProvider`'s header now names three decisions rather than two, as a list, each
with the deletion that would remove it while leaving the suite green: the timer arm, the unnamed
refusal, and the release-path refusal that was S2-15. It also records that the count has now been
wrong twice in opposite directions, first claiming everything moved and then claiming two.
`ProvisioningDesk`'s enumeration gained the same two phone-side entries in the same words, and a
closing line saying that neither list is edited alone.

**S2-25.** `Nonce.absent` now documents both ways a nonce can be missing and says which one
`shouldHonourDecline` is deciding about. `Message.decline` no longer calls itself the second
message. `shouldHonourDecline`'s own comment states that only standalone refusals reach it, and
names the other path and what binds it. `MessageKey.nonce` distinguishes the standalone refusal,
which always carries the field, from the direct reply, which carries none and needs none.

No code changed. 465 core tests pass, the iOS target builds, the watch app builds.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Round six of Scope 2. Same recorded asymmetry: this session holds rounds one through five, including the recommendation to stop that round five's triage evidently weighed. Reading the results file and the new diff.

Fable:
Ran 4 commands, read A4-round-five-scope2-results.md

Two verification greps before writing: every site that constructs a decline message, and the desk header's twin enumeration at this commit.

Found decline constructors and read desk header
A4 round six, scope 2: the five, reviewed

Commit reviewed: 1f7e65f (checkout a644d88, differing only in the results file — verified). Round five read 9304d6c; the chain to 74fe841 is unbroken. Standing asymmetry, recorded a last time: this session holds all five prior rounds, including my own recommendation to stop that the stop rule rightly overrode, so this round I went looking specifically for the failure mode that overriding exposed — a correction applied in one place and not another.

Verdict in one paragraph: all five fixes address their findings, and four of them are complete without qualification. The fifth — S2-17, the sentence that held the scope open — removes the false claim it was asked to remove and replaces it with an enumeration that miscounts: the header says two decisions stayed in WatchKeyProvider and three live there, by the header's own criterion for what counts as one. That is a one-line documentation correction, not a code defect, and every one of the three decisions is correctly documented at its own site. Nothing else above zero was found. My recommendation on the exit condition is at the end, stated plainly.

Question 1: does each fix address its finding?

S2-17 — the instance is fixed; the replacement miscounts. The stale sentence is gone, the history is recorded in the file itself ("this copy was left behind"), and the two decisions it names are real, accurately described, and paired with the right test-invisibility argument. But the count claim — "and two decisions" — is false by one. The third: in approve()'s release path, WatchKeyProvider.swift:87-93, a release the phone cannot perform (key unreadable, or respond throwing) becomes a named refusal rather than silence. That is a policy choice with wire consequences, it was itself a finding once (S2-15), and it meets the header's own bar for what must be named: delete the refuse call from that guard and every test stays green while the S2-15 silence quietly returns. The two headers also now disagree with each other — ProvisioningDesk's twin enumeration lists the timer arming and the watch cadence but neither refusal rule, under an intro line ("What is still resident in the app targets") that reads as complete. Nothing here is wrong in code: the one standalone-decline constructor in the project is refuse(naming:) with its non-optional nonce (verified by grep — there is no second site), and each decision is documented where it lives. What's wrong is a count, in the sentence family this gate has now corrected in rounds four, five, and six.

S2-19 — complete, and I withdraw my abstention. The comparison is strict, the trade is stated accurately in the comment (a tap at exactly the window now refuses — equally unreachable, and refusing is the fail-closed side), and both sides of the exact instant are pinned by tests anchored on the request's own instant. The brief asked whether I still think the character is wrong: no. My round-five position was that the two measure-zero cases were symmetric; the fix's comment identifies the asymmetry I undervalued — when both cases are unreachable, the character should still sit on the side where being wrong refuses rather than releases, and the tests make the choice permanent instead of re-arguable. I checked both callers: approve at exactly the window refuses, expire at exactly the window fires. Consistent.

S2-21 — complete, and the reasoning survives the attack the brief invited. The claim is that the reply channel binds a declined answer to its request, so the nonce adds nothing there. Verified in the code rather than accepted: the reply arrives in the sendMessage reply handler closure, which captures the token of the attempt that sent the request, and phoneAnswered guards flow.isCurrent(token) before anything else — so a declined reply can only ever terminate the attempt whose request it answers, a binding at least as strong as the nonce match, resting on the same WatchConnectivity delivery guarantee the whole exchange already declares load-bearing. The factual premises also check out: received returns .declined only on a validate failure, so the only request answered that way genuinely has no nonce to echo, and the reply path never consults shouldHonourDecline — the token does that work. The corrected VAULT.md and SECURITY.md paragraphs say exactly this and are now true of the code. Changing the wire instead would have added a field that duplicates a binding the channel already provides; the documents were the right thing to fix.

S2-22 — complete. The comment now names the declined reply that lands in the else branch, explains why the outcome is right by rule rather than by coincidence, and carries the sealed-key-in-a-reply footnote. It matches the code.

S2-23 — complete. pendingInstant is internal, read-only, and exposes nothing that wasn't already internal; all three window tests anchor on it; the two new exact-boundary tests use it from birth. The flake path is gone.

Question 2: did the fixes introduce anything?

No. The entire code delta in this scope is one comparison character, one internal accessor, comments, and test re-anchoring — I read all of it rather than sampling. The OpenFactorApp changes are scope 1 and scope 4 work (the arrival queue removed in favor of newest-wins, the wrapped-key reconcile retried on every foreground) landing in a file this scope reads; I checked the specific dependency this scope has on that file, and the watch alert block, its isAsking && !lock.isLocked binding, and the scenePhaseChanged → PrivacyShield.apply ordering ahead of it are all untouched. The reconcile call added to the scene-phase handler runs after the shield is applied and cannot reorder the alert's suppression.

Question 3: is anything claimed that the code does not do?

One item, already described: "two decisions" where three exist, and two enumerations that disagree. Everything else I checked holds: the new SECURITY.md and VAULT.md refusal paragraphs are accurate (including "the only request answered that way is one that failed to parse"), the isAnswerable comment describes the comparison the code performs, the desk's pendingInstant comment describes why it exists, and the phoneAnswered comment now describes what actually arrives.

Question 4: convergence, and the exit condition

Converging to the point of termination: round six's entire finding is a number in a comment. The trajectory Fable's round-five summary traced ends here with "round six finds a count."

Now the verdict the round exists to deliver, stated plainly. The exit condition has two halves. Nothing above low: passes — the one finding is a documentation count, low. No fix called incomplete: this is a judgment call, and here is mine. S2-17's fix did what the finding demanded — the rejected sentence is gone from the file it was left in, and the history is recorded. The replacement's miscount is a new instance of the same class, and round two's template says a fix that handles the case while leaving the class open is a finding. I have filed it as one. But I do not score the fix incomplete, for a reason the stop rule itself supplies: the rule holds a scope open when the previous round's fixes were "substantial enough that shipping them unreviewed would be the same bet the gate exists to refuse." The remedy here is changing "two decisions" to name the third and reconciling the twin header — a documentation edit with no code path, no wire byte, and no test behind it that could be wrong in a way a seventh round would catch. Holding three engines open for that would be the rule serving its letter against its purpose.

Recommendation: close scope 2, contingent on the one-line correction being made — and made in both files, since the class this gate has now hit four times is precisely a sentence corrected in one place and not its twin. If the maintainer reads the rule more strictly than I do, the seventh round is a review of one sentence, and I am willing to be the engine that says so now: with that count corrected, this scope has nothing left that three cold readers have been able to find, across six rounds, twenty-six accepted findings, and a state machine that has not produced a code defect since the extraction. The gate should spend its next round where the defects still are.

GPT:
Reviewed 1f7e65f; the checkout is a644d88 and differs only in the stated results file. I found no behavioral or cryptographic defect, but two low false-claim findings make two fixes incomplete, so the stop condition is not met.
Findings
Low — the corrected seam description still omits a third decision
[WatchKeyProvider.swift (line 38)](OpenFactor/Vault/WatchKeyProvider.swift:38) says exactly two decisions remain in the app target: arming the timer and suppressing unnamed refusals. But [`approve()` at line 92 (line 92)](OpenFactor/Vault/WatchKeyProvider.swift:92) also decides that failure to load the key or construct the response becomes a named refusal rather than silence.
That is policy, not sending plumbing, and it was one of the app-resident decisions identified in round four. S2-17’s correction is therefore still incomplete, although much narrower than before.
Smallest fix: list this third decision, or avoid giving an exhaustive count.

Low — the direct-reply exception was not propagated to the core message model
The new documents correctly distinguish a nonce-less direct reply from an old phone’s nonce-less standalone refusal. The core comments still state the old rule:
[`WatchInbox.Nonce.absent` (line 30)](Sources/OpenFactorCore/Vault/WatchInbox.swift:30): “a phone built before the field existed.”
[`WatchInbox.Message.decline` (line 43)](Sources/OpenFactorCore/Vault/WatchInbox.swift:43): “The second message, refusing.”
[`shouldHonourDecline` (line 81)](Sources/OpenFactorCore/Vault/WatchInbox.swift:81) again says a nonce-less decline comes from an old phone.
[`MessageKey.nonce` (line 116)](Sources/OpenFactorCore/Vault/WatchProvisioning.swift:116) makes the same unqualified compatibility claim.
Concrete current path: a malformed request makes ProvisioningDesk.received return .declined; the phone replies with ["status": "declined"]; WatchInbox.classify returns .decline(.absent). Thus .absent and .decline can describe a current direct reply, not only an old standalone second message.
The behavior remains safe: phoneAnswered is bound to its original reply closure and checks the captured flow token, and it never calls shouldHonourDecline. Smallest fix: qualify these core comments with the same standalone-versus-direct distinction now present in VAULT.md and SECURITY.md.

Four-question assessment
Do the changes address their findings? S2-19’s strict boundary and timestamp-anchored tests are complete. S2-21’s behavioral reasoning is correct, and S2-22’s model comment now describes the direct decline. S2-17 and the documentation half of S2-21 remain incomplete for the comments above.
Did anything new appear? No new behavioral issue. At exactly 120 seconds the strict comparison refuses, which is the safe side; all surrounding instants are correctly tested against the stored validation instant.
False claims? The two findings above.
Is this converging? Yes. The cryptography, parsing, state machine, timer behavior, refusal binding, and mixed-version behavior are stable. What remains is documentation propagation, not a moving security defect surface.
Because the exit rule requires both “nothing above low” and “no fix called incomplete,” Scope 2 should not close yet.
Record note: despite its description, A4-round-five-scope2-results.md is 158 lines and contains a consolidated account of the three returns, not the returns in full. The requested “What was done” and “For round six” material was present.
No tests were run because they would create build artifacts and violate the read-only requirement. The repository remained clean.

Grok:
Reviewed 1f7e65f (this checkout is a644d88, that commit plus the round-five results file). Round five was 9304d6c. Four questions.

───

1. Does each change address the finding it claims to?

S2-17 — yes. WatchKeyProvider no longer says every rule moved. It names the two that stayed: arming the timer on answer == .asking, and not sending a refusal the desk cannot name. Both match the code. The header also records that this copy was left behind when the desk’s was corrected. That is the sentence that held the scope open, now true in the file it was about.

S2-19 — yes, and I still think the instant is unreachable. I was one of the two who said Task.sleep waits at least the duration and validatedAt is stamped before the sleep is scheduled, so a wake at exactly validatedAt + 120s does not happen. I have not found a way to make it happen. The character was changed anyway: elapsed >= .zero && elapsed < .seconds(window). At exactly 120s, expire now returns the nonce and approve now returns .refuse. Both sides are tests, both anchored on pendingInstant.

What it trades: a tap at exactly the window is refused. That instant is as unreachable as the other. Refusing is the safe side. I am not asking for <= back.

S2-21 — yes, and the document fix is the right one. The reply wrapper is still replyHandler([status: answer.rawValue]) with no nonce. A forty-byte request still gets declined that way, because received never parsed a nonce to echo.

The argument that the reply channel already binds the answer is right, not a dodge. The watch’s sendMessage reply handler closes over that attempt’s token. phoneAnswered returns immediately if !flow.isCurrent(token). A nonce-less declined on that path can only end the attempt that asked. It cannot be delivered as a standalone didReceiveMessage; those go through phoneSent and shouldHonourDecline. Current standalone refusals still go through refuse(naming:) and always carry 16 bytes.

A wire change would invent a nonce for a request that failed to parse. There isn’t one. The documents now say so: standalone refusals carry the field, a direct reply does not and needs none. I would not change the wire.

S2-22 — yes. The comment lists the declined reply, says classify reads it as a decline, and says both branches reach the same terminal. That is what the code does. A sealed payload in a reply would also hit the else and be treated as a refusal. This phone never puts one there.

S2-23 — yes. pendingInstant is the pending request’s validatedAt. aFractionInsideStillReleases, aFractionOutsideRefuses, theDeadlineHasPassedWhenTheTimerWakes, and the two exact-window tests all advance that instant. A stall between received and the test no longer eats the margin.

tapInsideTheWindowReleases still uses .now.advanced(by: .seconds(119)). That has a full second of slack, which is not the flake that was filed.

───

2. Did any change introduce something new?

The strict bound does not create a reachable refusal of a live tap. The timer still sleeps 120s and then asks; at that wake, elapsed is already past the window either way.

refuse(naming:) still has the three standalone callers (expired tap, named decline, load/respond failure) and still is not used for the reply. That split is the S2-21 rule, not an accident. Routing a parse failure through refuse(naming:) would require a nonce received never produced. The reply wrapper sending {status: declined} without going through refuse is the documented exception. I walked it: answer returns .declined without setting pending, so expireConsent is not armed, and no second send follows.

I do not see a new way to release without a tap, to overwrite pending, or to install a key from an unverified or abandoned attempt. The alert is still only the two buttons, the setter is still a no-op, watchAsking is still isAsking && !lock.isLocked.

───

3. Claims the code does not do

The two comments that were false now match. WatchKeyProvider names the timer arm and the unnamed-refusal rule. phoneAnswered names the declined reply. VAULT.md and SECURITY.md no longer say every decline carries a nonce.

I did not find a remaining false claim in these files about this behaviour.

───

4. Is this converging?

Yes. This batch is five corrections to sentences, one comparison, and a test anchor. None of them reopened a protocol hole. None of them fought a previous fix.

Round five failed the exit condition because a comment was fixed in one file and not its twin. That file now says the same thing the desk does. Against the rule as written — nothing above low, no fix called incomplete — this pass meets it. I would stop.
