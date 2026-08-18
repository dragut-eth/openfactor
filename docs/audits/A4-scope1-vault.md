# A4, scope 1: the vault at rest

Gate A4 round one, the scope covering what a device holds at rest and what an attacker who reads
it learns. The prompt is `docs/audits/A4-prompts.md`, preamble plus Scope 1, unchanged.

**Commit under review: `74fe841`.** Three engines run this scope independently, in fresh
conversations, and each pass is recorded here whole as it arrives.

**One edit is made to every pass published here, and it is the only one.** Absolute paths from
the reviewing machine are rewritten as repository-relative. Nothing else is trimmed, softened, or
reordered, including the parts that turn out to be wrong.

| Engine | Status |
| --- | --- |
| ChatGPT 5.6 Sol | Returned, below. Triaged |
| Fable 5 (high effort) | Returned, below. Triaged |
| Grok 4.6 | Not yet run |

---

## ChatGPT 5.6 Sol

*Read-only pass over commit `74fe841`. Reproduced as returned.*

> Reviewed commit `74fe84168180ce103cae32f6708acf0da93dbfef` read-only. I found one high-severity
> recovery defect, three medium-severity persistence/failure-path defects, and several
> specification mismatches.
>
> ### High — The wrapped recovery key never syncs
>
> Files/functions: `Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:30` (`WrappedKeyStore.init`),
> `Sources/OpenFactorCore/KeychainSecretStore.swift:208` (`setSynchronizable`),
> `OpenFactor/Settings/SyncAwareKeychainStore.swift:94` (`setSynchronizable`),
> `OpenFactor/OpenFactorApp.swift:45` (`init`).
>
> `WrappedKeyStore` defaults to `synchronizable: false`. The app constructs `Vault(keys: keys)`
> without overriding that default. Enabling sync calls `KeychainSecretStore.setSynchronizable`,
> whose service is the account service; neither it nor `SyncAwareKeychainStore` touches the
> wrapped-key service.
>
> Concrete failure:
>
> 1. Create a vault. The `OFK1` item is saved local-only.
> 2. Enable sync. Each `OFV1` account item becomes synchronizable, but the `OFK1` item remains
>    local-only.
> 3. Lose or replace the phone.
> 4. The new device receives all account ciphertext but neither the random vault key nor its
>    wrapped representation.
> 5. The correct passphrase cannot help: it derives only the wrapping key, and there is no
>    wrapped vault key to decrypt.
>
> This defeats the recovery design and can turn device loss into permanent loss of every synced
> account.
>
> It directly contradicts `docs/VAULT.md:391`: "kSecAttrSynchronizable on the account items and on
> the wrapped key record, both following the user's preference, flipped in place by
> SyncAwareKeychainStore".
>
> Smallest fix: add an in-place synchronizability update for the wrapped-key item and make the
> settings operation update both services. On enabling sync, update the wrapped key before the
> accounts, and do not persist/display the enabled state until both operations succeed.
>
> ### Medium — The watch vault key is not explicitly written with `.complete` protection
>
> File/function: `Sources/OpenFactorCore/Vault/VaultKeyStore.swift:98` (`install`).
>
> The platform condition includes watchOS, but delegates the actual options to
> `SharedInbox.writingOptions`. That helper supplies `.completeFileProtection` only under
> `os(iOS)`; on watchOS it returns only `.atomic`.
>
> Thus the watch build does not request the protection class that the comments and
> `docs/VAULT.md:102` require: "Protection class `.complete` … on watchOS it follows wrist-lock."
>
> If the watch's inherited/default class is weaker, the raw 32-byte vault key remains readable
> after first unlock despite wrist-lock. The omission is certain; I did not establish the target
> watchOS default class from the scoped source, so I am not claiming a demonstrated extraction.
>
> Smallest fix: give `VaultKeyStore` its own writing options and select
> `[.completeFileProtection, .atomic]` for iOS, watchOS, and any other supported data-protection
> platform. Verify the resulting class on watch hardware.
>
> ### Medium — A crash can permanently leave the raw vault key eligible for backup
>
> File/function: `Sources/OpenFactorCore/Vault/VaultKeyStore.swift:98` (`install`).
>
> The persistence order is: atomically write the raw key at line 111, then mark it excluded from
> backup at lines 121 to 124.
>
> If the process is killed between those operations, or `setResourceValues` throws, the complete
> key file remains installed without the exclusion. Because later `state()` sees a valid key,
> normal startup does not retry the missing attribute. A subsequent backup can therefore contain
> the raw vault key, contrary to "Vault key … Backed up: Never." and "The vault key is … never
> backed up."
>
> An unencrypted local backup containing both the application data and Keychain material would
> then defeat the passphrase separation the exclusion is intended to preserve.
>
> Smallest fix: stage the key in a dedicated backup-excluded directory, or set and verify
> exclusion on a temporary file before atomically installing it. No successfully installed key
> should ever predate its exclusion.
>
> ### Medium — A Keychain read error is treated as "no vault," enabling destructive replacement
>
> Files/functions: `Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:82` (`exists`),
> `Sources/OpenFactorCore/Vault/Vault.swift:51` (`state`),
> `Sources/OpenFactorCore/Vault/Vault.swift:87` (`create(with:)`),
> `Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:93` (`save`).
>
> `exists` implements `(try? load()) != nil`, collapsing every Keychain failure, including
> `errSecInteractionNotAllowed`, a transient availability error, or an unexpected result, into
> "absent." `Vault.state()` likewise suppresses key-file errors.
>
> Concrete failure:
>
> 1. A reinstall has no container key, but its old wrapped-key item still exists.
> 2. `WrappedKeyStore.load()` temporarily fails, so `state()` reports `.absent`.
> 3. The interface offers creation.
> 4. The Keychain becomes available before `create(with:)`.
> 5. `SecItemAdd` reports a duplicate; `save` responds by updating that existing item with a newly
>    wrapped, unrelated key.
> 6. The new key is installed, while all existing account records remain encrypted under the old
>    key. The old wrapped key, and hence the only recovery route, has been overwritten.
>
> Smallest robust fix: creation must use an add-only operation that refuses `errSecDuplicateItem`;
> reserve upsert/replacement for explicit passphrase replacement. Storage errors should also
> produce an unavailable/error state, never `.absent`.
>
> ### Specification discrepancies — Low
>
> The normative document and source contain several exact false claims:
>
> * `docs/VAULT.md:134` specifies account service `"app.openfactor.vault"`;
>   `Sources/OpenFactorCore/KeychainSecretStore.swift:79` uses `"app.openfactor.accounts"`.
> * The document says metadata JSON keys are sorted, but `encode` at
>   `Sources/OpenFactorCore/KeychainSecretStore.swift:608` uses a default `JSONEncoder` without
>   `.sortedKeys`.
> * `docs/VAULT.md:152` and `VaultRecord`'s header at
>   `Sources/OpenFactorCore/Vault/VaultRecord.swift:24` say `records()` sets `kSecReturnData`
>   false; `records()` at `Sources/OpenFactorCore/KeychainSecretStore.swift:503` necessarily sets
>   it true and decrypts only the metadata half.
> * `KeychainSecretStore`'s table at `Sources/OpenFactorCore/KeychainSecretStore.swift:14` says
>   `kSecAttrGeneric` is "cleared on conversion," while the normative document explicitly says no
>   converter exists.
>
> These do not currently expose a secret, but the document calls itself byte-exact and normative.
> The smallest fix is to reconcile each statement with the intended implementation.
>
> ### What resisted attack
>
> * No issuer, account name, or OTP secret is stored in a Keychain attribute. Account items expose
>   a UUID, constant service and label, access group, sync/accessibility state, and system
>   timestamps.
> * Enumeration reveals the exact account count because there is one item per account. Padding
>   cannot hide that. It hides lengths only to buckets: an `OFV1` record is
>   `68 + metadataBucket + secretBucket` bytes, with each bucket a multiple of 128. The common
>   case is therefore 324 bytes; unusually long metadata or secrets reveal their bucket.
> * Metadata and secrets are cryptographically separated. Their AAD differs by `0x6d` versus
>   `0x73` and includes the raw account UUID, preventing half substitution and cross-account
>   substitution. Listing retrieves the combined ciphertext but opens only the metadata half;
>   metadata updates copy the secret ciphertext verbatim.
> * Wrapped-key parsing checks the exact 100-byte length before slicing. Salt and iteration count
>   are authenticated as AAD; iterations are clamped before PBKDF2.
> * A generated passphrase has 120 bits of entropy. A random 32-byte salt, 600,000 PBKDF2-HMAC-SHA256
>   iterations, and a fresh AES-GCM nonce provide no shortcut beyond ordinary offline guessing,
>   which remains infeasible at that entropy.
> * Malformed, unknown-version, or undecryptable account records are reported individually as
>   unreadable rather than making readable accounts disappear.
>
> I did not run the test suite because doing so would create build artifacts in the repository,
> contrary to the read-only constraint. No repository files were modified.

