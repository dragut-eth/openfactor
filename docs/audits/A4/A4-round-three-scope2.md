# A4 round three, scope 2: what changed and why

Round two reviewed the eleven fixes from round one and changed ten more things. **Those ten have
not been reviewed by anybody.** This is the "what changed" block the round three prompt in
`docs/audits/A4/A4-prompts.md` calls for.

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
| ChatGPT 5.6 Sol | Returned, below. One medium, two low, and a fix assessment item by item |
| Fable 5 | Returned, below. Eight of ten complete, one medium-low, one low |
| Grok 4.6 | Returned, below. No new medium. Converging, said plainly |

**All three engines found F1 independently, by three different routes**: Fable by reading the
answer set against the model, ChatGPT by walking a five-step interleaving to a decline, Grok by
noticing that a flow test's sentence is false of the only code that calls `open`. Round one
produced unanimity on 3 findings out of 44. This is the fourth.

Grok also declined to file F2 as a hole, saying it had not seen the call fail and would not treat
it as demonstrated. It was fixed anyway, which the other two asked for. **Two engines calling the
same `try?` a medium and one refusing to call it anything is the disagreement worth keeping**, and
it is the reason the fix now reads the flag back rather than only throwing.

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

**ChatGPT's third finding: two documents disagreeing about what the app rests on.**
`docs/VAULT.md`'s "what must be proven" list still called WatchConnectivity routing defense in
depth "because of the authentication string", and credited a negative control involving that
string. The six digit string was removed a while ago, in a section of that same document, and
`SECURITY.md` has said routing is load bearing ever since. The list now says blocking and load
bearing, and the E7 measurement is marked as history rather than as a property.

**Where ChatGPT asked for more than was done, and it is recorded rather than quietly declined.**
It wanted the exclusion read back rather than merely attempted, which is done: `install` refuses
to write a key at all unless the directory reads back excluded, with `notExcludedFromBackup` as
its own error. It also wanted `repairProtection` to fail closed or report that a key remains
weak. It still swallows its errors, deliberately: that path repairs a key which already exists
and is already readable, so failing closed would stop somebody reading their own accounts to
punish a metadata call, and the file is left no worse than it was. The two calls are now
documented against each other in the source. **This is a judgment, and a reviewer disagreed with
it.**

**Grok's three of its own, and one of them is about a test I wrote.** The test pinning the clock
fix asserted a negative reading and its message claimed such a reading could never be inside the
window. Grok checked: minus an hour is less than two minutes, so the obvious comparison lets an
arbitrarily old request through, and the test proved nothing of the sort. The policy that makes
the message true did not exist. It does now, as `ValidatedRequest.isAnswerable(within:)` in the
core, which refuses a negative elapsed time the way `AppLockEngine` refuses a backward clock, and
the app asks it rather than comparing anything itself. Both directions are tested, and the test
was confirmed red against the obvious comparison.

Grok also caught `docs/VAULT.md` still saying a nonce-less decline is honoured so as not to
strand a watch. The code comment saying that was corrected in round two; this sentence was not.
And it noted that the consent window was still only checked on a tap, so the alert could sit for
hours: **the second review to ask for that**, and it is done, so the deadline arrives on its own,
the alert goes, and the watch is told.

**Not yet acted on: the residue on change 10.** The owner taps the affirmative button, the phone
declines on their behalf because the window has passed, and the watch is told while the person who
tapped is not. It is the only path where tapping yes produces no on the device that was tapped.

## The answer to question four

Both engines answered it, and they agree on the shape while disagreeing on how far it has got.

ChatGPT: the cryptography and the parser have converged; the two repeatedly rewritten areas have
not, because the file-writing path still failed open at its critical operation and the tested
reducer disagreed with the app layer that owns the attempt. Its verdict is that the defect surface
is smaller than round one and **not yet stable enough to support this repository's absolute backup
and request-binding claims**, which is the sharpest sentence written about this gate so far, since
both of those claims are made in `SECURITY.md` without qualification.

Grok: yes, and it gave the clearest test for the distinction. Change 1 introduced change 8 in the
same batch and change 5 introduced change 6 in the same batch, both caught by tests before any
reviewer saw them. **The last batch closed the holes the previous batch opened, instead of opening
a third generation, and that is the difference between churn and convergence.** What remains it
calls residue rather than a new family: one line in the watch target, and two behaviours that the
suite still cannot reach.

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

## ChatGPT 5.6 Sol

*Read-only pass over commit `71e88c3`. Reproduced as returned, with absolute paths made
repository-relative.*

