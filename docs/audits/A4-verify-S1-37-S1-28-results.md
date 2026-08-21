# A4 verification: S1-37 and S1-28, answered

Reviewed commits: `c4360dd` for S1-28, `f75ce5b` for S1-37.

## The answers

| Engine | S1-37 fixed? | S1-28 fixed? | New high or medium? |
| --- | --- | --- | --- |
| ChatGPT | **Not fully** | **No** | No |
| Fable | Yes | Yes | No |
| Grok | Yes | Yes | No |

**Nobody found a new high or medium**, and the third round running has ended two to one with the
same engine dissenting. As before, the dissent is specific and one half of it is right.

## S1-38 (low): a twin forming between the count and the update still collides, and is misnamed

**Found by ChatGPT alone. Verified here, and Grok's contrary reading is wrong.**

`setSynchronizable` repairs, counts at one point, and updates at another:

```
guard try countingBothFlags() <= 1 else { throw .twinnedRecord }     // line 14
...
let status = SecItemUpdate(find as CFDictionary, changes as CFDictionary)   // line 26
guard status == errSecSuccess else { throw error(for: status) }
```

A record arriving between those two lines is invisible to the count, the update then collides with
it, `SecItemUpdate` returns `errSecDuplicateItem`, and `error(for:)` maps that to `.duplicate`.
`message(for:)` special-cases only `.twinnedRecord`, **so the retry advice that S1-28 removed comes
back in exactly this window.**

Grok wrote that in this situation the conversion "throws `twinnedRecord` rather than colliding".
That is true only if the count sees the pair, which by construction it does not. **The count-then-act
shape is the same one S1-26 was about**, and it was closed there by making one read serve both
purposes. It cannot be closed the same way here, because a count and an update are inherently two
calls.

**But the naming can be fixed cheaply and completely**: a collision at this update *is* the twin
case, by construction, so mapping `errSecDuplicateItem` to `.twinnedRecord` in this method makes the
answer honest whether the pair was there at the count or arrived after it. That does not close the
race and does close the misleading advice.

## S1-39 (low): the Keychain half of `SecretStoreTests` still runs nowhere

Numbered so it can be tracked. This is the remainder disclosed when S1-37 was fixed, not a new
discovery, and all three engines describe it identically.

`StoreUnderTest` is now a one-case list, so fifteen `SecretStoreTests` cases run against the
in-memory store only. The probe that used to narrow it silently is gone and the file says plainly
that the Keychain half is not covered anywhere.

**ChatGPT scores S1-37 "not fully fixed" on this**, which is a labelling difference rather than a
disagreement: it also confirms the twenty six moved tests now run unconditionally in a job that
executes, and that the CI rule cannot detect this shape. Fable's phrasing is the one worth keeping:
a probe that silently narrowed has become **a stated list that admits its limit**, which converts
hidden non-coverage into recorded non-coverage.

## S1-40 (low, contested): the disable path can still move accounts before the refusal

Disclosed in the brief. All three name it and they score it differently.

`precheckConversion()` succeeds, a second record arrives, the accounts convert to local, and the
wrapped store's own count then finds the pair and refuses. **The accounts have moved while the
preference still reads on**, which is the state S1-28 was filed about, reached through an arrival
rather than a pre-existing pair.

- **ChatGPT**: this reproduces the filed inconsistency, so S1-28 is not fixed.
- **Fable**: the class is closed and what remains is the API's concurrency floor. Its framing is
  the most useful thing in the round: the finding has gone from **"any pre-existing pair,
  permanently, with wrong advice"** to **"an arrival landing inside one conversion span, once,
  honestly labelled, with retries refusing safely"**.
- **Grok**: not the filed path, and it does not restore the retry loop.

**No cheaper construction exists**, and Fable says why: the Keychain offers no transaction spanning
two stores. Closing it would need the accounts conversion and the wrapped conversion to be one
atomic operation, which the platform does not provide.

## What was confirmed

**S1-37's mechanics, by all three.** Both files are genuine renames with the gate line removed and
nothing else touched; the probe file itself is deleted, so nothing is left to skip on; the hosted job
runs the target they now live in; and the count checks out at fifteen plus eleven. Fable verified
target membership is by the project's synchronised folder groups, the same mechanism that carried
every test file added in prior rounds into jobs that demonstrably ran.

**No cross-suite interference**, checked by all three: both moved suites isolate every case behind
UUID-suffixed service names and temp directories, which is the convention the existing hosted suites
already follow.