### Triage

Every finding was checked against the code before being accepted. **All eight confirmed, none
rejected.** That is the second consecutive cold review with no false positives, which is a fact
about the method worth recording alongside the findings.

**High, the wrapped key never syncs. Confirmed, and the most serious defect this project has
had.** `WrappedKeyStore` defaults `synchronizable: false` at
`Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:34`, the app takes that default, and
`KeychainSecretStore.setSynchronizable` operates through `baseQuery()`, whose
`kSecAttrService` is the accounts service. Nothing in the repository ever writes
`kSecAttrSynchronizable` for `app.openfactor.vault.key`.

Two aggravating details the pass did not have to find. `docs/VAULT.md` promises the opposite in
its Sync section, and the property's own comment three lines above the default says it "follows
the account items" and that a device syncing accounts without the means of reading them "would be
a device that syncs nothing usable". The code contradicts a comment directly above it.

The consequence is total, silent, and only discovered at the worst moment: enable sync, lose the
phone, and the replacement receives every account as ciphertext with no wrapped key for the
passphrase to unwrap. The encrypted export is the only surviving recovery path.

**Medium, the watch protection class. Confirmed, and it is a regression introduced on
2026-08-18.** `VaultKeyStore.install` guards with `#if os(iOS) || os(watchOS) || os(tvOS)` and
then calls `SharedInbox.writingOptions`, which yields `.completeFileProtection` only under
`os(iOS)`. When macOS began refusing that option, the write was pointed at the shared helper
without noticing the helper's platform condition was narrower than the branch enclosing it. The
watch writes the key with `.atomic` alone, beneath a comment claiming `.complete`.