> Reviewed commit `71e88c3`; the checked-out source matches it, with only the stated audit-document paragraph differing. I found one medium and two low issues.
>
> Findings
>
> 1. Medium — staging-directory exclusion failure is ignored, preserving the raw-key backup window
>
> `VaultKeyStore.stagingDirectory()` (line 176) suppresses failure from the operation that establishes its security precondition:
>
>     values.isExcludedFromBackup = true
>     try? marked.setResourceValues(values)
>
> Concrete failure order:
>
> 1. Creating or re-marking `PendingKeys` succeeds, but setting its backup exclusion fails.
> 2. The error is discarded and the directory is returned.
> 3. `install` writes the complete raw key at line 144.
> 4. The process is killed before the staged file itself is marked at line 157.
> 5. `defer` does not run, leaving an unexcluded raw key for the next backup.
>
> This is the same exposure reported in the previous two rounds, now conditional on a metadata-operation failure rather than every install. It contradicts both the source comment at lines 129-139 and SECURITY.md (line 116), which claim exclusion is established before any key material exists.
>
> The related migration in `repairProtection` also suppresses both metadata failures at lines 96 and 105, so reading an older weak key does not reliably repair it and gives the caller no indication that remediation failed.
>
> Smallest fix: make staging-directory exclusion throwing, read it back as `true`, and refuse to write any key otherwise. Add fault injection for directory-exclusion failure and assert that no file containing key bytes is created. Existing-key repair should either fail closed or explicitly report that the key remains weak.
>
> 2. Low — `.busy` is nonterminal in the flow but terminal in the actual watch model
>
> `WatchVaultModel.phoneAnswered` (line 176) passes `.busy` to the flow, which deliberately keeps the attempt outstanding, but then clears the cryptographic attempt because `.busy != .asking`:
>
>     flow.phoneAnswered(answer, token: token)
>
>     if answer != .asking {
>         attempt = nil
>         self.token = nil
>     }
>
> A concrete consequence:
>
> 1. Phone retains request A.
> 2. Watch times out A and starts B.
> 3. Phone replies `.busy` to B while retaining A.
> 4. The flow says B remains outstanding, but the model discards B's nonce and private key.
> 5. Owner declines A; the phone sends `{status: "declined", nonce: A_nonce}`.
> 6. At `phoneSent` (line 261), the nonce comparison is skipped because `attempt == nil`.
> 7. `flow.phoneDeclined()` terminates B despite the mismatched nonce.
>
> No key is released, so this is an availability/state-integrity issue rather than key compromise. It nevertheless disproves the round-three account's claim that `.busy` keeps the attempt and that A's decline is ignored while B waits.
>
> Smallest fix: retain the attempt for both nonterminal answers:
>
>     if answer != .asking && answer != .busy { ... }
>
> Also ignore any nonce-bearing decline unless a current attempt exists and matches it. The missing regression test must exercise `WatchVaultModel`'s integration behavior; the existing core-flow test passes precisely because it cannot see the model clearing `attempt`.
>
> 3. Low — the vault document still claims an authentication string exists
>
> docs/VAULT.md (line 593) says WatchConnectivity routing is merely defense in depth "because of the authentication string," and line 604 still credits a negative control involving that string. The string was removed, and the same document correctly says at lines 343-361 that routing exclusivity is now load bearing and undocumented by Apple.
>
> Smallest fix: update this old "must be proven" entry to record the current load-bearing assumption and remove the obsolete authentication-string test claim.
>
> Fix assessment
>
> 1. Excluded staging directory: incomplete because the exclusion error is swallowed.
> 2. Repair existing key metadata: works on the successful path, but silently fails to remediate.
> 3. `ContinuousClock`: correct; wall-clock rollback no longer affects production expiry.
> 4. Remove response-handler re-ask: correct; the unsound inference is gone.
> 5. Add `.busy`: correct on the phone and in the extracted flow, incorrect end to end because the model discards the attempt.
> 6. Preserve the timeout screen on late `.busy`: correct in the flow, but its claim that the late key remains openable is defeated by the model.
> 7. Guard `phoneDeclined`: correct for preventing a decline from demoting `.ready`.
> 8. Mark the staged file itself: correct when staging-directory setup succeeds.
> 9. Distinguish malformed from absent nonce: the type distinction is fixed, but mismatched nonce handling is defeated when item 5 clears `attempt`.
> 10. Expired approval declines and clears state: correct.
>
> The cryptographic construction and byte parsing remain sound: exact lengths precede slicing, P-256 points are validated, the request nonce is checked before public-key parsing or derivation, and the fixed-width transcript binds the version, nonce, and both public keys in both HKDF and GCM AAD. Approval still has only the affirmative alert action as its production call site.
>
> Convergence
>
> The cryptography and parser have converged. The two repeatedly rewritten areas have not: the file-writing path still fails open at its critical exclusion operation, and the state machine's tested reducer now disagrees with the app layer that owns the cryptographic attempt. The defect surface is smaller than in round one, but these are not yet stable enough to support the repository's absolute backup and request-binding claims.
>
> No build or tests were run because doing so would create repository files, contrary to the read-only requirement.

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

---

## Grok 4.6

*Read-only pass over commit `71e88c3`. Reproduced as returned.*

