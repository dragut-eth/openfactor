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

## What was done: S1-31

**The class is made to agree with the flag, in place, and nothing else moves.**

`repairProtectionClasses()` reads every record's flag and class, and where they disagree it updates
**the class alone**, pinned to that record's own flag. It never deletes, never writes the wrap, and
never moves a record between flags. **The flag is the record's own statement of where it belongs**,
so the class is brought to it rather than the other way round, which means the worst this can do to
a record it should have left alone is set the class it already had.

That direction matters. Moving the *flag* instead would decide, on no evidence, that a record
flagged for iCloud does not belong there. This gate has now filed a high and two mediums against
exactly that habit.

It runs inside `setSynchronizable`, on both directions of the toggle, which is what the foreground
reconcile already calls. **Only records whose pair actually disagrees are touched**, so an ordinary
record is not rewritten on every foreground.

Fable's remedy, taken as filed.

### The report can now say it

`syncReport` gained `protectionMatchesFlag`, and the Debug row appends "class does not match" when
it is false. **The flag alone could never say this**: a record written with the flag set and a
device-only class reads as "in iCloud" while iCloud can never carry it. Two of this gate's findings
were about a boolean nobody could see, and this is the second half of the same boolean.

**This is what makes the question answerable on hardware.** Open Settings on either phone and the
row says whether that device is affected.

### The tests

Three hosted, against the real Keychain, red before the fix. A record planted in the broken shape
is repaired to `whenUnlocked` with its flag unmoved and its wrap byte-identical; the report names
the mismatch before and its absence after; and a correctly paired record survives a conversion
without its class changing, which is what keeps the repair idempotent.

The planting is raw `SecItemAdd`, because **no code path in the app can produce this shape any
more**, which is the point of the fix that came before it.

Mutation verified applied: removing the repair call reddens the two tests that assert it and leaves
the idempotence test green, which is the correct signature.

### What this does not do

It repairs a device that runs this build. **A device that never runs it keeps its record as it is**,
and there is no route by which one phone repairs another: the mismatch is a property of a Keychain
item that, in this state, is not syncing.

482 core tests pass, the app suite passes, both targets build.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

GPT:
Reviewed commit b3e7e08. The checkout differs only by the round-five brief.
Findings
Medium — sync-enabled vault creation still uses a device-only protection class
[WrappedKeyStore.addIfAbsent (line 222)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:222) now reads the current sync preference, but it changes only kSecAttrSynchronizable:
attributes[kSecAttrSynchronizable as String] = synchronizable()
attributes[kSecAttrAccessible as String] = accessibility.attribute
The app constructs this store without overriding its default .whenUnlockedThisDeviceOnly accessibility at [OpenFactorApp.swift (line 79)](OpenFactor/OpenFactorApp.swift:79). Consequently, when the closure returns true, the add requests a synchronizable item with a ThisDeviceOnly protection class.
Apple explicitly prohibits that combination: synchronizable items may not use an accessibility value ending in ThisDeviceOnly. Apple’s kSecAttrSynchronizable documentation states this directly.
Concrete failure:
Sync remains enabled after the owner erases and recreates the vault—the exact S1-14 route.
Vault.create(with:) calls addIfAbsent.
The closure returns true.
SecItemAdd receives kSecAttrSynchronizable = true and kSecAttrAccessibleWhenUnlockedThisDeviceOnly.
Security rejects the incompatible attributes. Creation reports the gate’s generic “could not be set up; try again.”
Every retry uses the same incompatible attributes, and Settings is behind the vault gate, so the person has no in-app way to turn sync off.
This fails closed rather than recreating the former account-loss state, but it does not implement the claimed write-time synchronization fix and can leave setup permanently blocked after an erase.
The new test at [WrappedKeySyncTests.swift (line 250)](OpenFactorTests/WrappedKeySyncTests.swift:250) reads back only the sync flag. It never asserts kSecAttrAccessibleWhenUnlocked, so it does not test the complete Keychain contract.
Smallest fix: evaluate the preference once and choose both attributes from it:
let shouldSync = synchronizable()
attributes[kSecAttrSynchronizable as String] = shouldSync
attributes[kSecAttrAccessible as String] =
    shouldSync ? SecretAccessibility.whenUnlocked.attribute : accessibility.attribute
