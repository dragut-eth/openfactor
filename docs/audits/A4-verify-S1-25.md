# A4 verification: S1-25, with S1-27

**This is not a review round.** Two closed questions and nothing else. Do not report low-severity
findings. Do not review anything outside these two items. **A thin answer is the correct answer**,
and one that says what was checked in order to conclude nothing is worth more than one that
manufactures a finding.

Both are here together because the fix for the medium requires the line the low is about, and
separating them would have meant knowingly leaving a defect in a line being rewritten.

**The code under review is `07e2972`.** Both findings were filed against `b3e7e08` and are written
up in `A4-round-five-scope1-results.md`, which carries all three round five returns in full. The two
previous verification rounds are `A4-verify-S4-41-results.md` and
`A4-verify-S4-42-S4-44-results.md`.

Read-only. Do not build and do not run tests; keep the checkout clean.

## The question two of you said the code could not answer, answered

Both returns that filed S1-25 said the incompatible add would either be **refused** or **accepted**,
that both outcomes were defects, and that the code could not tell you which.

**It is accepted.** A hosted test reading the attribute back off the real Keychain reported the
stored class as `"aku"`, which is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, on an item written
with `kSecAttrSynchronizable = true`.

So the flag said leave and the class said stay. Nothing synced, while every account did, which is
S1-1. And `syncReport` reads the flag rather than the class, so the one readout that exists to make
this visible would have reported the record as synced. `theFlagIsAskedAtWriteTime` stayed green
throughout, exactly as one of the returns predicted.

**Verify that finding rather than taking it from this brief.** If the reasoning above is wrong
about what was stored, everything below rests on it.

## What was changed

**The pairing rule has one home.** It was written out at four sites: `setSynchronizable` and the
accounts store had it right, and the two add paths in `WrappedKeyStore` took the flag from the
preference and the class from a stored default. Writing it correctly a fifth time at the two broken
sites would have left the shape that produced the defect, so it is now
`SecretAccessibility.forSync(_:)` and **all four sites call it**.

**`WrappedKeyStore`'s stored `accessibility` was removed**, along with its initialiser parameter.
With the class derived from the flag it selected nothing, and a parameter that is silently ignored
is a false affordance. No caller passed it.

**S1-27**: `addIfAbsent` snapshots `synchronizable()` once and uses that one answer for the add and
for the rollback delete. Asking again to build the rollback meant a preference that moved in between
named the other slot, so the undo deleted the record that was already there rather than the one the
call had just written.

**A residual, recorded rather than fixed:** `KeychainSecretStore` still takes `accessibility` and
`synchronizable` as independent parameters, so the pair can still be split at that boundary. Its one
caller uses `forSync` now.

## The two questions

**1. Is each item fixed? Yes or no, for each of S1-25 and S1-27.** If no, one sentence on what
remains.

Judge the code. For S1-25: is there any remaining path that writes a sync flag and a protection
class from different sources, at any of the four sites or a fifth this brief has not named? For
S1-27: can any preference change between two reads still redirect a write or a delete in that call?

**2. Does either fix introduce a new high or medium?** Yes or no. If yes, name it and give the call
order.

The surfaces where the author is least confident:

- **Removing a public initialiser parameter and a public stored property.** Whether anything
  depended on setting them, and whether the default that remains is right for every caller.
- **`forSync` on `SecretAccessibility`**, a type shared with the accounts store. One rule for two
  stores that have different threat properties: say if that conflation is wrong.
- **A record already written with the broken pairing.** Existing installs may hold a wrapped key
  with the sync flag set and a device-only class. Nothing in this change migrates it. Does the
  foreground reconcile repair it, does `setSynchronizable` repair it, or does it stay wrong?
- **The snapshot in `addIfAbsent`** now spans a `SecItemAdd`, a count, and a delete. Whether one
  answer held across all three is right, or whether any of those steps wanted a fresh reading.

## One disclosure about the tests

Three hosted tests were added against the real Keychain. **The third passed before the fix, which is
how its own defect was found**: the closure read the preference before flipping it, so both reads
returned false and the rollback hit its own record by accident. It was corrected to answer false
once and true afterwards. Both mutations were verified to apply before being run: collapsing
`forSync` to always device-only reddens the eligibility test, and restoring the second
`synchronizable()` call reddens the rollback test.

Nothing else is in scope. Two answers and their reasoning is the whole deliverable.