**Medium, install ordering. Confirmed.** The key is written and then excluded from backup, so a
crash between the two, or a throw from `setResourceValues`, leaves a valid key with no exclusion.
Nothing retries, because `state()` sees a valid key and asks no further questions.

**Medium, errors collapsing to absent. Confirmed, and it is a second path to total loss.**
`exists` is `(try? load()) != nil`, and `save` answers `errSecDuplicateItem` by updating the
existing item. A transient read failure therefore leads the interface to offer vault creation,
and accepting that offer overwrites the wrapped key that every stored account depends on.

**Low, all four specification mismatches. Confirmed exactly as reported.** The service constant,
the absent `.sortedKeys`, the `kSecReturnData` claim that the two-halves design deliberately
replaced without the document following, and a comment referencing a converter the design says
does not exist.

---

## Fable 5, high effort

*Read-only pass over commit `74fe841`. Reproduced as returned, abridged only where noted.*

> **F1 — Medium. `Vault.replacePassphrase()` writes the new wrap before anyone has seen the new
> passphrase.** `Vault.swift:130`.
>
> `docs/VAULT.md` states the invariant: "No vault exists without its passphrase having been shown
> and acknowledged." The doc comment on `Vault.create()` explains exactly why the one-shot shape
> is dangerous and why the interface takes the two-step path. `replacePassphrase()` is the same
> one-shot shape with no two-step alternative: generate, save the wrap under the new passphrase,
> and only then return the string. The old passphrase is dead at the save. If the process dies or
> the view is torn down before the string reaches the screen, the device stays `open` so nothing
> looks wrong, and the user's written-down passphrase now opens nothing. They discover it at
> recovery time on a new device. This is strictly worse than the creation case the project
> already fixed, because a working recovery credential is invalidated rather than merely never
> issued.
>
> Smallest fix: add `replacePassphrase(with passphrase: String)` mirroring `create(with:)`, have
> the screen generate and show first, and demote or delete the one-shot form.
>
> **F2 — Medium. `Vault.create(with:)` will pave over an existing vault, and the state it acts on
> can go stale.** `Vault.swift:87`, `WrappedKeyStore.swift:93`.
>
> `create(with:)` performs no check that a vault does not already exist, and
> `WrappedKeyStore.save` replaces any existing record. The only guard is the setup screen's
> wording plus a human tap, and the doc itself establishes the screen can be looking at stale
> state: "Absent and locked are indistinguishable for as long as iCloud Keychain takes to deliver
> the wrapped record, measured here at close to half an hour."
>
> Second device reads `absent`; the user eventually taps create anyway; meanwhile the real wrapped
> record arrives. `save` overwrites it. If that overwrite syncs, the only recovery record for the
> original vault is destroyed on every device, and every synced account item is ciphertext under a
> key that exists solely on the first phone. Permanent loss of the recovery path from one tap on a
> screen that told the user something true but stale. A pure-UI guard cannot close a TOCTOU
> against a half-hour-latency sync channel.
>
> Smallest fix: in `create(with:)`, `guard !wrapped.exists else { throw .vaultAlreadyExists }`, a
> fresh re-read at write time, with a separately named override for erase-and-recreate.
>
> **F3 — Medium, with a stated uncertainty. Saving the wrapped record can create a twin or
> silently flip its sync state.** `WrappedKeyStore.swift:93`, `Vault.swift:46`.
>
> `kSecAttrSynchronizable` is part of a Keychain item's primary key. `save()` calls `SecItemAdd`
> with the store's own `synchronizable` value, while the duplicate check only fires when primary
> keys collide. If the existing record is synced and the store writes local, or the reverse,
> `SecItemAdd` succeeds and there are now two wrapped records under
> `("app.openfactor.vault.key", "wrapped")`. `load()` queries with `kSecAttrSynchronizableAny` and
> `kSecMatchLimitOne`, so which one a later unlock reads is unspecified: a passphrase change
> followed by an unlock that reads the other twin reports `wrongPassphrase` for a correct
> passphrase. If the flags collide the other way, the `SecItemUpdate` path sets
> `kSecAttrSynchronizable` in its change dictionary, converting a synced record to local or the
> reverse as a side effect of a passphrase change.
>
> The code's own comment concedes the exposure: "two records under one account identifier is the
> twin case gate A2 flagged and this project has never been able to test." I cannot confirm
> exploitability from the attached files alone; I can confirm the attached files do not prevent
> it.
>
> Smallest fix: in `save()`, first query with `kSecAttrSynchronizableAny` for the existing item and
> update it as found, matching its current sync flag rather than forcing a new one; only
> `SecItemAdd` when nothing exists. Sync-flag changes should be the exclusive job of the code that
> flips accounts.
>
> **F4 — Low. A wrapped record from a future version, or a corrupted one, is reported as a wrong
> passphrase.** `Vault.swift:116`.
>
> `unlock(with:)` catches every `WrappedVaultKey.WrapError` as `.wrongPassphrase`. But
> `notAWrappedKey`, for instance an `OFK2` magic written by a newer version, and
> `iterationsOutOfRange` are detected before any derivation and are provably not a wrong
> passphrase. The account-record path got this right. Failure: a user downgrades or restores onto
> an older build, types their correct passphrase, is told it is wrong, and the locked screen's
> only offered exit is erase, destroying accounts a newer build could have opened.
>
> **F5 — Low. Every error on the "does a vault exist" question collapses to `absent`, which is the
> answer that offers creation.** `WrappedKeyStore.swift:82`, `Vault.swift:51`. Rated low rather
> than medium because the mitigations are real, but it is the same pattern the design elsewhere
> forbids: the reassuring answer produced by an unreadable state. Combined with F2's missing
> write-time guard, error-as-absent is the setup for the destructive tap.
>
> **F6 — Low. `docs/VAULT.md` and the code disagree in four places.** The page declares itself
> normative. Service constant: the page says `"app.openfactor.vault"`, the code uses
> `"app.openfactor.accounts"`; since items are already written under `accounts`, the page must
> change, but today a v2 implementer working from the normative page queries the wrong service and
> finds nothing. UUID case: the page says lower case, `id.uuidString` renders upper case, the same
> class of interop break. Sorted JSON keys: claimed by the page, absent from the encoder, and the
> published test vector achieved sorted keys only by bypassing `encode` and supplying raw bytes.
> And a comment describing a conversion the design says does not exist.
>
> **F7 — Informational. The two halves of an account record authenticate independently, not as a
> pair.** `VaultRecord.swift:56`. Each half's AAD is `magic ‖ tag ‖ uuid`, so nothing binds a
> metadata half to the secret half written beside it. An adversary with Keychain write access can
> splice an old metadata half onto the current record and both halves open cleanly, rewinding an
> HOTP counter without disturbing the secret. Filed as informational because `docs/VAULT.md`
> already cedes integrity against that adversary and whole-record replay achieves the same
> rollback. Worth a sentence so the property is not discovered by surprise.
>
> **F8 — Informational. Secret plaintext and vault key bytes live in non-zeroizing `Data`.**
> `VaultRecord.swift:151`, `VaultKeyStore.swift:76`. Swift `Data` cannot be reliably zeroized,
> iOS does not swap to disk, and no path logs or persists either value. An accepted-risk note
> rather than an exploit.
>
> **Where the code held, and why.** No attribute carries an issuer, a name, or a secret: an
> enumerator sees a constant service, a constant label, a UUID, the accessibility class, the sync
> flag, and system timestamps. Half substitution fails on the `0x6D`/`0x73` AAD byte and
> cross-account substitution on the UUID. Listing never decrypts a secret: `openSecret` is called
> only from `secret(for:)`, `records()` opens metadata only, and `update()` moves the secret
> half's bytes without decrypting. Both parsers bounds-check before slicing and no byte sequence
> could be constructed that traps either. The wrapped record gives an attacker salt, iterations,
> nonce and AEAD output and nothing else derived from the passphrase; iterations are clamped
> before derivation and authenticated as AAD, so a hostile record can neither zero the work factor
> nor buy a stall. Creation writes the record before the key, so a crash between them yields
> `locked`, which the passphrase recovers.
>
> **What I could not assess from this scope.** `PBKDF2.deriveKey`,
> `BackupPassphrase.canonical`/`generate`, and `SharedInbox.writingOptions` are referenced but
> were not among the attached files, so three assumptions went unverified: that PBKDF2 is invoked
> with a 32-byte output and a byte-identical canonical encoding between wrap and unwrap; that the
> generate/grouped/canonical round trip is exact, a mismatch making every vault silently
> unrecoverable; and that `writingOptions` includes `.atomic`.