Use that same snapshot for any rollback. The hosted test should read back both attributes; actual cross-device delivery remains a hardware property.
Medium, latent — save still permits the destructive twin update through a TOCTOU window
The guard at [WrappedKeyStore.swift (line 156)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:156) and the record selection at [WrappedKeyStore.swift (line 164)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:164) are separate Keychain operations:
countingBothFlags() returns one.
An opposite-flag record arrives from iCloud.
SecItemCopyMatching(...kSecMatchLimitOne) now sees two and returns either unspecified.
SecItemUpdate at line 186 overwrites whichever one was returned with a wrap of the caller’s current vault key.
If that was the synced record for the other live vault, its only recovery credential is replaced account-wide.
Thus the guard refuses a pair that already exists but leaves the original destructive class open when the pair appears between check and selection.
This is latent because the shipped app still has no passphrase-replacement screen, but Vault.replacePassphrase(with:) remains public and this is the same data-loss outcome as S1-19.
Smallest fix: fetch candidates() once, require exactly one candidate, and update specifically under that candidate’s captured flag. Do not perform a second Any/MatchLimitOne selection. Removing replacement until such a targeted operation exists would also be safe.
The fake does not model this. [InMemoryWrappedStore.save (line 74)](Tests/OpenFactorCoreTests/InMemoryWrappedStore.swift:74) holds one lock across count and replacement, while the real adapter performs separate Keychain calls. The hosted test plants the twin before save, so both tests agree with the static guard and miss its race.
Low, latent — the dynamic preference is read twice, allowing rollback to delete the record it was meant to protect
[WrappedKeyStore.addIfAbsent (line 222)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:222) asks synchronizable() when adding, then asks it again at line 239 to choose what to delete after detecting a twin.
Concrete call order:
The first read is false; the call adds local wrap W_B.
Synced live wrap W_A is present, so the count is two.
The preference changes to true.
The rollback query now selects the synchronizable slot and deletes W_A, not W_B.
addIfAbsent returns false, so Vault.create does not install K_B. The surviving W_B wraps an unused key, while W_A—the recovery credential for the existing accounts—is gone everywhere.
This is the flag-keyed wrong-record deletion S1-20 described, reintroduced through the remaining rollback delete rather than discard. The normal Settings path reduces reachability because it writes the preference only after conversion succeeds, and a twin should make conversion fail; hence low rather than high. The Sendable store nevertheless accepts a mutable concurrent closure, so the two reads cannot safely be assumed equal.
Smallest fix: snapshot shouldSync once at the beginning and use it for the add and rollback. A test whose closure returns different successive values should assert that the pre-existing record survives byte-for-byte.
Fix assessment
Removing discard from unlock is correct. Both wraps survive, and the regression test plus structural API removal are sufficient evidence for this specific fix. The test could assert bytes as well as count, but unlock no longer has a wrapped-record mutation operation available.
Choosing no deletion over deleting parse-invalid candidates was correct. With only a flag-keyed delete, an item can change between inspection and deletion; invalidity of the old bytes says nothing about the current occupant of that slot.
Refusing a known twin in save is the right policy, but the non-atomic implementation does not close S1-19.
The write-time preference closure fixes the stale Boolean but does not produce a valid synchronizable item and introduces the double-read rollback hazard.
The list-to-gate signal is sound. It runs on the main actor, reports each row’s transition into failure once, and gate.refresh() re-reads the store. One broken account alongside readable accounts does not satisfy suggestsAWrongKey, so it cannot drive the gate closed. I found no re-entrancy loop.
Restricting reconciliation to .active is correct.
The twinnedRecord message is incomplete. “Nothing was changed” is true, but in a replacement flow “Unlocking with your passphrase still works” can sound as though the newly shown replacement works. It does not. It should say that the existing passphrase or passphrases still work, the new one was not saved, and OpenFactor cannot change a passphrase while both records remain.
Tests
aSuccessfulUnlockDeletesNothing: tests the required property and is reinforced by removal of the mutation API.
candidatesSeesBothTwins: genuinely tests the Keychain adapter, including both flags and bytes.
savingIntoTwinsIsRefused: genuinely tests the already-present-pair branch, but describes rather than closes the TOCTOU class.
theFlagIsAskedAtWriteTime: proves the closure is consulted at write time, but only checks the Boolean attribute. It misses the incompatible accessibility class and cannot establish that the item is eligible to sync.
The fake still overstates save fidelity by making its guard and replacement atomic.
Twin state end to end
At most two records can accumulate: the fixed service/account/access-group identity has only the two sync-flag variants, and another item under either existing flag is a duplicate. save refuses an observed pair, and conversion can collide but cannot create a third.
With live W_A/K_A/P_A and W_B/K_B/P_B:
Each original device continues using its local key.
A keyless device tries both wraps. P_A installs K_A; P_B installs K_B.
Neither unlock deletes or rewrites either wrap.
A well-formed second wrap costs one additional 600,000-round PBKDF2 derivation per actual unlock—not per ordinary launch while the local key remains installed.
The owner cannot safely replace either passphrase, merge the vaults, label which accounts belong to which wrap, or remove one through the app.
An open device has no release-mode “use the other passphrase” action. Full erase removes both wraps and all accounts; it is destruction, not conflict resolution. Reinstalling can remove the container key and make another unlock possible, but that is neither presented nor a suitable resolver.
Sync conversion may fail on the primary-key collision, and foreground reconciliation silently leaves the pair alone.
No account that was recoverable before b3e7e08 becomes unrecoverable because of the removal. This commit is strictly safer than a90dd70: round four could destroy one live vault’s only recovery credential merely by successfully unlocking the other; this commit preserves both. Permanent retention is therefore the correct immediate security policy.
A non-destructive route is still warranted: at minimum, let the owner discard only the installed container key and return to the passphrase screen so each vault can be accessed without touching either wrap. Any actual merge or deletion needs evidence connecting a recovered key to account ciphertext and a deletion primitive that cannot race a replacement.
Verdict
This is converging and is materially safer than round four, but scope 1 should not close. The destructive unlock cleanup is gone, and the list-to-gate change holds. The write-time synchronization path remains invalid, and the save refusal still has a twin-arrival window. The round also introduced a smaller mutable-closure rollback hazard.
No files were changed, and no build or test suite was run.


