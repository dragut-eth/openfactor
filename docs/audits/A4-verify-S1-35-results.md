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

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

GPT:
Verification verdict
Question	Verdict
Is S1-35 fixed?	Yes
New high or medium introduced?	No


S1-35 — Fixed
[repairProtectionClasses() (line 351)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:351) now requires every attempted SecItemUpdate to return errSecSuccess; any other status is translated and thrown.
On sync enable, that throw propagates through:
WrappedKeyStore.setSynchronizable(true);
SyncAwareKeychainStore.setSynchronizable(true);
the Settings binding.
The account conversion is therefore never reached, and the preference is not committed. There is no remaining enable path that treats a failed repair as success.
The hosted test deletes the observed record immediately before the repair update and requires a throw. Restoring the swallowed-status implementation would make that test fail.
New high or medium — No
Foreground reconciliation still swallows errors with try?, but it changes no dependent state and retries on every foreground.
On disable, accounts have already moved before a wrapped-key repair throws. That is the already-filed S1-28 state—accounts local while the preference still reads on—not a new consequence. The throw is preferable to silently claiming the wrapped operation succeeded.
A partial twin repair is safe and recoverable: successfully corrected classes remain corrected, the first failure stops the call, and the idempotent next attempt handles the remainder. No wrap bytes, flags, or records are deleted.
The generalized beforeWrite seam is nil through the public initializer, has exactly two production call sites, and is supplied only by hosted tests. Its placement immediately before each adapter write expresses the intended race without adding a shipping behavior.
No files were changed, and no build or tests were run.


Grok:
Commit: bb10d82. S1-35 filed in A4-verify-S1-31-results.md.

Answers

┌─────────────────────┬─────┐
│                     │     │
├─────────────────────┼─────┤
│ S1-35 fixed?        │ Yes │
├─────────────────────┼─────┤
│ New high or medium? │ No  │
└─────────────────────┴─────┘

Why it is fixed

A failed class update now guards on errSecSuccess and throws. setSynchronizable calls repairProtectionClasses() before it returns success, so the throw reaches SyncAwareKeychainStore.

On enable, the wrap move runs first. A throw means store.setSynchronizable(true) is never called, and Settings only writes syncEnabled after that returns. Accounts stay local and the switch stays off.

No remaining enable path treats a failed repair as a successful wrap conversion. Reconcile is try? wrapped.setSynchronizable(true) only; it does not convert accounts and does not flip the preference.

Callers, seam, partial repair

Reconcile swallowing a perpetual throw is a retry, not a commit. Harmless.

beforeWrite is nil on the public initialiser. The internal initialiser is the only way to set it. It fires after the repair has chosen a mismatched record and built the slot, immediately before SecItemUpdate — the gap the test deletes into. Shipping builds do not reach a non-nil closure. save still uses the same optional; one hook, two gaps.

If the first of two mismatched records is repaired and the second throws, the caller sees the throw. Enable still does not convert accounts. The next attempt skips the record that already matches. That is the right shape.

Disable vs silence

The judgement is not wrong. Enable-and-silence was S1-1: accounts leave, wrap stays device-only, switch reads on. That door is closed. Disable still converts accounts first, so a failed repair throws with accounts already local and the preference still on. That is S1-28’s shape, already filed. One more route to an existing finding is better than the quiet enable path this change exists to kill. S1-28’s pre-flight is the fix for both.

Fable:
Verification: S1-35 — commit bb10d82 (filed in the S1-31 verification round)

One acknowledgement before the verdicts, since this gate's culture is to record rather than smooth over: S1-35 exists because my own S1-31 verdict reasoned "skipped and retried at the next foreground" — which was true of the reconcile and false of the toggle, the caller that converts every account and commits the preference on the strength of the return. ChatGPT caught the caller distinction I missed. The finding's severity was right and my benign reading was wrong.

Question 1: is S1-35 fixed?