> Reviewed 71e88c3 (this tree is that commit plus the round-three account paragraph). Round two was 350375b; round one was 74fe841. Four questions only.
>
> 1. Does each change address the finding it claims to?
>
> 1. Excluded directory before any key bytes — yes, with one leftover. stagingDirectory() creates PendingKeys, marks it excluded, then the key is written inside it. A kill after the write no longer leaves an unexcluded .{uuid} next to vault.key. replaceItemAt(..., options: [.usingNewMetadataOnly]) is the option round two asked for, so an overwrite can take the new protection class. Directory exclusion is try?. If that call fails they still write. The file is then marked with try (not try?), so a surviving install still excludes vault.key. The kill window between write and that mark is unexcluded only when the directory mark already failed. I did not see that fail in the source; I am not treating it as a demonstrated hole.
>
> 2. load repairs metadata — yes, for what it can see. Bytes are read first, size-checked, then setAttributes / setResourceValues run under try?. A failed repair leaves the old class and still returns the key. The test writes an unmarked 32-byte file, loads, and checks exclusion on a fresh URL (they already burned themselves on a cached URL). Protection class still cannot be observed on the macOS host. I did not run the tests.
>
> I do not know whether changing NSFileProtectionKey in place is atomic against a kill. The comment says the worst failure is the protection the file already had. If that API re-wraps the file and a kill lands in the middle, that comment would be wrong. I am not claiming it does.
>
> 3. ContinuousClock — yes in production. validatedAt is an internal Instant. approve uses request.age(). A wall-clock jump cannot make elapsed time negative on that clock. age(now:) is the only public read, so the app cannot compare a Date to it again.
>
> The comment on age says the result is "never negative." The function does not clamp. age(now: start.advanced(by: Duration.seconds(-3600))) is negative, and negative <= 120 is still inside the window approve uses. Production calls age() with default .now, which should be >= validatedAt. The new test asserts <= 0 and claims that is "never ... inside the window." That assertion does not check > consentWindow. The clock fix holds; the test does not prove what its message says.
>
> 4. Re-ask removed — yes. phoneSent no longer calls ask() on an obsolete response. ChatGPT's seven-step sequence (delayed A while the phone holds B) no longer starts C.
>
> 5. .busy — yes on the phone, half-done on the watch. answer returns .busy when pendingRequest != nil. The first-message reply is no longer a lie. In WatchProvisioningFlow, .busy is non-terminal.
>
> WatchVaultModel.phoneAnswered still does:
>
>         // Anything but "asking" ends this attempt, so the key it holds is of no further use.
>         if answer != .asking {
>             attempt = nil
>             self.token = nil
>         }
>
> .busy is not .asking, so the model throws away the ephemeral key while the flow keeps outstanding. The phone will not seal to a request it answered .busy for, so I could not turn this into a dropped installable key: the request that still has a human in front of it is the earlier one, and that attempt was already overwritten when the watch asked again. What it does do is make the flow test's sentence "a later answer to it can still open" true of WatchProvisioningFlow and false of the only code that calls open.
>
> 6. .busy after timeout — yes. guard stage == .waiting keeps needsPhoneApp. The test that found this is the right test.
>
> 7. phoneDeclined guard — yes. Same outstanding != nil as responseDidNotOpen, with tests from both sides. A decline after installedKey leaves .ready.
>
> 8. Exclusion on the staged file — yes. That is why usingNewMetadataOnly does not strip exclusion off vault.key. The existing exclusion test going red is the proof they needed.
>
> 9. Present-but-unreadable nonce — yes, by reading, not by a test. if let raw = message[nonce] then as? Data, else return. Absent still honours (old phone). Wrong type is ignored. Lives in the watch target. Same shape that hid the original races.
>
> 10. Expiry declines — yes for the security property. The tap no longer releases a stale key, and the watch is told. The alert can still sit on screen for hours until that tap; they did not add a timer that clears it at two minutes. After the tap the watch is declined, not silently ignored. Fail closed.
>
> Fable's leftover path (decline of A while the watch holds B) is narrowed the way the account says: B gets .busy, not .asking, and the 25-second timer ends on a screen with a button. That is enough. Because the model also nils attempt on .busy, a later decline of A is honoured (no attempt to compare) and B ends immediately. That is an accident, not a specified rule, and it is kinder than waiting out the timer.
>
> 2. Did any change introduce something new?
>
> Change 1 introduced change 8 in the same batch. Change 5 introduced change 6 in the same batch. Both were caught by tests before this review. That is the suite doing its job, and it is also what a third rewrite of the same write path looks like.
>
> The new interaction I actually see is change 5 against the pre-existing if answer != .asking line. It does not give a second request the vault key, and it does not approve without a tap. It means a .busy watch cannot open a sealed payload even if one arrived, and a decline for a different nonce can now end that attempt because attempt is already nil.
>
> I walked ChatGPT's delayed-response sequence against the current model. Without the re-ask, B is kept and the approval of B opens. That construction is sound. The thing two of us cleared last round (no spin) was never the defect; removing the re-ask was the right call.
>
> repairProtection on every load did not, from the code, rewrite key bytes. contents(atPath:) happens first. I am not filing a damage path I cannot show.
>
> 3. Claims the code does not do
>
> * WatchProvisioning.Answer.busy: "The watch keeps its attempt." True in WatchProvisioningFlow. False in WatchVaultModel.
> * phoneAnswered in the model: "Anything but asking ends this attempt." That is what the if does, and it is the opposite of the .busy comment one file over.
> * age(now:): "never negative." It returns Duration.components.seconds with no clamp.
> * The new age test's message: a backward now "must never read as inside the window." -3600 <= 120 is inside the window approve uses.
> * install: "from the moment any key material exists on disk it is already outside every backup." True only if the directory setResourceValues succeeded. That call is try?.
> * docs/VAULT.md still says a nonce-less decline is honoured so as not to "strand" a watch. The timeout is 25 seconds and then there is a button. The watch comment was corrected; this sentence was not.
>
> messageKeysArePinned now includes nonce. SECURITY.md no longer states the echo unconditionally and no longer calls the window wall-clock minutes. Those two match.
>
> 4. Is this converging?
>
> Yes. The surface is shrinking, not rotating.
>
> The write path has been rewritten three times and, with change 8, is the first version that actually has the two properties people kept asking for: no unexcluded key during the write, and an overwrite that can take new metadata. I would not rewrite it a fourth time for the try? on the directory.
>
> The state machine has been touched three times and is smaller than it was: the re-ask is gone, the phone does not lie, a late decline cannot demote .ready, consent is on a clock that does not run backwards. What is left is one line in the watch target that was not updated when .busy was added, and two behaviours (9 and 10) that still cannot be tested from the suite that exists. That is residue, not a new family of defects.
>
> Twenty-one changes is a lot. The last batch closed the holes the previous batch opened, instead of opening a third generation. That is the difference between churn and convergence.
>
> No new medium. The cryptography and parsers were not touched and I am not re-litigating them. Approval is still only the affirmative button. I did not find a way to install a key from an unverified or abandoned attempt, or to seal to a request the owner is not being shown.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

