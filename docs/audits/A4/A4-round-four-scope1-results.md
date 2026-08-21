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

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

GPT:
Round-four verdict
Reviewed a90dd70c856bf4ee53df5f41130f64ac38af751e read-only. The checkout’s only later change is the round-four brief.
Scope 1 is not converging in this round. Trying every wrapped record is sound, but automatically deleting the others converts the previous medium availability defect into a high-severity recovery-record destruction path. The new tests agree with the mistaken definition of “winner” rather than proving it.
High — A valid passphrase selects a wrap, not the wrap belonging to the stored accounts
Files/functions:
[Vault.swift (line 174)](Sources/OpenFactorCore/Vault/Vault.swift:174), unlock(with:)
[WrappedKeyStore.swift (line 112)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:112), discard
[VaultGateModel.swift (line 194)](OpenFactor/Vault/VaultGateModel.swift:194), unlock
[VaultDecisionTests.swift (line 227)](Tests/OpenFactorCoreTests/VaultDecisionTests.swift:227)
The claim at Vault.swift:201 is false: successfully unwrapping a record proves only that the supplied passphrase belongs to that record. Nothing in OFK1 binds the resulting key to the account ciphertext.
Concrete destructive sequence:
Phone A has accounts encrypted under key A, a synchronizable wrap A, and passphrase A.
Phone B has sync disabled. Before wrap A arrives, B creates a second vault with key B, local wrap B, and passphrase B.
The synchronizable accounts and wrap A later arrive. B now has the intended opposite-flag twin: wrap A and wrap B.
Key B opens none of the arriving accounts, so VaultGateModel presents the unlock screen.
The owner enters passphrase B—the passphrase B recently displayed and that genuinely opens wrap B.
Vault.unlock unwraps B successfully, installs key B, and calls discard for wrap A.
WrappedKeyStore.discard deletes the synchronizable wrap A. That deletion can propagate through iCloud Keychain.
Only after Vault.unlock returns does VaultGateModel discover that key B opens no accounts. By then wrap A is gone. Lines 205–210 set hasInstalledAFreshKey and open the list rather than trying another candidate.
The account ciphertext remains under key A, but passphrase A now has no wrapped record to open. After the last device holding key A is lost, the accounts are permanently unrecoverable.
Trying all candidates correctly fixes “the right passphrase was tested against the wrong record.” Deleting every other candidate does not follow from that success and introduces the destructive step.
There is a second deletion hazard: WrappedCandidate includes the record bytes, but the real discard implementation identifies an item only by its sync flag. If the item under that flag changes after candidates() returns, discard(oldCandidate) deletes the replacement, not necessarily the bytes that were examined.
Smallest fix: retain all candidates after a successful unwrap. If automatic cleanup is desired, first prove that the installed key opens the existing account ciphertext. That likely requires returning the selected candidate to a layer that can query SecretStore; delete nothing when there are no records or when all records remain unreadable. The flag-only deletion also needs a stable identity or a compare-and-abort mechanism.
Do the new tests test the code?
Only partly.
The candidate-iteration tests genuinely verify that:
a later candidate is tried after an earlier wrong-passphrase result;
nothing is discarded when no record opens;
malformed data does not outrank evidence that a passphrase was wrong.
The deletion test agrees with the code by construction. It calls one record “stranger” and the passphrase-matching record “mine,” but it creates no account ciphertext with which to establish that distinction. Reversing the entered passphrase would make the alleged stranger win just as successfully and delete “mine.”
The missing regression test is:
Seal an account under key A.
Plant wrap A/passphrase A and wrap B/passphrase B.
Enter passphrase B.
Assert that wrap A is not deleted merely because B authenticated.
The fake also differs materially from the real adapter:
[InMemoryWrappedStore.swift (line 46)](Tests/OpenFactorCoreTests/InMemoryWrappedStore.swift:46) deletes an exact (record, flag) candidate.
[WrappedKeyStore.swift (line 112)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:112) deletes whichever current item carries that flag.
The fake’s save collapses every candidate to one record; the real save updates one kSecMatchLimitOne result and can leave a twin.
The fake cannot inject a candidate-enumeration or discard failure.
The hosted real-Keychain tests cover sync conversion and save behavior, but none exercises the new candidates or discard methods. The package’s VaultTests still skips when the unsigned process lacks Keychain entitlement. Thus the most destructive new adapter behavior has no real-Keychain test.
Other round-four changes
S1-13 — Foreground reconciliation
Retrying on every foreground materially addresses the transient-failure case. A launch-time errSecInteractionNotAllowed is no longer abandoned for the process lifetime.
It still silently ignores every failure, so a persistent failure remains invisible. I would now treat that as a lower-risk residual rather than the previous medium: the operation is retried repeatedly, the hardware experiment establishes the normal success path, and using the Settings toggle surfaces conversion errors. The comments accurately disclose the remaining decision.
One minor discrepancy: the scene-phase handler invokes reconciliation on every phase change, including departure, not exclusively “whenever the app comes forward.” The extra idempotent attempt is not a security defect.
S1-15 — Bounded vault-key read
The bound is fixed. [BoundedFile.swift (line 53)](Sources/OpenFactorCore/Import/BoundedFile.swift:53) opens once with O_NOFOLLOW | O_NONBLOCK, checks the same descriptor with fstat, rejects non-regular files, and reads at most limit + 1. No stat/read race or whole-file allocation remains.
Mapping .unreadable to nil is benign in the normal recovery invariant:
If a wrapped record is readable, the gate becomes .locked, and unlocking safely reconstructs the same key.
If the wrapped store also cannot be read, the gate becomes .unavailable.
A missing wrap plus an unreadable key can produce .absent, but that already requires the recovery record to have been independently deleted or corrupted—availability and integrity the threat model expressly does not claim against a Keychain-writing sibling.
There is nevertheless a false method comment at [VaultKeyStore.swift (line 73)](Sources/OpenFactorCore/Vault/VaultKeyStore.swift:73): nil does not mean only that the device “has not been given” a key; it also means an existing key could not be opened or read.
Hardware evidence
The experiments are useful but narrower than the conclusions around them:
E8 proves one already-synchronized record reached one replacement phone and could be read by an older compatible build. It does not exercise the current multi-candidate reader, twins, Quick Start, restore, or a newly written item’s propagation.
E9 proves one successful reconciliation. It says nothing about the failure path, as the document correctly admits.
E10 proves wrong-key detection and recovery with one current wrap. It does not validate the new choice between two wraps; in fact, it demonstrates why account validation is necessary after installing a candidate key.
I do not treat E8’s immediate result as disproving “iCloud can take up to an hour.” One observation of a record already resident in the Apple Account cannot establish an upper bound. The existing half-hour references describe newly written items or a second device set up during propagation; they should distinguish that from replacement recovery, but they are not refuted as general “can take” statements.
False behavioral claims
These should be corrected, although under the round-four scoring rule they are not independent scope blockers:
[Vault.swift (line 184)](Sources/OpenFactorCore/Vault/Vault.swift:184): “the passphrase decides which one was real.” It decides only which wrap matches that passphrase.
[Vault.swift (line 201)](Sources/OpenFactorCore/Vault/Vault.swift:201): a successful unwrap does not prove which record belongs to the accounts.
[WrappedRecordStore.swift (line 49)](Sources/OpenFactorCore/Vault/WrappedRecordStore.swift:49): the real adapter does not remove one exact candidate; it removes the current item carrying the candidate’s flag.
[VaultDecisionTests.swift (line 245)](Tests/OpenFactorCoreTests/VaultDecisionTests.swift:245): the test’s passphrase proves the wrap opened, not that the other wrap belongs to a nonexistent vault.
[WrappedKeyStore.swift (line 260)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:260) still says load resolves S1-12 by choosing unspecified, although the unlock path now uses candidates.
[VaultKeyStore.swift (line 73)](Sources/OpenFactorCore/Vault/VaultKeyStore.swift:73) understates the reasons load returns nil.
Convergence
Across the full history, the confidentiality design remains sound: no account name or secret has returned to a Keychain attribute; record halves remain separated by the 0x6d/0x73 AAD byte and UUID; listing opens metadata only; the 100-byte wrapped record is length-checked before slicing; and the KDF parameters remain bounded and authenticated.
This round itself is not converging. S1-12 was a medium problem in which a correct passphrase could be rejected because the wrong wrap was selected. The new iteration fixes that, but its cleanup can delete the only wrap for the actual account ciphertext. The same wrapped-key state machine has therefore moved from ambiguity to potential permanent loss, and the accompanying test encodes the incorrect assumption rather than challenging it. Remove or properly validate the discard before closing Scope 1.
I did not build or run tests, as the round-four brief explicitly forbids it. The checkout remained clean.

