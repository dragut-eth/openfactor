# A4 round five, scope 1: the removal holds, and the flag I fixed lost its protection class

Reviewed commit: `b3e7e08`, delivered as checkout `cc1afc6`, which adds only the brief. Round four
read `a90dd70`, round three `29d62e7`, round two `46f65a3`, round one `74fe841`.

## The short version

**The high is gone and all three engines say so without qualification.** `unlock` deletes nothing,
the remove operation is off the protocol, and reintroducing it means designing an API back into
existence past a doc comment recording why it went. Fable: the first fix in this gate that
subtracted code instead of adding it.

**Declining Fable's narrower remedy was right, and Fable says so itself**, in the sharpest sentence
of the round: the proof is about the bytes examined, the only available delete names a slot, the
Keychain has no compare-and-delete, so **the fix was unimplementable as specified**.

**But S1-14's fix is defective, and two engines found it independently.** Making the sync flag a
question left its protection class behind. That is a medium.

**Two more real problems in the same file**, both about the twin state the removal deliberately
made permanent: a passphrase write that still has a race, and a rollback delete that reads the
preference a second time.

**And the twin state has almost no way to be seen or escaped**, which is where Fable spent its
attack and found the round's other new item.

## S1-25 (medium): a synchronizable record is written with a device-only protection class

Found by ChatGPT and Grok independently. Verified here.

`addIfAbsent` now asks `synchronizable()` at write time, which was the fix. It still writes
`accessibility.attribute` beside it, and the app constructs the store without overriding the
default `.whenUnlockedThisDeviceOnly`. So when the preference is on, the add requests
`kSecAttrSynchronizable = true` together with an accessibility value ending in `ThisDeviceOnly`.

**Apple documents that pairing as unsupported.** A synchronizable item may not carry a
device-only class.

The route is exactly the one S1-14 named: erase from the locked screen with sync still on, create
again, `create(with:)` calls `addIfAbsent`, the closure returns true.

**Neither engine could tell from the code which way it fails, and both consequences are defects.**

- **The add is refused.** Creation reports the gate's generic "could not be set up; try again",
  every retry uses the same incompatible attributes, and Settings sits behind the vault gate so
  there is no in-app way to turn sync off. Setup is permanently blocked after an erase.
- **The add is accepted.** The wrap is ineligible for iCloud while every account syncs, which is
  S1-1, the finding this whole scope opened with, on the exact path S1-14 named.

**The correct pattern already exists forty lines away.** `setSynchronizable` writes both attributes
together, with a comment saying a synchronizable item cannot be device-only by definition. The two
add paths do not.

**The new test cannot catch it.** `theFlagIsAskedAtWriteTime` reads back only
`kSecAttrSynchronizable`. It would stay green in the accepted case. Both engines say the hosted
test must read back both attributes.

`save`'s add branch has the same pair.

## S1-26 (medium, latent): the twin refusal is count-then-select

Found by ChatGPT; named by Fable as an accepted residual.

`save` guards on `countingBothFlags() <= 1` and then performs a **separate**
`SecItemCopyMatching` under `Any` with `kSecMatchLimitOne`. Between them a record can arrive from
iCloud, and the match then returns one of two, unspecified, and `SecItemUpdate` overwrites it with
a wrap of the caller's key.

**If that was the synced record for the other live vault, its only recovery credential is replaced
account-wide.** That is S1-19's outcome, through the window rather than through the door.

ChatGPT's remedy: fetch `candidates()` once, require exactly one, and update under that
candidate's captured flag rather than performing a second selection.

Fable accepts the same window as a narrowing, noting it has no 600ms derivation inside it, and
scores it a residual rather than a finding. **The fake cannot express the difference**: it holds
one lock across count and replacement, and the hosted test plants the twin before `save`, so both
tests agree with the static guard and neither sees the race.

## S1-27 (low, latent): the rollback delete reads the preference a second time

Found by ChatGPT. Verified, and it is the sharpest thing in the round.

`addIfAbsent` calls `synchronizable()` for the add, and **calls it again** to build the rollback
delete. Between the two, the preference can change.

