# A4 round four, scope 2: what three engines found in the extraction

Round four read `ae90bcb`. All three engines returned.

**All eleven original findings are now accepted**, including the three that had been fixed and
unreviewed since round three. **And this is the first round of the gate to return no medium and no
high at all**: seven new items, every one low.

| Engine | Verdict |
| --- | --- |
| Fable 5 | "The extraction is faithful and the seam is nearly right." Two low, two missing tests |
| Grok 4.6 | One low. "I would not extract these two types again" |
| ChatGPT 5.6 Sol | Two low. "Genuine convergence, while demonstrating that 'everything left is plumbing' is still premature" |

## The fix that does not fire

**Two engines independently found that the consent timer never expires anything.**

`expireConsent` sleeps for exactly the window, 120 seconds, and asks the desk once. `age()`
truncates to whole seconds and `isAnswerable` accepts `elapsed <= 120`. So the timer wakes at
T+120.x, `age()` returns 120, the request is still answerable, `expire` returns `nil`, the one-shot
task ends, and **the alert stays up indefinitely**.

The desk test that proves the deadline takes the question down advances by 121 seconds. The
production timer asks at 120. As Grok put it: the early, wrong-nonce and already-answered no-ops are
tested and real; the successful deadline, as the app actually arms it, is not.

**This is the same shape as two fixes the gate has already rejected**, and it is worth naming as a
pattern rather than an incident. The mtime clamp passed a test that could not see the attack. The
creation check passed a test whose fake never changed. This timer passes a test that asks at a
moment the timer never asks at. Each time the test was written by whoever wrote the fix, and each
time it agreed with the fix rather than with the world.

Nothing is released by it: a tap after the window still refuses and sends the decline. What fails
is the automatic clearing that round three asked for and that this round's account claimed.

## The order the extraction reversed

**Two engines found the key being read before the request is validated.** `Conditions` is built
eagerly, so `keys.load()` runs before `received` checks the length and before it checks whether the
app is frontmost. A malformed forty-byte request reads the vault key before being rejected for its
length; a valid request arriving in the background reads it before being told `.needsApp`.

They disagree about what it costs. ChatGPT rates it low and says it **restores a previously fixed
behaviour** and falsifies three documents: the comment above the method, `docs/VAULT.md`, and
`SECURITY.md` all say the phone validates and foregrounds before it reads the key. Fable found the
same eager read and calls it a wasted read rather than a leak, since a protected file simply reads
as absent in the background.

Both note the same thing about the tests: `rubbishIsRefused` and `backgroundIsNeedsApp` pass
precomputed `Conditions`, so they cannot see when the app evaluated anything.

`approve()` has the same shape: it loads the key before asking the desk whether there is anything
to release.

## All three rejected the same claim

**"What stayed behind in the app is everything that is not a decision" is too strong**, and every
engine said so in its own words. What is still resident and still untestable:

- the condition that arms the expiry timer, `answer == .asking`, whose removal would leave every
  desk test passing and kill auto-clearing entirely
- the rule that sends a refusal even when the desk has nothing to name
- the policy that a phone which cannot read its key refuses rather than asks
- the first reply, which is parsed in `WatchVaultModel` with its own `status as? String` rather
  than through `WatchInbox.classify`, so one wire vocabulary now has two readers
- the whole asking cadence on the watch: `refreshAndAsk`, `keyOpensNothing`, and the
  `hasReplacedStaleKey` latch, which its own comment records as having been wrong once

Fable's summary is the accurate one: **the extraction moved the message-handling rules and left the
cadence rules.**

## What round four added

| # | Finding | Severity | Engines |
| --- | --- | --- | --- |
| S2-12 | the consent timer wakes at the window and finds the request still answerable, so nothing expires | low | Grok, ChatGPT |
| S2-13 | the key is read before the request is validated and before the frontmost check | low | ChatGPT, Fable |
| S2-14 | a current build can send a nonce-less decline, which the protocol says only old builds send | low | Fable |
| S2-15 | a phone that cannot read its key refuses in silence, while the expired path sends a bound refusal | low | all three |
| S2-16 | the first reply is parsed in the model rather than through `WatchInbox`, so one vocabulary has two readers | low | Grok |
| S2-17 | the seam claim is too strong: the timer's arming condition and the asking cadence are decisions still in the app | low | all three |
| S2-18 | two rules have no test: `classify`'s preference order, and the asked-answered-asked cycle | low | Fable, Grok |

