# A4 round four, scope 1: the discard, found by all three

Reviewed commit: `a90dd70`, which is `4b8317f`'s ancestor plus the scope 4 brief. Round three read
`29d62e7`, round two `46f65a3`, round one `74fe841`.

## The short version

**A high. All three engines found it, independently, and it is the same one.** Two scored it high
and one medium; recorded here as high, because the outcome is account data that nobody can ever
decrypt again.

**It was introduced this session, by the fix for S1-12, and nobody asked for it.** The finding said
unlock picked one wrap unspecified. Trying every wrap answers that completely. Deleting the wraps
that did not open was added on top, on a premise that is false, and it is the destructive half.

**The test written alongside it asserts the defect as the specification.** It builds two
independent live vaults and then asserts that one of their recovery records is destroyed. That is
the fifth time in this gate a fix has arrived with a passing test written by whoever wrote the fix,
and the most expensive instance.

Everything else in the batch survived attack: S1-13, S1-15 and S1-16 are accepted by all three.

## S1-18 (high): a successful unlock deletes wraps it has no evidence are dead

`Vault.swift:206`, `WrappedKeyStore.swift:112`. Verified here against both.

**The premise is false and it is written in the code.** The comment says the passphrase "has just
proved which record belongs to these accounts, so the other one is a record for a vault that no
longer exists." Unwrapping proves which record *that passphrase opens*. **Nothing in the OFK1
format binds a wrap to the account ciphertext**, so it says nothing about whether the other
record's vault is alive.

The scenario is the one that produces twins in the first place, which the code's own `addIfAbsent`
comment documents:

1. Phone A holds a synced vault: record W_A, key K_A, accounts sealed under K_A.
2. Phone B, sync preference off, creates a vault during the arrival window. `addIfAbsent` writes
   W_B under the local flag and counts one, because W_A has not landed yet.
3. W_A arrives. Two items, same service, opposite `kSecAttrSynchronizable` flags. **Both vaults are
   live.**
4. Phone B cannot read the arriving accounts, so the gate sends it to unlock.
5. The person types P_B, the passphrase phone B recently showed them.
6. `unwrap` opens W_B, `install` writes K_B, and the loop discards W_A.
7. `discard` calls `SecItemDelete` with `kSecAttrSynchronizable = true`. **The deletion propagates
   to every device on the Apple Account.**

Phone A keeps working from the key in its own container, so nothing looks wrong. The day phone A is
replaced, the accounts sealed under K_A have ciphertext and no wrap. `create(with:)`'s own
documentation calls that state the silent disaster: a device that works until it is replaced and
then cannot be recovered by anybody.

**There is no safe flag direction.** Type P_A instead and W_B is deleted, which was the only
recovery record for vault B's accounts, sealed under a key that existed only in a container that
has since been reinstalled.

**Before the discard, the twin state was recoverable.** Each passphrase opened its own vault, and
try-every-record made the coexistence permanently harmless at the cost of one extra derivation.
The discard converts "recoverable with the right string" into "destroyed by using the other right
string".

The mechanics are otherwise clean, and all three checked: `discard` sits after `keys.install` and
every failure path exits before it, so it cannot run on a failed unlock.

**The premise holds in exactly one case**, a twin wrapping the same vault key, and the code cannot
identify that case, because proving it means unwrapping the loser, which needs a passphrase nobody
typed.

### The remedies proposed

- **Grok:** do not discard on unlock at all. A leftover twin is settled the same way next time.
  If one must go, only a loser under this device's own flag, never `isSynchronizable == true`.
- **Fable:** discard only losers that failed as `notAWrappedKey` or `iterationsOutOfRange`, bytes
  that are provably nobody's recovery record. Leave every well-formed wrap.
- **ChatGPT:** retain all candidates. If cleanup is wanted, first prove the installed key opens the
  existing account ciphertext, which means returning the chosen candidate to a layer that can query
  `SecretStore`, and deleting nothing when there are no records or none is readable.

## S1-19 (medium, latent): `save` with twins updates one of them unspecified

Found by Fable. Verified: `save` finds one record with `kSecMatchLimitOne` under `Any` and updates
whichever it found.

With twins present, `replacePassphrase(with:)` can overwrite vault A's synced record with a wrap of
key B, propagating account-wide. **The same destruction through a different door, and it needs no
unlock at all.**

Latent because nothing outside the tests calls it, which this repository confirms: the only callers
of `replacePassphrase` and `prepareReplacementPassphrase` are in `VaultDecisionTests` and
`VaultTests`.

Fable's remedy: `save` refuses when `countingBothFlags() > 1`, or resolves through the caller's
known key.

## S1-20 (low): `discard` identifies a record by its flag alone

Found by ChatGPT and Grok. Verified.

`WrappedCandidate` carries the record bytes, and `WrappedKeyStore.discard` builds a query from the
flag only. **If the item under that flag changes between `candidates()` and `discard()`, the
replacement is deleted rather than the bytes that were examined.** iCloud writing into the synced
slot in that window is exactly how that happens.

