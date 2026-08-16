# The OpenFactor vault

**Version 1. Written before the code, and audited before the code**, for the reason
`docs/BACKUP_FORMAT.md` was: this decides how every secret is stored on every device, and it
is not fixable in an update once people have data.

This document is normative. Where the code and this page disagree, the page is correct and the
code is a defect.

**Revised once already, before implementation, by two independent reviews.** Twelve findings
were accepted, five of them blocking, and they are recorded in `docs/audits/V1.md`. Several
were data loss rather than weakness: a silent erase with no tripwire, a passphrase that would
never have been shown to users who keep sync off, and a wrapped key split across two
independently syncing records. The first draft read as finished. That is the argument for
auditing a page rather than a diff.

## The problem this exists to solve

Secrets were stored as plaintext Keychain items in a shared access group, and the project
believed the developer team was a boundary. **It is not.** Gate E1 measured it: a second app
signed by the same team read another app's secrets out of the group Apple's documentation
calls private. Evidence, method and Apple's own wording are in
`docs/audits/E1-keychain-access-groups.md`.

The rule the design is built around:

> Anything an app can read **silently**, a sibling app can be authorised to read silently.

No arrangement of access groups helps, because each is a grant the account holder controls.
**The sandboxed container is the exception**: no entitlement, portal setting or account action
grants one app access to another app's private container. The Keychain is built for sharing;
the container is built for isolation.

**The design in one sentence:** the ciphertext lives in the Keychain, where it syncs; the key
lives in the container, where nothing else can reach it.

```
   iCloud Keychain  ──────  ciphertext only, no key material, ever
          │
          ├── iPhone   ── vault key in the app's private container
          └── Watch    ── vault key in the app's private container
```

## What this defends against, and what it does not

**Closed: confidentiality against another app on the same team.** However it is signed and
whatever it declares, it reads ciphertext. It cannot obtain the key, because the key is in a
container the sandbox denies it. This holds with no dependence on account configuration, which
is what makes it a property of the code that a fork inherits by cloning.

**Improved: iCloud Keychain becomes a transport for ciphertext.** A compromise of it yields
sealed blobs, so the escrow discussion in `SECURITY.md` stops being load bearing.

**Not closed, and this is the correction the audit forced: integrity and availability.** A
sibling app can *write* the Keychain as easily as read it. It can delete every account item,
and with sync on that deletion propagates: this project measured a watch emptying fourteen
minutes after a sync change. It can also replay an older ciphertext for an account and the tag
will verify, because nothing binds a ciphertext to a point in time.

Encryption is the wrong tool for that and no key hierarchy fixes it. **The backstop is the
encrypted export**, which is why this design makes it a recommended step rather than a
convenience, and why the interface must say so.

**Not closed: a malicious OpenFactor update**, which reads its own container by definition.
Publisher trust is irreducible on every platform. The answer is verifiability rather than
cryptography: public source, and reproducible builds so a shipped binary can be checked
against it.

**Not closed:** an unlocked device in an attacker's hands, or a compromised operating system.

## The key hierarchy

| | What it is | Where it lives | Synced? | In backups? |
| --- | --- | --- | --- | --- |
| **Vault key** | 256 random bits from the system CSPRNG | Each device's container | **Never** | **Never** |
| **Passphrase** | 120 bits, generated, Base32, shown in groups of four | **Nowhere. Shown to the user once** | Never | Never |
| **Wrapped key** | The vault key sealed under a key derived from the passphrase, with its salt and iteration count | One Keychain item | Yes, it is ciphertext | As Keychain items are |

**The passphrase is never persisted.** The first draft kept a copy in the container "for
convenience" and both reviewers attacked it: nothing in either recovery path reads it back, it
would ride into device backups, and it silently undoes the property that losing the passphrase
means losing recovery. It is generated, displayed, acknowledged, and forgotten by the app.

Because the vault key lives in the container, a passphrase can always be **replaced** without
it: generate a new one, rewrap, show it. That is what happens if somebody fails to write the
first one down. It is not a way to recover a lost passphrase on a device that has no key.

**The vault key encrypts accounts; the passphrase only ever wraps the vault key.** A normal
launch reads the key from the container and performs no key derivation at all. Changing the
passphrase rewraps 32 bytes instead of re-encrypting every account.

### The vault key file

`Application Support`, never `Caches` or `tmp`, which iOS purges under storage pressure with no
user action and no signal. Written with the strongest file protection class, and **excluded
from device backups**.

The exclusion is deliberate friction. Letting the key ride along would make restores seamless,
would mean the passphrase is never exercised and never noticed as important, and would place
the key inside any unencrypted local backup.

