# A4 round two, scope 1: what three engines found in the fixes

Round two of scope 1 read `46f65a3`. The account it responded to is `A4-round-two-scope1.md`, and
all three engines returned.

**Two engines walked out the same high finding independently, and all three found the same
medium.** That is a higher agreement rate than round one of this scope produced, where no finding
at all was reported by all three.

| Engine | Verdict |
| --- | --- |
| ChatGPT 5.6 Sol | One high, three medium, two low. "Creation remains destructively racy" |
| Grok 4.6 | Two of eleven incomplete, five surviving false claims |
| Fable 5 | Nine of eleven hold, one plausible medium, and a coverage claim it could not verify |

## The high finding, found twice

`create(with:)` asked `state()` whether a record existed, then ran `WrappedVaultKey.wrap` at
600,000 PBKDF2 iterations, then called `save`, which replaces whatever it finds. **A wrapped
record arriving from iCloud during the derivation was overwritten by a wrap of a brand new vault
key**, and every account already sealed under the old one became unopenable by anybody, including
somebody holding the correct passphrase.

Grok put the cost of the gap precisely: hundreds of milliseconds, during which `VaultGateModel`
also holds `isWorking`, so `refresh()` returns early and the gate cannot see the arrival either.

**The test written for that fix could not see it**, because `InMemoryWrappedStore`'s record never
changed between the check and the write. Both engines said so. That is the sharpest thing either
found: the fix had a test, the test passed, and neither fact meant what it appeared to.

Creation now uses `addIfAbsent`, a write that refuses to replace anything. The fake gained a
`duringWrite` hook that does what iCloud does at the worst moment, and the test built on it fails
against the old shape.

## The medium all three found

`refresh()` guarded the passphrase screen with `state == .absent` and nothing else, so a transient
read failure returning `.unavailable` replaced the screen and discarded the only copy of a
passphrase somebody was in the middle of writing down. Nothing is lost from the vault, because
nothing has been written; the person is left holding a string that opens nothing.

The rule is stated the other way round now, which is also how the documentation states it: leave
the screen only on evidence that the displayed passphrase must be abandoned, meaning a record or a
key. **Fable also pointed out the fix had no test at all**, and that the round two account claimed
otherwise, which is a claim-versus-reality defect in its own right. There are three tests now, in
the app target, where that fix lives.

## What each engine found alone

**ChatGPT: the label limit counts characters, not bytes.** A grapheme cluster carries any number of
combining marks, so `"a"` plus fifty thousand combining acute accents is one `Character` and a
hundred kilobytes, and passed the sixty four character bound untouched. Measured before fixing:
one character, 100,001 bytes. There is a byte ceiling now, set at four kilobytes from measuring
the most expensive graphemes people actually type. The first value tried was 1,024, which is below
what sixty four family emoji occupy, and the existing grapheme test caught it immediately.

**Fable: `save` writes the wrong protection class onto a synced record.** The update carried this
store's construction-time `whenUnlockedThisDeviceOnly` onto a record that `setSynchronizable(true)`
had moved to iCloud and to `whenUnlocked`. Either securityd refuses it, or the record sits
device-only while flagged as syncing, which is the silent withholding this store exists to
prevent. Filed as plausible rather than confirmed, because settling it needs a device. Only the
value changes now.

**Grok: creation always wrote `synchronizable: false`.** The app built its vault with the default
store, so the toggle path was fixed and the create path was not. Erase from the locked screen with
sync on, create again, and the wrap is local while every new account syncs, which is the original
total-loss shape reached by a different tap. The wrap now takes the current preference.

**Fable, the same fact from the other side:** a device that enabled sync before this all began is
sitting in the loss shape now and nothing prompts its owner to toggle anything. There is an
idempotent reconcile at launch, following the precedent this scope already set when reading a key
began repairing how it was stored.

## Everything else

The one-shot `replacePassphrase()` is no longer public. A PBKDF2 failure no longer reports as a
wrong passphrase, which was the same category error as finding 9 in miniature. The iteration-count
route into `recordNotUnderstood` has its own test, which Grok noticed it lacked.
`creatingRefusesWhileUnreadable` expects a specific error rather than any error, which Fable
noticed would pass for the wrong reason.

Five documentation claims that survived the last pass are gone: listing has returned the item's
data since the metadata moved into it, so the `kSecReturnData` sentence was false in two places;
nothing is cleared on a conversion that does not exist; and the vault has four states, which the
page, the header and two comments still called three.

