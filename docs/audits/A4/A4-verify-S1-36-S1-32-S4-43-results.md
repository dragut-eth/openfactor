# A4 verification: S1-36, S1-32 and S4-43, answered

Two rounds, reported together. S1-36 and S1-32 were reviewed at `65b7b3e`; S4-43 at `a16e5fe`.

## The answers

| Engine | S1-36 | S1-32 | S4-43 | New high or medium? |
| --- | --- | --- | --- | --- |
| ChatGPT | Yes | Yes | Yes | No |
| Fable | Yes | Yes | Yes | No |
| Grok | Yes | Yes | Yes | No |

**Unanimous on every item.** The gate still has no open high and no open medium.

## S1-37 (low): two Keychain suites execute nowhere, and one of them is the accounts store

Fable followed the disclosed coverage asymmetry rather than accepting it, and the answer is worse
than the disclosure. **Verified here, and the numbers are ours rather than the reviewer's.**

The disclosure was that breaking `forSync` reddens four tests, all in the wrapped key suite. Fable
found why: the accounts-side hosted tests assert the stored class **only in the sync-off
direction**, and both sync-on tests assert the flag and never `kSecAttrAccessible`. So a `forSync`
collapsed to always-device-only agrees with the only accounts-side class assertion that runs.

**Then it found the assertions that would have caught it, and found that they run nowhere.**
`KeychainSecretStoreTests` asserts both classes after a conversion. It is gated on
`KeychainAvailability.isUsable`, which is false on the unsigned package host, so `swift test` skips
it. And the hosted CI job runs `-only-testing:OpenFactorTests`, which is the app target. **That
suite is in neither.**

Measured at this commit:

| Suite | Tests | Runs in `swift test` | Runs in hosted CI |
| --- | --- | --- | --- |
| `KeychainSecretStoreTests` | 15 | skipped | not included |
| `VaultTests` | 11 | skipped | not included |

**Twenty six tests that execute in no job and on no machine**, and `swift test` reports thirty two
skipped instances between them.

**This is the gate's founding shape, recurring.** `VaultTests` never running is what produced
`WrappedRecordStore` and `VaultDecisionTests` in the first place, and it was treated then as the
most important methodological finding this project had made. **Nobody noticed that
`KeychainSecretStoreTests` sits in exactly the same position**, and that one covers the accounts
store, which holds every secret.

It is not a code defect and holds nothing open under this round's scoring. It is a coverage void
wearing the appearance of coverage, and the remedy is a CI change rather than a code change.

Fable's cheaper interim closure, worth taking regardless: **one assertion in each of the two
existing hosted sync-on tests**, reading back `kSecAttrAccessible` and expecting `whenUnlocked`,
mirroring what the wrapped key suite already does. That closes the specific asymmetry today without
waiting on the larger question.

## What was confirmed

**S1-36.** All three walked the path to `.notFound` rather than taking it: the seam deletes every
record, the class update matches nothing, `error(for:)` maps `errSecItemNotFound`, and the typed
`throws(SecretStoreError)` chain propagates it unchanged. Fable adds the detail that makes it exact:
`setSynchronizable`'s own move status, also `notFound`, is never evaluated because the repair throws
first, **so no other error can shadow it**. And because `SecretStoreError` is `Equatable`, the value
form matches by equality, so a wrong mapping reddens it where `(any Error).self` accepted it
silently.

**S1-32.** Identical by definition rather than by testing: `forSync`'s body *is* the replaced
ternary, over a two-value domain. All three re-ran the site enumeration at this commit and agree
every production site that derives the pairing goes through `forSync`. The one that still writes
both attributes without calling it, `KeychainSecretStore.add`, **transports constructor values
rather than deriving them**, and every production feed of those values comes through `forSync`. That
is the residual already recorded with S1-25, unchanged and out of scope.

**S4-43.** Fable checked the three things the brief named and confirmed each. The only other path
that touches files by name, `sweepStale`, iterates `handle.names()` and reads and removes the same
string throughout, so **it never converted to a `UUID` and back and was never subject to the
mismatch**. `SharedInbox.write` is the sole writer and the extension writes only through it, so the
guard can reject only names this app did not write. And the two guards **compose as an AND** rather
than one masking the other: a lowercase file is refused even though it is a file, and a canonical
directory is refused even though the spelling matches.

**Nothing newly accumulates.** All three reached the same place: under the old code a non-canonical
file was also only removed by `sweepStale`, because collection acted on the canonical twin, a
different file. So the cleanup behaviour is unchanged and the fix removes a hazard rather than
adding a persistent class.

## Where the gate stands

**No high, no medium, six lows and one waiver.**