## Fable

Round three of Scope 2. Same asymmetry on record as last time: this conversation holds rounds one and two, not the fresh session the method prefers. Reading the round-three account and the updated prompts first.
Ran 6 commands, read A4-round-three-scope2.md
One claim I need to verify in the current source before writing this up: how the watch model's `phoneAnswered` treats the new `.busy` answer — the diff didn't touch it.
Read phoneAnswered in the watch model at 71e88c3
A4 round three, scope 2: the ten changes, reviewed
Code reviewed: 71e88c3, via the tip of `a4-fixes` (7e79d1c), which I confirmed differs from it only in the round-three account itself. Round two read 350375b; round one read 74fe841. Standing asymmetry, recorded again: this conversation held rounds one and two, so I am reviewing responses to findings I helped produce, which is the acceptance bias this round tells me to resist. Where a change adopted my own round-two suggestion, I have said so and attacked it anyway.
Verdict in one paragraph: eight of the ten changes are complete, several with the test that would catch their own regression. Change 5 is the one that isn't — the `.busy` answer was implemented in the core and never in the watch model, which still treats it as terminal and destroys the attempt the flow is deliberately holding, so two shipped tests and this round's own account now assert claimability the app does not have. Change 1 is complete except that its load-bearing call is a swallowed error. And to question four: the storage path is converging; the core protocol is converging; the app-target seam is not — this is the third consecutive round in which a fix's core half landed tested and its app-target half landed wrong or absent.
Question 1, change by change
1. The PendingKeys directory — yes, with one soft spot (finding F2). The construction is right, and righter than either previous attempt: exclusion now precedes content by construction, the directory also carries the protection class so files start protected, the sweep covers the kill-orphan (which is itself already excluded when it happens), and `.usingNewMetadataOnly` resolves the metadata question round two could not — with the honest note that macOS measurement covered only the exclusion half. The fresh-install and overwrite paths still pass the existing suite through `replaceItemAt`. The soft spot: in `stagingDirectory()`, the directory's `setResourceValues(isExcludedFromBackup)` is `try?` — see F2.
2. Repair on read — yes. This reaches the device the account correctly says needs it most: the watch reads its key on every activation, so an old-rules file gets repaired at first launch of the new build. Metadata-only is verifiably true of the exclusion half (`loadRepairsAnUnexcludedKey`, whose fresh-URL comment records a real trap found while writing it) and unverifiable on the test host for the protection-class half, since `protectionAttributes` is `[:]` on macOS — `repairPreservesTheKey` proves content stability there while the class change is a no-op. The claim "incapable of damaging the key" therefore rests on Apple's `setAttributes` being atomic for class changes, which is reasoned, not measured; the one check that settles it is reading class and bytes back on a real watch that entered the build with an old-rules file. SECURITY.md's "verified on a real device" sentence predates this change, and whether that verification included the repair path is not stated.
3. `ContinuousClock` — yes, fully. Instant internal, `age(now:)` the only reading, the test pins the backward case explicitly, and the `SuspendingClock` rejection is reasoned correctly in the comment (a sleeping phone with an alert up has still let time pass for the person). Two residues, both small: `age`'s docstring says "never negative" while its own test asserts a negative return when handed a past instant — the contract and the comment disagree, and one clause ("under the default argument") fixes it; and truncation to whole seconds makes the window lenient by under a second, which is nothing.
4. The re-ask removed — yes, and the removal is correct. For the record, since the prompt says disagreement with recorded conclusions is in scope: I was one of the two reviewers who cleared the re-ask, and ChatGPT's seven-step sequence is right where my trace was incomplete. I verified the loop couldn't spin, which was true and was not the question; the inference "obsolete response ⟹ slot free" is indeed unsound when the response was delayed rather than just-answered, and in that interleaving the re-ask abandons a request the phone is actively showing. The maintainer's summary — "the spin was never the problem" — is accurate, including about my review.
5. `.busy` — the core half yes, the watch half no. This is the round's finding (F1).
6. The busy-after-timeout guard — yes at the flow level, with the right test, and the account's own observation that needing it inside the same batch is unflattering is fair. The dead code after the guard (`stage = .waiting` when stage is already `.waiting`) is a harmless oddity. But note this guard's test asserts "a late key still installs" after busy-after-timeout — true of the flow, false of the app, for the reason in F1.
7. The `phoneDeclined` guard — yes, exactly the sibling guard with tests from both sides. Closes my round-two N3.
8. Exclusion on the staged file — yes, and the account's reading of it is the correct one: change 1 alone would have shipped the resting key unexcluded, the suite caught it, and that is simultaneously the suite doing its job and evidence change 1 wasn't fully understood when written. Both readings are indeed available; the second is the one that generalizes.
9. Present-but-unreadable nonce — yes. The three cases are now distinct: absent → honoured (old build), unreadable → ignored, readable-but-foreign → ignored. A readable nonce of the wrong length lands in `answers(_:)`'s length guard and is ignored, consistently.
10. Expiry declines — yes, with one residue. The watch now learns immediately and the alert clears. The residue: the owner tapped "Set up Apple Watch" and the phone silently declined on their behalf — the watch gets told, the person who tapped still gets nothing, and their watch now reads "Not set up. Try again." Better than the silent no-op it replaces; still the only path where tapping the affirmative button produces the negative outcome with no explanation on the device that was tapped.
Question 2: what the changes introduced
F1 — Medium-low. The watch model treats `.busy` as terminal, so the flow and the app disagree about whether the attempt survives
`WatchVaultModel.swift:184`: `if answer != .asking { attempt = nil; self.token = nil }` was not updated when the fifth answer was added. `.busy` fails that test, so the model destroys the attempt and its token in the same breath as `flow.phoneAnswered(.busy)` deliberately keeps the attempt outstanding. The result is the exact split the tokens were invented to prevent: the flow says waiting-and-claimable, the model holds nothing.
What it breaks, concretely: `busyKeepsTheAttempt` asserts "the attempt is held, so a later answer to it can still open" — false in the app; `busyAfterTimeoutDoesNotRestoreTheSpinner` asserts "the attempt is still claimable, so a late key still installs" — false in the app, because `phoneSent`'s install path guards on the stored attempt the model just discarded; and the decline-nonce matching from round two degrades silently, since with `attempt` nil a readable foreign nonce falls through and is honoured, reopening the stale-decline corner change 4 of round two closed. The account's own description of change 5 — "the watch keeps the attempt and keeps waiting" — is true of `WatchProvisioningFlow` and untrue of the watch.
Practical harm today is bounded, which is why this is not higher: a `.busy` answer refers to a request the phone dropped, so no sealed response to that attempt is ever coming, and the 25-second timeout recovers either way. But the properties two tests and one document now pin are not the properties the shipped watch has.
Smallest fix: `if answer != .asking && answer != .busy` — one condition, mirroring the flow's own definition of non-terminal — plus the comment above it, which currently reads "Anything but 'asking' ends this attempt" and is the false claim making the bug look deliberate. The durable fix is the extraction; see question four.
F2 — Low. The guarantee's load-bearing call swallows its error
`VaultKeyStore.swift:190`-ish, in `stagingDirectory()`: the directory exclusion — the thing SECURITY.md now states unconditionally ("there is no instant at which a complete key sits on disk outside the exclusion") — is applied with `try?`, while the file-level mark three lines later in `install` correctly throws. If the directory mark ever fails, key material is written into an unexcluded directory and the write-window guarantee lapses with no error, no log, and no test able to notice. The re-mark on every call self-heals for the next install, which is the pattern this same finding's history says not to rely on. Smallest fix: let it throw, as the file mark already does — `install` has a caller prepared for failure on every other line.
Recorded, not defects

