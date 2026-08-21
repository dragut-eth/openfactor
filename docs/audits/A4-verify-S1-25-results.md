# A4 verification: S1-25 and S1-27, answered

Reviewed commit: `07e2972`. Both findings were filed against `b3e7e08` and are written up in
`A4-round-five-scope1-results.md`.

## The answers

| Engine | S1-25 fixed? | S1-27 fixed? | New high or medium? |
| --- | --- | --- | --- |
| ChatGPT | **No** | Yes | No |
| Fable | Yes | Yes | No |
| Grok | Yes | Yes | No |

**S1-27 is unanimously fixed and nobody found a new high or medium.** The split on S1-25 is about
scope rather than facts: **all three describe the same situation and label it differently.**

## S1-31 (medium): a record already written with the broken pairing is never repaired

This is the surface the brief handed over as the author's least confident, and asking about it is
what produced the answer.

**The write is fixed and the data is not.** All three confirm every site now derives the class and
the flag from one value. None of them repairs a record already stored as
`kSecAttrSynchronizable = true` beside a device-only class.

`WrappedKeyStore.setSynchronizable(shouldSync)` queries for `synchronizable = !shouldSync`.
Verified here. So `setSynchronizable(true)` looks for records flagged **false**, and a broken record
is already flagged **true**. It is not in that query. **The foreground reconcile calls exactly that
method, so it misses the record on every launch, forever**, and `syncReport` reads the flag rather
than the class, so the one readout that exists reports the record as being in iCloud while its
class keeps it on the device.

That is the S1-1 loss shape, silent, on any install that reached the state.

**ChatGPT scores this as S1-25 not fixed**: the finding's consequence still exists on affected
installs. **Fable and Grok score the write fixed and call this unremediated history**, with Fable
adding that the population is knowable and likely includes the E-series test phones, and Grok
calling it leftover data rather than a remaining split write. They agree on every fact.

**One thing none of the three said, and it widens the window.** The broken pairing did not begin
with the write-time preference change. Before it, the app constructed the store as
`WrappedKeyStore(synchronizable: UserDefaults.standard.bool(...))` and never passed an
accessibility, so the stored default applied. **Any vault created while the sync preference was
already on has produced this record since the round two fix that made creation follow the
preference.** The window is weeks, not a day.

**What repairs it**, per Fable and Grok: a full sync off then on. The disable finds `flag = true`,
rewrites both attributes as a pair, and the re-enable pairs them again. Nothing detects the
mismatch to prompt it.

**Fable's smallest fix**, which is the right shape: teach the reconcile or `syncReport` to read both
attributes and, on a `flag = true` with a device-only class, update the class in place through
`forSync(true)`. An update, no delete, idempotent, in the function that already runs every
foreground.

**And it is checkable on hardware.** The Debug readout shows the flag and the record count. Showing
the protection class beside them would say immediately whether either of the two phones is in this
state, which is worth knowing before deciding how urgent the repair is. E8 measured a wrapped key
that did reach a replacement phone, so at least that record was paired correctly; that says nothing
about a vault created later with the preference already on.

## S1-32 (low): the pairing rule has a fifth home

Found by Fable, and noted by Grok independently. Verified.

**The brief said the rule now has four call sites. There are five.**
`KeychainSecretStore.swift:238` writes it out inline as
`shouldSync ? .whenUnlocked : .whenUnlockedThisDeviceOnly`.

It is correct: both attributes come from one `shouldSync`. But it is the pairing rule written out a
second time, and **the fix's own reasoning was that writing it correctly a fifth time would leave
the shape that produced the defect.** Fable's recommendation is to convert it when that file is
next touched.

## What was confirmed

**S1-27, unanimously.** `addIfAbsent` reads the preference once and that answer feeds the add's
flag, its class, and the rollback's target. Both Fable and Grok answered the author's stated
uncertainty about the snapshot spanning add, count and delete, and answered it the same way:
**holding one answer is not merely acceptable but required**, because the undo must name the slot
this call wrote. A fresh reading inside the call is the defect itself.

**Every write site.** Fable enumerated all six production sites that write `kSecAttrAccessible`
across every target, by grep rather than by reading the brief's list, and reports no remaining path
that takes the flag and the class from different sources.

**The removal of the parameter and the property.** No caller in any target passed or read them, and
the `accessibility:` arguments visible in `SyncAwareKeychainStore` belong to `KeychainSecretStore`
rather than to the store that lost them.

**`forSync` shared between the two stores.** Fable's reason for calling the conflation correct: the
rule encodes a Keychain semantics constraint rather than a per-store policy, and the item with a
genuinely different threat model, the vault key, is a container file this type never touches.

**The accepted-not-refused premise, which the brief asked them to verify rather than take.** Fable
could not execute against securityd in a read-only round and said so, then gave three independent
observations consistent only with acceptance: two older tests stayed green while writing or
updating a split pair, and the new read-back reported `aku` beside `synchronizable = true`. A
refusal would have reddened all three. It also records that this retroactively settles its own round
two finding at the second of the two variants it had offered.

## On the format, after three uses

**This is the first verification round that returned a "no", and it returned it on a question the
brief asked itself.** The stranded record was one of four surfaces listed as the author's least
confident, phrased as "does the foreground reconcile repair it, does `setSynchronizable` repair it,
or does it stay wrong?". The answer came back precise and unanimous on the facts.

That is the argument for naming uncertainties in the brief rather than only the parts that look
finished. Question 2 did not produce either of this round's items; question 1 and the disclosed
surface did.