Yes. The swallowed status is gone: WrappedKeyStore.swift:364 now evaluates every attempted repair's SecItemUpdate and throws error(for: status) on anything but errSecSuccess. I traced the throw to the caller that mattered, against a complete enumeration of callers (grep across all targets):

repairProtectionClasses has exactly one caller, setSynchronizable, which invokes it with try and propagates.
The enable direction — the one the finding is about — calls wrapped.setSynchronizable(true) before store.setSynchronizable(true) in SyncAwareKeychainStore, so the throw stops the account conversion before it starts, SettingsView catches it, and the preference — which flips only after success — is never committed. Both halves of the filed remedy hold: no conversion, no commitment.
The reconcile swallows with try? and converts nothing and commits nothing on its return, so swallowing there remains correct.

Is there a remaining path where a repair fails and something proceeds as though it had not? I checked the three candidates and found none: the loop throws at the first failed item, so the count can never overstate; the move's own status is still evaluated after the repair, so a failed move still throws; and no other code path reads the repair's result or depends on it (save, addIfAbsent, and unlock never call it). The one configuration where a succeeded move coexists with a throwing repair requires a second, stranded record — twin territory, which already throws visibly and is filed as S1-28.

The test is a genuine one: the seam deletes the record between the repair's read and its write, the update lands on nothing, and the call throws; with the swallow restored, the repair returns zero, setSynchronizable falls through to its legitimate errSecItemNotFound return, and the test goes red — the mutation reproduces the exact silent path the finding described. One half-sentence of looseness for the record, not a finding: #expect(throws: (any Error).self) would pass on a wrong error type, the same shape a previous round tightened elsewhere.

Question 2: does the fix introduce a new high or medium?

No. The four surfaces, checked against the complete caller list:

Every caller of setSynchronizable. There are exactly three routes: the Settings toggle through SyncAwareKeychainStore (both directions), and the foreground reconcile. The toggle already had a catch with a user-facing message and a preference that only commits on success — a new throw there lands in handling built for throws. The accounts store's own setSynchronizable is untouched. Nothing reaches the wrapped store's method indirectly from the vault, the watch, or the extension.
The reconcile, throwing every foreground forever on an unrepairable record: harmless in effect — try?, no state change, no user surface — and not a new shape; it is the same silent-retry-forever profile the reconcile already has under the S1-28 twin collision. The cost is a wasted call per foreground, which the repair's touches-only-mismatches design already minimizes.
The generalised seam: verified nil on every shipping path — the public initialiser sets it to nil explicitly, the only setter is the internal test initialiser, and the only references in the tree outside the store are in WrappedKeySyncTests. Its second fire site sits inside the repair loop, after the slot is chosen and before the update — exactly where the test needs the record to vanish — and executes only for records whose pair already disagrees, so a shipping build's healthy path runs one nil-check in save and none in the repair. Generalising one closure over duplicating a second hook was the right call; two seams would be twice the production surface for the same expressiveness.
Partial repair: the first-throw-wins shape is right. Each repaired item is independently correct and stays repaired; the unrepaired remainder is exactly what the next attempt's mismatch filter finds; and the caller's only meaningful response — abort the conversion and surface the failure — is the same whether one or all repairs failed, so collecting errors would add bookkeeping without changing any outcome.

On the disclosed disable-direction interaction, the judgement asked about: it is correct, and the throw is not worse than the silence it replaced. The comparison is between a visible partial state — accounts local, switch still reading on, an error on screen, retryable — and a silent completion that left a malformed record behind while everything reported success. The partial state is S1-28's already-filed shape reached through one more door, it is the honestly-alarming direction rather than the quietly-reassuring one, and the project's own rule — the failure that understates exposure must not be the quiet one — decides it. I would add only that the repair rarely has work on the disable direction at all (disable's own move query targets flag = true records and rewrites both attributes), so the added route is narrow as well as filed.

Verdicts: S1-35 fixed; no new high or medium introduced.
