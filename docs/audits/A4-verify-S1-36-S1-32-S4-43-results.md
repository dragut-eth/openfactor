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
