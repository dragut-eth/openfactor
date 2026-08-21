# A4 round five, scope 1: a mechanism removed, and a write that now refuses

**The code under review is `b3e7e08`.** Round four read `a90dd70`, round three `29d62e7`, round two
`46f65a3`, round one `74fe841`. Every prior round's results are in `docs/audits/`, with all three
returns in full.

**Files:** as the scope 1 list in `A4-prompts.md`, plus
`Sources/OpenFactorCore/Vault/WrappedRecordStore.swift`,
`Sources/OpenFactorCore/SecretStoreError.swift`, `OpenFactor/Vault/VaultGateModel.swift`,
`OpenFactor/AccountListViewModel.swift`, `OpenFactor/OpenFactorApp.swift`,
`Tests/OpenFactorCoreTests/VaultDecisionTests.swift`,
`Tests/OpenFactorCoreTests/InMemoryWrappedStore.swift`, and
`OpenFactorTests/WrappedKeySyncTests.swift`.

Read-only. Do not build and do not run the test suite; keep the checkout clean.

## Scoring

A finding that lives only in a comment or a document is recorded but does not hold the scope open.
Report false claims; do not treat hunting them as the job.

## What this round is

**Round four returned a high, all three of you found it independently, and it was this gate's own
fix that introduced it.** The full account is in `A4-round-four-scope1-results.md`. In short:
`unlock` tried every wrapped record, which was right, and then deleted the records the passphrase
did not open, on the premise that opening one proved the others dead. Nothing in OFK1 binds a wrap
to the account ciphertext, so it proved no such thing, and in the twin state both records are
usually live vaults' only recovery credentials.

**This round reviews the removal of that mechanism, and two writes that now refuse rather than
guess.** Removal is an unusual shape for a fix and deserves its own suspicion: the question is not
only whether the deletion is gone, but what the absence leaves behind.

## What changed

**`unlock` deletes nothing, and `discard(_:)` no longer exists** on `WrappedRecordStore`, on
`WrappedKeyStore`, or on the fake. The protocol states that there is no remove operation on
purpose. That closes S1-20 with it, since a flag-keyed delete cannot take the wrong record when
there is no delete.

**Attack the absence.** A twin pair now persists forever, costing one extra PBKDF2 derivation per
unlock. Say whether anything else accumulates: whether two records can become three, whether any
path still writes a second record while one exists, whether the permanent pair degrades anything
beyond the derivation, and whether a person in this state has any route out of it at all. If the
answer is that they do not, say whether that is acceptable or whether it needs a route that has
evidence behind it.

**Grok's remedy was taken over Fable's narrower one.** Fable proposed discarding only losers that
failed as `notAWrappedKey` or `iterationsOutOfRange`, bytes provably nobody's recovery record. That
was declined because the only delete primitive available identified a record by its sync flag, so
iCloud writing into that slot between the read and the delete would remove a record nobody
examined. **Say if you think that was the wrong call.**

**`save` refuses a twin pair**, throwing the new `SecretStoreError.twinnedRecord`, because a
replacement through a one-item match updates whichever record it finds, which is the same
destruction as the discard through a door that needs no unlock. Attack the refusal: a person whose
Keychain holds a twin pair can now never change their vault passphrase, and the only path out is a
state nothing in the app resolves. Is refusing right, and is the error's message honest about what
it costs?

**`WrappedKeyStore.synchronizable` became a question asked at each write** rather than a `Bool`
captured at launch, closing S1-14. Check the shape against `ProvisioningDesk.Conditions.hasVault`,
which is the same pattern, and say whether asking at write time introduces anything: a preference
read on a background thread, an ordering that differs from the accounts store's, or a write and a
conversion disagreeing.

**A code that fails to generate now signals the gate**, closing S1-17. `AccountListViewModel`
reports the transition into failure once per failure, and the app calls `gate.refresh()`.
**This is a new call path from the list back into the gate that owns it.** Attack it: re-entrancy,
a refresh during a tick, a loop between a gate that reopens the list and a list that signals again,
and whether one permanently broken account among working ones can drive it.

**The reconcile now runs only when the scene becomes active**, not on every phase change.

## Three things handed over rather than left to be found

**The removal could not be mutation tested the way a guard can.** There is no line to revert,
because the API is gone. The regression test asserts the property instead: two live wraps, unlock
with each passphrase in turn, both records survive both times. Say whether that is sufficient
evidence for a fix of this shape.

**The fake was changed in the same commit as the code it fakes.** `InMemoryWrappedStore.save` now
refuses a twin pair, mirroring the adapter. Round four's finding was that this fake agreed with the
code by construction, so **a fake edited alongside the code is exactly the shape that produced that
finding.** Check whether the fake now models the adapter or merely agrees with it again.

**The hosted tests are new and were written by the same hand as the fix.**
`WrappedKeySyncTests` gained three tests running against the real Keychain: `candidates()` under a
planted twin, the save refusal, and the write-time preference. The refusal was mutation tested
there and reddens when the guard is removed. The other two were not. Say whether they test the
adapter or describe it.

## What to answer

1. **Does each change address the finding it claims to?** A fix that moves a check without
   changing what is checked, or that handles the case while leaving the class open, is a finding.

2. **Did any change introduce something new?** Round four's answer was a high, produced by round
   three's fix. Assume this round did too and go looking. The new surfaces are the permanent twin
   pair, the refusing write, and the list-to-gate signal.

3. **Do the new tests test the code, or agree with it?** This scope has now had two rounds where
   the answer was "agree", and both times the test had been written alongside the fix by its
   author. The three items handed over above are where to look first.

4. **Is this converging?** Round four's verdict was that everything previously found had converged
   and the regression was in new ambition. Say where it stands now, and say plainly if the answer
   is that removing the mechanism has left the scope somewhere worse than before it was added.

5. **The recovery question, answered directly.** Walk the twin state end to end at this commit.
   Two devices, one Apple Account, two wraps, both vaults live. What can the owner do, what can
   they not do, and is anything they hold now unrecoverable that was recoverable before this
   commit or after it?

You are not bound by any previous round's conclusion, including your own. This gate has had a
reviewer retract its own finding, has rejected fixes that came with passing tests written by
whoever wrote the fix, and has just removed a mechanism it shipped two rounds earlier because all
three of you rejected its premise. **Saying that an earlier conclusion was wrong is in scope.**
