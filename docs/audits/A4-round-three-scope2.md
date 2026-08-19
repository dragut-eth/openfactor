# A4 round three, scope 2: what changed and why

Round two reviewed the eleven fixes from round one and changed ten more things. **Those ten have
not been reviewed by anybody.** This is the "what changed" block the round three prompt in
`docs/audits/A4-prompts.md` calls for.

**The code under review is `71e88c3`.** Round two read `350375b`; round one read `74fe841`.

Check out the tip of `a4-fixes`, which is what the reviewing copy holds. It differs from `71e88c3`
only in this file, and only by the paragraph you are reading: a page that names its own commit
cannot be committed at the number it names.

Round two's returns are reproduced in full in `A4-round-two-scope2.md`, and round one's in
`A4-scope2-watch.md`. Both are worth reading before this: round two's three returns disagreed with
each other about whether the same construction was sound, and that disagreement is where the two
most useful changes came from.

## The ten changes

**1. The key is written inside a directory that is excluded before any key material exists.**
Round two found the previous fix insufficient twice over: `replaceItemAt` without
`.usingNewMetadataOnly` keeps the *destination's* metadata, so an existing weakly-protected key
survived the fix that was supposed to correct it; and a kill between writing the staging file and
marking it still left a raw unexcluded key at `.{uuid}`, because `defer` does not run after a kill.
`VaultKeyStore.install` now writes into a `PendingKeys` directory created and marked excluded
*before* anything goes in it, sweeps orphans left by a previous kill, and replaces with
`.usingNewMetadataOnly`.

**2. Reading the key repairs how it is stored.** ChatGPT filed this as the caveat at the end of
its item 1: the new options fix future writes, and nothing repairs a key already on disk. Every
change above governs the *next* write, and a Watch provisioned before these rules were corrected never writes
again, so it would never receive them. `VaultKeyStore.load` now sets the protection class and the
backup exclusion on the existing file. Metadata only: it never opens, rewrites, or replaces the
key.

**3. The consent window is measured on `ContinuousClock`.** All three engines found the `Date`
version fails open on a backward jump, since a negative elapsed time is inside any window forever.
`ValidatedRequest.validatedAt` is a `ContinuousClock.Instant` and is **internal**, so nothing
outside the package can compare a `Date` to it again. `age(now:)` is the only public reading, and
takes the instant so a test can choose it, which answers Fable's L1 about a parser that reads a
clock.

**4. The watch no longer re-asks from inside its response handler.** ChatGPT wrote out the
seven-step sequence: a delayed response arrives, the watch treats it as proof the phone's slot is
free, and abandons a request the phone has genuinely retained and is showing an alert for. The
inference is unsound across an asynchronous channel, whether or not it recurses. Fable and Grok
were separately invited to disbelieve the claim that it cannot spin; both walked the call order,
both correctly found no spin, and the spin was never the problem.

**5. The phone answers `.busy`.** Previously it answered `.asking` for a request it discarded,
which is what made the watch want to infer anything. This is the fix ChatGPT named: make the
phone's direct reply authoritative, so it never claims to be asking about a request it did not
keep. `.busy` is non-terminal: the watch keeps the attempt and keeps waiting, because the answer
may still be coming and the timeout recovers if it is not. It was rejected as over-engineering
when round one proposed it.

**6. `.busy` arriving after a timeout leaves the dead-end screen up.** Found by the test written
for change 5, not by a review. A timed-out attempt stays claimable on purpose, so a late key still
installs; that let a `.busy` answer put a spinner back up whose timer had already fired. The
guard is `stage == .waiting`.

**7. `phoneDeclined` gained the guard its sibling already had**, so a decline arriving with
nothing outstanding cannot demote a `.ready` watch. Tests from both sides.

**8. The backup exclusion is set on the staged file, not only on the directory.** Found by the
suite rather than a review, and it is the sharpest thing in this batch: `.usingNewMetadataOnly`
installs the *staged* file's metadata at the resting path, where there is no excluded directory to
sit inside, so change 1 silently stripped the exclusion off the key it wrote. The existing
"excluded from backups" test went red the first time both changes ran together.

**9. A decline whose nonce is present but unreadable is ignored rather than honoured.** `as? Data`
alone conflated *absent* with *present and of the wrong type*, so a decline carrying a nonce this
build could not read fell into the branch reserved for a phone too old to send one, and was
honoured. ChatGPT asked for the two cases to be separated.

