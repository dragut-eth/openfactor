# A4 verification: S1-31, answered

Reviewed commit: `e4bd414`. S1-31 was filed in `A4-verify-S1-25-results.md`.

## The answers

| Engine | S1-31 fixed? | New high or medium? |
| --- | --- | --- |
| ChatGPT | **No** | No |
| Fable | Yes | No |
| Grok | Yes | No |

**Nobody found a new high or medium.** All three verified the repair's direction and placement.
ChatGPT found a path the other two reasoned past, and it is real.

## S1-35 (medium): the repair swallows its own failure, and the toggle carries on

Found by ChatGPT. Verified here, and the consequence is the one this scope opened with.

```
if SecItemUpdate(slot as CFDictionary, changes as CFDictionary) == errSecSuccess {
    repaired += 1
}
```

A failed update is counted as not-repaired and nothing is said. Then `setSynchronizable` reaches
`if status == errSecItemNotFound { return false }` and returns **normally**, because the move query
legitimately found nothing to move. Then, in `SyncAwareKeychainStore`:

```
if shouldSync {
    try wrapped.setSynchronizable(true)
    return try store.setSynchronizable(true)
}
```

The wrapped call did not throw, so **every account is converted to iCloud** and the interface
commits the preference.

**Accounts in iCloud, wrapped key device-only, switch reading on.** That is S1-1, the finding this
whole scope opened with, reached through the repair that exists to prevent it.

**The distinction the other two engines missed is between the two callers.** Fable reasoned that a
failed update is skipped and retried at the next foreground, which is true of the reconcile and
false of the explicit toggle: the reconcile retries harmlessly, and the toggle commits a preference
and converts the accounts on the strength of a repair that did not happen. Grok reached the same
benign reading. Neither is wrong about the reconcile.

**This project already has the rule, written down one hundred lines above the code that breaks it.**
`KeychainSecretStore.setSynchronizable` carries the sentence from gate A2, F14: *the failure that
understates exposure must not be the quiet one*. And it has the precedent twice over:
`SharedInbox.write` refuses when it cannot exclude the directory from backup, and `VaultKeyStore`
refuses to write a key it cannot exclude. **I wrote the opposite in the one place where the quiet
failure converts every account.**

ChatGPT's remedy, which is the right one: require `errSecSuccess` for every attempted repair and
throw otherwise, so account conversion and the preference commitment both stop when the wrapped
record was not repaired.

**The successful-path tests cannot see this**, which is why it survived three hosted tests.

## What all three confirmed

**The direction and the placement.** The repair updates the class alone, pinned to each record's own
flag, changes no primary-key attribute, never deletes, never rewrites the wrap, and skips records
whose pair already matches.

**The twin interaction, which was the surface I was least sure of, holds.** Both Fable and Grok
walked it independently and reached the same answer: under twins the move collides and produces
`errSecDuplicateItem`, but **the repair runs before the status guard throws**, so the stranded
twin's class is corrected even on the call that then fails visibly. The toggle still fails; the
stranded class does not. Fable adds that the repair itself can never collide, because
`kSecAttrAccessible` is not part of the primary key.

**The preference-off gap is correct rather than residual.** Grok: the record's flag is true because
it was written with sync on, and the preference only flips after a successful conversion, so a
device holding one still has the preference on. Fable adds the one route that reaches a
preference-off device, app deletion and reinstall, since the Keychain outlives the app and the
preference does not, and notes the mismatch is inert there until sync is wanted again, at which
point the enable toggle repairs before anything depends on it. ChatGPT agrees no automatic loosening
is needed.

**Loosening the class is the right trade**, unanimously. Fable's reasoning: the content is
ciphertext, so the class governs sync eligibility rather than confidentiality, and it is exactly
what the flag already promised. Bringing the flag to the class instead would decide on no evidence
that a record marked for iCloud stays off it, **which is the habit this gate has now filed three
findings against**.

**The shared definition is not circular**, and Fable broke the worry properly rather than
dismissing it: the hosted tests compare the stored class against the raw `kSecAttrAccessible*`
constants rather than against `forSync`, so a wrong definition reddens two tests instead of
agreeing with itself.

## On the panel, after five verification rounds

**Three consecutive rounds have now ended two-to-one, with the same engine dissenting, and in all
three the dissent was specific and right.** Each time the mechanism was fixed and a remainder
survived that the other two named and accepted, or in this case reasoned past.

That is worth recording without turning it into a ranking. Fable and Grok each produced findings
this round that the dissent did not: the twin ordering, the reinstall route, the non-circularity of
the shared definition. **What the pattern actually argues for is keeping three**, and for reading a
lone "no" as a claim to check rather than a vote to be outvoted.

## What was done: S1-35

**The repair fails closed.** A `SecItemUpdate` that does not succeed throws, so
`setSynchronizable` throws, so `SyncAwareKeychainStore` never reaches the account conversion and
the interface never commits the preference. The comment cites the rule it broke, which was already
in the file next door.

