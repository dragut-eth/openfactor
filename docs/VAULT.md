# The OpenFactor vault

**Version 1. Written before the code, and audited before the code**, for the reason
`docs/BACKUP_FORMAT.md` was: this decides how every secret is stored on every device, and it is
not fixable in an update once people have data.

This document is normative. Where the code and this page disagree, the page is correct and the
code is a defect.

**Revised twice before a line was written.** An internal round found twelve defects, five
blocking, three of them data loss (`docs/audits/V1.md`). Three external reviews then found ten
more, including a protocol that was half a protocol, a property the design was giving away
without mentioning it, and a sentence that was true and led to a false conclusion
(`docs/audits/V2-chatgpt.md`, `V2-grok.md`, `V2-fable.md`). Each draft read as finished. That is
the argument for auditing a page rather than a diff.

## The problem this exists to solve

Secrets were plaintext Keychain items in a shared access group, and the project believed the
developer team was a boundary. **It is not.** Gate E1 measured a second app signed by the same
team reading another app's secrets out of the group Apple's documentation calls private.

> Anything an app can read **silently**, a sibling app can be authorised to read silently.

No arrangement of access groups helps, because each is a grant the account holder controls.
**The container is the exception**, and gate E4 measured that too: a sibling holding the
victim's exact path was refused by the kernel with `EPERM`, and could not even enumerate.

**The design in one sentence:** the ciphertext lives in the Keychain, where it syncs; the key
lives in the container, where nothing else can reach it.

```
   iCloud Keychain  ──────  ciphertext only, no key material, ever
          │
          ├── iPhone   ── vault key in the app's private container
          └── Watch    ── vault key in the app's private container
```

## What this defends against, and what it does not

**Closed after provisioning: confidentiality against another app on the same team.** It reads
ciphertext and cannot obtain the key.

**During provisioning** the claim is weaker and depends on the watch exchange below, which is
why that exchange has an authentication string rather than only a button.

**Improved, with a distinction the first draft got wrong: iCloud Keychain becomes a transport
for ciphertext.** For **confidentiality** the escrow discussion in `SECURITY.md` stops being
load bearing, since a compromise yields sealed blobs. For **availability** it is exactly as load
bearing as before: with sync on and every device lost, escrow is how the ciphertext and the
wrapped key come back so the passphrase has something to unwrap.

**Not closed: integrity and availability.** A sibling can *write* the Keychain as easily as read
it. It can delete every item, and sync propagates that; this project measured a watch emptying
fourteen minutes after a sync change. It can replay an older ciphertext and the tag will verify.
Encryption is the wrong tool and no key hierarchy fixes it. The mitigations are a tripwire that
turns silent destruction into a reported anomaly, and the encrypted export as the actual
backstop.

**Not closed: a malicious OpenFactor update**, which reads its own container by definition.
Answered by public source and reproducible builds, not by cryptography.

**Not closed:** an unlocked device in an attacker's hands, or a compromised operating system.

## The key hierarchy

| | What it is | Where | Synced | Backed up |
| --- | --- | --- | --- | --- |
| **Vault key** | 256 random bits, system CSPRNG | Each device's container | **Never** | **Never** |
| **Passphrase** | 120 bits, generated, Base32 | **Nowhere. Shown once** | Never | Never |
| **Wrapped key** | The vault key sealed under the passphrase, with its salt and iterations | One Keychain item | Follows the sync preference | As Keychain items are |

**The passphrase is never persisted.** It is generated, displayed, acknowledged, and forgotten.
Because the vault key lives in the container, a passphrase can be **replaced** at any time by
rewrapping. That is not a way to recover a lost one on a device that has no key.

### Rewrapping is not revocation

**Changing the passphrase does not rotate the vault key**, and the convenience of rewrapping 32
bytes must not be mistaken for a remedy. The wrapped item is a Keychain item, so the in-scope
adversary can capture it; anyone holding an old wrapped item and the old passphrase can unwrap
the vault key **forever**, and a sibling can replay the old item.

**Responding to a suspected compromise requires vault key rotation**: a new vault key, every
account re-encrypted under it, a new passphrase, and every other device re-provisioned. **Version
1 does not implement that path.** It is stated here so that nobody offers a passphrase change as
though it were one.