### Deriving the wrapping key

```
wrappingKey = PBKDF2-HMAC-SHA256(
                  password   = the passphrase, canonicalised per BACKUP_FORMAT.md
                  salt       = 32 random bytes, stored in the same item
                  iterations = read from the item, 600000 when written
                  length     = 32 bytes)

wrappedVaultKey = AES-256-GCM-Seal(
                      key   = wrappingKey
                      data  = the 32 byte vault key
                      aad   = the ASCII bytes of "openfactor.vault.v1")
```

**The vault passphrase is always generated, never chosen.** The archive offers a custom
passphrase; this deliberately does not. The reason is specific: a reader that tries several
candidate derivations of one typed input against one ciphertext is exactly the shape that
produced the AES-GCM key commitment collision recorded in `BACKUP_FORMAT.md`, and the fix
there, requiring the plaintext to parse, has no equivalent here because the plaintext is 32
opaque bytes. One generated form means one derivation and the question does not arise.

**The iteration count is stored, not assumed**, so raising it later does not brick every
existing vault, and it is clamped to the same 100,000 to 10,000,000 range the archive enforces
so a written value cannot grind a device or weaken a derivation.

**A fresh salt and nonce on every rewrap**, not only on creation.

### The wrapped key is one item, not two

```
kSecClass            kSecClassGenericPassword
kSecAttrService      "app.openfactor.vault.key"
kSecAttrAccount      "wrapped"
kSecValueData        a single sealed structure: version, salt, iterations, wrapped key
```

The salt, the iteration count and the wrapped key travel together **inside one record**. The
first draft said the salt was stored "beside" the key, and the review pointed at this project's
own measurements: iCloud Keychain propagates one item at a time and took close to half an hour
for seven, so two records mean a device can hold one and not the other. A correct passphrase
would then fail to derive anything, indistinguishable from a wrong one.

**This is the only item in the design that is ever written twice**, on a passphrase change, and
`docs/ARCHITECTURE.md` records that a second writing device is a case this project has never
tested. Rewrapping replaces the item in place; the untested case is listed under what still
needs proving.

## How an account is stored

One Keychain item per account, as today, and the item is opaque.

```
kSecClass            kSecClassGenericPassword
kSecAttrService      "app.openfactor.vault"      a constant, identical for every item
kSecAttrAccount      the account's UUID           an identifier, never a name
kSecAttrSynchronizable  follows the user's sync preference
kSecValueData        AES-256-GCM(vault key, padded payload, aad = version + UUID)
```

**Everything about an account is inside the ciphertext**: issuer, name, colour, sort order,
and the secret. The list of services somebody uses is most of what an attacker wanted.

**The payload is padded to fixed buckets before sealing.** GCM ciphertext is the length of its
plaintext, so without padding the length of an issuer and account name leaks to any reader.
`BACKUP_FORMAT.md` discloses its equivalent leak rather than fixing it, because padding an
archive is a format change; here it costs a few bytes per item.

**The AAD is the format version and the UUID.** The UUID stops a ciphertext being moved between
items, which would otherwise let a writer swap two accounts so each decrypts cleanly under the
wrong name. The version leaves a clean signal for a future format change mid-rollout.

**A fresh nonce for every write.** Not per session, not per account, per write.

**One account failing never fails the vault.** An item that will not decrypt is reported the way
an unreadable record is today, through `StoredRecords.unreadable`, and the rest still open.

### What remains visible to a sibling app

Stated because the first draft claimed more than it delivered:

- **How many accounts exist**, since every item shares one service string and can be counted.
- **When each was created and last modified**, from the OS-assigned Keychain attributes, which
  the app does not control.
- **The approximate size bucket** of each payload after padding.

## Getting the key onto a device

A device with no vault key can read nothing. There are exactly two ways it gets one.

### The passphrase

Read the wrapped key item, ask for the passphrase, derive, unwrap, write the vault key into the
container. This is the path for a reinstall, a new iPhone, or any device with no paired
companion to ask.

**Absent is not wrong.** If the wrapped key item has not arrived yet, which is ordinary given
measured iCloud Keychain latency, the app says the vault has not reached this device yet. It
must never report a correct passphrase as incorrect because a record is still in flight.

### A paired watch

Typing 24 characters on a wrist is not a design, so the watch asks its phone.