**The move strengthens rather than weakens what they assert**, which I had not considered. Fable's
point: protection-class assertions now run against a Keychain that actually implements protection
classes, where the never-reached macOS path could not have honoured them.

**The CI rule is the right rule and not too blunt**, unanimously. Fable's reason: it follows this
CI's own idiom, where every absence check is a deliberate barrier with a documented override, and
the override here shifts the burden to proving execution, **which is the burden this finding existed
to impose**.

**The method reads coherently after five consecutive changes**, which was the surface I was least
sure of. Fable calls it the cleanest the method has been: four orthogonal stages in stated order,
repair, refuse-if-ambiguous, move, report, with each stage's position carrying its own argument. It
also confirms the reordering cannot invalidate the guard, **because the repair touches no
primary-key attribute and therefore cannot change the count the guard reads**.

**The new tests do not re-admit the agree-with-the-code shape.** All three assert named errors, which
is the S1-36 lesson holding, and the disable test pins the accounts-untouched property that is the
heart of the finding.

## Where the gate stands

**No high, no medium. Five lows and one waiver.**

| Item | Scope | What it is |
| --- | --- | --- |
| S1-34 | 1 | the seam can express the same-slot case and no test does |
| S1-38 | 1 | a twin forming between the count and the update collides and is reported as `.duplicate` |
| S1-39 | 1 | the Keychain half of `SecretStoreTests` runs nowhere |
| S1-40 | 1 | contested: the disable path can move accounts before the refusal, on an arrival |
| S4-45 | 4 | five false claims left |
| S1-33 | 1 | **waived**, with its reasoning and what would reopen it |

**S1-38 is the only one of these with a clean cheap fix**, and it is a one-line mapping rather than
a race to close.

## What was done: S1-38, and S1-40 waived

### S1-38: the collision is named for what it is

A collision at that update **is** the twin case, by construction: the update moves one record into
the opposite slot, and the only way that slot is occupied is by a second record. So
`errSecDuplicateItem` there is evidence of a pair rather than a separate kind of failure, and it now
throws `.twinnedRecord`.

**The race is not closed and cannot be by this shape**, because a count and an update are two calls.
What is closed is answering it with the wrong name, which is what sent a person the retry advice
this method exists to stop.

**The test was red for the wrong reason twice before it was right.** `beforeWrite` fires inside the
repair loop, which only runs for a record whose pair disagrees, so a test planting a correctly
paired record never fired the seam at all: the conversion simply succeeded, and the assertion failed
identically before and after the fix. The seam now also fires between the count and the update,
which is the gap this finding is about, and the test discriminates: removing the mapping reddens it.

**That is the fourth test this week that did not discriminate on its first writing.** The pattern is
consistent enough to name: each time, the seam or the side effect was placed somewhere the code
under test does not reach on the path being exercised. Running the mutation is what caught all four.

### S1-40 is waived

**Decision: recorded, not fixed.** The disable path can still move accounts before the wrapped
record refuses, when a second record arrives after `precheckConversion` has already passed.

**Why it is not being fixed.** Closing it needs the accounts conversion and the wrapped conversion
to be one atomic operation, and **the Keychain offers no transaction spanning two stores.** No
cheaper construction exists, and both engines that examined it reached that independently.

**What it costs, stated rather than minimised.** The accounts are local, the preference still reads
on, and the switch overstates protection until the next attempt. The next attempt refuses before
moving anything, so it is one span rather than a loop, and the message is now honest.

**What changed about it, which is the reason to accept it.** The finding has gone from *any
pre-existing pair, permanently, with wrong advice* to *an arrival landing inside one conversion
span, once, honestly labelled, with retries refusing safely*. The class is closed; what remains is
the platform's floor.

**What would reopen it.** A Keychain transaction spanning two services, or a redesign that puts the
wrapped record and the accounts under one primary key. Neither is contemplated.

**What accepting it does not mean.** It is a shipping decision, not a statement that the window is
safe, and it is not the same as the toggle being trustworthy under twins. For the length of one
conversion span the switch can say something that is not true about where accounts are. That is
accepted because no cheaper construction exists on this platform, not because it stopped being
true.

## Correction: S1-37 was not real, and the fix for it removed coverage

**Measured, after the fact, and the measurement should have come first.**

S1-37 said twenty six tests executed in no job and on no machine. **They executed in the hosted job
all along.** The `OpenFactorTests` target's `fileSystemSynchronizedGroups` lists **both**
`OpenFactorTests` and `Tests/OpenFactorCoreTests`, so every file in the package test directory
compiles into the hosted bundle too. In a simulator the Keychain probe returns true, so both suites
were enabled and ran.