Wednesday 10:46 PM








Read docs/audits/A4/A4-verify-S1-25.md. It is a verification round, not a review round: two closed questions covering two findings, S1-25 and S1-27, and it asks for a separate fixed-or-not verdict on each. Nothing else is in scope. Background on both, including all three round five returns in full, is in A4-round-five-scope1-results.md in the same directory; the two previous verification rounds are A4-verify-S4-41-results.md and A4-verify-S4-42-S4-44-results.md. You may open anything those reference. The code under review is 07e2972; both findings were filed against b3e7e08. Do not modify, create, or delete any file, and do not build or run tests; your reply is the whole deliverable.






5:01 PM






Worked for 1m 59s



Verification verdicts
Item	Fixed?
S1-25	No
S1-27	Yes
New high or medium introduced?	No


S1-25 — Not fixed
New writes are corrected: save, addIfAbsent, wrapped-key conversion, and the account-store factory derive both attributes from SecretAccessibility.forSync(_:).
However, records already written as synchronizable = true plus WhenUnlockedThisDeviceOnly remain defective. [setSynchronizable(true) (line 304)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:304) queries only records with the opposite flag, false. It therefore does not select or repair a malformed record whose flag is already true. The foreground reconcile calls this same method, so it also does nothing; syncReport continues reporting the flag as synced.
A manual off-then-on toggle would repair the pairing, but nothing detects or initiates that migration. The original recovery gap therefore remains on installations that executed the broken write.
S1-27 — Fixed
[addIfAbsent (line 219)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:219) calls synchronizable() exactly once, stores the answer in shouldSync, and uses that value for:
the added item’s sync flag;
its derived protection class; and
the rollback delete’s target flag.
A preference change during the call can no longer redirect the delete to the pre-existing record. Holding the snapshot across add, count, and rollback is correct: those operations must retain the identity of this call’s write; a later preference belongs to a subsequent conversion.
New high or medium — No
Removing the accessibility parameter preserves the old sync-off default and corrects the sync-on case; no repository caller depended on the removed property or parameter. forSync expresses the same Keychain eligibility rule for both encrypted account records and the encrypted wrapped key. The remaining independently configurable KeychainSecretStore boundary is pre-existing, and its production caller now supplies the correct pair.
The uncorrected installed records above are the unresolved original S1-25 medium, not a new regression introduced by this fix.
No files were changed, and no build or tests were run.

