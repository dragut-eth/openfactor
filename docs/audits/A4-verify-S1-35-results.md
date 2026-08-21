# A4 verification: S1-35, answered

Reviewed commit: `bb10d82`. S1-35 was filed in `A4-verify-S1-31-results.md`.

**The brief said two engines. Three answered.** So the coverage caveat it carried does not apply,
and the round is the usual width.

## The answers

| Engine | S1-35 fixed? | New high or medium? |
| --- | --- | --- |
| ChatGPT | Yes | No |
| Fable | Yes | No |
| Grok | Yes | No |

**Unanimous on both questions.** With this, **no high and no medium is open anywhere in the gate.**

## A reviewer retracting its own reading

Fable opened by recording that S1-35 exists because of its own S1-31 verdict: it reasoned that a
failed update is *skipped and retried at the next foreground*, which is true of the reconcile and
false of the toggle, the caller that converts every account and commits the preference on the
strength of the return. It states that ChatGPT caught the caller distinction it missed, that the
finding's severity was right, and that its own benign reading was wrong.

**That is the second time in this gate a reviewer has retracted**, the first being a round-two
finding of its own in scope 4. Recorded because a panel that corrects itself is worth more than one
that is never wrong, and because this project's rule is to record rather than smooth over.

## S1-36 (low): the new test accepts any error

Flagged by Fable as a half-sentence for the record rather than a finding, which is correct under
this round's scoring. Recorded here because it is real, cheap, and has a precedent.

`aFailedRepairIsReported` asserts `#expect(throws: (any Error).self)`, so **it would pass on the
wrong error type**. Verified: the same file's `savingIntoTwinsIsRefused` asserts
`SecretStoreError.twinnedRecord` exactly, and the core suite is precise throughout, with
`Base32Tests` asserting specific cases with their associated values.

Fable notes this is the same shape a previous round tightened elsewhere.

## What all three confirmed

**The throw reaches the caller that mattered.** On enable, `SyncAwareKeychainStore` calls the
wrapped store **before** the accounts store, so the throw stops the conversion before it starts,
`SettingsView` catches it, and the preference, which flips only after success, is never committed.
Both halves of the filed remedy hold.

**No remaining path treats a failed repair as success.** Fable enumerated by grep rather than from
the brief: `repairProtectionClasses` has exactly one caller, `setSynchronizable` has exactly three
routes, and nothing in the vault, the watch or the extension reaches it indirectly. It also checked
three specific candidates and found none: the loop throws at the first failure so the count can
never overstate, the move's own status is still evaluated afterwards, and no other code path reads
the repair's result.

**The reconcile swallowing forever is harmless and is not a new shape.** It converts nothing and
commits nothing on its return, and Fable adds that it is the same silent-retry-forever profile the
reconcile already has under the S1-28 collision.

**Partial repair is the right shape**, unanimously. Each repaired record stays repaired, the
remainder is exactly what the next attempt's mismatch filter finds, and the caller's only meaningful
response is the same whether one or all failed, so collecting errors would add bookkeeping without
changing an outcome.

**The seam is `nil` on every shipping path**, verified by grep in the tree: the public initialiser
sets it explicitly, the internal test initialiser is the only setter, and the only references
outside the store are in the tests. Fable adds that a healthy shipping build runs one nil-check in
`save` and **none in the repair**, since the second fire site sits inside the loop that only runs for
records whose pair already disagrees.

## The disclosed interaction, and a narrowing of it

All three back the judgement, and one improves on it.

The comparison is between a **visible** partial state, accounts local with the switch still reading
on, an error on screen, retryable, and a **silent** completion that left a malformed record behind
while everything reported success. Fable decides it on the project's own rule: the failure that
understates exposure must not be the quiet one.

**Fable also narrows my disclosure in a way I had not seen.** The repair rarely has work to do on
the disable direction at all, because disable's own move query targets `flag = true` records and
rewrites both attributes as it goes. So the route this change adds to S1-28 is **narrow as well as
filed**, which is a smaller consequence than I recorded.

## Where the gate stands

**No high and no medium is open.** The severity half of the goal set for A4 is met, on the second
attempt after the night that broke it.

What remains is eight lows and one waiver, which is the triage this was aimed at:

| Item | Scope | What it is |
| --- | --- | --- |
| S1-28 | 1 | the twin state breaks the sync toggle forever, and disabling overstates protection |
| S1-29 | 1 | the refusal's message can read as saying the new passphrase works, and has nowhere to appear |
| S1-30 | 1 | nothing hosted covers the sync toggle under twins |
| S1-32 | 1 | the pairing rule has a fifth home, written out inline |
| S1-34 | 1 | the seam can express the same-slot case and no test does |
| S1-36 | 1 | the new test accepts any error rather than the one it means |
| S4-43 | 4 | the exact directory entry is not carried through |
| S4-45 | 4 | five false claims left |
| S1-33 | 1 | **waived**, with its reasoning and what would reopen it |

**S1-28 is the one to look at first**, and not because of its severity. It is now load-bearing for
two things: its own finding, and the disable-direction route this change added. Its fix, a twin
pre-flight before the accounts convert, closes both.

## What was done: S1-36 and S1-32

Two lows that share nothing but their size, taken together because neither changes behaviour.

**S1-36.** `aFailedRepairIsReported` asserts `SecretStoreError.notFound` rather than any error. The
repair's update matches nothing once the record is removed, and `error(for:)` maps
`errSecItemNotFound` to `.notFound`. A test that accepts whatever is thrown would stay green if the
repair began failing for an unrelated reason, which is the opposite of what it is there to notice.

Mutation verified applied: making `error(for:)` report `.duplicate` for a missing item reddens it,
where the old assertion would have passed.

**S1-32.** The pairing rule's fifth home is gone. `KeychainSecretStore.setSynchronizable` used a
ternary where every other site calls `SecretAccessibility.forSync`. Identical values for identical
input, so this changes nothing and removes a place where the rule can drift, which is how two of its
five homes came to disagree in the first place.

**One limit worth stating rather than implying.** Breaking `forSync` reddens four tests, and **all
four are in the wrapped key suite**. No accounts test noticed, so the accounts side of the rule is
covered by the substitution being provably identical rather than by a test of its own. That is
enough for this change and it is not coverage.

482 core tests pass, the app suite passes.