Fable:
Scope 1, round four — commit a90dd70 (checkout 5808e0a, differing only in the brief)

Same asymmetry on record as every round: this is one continuous conversation across all four of my passes, and the discard I attack below is a mechanism whose absence I effectively endorsed in round three. I re-derived everything from the bytes at this commit.

Summary: one finding that holds the scope open. The S1-12 resolution — try every wrapped record and let the passphrase choose — is correct and sufficient. The discard bolted onto it is built on a false premise, and in the main scenario that produces twins it destroys a live vault's only recovery record, silently, with account-wide propagation when the deleted record is the synced one. The test written for it encodes the same false premise, which is this round's question three answered in the worst way. Everything else in the batch — the foreground reconcile, BoundedFile, the .unreadable-to-nil mapping, the comment corrections — holds up under attack.

The finding: the discard takes a record it has no evidence is dead (High)

Vault.swift:206, WrappedKeyStore.swift:112

The brief says: "Attack the discard. If the removal can take the wrong record... that is the finding this round is for." It can, and the flaw is in the premise, not the mechanics. The comment justifying the discard says the loser is "a record for a vault that no longer exists." The passphrase proves no such thing. It proves which record the typed string opens — nothing about whether the other record's vault is alive.

Walk the main twin-producing scenario, which is the one the code's own comments document (addIfAbsent: a record "can arrive from iCloud minutes or hours after the count"): phone A holds a synced vault (record R_A, key_A). Phone B, sync preference off, taps create during the arrival window; addIfAbsent writes R_B (local, key_B) and counts one because R_A has not landed yet; R_A arrives later. Twins: R_B local, R_A synced — and note this genesis requires differing flags, since two synced items with one primary key are merged by iCloud, not twinned. Both vaults are now live: A's accounts sealed under key_A, B's under key_B, both in the Keychain. B is later reinstalled and unlocks. Whichever passphrase the person types:

They type P_B: winner R_B, loser R_A (synced) → discard deletes it → deletion of a synchronizable item propagates to every device on the account, which this project has itself measured ("a watch emptying fourteen minutes after a sync change", VAULT.md). Phone A keeps working on its container key and is now the state create(with:)'s own documentation calls the silent disaster: "a device that works until it is replaced and then cannot be recovered by anybody." Vault A's accounts — the account's main vault — are permanently unrecoverable the day phone A dies.
They type P_A: winner R_A, loser R_B (local) → deleted. R_B was the only recovery record for vault B, whose accounts sit in the Keychain sealed under a key that existed only in B's wiped container. Those accounts are now permanently unrecoverable.

There is no flag direction that is safe, because in this scenario both records are live vaults' only recovery credentials. Before the discard, the two-vault state was a mess but a fully recoverable one — each passphrase opened its vault, and the new try-every-record unlock made the coexistence permanently harmless. The discard converts "recoverable with the right string" into "destroyed by using the other right string," which is precisely the difference this vault design exists to preserve. To the brief's other question — can it run when the unlock did not succeed — no: it sits after keys.install and before the return, and every failure path exits before it. The mechanics are clean; the target selection is the defect.

The premise holds in exactly one case: a twin that wraps the same vault key (a superseded rewrap, a sync ghost). The code cannot distinguish that case from the two-vault case, because proving "same vault key" requires unwrapping the loser, which requires a passphrase nobody typed.