1. The first read is false, so the call adds local wrap `W_B`.
2. Synced live wrap `W_A` is present, so the count is two.
3. The preference changes to true.
4. The rollback query now names the **synchronizable** slot and deletes `W_A`, not `W_B`.
5. `addIfAbsent` returns false, so `create` does not install `K_B`. The surviving `W_B` wraps a key
   nobody uses, and `W_A`, the recovery credential for the accounts that exist, is gone everywhere.

**This is S1-20, the flag-keyed wrong-record delete, reintroduced through the rollback**, in the
same commit whose protocol comment says there is no remove operation on purpose. The comment is
about `discard`. The `SecItemDelete` in `addIfAbsent` was never in scope and is still there.

Low because the Settings path writes the preference only after a successful conversion, and a twin
should make conversion fail. **But the store now accepts a mutable concurrent closure**, so the two
reads cannot be assumed equal on principle rather than on luck.

Remedy: snapshot once at the top and use it for both the add and the rollback. A test whose closure
returns different successive values should assert the pre-existing record survives byte for byte.

## S1-28 (low to medium): the twin state breaks the sync toggle permanently, and one direction overstates protection

Fable's F1, and the item the brief's "attack the absence" question was for. Grok reached the same
place and said it could not tell what the collision returns; Fable answers it.

Twins are one record under each flag. `setSynchronizable(true)` finds the local one and updates its
flag, **which collides with the synced record's primary key**. `SecItemUpdate` returns
`errSecDuplicateItem` and the store throws `.duplicate`, not `.twinnedRecord`.

- **Enabling sync**: `SyncAwareKeychainStore` moves the wrapped key first, so the throw precedes
  any account conversion and the state stays consistent. The toggle fails with
  "Sync could not be changed. Some accounts may not have moved, so try again." **Trying again fails
  forever.**
- **Disabling sync**: accounts convert **first**, then the wrapped move throws. The preference flips
  only after success, so it stays reading "on" while every existing account is already device-only.
  **The switch now claims accounts are offered to iCloud when they are not.** New accounts sync,
  old ones do not, and retrying re-fails forever.

The launch reconcile hits the same collision on every foreground and swallows it, permanently.

**The honest `twinnedRecord` description exists forty lines from the code that should throw it and
never will.** Fable's remedy: a twin pre-flight in `setSynchronizable` throwing `twinnedRecord`,
run before converting accounts on the disable path, and let `message(for:)` pass that description
through instead of advising a retry that cannot succeed. That would also give the twin state its
first non-Debug visibility.

## S1-29 (low): the refusal's message is incomplete, and has nowhere to appear

All three engines. `twinnedRecord` says nothing was changed and unlocking with your passphrase
still works. Both true.

**In a replacement flow it can be read as saying the newly shown passphrase works. It does not.**
ChatGPT's version: say the existing passphrase or passphrases still work, the new one was not
saved, and OpenFactor cannot change a passphrase while both records remain.

Grok adds that it does not say the change is impossible until something outside the app removes a
wrap. Fable adds the reachability point: the one place a person in this state actually collides
with the pair today is the sync toggle, which throws a different error.

## S1-30 (low): test gaps the round named

- `theFlagIsAskedAtWriteTime` checks the Boolean only, and misses S1-25 entirely.
- Nothing hosted covers `setSynchronizable` under twins, which is where S1-28 lives. **The missing
  test and the missing fix are the same work item.**
- Nothing pins that an unparseable record survives a successful unlock, so Fable's own declined
  round four variant could be reintroduced without any test objecting. The decision was made in
  prose; a test would make it executable.
- `theFlagIsAskedAtWriteTime` exercises `addIfAbsent`'s closure read and not `save`'s add branch.

## What survived attack

**The removal, unanimously.** Grok: the property test is the right evidence for a missing
mechanism, because there is no line to revert. Fable: enforced twice independently, by the compiler
and by a test built on the exact two-live-vaults state, asserting survival **in both directions**,
which matters because round four's destruction was direction-dependent.