| Item | Scope | What it is |
| --- | --- | --- |
| S1-28 | 1 | the twin state breaks the sync toggle forever, and disabling overstates protection |
| S1-29 | 1 | the refusal's message can read as saying the new passphrase works, and has nowhere to appear |
| S1-30 | 1 | nothing hosted covers the sync toggle under twins |
| S1-34 | 1 | the seam can express the same-slot case and no test does |
| S1-37 | 1 | twenty six Keychain tests execute in no job and on no machine |
| S4-45 | 4 | five false claims left |
| S1-33 | 1 | **waived**, with its reasoning and what would reopen it |

S1-28 remains the one to take first, because it is load-bearing for its own finding and for the
disable-direction route the S1-35 fix added, and S1-30 is its test.

**S1-37 is the one to think hardest about**, because it is not about this code at all. It says that
a suite can exist, be written carefully, pass review, and assure nothing, which is the thing this
gate discovered about itself a week ago and has now discovered again.

## What was done: S1-28 with S1-30, and the rest of S1-37

### S1-37: two suites now run, a third is named rather than hidden

`KeychainSecretStoreTests` and `VaultTests` moved to the hosted target, where a simulator always has
a real Keychain, and the run-time gate is gone rather than made conditional on something else.
**All twenty six execute and pass on the first run**, so nothing was hiding behind the skip.

CI refuses `enabled(if:)` in either test directory now, with the reasoning in the job: a suite that
decides at run time whether to run can assure nothing and report success.

**Moving them surfaced a third case.** `StoreUnderTest` used the same probe to choose which stores
`SecretStoreTests` runs against, so its Keychain half has also never run while the suite reported
success for fifteen cases. The probe is gone and the list is stated rather than decided, so the file
now says plainly that only the in memory store is covered. Moving that suite needs helpers the
package's own tests depend on, so it is recorded as the remaining half of S1-37 rather than done
badly. **The new CI rule does not catch that shape**, which is worth knowing about the rule.

### S1-28: the conversion refuses by name, and nothing moves before it can

Three changes, each with its own test, each red first.

**`setSynchronizable` refuses a twin pair with `twinnedRecord`** instead of colliding into
`errSecDuplicateItem`. The collision reached a person as advice to try again, which failed the same
way every time, and the honest error already existed forty lines away with nothing throwing it.

**The refusal sits below the repair, deliberately.** The S1-31 verification established that the
class repair runs even on a call that then fails, and that a stranded record in a pair is corrected
either way. The repair is correct under twins because each update is pinned to one record's own flag
and changes no primary-key attribute, so it can neither collide nor pick the wrong record. Putting
the guard above it would have left such a record wrong on every call that refuses, which is every
call, forever. **Moving the guard above the repair reddens
`twinsAreRepairedEvenWhenConversionRefuses`.**

**`SyncAwareKeychainStore` asks before it moves anything.** Turning sync off converts the accounts
first and the record second, and that order is deliberate: the reverse leaves a window with accounts
in iCloud and no key to read them. But it meant a record that cannot convert threw with every
account already local while the preference, which flips only on success, still read on, so the
switch claimed iCloud held accounts it did not. `precheckConversion()` is one read that refuses
before anything is written. **Removing it reddens
`accountsDoNotMoveWhenTheWrappedRecordCannot`.**

**And the message stops advising a retry that cannot succeed.** `message(for:)` passes
`twinnedRecord`'s own sentence through. Two records is a state nothing in this app resolves, so
generic advice to try again is a loop rather than help.

**This also closes the route the S1-35 fix added**, which was recorded at the time: a failed repair
throwing after the accounts had already moved. The pre-flight stops the accounts moving at all.

457 package tests pass, the hosted suite passes, both targets build.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

GPT:
Is S4-43 fixed? Yes. SharedInbox.write, including the extension path, always writes UUID().uuidString. pending now requires that exact canonical spelling before returning the UUID, so take and sweep reconstruct the same basename that was observed. The canonical-name and regular-file guards compose: an entry must satisfy both. The code no longer depends on filesystem case sensitivity.
Noncanonical names are excluded from collection but remain visible to sweepStale, which timestamps and removes them using their exact enumerated names once stale.

Does the fix introduce a new high or medium? No. It only narrows candidate admission to names the app itself produces. Noncanonical entries do not newly accumulate indefinitely; they retain the existing age-gated cleanup path.

No files were changed, and no builds or tests were run.

S1-36: The seam deletes the record immediately before the repair update. That update consequently returns errSecItemNotFound, which maps to SecretStoreError.notFound. The exact #expect(throws: SecretStoreError.notFound) assertion will fail for any other error or no error.

S1-32: forSync(true) returns .whenUnlocked and forSync(false) returns .whenUnlockedThisDeviceOnly, exactly matching the removed ternary. No other production pairing-rule implementation remains. KeychainSecretStore.add consumes constructor values, but the app’s caller derives that pair through forSync; the previously disclosed independent initializer boundary is not another implementation of the rule.