* Mixed versions, the direction the docs don't cover: an old watch receiving `"busy"` fails the `rawValue` init and lands on "treated as a refusal" — an instant "Not set up. Try again." where the old pairing showed a spinner then a timeout. Self-healing and arguably kinder, but it is a behavior change for old watches that nothing documents; VAULT.md's new compatibility paragraph covers the nonce key and says the older watch keeps "exactly the behaviour it already had," which is true of declines and not of `.busy`.
* The narrowed-not-closed path the account discloses is described accurately: I re-traced it, and `.busy` plus the timeout is where it honestly ends. Whether that is sufficient — I think yes: every remaining dead-end in the machine now terminates at a screen with a button within 25 seconds, and the alternatives round two tried were worse.
* One missing test that is core-reachable today: nothing exercises the orphan sweep (`stagingDirectory` deleting a leftover pending file). Plant a file, install, assert it is gone — three lines, and it pins the half of change 1 that exists specifically because `defer` doesn't run after a kill.

Question 3: claims vs. code
The model comment "Anything but 'asking' ends this attempt" (F1) is the significant one — it states the defect as policy. The `age` docstring's "never negative" (change 3, above) is the small one. SECURITY.md's new storage paragraph is accurate conditional on the `try?` in F2 holding, which is exactly the kind of condition this project prefers written down. The new VAULT.md third-message table is accurate and the kind of thing a second implementer genuinely needs; its "exactly the behaviour it already had" clause is the only sentence in it that overreaches, per the mixed-version note above.
Question 4: is this converging?
Split answer, said plainly.
The storage path: yes, now. Three rewrites for one finding is a bad number, but the trajectory is not circular — each rewrite failed at a strictly deeper layer (unmarked file → unmarked staging file → destination metadata), and the current shape is the first one that is right by construction rather than by ordering: exclusion precedes content, repair reaches devices that never write, and the one metadata question was measured rather than believed. Residual risk is F2's swallowed error and the unmeasured protection-class half on watch hardware. I would not expect a fourth rewrite.
The core protocol and flow: yes, throughout. Every core-side change across three rounds landed with the test that would catch its regression, one of those tests caught a defect in its own batch before any reviewer saw it, and the negative-control suite now pins properties (ephemeral freshness, label participation, monotonic age) that round one proved the old suite could not see.
The app-target seam: no, and it is the generator. The pattern is now three rounds long and exact: round one's races lived in the untestable watch model; round two's re-ask and consent window landed in app targets argued for by comments, and two of the three needed rework; round three's `.busy` landed tested in the core and wrong in the model — F1 is the same species of defect as the two races that started this scope, in the same file, for the same reason, found the same way (by reading, because nothing else can reach it). The defect surface is not moving around at random; it is pooling exactly where the tests cannot go, and the extraction that would drain it — the pending-request rule and the answer-handling into core value types, the pattern this project already executed twice under the names `WatchProvisioningFlow` and `AppLockPresentation` — has now been proposed in round one by two engines, acknowledged in round two, posed as "a fair question" in round three's own account, and not done. That is the most useful sentence I can write here: the next defect in this scope is already predictable to be in `WatchVaultModel` or `WatchKeyProvider`, because that is where the last five were, and it will keep being true until the decisions leave the targets the suite cannot reach.