**Round three reads the tip of `a4-fixes`.** Everything above was fixed; what to attack is below.

**One scope 1 file has changed since these fixes, and it did not come from this scope.** While
closing scopes 3 and 4, a sweep went through every whole-file read in the project looking for the
same mistake those scopes kept producing, a bound applied after the allocation it claims to
prevent. `VaultKeyStore.load` was the last one and it was closed anyway, although it reads a file
this app writes into its own container: it now asks the file system for the size and reports
`damaged` above the key size before reading. Eight lines, and the only in-scope difference between
the commit the fixes landed on and the tip.

## For round three

Four questions, the fourth being round three's own.

1. **Does each change address the finding it claims to?** Round two answered no twice for round
   one's fixes, both times because a check sat too far from the thing it was checking. Look for
   the same shape again.

2. **Did any change introduce something new?** Creation now takes a different write path from
   every other caller, the label clamp has two stages, and the app reconciles a Keychain item at
   launch.

3. **Does any comment or document now claim something the code does not do?** Round two found five
   surviving false claims after a pass that said it had removed them all. Assume there are more.

4. **Is this converging?** Say plainly whether the defect surface is shrinking. Round two of this
   scope found a high-severity defect in a fix that had a test, where the test could not see the
   defect it was written for. That is the failure mode to weigh.

**Where to look hardest.** `addIfAbsent` narrows a race rather than eliminating it, and says so:
the Keychain add is atomic against a same-flag duplicate and not against an opposite-flag twin,
which is why it counts afterwards and undoes its own write. That is the least satisfying thing in
this batch.

`AccountLabel.clamped` has a second stage that keeps unicode scalars when a single grapheme
exceeds the whole budget. What it renders as is deliberately not considered.

The launch reconcile writes to the Keychain on every cold start when sync is on. It is claimed to
be idempotent and quiet.

And `VaultGateModel.refresh` has now been changed twice in two rounds, both times for the same
screen, which is the pattern that preceded every other repeat finding in this gate.

---

## ChatGPT 5.6 Sol

*Read-only pass over commit `46f65a3`. Reproduced as returned, with absolute paths made
repository-relative.*