### Triage of the Fable 5 pass

**F1 confirmed, and it is the sharpest finding of the two passes.** `replacePassphrase` at
`Vault.swift:137` saves the new wrap and returns the string afterwards. The project already
learned this lesson once: `create(with:)` exists precisely because the one-shot `create()` shape
was dangerous, and the reasoning is written in the comment above it. Nobody applied it to
replacement. A crash or a torn-down view between the save and the screen leaves a vault whose
only recovery credential was never seen by anybody, and the device keeps working so nothing
signals it.

**F2 confirmed.** `create(with:)` calls `wrapped.save` with no existence check, and `save`
overwrites on duplicate. The stale-state window is the project's own measured half hour.

**F3 confirmed as written, and it carries a sequencing consequence.** `kSecAttrSynchronizable` is
part of a Keychain item's primary key, so a differing flag produces a twin rather than a
duplicate error. **It cannot fire today only because of the high-severity defect above:** the
wrapped key's flag is always `false`, so it never differs. Fixing the sync gap without fixing
`save` at the same time would create exactly the twin case this finding describes. The two must
land together.

**F4 confirmed.** `Vault.swift:116` catches every `WrapError` as `.wrongPassphrase`, including
the two that are decided before any derivation runs.

**F5 confirmed**, and it is the same defect ChatGPT filed as its third medium. Two engines, two
severities, one finding.