**The seam was generalised rather than duplicated.** `duringSave` became `beforeWrite` and is
called at both gaps: the one in `save` and the one in the repair. One optional closure, two call
sites, still `nil` on every shipping path and still reachable only through the internal
initialiser. The alternative was a second hook to test three lines.

The test removes the record in the gap so the class update lands on nothing, and asserts the throw.
Mutation verified applied: restoring the swallowed status reddens it.

### An interaction I found while implementing, which is not a new finding but is worth stating

**On the disable direction the throw arrives after the accounts have already moved.**
`SyncAwareKeychainStore` converts the accounts first when turning sync off, then the wrapped key.
So a failed repair on that path now throws with every account already local while the preference,
which only flips after success, still reads on.

That is **S1-28's shape exactly**, already filed: the switch overstating protection. This change
does not create it and does not widen it beyond one more route to it, and the alternative is the
silence that made S1-35 a medium. **Recorded here so it is a known consequence rather than a
discovery.** S1-28's fix, a twin pre-flight before the accounts convert, is also the fix for this
route.

## S1-33 is waived

**Decision: recorded, not fixed.** Under the gate's rule, an item left standing is listed with its
reason.

**What it is.** iCloud can replace the bytes of the observed record, at the same primary key, in
the gap between `save` reading it and writing. Two engines called it the API's floor and one called
it the remainder of S1-26.

**Why it is not being fixed.** Reaching it needs a cross-device erase and re-create landing inside a
microsecond window during a concurrent passphrase change on this device, and **passphrase
replacement has no interface at all**: `replacePassphrase(with:)` is called by nothing but tests.

**And the available fix is not cheap.** `../E/E12-a-compare-and-swap-token.md` measured that
`kSecAttrGeneric` can carry a compare-and-swap token, so the floor claim is false and a mechanism
exists. But it rests on two things nobody has measured: whether iCloud carries the token between
devices unchanged, and whether every writer maintains it, since a peer on an older build updates
the value and leaves the token alone. Building a version-token protocol into the store that has
produced a high and two mediums, on two unmeasured preconditions, to close a window nothing can
currently reach, is the worse bet.

**What would reopen it.** A passphrase-change screen shipping, or the two-device measurement E12
asks for coming back positive. Either changes the arithmetic and this decision should be revisited
rather than inherited.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Grok:
Commit: e4bd414. S1-31 filed in A4-verify-S1-25-results.md.

Answers

┌─────────────────────┬─────┐
│                     │     │
├─────────────────────┼─────┤
│ S1-31 fixed?        │ Yes │
├─────────────────────┼─────┤
│ New high or medium? │ No  │
└─────────────────────┴─────┘

Why it is fixed

The stranded record is synchronizable = true with a this-device-only class. setSynchronizable(true) still looks for flag false, so conversion still misses it. repairProtectionClasses() then walks every record, and where protectionMatchesFlag is false it updates only kSecAttrAccessible, pinned to that item’s own flag. No delete, no wrap rewrite, no flag move.

Reconcile still calls setSynchronizable(true) on every foreground when the preference is on. Repair runs even if the conversion update returns errSecItemNotFound. That is the path the finding said never touched these records.

A matching record is skipped (where !protectionMatchesFlag). The worst update on a record that should have been left alone is writing the class it already had.

Preference off: right that reconcile does not run. The S1-31 record’s flag is already true; it was written with sync on, and the preference only flips after a successful conversion, so the devices that have it still have the preference on. A flag-true wrap with preference off is a different inconsistency and is not this finding.

Twins / S1-28: repair runs before the conversion status is thrown. Each update is keyed to that row’s flag, so it does not change a primary key and does not collide. If conversion then throws .duplicate, the class repair has already happened. The toggle still fails; the stranded class does not.

Loosening to whenUnlocked: that is what the flag already claimed. Leaving the class device-only is the loss shape. The trade is the correct one.

protectionMatchesFlag uses forSync: the report and the repair share one definition. A wrong forSync would make both wrong together; it would not hide a mismatch.

Devices that never run this build stay as they are. That limit is stated and is not a remaining path on a device that does.

Fable:
Verification: S1-31 — commit e4bd414 (filed in the S1-25 verification round)
Question 1: is S1-31 fixed?
Yes. The finding was that a record with `kSecAttrSynchronizable = true` beside a device-only class sat outside `setSynchronizable`'s query (which looks for the opposite flag), so the foreground reconcile passed over it forever while `syncReport` called it synced. I traced every path that can now reach such a record:

* The reconcile (every foreground, preference on) calls `setSynchronizable(true)`; the move query still misses the stranded record, but `repairProtectionClasses()` runs unconditionally after the move and before the status is evaluated, reads every record under both flags, and updates the class alone — pinned to the record's own flag — wherever `protectionMatchesFlag` fails. The stranded record is repaired on the first foreground.
* Both toggle directions run the same repair. The disable direction additionally repairs by construction: its move query matches `flag = true`, and the move itself writes flag and class together.
* The twin interaction with S1-28 does not leave the repair unreached, and the placement is what guarantees it: under twins, the move collides and produces `errSecDuplicateItem`, but the repair runs before the status guard throws, so the stranded twin's class is corrected even on the call that then fails visibly. Within the repair, each update is pinned to its own record's flag and changes no primary-key attribute (`kSecAttrAccessible` is not part of the primary key), so the repair itself can never collide, twin, or move anything.