> Reviewed commit `46f65a39051ba7cd73fd6a420777aa5d2faf22ae`; round one read `74fe841`. The change account names `a7f9121`, but the scoped implementation is unchanged between `a7f9121` and `46f65a3`.
>
> Several fixes are sound, but creation remains destructively racy, the refreshed setup state can still discard a passphrase, and the new label bound is bypassable.
>
> ### High — Creation still overwrites a wrapped key that arrives after the initial check
>
> Item 6 claims creation refuses when a wrapped record is already present. It checks only before deriving the new wrap; the persistence operation remains replacement-capable.
>
> Concrete call order:
>
> 1. A new device calls `create(with:)`; `state()` reads no wrapped record and returns `.absent`.
> 2. `WrappedVaultKey.wrap` starts its 600,000-iteration PBKDF2 operation.
> 3. The old synchronized `OFK1` record arrives from iCloud.
> 4. `wrapped.save` now finds that record.
> 5. Because `save` is an upsert, it executes `SecItemUpdate` and replaces the arrived record with the newly generated wrap.
> 6. `keys.install` installs the new random vault key.
> 7. Existing `OFV1` account records remain sealed under the old key, while its only wrapped copy has been replaced and that replacement may sync outward.
>
> The new test cannot catch this: its fake record remains static between `state()` and `save()`. It tests "present before creation begins," not "arrives during creation," which is the race the comments claim to close.
>
> The twin fix has the same structural gap: look-before-add is not atomic against an iCloud item arriving between the query and `SecItemAdd`, especially because differing synchronization flags form distinct Keychain identities.
>
> Smallest fix: give `WrappedRecordStore` a creation-specific, non-replacing operation distinct from `save`. `Vault.create(with:)` must use it, and encountering any record at commit time must return `.alreadyExists`. The Keychain implementation must also detect the opposite-sync twin case; a simple query followed by an add does not provide that guarantee.
>
> ### Medium — A transient read failure still clears the only copy of a displayed passphrase
>
> The new guard preserves `.showingPassphrase` only when `vault.state()` returns `.absent`. Concrete call order:
>
> 1. On a fresh device, the model generates a passphrase and stores its only copy in `.showingPassphrase`.
> 2. The user switches applications to save it.
> 3. Returning activates the scene and calls `refresh()`.
> 4. A transient Keychain read error makes `vault.state()` return `.unavailable`.
> 5. The guard does not apply, so `stage` becomes `.unavailable` and the passphrase is destroyed.
> 6. "Try again" later returns to setup, where a different passphrase is generated. The user may retain the first string, which opens nothing.
>
> No vault has yet been written, so this does not destroy accounts, but it recreates the exact harmful state the change describes: a person holds a recovery credential that was discarded without explanation. The comment immediately above the implementation is also false.
>
> Smallest fix: while showing a passphrase, preserve the stage for both `.absent` and `.unavailable`; leave it only for `.locked` or `.open`, which are affirmative evidence that the displayed passphrase must be abandoned.
>
> ### Medium — The new 64-character label limit does not bound stored bytes
>
> The new limit counts Swift extended grapheme clusters, not Unicode scalars or encoded bytes. A grapheme cluster can contain an arbitrary number of combining marks. A concrete bypass is `61 cc 81 cc 81 cc 81 ... cc 81`: ASCII `a` followed by repeated U+0301 COMBINING ACUTE ACCENT. Swift treats the entire sequence as one `Character`, so `text.count` is 1 and `clamped` returns every byte unchanged.
>
> A hostile import can therefore still produce hundreds of kilobytes or megabytes of JSON metadata, which is then padded, encrypted, placed in one Keychain item, and potentially offered to iCloud. It also invalidates the justification in `AccountLabel` that "sixty-four of even the most expensive graphemes is still trivially small," and means the at-rest length is not confined to the documented ordinary one-, two-, or three-bucket classes. A planted account can be recognized later from its extreme sealed length.
>
> Smallest fix: retain the user-facing grapheme limit, but add an encoded-byte ceiling after truncation.
>
> ### Low — The unsafe one-shot passphrase replacement remains public
>
> The safe two-step API was added, but the original method still generates, persists, then returns. A process kill after persistence and before display still leaves the old recovery credential invalid and the new one unknown. There is currently no production call site, so this is a public API footgun rather than a reachable app failure today. Smallest fix: remove or make the one-shot method test-only/internal.
>
> ### Low — The claimed documentation cleanup is incomplete
>
> Several false behavioral claims remain: `docs/VAULT.md` and `VaultRecord.swift` say listing sets `kSecReturnData` to false, while `KeychainSecretStore.records` correctly sets it to true because encrypted metadata is in the value; `KeychainSecretStore.swift` still says `kSecAttrGeneric` is "cleared on conversion," despite there being no converter; `VaultGateModel.refresh` says it does nothing while a passphrase is displayed, but the implementation changes state for `.locked`, `.open`, and `.unavailable`; and `VaultGateView` and `docs/VAULT.md` still say the gate shows "one of three things," but `.unavailable` is now a separate rendered outcome.
>
> ### Fix-by-fix assessment
>
> 1. Wrapped-key synchronization: addressed. 2. Watch `.complete` protection: addressed for new writes. 3. Sync twins: steady-state handled, arrival race remains open. 4. Backup-exclusion window: addressed. 5. Read errors versus absence: addressed. 6. Creation refusal: incomplete because check and replacement are separate operations. 7. Refreshing while showing a passphrase: incomplete for `.unavailable`. 8. Replacement passphrase ordering: the production-safe API exists, but the unsafe public one-shot remains. 9. Future-version wrapped records: addressed. 10. Documentation mismatches: partially addressed. 11. Padding disclosure: the ordinary bucket leakage is now described, but the new character bound is not a byte bound.
>
> The metadata/secret AEAD separation and PBKDF2 construction remain sound for the reasons from round one. I did not run tests because that would create build artifacts, contrary to the read-only requirement.

---

## Grok 4.6

*Read-only pass over commit `46f65a3`. Reproduced as returned.*