**10. Expired consent declines instead of returning silently.** The window check returned, which
left the alert on screen and the request in memory: the owner taps Approve, nothing is sent, and
nothing says why. Expiry now takes the decline path, which clears the alert, clears the request,
and tells the watch, so it stops waiting at once rather than at its own timeout. ChatGPT asked for
the request and alert to be cleared on expiry.

Alongside these: `messageKeysArePinned` pins the fourth wire key, `SECURITY.md` no longer states
the nonce echo unconditionally or calls the window wall-clock minutes, a comment claiming a watch
would wait forever is corrected to what the timeout actually does, and `docs/VAULT.md`'s protocol
section documents the refusal message, which is a third message carrying no version magic and was
absent from the byte tables.

## What round two concluded

ChatGPT: one medium and three low, with a fix assessment item by item, and it was the only engine
to say of item 2 that it was "not fixed". Fable: nine of eleven complete, one gap, one new medium.
Grok: three of eleven incomplete, plus two documentation mismatches. All three returns are in
`A4-round-two-scope2.md`.

Fable's uncovered path is **narrowed rather than closed**, which is the honest description. Its
sequence still ends with a wearer waiting: a decline echoing attempt A's nonce is correctly
ignored by a watch holding attempt B, and B is never answered. What changed is that B gets `.busy`
rather than `.asking`, so nothing claims a person is being asked about it, and the timeout ends
the wait at a screen with a button. Whether that is sufficient is a fair question for this round.

## Where to look hardest

**The state machine has now been modified on three separate occasions, and every previous round
found that the last round's fixes had introduced defects of their own.** Changes 4, 5, 6 and 7 are
that machine. Change 5 adds a fifth answer to a wire protocol; change 6 is a guard added to it
within the same batch, which is not a reassuring sign about how well change 5 was understood when
it was written.

**The file-writing path has been rewritten three times for the same finding.** Change 1 is the
third attempt at "the key is never on disk unexcluded", and change 8 is a defect that attempt
introduced. Ask whether the current shape is right or merely the first one nobody has broken yet.

**Change 2 runs on every read.** It calls `setAttributes` and `setResourceValues` on the live key
file every time the key is loaded. It is claimed to be incapable of damaging the key. Test that
claim.

**Two of the ten changes came from the test suite rather than from a review**, which is either
evidence the suite is doing its job or evidence that changes 1 and 5 were not thought through
before they were written. Both readings are available and the second one is not being avoided.

**Changes 9 and 10 are in the app targets, where this project's test suite cannot reach**, so they
are argued for in comments and unproven by any test. That is the same condition that hid the two
races round one found in the watch's flow, and the reason `WatchProvisioningFlow` exists at all.
Whether these two belong in the core for the same reason is a fair question to put.

## Question four

Round three asks something the earlier rounds did not: **is this converging?** Scope 2 has had
twenty one changes across three sittings. Say plainly whether the defect surface is shrinking or
moving around. If the answer is that an area has been rewritten three times and is still wrong,
that is the most useful sentence you can write here, and it will not be argued with.

---

# Round three: the returns

| Engine | Status |
| --- | --- |
| Fable 5 | Returned, below. Eight of ten complete, one medium-low, one low |
| ChatGPT 5.6 Sol | Sent, not yet returned |
| Grok 4.6 | Sent, not yet returned |

**Standing asymmetry, recorded because Fable records it itself:** its round three ran in the
conversation that held rounds one and two rather than in a fresh session, so it was reviewing
responses to its own findings. It says where that applies and attacks the change anyway.

## What round three found, and what was done

**F1, and it is the one that matters.** `.busy` was added to the core, tested in the core, and
never taught to the watch model, which still ended the attempt for any answer that was not
`.asking`. So `WatchProvisioningFlow` held an attempt the model had already destroyed. **Two tests
written in the same batch assert the surviving attempt and both passed**, because both test the
flow and nothing can test that file.

The suggested fix was one more condition. What was done instead removes the second opinion: the
model no longer decides whether an attempt is over, it asks the flow, which is the only place that
question has an answer. A sixth answer cannot split them apart again, because there is one
definition rather than two that must be kept in step. The decline path was reordered for the same
reason: it used to clear the attempt before telling the flow.

