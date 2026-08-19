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

**Review commit for round three: `71d3ee6`.**

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
