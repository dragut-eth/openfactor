# A4 verification: the last three, answered

Reviewed commit: `f7361bf`. The brief is `A4-verify-final.md`.

## The answers

| Engine | Correction right? | S1-38 | S1-34 | S4-45 | New high or medium? |
| --- | --- | --- | --- | --- | --- |
| ChatGPT | Yes | Fixed | Fixed | **Not fixed** | No |
| Fable | Yes | Fixed | Fixed | Fixed | No |
| Grok | Yes | Fixed | Fixed | Fixed | No |

**The correction is unanimously confirmed**, S1-38 and S1-34 are unanimously fixed, and **S4-45 is
not**, because the engine in the minority is right.

## Question zero: the correction stands, and one engine went further than asked

All three verified it independently rather than accepting it a second time.

**Fable traced the topology to its origin.** The `OpenFactorCoreTests` synchronized group has been
listed in the `OpenFactorTests` target since `da0d4fb`, **the commit that added the Xcode project at
gate A1**. So the package test directory has compiled into the hosted bundle for the project's
entire Xcode history, which makes twenty six executions the expected result rather than an anomaly.

**Grok names the failure precisely**: `swift test` skipping them is true, the job flag is true, and
**the membership inference was the false step.**

**Fable also audited how it came to verify a false finding**, unprompted, and found worse than a
missed check: the refuting evidence had passed through its hands twice, including a premise its own
round two analysis had relied on. Its sentence is the one to keep: **a premise that contradicted its
own established facts arrived wearing a results table**, and it checked the half that was checkable
by reading and inherited the half that needed the build system.

## S4-45 is not fixed, and the reason repeats today's lesson

**ChatGPT alone is right.** I verified the mechanism.

The claim left alone was that `take` removes the item it refused. Fable and Grok both cleared it
with the same reasoning: a directory was the only case it did not remove, and `pending` now requires
a regular file, so a directory can never be a candidate.

**That answers admission, not use.** The sequence:

1. `pending` stats the entry and admits it as a regular file.
2. A sibling replaces it with a directory under the same name.
3. `take` calls `openat`, which **succeeds on a directory**, and `BoundedFile` then refuses it
   because `fstat` says it is not regular.
4. The deferred `unlinkat` without `AT_REMOVEDIR` **cannot remove a directory**, and fails silently.

So the item it refused stays. **The consequence is accumulation, which S4-42 already accepted**, so
what is wrong is the sentence rather than the code.

**Three people made the same error on the same claim in one day.** I left the sentence alone by
checking what can be admitted and inferring what can be present at use. Fable and Grok cleared it
the same way. This morning I checked which jobs run a suite and inferred where it executes. **A
static check standing in for a dynamic one**, four times, across two engines and me, in a single
session.

Fable's is the sharpest instance: it wrote the most rigorous self-correction in the whole gate about
inheriting an unchecked premise, **and made the same class of error one section later in the same
document.** That is the argument that this is a habit rather than a knowledge gap.

## The App Lock family, and the structural answer

**Three sentences remain wrong**, per Fable and Grok, who enumerate the same three:
`VaultGateView.swift:23`, `VAULT.md:514`, and `UI_SPEC.md:48`. ChatGPT named the first. All three
still describe the warm lock as a root replacement that destroys state, while `docs/APP_LOCK.md`
states the mechanism correctly: a locked cold launch builds the lock as root and rebuilds the tree
when it clears, and a warm lock is a window above a tree that is not torn down.

**Nine sentences across six files, three correction passes, three still wrong**, including a pass
that was itself about these sentences.

All three reach the same remedy and Fable states it best: **every correction has been a partial
sweep of an unenumerated set.** `APP_LOCK.md` is already the correct single description; each
dependent file should keep only its local consequence and a pointer. **The same move, for the same
reason, as `forSync`.**

## What was confirmed

**S1-38's load-bearing claim, argued rather than asserted.** Fable and Grok independently: the
update's change dictionary mutates exactly one primary-key attribute, the sync flag;
`errSecDuplicateItem` at a `SecItemUpdate` signals only a primary-key conflict; therefore a
collision means the destination slot is occupied, which with this store's single account name means
a second record. **A pair, by construction, whenever it arrived.** Fable adds that a cross-group
record cannot produce it, because the access group is part of the key a collision must match.

**The seam is `nil` on every shipping path**, enumerated by both: three fire sites, the public
initialiser sets it explicitly, the internal initialiser is unreachable across the module boundary,
and every non-nil closure in the tree is a test.

**Pinning a waived behaviour is right, and is the opposite of entrenchment.** Fable's argument, which
answers the surface better than the brief asked it: entrenchment would be asserting the behaviour as
*desired*; this asserts it as *factual*, so the waiver's premise becomes executable and cannot
silently drift. **The discomfort stays in the waiver; the test only guarantees the record stays
true.**

**`sweepLeavesWhatArrivedLater` was correctly left alone**, confirmed by both: it snapshots, writes
after the snapshot, sweeps the snapshot, and asserts the later arrival is the sole survivor. The
name is exact.

## Where the gate stands

**No high, no medium. One low open.**

| Item | State |
| --- | --- |
| S4-45 | **open**: the `take` sentence is false for a swapped entry, and three App Lock sentences remain |
| S1-33 | waived, with what would reopen it |
| S1-40 | waived, with what would reopen it |
| S1-37, S1-39 | withdrawn, and the withdrawal is unanimously confirmed |

The remaining work is prose plus one structural decision: whether to correct three more sentences or
to collapse the family to one description with pointers, which all three engines recommend.

## What was done: S4-45, closed by collapsing the family

### The `take` sentence

Corrected rather than deleted, and it now names the case that makes it false: an entry that was a
regular file when `pending` looked and a directory by the time `take` opened it. `unlinkat` cannot
remove that, so it accumulates, **which is the cost S4-42 already accepted**, and it cannot be
collected either.

### The App Lock family, collapsed

**Enumerated first**, because the diagnosis was that every previous correction had been a partial
sweep of a set nobody had listed. One grep across both file types found the whole family: nine
sentences in six files, plus the correct description in `docs/APP_LOCK.md` and the implementation's
own comments in `OpenFactor/Lock/`.

**`docs/APP_LOCK.md` is now the only description**, and says so in a section of its own that records
why: nine sentences, six files, three passes, three still wrong afterwards. Its historical section is
marked historical, since it describes the arrangement that preceded the current one in the present
tense and had become false on its own.

**Every dependent file keeps its local consequence and a pointer.** `VaultGateView`, `docs/VAULT.md`
and `docs/UI_SPEC.md` were the three still wrong. `OpenFactorApp` and `AddAccountSession` were
already correct after an earlier pass but still re-described the mechanism, so they were shortened
too: **a correct restatement is still a restatement, and the next change to the mechanism would have
left them wrong again.** `HANDOFF.md`'s account of the two field bugs is history and now reads as
history.

**The files under `OpenFactor/Lock/` keep their descriptions**, because they are the mechanism
rather than dependents of it.

**This is the same move as `forSync`**, for the same reason and after the same symptom: a rule
restated at five sites drifted at two of them, and a mechanism restated at six drifted at three.

Verified by re-running the enumeration afterwards: no description of the mechanism survives outside
its home and its implementation.

457 package tests pass, the hosted suite passes, both targets build.

## Where the gate stands now

**No high, no medium, no low open.** Two waivers with their reasons, two withdrawals confirmed
unanimously.

What remains of A4 is the closing opinions: each engine reads its own published passes in a fresh
conversation and writes a short opinion for `README.md`, unflattering parts included.