**The fake, this time.** Fable's reasoning is the one to keep: a fake edited alongside the code
stops being circular **when the real store is held to the same property in the same commit**. The
mutation-tested hosted test is the anchor. Both engines note the remaining unanchored divergence,
`addIfAbsent`'s add-count-undo, which the fake cannot express.

**The two non-mutation-tested hosted tests test rather than describe.** Fable's structural argument:
`candidatesSeesBothTwins` plants its premise through raw `SecItemAdd`, independent of the adapter,
and asserts the count **before** the adapter is asked anything, so a broken `candidates()` cannot
vouch for itself.

**The list-to-gate signal, unanimously, with no re-entrancy.** The gate only reopens the list on
evidence the codes work, and the list only signals on evidence they stopped. Grok adds a
pre-existing limitation it inherits: `hasInstalledAFreshKey` forces `keyOpensNothing` false, so
after an unlock that installed a wrap which does not open the accounts, the dashes stay for the
rest of the process. Fable adds a cost note: N rows failing in one tick fire N refreshes, each a
full `records()` read on the main actor.

**Reconcile on `.active` only**, and the carried-forward round four asks: the exhaustive catch in
`VaultKeyStore.load`, and the half-hour comment now distinguishing propagation from a resident
record.

## The recovery walk, which the brief asked for

All three walked it and agreed on the arrow.

**Nothing that was recoverable before this commit is unrecoverable now.** At `a90dd70`, typing one
passphrase destroyed the other live vault's only recovery credential, account-wide when the loser
was synced. At `b3e7e08` every path short of a deliberate authenticated erase preserves both. Grok:
the discard was the thing that made a live wrap unrecoverable.

**At most two records can accumulate.** The primary key admits exactly two flag values, `save`
refuses an observed pair, and conversion can collide but cannot create a third.

**Fable found the evidence-based route out that the brief asked whether one exists**, and it uses
only shipped mechanisms: export vault B's accounts on B, export vault A's on A, erase once, create
one fresh vault, import both archives. Every account survives and the twin state ends. It costs
deliberateness, which is the correct price.

**What the owner still cannot do**: change either passphrase, flip the sync toggle, get the app to
pick a winner, or see the word "twin" anywhere outside the Debug readout. ChatGPT proposes a
minimum: let the owner discard only the installed container key and return to the passphrase
screen, so each vault can be reached without touching either wrap.

## Converging?

**All three say yes, and materially safer than round four.**

- **Fable: qualitatively different.** Every previous round's fixes added mechanism and twice the
  added mechanism was the next round's finding. This round's principal fix is a removal enforced by
  the type system. **Second consecutive round in which it can construct no call order that loses
  data.** What is left is legibility, not destruction.
- **Grok: converging, and the first round in this scope that got there by removing.** Would not
  close while create-with-sync-on splits the flag from the protection class, and while reconcile
  can still write into a twin pair.
- **ChatGPT: converging and materially safer, but do not close.** The write-time synchronization
  path is invalid and the save refusal still has a twin-arrival window.

**Two of three say do not close. Nobody says the scope is stuck.**

## What was done: S1-25, and S1-27 with it

### The test answered the question neither engine could

Both returns said the incompatible add would either be **refused** or **accepted**, and that both
outcomes were defects, and that the code could not tell you which. The hosted test settles it:

**It is accepted.** The Keychain reported the stored class as `"aku"`,
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, on an item written with
`kSecAttrSynchronizable = true`. So the flag says leave and the class says stay.

That is the worse of the two, and it is worse than either engine described. Nothing syncs, while
every account does, which is S1-1, the finding this scope opened with. **And `syncReport` reads the
flag back and reports the record as synced**, so the one readout that exists to make this visible
would have said it was fine. `theFlagIsAskedAtWriteTime` passed throughout, exactly as ChatGPT
predicted it would.

### The rule now has one home

The pairing was written out at four sites. `setSynchronizable` had it right, `SyncAwareKeychainStore`
had it right for the accounts, and the two add paths split it. **Writing it a fifth time at the two
broken sites would have left the same shape that produced this.**

`SecretAccessibility.forSync(_:)` is the rule, and all four sites call it. A reviewer checks it
once.