Fable:
Round five for Scope 1. Reading the brief first.

Ran 3 commands, read A4-round-five-scope1.md

The core removal is clean in the diff. Now the app-side wiring, the list-to-gate signal, and all three new test surfaces.

Diff app wiring and list-to-gate signal

The wiring holds together. Now the three handed-over test surfaces.

Diff all three new test surfaces

Three quick verifications: no leftover discard callers, the ProvisioningDesk pattern the brief points at, and how the settings toggle renders store errors.

Checked discard callers, ProvisioningDesk pattern, settings error rendering

Everything is read. Here is the round-five deliverable.

Scope 1, round five — commit b3e7e08 (checkout cc1afc6, differing only in the brief)

Standing note, as every round: one continuous conversation across all five of my passes. This round that cuts the other way — the brief asks me to judge whether declining my own round-four remedy was the wrong call, and I answer that below against the bytes, not my ego.

Summary: the removal is correct, complete, and — for the first time in this gate — a fix that subtracted code instead of adding it, and I can construct no data-loss call order through what remains. The three handed-over items survive attack: the property test is sufficient evidence for a removal, the fake now models the adapter on the property that matters because a mutation-tested hosted test anchors the same property against the real Keychain, and two of the three hosted tests test rather than describe. Declining my narrower discard was the right call, and I say why. The one genuine new finding is a degradation the brief asked me to hunt for: in the twin state, the sync toggle fails forever with advice to retry, and the disable direction fails after the accounts converted, leaving the switch claiming sync that is not happening. No data is lost anywhere.

Question 1: does each change address its finding?

The removal (S1-20) — yes, and cleanly. discard(_:) is gone from the protocol, the adapter, and the fake; no caller survives anywhere in the tree (I grepped all targets); unlock's success path is unwrap, install, return. The class is closed at the type level: the defect was "unlock deletes on inference," and there is now no API through which unlock can delete — reintroduction requires deliberately re-adding a protocol requirement past a doc comment that records why it was removed and a test named aSuccessfulUnlockDeletesNothing. That is the right shape for this fix.

The save refusal — yes. countingBothFlags() <= 1 guards the write before anything is found to update, the count throwing also refuses (consistent with "decline to overwrite what it cannot see"), and the hosted test proves byte-exact survival of both records through a refusal against the real Keychain, mutation-tested per the brief. Is refusing right? Yes — with two live vaults' credentials present and no way to name the target, every alternative writes into an unexamined slot; refusal is the only non-destructive option, and it is the same decision unlock now embodies. Is the message honest? twinnedRecord's description — "nothing was changed. Unlocking with your passphrase still works" — is honest and names the safe path. Its problem is not honesty but reachability, which is my F1 below: the one place a person in the twin state actually collides with the pair today never throws this error. One accepted residual to name: the guard is count-then-update, so a twin arriving in the microseconds between them reproduces the unnamed-target write — the same accepted narrowing as addIfAbsent, and here the window has no 600ms derivation inside it.

The write-time preference (S1-14) — yes. The Bool became @Sendable () -> Bool, wired to a live UserDefaults read at the one call site, matching ProvisioningDesk.Conditions.hasVault in shape and in reasoning (asked when the answer matters, not captured when the object is built). Against the brief's specific worries: the closure is read inside Task.detached during creation, and UserDefaults is documented thread-safe; the ordering now matches the accounts store's rule instead of contradicting it, which was the whole finding; and a write and a conversion cannot interleave from the UI, since creation exists only behind the gate and the toggle only behind an open vault. The launch reconcile note in OpenFactorApp.init was updated to match.

The list-to-gate signal (S1-17) — yes, and the loop question has a clean answer. The signal fires on the transition into failure only (AccountListViewModel.swift:235), with a test pinning once-not-per-tick. The receiver is gate.refresh(), whose wrong-key decision re-reads the records fresh: one broken account among working ones yields a mixed list, suggestsAWrongKey is false, the stage stays .open, the stage doesn't change so nothing rebuilds, and the failed row cannot re-signal without first recovering — which, under a wrong key, it never does. The genuine wrong-key case moves the stage to .locked, which tears the list down and ends the ticks. No cycle exists: the gate only reopens the list on evidence the codes work, and the list only signals on evidence they stopped. Cost note, not a finding: N rows failing in one tick fire N refreshes, each a full records() read on the main actor — a burst, once per failure episode.