The missing account-side mutation coverage is acceptable for this behavior-preserving substitution: both mappings are directly evident, and the wrapped-key tests exercise the shared function. It remains a coverage limitation, not a blocker or regression.
No build or tests were run, and the worktree remains clean.

Fable:
Verification: S1-36 and S1-32 — commit 65b7b3e
Question 1: is each item fixed?

S1-36 — yes. The assertion now names SecretStoreError.notFound, and I walked the path to confirm that is exactly what it produces: the repair loop iterates the list read before the seam fires, the seam deletes every record for the service, the class update's SecItemUpdate therefore matches nothing and returns errSecItemNotFound, error(for:) maps that to .notFound, and the typed throws(SecretStoreError) chain propagates it unchanged through setSynchronizable — whose own move status (also notFound, saved earlier) is never evaluated because the repair throws first, so no other error can shadow it. Would the assertion fail on anything else? Yes: SecretStoreError is Equatable and the value form of #expect(throws:) matches by equality, so .duplicate, .keychain(status:), or a wrong mapping all redden it — and the disclosed mutation (mapping a missing item to .duplicate) is precisely the class of drift the old (any Error).self form accepted silently.

S1-32 — yes. The substitution is identical by definition rather than by testing: forSync's body is the replaced ternary (shouldSync ? .whenUnlocked : .whenUnlockedThisDeviceOnly), over a two-value input domain, so the mapping is provably unchanged for both inputs. On the remaining-sites question, I re-ran the enumeration from the S1-25 verification at this commit: every site that derives the pairing now goes through forSync — the three write paths and the repair in WrappedKeyStore, SyncAwareKeychainStore, and now KeychainSecretStore.setSynchronizable. The one site that still writes both attributes without calling forSync at the write is KeychainSecretStore.add, which transports constructor-supplied values rather than deriving them; every production feed of those values goes through forSync (via SyncAwareKeychainStore) or is the paired default, and that independent-parameters boundary is the residual already recorded in the S1-25 verdicts, unchanged by and out of scope for this item.

Question 2: does either change introduce a new high or medium?

No. S1-36 changes a test assertion and no production code. S1-32 replaces an expression with a function whose body is that expression; no behavior can differ, and the diff confirms nothing else moved in the file.

On the disclosed coverage asymmetry, which is the one thing here worth more than a sentence: the author's mutation report is accurate, and I verified why it is accurate rather than taking it — the accounts-side hosted tests assert the stored class only in the sync-off direction (addsUnsyncedWhenPreferenceIsOff, line 107, ThisDeviceOnly), while both sync-on tests (convertsExistingAccounts, followsThePreferenceWithoutBeingRebuilt) assert the flag and never kSecAttrAccessible, so a forSync collapsed to always-device-only agrees with the only accounts-side class assertion that executes. Worth stating precisely: assertions that would catch it do exist, at KeychainSecretStoreTests lines 132 and 213 — but that suite is Keychain-gated, skips on the unsigned package host, and is excluded from the hosted CI job, so they execute nowhere. That is the gate's oldest known shape, coverage in text but not in execution.

Is that acceptable for this change? For this change, yes — a provably identical substitution needs no test to be trusted, and forSync itself is pinned by four executing tests against raw Keychain constants. But the asymmetry the mutation exposed is real and predates this commit: the accounts store's sync-on class pairing — the accounts-side twin of the exact property S1-25 was about — has no executing coverage anywhere, and the accounts side is also where the one non-forSync transport boundary remains. The cheap closure is one assertion in each of the two existing hosted sync-on tests: read back kSecAttrAccessible and expect whenUnlocked, mirroring what the wrapped-key suite already does. I'd file that as the follow-up that lets the rule be trusted to one function on both stores, not just one.

Verdicts: S1-36 fixed; S1-32 fixed; no new high or medium introduced.

Both questions verified against the code at a16e5fe. Here is the deliverable.

Q1 — Is S4-43 fixed? Yes.

pending now gates every candidate with guard let id = UUID(uuidString: name), name == id.uuidString else { return nil } (SharedInbox.swift:218), so a Pending is produced only when the on-disk basename is byte-for-byte the canonical uppercase spelling. Since take reads and removes by id.uuidString (:273–285) and sweep removes by id.uuidString (:309), the entry observed (name) and the entry acted on (id.uuidString) are now guaranteed identical. Checking the three things the brief names:

No remaining path where observed and acted-on differ. The pending-driven path is closed by the guard above. The only other path that touches files by name, sweepStale, iterates handle.names() and reads/removes the same name string throughout (:334–353) — it never converts to a UUID and back, so it was never subject to the mismatch and still isn't.
Every write really produces id.uuidString exactly. SharedInbox.write is the sole writer and uses directory.appendingPathComponent(id.uuidString) (:155); the extension writes only through SharedInbox().write (ShareViewController.swift:71), with no other file-writing into the inbox. So the guard can only ever reject a name this app did not write, never drop a genuine share.
The narrow form is sufficient. The discarded basename mattered only where a Pending.id was re-canonicalized in take/sweep; the guard makes that a no-op for identity, and sweepStale never re-canonicalizes. There is nowhere the guard fails to reach that still suffers the split.
Q2 — Does the fix introduce a new high or medium? No.

Working the three surfaces the author flagged:

A non-canonical name. It is rejected before the stat, so it is never presented and never in the identifier set a collection supersedes — but sweepStale still ages it out by exact name, because that path judges by age and operates on the readdir string directly. Nothing accumulates that could not before: under the old code a non-canonical file was also only removed by sweepStale (collection acted on the canonical twin, a different file), so the cleanup behaviour is unchanged; the fix removes the hazard of choosing on one file and acting on another rather than adding a new persistent class. The only lingering items remain the pre-existing accepted ones (a canonical-named directory, excluded by the S4-42 guard and un-removable by unlinkat).
Composition with S4-42's regular-file guard. The two guards are sequential in the same compactMap and form an AND: name-canonical (lexical, first) then regular-file (stat, second). Neither masks the other — a candidate must be both, removing either guard re-opens its own finding, and the name guard short-circuiting the stat for foreign names loses nothing because those names are correctly not candidates and are still swept by age.
Case-insensitivity dependence. The code no longer relies on it. pending requires exact-spelling equality, so on a case-sensitive volume only the canonical name is admitted and take/sweep act on that same spelling; sweepStale is case-agnostic by construction. No path depends on case-folding to make two spellings collide.

What I checked to conclude nothing: the guard in pending, the id.uuidString construction in write/take/sweep, that the extension has no alternate write path, that sweepStale operates on the raw basename, and the ordering/composition of the two compactMap guards. I did not review anything outside S4-43, and I did not touch S4-45.

Grok:
1. Yes.

pending requires name == id.uuidString after the parse. The only inbox writer in this app is SharedInbox.write, used by the extension as well, and it names the file id.uuidString. take and sweep still rebuild from uuidString; that is the same string pending admitted, so the entry selected is the entry acted on. Discarding the basename after that guard does not reopen a second spelling. A lowercase plant is not a candidate (onlyTheCanonicalSpellingIsAnItem).

2. No.

A non-canonical name is no longer an item and is not in a collection’s identifier set. sweepStale still walks every names() entry by age, so it ages out the same way as any other foreign leftover. That is not new accumulation.

The spelling check and the regular-file check are both in the same compactMap and both must pass: a lowercase UUID file is refused even if it is a file; a canonical UUID directory is refused even if the spelling matches.

The pending → take / sweep path no longer depends on a case-insensitive volume.

Commit: 65b7b3e. S1-36 filed in A4-verify-S1-35-results.md; S1-32 in A4-verify-S1-25-results.md.

Answers

┌─────────────────────┬────────┐
│                     │ Fixed? │
├─────────────────────┼────────┤
│ S1-36               │ Yes    │
├─────────────────────┼────────┤
│ S1-32               │ Yes    │
├─────────────────────┼────────┤
│ New high or medium? │ No     │
└─────────────────────┴────────┘

S1-36

The seam deletes the record, then SecItemUpdate matches nothing. error(for:) maps errSecItemNotFound to .notFound. The assertion is #expect(throws: SecretStoreError.notFound). A different case, including .keychain or .duplicate, fails it. That is what the old (any Error).self would have accepted.

S1-32

KeychainSecretStore.setSynchronizable now does SecretAccessibility.forSync(shouldSync). forSync is shouldSync ? .whenUnlocked : .whenUnlockedThisDeviceOnly, which is the ternary it replaced. Both inputs match.

Every production site that writes a flag and a class together goes through forSync: wrap save add, addIfAbsent, wrap setSynchronizable, wrap repair, SyncAwareKeychainStore constructing the account store, and this conversion. KeychainSecretStore.add still copies stored fields; the app sets those from forSync. That is the residual recorded with S1-25, not a fifth copy of the rule.

Accounts tests

Acceptable for this change. The substitution is identical by reading both expressions, so no accounts test had to move. Trust in forSync itself sits in the wrap suite (and in KeychainSecretStoreTests.syncChangesTheProtectionClass, which asserts both classes after conversion and does not run on the unsigned package host). That is enough for a no-behaviour edit. It is not coverage of the accounts conversion site, and the commit says so.
