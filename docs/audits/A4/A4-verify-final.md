# A4 verification: the last three, and a correction that comes first

**This is not a review round.** Closed questions and nothing else. Do not review anything outside
the items named. **A thin answer is the correct answer.**

**The code under review is `f7361bf`.** The eight previous verification rounds are in this
directory.

Read-only. Do not build and do not run tests; keep the checkout clean.

## Read this first: a finding you verified as fixed was not real

**S1-37 was wrong, and all three of you verified it as fixed.** One of the round five returns
supplied the premise and the other two accepted it. So did the maintainer, who wrote it into a
results table, a commit message and a CI rule without checking it.

**The claim.** Twenty six tests in `VaultTests` and `KeychainSecretStoreTests` executed in no job
and on no machine, because `swift test` skips them and the hosted CI job passes
`-only-testing:OpenFactorTests`.

**What is actually true.** The `OpenFactorTests` target's `fileSystemSynchronizedGroups` lists
**both** `OpenFactorTests` and `Tests/OpenFactorCoreTests`. The package test directory compiles into
the hosted bundle, and in a simulator the Keychain probe returns true. **Measured by running the
hosted suite at the commit before the fix: twenty six executions.** Not zero.

**Two verified facts and one unchecked inference.** `swift test` skips them: true. The job passes
that flag: true. **Target membership: never checked**, by anybody.

**And the fix removed coverage.** `StoreUnderTest` used the same probe to choose which stores
`SecretStoreTests` runs against, so removing it dropped fifteen Keychain executions from the hosted
run: thirty before, fifteen after, thirty again now. **S1-39 was therefore created by that change
rather than discovered.** Both findings are withdrawn, the probe is restored, and the CI rule added
in S1-37's name is removed, because a rule whose stated reason is untrue should not survive on the
grounds that it sounds prudent.

**This is not raised to assign blame.** It is raised because the audit record showed a withdrawn
finding as verified closed, and because the lesson generalises: `E12` in this directory records that
a claim about a platform API is checkable, and it was checked and found false. Two days later a
claim about a build system was not checked and was false. **The lesson had been filed as being about
the Keychain rather than about claims.**

**Question 0, and answer it first: is the correction itself right?** Yes or no. If the analysis
above is wrong in any part, that matters more than anything else in this round.

## The three items

**S1-38.** `setSynchronizable` counts, then updates. A record arriving between those calls is
invisible to the count, the update collides, and `errSecDuplicateItem` surfaced as `.duplicate`,
which Settings renders as advice to try again: the retry loop S1-28 removed, back in that window.
Now a collision there throws `.twinnedRecord`, on the reasoning that **nothing else can collide at
that update**, so the collision is evidence of a pair by construction. The race is not closed and
cannot be by this shape.

**S1-34.** The same-slot substitution that S1-33 was waived for now has a test, which asserts the
**current** behaviour rather than the desired one, so that a waiver written in prose fails if the
answer moves.

**S4-45.** Four false claims corrected. **Two were left alone because they had become true**:
`take` removes the item it refused, which was false only for a directory until S4-42 stopped
directories becoming candidates; and `sweepLeavesWhatArrivedLater` says "leaves what arrived after
the caller looked", which is exactly what its test does.

## The two questions

**1. Is each item fixed? Yes or no, for each of S1-38, S1-34 and S4-45.** If no, one sentence.

For S4-45 specifically: **check the two that were left alone.** If either is still false, leaving it
was a mistake and the reasoning above is the error.

**2. Does any of it introduce a new high or medium?** Yes or no. If yes, name it and give the call
order.

Surfaces where the author is least confident:

- **The `beforeWrite` seam now fires at three gaps**: in `save`, inside the repair loop, and between
  the count and the update in `setSynchronizable`. Confirm it is still `nil` on every shipping path
  and that no shipping build reaches a non-nil closure at any of the three.
- **Mapping `errSecDuplicateItem` to `.twinnedRecord`** rests on the claim that nothing else can
  collide at that update. Say if that claim is wrong.
- **A test that pins a waived behaviour** is unusual. Say whether encoding an accepted limitation as
  an assertion is right, or whether it entrenches something that should stay uncomfortable.
- **The App Lock sentences.** Six sentences across four files describe one mechanism and have now
  been corrected in three separate passes. Say whether any remain wrong, and whether the real
  problem is that the mechanism is described in every file that depends on it rather than in one
  place they point at.

Nothing else is in scope.
