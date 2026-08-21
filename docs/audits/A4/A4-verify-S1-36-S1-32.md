# A4 verification: S1-36 and S1-32

**This is not a review round.** Two closed questions and nothing else. Do not report low-severity
findings beyond answering these. Do not review anything outside these two items. **A thin answer is
the correct answer.**

**Both are low, and neither changes behaviour**, which is why they are together and why this round
should be short.

**The code under review is `65b7b3e`.** S1-36 was filed in `A4-verify-S1-35-results.md`; S1-32 in
`A4-verify-S1-25-results.md`. The six previous verification rounds are in the same directory.

Read-only. Do not build and do not run tests; keep the checkout clean.

**Already decided, so do not report:** S1-33 is waived, with reasoning at the end of
`A4-verify-S1-31-results.md`. S1-28, S1-29, S1-30 and S1-34 are open and filed.

## S1-36, as filed

`aFailedRepairIsReported` asserted `#expect(throws: (any Error).self)`, so it would pass on the
wrong error type. The same file asserts `SecretStoreError.twinnedRecord` exactly elsewhere, and the
core suite is precise throughout.

**What was changed.** The assertion names `SecretStoreError.notFound`, which is what
`error(for: errSecItemNotFound)` produces when the removed record makes the class update match
nothing.

## S1-32, as filed

`KeychainSecretStore.setSynchronizable` wrote the flag-and-class pairing as an inline ternary where
every other site calls `SecretAccessibility.forSync`. It was correct, both attributes coming from
one `shouldSync`, but it was the rule written out a fifth time, and the fix that centralised the
rule argued that writing it again is the shape that produced the defect.

**What was changed.** That site calls `forSync`.

## The two questions

**1. Is each item fixed? Yes or no, for each of S1-36 and S1-32.** If no, one sentence on what
remains.

For S1-36: is `.notFound` actually what that path produces, and would the assertion now fail if it
produced something else? For S1-32: is the substitution genuinely identical for both inputs, and is
there now any remaining site in the tree that writes a sync flag and a protection class without
going through `forSync`?

**2. Does either change introduce a new high or medium?** Yes or no. If yes, name it and give the
call order.

**One thing the author found and is disclosing rather than leaving to be caught.** Breaking `forSync`
deliberately reddens four tests, and **all four are in the wrapped key suite**. No accounts test
noticed, so the accounts side of the rule is covered by the substitution being provably identical
rather than by a test. Say whether that is acceptable for a change of this size, or whether the
accounts path needs coverage of its own before the rule is trusted to one function.

Nothing else is in scope. Two answers and their reasoning is the whole deliverable.