Smallest fix: discard only losers that failed as notAWrappedKey or iterationsOutOfRange — bytes that are provably not anyone's recovery record — and leave every well-formed wrap in place. The unlock loop already makes surviving twins cost nothing but one extra PBKDF2 derivation per unlock, forever, which is the correct price for never destroying a credential on inference. If tidiness for genuine dead twins is wanted later, it needs evidence (a successful unwrap of both under known passphrases yielding the same key), not the absence of evidence.

Same family, latent (Medium): with twins present, save — the replacePassphrase(with:) path — finds one record under kSecMatchLimitOne and updates whichever it found, unspecified. On open-phone-B with twins, a passphrase change can overwrite vault A's synced record with a wrap of key_B, propagating account-wide: the same destruction through a different door, and it needs no unlock. Latent because nothing in the app calls replacePassphrase yet. Smallest fix: save refuses (or resolves via the caller's known key) when countingBothFlags() > 1.

Question 3: do the new tests test the code, or agree with it?

For the discard, they agree with it, by construction, twice over — and this is the sharpest instance yet of the failure this question exists to catch:

theLoserIsDiscarded (VaultDecisionTests) builds two wraps from BackupPassphraseFixture, each around a fresh random vault key — the test literally constructs the two-live-vaults case — and then asserts the destruction: "one record left." Its doc comment restates the code's false premise word for word ("a wrap for a vault that no longer exists"). The test was written alongside the fix, inherited its author's model, and green-lights the exact behavior I am filing as the finding.
The fake structurally cannot show the blast radius. InMemoryWrappedStore.discard removes an element from an array. The real discard deletes a synchronizable Keychain item, whose deletion propagates to every device on the account. No in-memory fake can represent "this delete reaches phones that are not in the test," so the one property that makes the discard dangerous is invisible to the entire suite by design.

Two further fidelity gaps, lower stakes: the fake's save collapses twins to a single record, where the real save updates one of two and leaves the other — which is what hides the replacePassphrase-with-twins hazard above; and the fake's discard matches on record-plus-flag equality where the real one deletes by flag alone, so a loser whose synced slot was updated by iCloud between candidates() and discard() would have its newer contents deleted — inexpressible in the fake.

To the brief's other structural question — anything else whose only coverage runs through a silently-failing Keychain: yes, the two new primitives themselves. WrappedKeyStore.candidates() and discard(_:) gained no hosted tests (WrappedKeySyncTests was not extended), and the package suite exercises only the fake. So the Keychain implementations of exactly this round's new mechanism — including the flag-keyed delete — currently have no test anywhere that executes them.

The rest of the new tests are good tests: wrongPassphraseAgainstTwins pins that nothing is discarded when nothing opened, rubbishBesideARealWrap pins the best-evidence error, and both would catch real regressions in the resolution half.