The reconcile on scene-active only — yes, the if phase == .active guard removes the pointless background-transition write attempts.

Carried-forward round-four asks, all landed: VaultKeyStore.load's catch is exhaustive with the .unreadable decision documented; the half-hour comment in WrappedKeyStore.load now distinguishes freshly-written propagation from a resident record, citing E8.

Question 2: did any change introduce something new?

I went looking on all three new surfaces the brief names. The refusing write is where something is.

F1 — Low/Medium, no data loss. The permanent twin pair breaks the sync toggle, permanently, with wrong advice — and the disable direction leaves the switch overstating protection. The brief asks what the pair degrades beyond one derivation. Walk it: twins are {local L, synced S}, one under each flag, same primary key otherwise. WrappedKeyStore.setSynchronizable(true) finds L and updates its flag to true — which now collides with S's primary key, so SecItemUpdate returns errSecDuplicateItem and the store throws .duplicate, not .twinnedRecord. Consequences, by direction:

Enabling sync: SyncAwareKeychainStore moves the wrapped key first, so the throw precedes any account conversion — state stays consistent, but the toggle fails with message(for:)'s generic "Sync could not be changed... try again" (SettingsView.swift:250). Trying again fails forever. The honest twinnedRecord description exists forty lines from the code that should throw it, and never will.
Disabling sync: accounts convert to device-only first, then the wrapped move throws — so the preference stays "on" (it flips only after success) while every existing account is already local. The switch now claims accounts are offered to iCloud when they are not, new accounts sync while old ones don't, and retrying re-fails on the wrapped record forever. A person who believes iCloud holds their accounts and loses the phone discovers otherwise at the worst moment — the quiet overstatement of protection this project's own gate-A2 history says must never be the silent failure.
The launch reconcile, in twin state with the preference on, hits the same collision on every foreground and swallows it, forever — harmless but permanently spinning.

Smallest fix: a twin pre-flight in setSynchronizable (countingBothFlags() > 1 → throw .twinnedRecord), run it before converting accounts on the disable path too, and let message(for:) pass twinnedRecord's own description through instead of advising a retry that cannot succeed. That also gives the twin state its first non-Debug visibility, which it currently lacks entirely — today the only user-facing symptoms are this failing toggle and a refused passphrase change whose honest message has no UI to appear in.

On the rest of the absence-attack checklist: two records cannot become three under one access group — the primary key admits exactly two flags — and nothing writes this service into any other group (the vault post-dates the shared-group entitlement, and candidates() would surface and unlock would tolerate a stranger if one ever appeared). No path writes a second record while one exists: save refuses at two and updates-as-found at one, addIfAbsent is add-count-undo, setSynchronizable updates in place. One honesty note on "there is no remove operation on purpose": addIfAbsent's undo is still a flag-keyed delete. Its target is the slot this process wrote a call earlier, and the interleaving that could poison it — an iCloud merge into that same slot between two adjacent calls, with the preference on and a local record the earlier state() somehow missed — is a sliver I could not make real. Recorded, not filed.

Question 3: do the new tests test the code, or agree with it?

The removal's property test — sufficient, for a stated reason. A removal cannot be mutation-tested, but this fix is enforced twice independently: the compiler (no discard requirement exists to call) and aSuccessfulUnlockDeletesNothing, which builds the exact two-live-vaults state round four was about — two fresh random keys, the fixture makes this explicit — and asserts survival in both unlock directions, which matters because round four's destruction was direction-dependent. One gap worth one test: nothing pins that an unparseable record survives a successful unlock, so my own declined round-four variant (discard rubbish only) could be reintroduced without any test objecting; whether that variant is ever acceptable was decided in prose, and a test would make the decision executable.