**S2-14 is the sharpest of the seven.** `decline()` sends unconditionally, so when the desk has
nothing to name the message goes out with a status and no nonce. `docs/VAULT.md`'s byte table says
the nonce is present on a decline, and the watch's compatibility rule honours a nonce-less decline
**because it can only have come from a phone built before the field existed**. So a current phone
can emit exactly the unbound refusal the nonce was added to abolish, and the watch will believe it
against whatever attempt it holds. Fable's path to it is the expiry timer racing a tap on Not now.

**S2-15 is the same rule missing from three call sites**, which is why all three engines touched it
from different directions. Unifying them behind one refusal would close S2-14 as well.

## What survived, checked individually

Fable walked every fix from rounds one through three through the new code rather than trusting the
account, and all of them hold: the watchOS protection class and exclusion-before-content, `.busy`,
the no-replacement rule, the consent window with its backward-clock refusal, the CSPRNG catch, both
flow guards, the decline nonce matching, absent-versus-unreadable, and expiry-as-refusal.

**Two things are better than the account claimed.** Round three's split brain got the structural
cure rather than the one-line fix Fable proposed: attempt lifetime is derived from `flow.isAsking`,
so a sixth answer cannot separate the model from the flow again, and the two flow tests that
asserted a property the shipped watch did not have are now true of the app. And the substitution
test both round-one engines asked for finally exists, four rounds later, "because it finally
could."

## Convergence, and the stop rule

All three say yes, and Fable says it about the whole scope for the first time: this round's
findings are smaller, fewer, and in a different class than the last round's, and the two new types
are the same shape as `WatchProvisioningFlow` and `AppLockPresentation`, which are the two
structures in this project that stopped producing defects after they were built.

Grok: "I would not extract these two types again." ChatGPT: genuine convergence, and the plumbing
claim is premature.

**Against the stop rule proposed earlier, this round half-passes.** It returned nothing above low,
which is the first half. It also called a fix inert, which fails the second. Scope 2 needs one more
pass, and the residue all three describe is small enough to enumerate: unify the three refusal call
sites, make the timer actually expire, run the first reply through `WatchInbox`, decide whether the
asking cadence follows the messages into the core, and add the two one-line tests.

---

# What was done

**The code under review is `9304d6c`.** All seven are fixed.

**S2-12, the timer that expired nothing.** The window is compared as a duration rather than through
`age`'s whole seconds. The new test asks at the instant `Task.sleep(for: .seconds(120))` actually
wakes, which is the moment the old test avoided by asking a second later. Both sides of the
boundary are pinned to the millisecond.

**S2-13.** `Conditions.hasVault` is a closure. The desk asks it only after the request has parsed
and the app is known to be frontmost, and two tests record whether it was asked at all rather than
what it returned.

**S2-14 and S2-15, which were one rule missing from three call sites.** There is one `refuse`
method now. A refusal this phone cannot name is not sent, so the timer-versus-tap race can no
longer emit the unbound decline the watch honours as coming from an older build. And a phone that
cannot read its key refuses rather than going silent, which is what the expired path three lines
away already did.

**S2-16.** The direct reply goes through `WatchInbox.classify`, so the wire vocabulary has one
reader. Anything that is not an answer is treated as a refusal, by the same rule that governs an
answer this build cannot name.

**S2-17.** The claim is gone and the comment lists what actually stayed in the app targets: the
condition that arms the timer, and the watch's asking cadence. **Moving those was considered and
not done**, and the reason is stated rather than implied: neither produced a finding in this gate.

**S2-18.** Both rules pinned.

Each fix was reverted individually and its test confirmed red.

## For round five

This is the round where the scope can meet the gate's exit condition: nothing above low, and no fix
called incomplete. Four questions.

**The timer is the third attempt at the same deadline.** No window at all, then a window checked
only on a tap, then a timer that woke too early to fire. Ask whether the arithmetic is right at
every boundary rather than at the two this batch tested.

**`hasVault` is now a closure held in a value type.** It is called at most once and only after two
guards. Check that it cannot be called twice, and that nothing captured in it outlives the request.

**One `refuse` method serves three callers.** That is the consolidation two rounds asked for, and
consolidation is how four entry points become wrong together.

**The watch's reply path changed reader.** A reply that is not an answer is now treated as a
refusal. Check that no phone this build can talk to sends something that lands there wrongly.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Fable:
Round four of Scope 2. Same standing asymmetry: this conversation holds rounds one through three. Reading the round-four account and confirming the checkout.