### The vault key file

`Application Support`, never `Caches` or `tmp`, which iOS purges under storage pressure with no
user action and no signal.

**Always located through `FileManager`, never through a remembered path.** An app update
preserves the data and **moves the container**, measured in `docs/audits/E6-container-durability.md`:
the file survived byte for byte while its directory changed identity. Anything that caches or
persists the absolute path, including the tripwire anchor, breaks at the first update, and
breaks by pointing at a container that is no longer there rather than by failing loudly.

**Protection class `.complete`**, named rather than described as strongest. The consequence is
deliberate: the key is unreadable whenever the device is locked, so nothing can read the vault in
the background, and on watchOS it follows wrist-lock. The app has no background modes, so
nothing is lost. `.completeUntilFirstUserAuthentication` would be a materially weaker and
different promise and is not what this means.

**Excluded from device backups.** Deliberate friction: otherwise the passphrase is never
exercised, never noticed as important, and absent when finally needed, and the key would sit
inside any unencrypted local backup.

## Record formats

Both records are byte-exact, because a page that calls itself normative cannot leave the layout
to whoever writes the code first. **The bar is that our implementations agree across versions
and platforms and that a version 2 reader opens version 1 records**, not that a stranger can
write a reader from this page alone. That is the archive's bar, and the archive is an
interchange format; this is not.

All integers are big endian. **Test vectors are part of this format** and must exist before the
implementation is considered complete.

### The account record

One Keychain item per account, as today.

```
kSecClass               kSecClassGenericPassword
kSecAttrService         "app.openfactor.vault"     a constant, identical for every item
kSecAttrAccount         the account's UUID, lower case, hyphenated
kSecAttrSynchronizable  follows the sync preference
kSecAttrGeneric         absent
kSecValueData           the layout below
```

```
offset  size  field
0       4     "OFV1"  format magic and version
4       12    metadata nonce
16      4     metadata sealed length, ciphertext plus 16 byte tag
20      n     metadata sealed bytes
20+n    12    secret nonce
32+n    4     secret sealed length, ciphertext plus 16 byte tag
36+n    m     secret sealed bytes
```

**Two halves under one key, and this is not decoration.** Today `records()` sets
`kSecReturnData` to false on every listing path, and the file states the property: listing
accounts never decrypts a single secret. Sealing everything as one blob would end that, because
drawing a list would decrypt every secret into memory to render a screen that needs none of
them. Splitting the seal preserves it: **listing decrypts the metadata half only**, and the
secret's plaintext appears when a code is generated and at no other time.

AAD, which gives the halves domain separation so one cannot be substituted for the other:

```
metadata:  "OFV1" || 0x6D || the UUID's 16 raw bytes
secret:    "OFV1" || 0x73 || the UUID's 16 raw bytes
```

**The metadata half** is JSON, keys sorted, holding issuer, name, colour, sort index and the
generator including any HOTP counter, then padded to the next multiple of 128 bytes with a
length prefix so the padding is unambiguous. Padding exists because GCM output is the length of
its input, so without it the length of an issuer and account name leaks to any reader.

**The secret half** is the raw secret bytes, padded the same way.

**Unknown JSON fields are ignored, not rejected**, so a later version can add one. An unknown
**magic** is refused, and the item is reported unreadable rather than guessed at.

**The secret half is written once and never rewritten.** A rename, a colour change, a reorder or
an HOTP counter rewrites the metadata half and copies the secret half **verbatim**, so those
operations never decrypt a secret and never need a fresh nonce for it. This also corrects a
claim in the first draft: account items are rewritten constantly, and the wrapped key is not the
only item written more than once.

**A fresh nonce whenever a half is actually re-sealed.**

**One account failing never fails the vault**, reported through `StoredRecords.unreadable`.

### The wrapped key record

```
kSecClass               kSecClassGenericPassword
kSecAttrService         "app.openfactor.vault.key"
kSecAttrAccount         "wrapped"
kSecAttrSynchronizable  follows the sync preference, the same as accounts
kSecValueData           the layout below
```

```
offset  size  field
0       4     "OFK1"
4       32    PBKDF2 salt
36      4     PBKDF2 iterations
40      12    nonce
52      48    the 32 byte vault key sealed, plus its 16 byte tag
```