**`WrappedKeyStore`'s stored `accessibility` was removed rather than left.** With the class derived
from the flag it chose nothing, and a constructor parameter that is silently ignored is the kind of
false affordance this gate keeps finding in prose. No caller passed it.

### S1-27 came with it, and could not honestly be left

The fix requires `let shouldSync = synchronizable()` so the flag and the class come from one
answer. Once that local exists, leaving a second `synchronizable()` call three lines below to build
the rollback delete would be deliberate: a preference that moved in between names the other slot,
and the undo deletes the record that was already there instead of the one this call just wrote.
That is a flag-keyed deletion of a record nobody examined, which is the shape removed from `unlock`
one commit earlier. One snapshot serves the add and the undo.

**This is one medium and one low that share the same lines, not a batch.** The rule from the post
mortem was one medium per commit, and that holds.

### The tests, and one of them was wrong first

Three hosted tests against the real Keychain: creating with sync on is eligible for iCloud,
creating with sync off stays on the device, and a preference that moves mid-call cannot redirect
the undo.

**The third passed before the fix, which is how I found it was wrong.** Its closure read the
preference before flipping it, so both reads returned false and the undo hit its own record for the
right reason by accident. Corrected to answer false once and true afterwards, it goes red.

Both mutations verified applied before running: collapsing `forSync` to always device-only reddens
the eligibility test, and restoring the second `synchronizable()` call reddens the undo test.

**A residual, stated rather than fixed:** `KeychainSecretStore` still takes `accessibility` and
`synchronizable` as independent parameters, so the pair can still be split at that boundary. Its
one caller uses `forSync` now. Changing that signature is outside this finding.

482 core tests pass, the app suite passes, both targets build.

## What was done: S1-26

**One read decides both things.** `save` counted the records and then asked separately which one to
update. Those are two reads of a store another device writes into, so a record arriving between
them is invisible to the count and can be what the second question returns. `candidates()` now
answers both from a single query: how many there are, and which flag the one to write carries. The
update is pinned to **the flag that was observed**, not to whatever a fresh query would return.

A record arriving after the read lands under the other flag and is therefore not this write's
target. If the observed record has gone, the update finds nothing and fails, which is the honest
outcome: what the call meant to replace is no longer there.

ChatGPT's remedy, taken as filed. The alternative it offered, withdrawing passphrase replacement
until a targeted operation exists, was not needed once the operation could name its target.

### The test needed a seam, and the seam is the point

**A non-racy test cannot tell the two versions apart.** Both write the same record when nothing
changes underneath, so a test that does not express the arrival is green either way, which is the
failure this gate has found repeatedly.

`WrappedKeyStore` gained an internal `duringSave` closure, `nil` on every shipping path, reached
through an internal initialiser only tests can call. It runs in the gap between reading the store
and writing to it, which is exactly where this store's worst defects have lived.

**Adding a seam to production code was a deliberate trade.** The argument against is that a hook
exists for tests rather than for the app. The argument for it is this gate's own central finding:
untestable code is where defects pool, and this project has paid for that twice already, once in a
vault suite that never ran and once in a fake whose `save` could not represent a twin. A property
nothing can express is a property nothing can hold onto.

The test makes the seam do what iCloud reconciliation does: the observed record is gone and a
different one is present under the opposite flag. **Deterministic in both directions**, which
matters because the underlying defect depends on an unspecified choice. Before the fix, the planted
stranger came back carrying this call's 31 bytes instead of its own 33. After it, the stranger is
untouched and the write fails.

Mutation verified applied: restoring a second query for the target reddens it.

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

Grok:
Commit reviewed: b3e7e08 (checkout cc1afc6 adds only this brief). Round four read a90dd70.

The high is gone. Trying every wrap without deleting is the fix that matches S1-18. What remains is a twin pair that nothing in the app resolves, and a write that still does not keep the sync flag and the protection class together.

───

1. Does each change address the finding it claims to?

S1-18 — yes. unlock installs and returns. There is no discard on the protocol, the Keychain type, or the fake. Reintroducing a delete into that loop would have to invent an API that was removed. aSuccessfulUnlockDeletesNothing plants two wraps around two random keys, unlocks with each passphrase, and asserts recordCount == 2 both times. That is the property the old test inverted.