**F2.** The staging directory's exclusion was applied with `try?`. That call is what `SECURITY.md`
states unconditionally, so swallowing its error would have written key material into an unexcluded
directory with nothing raised and no test able to see it. It throws now. The repair on read keeps
its `try?` deliberately, and the two are documented against each other: a repair that fails leaves
a key no worse than it was, while a staging mark that fails creates the exposure.

Also done: the orphan sweep has the test Fable named, and it was confirmed red with the sweep
removed. `age`'s docstring no longer says "never negative" while its own test asserts a negative.
`docs/VAULT.md` no longer claims an older watch keeps exactly the behaviour it had, which is true
of the nonce key and not of `.busy`. `SECURITY.md` says which half of the repair the device
verification covers, which is neither half, since it predates it.

**Not yet acted on: the residue on change 10.** The owner taps the affirmative button, the phone
declines on their behalf because the window has passed, and the watch is told while the person who
tapped is not. It is the only path where tapping yes produces no on the device that was tapped.

## The answer to question four

Fable split it three ways: the storage path is converging and it would not expect a fourth
rewrite; the core protocol and flow are converging throughout; **the app-target seam is not, and it
is the generator.**

Its argument is that the pattern is now three rounds long and exact. Round one's two races lived in
the untestable watch model. Round two's re-ask and consent window landed in app targets argued for
by comments, and two of three needed rework. Round three's F1 is the same species, in the same
file, found the same way, because reading is the only thing that can reach it. **The defect surface
is not moving around at random; it is pooling where the tests cannot go.**

The extraction that would drain it is the pattern this project has already run twice, under the
names `WatchProvisioningFlow` and `AppLockPresentation`. It was proposed in round one by two
engines, acknowledged in round two, put as "a fair question" by this very file, and not done.

---

## Fable 5

*Read-only pass over commit `71e88c3`. Reproduced as returned, with absolute paths made
repository-relative.*