> Commit reviewed: 46f65a3 (vault code is that of a7f9121; the two later commits are documentation only). Round one read 74fe841.
>
> **1. Does each change address the finding it claims to?**
>
> Most of them do. Two do not finish the class they name.
>
> Item 6 is incomplete. `create(with:)` now refuses when `state()` is already `.open` or `.locked`. That stops the case the tests write: a wrap that is sitting there before the call. It does not stop a wrap that appears during the call.
>
> `WrappedVaultKey.wrap` is 600,000 iterations of PBKDF2. That is hundreds of milliseconds between the check and save. `VaultGateModel.createVault` sets `isWorking = true` first, and `refresh()` returns immediately while that flag is set, so an arrival in that window is not seen by the gate either.
>
> `save` is specified to replace whatever it finds. On the Keychain implementation it looks, then `SecItemUpdate`s the value in place. Call order if iCloud delivers the real wrap during the KDF: `state()` → `.absent`; `wrap(...)` runs; the arrived OFK1 item is now in the Keychain; `save` finds it and overwrites `kSecValueData` with a wrap of a new vault key; `create` returns success. `alreadyExists` is never thrown.
>
> `WrappedRecordStore.save`'s contract is "replacing any earlier one." `InMemoryWrappedStore.save` does exactly that and has no way to refuse. `VaultDecisionTests` never inserts a record between `state()` and `save`. The reported case is green; the class is open.
>
> Smallest fix that actually closes it: create must not go through a replacing save. Add-only (`SecItemAdd`, no update), or a second load immediately before save that refuses if anything is there. The check has to be on the write, not hundreds of milliseconds earlier.
>
> Item 1 is incomplete on the write that creates the item. The toggle path is fixed. The create path is not. `OpenFactorApp` still builds `Vault(keys: keys)` with a default `WrappedKeyStore()`, whose `synchronizable` is false. A first save therefore always `SecItemAdd`s a device-only wrap.
>
> First-run is saved by the UI: Settings sit behind an open vault, so the user creates first (local wrap) and later flips the switch (conversion). The leftover is erase-from-locked then recreate. `VaultUnlockView` deletes the accounts, then `destroyVault()`. `syncEnabled` is not cleared. The next `create(with:)` writes a local wrap again. New accounts are added through `SyncAwareKeychainStore` with the preference still on. Ciphertext leaves; the wrap does not, until someone toggles a switch that already reads "on." That is the original failure, reached by a different tap.
>
> Smallest fix: the wrap `Vault` writes has to take the current preference, the same way new accounts do.
>
> **2. Did any change introduce something new?**
>
> The create/save race above is not new machinery so much as the item-6 fix making the old overwrite reachable in a shorter window. Enabling wrap sync is what makes an arriving wrap possible at all; they knew that, which is why 1 and 3 were meant to land together. 3 stops twinning on a later save. It does not stop replacing the arrived wrap on create.
>
> Item 5's fourth state is real and the unavailable screen does not offer create. I did not find a path that treats `.unavailable` as `.absent`.
>
> Item 7's new condition does what it claims for the two states that matter. If `state()` is `.unavailable` while a passphrase is on screen, `refresh()` now leaves that screen and drops the string. That contradicts both the new comment and `docs/VAULT.md`. The test that exists only covers still-absent.
>
> Item 4's staging directory plus `replaceItemAt(..., .usingNewMetadataOnly)` plus a load-time repair is more moving parts than the old write-then-mark. The properties it claims are the ones the new tests can see on macOS. Protection class is still unmeasurable on the test host; that is stated.
>
> **3. Does any comment or document now claim something the code does not do?**
>
> Yes. `docs/VAULT.md` still says creation "refuses outright when a record is already there, so the destructive tap cannot land." The tap can still land. The same page still says `records()` "sets `kSecReturnData` to false on every listing path"; it sets it to true. `KeychainSecretStore`'s header table still says `kSecAttrGeneric` is "cleared on conversion." `Vault.swift`, `VaultGateView`, `VaultGateModel.refresh`, and `VAULT.md` still talk about "three states" / "one of three things." There are four. `WrappedKeyStore.exists` is still `(try? load()) != nil`.
>
> **VaultDecisionTests**
>
> The change account is right that this is the first place to attack, and right that until this commit the vault's decisions had no test that runs.
>
> What it cannot see, because `InMemoryWrappedStore` is one optional `Data` with a replacing save and no sync flag: twinning; create overwriting a wrap that arrives after `state()`; the wrap's `kSecAttrSynchronizable`; and `refresh()`, which lives in the app target.
>
> `WrappedKeySyncTests` covers 1 and 3 against the real Keychain, and is skipped on the same unsigned host that skipped `VaultTests`. So the decisions that run here are the ones that do not need the Keychain. The two that still destroy a wrap if they are wrong are only half-covered.
>
> That is not a reason to throw the suite out. It is a reason not to treat a green `VaultDecisionTests` as proof that items 1 and 6 are closed.
>
> **Item 6 on upgrade**
>
> The worry in the change account does not fire. An existing install is `.open` or `.locked`. Neither is offered create, and both now throw `alreadyExists` if something called it anyway. I do not see a phone that cannot set itself up because of this check.
>
> **4. Is this converging?**
>
> The eleven, verdict by verdict: 1 toggle path yes, create path still writes `synchronizable: false`. 2 yes. 3 yes on the Keychain type. 4 yes, as far as a Mac test can see. 5 yes in `Vault.state()` and the new screen; header and docs still say three states. 6 only if the wrap is visible before `wrap()` runs. 7 stays when still absent, leaves when locked; arrival-while-showing is not tested and the comment overclaims. 8 yes. 9 yes, tested for garbage bytes but not for a bad iteration count. 10 service and UUID case corrected, encoder sorts, two leftover false comments. 11 documentation only, and accurate.