Run at `2196b97`, the commit before the fix: **26 executions of `VaultTests` and
`KeychainSecretStoreTests`.** Not zero.

### How the wrong conclusion was reached

Two true facts and an unchecked inference. `swift test` skips them: verified. The hosted job passes
`-only-testing:OpenFactorTests`: verified. **Target membership was never checked**, and the returns'
phrasing, that the job "runs only the app target so they were never in it", was repeated rather than
tested.

**This is the same error E12 exists to warn about**, one layer down. There, a claim that a platform
API could not do something was checked by running it, and it was false. Here, a claim about a build
system was not checked, and it was false. The lesson did not transfer because it was filed as being
about the Keychain rather than about claims in general.

### What the fix cost

`StoreUnderTest` used the same probe to decide which stores `SecretStoreTests` runs against. In the
hosted target the probe returned true, so it ran **both**. Removing it narrowed the list to the in
memory store and **silently dropped fifteen Keychain executions from the hosted run**:

| | Before | After the fix | Now |
| --- | --- | --- | --- |
| `SecretStoreTests` executions | 30 | 15 | 30 |
| `VaultTests` and `KeychainSecretStoreTests` | 26 | 26 | 26 |

So **S1-39, filed as a finding, was created by that change rather than discovered.** Before it, the
Keychain half ran.

### What was put back, and what was kept

**The probe is restored**, with its purpose stated: this file compiles into two targets, and the
probe is what distinguishes an unsigned package run from a hosted one. That is the behaviour that
was wanted all along.

**The CI rule is removed.** Its justification was the false finding, and it banned one shape of
conditionality while the same idea legitimately lives in another shape two directories away. A rule
whose stated reason is untrue should not be kept because it sounds prudent.

**The two suites stay where they were moved**, ungated. `swift test` no longer compiles them, so
they need no gate, and nothing is lost: they run in the hosted job as they always did.

### The record

S1-37 is **withdrawn as a finding**. S1-39 is **withdrawn**: it described a state this work
created. The commit message of `f75ce5b` and the CI comment it added both contain the false
account; this section is the correction, and the code no longer carries the claim.

## What was done: S1-34 and S4-45

### S1-34: the waived behaviour is now executable

`aSameSlotSubstitutionIsOverwritten` uses the seam to replace the observed record's bytes **in the
same slot, under the same flag**, between `save` reading and writing, and asserts that the write
lands on content it never examined.

**It asserts the current behaviour, not the desired one.** That is the point: S1-33 was waived in
prose, and prose does not fail when something changes. If this test ever goes red, the waived answer
has moved and **the waiver needs revisiting rather than the test needing fixing**, which the comment
says in as many words.

### S4-45: four corrected, two left alone because they had come true

**Each of the six was re-read against the code rather than against the list.** That mattered: two no
longer needed changing.

Corrected:

- `InboxOpener` said a stale item is left for the stale sweep. It is superseded here, and the
  paragraph below it already explained why: everything the call read is at least as old as the
  newest, so if the newest is stale they all are.
- `OpenFactorApp` and `AddAccountSession` both still described App Lock as swapping the root or
  unmounting the view tree. **This is the third and fourth sentence of that family**, after two were
  corrected in round four and a fifth was found later. Both now say what the design says: a locked
  cold launch rebuilds the tree beneath, a warm lock is a window above a tree that survives, and
  neither flips `isPresented`.
- `agesAreReadPerFile` was named for a race it does not express, since nothing is written while its
  sweep runs. It is now named for what it asserts, and its comment points at
  `aShareLandingDuringASweepSurvives`, which is the test that does express it and did not exist when
  the name was written.

Left alone, with the reason recorded:

- `InboxOpener`'s claim that `take` removes the item it refused **is true now**. It was false only
  for a directory, and S4-42 stopped a directory from becoming a candidate.
- `sweepLeavesWhatArrivedLater` is named "Superseding leaves what arrived after the caller looked",
  and the test writes after `pending()` and before `sweep`. **That is exactly what the name says**,
  so it was reported as overstating and is not.

That is two of the round's items that resolved themselves through code changes made for other
findings, which is worth noting: **a false claim can be retired by making it true.**

457 package tests pass, the hosted suite passes, both targets build.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Grok:
Commit: c4360dd (S1-28). S1-37 landed in f75ce5b. Both filed in A4-verify-S1-36-S1-32-S4-43-results.md.

Answers