```
Watch                                            Phone
  │  no vault key in my container
  │  generate a fresh P-256 keypair, private
  │  key stays in the watch's container
  │
  │ ──────── request + public key ──────────────►
  │                                     the person taps Provision on the phone,
  │                                     which is foregrounded and unlocked;
  │                                     ECDH → HKDF(info = "openfactor.vault.watch.v1")
  │                                     → AES-256-GCM seal, aad = the same string
  │ ◄─────── sealed vault key ────────────────────
  │
  │  unseal, write to container, never ask again
```

**Provisioning needs the phone once. Operation never does.** Afterwards accounts continue to
arrive through iCloud Keychain as ciphertext with no phone involvement, and codes are generated
with the phone off, absent or out of range. The `WKRunsIndependentlyOfCompanionApp` promise in
`docs/PROJECT.md` survives intact.

**A person taps to approve on the phone.** The first draft answered any well-formed request
automatically, and the review's objection was the one this project has learned to respect: the
belief that WatchConnectivity routing is exclusive to a paired counterpart app has exactly the
shape of the belief E1 destroyed. It is on the list of things to prove, and until it is proven
the exchange does not happen without a deliberate human act.

**The interactive channel only.** Queued transfer modes persist payloads to disk while waiting
for delivery, and this payload is the key to everything.

**If the phone itself has no key yet**, which happens when a phone and watch are replaced
together, it says so rather than failing silently, and the watch retries after the person has
recovered the phone.

## Sync, and what it does not change

The sync preference is `kSecAttrSynchronizable` on the items, which `SyncAwareKeychainStore`
already flips in place without reading secrets. **The vault key never syncs under any setting.**

Everything is encrypted whether sync is on or off. There is no local-only plaintext mode: a
sibling app reads local items exactly as easily as synced ones.

**With sync off, a lost device is a lost vault.** The wrapped key exists only on that device,
so there is nothing to recover from and the passphrase has nothing to unwrap. The section above
is titled "the passphrase" rather than "the passphrase always works" for this reason. For a
sync-off user the encrypted export is not a recommendation, it is the only copy.

## The passphrase is shown when the vault is created

Not when sync is enabled. The vault is created at first launch regardless of sync, so tying the
display to the sync toggle would leave a local-only user holding a vault whose passphrase they
were never shown, and losing everything the first time they reinstall.

**No vault exists without its passphrase having been shown and acknowledged**, the same rule the
archive follows, for a stronger reason: an archive is optional and this is not.

**The two passphrases must be distinguishable.** The vault passphrase and an archive passphrase
are generated identically and look identical, and somebody recovering months later under
pressure will hold two strings and no way to tell them apart. Each must be labelled where it is
shown, and where it is asked for.

## Migration from the current storage

Existing installations hold plaintext items in a shared access group.

**The first draft said the old items are simply erased, on the grounds that only two people
hold disposable test data. The review was right to call that blocking.** Nothing in it was
scoped to those two people. The same code would fire on the next person to install, silently,
with no confirmation, in an app whose erase feature is deliberately gated behind Face ID and a
typed word.

So: **plaintext items are never deleted without an explicit act.** On finding them, the app
explains what is about to happen, offers an encrypted export first, and requires the same
deliberate confirmation erasing already requires. Whether the accounts are then converted or
erased and re-added is an implementation choice; doing either silently is not.

## Invariants

Checkable, and several belong in CI and the ship script:

- The **vault key** is never written to the Keychain, never synced, never backed up, never
  logged, and never leaves a device except sealed to a paired watch's public key.
- The **passphrase** is never persisted anywhere, in any form.
- **No plaintext secret** is ever written to a file, a container, or a log.
- No Keychain item carries an issuer, an account name, or any other metadata in the clear.
- The complication and any future extension hold neither the key nor an entitlement to the items.
- Queued WatchConnectivity transfer modes are never used for key material.
- No vault-key or passphrase material is ever placed in an iCloud Drive or ubiquitous container.

## What must be proven before this is implemented

Written down so an audit can rule on them rather than assume them, and so nobody mistakes
confidence for evidence a second time.

1. **That a sibling app cannot read another app's private container.** The whole design rests on
   it, and the belief has the exact shape of the one E1 destroyed. A probe settles it.
2. **That WatchConnectivity routing is exclusive to the paired counterpart app**, and that a
   sibling cannot inject a provisioning request.
3. **That excluding the key file from backups behaves as documented on a real restore**, and
   separately under Apple's device-to-device Quick Start migration, which is a different
   mechanism and may not honour the same flag.
4. **That a watch can hold a P-256 private key and complete the exchange** inside the interactive
   channel's message size limits.
5. **That an opaque service constant with UUID accounts leaves no queryability** the store
   depends on today.
6. **That rewrapping, the one item written twice, survives the two-writer case** this project has
   never tested.