Ran 5 commands, read 7 files
A4 round four, scope 2: the extraction, reviewed

Commit reviewed: ae90bcb (tip of a4-fixes). Round three read 71e88c3, round two 350375b, round one 74fe841. Standing asymmetry, recorded once more: this conversation holds all three prior rounds, and this round reviews a change made partly in response to my own round-three closing sentence — the pressure to approve it is real and named.

Verdict in one paragraph: the extraction is faithful and the seam is nearly right. Every fix from rounds one through three survived the move — I checked them individually, not as a class — and the round-three split-brain got the correct structural cure, not a patch. The two new types' tests pin the rules they claim to pin. What this round found is small and lives, predictably, in what stayed behind: the phone can now emit a nonce-less decline the protocol documentation says cannot exist, and the two paths that answer an unanswerable question disagree about whether to tell the watch. To question five: yes, this is converging, and this round is the evidence — the findings are the smallest of any round, and they are wire hygiene, not key handling.

Question 1: does the behaviour survive?

I walked every prior fix through the new code rather than trusting the account.

Survived intact: the watchOS protection class and exclusion-before-content (writingOptions, stagingDirectory — now stronger: the directory mark throws and is read back through a fresh URL, which closes my round-three F2 beyond what was asked, and discard() now sweeps PendingKeys, closing the erase-path orphan I noted); the .busy answer (secondRequestIsToldBusy); the no-replacement rule (approvalFollowsTheQuestionOnScreen — the substitution test both round-one engines asked for finally exists, four rounds later, because it finally could); the consent window with the backward-clock refusal (isAnswerable fails closed, and the new test pins the exact case round three caught the old test's message overclaiming); the CSPRNG catch; both flow guards; the decline nonce matching; absent-versus-unreadable; expiry-as-refusal.

Fixed better than before, twice. Round three's F1 (the model treating .busy as terminal) got the structural cure rather than the one-line fix I proposed: releaseAttemptIfFinished() derives attempt lifetime from flow.isAsking, so there is one definition of "over" and a sixth answer cannot split the model from the flow again. I traced it through busy, busy-after-timeout, obsolete responses, declines, and terminal answers; model and flow now agree in every case, including the two the round-three flow tests asserted falsely of the app — those assertions are true of the shipped watch now. And the no-attempt decline case (my round-three F1 collateral: a readable foreign nonce honoured because if let attempt fell through) is now ignored by rule — matchesCurrentAttempt: false when nothing is held — with refusalIgnoredWithNoAttempt pinning it.

One deliberate improvement beyond the account: the expiry timer. The window used to be checked only at the tap; the alert now comes down on its own, which retires most of my round-three note about the owner tapping into a silent refusal. The timer's three failure modes — early, wrong request, already answered — are exactly deadlineCannotMisfire's three cases, and the timer itself holds no rule: it wakes up and asks. Task.sleep(for:) and the desk both measure on ContinuousClock, so they cannot disagree about whether the deadline passed.

Question 2: is the seam in the right place? Two findings say almost.
F1 — Low. A new build can send the nonce-less decline the protocol says only old builds send

WatchKeyProvider.swift:103-116. decline() sends unconditionally: when desk.decline() returns nil, the message goes out with a status and no nonce. VAULT.md's new byte table states the nonce is "present on a decline", and the watch's compatibility rule — honour a nonce-less decline, because it comes from "a phone built before the field existed" — believes that. A nonce-less decline from a current phone is therefore an unbound refusal from a build that is supposed to bind every refusal, and the watch will honour it against whatever attempt it holds.

Reachable path: the expiry timer and a tap on "Not now" race on the MainActor; the timer wins, clears the desk, and sends the bound decline; the already-queued tap then runs decline() against an empty desk and emits the unbound one. For it to do harm, the stray must arrive after the wearer has already started a fresh attempt — a narrow interleaving, self-healing in one retry, and the flow's outstanding guard absorbs the common timing. But it is the exact class — a refusal ending an attempt it does not name — that the nonce field was added to close, and it survives here only because the send-when-empty rule is a decision that stayed in the app, where no test can see it. Smallest fix: guard let nonce = desk.decline() else { return } — a build that names its refusals should refuse to send one it cannot name.

F2 — Low. The two unanswerable-question paths disagree, and one of them goes silent

WatchKeyProvider.swift:81-84. When the tap arrives and the key file cannot be read, approve() clears the desk and returns — the watch is told nothing and waits out its timeout. Three lines down, the expired-window path answers the same situation by sending a bound refusal. Both are decisions about what an unanswerable question tells the wire, both live in the untested target, and they chose differently. The silent behavior is faithfully preserved from round three — this is a survival, not a regression — but the refusal mechanism now exists and this path doesn't use it. Smallest fix: send(declineEchoing: desk.decline()) in the guard, which also makes F1's fix a single shared rule at all three call sites.

What genuinely remains app-side, named rather than waved at

The seam claim — "everything that is not a decision" — is close but not exact. Still resident in the app targets: the condition that arms the expiry timer (answer == .asking); the send-on-empty rules above; and on the watch, the entire asking cadence — refreshAndAsk's ordering, keyOpensNothing, and the hasReplacedStaleKey latch, which is a decision that was wrong once before by its own comment's account. These predate the extraction and none touched a finding this gate produced, but they are decisions, and the honest statement is that the extraction moved the message-handling rules and left the cadence rules. One incidental ordering change worth a sentence: Conditions is now computed eagerly, so keys.load() (and its repair pass) runs on every incoming request, including malformed ones and ones arriving in the background — the old guard order avoided that. No security consequence (the protected file just reads as absent in the background); it is a wasted read, not a leak.

Question 3: do the nineteen tests pin the rules?

Mostly yes, and the method described — reverting each rule to watch its test fail — is the right discipline, visible in the tests' shapes: tapOutsideTheWindowRefuses includes the backward clock, deadlineCannotMisfire enumerates the timer's wrong moments, declineWithAnUnreadableNonce pins the merge that was once a defect. Two small gaps: nothing pins classify's stated preference order (a message carrying both a response and a declined status must read as the sealed response — the comment says the order matters, no test holds it); and nothing pins that the desk accepts a new request after the previous one was answered — the full cycle, asked-answered-asked, is implied everywhere and asserted nowhere. Both are one-line tests. The nonceBytes empty-Data reasoning the account told me to verify rather than take: verified — answers(_:) length-checks 16 before comparing, so the empty stand-in fails for .present, and .absent/.unreadable never consult the match at all; no input reaches a wrong outcome through it.

Question 4: did the move introduce anything?

F1 is the one introduction with teeth, and it rode in with the new expiry timer rather than the extraction proper. Beyond that: the eager Conditions read (above); the Approval equality-by-nonce, which is test-facing and sound; and the out-of-scope arrivals in OpenFactorApp — I checked the specific worry the account raised, and the provisioning alert, its binding, the !lock.isLocked suppression, and the scenePhaseChanged → PrivacyShield.apply ordering are untouched; the inbox sweep and arrival queue slot in after the shield application and do not reorder anything this scope depends on. The VaultKeyStore.load size check is benign here and its skipped-when-sizeless residual is already filed by scope 1.

Question 5: is this converging?

Yes — and for the first time I can say it about the whole scope rather than parts of it. The test is whether this round's findings are smaller, fewer, and in a different class than the last round's, and they are: round one found key-adjacent defects, rounds two and three found fixes fighting the structure, and round four found two wire-hygiene inconsistencies and two missing one-line tests. The prediction that closed round three — the next defect will be in WatchVaultModel or WatchKeyProvider — came true one more time (both findings are in WatchKeyProvider), but for the last interesting reason: what's left in those files is now small enough to enumerate, and the findings it can still produce are of the kind found this round, not of the kind found in round one. This is not the fourth rewrite under a new name. The desk and the inbox are the same shape as WatchProvisioningFlow and AppLockPresentation, which are the two structures in this project that stopped producing defects after they were built. The residue worth carrying forward is exactly three items: unify the three refusal call sites behind one rule (F1/F2), decide whether the asking cadence follows the messages into the core, and add the two one-line tests. If those land quietly, this scope is done being reviewed and can go back to being used.

Grok:
1. Does the behaviour survive?

The round-one through round-three rules that lived in the two app files are still the same rules, now on ProvisioningDesk and WatchInbox.

Phone, first-wins. received returns .busy when pending != nil and does not replace it. Approving after a second request releases the first nonce. Both are tests. That is the substitution fix.

.asking vs .busy. A discarded request is told .busy. The watch flow still treats .busy as non-terminal, and only while stage == .waiting.

The model no longer fights the flow. Round three’s leftover was if answer != .asking destroying the attempt the flow had kept. That line is gone. releaseAttemptIfFinished asks flow.isAsking. An obsolete sealed payload still does not clear a live attempt, so ChatGPT’s delayed-A-while-holding-B sequence still ends with B able to open.

Consent. isAnswerable is elapsed >= 0 && elapsed <= window. A backward now refuses. A tap at 121 seconds refuses. A second tap after a release or a refusal is .nothing. approve nils pending before it chooses .release or .refuse, so a second tap on a lingering alert cannot release. That is the case the brief asked to check, and it holds.

Decline nonce. Absent is honoured, unreadable is ignored, present is honoured only when it matches. shouldHonourDecline(.present, matchesCurrentAttempt: false) is false, including when there is no attempt. phoneDeclined still has the outstanding != nil guard, so a nonce-less decline after .ready does not demote the list.

Re-ask on obsolete response. Gone. Still gone.

Human tap. WatchKeyProvider.approve is still only the affirmative button in OpenFactorApp. The alert binding’s setter is still a no-op. watchAsking is still watchKeys.isAsking && !lock.isLocked. PrivacyShield.apply is still on scene-phase and lock changes.

Empty Data on the decline path. answers(_:) bails when candidate.count != nonce.count, so empty fails. shouldHonourDecline does not use that boolean for .absent or .unreadable; those return true and false on the enum alone. The empty buffer is only a stand-in so answers has something to chew. The honour decision is made before that result matters.

What did not survive as a working extra, though the tap path still refuses: see finding below.

───

Finding

Low — the new consent timer sleeps for the window, then expire usually does nothing

Where: WatchKeyProvider.expireConsent (OpenFactor/Vault/WatchKeyProvider.swift:151) together with ValidatedRequest.isAnswerable (WatchProvisioning.swift:305) and ProvisioningDesk.expire (ProvisioningDesk.swift:119).

Call order: received stamps validatedAt, then Task.sleep(for: .seconds(120)), then desk.expire(nonce) with now: .now.

age is whole seconds (Duration.components.seconds). isAnswerable is elapsed >= 0 && elapsed <= 120. After a sleep of 120 seconds, elapsed is 120.0–120.999…, age is 120, isAnswerable is still true, expire returns nil, and nothing reschedules. The alert stays up.

The desk test that proves the deadline takes the question down passes now advanced by 121 seconds. The timer never does that. Early / wrong-nonce / already-answered no-ops are tested and real. The successful deadline, as the app actually arms it, is not.

What this is not. It is not a way to release the key. A tap after 121 seconds still returns .refuse and sends the decline. The hours-old alert can sit until that tap, which is the round-three complaint the timer was meant to close.

Smallest fix: sleep past the last whole second that is still answerable (121 seconds), or treat elapsed >= window as expired, or pass now into expire from a clock the test can see. Then add a test that expire at the instant the timer actually wakes does return the nonce.

───

2. Is the seam in the right place?

Most of the rules that produced the five defects are in the core. What is left in the app files is thinner. It is not empty of decisions.

Still a policy, still untested: if keys.load() fails, WatchKeyProvider.approve calls desk.decline() instead of asking the desk. A phone that cannot read its key refuses even a live, in-window request. Conservative, and not on ProvisioningDesk. If respond throws after .release, the desk is already empty and nothing is sent; the watch waits out its own 25 seconds. Same file.

Still a schedule, still untested: starting expireConsent only on .asking is a decision. Forgetting that line would leave the tap-to-refuse path intact (the desk tests still pass) and kill auto-clear. That is how this class of bug used to hide.

Still parsing the first reply in the model. phoneSent goes through WatchInbox.classify. The sendMessage reply handler still does status as? String plus Answer(rawValue:) in WatchVaultModel. Same vocabulary, two doors. A sixth wire value has to be taught to both.

Still “when do we ask?” in the model. refreshAndAsk, hasReplacedStaleKey, stage != .waiting, the CSPRNG catch. Those had defects in earlier rounds. They were not the five this extraction targeted. They are still unreachable.

Load-bearing plumbing that is still plumbing: only sendMessage, never queued WC modes. No test will notice if that becomes transferUserInfo. docs/VAULT.md still says that is an invariant.

The claim “what stayed behind is not a decision” is too strong. The claim “the five desk/inbox rules can now be broken in a test” is true.

───

3. Do the new tests actually pin the rules?

They pin the rules they can see. I checked the ones that would have been green against the old bugs:

• Overwriting pending and still returning .asking fails secondRequestIsToldBusy (wrong answer) or approvalFollowsTheQuestionOnScreen (wrong nonce).
• Dropping the window fails tapOutsideTheWindowRefuses at 121 seconds and on a backward now.
• as? Data merging unreadable into absent fails declineWithAnUnreadableNonce and the unreadable rows of decidingWhetherToBelieveARefusal.
• Honouring a present nonce with no attempt fails refusalIgnoredWithNoAttempt.

Approval equality is nonce-only. That is enough for these tests; it would not catch a desk that swapped the public key and kept the nonce.

What they do not pin: that WatchVaultModel actually passes matchesCurrentAttempt: false when attempt is nil (it does, via ?? false); that expireConsent is started; that the timer’s wake instant is past the window. Those are the last miles the old files still own.

───

4. Did the move introduce anything?

ProvisioningDesk is a mutating Sendable value sitting on a @MainActor object. All desk mutations in the provider are on the main actor. I do not see a concurrent approve / expire / received race. expire matching by nonce is the right check for a timer that outlives a decline-and-ask cycle: a late fire for the old nonce returns nil while a new request is on the desk.

Several expireConsent tasks can be in flight. Each carries one nonce. That is the design. It is not a loop.

WatchInbox is a pure enum. classify prefers a response key over status, which matches “the sealed payload is the generous case.” The phone never sends both.

OpenFactorApp (scope 1 / 4 landing). Inbox sweep on activation, ArrivalQueue, wrapped-key reconcile at launch. The watch alert is still on the same Group, still watchAsking, still both buttons explicit, still above the lock branch, still next to PrivacyShield.apply. watchKeys.activate() is still a .task. I do not see those additions changing the order this scope depends on.

VaultKeyStore.load size check. If fileSize is present and greater than 32, it throws before contents(atPath:). If the file system gives no size, it still reads the whole file and then checks count == 32. That is the residual the brief already named. This file is one this app writes. I am not promoting it.

───

5. Is this converging?

Yes. This is the right structure, not a fourth rename of the same pile.

Rounds one to three kept finding defects in two files the suite cannot compile. The answer is the same one this project already used for the watch flow and for App Lock: put the rule in a value type, pin it, leave I/O behind. The five desk/inbox rules are now breakable in CI. That is a smaller surface than “read WatchKeyProvider again and hope.”

Twenty-five changes is a lot. The last ones were not a new family of protocol bugs; they were “this decision had no test.” Residue remains (timer boundary, reply-handler parse, load-fail policy, when-to-ask). That is leftover last mile, not the pooling that round three called predictable.

I would not extract these two types again. I would make the timer actually expire, and I would run the first-message reply through WatchInbox.classify so there is one reader.

The cryptography and the 85/145 parsers were not moved and I am not re-litigating them. Approval is still a human tap. I did not find a way to install a key from an unverified or abandoned attempt, or to seal to a request the owner is not being shown.

GPT:
Reviewed commit ae90bcb; the worktree is clean and exactly at that commit. I found two low-severity defects.
Findings
Low — the extraction reversed the security-relevant “validate and foreground-check before reading the key” order
[`WatchKeyProvider.answer(to:)` (line 131)](OpenFactor/Vault/WatchKeyProvider.swift:131) constructs Conditions before calling the desk:
let conditions = ProvisioningDesk.Conditions(
    isFrontmost: UIApplication.shared.applicationState == .active,
    hasVault: ((try? keys.load()) ?? nil) != nil)

let answer = desk.received(request, when: conditions)
Swift evaluates hasVault eagerly, while [`ProvisioningDesk.received` (line 74)](Sources/OpenFactorCore/Vault/ProvisioningDesk.swift:74) performs validation and the foreground check only afterwards.
Concrete call orders:
A malformed 40-byte request reaches answer; keys.load() reads the vault key before received rejects the length at line 77.
A valid request wakes an unlocked phone in the background; keys.load() succeeds before received returns .needsApp at line 78.
No sealed key is sent, so this is not key exfiltration. It nevertheless restores a previously fixed behavior and falsifies the comment at WatchKeyProvider.swift:123 stating that rubbish is refused before the key is read. It also contradicts [docs/VAULT.md (line 398)](docs/VAULT.md:398) and [SECURITY.md (line 325)](SECURITY.md:325), which say the phone is foregrounded before it reads the key and that malformed input no longer reaches it first.
The same residual ordering decision appears in [`approve()` (line 76)](OpenFactor/Vault/WatchKeyProvider.swift:76): it loads the key before asking whether desk.approve() is .release, .refuse, or .nothing. Thus an expired request, an already-cleared desk, or a second tap still reads the key unnecessarily.
Smallest fix: make vault availability lazy so ProvisioningDesk invokes it only after successful validation and the foreground guard. In approve, ask the desk first and load the key only for .release; if that load fails, refuse using the released request’s nonce.
The new tests do not catch this: rubbishIsRefused and backgroundIsNeedsApp pass precomputed Conditions, so they cannot observe when the app evaluated keys.load().

Low — the one-shot consent timer normally fires while the request is still considered answerable
[`expireConsent` (line 151)](OpenFactor/Vault/WatchKeyProvider.swift:151) sleeps for exactly 120 seconds and asks the desk once. But [`ValidatedRequest.age` (line 322)](Sources/OpenFactorCore/Vault/WatchProvisioning.swift:322) discards fractional seconds, while isAnswerable accepts elapsed <= 120.
Concrete sequence:
Request validates at time T.
The timer starts milliseconds later and sleeps 120 seconds.
It wakes around T + 120.x.
age() returns integer 120.
isAnswerable(within: 120) returns true.
[`ProvisioningDesk.expire` (line 119)](Sources/OpenFactorCore/Vault/ProvisioningDesk.swift:119) returns nil.
The one-shot task ends, leaving the alert and request indefinitely.
A later tap still fails closed and sends a refusal, so stale consent cannot release the key. The defect is that the newly claimed automatic expiry normally does not occur.
The desk tests miss the boundary: [`deadlineTakesTheQuestionDown` (line 157)](Tests/OpenFactorCoreTests/ProvisioningDeskTests.swift:157) tests 121 seconds, while the production timer asks at 120.
Smallest fix: compare the full ContinuousClock.Duration without truncating, define the valid interval as strictly less than the window, and test exactly 120 seconds plus a fractional value such as 120.5 seconds.

Answers to the five questions
Does the behavior survive? Mostly. Pending-request nonreplacement, truthful .busy, monotonic consent, fail-closed approval, decline nonce matching, stale-callback guards, and retention of the attempt after .busy all survive. The malformed/background-before-key ordering does not.

Is the seam right? The core types are appropriately scoped, but the claim that the app targets contain no decisions is not yet true. Eager key loading and the timer/window boundary are correctness-sensitive orderings left in WatchKeyProvider. The watch model’s direct-reply parsing also remains separate from WatchInbox, although its present behavior matches the core vocabulary.

Do the tests pin the rules? The desk tests correctly pin nonreplacement, .busy, approval identity, clock rollback, desk clearing, and stale/wrong timer nonces. The inbox tests correctly distinguish absent, unreadable, matching, and foreign nonces. They do not pin adapter evaluation order or the production timer’s exact boundary, which are the two failures above.

Did the move introduce anything? Yes: both findings arise from composing the extracted types with the app adapter. I found no Sendable or actor-isolation defect; the mutable desk remains confined to the @MainActor provider, and timer nonces correctly prevent an old timer from expiring a newer request.

Is this converging? Yes, but it is not finished. The core state rules are now substantially smaller, coherent, and directly tested; the previous .busy split and stale-decline interaction are closed. The remaining defects are concentrated in two short adapter orderings rather than spread across the protocol. That is genuine convergence, while also demonstrating that the assertion “everything left is plumbing” is still premature.

The round-three storage finding is fixed: staging exclusion now throws, is read back before any key write, and the staged file retains its own exclusion for .usingNewMetadataOnly. The added VaultKeyStore.load size check preserves the exact 32-byte post-read check. The unrelated OpenFactorApp changes do not disturb provisioning: the alert buttons, no-op binding setter, App Lock condition, and sole affirmative call to approve() remain unchanged.
The cryptography and byte parsers remain sound: exact lengths precede slicing, P-256 points are validated, the request nonce is checked before phone-key parsing or derivation, and the fixed-width transcript binds the version, nonce, and both public keys in HKDF and GCM AAD. I found no path to approve without the affirmative tap, seal to a substituted pending request, or install a response not verified by the current attempt.
No build or test command was run because the review was required to create or modify no files.