## ChatGPT

Reviewed commit `71e88c3`; the checked-out source matches it, with only the stated audit-document paragraph differing. I found one medium and two low issues.
Findings

1. Medium — staging-directory exclusion failure is ignored, preserving the raw-key backup window
[`VaultKeyStore.stagingDirectory()` (line 176)](Sources/OpenFactorCore/Vault/VaultKeyStore.swift:176) suppresses failure from the operation that establishes its security precondition:

```
values.isExcludedFromBackup = true
try? marked.setResourceValues(values)
```

Concrete failure order:
   1. Creating or re-marking `PendingKeys` succeeds, but setting its backup exclusion fails.
   2. The error is discarded and the directory is returned.
   3. `install` writes the complete raw key at line 144.
   4. The process is killed before the staged file itself is marked at line 157.
   5. `defer` does not run, leaving an unexcluded raw key for the next backup.
This is the same exposure reported in the previous two rounds, now conditional on a metadata-operation failure rather than every install. It contradicts both the source comment at lines 129–139 and [SECURITY.md (line 116)](SECURITY.md:116), which claim exclusion is established before any key material exists.
The related migration in `repairProtection` also suppresses both metadata failures at lines 96 and 105, so reading an older weak key does not reliably repair it and gives the caller no indication that remediation failed.
Smallest fix: make staging-directory exclusion throwing, read it back as `true`, and refuse to write any key otherwise. Add fault injection for directory-exclusion failure and assert that no file containing key bytes is created. Existing-key repair should either fail closed or explicitly report that the key remains weak.
2. Low — `.busy` is nonterminal in the flow but terminal in the actual watch model
[`WatchVaultModel.phoneAnswered` (line 176)](OpenFactorWatch Watch App/WatchVaultModel.swift:176) passes `.busy` to the flow, which deliberately keeps the attempt outstanding, but then clears the cryptographic attempt because `.busy != .asking`:

```
flow.phoneAnswered(answer, token: token)

if answer != .asking {
    attempt = nil
    self.token = nil
}
```