Question 1: does each change address its finding?
S1-12, the resolution half — yes, and it is the right shape. Trying every candidate and letting the wrap identify itself removes the "unspecified pick" entirely rather than narrowing it; the best-evidence error reporting (sawWrongPassphrase beating recordNotUnderstood) is correct for the mixed rubbish-plus-real case; derivationFailed aborting the loop is right because CommonCrypto failure is device-wide. Only the discard half is the finding above.
S1-13 — yes. The reconcile now runs on every scene-phase change, which covers the stated failure (Keychain refusing a still-locked device at cold start, retried at the exact moment that stops being true). E9 is direct hardware evidence of the repair working on a device manufactured into the loss shape by the build that caused it, with a clean inference chain (the old build never writes the flag; no toggle was touched). The swallowed error is now an argued decision with the counter-argument recorded and a named place to surface a persistent failure; I accept it, noting the new Debug syncReport readout is what makes it observable at all. One nit, not a finding: the onChange fires on backgrounding too, attempting a Keychain write at a moment it will often fail — harmless, retried, just wasted.
S1-15 — yes, and I confirm the two engines' "benign" verdict on .unreadable → nil, with the reasoning spelled out. For the mapping to mislead destructively, the gate must read absent, which additionally requires the Keychain to answer "no record" while the file read fails. The protection classes move together — a device unlocked enough to read a whenUnlocked Keychain item is unlocked enough to read a .complete file — so the co-occurrence needs genuine file corruption, not a transient. The harmless reading (locked) self-heals: unlock re-derives the same vault key and install overwrites the unreadable file. And behind any residual absent, the human gate plus addIfAbsent still stand. One small ask: the catch { return nil } in VaultKeyStore.load also swallows any future ReadError case; an exhaustive switch would keep this decision visible when the enum grows.
S1-16 — verified for every comment I checked: VaultGateView says four things and records its own history, the refresh doc matches the inverted guard, AccountLabel's header now disclaims the storage bound and points at maximumBytes, and addIfAbsent's comment honestly retracts "microseconds." No new false claims found in these — the one new false claim is the "vault that no longer exists" sentence attached to the discard, which is a comment defect that happens to sit on a code defect, so it travels with the finding rather than the comment floor.
Question 2: did any change introduce something new?

Yes — the discard is this round's instance of the gate's recurring shape: the fix for "unlock picks one unspecified" is correct, and the cleanup stapled to it introduced the round's worst defect, exactly like scope 4's defer. That is the finding above. Beyond it I found nothing new: BoundedFile is the correct one-open-one-bounded-read shape (O_NOFOLLOW/O_NONBLOCK/fstat-on-descriptor, limit enforced by reading limit+1; the only crumb is EINTR mapping to .unreadable, which for this caller degrades to the self-healing locked path), and the unlock loop cannot install a key without a successful unwrap or discard without a successful install.

The hardware evidence, read adversarially as asked

