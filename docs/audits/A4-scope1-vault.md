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
| Grok 4.6 | Not yet run |
| Fable 5 | Not yet run |

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

### Not yet acted on

**Nothing has been changed.** The remaining two engines run this same scope against the same
commit, and fixing between passes would mean the later ones review different code and their
findings could not be compared with these. Fixes begin when scope 1 is complete on all three.

One operational note recorded at the time: the high-severity defect affects the maintainer's own
device and the build already on TestFlight, so an encrypted export was advised immediately as the
only recovery path currently available.