A concrete consequence:
   1. Phone retains request A.
   2. Watch times out A and starts B.
   3. Phone replies `.busy` to B while retaining A.
   4. The flow says B remains outstanding, but the model discards B’s nonce and private key.
   5. Owner declines A; the phone sends `{status: "declined", nonce: A_nonce}`.
   6. At [`phoneSent` (line 261)](OpenFactorWatch Watch App/WatchVaultModel.swift:261), the nonce comparison is skipped because `attempt == nil`.
   7. `flow.phoneDeclined()` terminates B despite the mismatched nonce.
No key is released, so this is an availability/state-integrity issue rather than key compromise. It nevertheless disproves the round-three account’s claim that `.busy` keeps the attempt and that A’s decline is ignored while B waits.
Smallest fix: retain the attempt for both nonterminal answers:

```
if answer != .asking && answer != .busy { ... }
```

Also ignore any nonce-bearing decline unless a current attempt exists and matches it. The missing regression test must exercise `WatchVaultModel`’s integration behavior; the existing core-flow test passes precisely because it cannot see the model clearing `attempt`.
3. Low — the vault document still claims an authentication string exists
[docs/VAULT.md (line 593)](docs/VAULT.md:593) says WatchConnectivity routing is merely defense in depth “because of the authentication string,” and line 604 still credits a negative control involving that string. The string was removed, and the same document correctly says at lines 343–361 that routing exclusivity is now load bearing and undocumented by Apple.
Smallest fix: update this old “must be proven” entry to record the current load-bearing assumption and remove the obsolete authentication-string test claim.

Fix assessment

1. Excluded staging directory: incomplete because the exclusion error is swallowed.
2. Repair existing key metadata: works on the successful path, but silently fails to remediate.
3. `ContinuousClock`: correct; wall-clock rollback no longer affects production expiry.
4. Remove response-handler re-ask: correct; the unsound inference is gone.
5. Add `.busy`: correct on the phone and in the extracted flow, incorrect end to end because the model discards the attempt.
6. Preserve the timeout screen on late `.busy`: correct in the flow, but its claim that the late key remains openable is defeated by the model.
7. Guard `phoneDeclined`: correct for preventing a decline from demoting `.ready`.
8. Mark the staged file itself: correct when staging-directory setup succeeds.
9. Distinguish malformed from absent nonce: the type distinction is fixed, but mismatched nonce handling is defeated when item 5 clears `attempt`.
10. Expired approval declines and clears state: correct.

The cryptographic construction and byte parsing remain sound: exact lengths precede slicing, P-256 points are validated, the request nonce is checked before public-key parsing or derivation, and the fixed-width transcript binds the version, nonce, and both public keys in both HKDF and GCM AAD. Approval still has only the affirmative alert action as its production call site.
Convergence
The cryptography and parser have converged. The two repeatedly rewritten areas have not: the file-writing path still fails open at its critical exclusion operation, and the state machine’s tested reducer now disagrees with the app layer that owns the cryptographic attempt. The defect surface is smaller than in round one, but these are not yet stable enough to support the repository’s absolute backup and request-binding claims.
No build or tests were run because doing so would create repository files, contrary to the read-only requirement.

## Grok

Reviewed 71e88c3 (this tree is that commit plus the round-three account paragraph). Round two was 350375b; round one was 74fe841. Four questions only.

───

1. Does each change address the finding it claims to?

1. Excluded directory before any key bytes — yes, with one leftover. stagingDirectory() creates PendingKeys, marks it excluded, then the key is written inside it. A kill after the write no longer leaves an unexcluded .{uuid} next to vault.key. replaceItemAt(..., options: [.usingNewMetadataOnly]) is the option round two asked for, so an overwrite can take the new protection class. Directory exclusion is try?. If that call fails they still write. The file is then marked with try (not try?), so a surviving install still excludes vault.key. The kill window between write and that mark is unexcluded only when the directory mark already failed. I did not see that fail in the source; I am not treating it as a demonstrated hole.

2. load repairs metadata — yes, for what it can see. Bytes are read first, size-checked, then setAttributes / setResourceValues run under try?. A failed repair leaves the old class and still returns the key. The test writes an unmarked 32-byte file, loads, and checks exclusion on a fresh URL (they already burned themselves on a cached URL). Protection class still cannot be observed on the macOS host. I did not run the tests.

I do not know whether changing NSFileProtectionKey in place is atomic against a kill. The comment says the worst failure is the protection the file already had. If that API re-wraps the file and a kill lands in the middle, that comment would be wrong. I am not claiming it does.

3. ContinuousClock — yes in production. validatedAt is an internal Instant. approve uses request.age(). A wall-clock jump cannot make elapsed time negative on that clock. age(now:) is the only public read, so the app cannot compare a Date to it again.

The comment on age says the result is “never negative.” The function does not clamp. age(now: start.advanced(by: Duration.seconds(-3600))) is negative, and negative <= 120 is still inside the window approve uses. Production calls age() with default .now, which should be ≥ validatedAt. The new test asserts <= 0 and claims that is “never … inside the window.” That assertion does not check > consentWindow. The clock fix holds; the test does not prove what its message says.

