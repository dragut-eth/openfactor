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