> Round three of Scope 2. Same asymmetry on record as last time: this conversation holds rounds one and two, not the fresh session the method prefers.
>
> Code reviewed: 71e88c3, via the tip of `a4-fixes` (7e79d1c), which I confirmed differs from it only in the round-three account itself. Round two read 350375b; round one read 74fe841. Standing asymmetry, recorded again: this conversation held rounds one and two, so I am reviewing responses to findings I helped produce, which is the acceptance bias this round tells me to resist. Where a change adopted my own round-two suggestion, I have said so and attacked it anyway.
>
> Verdict in one paragraph: eight of the ten changes are complete, several with the test that would catch their own regression. Change 5 is the one that isn't — the `.busy` answer was implemented in the core and never in the watch model, which still treats it as terminal and destroys the attempt the flow is deliberately holding, so two shipped tests and this round's own account now assert claimability the app does not have. Change 1 is complete except that its load-bearing call is a swallowed error. And to question four: the storage path is converging; the core protocol is converging; the app-target seam is not — this is the third consecutive round in which a fix's core half landed tested and its app-target half landed wrong or absent.
>
> Question 1, change by change
>
> 1. The PendingKeys directory — yes, with one soft spot (finding F2). The construction is right, and righter than either previous attempt: exclusion now precedes content by construction, the directory also carries the protection class so files start protected, the sweep covers the kill-orphan (which is itself already excluded when it happens), and `.usingNewMetadataOnly` resolves the metadata question round two could not — with the honest note that macOS measurement covered only the exclusion half. The fresh-install and overwrite paths still pass the existing suite through `replaceItemAt`. The soft spot: in `stagingDirectory()`, the directory's `setResourceValues(isExcludedFromBackup)` is `try?` — see F2.
>
> 2. Repair on read — yes. This reaches the device the account correctly says needs it most: the watch reads its key on every activation, so an old-rules file gets repaired at first launch of the new build. Metadata-only is verifiably true of the exclusion half (`loadRepairsAnUnexcludedKey`, whose fresh-URL comment records a real trap found while writing it) and unverifiable on the test host for the protection-class half, since `protectionAttributes` is `[:]` on macOS — `repairPreservesTheKey` proves content stability there while the class change is a no-op. The claim "incapable of damaging the key" therefore rests on Apple's `setAttributes` being atomic for class changes, which is reasoned, not measured; the one check that settles it is reading class and bytes back on a real watch that entered the build with an old-rules file. SECURITY.md's "verified on a real device" sentence predates this change, and whether that verification included the repair path is not stated.
>
> 3. `ContinuousClock` — yes, fully. Instant internal, `age(now:)` the only reading, the test pins the backward case explicitly, and the `SuspendingClock` rejection is reasoned correctly in the comment (a sleeping phone with an alert up has still let time pass for the person). Two residues, both small: `age`'s docstring says "never negative" while its own test asserts a negative return when handed a past instant — the contract and the comment disagree, and one clause ("under the default argument") fixes it; and truncation to whole seconds makes the window lenient by under a second, which is nothing.
>
> 4. The re-ask removed — yes, and the removal is correct. For the record, since the prompt says disagreement with recorded conclusions is in scope: I was one of the two reviewers who cleared the re-ask, and ChatGPT's seven-step sequence is right where my trace was incomplete. I verified the loop couldn't spin, which was true and was not the question; the inference "obsolete response implies slot free" is indeed unsound when the response was delayed rather than just-answered, and in that interleaving the re-ask abandons a request the phone is actively showing. The maintainer's summary — "the spin was never the problem" — is accurate, including about my review.
>
> 5. `.busy` — the core half yes, the watch half no. This is the round's finding (F1).
>
> 6. The busy-after-timeout guard — yes at the flow level, with the right test, and the account's own observation that needing it inside the same batch is unflattering is fair. The dead code after the guard (`stage = .waiting` when stage is already `.waiting`) is a harmless oddity. But note this guard's test asserts "a late key still installs" after busy-after-timeout — true of the flow, false of the app, for the reason in F1.
>
> 7. The `phoneDeclined` guard — yes, exactly the sibling guard with tests from both sides. Closes my round-two N3.
>
> 8. Exclusion on the staged file — yes, and the account's reading of it is the correct one: change 1 alone would have shipped the resting key unexcluded, the suite caught it, and that is simultaneously the suite doing its job and evidence change 1 wasn't fully understood when written. Both readings are indeed available; the second is the one that generalizes.
>
> 9. Present-but-unreadable nonce — yes. The three cases are now distinct: absent -> honoured (old build), unreadable -> ignored, readable-but-foreign -> ignored. A readable nonce of the wrong length lands in `answers(_:)`'s length guard and is ignored, consistently.
>
> 10. Expiry declines — yes, with one residue. The watch now learns immediately and the alert clears. The residue: the owner tapped "Set up Apple Watch" and the phone silently declined on their behalf — the watch gets told, the person who tapped still gets nothing, and their watch now reads "Not set up. Try again." Better than the silent no-op it replaces; still the only path where tapping the affirmative button produces the negative outcome with no explanation on the device that was tapped.
>
> Question 2: what the changes introduced
>
> F1 — Medium-low. The watch model treats `.busy` as terminal, so the flow and the app disagree about whether the attempt survives
>
> `WatchVaultModel.swift:184`: `if answer != .asking { attempt = nil; self.token = nil }` was not updated when the fifth answer was added. `.busy` fails that test, so the model destroys the attempt and its token in the same breath as `flow.phoneAnswered(.busy)` deliberately keeps the attempt outstanding. The result is the exact split the tokens were invented to prevent: the flow says waiting-and-claimable, the model holds nothing.
>
> What it breaks, concretely: `busyKeepsTheAttempt` asserts "the attempt is held, so a later answer to it can still open" — false in the app; `busyAfterTimeoutDoesNotRestoreTheSpinner` asserts "the attempt is still claimable, so a late key still installs" — false in the app, because `phoneSent`'s install path guards on the stored attempt the model just discarded; and the decline-nonce matching from round two degrades silently, since with `attempt` nil a readable foreign nonce falls through and is honoured, reopening the stale-decline corner change 4 of round two closed. The account's own description of change 5 — "the watch keeps the attempt and keeps waiting" — is true of `WatchProvisioningFlow` and untrue of the watch.
>
> Practical harm today is bounded, which is why this is not higher: a `.busy` answer refers to a request the phone dropped, so no sealed response to that attempt is ever coming, and the 25-second timeout recovers either way. But the properties two tests and one document now pin are not the properties the shipped watch has.
>
> Smallest fix: `if answer != .asking && answer != .busy` — one condition, mirroring the flow's own definition of non-terminal — plus the comment above it, which currently reads "Anything but 'asking' ends this attempt" and is the false claim making the bug look deliberate. The durable fix is the extraction; see question four.
>
> F2 — Low. The guarantee's load-bearing call swallows its error
>
> `VaultKeyStore.swift:190`-ish, in `stagingDirectory()`: the directory exclusion — the thing SECURITY.md now states unconditionally ("there is no instant at which a complete key sits on disk outside the exclusion") — is applied with `try?`, while the file-level mark three lines later in `install` correctly throws. If the directory mark ever fails, key material is written into an unexcluded directory and the write-window guarantee lapses with no error, no log, and no test able to notice. The re-mark on every call self-heals for the next install, which is the pattern this same finding's history says not to rely on. Smallest fix: let it throw, as the file mark already does — `install` has a caller prepared for failure on every other line.
>
> Recorded, not defects
>
> * Mixed versions, the direction the docs don't cover: an old watch receiving `"busy"` fails the `rawValue` init and lands on "treated as a refusal" — an instant "Not set up. Try again." where the old pairing showed a spinner then a timeout. Self-healing and arguably kinder, but it is a behavior change for old watches that nothing documents; VAULT.md's new compatibility paragraph covers the nonce key and says the older watch keeps "exactly the behaviour it already had," which is true of declines and not of `.busy`.
> * The narrowed-not-closed path the account discloses is described accurately: I re-traced it, and `.busy` plus the timeout is where it honestly ends. Whether that is sufficient — I think yes: every remaining dead-end in the machine now terminates at a screen with a button within 25 seconds, and the alternatives round two tried were worse.
> * One missing test that is core-reachable today: nothing exercises the orphan sweep (`stagingDirectory` deleting a leftover pending file). Plant a file, install, assert it is gone — three lines, and it pins the half of change 1 that exists specifically because `defer` doesn't run after a kill.
>
> Question 3: claims vs. code
>
> The model comment "Anything but 'asking' ends this attempt" (F1) is the significant one — it states the defect as policy. The `age` docstring's "never negative" (change 3, above) is the small one. SECURITY.md's new storage paragraph is accurate conditional on the `try?` in F2 holding, which is exactly the kind of condition this project prefers written down. The new VAULT.md third-message table is accurate and the kind of thing a second implementer genuinely needs; its "exactly the behaviour it already had" clause is the only sentence in it that overreaches, per the mixed-version note above.
>
> Question 4: is this converging?
>
> Split answer, said plainly.
>
> The storage path: yes, now. Three rewrites for one finding is a bad number, but the trajectory is not circular — each rewrite failed at a strictly deeper layer (unmarked file -> unmarked staging file -> destination metadata), and the current shape is the first one that is right by construction rather than by ordering: exclusion precedes content, repair reaches devices that never write, and the one metadata question was measured rather than believed. Residual risk is F2's swallowed error and the unmeasured protection-class half on watch hardware. I would not expect a fourth rewrite.
>
> The core protocol and flow: yes, throughout. Every core-side change across three rounds landed with the test that would catch its regression, one of those tests caught a defect in its own batch before any reviewer saw it, and the negative-control suite now pins properties (ephemeral freshness, label participation, monotonic age) that round one proved the old suite could not see.
>
> The app-target seam: no, and it is the generator. The pattern is now three rounds long and exact: round one's races lived in the untestable watch model; round two's re-ask and consent window landed in app targets argued for by comments, and two of the three needed rework; round three's `.busy` landed tested in the core and wrong in the model — F1 is the same species of defect as the two races that started this scope, in the same file, for the same reason, found the same way (by reading, because nothing else can reach it). The defect surface is not moving around at random; it is pooling exactly where the tests cannot go, and the extraction that would drain it — the pending-request rule and the answer-handling into core value types, the pattern this project already executed twice under the names `WatchProvisioningFlow` and `AppLockPresentation` — has now been proposed in round one by two engines, acknowledged in round two, posed as "a fair question" in round three's own account, and not done. That is the most useful sentence I can write here: the next defect in this scope is already predictable to be in `WatchVaultModel` or `WatchKeyProvider`, because that is where the last five were, and it will keep being true until the decisions leave the targets the suite cannot reach.