4. Re-ask removed — yes. phoneSent no longer calls ask() on an obsolete response. ChatGPT’s seven-step sequence (delayed A while the phone holds B) no longer starts C.

5. .busy — yes on the phone, half-done on the watch. answer returns .busy when pendingRequest != nil. The first-message reply is no longer a lie. In WatchProvisioningFlow, .busy is non-terminal.

WatchVaultModel.phoneAnswered still does:

        // Anything but "asking" ends this attempt, so the key it holds is of no further use.
        if answer != .asking {
            attempt = nil
            self.token = nil
        }

.busy is not .asking, so the model throws away the ephemeral key while the flow keeps outstanding. The phone will not seal to a request it answered .busy for, so I could not turn this into a dropped installable key: the request that still has a human in front of it is the earlier one, and that attempt was already overwritten when the watch asked again. What it does do is make the flow test’s sentence “a later answer to it can still open” true of WatchProvisioningFlow and false of the only code that calls open.

6. .busy after timeout — yes. guard stage == .waiting keeps needsPhoneApp. The test that found this is the right test.

7. phoneDeclined guard — yes. Same outstanding != nil as responseDidNotOpen, with tests from both sides. A decline after installedKey leaves .ready.

8. Exclusion on the staged file — yes. That is why usingNewMetadataOnly does not strip exclusion off vault.key. The existing exclusion test going red is the proof they needed.

9. Present-but-unreadable nonce — yes, by reading, not by a test. if let raw = message[nonce] then as? Data, else return. Absent still honours (old phone). Wrong type is ignored. Lives in the watch target. Same shape that hid the original races.

10. Expiry declines — yes for the security property. The tap no longer releases a stale key, and the watch is told. The alert can still sit on screen for hours until that tap; they did not add a timer that clears it at two minutes. After the tap the watch is declined, not silently ignored. Fail closed.

Fable’s leftover path (decline of A while the watch holds B) is narrowed the way the account says: B gets .busy, not .asking, and the 25-second timer ends on a screen with a button. That is enough. Because the model also nils attempt on .busy, a later decline of A is honoured (no attempt to compare) and B ends immediately. That is an accident, not a specified rule, and it is kinder than waiting out the timer.

───

2. Did any change introduce something new?

Change 1 introduced change 8 in the same batch. Change 5 introduced change 6 in the same batch. Both were caught by tests before this review. That is the suite doing its job, and it is also what a third rewrite of the same write path looks like.

The new interaction I actually see is change 5 against the pre-existing if answer != .asking line. It does not give a second request the vault key, and it does not approve without a tap. It means a .busy watch cannot open a sealed payload even if one arrived, and a decline for a different nonce can now end that attempt because attempt is already nil.

I walked ChatGPT’s delayed-response sequence against the current model. Without the re-ask, B is kept and the approval of B opens. That construction is sound. The thing two of us cleared last round (no spin) was never the defect; removing the re-ask was the right call.

repairProtection on every load did not, from the code, rewrite key bytes. contents(atPath:) happens first. I am not filing a damage path I cannot show.

───

3. Claims the code does not do

• WatchProvisioning.Answer.busy: “The watch keeps its attempt.” True in WatchProvisioningFlow. False in WatchVaultModel.
• phoneAnswered in the model: “Anything but asking ends this attempt.” That is what the if does, and it is the opposite of the .busy comment one file over.
• age(now:): “never negative.” It returns Duration.components.seconds with no clamp.
• The new age test’s message: a backward now “must never read as inside the window.” -3600 <= 120 is inside the window approve uses.
• install: “from the moment any key material exists on disk it is already outside every backup.” True only if the directory setResourceValues succeeded. That call is try?.
• docs/VAULT.md still says a nonce-less decline is honoured so as not to “strand” a watch. The timeout is 25 seconds and then there is a button. The watch comment was corrected; this sentence was not.

messageKeysArePinned now includes nonce. SECURITY.md no longer states the echo unconditionally and no longer calls the window wall-clock minutes. Those two match.

───

4. Is this converging?

Yes. The surface is shrinking, not rotating.

The write path has been rewritten three times and, with change 8, is the first version that actually has the two properties people kept asking for: no unexcluded key during the write, and an overwrite that can take new metadata. I would not rewrite it a fourth time for the try? on the directory.

The state machine has been touched three times and is smaller than it was: the re-ask is gone, the phone does not lie, a late decline cannot demote .ready, consent is on a clock that does not run backwards. What is left is one line in the watch target that was not updated when .busy was added, and two behaviours (9 and 10) that still cannot be tested from the suite that exists. That is residue, not a new family of defects.

Twenty-one changes is a lot. The last batch closed the holes the previous batch opened, instead of opening a third generation. That is the difference between churn and convergence.

───

No new medium. The cryptography and parsers were not touched and I am not re-litigating them. Approval is still only the affirmative button. I did not find a way to install a key from an unverified or abandoned attempt, or to seal to a request the owner is not being shown.