The fake — models, this time, on the property that matters. Round four's finding was agreement by construction; the difference now is anchoring: the fake's save refusal mirrors an adapter behavior that a hosted, mutation-tested test (savingIntoTwinsIsRefused) proves against the real Keychain, byte-for-byte survival included. A fake edited alongside the code stops being circular when the real store is held to the same property in the same commit; that structure is what round four asked for. The remaining unanchored divergence is pre-existing and documented: the fake's addIfAbsent can never leave two records behind (the real undo-failure path can, returning false with both present), so that documented residual stays untestable in-package.

The two non-mutation-tested hosted tests — they test, not describe. candidatesSeesBothTwins earns this verdict on a structural point: its premise is planted through raw SecItemAdd, independent of the adapter under test, and asserted (recordCount == 2) before the adapter is asked anything — so a broken candidates() cannot vouch for itself; wrong flags, missing bytes, or a one-record answer each redden a specific assertion. theFlagIsAskedAtWriteTime genuinely distinguishes the snapshot from the question: the store is constructed while the flag is false and the flag flips before the write, so a capture-at-init implementation fails it. Two small holes: it exercises only addIfAbsent's closure read, not save's add-branch; and nothing hosted covers the collision behavior setSynchronizable exhibits under twins — which is exactly where F1 lives, so the missing test and the missing fix are the same work item.

The declined remedy: it was the right call, and my round-four mechanism was wrong

I proposed discarding only records that failed as notAWrappedKey or iterationsOutOfRange — "bytes provably nobody's recovery record." The proof is about the bytes examined; the only available delete names a slot (service, account, flag), and the Keychain has no compare-and-delete. Between candidates() and the delete, iCloud can write a real record into the synced slot that rubbish occupied, and the delete then removes a credential nobody examined — the identical defect one door along, hidden behind a sound-looking predicate. The Keychain API cannot express the operation my fix needed, so the fix was unimplementable as specified, and removal — accepting one extra derivation per unlock forever — is strictly safer than any delete this API can write. The intent was right; the mechanism was not; the maintainer's reasoning stands.

Question 5: the recovery walk, end to end at this commit

Two devices, one Apple Account. Phone A holds vault A, its record S synced. Phone B created vault B during the arrival window; its record L is local. Both vaults live, accounts of both sealed in the Keychain.

What the owner can do. Unlock either vault on any device holding both records, by typing that vault's passphrase — unlock tries both records, the right one identifies itself, and a wrong passphrase is reported as wrong rather than blamed on the wrong wrap. Read and generate codes for whichever vault is open; the other vault's accounts show as unreadable rows, honestly. Add accounts. And — this is the evidence-based route out the brief asks whether one exists — consolidate through the encrypted export: export vault B's accounts on B, export vault A's on A, erase everything once (Face ID plus typed word; this deletes both records and every account item, propagating), create one fresh vault, import both archives. Every account survives; the twin state ends. The route is real, uses only shipped mechanisms, and costs deliberateness, which is the correct price.

What they cannot do. Change either passphrase (twinnedRecord, honest, currently UI-less). Flip the sync toggle (F1: permanent failure with retry advice, and a half-converted state on the disable direction). See the word "twin" anywhere outside the Debug readout.

Is anything unrecoverable that was recoverable before or after? No — the arrow points the other way. At a90dd70, the first unlock destroyed one live vault's only recovery credential, account-wide when the loser was synced. At 29d62e7 and earlier, nothing was destroyed but a correct passphrase could be misreported and save could overwrite an unspecified twin. At b3e7e08, every path short of the deliberate, authenticated erase preserves both credentials, and both vaults remain recoverable by their passphrases indefinitely. This commit is the first at which the twin state is simultaneously non-destructive, fully unlockable, and escapable.

Question 4: converging?

Yes — and this round is qualitatively different from the four before it. Every previous round's fixes added mechanism, and twice the added mechanism was the next round's finding. This round's principal fix is a removal whose safety is enforced by the type system, whose property is tested in both directions, and whose adapter gap from round four (zero Keychain coverage of candidates) was closed with tests that construct their premises independently of the code under test. The scope is not worse than before the discard was added — it is better than every prior commit reviewed: round two's misreporting is fixed, round four's destruction is gone, and the write that could silently pick a victim now refuses. What remains open is exactly one new item (F1, a service degradation with wrong advice and a quiet overstatement of sync — no data loss), one known-open carry (the twin state's invisibility outside Debug, which F1's fix would largely resolve), and the documented, accepted residuals (the addIfAbsent arrival window; the microsecond save gap). For the second consecutive round I can construct no call order that loses data. The defect surface is not moving around; it is shrinking, and what is left is legibility, not destruction.