---

## Fable 5

*Read-only pass over commit `46f65a3`. Reproduced as returned, with absolute paths made
repository-relative.*

> One deviation to record before anything else, since the method file says to record asymmetries rather than hide them: the round-two prompt calls for a fresh conversation, and this is the same conversation that produced round one. I am the engine grading its own suggested fixes with its own round-one reasoning in context. I have re-read every changed file from the bytes rather than from memory of what I asked for, but the reader should weigh that structural bias.
>
> Summary: nine of the eleven fixes do what they claim, and several go further than asked (the repair-on-read for the protection class, the read-back on backup exclusion). Two do not survive scrutiny: the twin fix in `WrappedKeyStore.save` preserves the sync flag but clobbers the accessibility that must travel with it, and the `refresh()` fix does not implement the rule its own documentation states. The round-two account also claims test coverage for one fix that I cannot find a test for.
>
> **R1 — Medium (latent today). `save`'s update path preserves the sync flag but forces a device-only protection class onto a synced record — verdict: PLAUSIBLE**
>
> The twin fix carefully reads the existing record's `kSecAttrSynchronizable` and matches on it so the record neither twins nor moves. But the change dictionary still contains `kSecAttrAccessible: accessibility.attribute`, which is the store's construction-time value — `whenUnlockedThisDeviceOnly` for `Vault`'s default `WrappedKeyStore()`. So a save into a record that `setSynchronizable(true)` previously moved to iCloud (and to `whenUnlocked`, because "a synchronizable item cannot be device-only by definition" — that code's own comment) updates a synced item to a ThisDeviceOnly accessibility class. Apple documents ThisDeviceOnly accessibility as unsupported on synchronizable items.
>
> Two outcomes are possible and both are defects: `errSecParam`, meaning passphrase change fails whenever sync is on; or the update is accepted and the record sits in a device-only protection class while flagged synced — a state whose practical meaning is that the only recovery record is silently withheld from iCloud, which is precisely the harm the fix's own comment forbids.
>
> Why PLAUSIBLE rather than CONFIRMED: I cannot execute against securityd in this review. The hosted test `savingDoesNotRelocateTheRecord` exercises exactly this shape, which rules out the `errSecParam` variant on the simulator — but the suite reads back only the sync flag and never `kSecAttrAccessible`, so the accepted-with-wrong-class variant passes it unseen. Reachability today is test-only, because nothing in the app calls `replacePassphrase` yet; it goes live with the passphrase-change screen the two-step fix exists to serve.
>
> Smallest fix: carry the found item's `kSecAttrAccessible` into the update exactly as the sync flag is carried (or omit accessibility from the changes entirely and leave both halves to `setSynchronizable`). Then add an accessibility read-back to `WrappedKeySyncTests`.
>
> **R2 — Low/Medium. The `refresh()` fix does not implement the rule its documentation states**
>
> The account says: "It now moves away when a record has actually arrived, and leaves the screen alone otherwise." The code guards only `.absent`. A `state()` of `.unavailable` — a transient Keychain error at exactly the moment a scene becomes active — falls through the switch and replaces `.showingPassphrase` with `.unavailable`, discarding the generated string. That is the screen-cleared-under-somebody's-pen case the account's own "where to look hardest" section names, triggered by the one state whose defining property is "we don't know" rather than "a record arrived."
>
> Smallest fix: invert the guard to match the stated rule — while showing a passphrase, move away only when `state == .locked`, and return otherwise.
>
> **R3 — Low. The fix in R2 has no test, which contradicts the account's coverage claim**
>
> The account states: "Every fix was then reverted a second time, and the new suite caught each one." For item 7 I cannot find the test that would go red. `VaultGateModelTests` asserts the screen survives a refresh while the device is absent — that passes with the old unconditional early return too. No test creates a record behind a showing passphrase and asserts the stage moves to `.locked`; no test covers `.showingPassphrase` + `.unavailable`; no gate-level test covers the `.unavailable` stage at all. Reverting `refresh()` to the round-one shape leaves every suite green as far as I can trace. The fix is real, but it is in the exact condition the whole round-two account warns about: argued for in a comment and verified by nobody — and this time the account affirmatively claims otherwise, which is a claim-versus-reality defect in its own right under round two's question 3.
>
> **R4 — Low. The sync fix governs the next toggle, not the state existing devices are already in**
>
> `SyncAwareKeychainStore.setSynchronizable` is called only from the settings toggle. A device that enabled sync before this commit is sitting in the exact loss-shaped split the fix describes — accounts synced, wrapped key local — and stays there until its owner happens to toggle sync again, which nothing prompts them to do. This commit itself demonstrates the pattern for already-written state: `VaultKeyStore.load()` now repairs the protection class and backup exclusion of keys written under the old rules, on the explicit reasoning that "the device that most needs the fix is the one that already worked." The wrapped record got no equivalent reconcile-on-read. Smallest fix: on launch, if the preference says synced and the record's flag says local, run `wrapped.setSynchronizable(true)`; it is already idempotent.
>
> **R5 — Low. A false comment the fix said it removed still stands, in the second place it was made**
>
> Item 10 removed the "converted" sentence from VAULT.md, but `KeychainSecretStore.swift` still says `kSecAttrGeneric` holds "nothing. Never written, and cleared on conversion." Nothing converts and nothing clears. Round one flagged both instances; the fix removed one.
>
> **The eleven, verified**
>
> Fixed, with the mechanism checked rather than the intention: 1 (modulo R4's existing-device gap), 2 (the fix goes further than the finding, with `repairProtection` on every `load()`), 3 (right for the flag, wrong for the accessibility that rides with it, which is R1; two residuals: existing twins are not repaired, and look-then-add is not atomic), 4 (fixed; two informational residuals, `destroy()` does not sweep `PendingKeys`, and the sweep would race a second concurrent `install`), 5 (fixed at the vault layer; the gate-layer mapping has no test), 6 (fixed), 8 (fixed at the API; nothing in the app calls either yet, which is the right order), 9 (fixed; one crumb, `derivationFailed` still reports as `.wrongPassphrase`, blaming the user for a CommonCrypto error), 10 (fixed except R5), 11 (accurate; the arithmetic checks out).
>
> 7, the blinded refresh — half fixed. The dangerous direction is closed twice. But the implemented condition is broader than the stated rule, which is R2, and the fix carries no test, which is R3.
>
> **The new test infrastructure, attacked as instructed**
>
> `InMemoryWrappedStore` is faithful to the protocol for what the decisions consume. The assertions in `VaultDecisionTests` are mostly sharp: they check the record's bytes and the key's bytes survived a refused creation, not merely that an error was thrown. Two soft spots: `creatingRefusesWhileUnreadable` expects `(any Error).self`, so it would pass if creation refused for the wrong reason; and the fake cannot fail on `save`, so every decision downstream of a write failure — including the record-before-key ordering that the whole recovery story rests on — remains covered only by the Keychain-gated suite that this commit proved never runs on the test machine. That ordering is now the most consequential unverified decision left in this scope. The claim that moving the gap into the storage adapter is an improvement is fair; the claim that the suite caught every reverted fix is not, per R3.
>
> For triage: R1 is the one to resolve before the passphrase-change screen ships, and it takes a device or simulator run to settle which of its two variants is real. R2's fix is one changed condition plus the two missing tests. R4 is one idempotent call at launch. R5 is a deleted half-sentence. Nothing found this round weakens the at-rest confidentiality claim; like round one, everything lives in availability and recovery, which for an authenticator is where the bodies are buried.