AAD: `"OFK1" || salt || iterations`, so the two values that sit outside the seal because
derivation needs them are still bound and cannot be corrupted undetected.

Salt, iterations and wrapped key are **one record**. iCloud Keychain delivers one item at a
time and took half an hour for seven here; two records mean a device can hold one and not the
other, and a correct passphrase then fails indistinguishably from a wrong one.

**The iteration count is read from the record** and clamped to 100,000 to 10,000,000, the range
the archive enforces. **A fresh salt and nonce on every rewrap.**

### Deriving the wrapping key

```
wrappingKey = PBKDF2-HMAC-SHA256(passphrase canonicalised per BACKUP_FORMAT.md,
                                 salt, iterations, 32 bytes)
```

**The vault passphrase is always generated, never chosen.** Trying several candidate derivations
of one typed input against one ciphertext is the shape that produced the key commitment
collision recorded in `BACKUP_FORMAT.md`, and that fix, requiring the plaintext to parse, has no
equivalent for 32 opaque bytes. One generated form means one derivation.

At 120 generated bits the PBKDF2 parameters are belt and braces rather than the thing holding
the door.

## Getting the key onto a device

### The passphrase

Read the wrapped record, ask, derive, unwrap, write the vault key to the container.

**Absent is not wrong.** If the record has not arrived, the app says the vault has not reached
this device yet. A correct passphrase must never be reported as incorrect because a record is
still in flight.

### A paired watch

Typing 24 characters on a wrist is not a design.

```
Watch                                            Phone

 generate w_priv / w_pub, and a 16 byte nonce
 ── version ‖ nonce ‖ w_pub ───────────────────►
                                    generate ephemeral p_priv / p_pub
                                    shared   = ECDH(p_priv, w_pub)
                                    transcript = version ‖ nonce ‖ w_pub ‖ p_pub
                                    kek      = HKDF-SHA256(shared,
                                                 info = "openfactor.vault.watch.v1" ‖ transcript)
                                    sas      = first 6 digits of SHA-256(transcript)
                                    show sas, wait for the person to confirm it matches
                                    sealed   = AES-256-GCM(kek, vaultKey, aad = transcript)
 ◄── version ‖ nonce ‖ p_pub ‖ sealed ──────────
 recompute shared, kek, sas; show sas
 unseal, write to container, never ask again
```

**The phone needs its own ephemeral keypair.** The first draft wrote "ECDH, then HKDF, then seal
to the watch's public key" as though that were one primitive. ECDH needs a private key on both
sides; what it described was ECIES with half missing.

**The whole transcript is bound**, version, nonce and both public keys, into the HKDF info and
the AAD. The nonce is what makes a replayed response detectable.

**The person compares a six digit string on both screens.** A tap alone authorises *when* the
exchange happens, not *who* it happens with, and an injected request looks identical from the
user's side. The string is what makes routing exclusivity **defence in depth instead of load
bearing**, which is the move this document makes everywhere else.

**The interactive channel only.** Queued transfer modes persist payloads to disk while waiting.

**The phone must be foregrounded and unlocked** to read its own container, and says so rather
than failing silently. **If the phone has no key itself**, which happens when both are replaced
together, it says that instead, and the watch retries after the phone is recovered.

The watch's private key may live in the Secure Enclave rather than the container. It is used
once and discarded, so this is hygiene rather than a hole.

**Provisioning needs the phone once. Operation never does.** Afterwards accounts arrive through
iCloud Keychain as ciphertext with no phone involvement, and codes are generated with the phone
off, absent or out of range.

## The tripwire

A sibling can delete every item, and without this the app would render that as "no accounts
yet", confirming an attack as normal.

**The anchor lives in the container**, which E4 measured to be beyond a sibling's reach. A
manifest sealed into a Keychain item would be deleted along with everything else; a tripwire an
attacker can remove is not one. The container holds, at minimum, that a vault exists and a high
water mark of how many accounts it has held.

When the anchor says a vault exists and nothing is found, the app reports **data missing**, not
an empty vault, and points at the export.