Read docs/audits/A4/A4-verify-S1-25.md. It is a verification round, not a review round: two closed questions covering two findings, S1-25 and S1-27, and it asks for a separate fixed-or-not verdict on each. Nothing else is in scope. Background on both, including all three round five returns in full, is in A4-round-five-scope1-results.md in the same directory; the two previous verification rounds are A4-verify-S4-41-results.md and A4-verify-S4-42-S4-44-results.md. You may open anything those reference. The code under review is 07e2972; both findings were filed against b3e7e08. Do not modify, create, or delete any file, and do not build or run tests; your reply is the whole deliverable.

A verification round for S1-25 and S1-27. Reading the brief.

Read A4-verify-S1-25.md, ran 4 commands

The fix diff is clean. Now the closed-question verification: every remaining site that writes the flag/class pair, and the new hosted tests.

Ran 2 commands

Verification complete. Here is the deliverable — two closed questions, two answers.

Verification: S1-25 and S1-27 — commit 07e2972 (filed against b3e7e08)
Question 1: is each item fixed?

S1-25 — yes. I enumerated every site in the tree that writes kSecAttrAccessible (grep across all targets, production and test). The production write sites are six: three in WrappedKeyStore (save's add branch:192, addIfAbsent:229, setSynchronizable:312), all now deriving the class via SecretAccessibility.forSync(shouldSync) from the same single read that supplies the flag; KeychainSecretStore.add:148 and setSynchronizable:254, where flag and class both derive from one value (the construction pair or the one shouldSync parameter); and SyncAwareKeychainStore, which builds its construction pair from one syncEnabled() read through forSync. No remaining path writes the flag and the class from different sources. The removal of WrappedKeyStore.accessibility eliminates the stored-default source entirely, so the split cannot be reintroduced there without reintroducing the property.

One note for the record, not a defect and not holding anything open under this round's scoring: the brief says "all four sites call it," and there is a fifth home for the rule — the inline ternary at KeychainSecretStore.swift:238 (setSynchronizable's target). It is correct — one shouldSync feeds both attributes — but it is the pairing rule written out a second time, and the fix's own reasoning ("writing it correctly a fifth time would have left the shape that produced the defect") argues for converting it to forSync when that file is next touched. The recorded residual (independent accessibility/synchronizable parameters on KeychainSecretStore) is accurately described in the brief.

On the brief's instruction to verify the accepted-not-refused premise rather than take it: I cannot execute against securityd in a read-only round, but three independent observations are consistent only with "accepted" — the round-two-era savingDoesNotRelocateTheRecord stayed green while updating a synced item with a device-only class, theFlagIsAskedAtWriteTime stayed green writing the broken pair, and the new read-back infrastructure reported aku (WhenUnlockedThisDeviceOnly) stored beside synchronizable = true. A refusal would have reddened all three. I accept the premise, and it retroactively settles my own round-two R1 at its second variant: accepted, silently ineligible for iCloud.

S1-27 — yes. addIfAbsent now calls synchronizable() exactly once, at the top, and that snapshot feeds the add's flag, the add's class, and the rollback's target slot; countingBothFlags() reads no preference; there is no second read left in the call for a moving preference to redirect. The same single-read shape now also holds in save's add branch. The rollback can only ever name the slot this call wrote, which is the definition of the fix — and the answer to the author's uncertainty about the snapshot spanning add, count, and delete is that one answer is not merely acceptable but required: the undo must name the written slot, so any "fresh reading" inside this call is the S1-27 defect itself, and the count is flag-agnostic under Any. The hosted test's mechanics check out: the self-flipping closure answers false to the snapshot and true to any later read, so the pre-fix shape deletes the planted synced record and the assertion that it survives goes red — a genuine mutation-anchored test, and the brief's disclosure that its first version passed before the fix (both reads false) was diagnosed and corrected in the right direction.

Question 2: does either fix introduce a new high or medium?

No. The author's four surfaces, checked:

The removed parameter and property: no caller in any target passed or read WrappedKeyStore.accessibility (the accessibility: arguments visible in SyncAwareKeychainStore belong to KeychainSecretStore). The behavior that remains — class derived per write from the flag — is right for every existing caller, since the only production caller is the app store whose entire purpose is that pairing.
forSync shared across both stores: the conflation is correct, because the rule it encodes is a Keychain-semantics constraint (a synchronizable item may not be device-only), not a per-store policy; both stores use exactly these two classes with exactly this meaning, and the item with a genuinely different threat model — the vault key — is a container file, untouched by this type.
The eligibility tests: read back the stored class in both directions off the real Keychain, outside the store, and the collapse-forSync mutation was verified to redden them. They test rather than describe.
A record already written with the broken pairing — this is the one surface with a real answer, and the answer is: it stays wrong. The foreground reconcile calls setSynchronizable(true), which finds by flag = false; the broken record carries flag = true, so the reconcile misses it on every launch, forever. A plain re-enable of sync misses it the same way. syncReport reads the flag, so the one readout reports the record as "in iCloud" while its class keeps it on the device — the loss shape of S1-1, persisting silently on any install that created a vault with sync on between the write-time-preference change and this commit. What does repair it is a full sync off-then-on cycle: the disable finds flag = true, rewrites both attributes as a pair, and the re-enable pairs them again. Nothing detects the mismatch to prompt that cycle. This is damage from the original defect, not something this fix introduced, so it is not a new medium under this question — but it is unremediated history, the population (pre-release, likely including the E-series test phones) is knowable, and the smallest repair is mechanical: teach the reconcile — or syncReport — to read both attributes and, on a flag = true / device-only-class mismatch, update the class in place to forSync(true); an update, no delete, idempotent, in the function that already runs every foreground.

Verdicts: S1-25 fixed, S1-27 fixed, no new high or medium introduced. The one item worth carrying forward is the stranded-record repair above, plus the cosmetic fifth home of the pairing rule.

Grok:
Commit: 07e2972. Findings filed against b3e7e08.

Answers

┌─────────────────────┬────────┐
│                     │ Fixed? │
├─────────────────────┼────────┤
│ S1-25               │ Yes    │
├─────────────────────┼────────┤
│ S1-27               │ Yes    │
├─────────────────────┼────────┤
│ New high or medium? │ No     │
└─────────────────────┴────────┘

S1-25

The incompatible add is the one the Keychain accepts. creatingWithSyncOnIsEligibleForICloud reads kSecAttrAccessible back off a real item; the comment on forSync records that a split pair is stored as "aku" with the sync flag still true. That matches the brief. I did not re-run the test.

Every wrap write that sets both attributes now takes them from one boolean through SecretAccessibility.forSync:

• addIfAbsent (the S1-14 create path)
• save’s add branch
• setSynchronizable on the wrap

save’s update still writes only kSecValueData, so it cannot split the pair. Production account writes go through SyncAwareKeychainStore, which builds KeychainSecretStore with forSync(shouldSync) and synchronizable: shouldSync. KeychainSecretStore.setSynchronizable still inlines the same ternary instead of calling forSync, but both attributes come from the same shouldSync argument, not from two sources.

No fifth write in this store still pairs a live preference read with a stored class. WrappedKeyStore.accessibility is gone; nothing in the app passed it.

Already-written broken items stay broken while the flag already reads true. Reconcile and setSynchronizable(true) search for synchronizable == false. An item written as flag-true / class-aku is not that query, so it is not updated. A successful toggle off then on would rewrite class with the flag. That is leftover data, not a remaining split write.

S1-27

addIfAbsent takes let shouldSync = synchronizable() once and uses that value for the add, for forSync, and for the rollback SecItemDelete. A closure that returns false then true still deletes the local slot this call wrote. countingBothFlags does not read the preference. A fresh read on the delete is what would name the other slot; holding the snapshot across add, count, and delete is the correct undo.

save’s add branch also snapshots once and has no rollback. setSynchronizable uses its parameter, not the closure.

New high or medium

No. One rule for wrap and accounts is the Keychain’s rule, not a mixing of threat models. The snapshot should cover the delete; a second read is the defect. Existing flag-true / class-aku wraps are not repaired by this commit, and that is the residue the brief named, not something the pairing change introduced.