The fake does not have this property: it removes by `(record, flag)` equality, so no test can
express it.

## S1-21 (medium): the tests agree with the code, and the fake cannot show the damage

Found by all three. This is question three answered in the worst available way.

**`theLoserIsDiscarded` constructs the two-live-vaults case and asserts the destruction.** Both
wraps come from `BackupPassphraseFixture` around fresh random vault keys. It calls one "stranger"
and one "mine", but nothing in the test establishes that distinction: no account ciphertext exists
to tie either wrap to anything. **Reverse the passphrase typed and the alleged stranger wins and
"mine" is deleted, with the test equally green.** Its doc comment restates the code's false premise
word for word.

The test goes red if you stop discarding. It stays green if discarding is the defect.

**The fake structurally cannot show the blast radius.** `InMemoryWrappedStore.discard` removes an
element from an array. The real one deletes a synchronizable Keychain item whose deletion reaches
every device on the account. No in-memory fake can represent a delete arriving on a phone that is
not in the test, so the single property that makes this dangerous is invisible to the entire suite
by construction.

Three further divergences between the fake and the adapter, each hiding something:

- the fake's `discard` matches on record plus flag; the real one on flag alone, which hides S1-20
- the fake's `save` collapses candidates to one record; the real one updates one and leaves the
  other, which hides S1-19
- the fake's `addIfAbsent` is `records.isEmpty`, so `false` really means nothing was written; the
  Keychain implementation adds, counts, and can undo

**The missing regression test**, which all three describe in nearly the same words: seal an account
under key A, plant both wraps, type passphrase B, and assert that wrap A is still there.

## S1-22 (medium): the new adapter methods have no test anywhere

Found by Fable and Grok. Verified: `WrappedKeySyncTests` never calls `candidates()` or `discard()`,
and the package suite exercises only the fake.

So **the Keychain implementations of exactly this round's new mechanism, including the flag-keyed
delete, are not executed by any test in this repository.** `VaultTests` and
`KeychainSecretStoreTests` are still gated on `KeychainAvailability.isUsable` and skip on the
machine that runs the package suite.

## S1-23 (low, documentation): six claims the code does not make

Recorded, not holding the scope open, and most of them travel with S1-18:

- `Vault.swift:184`, "the passphrase decides which one was real". It decides which one that
  passphrase opens.
- `Vault.swift:201`, a successful unwrap does not prove which record belongs to the accounts.
- `WrappedRecordStore.swift:49`, the adapter does not remove one exact candidate; it removes the
  current item carrying that flag.
- `VaultDecisionTests.swift:245`, the test's passphrase proves the wrap opened, not that the other
  belongs to a vault that no longer exists.
- `WrappedKeyStore.swift:260`, `syncReport` still says `load` resolves a count above one by picking
  one unspecified. `unlock` no longer does; `load` still does, and `state()` still calls it.
- `VaultKeyStore.swift:73`, `nil` does not only mean the device has not been given a key. It also
  means a key exists and could not be read.

## S1-24 (low, documentation): the half hour applied to the wrong case

All three reached the same conclusion, and it is more careful than the claim this project made.

**E8 does not refute the half hour as a general statement.** One observation of a record already
resident in the Apple Account cannot establish an upper bound on propagation, and the surviving
citations describe a newly written item travelling between live devices, or a second device set up
during propagation. Fable checked all six citations and found they all describe that case.

What is wrong is **treating the half hour as how replacement recovery works**. A replacement phone
fetches an item already in the account, which is what E8 measured. `WrappedKeyStore.load`'s comment
is the one a reader could over-apply.

## What survived attack

**S1-13**, the foreground reconcile, accepted by all three. A cold-start Keychain refusal is now
retried at the moment it stops being true. ChatGPT explicitly downgrades its previous medium,
citing the retry, E9's hardware evidence, and the Settings toggle surfacing conversion errors. One
nit from two engines: the handler fires on every scene phase change including departure, so it also
attempts a write at a moment it will often fail. Idempotent, retried, wasted.

**S1-15**, the bounded vault key read, accepted by all three, and all three independently walked
the `.unreadable` to `nil` mapping to check it cannot offer creation over a live vault. It cannot:
`state()` reads `.locked` when a wrap is present and `.unavailable` when the wrap read throws, and
neither is `.absent`. Fable adds that the harmless reading self-heals, since unlocking re-derives
the same key and overwrites the unreadable file. One ask, from Fable: the catch-all in
`VaultKeyStore.load` will swallow any future `ReadError` case, and an exhaustive switch would keep
the decision visible when the enum grows.

**S1-16**, the seven comment corrections, verified individually by Fable and Grok.

**The confidentiality design**, which ChatGPT re-checked across the whole history: no account name
or secret has returned to a Keychain attribute, the record halves stay separated by the AAD byte
and UUID, listing opens metadata only, the hundred byte record is length checked before slicing,
and the KDF parameters stay bounded and authenticated.