Declining Fable’s narrower delete was the right call. A notAWrappedKey loser is still identified by isSynchronizable. iCloud can write a live wrap into that slot between candidates() and a flag-keyed SecItemDelete. That was S1-20. Without a delete-by-bytes primitive, any remaining remove is the same class as the high. Absence is what closes it.

S1-19 — yes, for save. countingBothFlags() <= 1 runs before the one-item match. The hosted test plants a real opposite-flag item, saves, and checks both byte strings survived. The comment says removing the guard reddens it.

S1-14 — the flag, yes; the class that has to travel with it, no. synchronizable is now @Sendable () -> Bool, asked at addIfAbsent and at save’s add path, same shape as ProvisioningDesk.Conditions.hasVault. OpenFactorApp passes { UserDefaults.standard.bool(forKey: PreferenceKey.syncEnabled) }. Enable sync and create in one session, the wrap is added with kSecAttrSynchronizable = true.

The add still uses the stored accessibility, default .whenUnlockedThisDeviceOnly. setSynchronizable is the one place that writes flag and class together. Create-with-sync-on therefore SecItemAdds a synchronizable item with a this-device-only class. Apple documents that pairing as unsupported.

Two outcomes, both defects, and I cannot tell which from the code:

• The add is refused. After erase-from-locked with sync still on, setup cannot write a wrap, and Settings sit behind an open vault, so the switch cannot be turned off. Dead end.
• The add is accepted. The hosted write-time test only reads the sync flag, so it would stay green while the wrap is ineligible for iCloud: accounts sync, wrap does not. That is S1-1 on the exact path S1-14 named.

theFlagIsAskedAtWriteTime would not catch this. Smallest fix: at each add, derive accessibility from synchronizable() the way setSynchronizable already does.

S1-17 — yes, and the new call path does not loop. refreshCode signals only when codeFailure goes from nil to set. One permanently broken row fires once; suggestsAWrongKey is readable.isEmpty && !unreadable.isEmpty, so mixed lists stay open. All-unreadable moves the gate to locked and unmounts the list. refresh() during a tick does not reload the list unless the stage changes. I do not see re-entrancy that generates codes again from the same signal.

Reconcile only on .active — yes. The handler still fires on the way to the background; the write does not.

S1-20 — closed with the API. There is no flag-keyed delete left on unlock.

───

2. Did any change introduce something new?

A twin pair persists until erase. Two boolean flags ⇒ at most two items under this service and account (one per flag), unless another access group still holds a leftover wrap. addIfAbsent is still the writer that can produce the pair: add, count, maybe undo. save will not add a third; with count 1 it updates the one it finds. I did not find a path that turns two into three under the query unlock uses.

Degradation beyond one extra PBKDF2 per unlock:

• Passphrase change is refused for as long as the pair exists.
• setSynchronizable / the launch reconcile are not twin-aware. Foreground with preference on looks up the local wrap and tries to flip it to sync. If a sync wrap is already there, that is a primary-key collision. I do not know whether securityd returns duplicate (swallowed by try?, pair remains) or merges into the iCloud item (the other vault’s wrap is overwritten, which is S1-18 through a door that needs no passphrase). That write is the one that still guesses.
• delete() still uses kSecAttrSynchronizableAny. Erase from the locked screen removes both wraps, and the synced one leaves every device. That matches “erase with sync on removes what iCloud holds,” which the erase copy already warns about for accounts. It is also the only in-app way out of the pair, and it is not a resolution with evidence: it destroys both credentials.

The list→gate signal can be a no-op after unlock has already installed a wrap that does not open the accounts. hasInstalledAFreshKey then forces keyOpensNothing false, so dashes stay for the rest of the process. That flag predates this round; the signal inherits it. Force-quit clears it. Not a new loop; a pre-existing “do not ask again” that also blocks S1-17 in that session.

I do not treat the permanent pair itself as a new high. Leaving both wraps is what round four asked for. The new surfaces that can still destroy are the twin-unaware setSynchronizable and erase-deletes-both, the first unverified, the second user-initiated and labelled.