E8, E9, E10 are genuinely the first exercise of all three recovery legs, and their self-stated limits are honest (E8's accidental old build is disclosed rather than re-run; restore and Quick Start remain unclaimed). What they do not establish, beyond their own caveats: all three ran on two devices in one iCloud account on a healthy network, and — the gap that matters most this round — none of them exercises the twin state or the discard. E8 explicitly says nothing on either phone could have shown a second record. The one mechanism whose danger is account-wide propagation of a delete has no hardware evidence and no Keychain-level test; if the discard is kept in any form, the E-series experiment it needs is: manufacture the twin on hardware, unlock, and watch what the other phone's Keychain loses.

The half-hour contradiction: E8 itself draws the right distinction — the old figure measured a freshly written item travelling between live devices; a replacement phone fetches an item already in the account. I checked every surviving citation (Vault.swift:24, WrappedVaultKey.swift:18, WrappedKeyStore.swift:66, VAULT.md:230 and :532, VaultSetupView, VaultGateModel): all describe the same-day-second-device case, which E8 leaves standing, and nothing safety-relevant depends on the number in either direction — the one-record rationale and the creation refusal hold whether propagation takes seconds or an hour. WrappedKeyStore.load's comment is the only one a reader could over-apply to replacement phones; a half-sentence would scope it.

Question 5: converging, or moving around?

Converging on everything previously found; the regression is in new ambition, not old ground. Every prior finding in this scope is now fixed by mechanisms of the right shape, several with hardware evidence, and this round's comment sweep held (the corrections I checked are accurate, including the self-critical ones). What broke the pattern of the last round is that S1-12's fix went beyond its finding: the resolution the finding needed is sound, and the destructive tidy-up nobody asked for is the new defect — the fourth time in this gate a fix has produced the next finding, and the first time the production was avoidable by simply doing less. The instruction that falls out is small and specific: remove or gate the discard (keep it only for unparseable bytes), make save refuse to write into an ambiguous twin pair, put candidates/discard under the hosted suite, and this scope is — for the first time in four rounds — out of findings I can construct a data-loss call order for.

Grok:
Commit reviewed: a90dd70 (checkout 5808e0a differs only by this brief). Round three read 29d62e7, round two 46f65a3, round one 74fe841.

The try-every-wrap half of S1-12 is sound. The discard half is the defect this round asked for.

───

Finding — Medium

A successful unlock deletes every wrap the typed passphrase did not open, including a synchronizable wrap that still belongs to another device.

Where. Vault.unlock after keys.install (Sources/OpenFactorCore/Vault/Vault.swift). WrappedKeyStore.discard deletes by kSecAttrSynchronizable (WrappedKeyStore.swift).

Call order. Two wraps can coexist: this device created locally (addIfAbsent returned true) and the original OFK1 later arrived from iCloud under the other flag. That is the remainder addIfAbsent already admits.

1. Phone A holds vault key K_A, wrap W_A synced, accounts sealed under K_A.
2. Phone B creates during the gap, writes W_B (key K_B, passphrase P_B).
3. W_A arrives. Two items, same service, same account "wrapped", opposite flags.
4. Phone B is open under K_B. Synced accounts are unreadable. suggestsAWrongKey sends it to unlock.
5. The person types P_B — the passphrase this phone just showed them.
6. unwrap opens W_B, install writes K_B, then discard of the loser calls SecItemDelete with kSecAttrSynchronizable = true.
7. W_A is removed from iCloud Keychain and from every device that held the synced copy.

Phone A still has K_A in its container, so it keeps generating codes until that file is gone. A reinstall of A, or a third phone, has ciphertext and nothing to unwrap. The setup copy said a second vault would leave the first unreadable on this device. The delete makes that true for recovery everywhere.

The comment on the loop is the wrong claim: “the other one is a record for a vault that no longer exists.” In this sequence the other one is the wrap for the vault that still exists on phone A.

discard runs only after unwrap and install both succeed, so it does not fire on a failed unlock (wrongPassphraseAgainstTwins is right about that). It fires on a successful unlock under the wrap that should have lost.

What specifically does not save it. Trying every candidate is what fixes “correct passphrase, wrong wrap.” That part does not require a delete. The delete is extra, and it is a synchronizable Keychain delete.

Smallest fix. Do not discard on unlock. Trying every wrap already settles which key to install; a leftover twin is retried the same way next time. If a twin must be removed, remove only a loser whose flag is this device’s own (the one addIfAbsent just wrote), never isSynchronizable == true.

───

1. Does each change address the finding it claims to?

S1-12, the try-all half — yes. candidates() returns every item under kSecAttrSynchronizableAny. A wrap only opens under its passphrase, so P_A still opens W_A even if W_B is first in the array. Rubbish beside a real wrap reports wrongPassphrase rather than recordNotUnderstood when the typed string failed GCM on the real one. derivationFailed still aborts the whole attempt rather than pretending it was a mistype.

S1-12, the discard half — no, for the reason above. Handling “conflict must not outlive unlock” by deleting every wrap that did not open leaves the class open: the wrap that did not open under this string can still be the wrap every other device needs.

S1-13 — yes for the case that was filed. Reconcile now runs from scenePhase .onChange (and still from .task at launch). A Keychain refusal at cold start while the phone is locked is retried when the scene becomes active, which is when whenUnlocked items start answering. It still uses try?. A persistent failure stays off-screen; that is written down as a decision, not an omission. E9 measured the success path only and says so.

S1-15 — the two engines were right that this does not offer create over a live vault. BoundedFile.read with limit: 32 is one open and a 33-byte ceiling; tooLarge / notARegularFile become damaged. .unreadable becomes nil. Vault.state() is:

if (try? keys.load()) ?? nil != nil { return .open }

then wrapped.load(). A nil key and a present wrap is .locked; a throw from the wrap is .unavailable. Neither is .absent. Mapping .unreadable to throw .damaged would not change state(), because try? already turns a throw into “no key.” Create is not offered unless the wrap read returns nil without throwing.

S1-16 — the seven named comments were rewritten. VaultGateView says four things; refresh’s doc matches the inverted guard; AccountLabel no longer pretends 64 graphemes bound storage; addIfAbsent no longer claims a microsecond window or that false means nothing was written.

───

2. Did any change introduce something new?

The discard is that shape: the fix for “load picks one wrap unspecified” was try-all, and the extra cleanup is what can delete the real recovery record. Same family as a defer that started deleting too much once it became reachable.

Reconcile on every phase change, not only .active, is new and probably harmless (setSynchronizable(true) is idempotent; failure is swallowed). It does not create items.

BoundedFile on the vault key is new. A named pipe or symlink at vault.key is damaged, not nil. An EACCES from .complete while the device is locked is .unreadable → nil; if the wrap query also fails, the gate is .unavailable, not setup. I do not see a new create path there.

───

3. Do the new tests test the code, or do they agree with it?

VaultDecisionTests for S1-12 tests Vault.unlock against InMemoryWrappedStore. That fake is a list of WrappedCandidate values. discard removes by Equatable (bytes + flag). WrappedKeyStore.discard deletes by flag only. The tests would not go red if the Keychain delete, given two items that both reported isSynchronizable == false (failed Bool bridge, or a second access group), removed the winner.

addIfAbsent on the fake is guard records.isEmpty. It never adds-then-counts-then-deletes. false on the fake really means nothing was written. The protocol comment now says the Keychain implementation does not promise that. The create-during-arrival test still uses save into a single slot, not plantTwin. So the fake agrees with Vault’s decisions. It does not behave like WrappedKeyStore in the two ways those decisions now depend on: opposite-flag identity, and a delete that is a Keychain primary-key delete.

theLoserIsDiscarded encodes “delete whatever did not open” as the spec. It goes red if you stop discarding. It stays green if discarding is the availability bug.

What else in this scope still only runs through a Keychain call that fails unsigned: VaultTests and KeychainSecretStoreTests (both .enabled(if: KeychainAvailability.isUsable)). WrappedKeyStore.candidates / discard have no hosted test in WrappedKeySyncTests either; that file never calls them. The adapter for the new API is uncovered on the machine that runs the package suite, and uncovered in the hosted sync suite too.

VaultKeyStoreTests hits the filesystem, not the Keychain; those still run.

───

4. Comments and documents that the code does not match

Recorded; not what should keep the scope open.

• Vault.swift and docs/VAULT.md still say iCloud Keychain took close to half an hour to move seven items, and that a second device the same day can read .absent for that long. E8 says a replacement phone saw the wrap on first launch, because the item was already in the account. That does not disprove the seven-item write-then-travel measurement, and E8 itself says the wait is still the right warning for a second device set up the same day. SECURITY.md does not use the figure. What is wrong is treating the half hour as how replacement works; the setup copy is about the other case.
• syncReport still says load resolves a count above one “by picking one unspecified.” unlock no longer does that. load() still does, and state() still calls load().
• Hardware: two phones, one Apple Account, success paths. E8’s reader was TestFlight 1.0 (5). That does not establish restore, Quick Start, a failed reconcile, or two devices creating inside one window (the Debug “2 records” check in the round-three note was not run).

───

5. Converging, or moving around?

The try-all change is inversion again, and it is the right inversion: do not let a one-shot MatchLimitOne settle asynchronously arriving Keychain state. That part should stick.

The discard is moving the problem. Three rounds argued about detecting twins. This round stops detecting and starts deleting. Deleting a synchronizable loser is how a local mistaken create becomes a family-wide recovery loss.

S1-13’s retry-on-foreground is a smaller, correct adjustment. S1-15 is not a fail-open into create. S1-14 and S1-17 remain as listed.

I would not close this scope while unlock still SecItemDeletes a wrap it did not open. Trying every candidate without the delete is the fix that matches the finding.