**F6 confirmed, and it found a fifth mismatch the other pass missed:** `id.uuidString` renders
upper case while the normative page specifies lower case.

**F7 and F8 accepted as informational**, both correctly reasoned and neither requiring code. F7
deserves the sentence it asks for in `docs/VAULT.md`.

### What the two passes together say about the method

The overlap is small. Of eight findings from each engine, **only two are the same**: error-as-absent,
and the documentation mismatches. ChatGPT found the high-severity sync gap that Fable did not.
Fable found six that ChatGPT did not, including the two most dangerous write-ordering defects.

**The gap in Fable's coverage was caused by this scope's file list, not by the engine.** It flagged
that it could not confirm F3's exploitability because `SyncAwareKeychainStore` was not among the
attached files, and that is the exact file that would have shown it the sync gap. The scope list
in `A4-prompts.md` omitted it, along with `PBKDF2.swift` and `BackupPassphrase.swift`, which the
pass also named as unverifiable assumptions. That is a defect in the prompt rather than in either
review, and it is recorded here rather than quietly corrected, because the next scope's file list
should be built by asking what a reviewer would need rather than what seems central.

### Not yet acted on

**Nothing has been changed.** The remaining engine runs this same scope against the same
commit, and fixing between passes would mean the later ones review different code and their
findings could not be compared with these. Fixes begin when scope 1 is complete on all three.

One operational note recorded at the time: the high-severity defect affects the maintainer's own
device and the build already on TestFlight, so an encrypted export was advised immediately as the
only recovery path currently available.