───

3. Do the new tests test the code, or agree with it?

Unlock removal — the property test is the right evidence for a missing mechanism. There is no line to revert. Two live wraps, both passphrases, both counts stay 2. Put a delete back and both halves go red. That is sufficient to show Vault.unlock no longer removes records, which is what the high was.

It still cannot show iCloud propagation, because the fake is an array. That is acceptable here: the defect was the call, and the call is gone.

Fake save was edited in the same commit. It now refuses when records.count > 1, same predicate as countingBothFlags(). replacementRefusesTwins would fail if the fake still collapsed the pair. The hosted savingIntoTwinsIsRefused is the one that actually plants an opposite-flag Keychain item and mutation-tests the adapter. Together those are a model plus a host test, not only agreement. The fake still does not model addIfAbsent’s add-count-delete, nor write-time preference (it always inserts isSynchronizable: false). Those gaps are the same class as round four, just not the discard class.

Hosted tests:

• savingIntoTwinsIsRefused — tests the adapter; the brief says the guard was reverted and it went red.
• candidatesSeesBothTwins — would fail if candidates still used MatchLimitOne. It tests the adapter even without a recorded mutation.
• theFlagIsAskedAtWriteTime — would fail if init captured synchronizable() once. It tests S1-14’s flag and is silent on accessibility, which is the hole above.

───

4. Is this converging?

Yes, and this is the first round in this scope that got there by removing a mechanism rather than tightening it. Round four’s high was new ambition on a correct try-all. This commit keeps try-all and drops the delete. That is better than a90dd70. It is not worse than 29d62e7: passphrase change is stricter (refuses twins instead of updating one unspecified), unlock is better (tries every wrap), recovery records stay.

The leftover is the pair itself: created by addIfAbsent’s remaining window, survived forever, passphrase change bricked, no evidence-based resolution. That is a smaller surface than a delete that propagated. I would not describe the scope as stuck. I would not close it while create-with-sync-on still splits flag and protection class, and while reconcile can still write into a twin pair.

False claims, recorded only: load() is still MatchLimitOne over Any; syncReport says so honestly. twinnedRecord’s user string says unlocking still works and that nothing was changed. It does not say passphrase change is impossible until something outside the app removes a wrap.

───

5. The recovery walk

Two iPhones, one Apple Account, two wraps, both vaults live. Phone A: W_A synced, key K_A, accounts under K_A. Phone B created in the gap: W_B local, K_B, then W_A arrived.

What they can do

• Type P_A on either phone: candidates() returns both, unwrap opens W_A, K_A is installed, neither wrap is deleted. Accounts sealed under K_A generate. Phone B will look “wrong-key” for B’s own accounts if any exist only under K_B.
• Type P_B: same, other direction. W_A remains in iCloud. Phone A still has K_A in its container and still generates. A later reinstall of A can still unwrap W_A.
• Unlock again later with the other string: still works; the extra PBKDF2 is the whole ongoing cost.
• Erase on one phone with sync on: accounts and both wraps go, including the other vault’s recovery record. That was already the cost of erase-with-sync; it is now also the only in-app exit from the pair.

What they cannot do

• Change the vault passphrase. save throws twinnedRecord. prepareReplacementPassphrase still returns a string; replacePassphrase(with:) is what refuses. There is still no production screen on that path.
• Get the app to pick a winner. Nothing proves a wrap against account ciphertext. Nothing deletes with evidence.
• Rely on reconcile to “fix” the pair. It may no-op or collide; it must not be how the pair is resolved.

Unrecoverable now vs before this commit

Before b3e7e08, typing P_B deleted W_A from iCloud. Phone A kept working until its key file vanished, then the accounts under K_A were ciphertext with no wrap. After this commit that does not happen. Nothing they hold is unrecoverable that was recoverable at a90dd70. The discard was the thing that made a live wrap unrecoverable.

The remaining bind is: they can live with two recovery records forever, or they can erase and destroy both. That is worse UX than a conflict screen with evidence. It is not worse cryptography than deleting on inference.

Fable:
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