## What the hardware evidence does and does not cover

All three read E8, E9 and E10 adversarially, as the brief asked, and all three landed in the same
place: they are the first exercise of all three recovery legs, their stated limits are honest, and
**none of them touches the twin state or the discard**.

E8 explicitly records that nothing on either phone could have shown a second record. So the one
mechanism whose danger is account-wide propagation of a delete has **no hardware evidence and no
Keychain-level test**.

Fable names the experiment it would need: manufacture the twin on hardware, unlock, and watch what
the other phone's Keychain loses.

## Converging?

**Everything previously found in this scope is converging.** Every prior finding is fixed by a
mechanism of the right shape, several with hardware evidence, and the comment sweep held.

**The regression is in new ambition rather than old ground.** Fable's sentence is the one worth
keeping: this is the fourth time in this gate a fix has produced the next finding, and the first
time the production was avoidable by simply doing less. Grok's is the other half: three rounds
argued about detecting twins, and this round stopped detecting and started deleting.

## What was done

### S1-18: the discard is gone, structurally

`unlock` deletes nothing. The loop tries every candidate, installs the one the passphrase opens,
and returns. The comment now states the premise correctly and the price accepted: **a surviving
twin costs one extra derivation per unlock, forever, and that is the correct price for never
destroying a credential on inference.**

**The remove operation was taken off the protocol entirely**, not guarded. `discard(_:)` no longer
exists on `WrappedRecordStore`, `WrappedKeyStore`, or the fake, and the protocol says in as many
words that there is no remove operation on purpose. That closes S1-20 with it: a flag-keyed delete
cannot take the wrong record if there is no delete. A structural removal is stronger than a guard,
because reintroducing the defect requires designing the API back into existence rather than
deleting a line.

Grok's remedy was taken over Fable's narrower one. Discarding provably-unparseable rubbish was
also declined, because the only delete primitive available identifies a record by its sync flag,
and iCloud writing into that slot between the read and the delete would remove a record nobody
examined. Rubbish beside a real wrap costs nothing but a skipped iteration.

### S1-21: the test now asserts the opposite of what it asserted

`theLoserIsDiscarded` is replaced by `aSuccessfulUnlockDeletesNothing`, which builds the same two
live wraps and unlocks with **each** passphrase in turn, asserting both records survive both times.
The doc comment records what the old test did and why all three engines rejected its premise.

### S1-19: a replacement into a twin pair is refused

`save` counts both flags before finding anything to update, and throws the new
`SecretStoreError.twinnedRecord` when two records exist. The error's description tells the person
the truth: nothing was changed, and unlocking with the passphrase still works. The fake now mirrors
the refusal instead of collapsing the pair, which is the fidelity gap round four named.
`replacementRefusesTwins` pins the vault-level behaviour: the change is refused and neither record
is touched.

### S1-22: the adapter is under the hosted suite

`WrappedKeySyncTests` gained three tests that run against the real Keychain: `candidates()` returns
both twins each under its own flag, a `save` into a twin pair is refused **and both records survive
byte for byte**, and a write follows the sync preference as it stands rather than as it started.
The twin is planted with a raw `SecItemAdd` under the opposite flag, which is what iCloud
delivering one does. **The refusal guard was mutation tested against the real Keychain**: removing
it reddens `savingIntoTwinsIsRefused`.

### S1-14: the sync flag is a question, not a snapshot

`WrappedKeyStore` holds `@Sendable () -> Bool` and asks it at each write, the same shape as
`ProvisioningDesk.Conditions.hasVault` and for the same reason. The app passes a closure over
`UserDefaults`, so enabling sync and creating a vault in one session writes the wrap under the
setting as it stands, not as it stood at launch.

### S1-17: a code that fails to generate is a signal

`AccountListViewModel` reports the transition into failure, once per failure rather than once per
tick, and the app wires it to `gate.refresh()`. The gate re-reads the records fresh, so one broken
account among working ones changes nothing, and a list where nothing is readable moves to the
passphrase prompt instead of drawing dashes until the next backgrounding.
`codeFailureSignalsOnce` pins both halves.

### The rest

- **S1-23**: all six false claims corrected. Three vanished with the discard; `syncReport`,
  `VaultKeyStore.load`, and the unlock comment now say what the code does.
- **S1-24**: the half hour is scoped to a freshly written item reaching a second device, with the
  replacement case stated separately and E8 cited.
- **Fable's ask**: `VaultKeyStore.load` catches exhaustively, so a future `ReadError` case must be
  classified on purpose rather than silently becoming "no key".
- **The reconcile nit from two engines**: it now runs only when the scene becomes active, not on
  the way to the background.

470 core tests pass, the full hosted suite passes, both apps build.

## Where the scope stands

Nothing above low is open. S1-18 through S1-24 are fixed or corrected; what remains for round five
to read is this batch, which includes the removal of a mechanism a previous round shipped.