**The unsolved part, stated rather than glossed.** With sync on, another device legitimately
adds and removes accounts, so a container anchor goes stale and a naive count comparison would
cry wolf. A per-account revision in the anchor would also detect replay, which is otherwise
undetectable. Reconciling that with legitimate multi-device churn is **not solved in this
document** and must be designed before the tripwire is built.

## Sync

`kSecAttrSynchronizable` on the account items and on the wrapped key record, both following the
user's preference, flipped in place by `SyncAwareKeychainStore` without reading secrets. **The
vault key never syncs under any setting.**

Everything is encrypted whether sync is on or off; a sibling reads local items as easily as
synced ones.

**With sync off, a lost device is a lost vault.** The wrapped record exists only there. For that
configuration the encrypted export is not a recommendation, it is the only copy.

## What the interface owes

**The passphrase is shown when the vault is created**, not when sync is enabled, since the vault
exists either way and a local-only user would otherwise hold one whose passphrase they had never
seen.

**No vault exists without its passphrase having been shown and acknowledged.**

**The two passphrases must be distinguishable.** The vault's and an archive's are generated
identically and look identical, and somebody recovering months later holds two strings and no
way to tell them apart. Both must be labelled where shown and where asked for.

**The watch's empty state gains a third cause.** It distinguishes accounts in flight from sync
being off; there is now provisioned-but-unprovisioned-key, and the existing advice to check sync
would send a wearer to turn off the thing that is working.

## Migration

**Plaintext items are never removed without an explicit act.** The first draft said they are
erased, justified by two people holding disposable data; nothing scoped it to those two, and the
same path would have fired on the next person with no confirmation, in an app whose erase
feature is gated behind Face ID and a typed word.

On finding old items the app explains what will happen, offers an encrypted export first, and
requires the same deliberate confirmation.

**Conversion must clear `kSecAttrGeneric`.** Today's items carry issuer and name as JSON in that
attribute. Encrypting the value and leaving the attribute satisfies the sentence "convert the
accounts" and defeats the entire design, and an implementer would not be wrong to do it unless
this says otherwise.

## Invariants

- The **vault key** is never written to the Keychain, never synced, never backed up, never
  logged, and never leaves a device except sealed to a confirmed watch public key.
- The **passphrase** is never persisted in any form.
- **No plaintext secret** is ever written to a file, a container, or a log.
- No Keychain item carries metadata in the clear, in `kSecValueData` or in any attribute.
- The complication and any extension hold neither key nor entitlement.
- Queued WatchConnectivity transfer modes are never used for key material.
- No key or passphrase material is placed in iCloud Drive, a ubiquitous container, **or an App
  Group container**. PR 16c introduces one for the share extension's inbox, and E1's rule
  classifies an App Group as a grant rather than a boundary.

## What must be proven before implementation

1. ~~A sibling app cannot read another app's private container.~~ **Proven**, `docs/audits/E4-container-isolation.md`.
2. **WatchConnectivity routing is exclusive to the paired counterpart app.** Half measured in
   `docs/audits/E5-watchconnectivity-routing.md`: a sibling app with no watch of its own
   activates a session and finds it inert, so a session is not a device wide channel. What is
   still unmeasured is a rogue watch app *claiming to be* OpenFactor's counterpart. Defence in
   depth rather than load bearing because of the authentication string, and if that string is
   ever removed this becomes blocking again.
3. **Backup exclusion behaves as documented on a real restore**, and separately under Quick
   Start, which is a different mechanism.
4. **A watch can hold a P-256 private key and complete the exchange** inside the interactive
   channel's message size limits.
5. **An opaque service constant with UUID accounts leaves no queryability** the store depends on.
6. **Rewrapping survives the two-writer case**, which this project has never tested, and which
   now applies to every account item rather than one.
7. **The container survives a restore and Quick Start.** Narrowed by
   `docs/audits/E6-container-durability.md` rather than closed. Measured there: the protection
   class and the backup exclusion both stick and both survive an update, and an app update
   preserves the data while **moving the container**, so nothing may ever cache the absolute
   path. Offload is not offered for a development install and stays unmeasured, though Apple
   documents it as preserving data. A restore and a Quick Start were not attempted, because
   both require wiping or newly configuring somebody's personal phone. **The backup exclusion
   is therefore verified as a flag and never as a restore**, and this document should not imply
   otherwise.
