# A4 verification: S1-37 and S1-28

**This is not a review round.** Two closed questions and nothing else. Do not report low-severity
findings beyond answering them. Do not review anything outside these two items. **A thin answer is
the correct answer**, and one that says what was checked in order to conclude nothing is worth more
than one that manufactures a finding.

**Sent to all three, and one of the two items is the reason.** S1-37 changed what the test suite
*is*. Every other verdict in this gate rests on evidence from that suite, so if the topology is
wrong the evidence base for everything else is affected. That is a different kind of claim from
"this function behaves correctly".

**The code under review is `c4360dd`.** S1-37 landed in `f75ce5b` and S1-28 in `c4360dd`. Both were
filed in `A4-verify-S1-36-S1-32-S4-43-results.md`, which also carries the returns that produced
them. The seven previous verification rounds are in the same directory.

Read-only. Do not build and do not run tests; keep the checkout clean.

**Already decided, so do not report:** S1-33 is waived, with reasoning at the end of
`A4-verify-S1-31-results.md`. S1-34 and S4-45 are open and filed.

## S1-37, as filed

`KeychainSecretStoreTests` and `VaultTests` were gated on a run-time Keychain probe. The unsigned
package host has no Keychain, so `swift test` skipped them; the hosted CI job runs
`-only-testing:OpenFactorTests`, so they were never in it. **Twenty six tests executed in no job and
on no machine while looking exactly like coverage**, and one of the two covers the accounts store.

This is the shape of this gate's founding finding: `VaultTests` never running is what produced
`WrappedRecordStore` and `VaultDecisionTests`.

**What was changed.** Both suites moved to the hosted target, where a simulator always has a real
Keychain, and the run-time gate was removed rather than made conditional on something else. All
twenty six execute and pass. CI now refuses `enabled(if:)` in either test directory.

**What was found while doing it, and deliberately not closed.** `StoreUnderTest` used the same probe
to choose which stores `SecretStoreTests` runs against, so **its Keychain half has also never run**
while the suite reported success for fifteen cases. The probe is gone and the list is now stated
rather than decided, so the file says plainly that only the in memory store is covered. Moving that
suite needs helpers the package's own tests depend on. It is recorded as the remaining half of
S1-37. **The new CI rule does not catch that shape.**

## S1-28, as filed

With two records, one under each flag, moving the one on this side to the other collides with the
record already there. `SecItemUpdate` returned `errSecDuplicateItem`, the store reported
`.duplicate`, and Settings rendered that as advice to try again, which failed identically every
time. `twinnedRecord`, the honest answer, existed with nothing throwing it.

On the disable direction the accounts convert first, so the collision arrived with every account
already local while the preference, which flips only on success, still read on: the switch claiming
iCloud held accounts it did not.

**What was changed.** Three things. `setSynchronizable` refuses a twin pair by name.
`SyncAwareKeychainStore` calls a new `precheckConversion()` before either direction, so nothing
moves until the wrapped record is known to be able to move. `message(for:)` passes `twinnedRecord`'s
own sentence through.

**The refusal sits below the class repair, deliberately.** The S1-31 verification established that
the repair runs even on a call that then fails, and that it is correct under twins because each
update is pinned to one record's own flag and changes no primary-key attribute. Above the repair, a
stranded record in a pair would stay wrong on every call that refuses, which is every call.

## The two questions

**1. Is each item fixed? Yes or no, for each of S1-37 and S1-28.** If no, one sentence on what
remains.

For S1-37: do the twenty six tests genuinely execute in a job that runs, and is the CI rule the
right rule for the failure it is meant to prevent? For S1-28: is there any remaining path on which
the toggle collides rather than refusing, or on which accounts move before the wrapped record is
known to be able to?

**2. Does either change introduce a new high or medium?** Yes or no. If yes, name it and give the
call order.

The surfaces where the author is least confident:

- **This is the fifth consecutive change to `setSynchronizable`**: the repair inside it, the repair
  failing closed, the twin guard, the guard's position relative to the repair, and the pre-flight in
  its caller. Read the method as a whole rather than as a diff, and say whether the accumulation has
  produced something incoherent even if each step was right.
- **The pre-flight is a second opinion about the same condition.** `precheckConversion` and
  `setSynchronizable` both check `countingBothFlags`, so a pair forming between them is not caught
  by the pre-flight. Say whether that matters, given the pre-flight exists to protect the accounts
  rather than the record.
- **Two suites changed target.** They now build against the app rather than the package, run in a
  simulator, and share a process with every other hosted test. Say whether anything about them is
  now different in a way that weakens what they assert, and in particular whether any of them can
  now interfere with another suite through the shared Keychain.
- **The CI rule bans a language feature outright.** Say if that is too blunt, and what should happen
  the first time somebody has a legitimate reason for a conditional suite.

Nothing else is in scope. Two answers and their reasoning is the whole deliverable.