Is there a state the repair can leave a record in that is worse than found? No, by construction: it writes exactly one non-key attribute to exactly the value `forSync` derives from the record's own flag, touches only records whose pair disagrees, never deletes, never rewrites the wrap (the test pins the bytes surviving), and a failed update is skipped and retried at the next foreground. The worst reachable outcome is the status quo ante.
What remains, in one sentence as budgeted: a device whose preference is off and is never toggled keeps its stranded record — which I checked and consider correct rather than residual harm, because with the preference off no sync expectation exists for the mismatch to violate, the record is repaired at the first moment sync is re-enabled (the enable toggle runs the repair), and the never-runs-this-build limit is the brief's stated non-goal.
Question 2: does the fix introduce a new high or medium?
No. The author's four surfaces, checked:

* Repair gated behind `setSynchronizable`, unreachable with the preference off: right, per the analysis above. The one route to a stranded record on a preference-off device is app deletion and reinstall (the Keychain outlives the app, the preference does not), and even there the mismatch is inert until sync is wanted again — at which point the enable toggle repairs before anything depends on the pairing. No additional route is needed.
* The twin case: holds, as walked above — the repair is reached before the S1-28 throw, and its per-record flag pinning cannot select the wrong item because the flag is the discriminator between twins.
* Loosening the class: the trade is right. The flag is the only statement the record itself makes about where it belongs, and it was only ever written from a genuine preference (at creation, or by the toggle); the content is ciphertext, so the class difference governs sync eligibility — precisely what the flag promised — not confidentiality. Bringing the flag to the class instead would decide, on no evidence, that a record marked for iCloud stays off it, which is the wrong-record-inference habit this gate has now filed three findings against. The narrowest edge — twins plus a stranded record during a disable, where the repair makes the stranded twin genuinely syncable moments before the toggle throws its known S1-28 collision — is non-destructive, stays within the flag's own statement, and surfaces an error rather than silence.
* The shared `forSync` definition: the report and the repair sharing one definition is the design, and the circularity the author fears is broken outside the pair — the hosted tests compare the stored class against the raw `kSecAttrAccessible*` constants, not against `forSync`, so a wrong definition reddens `creatingWithSyncOnIsEligibleForICloud` and `aSplitPairIsRepaired` rather than agreeing with itself.

The tests anchoring this are the genuine kind this gate has converged on: the split pair is planted through raw `SecItemAdd` independent of the store, the premise is asserted before the code under test runs, and the post-conditions are checked against raw constants — class repaired, flag unmoved, wrap byte-identical. Reverting the fix reddens the repair test on its first assertion, since the repair call is the only code that can change that class. The Debug readout now stating "class does not match" closes the observability half: the one instrument a device under test offers no longer agrees with the bug.
Verdicts: S1-31 fixed; no new high or medium introduced.

GPT:
S1-31 — Not fixed
The repair’s direction and placement are correct: it updates only the protection class, pins each update to the record’s flag, runs before a twin collision is reported, and is reached by the foreground reconcile when sync is enabled.
However, [repairProtectionClasses() (line 351)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:351) silently ignores every unsuccessful `SecItemUpdate`:

```
if SecItemUpdate(...) == errSecSuccess {
    repaired += 1
}
```

Concrete failure:

1. A record holds the stranded `true`/`ThisDeviceOnly` pairing.
2. `setSynchronizable(true)` finds no opposite-flag record.
3. The repair reads the malformed record, but its class update fails or the record disappears before the update.
4. The failure is ignored and the repair returns zero.
5. `setSynchronizable` returns `false` as a successful no-op.
6. `SyncAwareKeychainStore` proceeds to synchronize the accounts and the UI commits the enabled preference.
7. The accounts sync while the wrapped recovery record remains device-only or absent—the original S1-31 medium consequence.

Foreground reconciliation may retry a transient failure, but an explicit sync enable is incorrectly allowed to continue, and persistent or disappearance failures remain invisible. The successful-path hosted tests cannot detect this.
Smallest fix: require `errSecSuccess` for every attempted repair and throw `error(for: status)` otherwise. That stops account conversion and preference commitment when the wrapped record was not repaired.
A preference-off device does not otherwise need an automatic loosening: a normal off transition already pairs the record locally, and enabling sync reaches this repair. The flag-to-class direction is sound.
New high or medium — No
The ignored status leaves S1-31’s original medium open; it does not introduce a distinct regression. Successful repairs neither delete nor rewrite wrap bytes, and updating the class dictated by the existing flag is the correct Keychain eligibility change.
No files were changed, and no build or tests were run.