┌─────────────────────┬────────┐
│                     │ Fixed? │
├─────────────────────┼────────┤
│ S1-37               │ Yes    │
├─────────────────────┼────────┤
│ S1-28               │ Yes    │
├─────────────────────┼────────┤
│ New high or medium? │ No     │
└─────────────────────┴────────┘

S1-37

VaultTests and KeychainSecretStoreTests live under OpenFactorTests/. The @Suite attributes have no .enabled(if:). The hosted job still runs -only-testing:OpenFactorTests, so those twenty six cases are in that job. git grep of enabled(if: under Tests/ and OpenFactorTests/ finds nothing in Swift. Package swift test no longer contains those files.

The CI rule matches the failure: a suite that decides at run time can skip everywhere and still report success. Banning the feature in the two test trees is the right default. The job comment already says the way out is to prove where a conditional suite runs and change the check on purpose. That is blunt on purpose, not too blunt.

The remaining half is as recorded: StoreUnderTest is now a one-case list (inMemory), and SecretStoreTests against Keychain still does not run. The new rule would not have caught a silent empty list either. That does not put the twenty six back in the dark.

They isolate Keychain items with a fresh UUID service (and vault keys in a temp directory). Sharing a simulator process with the rest of OpenFactorTests does not weaken those assertions unless a test stops using its own service, which these do not.

S1-28

setSynchronizable repairs, then guard countingBothFlags() <= 1 else { throw .twinnedRecord }, then the move. Existing twins never reach SecItemUpdate, so they never become .duplicate and “try again.” SyncAwareKeychainStore.setSynchronizable calls precheckConversion() before either direction, so disable does not convert accounts when the wrap already cannot move. Settings only writes syncEnabled after that returns, and message(for:) uses twinnedRecord’s own sentence.

The method as a whole is coherent: pair the class, refuse if the move cannot succeed, then move. Repair stays above the refuse so a stranded twin is still corrected on the failing call (twinsAreRepairedEvenWhenConversionRefuses).

The second countingBothFlags is for a pair that already exists. A pair that forms between pre-flight and the wrap write is a different window. On enable, wrap conversion runs first and its own guard still throws before accounts move. On disable, accounts could move in that gap; then wrap conversion throws twinnedRecord rather than colliding. That is not the filed path, and it does not restore the try-again loop.

Reconcile still calls wrapped.setSynchronizable(true) with try?. It never converts accounts. Twins there are a swallowed refuse, not a collision.

New high or medium

No. The pre-flight does not change wrap bytes. The suite move does not share production service names.

Fable:
Verification: S1-37 and S1-28 — commit c4360dd (S1-37 landed in f75ce5b)
Question 1: is each item fixed?
S1-37 — yes, for the item as filed, with its disclosed remainder correctly recorded rather than closed. The evidence chain: both files are genuine renames into `OpenFactorTests` (98% similarity, gate line removed, nothing else touched in the suites), the hosted CI job runs `-only-testing:OpenFactorTests` on a simulator where a data-protection Keychain always exists, and `KeychainAvailability.swift` — the probe itself — is deleted, so nothing is left to skip on. The count checks out: 15 `@Test` functions in `KeychainSecretStoreTests` plus 11 in `VaultTests` is the twenty six. Target membership is by the project's synchronized folder groups (no per-file `pbxproj` entries; the same mechanism carried every test file added in prior rounds into jobs that demonstrably ran), and `@testable import OpenFactorCore` from the hosted bundle is the established, working pattern of `WrappedKeySyncTests`. Is the CI rule the right rule? Yes, for the failure it names: `enabled(if:)` is precisely the run-time-decision shape that let twenty six tests impersonate coverage, the grep covers both test directories, and — answering the bluntness surface — it is not too blunt, because it follows this CI's own idiom: every absence check in that file is a deliberate barrier with a documented override ("prove where it runs before adding it back, and change this check deliberately"), which is the correct answer to the first legitimate conditional suite: the burden shifts to proving execution, which is exactly the burden this finding existed to impose. The rule's known blind spot — list-based selection, the `StoreUnderTest` shape — is disclosed in the brief, stated in the file itself in plain words ("the Keychain half of `SecretStoreTests` is not covered anywhere"), and filed as the remaining half; a probe that silently narrowed has become a stated list that admits its limit, which converts hidden non-coverage into recorded non-coverage, and that is the fix's honest boundary.
S1-28 — yes. The three changes compose into a complete answer to the finding as filed. `setSynchronizable` now refuses a twin pair by name before the move runs, so the collision that produced `errSecDuplicateItem` — a single record flipping into an empty opposite slot cannot collide — is unreachable outside the microsecond arrival race this gate has consistently accepted and named. `precheckConversion()` runs before either direction in `SyncAwareKeychainStore`, so on the disable path the accounts no longer begin converting when a pair already exists — the state the finding was about. And `message(for:)` passes `twinnedRecord`'s own sentence through, so the failure that remains reachable is honestly worded instead of advising a retry that fails identically forever; on the next attempt the pre-flight refuses before anything moves, which also breaks the retry loop. Remaining paths, checked: the reconcile calls the wrapped store directly without the pre-flight, but converts nothing and commits nothing, and under twins it now gets the repair (which still runs first) plus a swallowed named refusal — correct. The one residual is the disclosed TOCTOU: a pair forming during the accounts conversion on the disable path still produces the partial state, now with the honest message. That residual is the accepted arrival-race class, shrunk from "any pre-existing pair, permanently, with wrong advice" to "an arrival landing inside one conversion span, once, honestly labeled, with retries refusing safely" — the class is closed and what remains is the API's concurrency floor.
Question 2: does either change introduce a new high or medium?
No. The four surfaces:

* The method read whole, after five consecutive changes: it is not incoherent — it is the cleanest this method has been. It now reads as four orthogonal stages in stated order: repair (twin-safe, per-record, primary-key-untouched — the new doc sentence is accurate), refuse-if-ambiguous, move (writing flag and class as one `forSync` pair), report. Each stage's position carries its argument, and the one reordering this commit made — repair hoisted from below the move to the top — strengthens the S1-31 property rather than disturbing it: the repair now precedes both the refusal and the move on every call, which the new test pins (`twinsAreRepairedEvenWhenConversionRefuses`, premise asserted, named error, class read back). The repair cannot change the count the guard reads (it touches no primary-key attribute), so the stages cannot invalidate each other.
* The pre-flight as a second opinion: the gap between `precheckConversion` and the wrapped move does not matter for what the pre-flight exists to do. Its job is ordering — refusing before the accounts move — and a pair present at decision time is now caught before any write on both directions. A pair forming after the check is the same arrival race that every write in this store already carries, its consequence is the visible, named, retry-safe partial state rather than a silent or looping one, and no cheaper construction exists: the Keychain offers no transaction spanning two stores.
* The suites' new home: nothing about the move weakens what they assert — it strengthens it, since protection-class assertions now run against a Keychain that actually implements protection classes, where the old (never-reached) macOS target could not have honored them. Cross-suite interference through the shared simulator Keychain is prevented by construction: both moved suites isolate every test behind `UUID`-suffixed service names and `UUID`-suffixed temp directories, so parallel hosted suites cannot see each other's items, and the existing hosted suites already follow the identical convention.
* The CI rule: answered under question 1 — right rule, documented override, disclosed blind spot filed rather than hidden.

The new tests deserve their sentence: all three assert the named error (the S1-36 lesson held), the disable-direction test pins the accounts-untouched property that is the heart of the finding, and the refusal test asserts both records survive by count — nothing here re-admits the agree-with-the-code shape.
Verdicts: S1-37 fixed (with its stated remainder filed, not hidden); S1-28 fixed; no new high or medium introduced.

GPT:
Finding	Verdict
S1-37	Not fully fixed
S1-28	Not fixed
New high or medium	No


S1-37: The 26 moved tests are now unconditional members of OpenFactorTests, and CI runs that target. Their UUID-scoped services and vault directories prevent shared-process Keychain interference. The CI ban is reasonable; any legitimate conditional suite should receive a narrow exception only after a CI job is shown to execute its enabled branch.
However, StoreUnderTest.testable now contains only .inMemory, so the Keychain half of the 15 SecretStoreTests cases still executes nowhere, and the CI rule cannot detect that form of conditional coverage. The stated “remaining half of S1-37” therefore remains.
S1-28: Existing twins are correctly repaired and then refused as .twinnedRecord, but two races remain:
On disable: precheckConversion() succeeds → a second record arrives → accounts move local → the wrapped store’s later count finds twins and refuses. The accounts have already moved while the preference remains enabled, reproducing the filed inconsistency.
A twin arriving after setSynchronizable’s own count but before SecItemUpdate can still make the update collide and return .duplicate rather than refusing by name.
The repair-first placement is otherwise coherent and correct under twins. These are incomplete closures of the existing low findings, not newly introduced high- or medium-severity regressions.
No build or tests were run, and the worktree remains clean.
