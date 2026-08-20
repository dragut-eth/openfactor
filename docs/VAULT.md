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

> Anything an app can read **silently**, a sibling app can be authorized to read silently.

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

**During provisioning** the claim is weaker and rests on WatchConnectivity's routing, which is
stated as a load bearing assumption in the exchange below rather than buried.

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

*Implemented as `VaultKeyStore` in PR 16d.*

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

*Both records are implemented as of PR 16d, in `Sources/OpenFactorCore/Vault/`, with tests that
assert the layout rather than only the round trip. That distinction earned itself immediately:
the first writer emitted the secret half's length before its nonce, which round tripped through
neither reader nor writer, and only the layout assertion caught it.*

### The account record

One Keychain item per account, as today.

```
kSecClass               kSecClassGenericPassword
kSecAttrService         "app.openfactor.accounts"  a constant, identical for every item
kSecAttrAccount         the account's UUID, upper case, hyphenated
kSecAttrSynchronizable  follows the sync preference
kSecAttrGeneric         absent
kSecValueData           the layout below
```

**Two of those lines were wrong until gate A4, and they were wrong in the direction that
matters.** The page said the service was `"app.openfactor.vault"` and the UUID was rendered lower
case; the code has always written `"app.openfactor.accounts"` and `UUID.uuidString`, which is
upper case. This page declares itself normative, so a second implementation written from it would
have queried a service nothing is stored under and matched no account it did look for. The items
already exist on people's phones, so the page is what changes.

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

**Two halves under one key, and this is not decoration.** Listing accounts never decrypts a
single secret: `records()` reads each item's value, because the sealed metadata is *in* that
value, and opens the metadata half alone.

The sentence here used to say `records()` sets `kSecReturnData` to false, which was written for
the design that preceded this one and has been false since the two halves arrived: the data is
what carries the metadata now, so of course it is returned. Two reviewers found it in the same
round, in this page and in the source comment that repeated it. Sealing everything as one blob would end that, because
drawing a list would decrypt every secret into memory to render a screen that needs none of
them. Splitting the seal preserves it: **listing decrypts the metadata half only**, and the
secret's plaintext appears when a code is generated and at no other time.

AAD, which gives the halves domain separation so one cannot be substituted for the other:

```
metadata:  "OFV1" || 0x6D || the UUID's 16 raw bytes
secret:    "OFV1" || 0x73 || the UUID's 16 raw bytes
```

**The metadata half** is JSON, keys sorted, holding issuer, name, color, sort index and the
generator including any HOTP counter, then padded to the next multiple of 128 bytes with a
length prefix so the padding is unambiguous. Padding exists because GCM output is the length of
its input, so without it the length of an issuer and account name leaks to any reader.

**The secret half** is the raw secret bytes, padded the same way.

**What padding leaves behind, stated because the page used to stop short of it.** Bucketing hides
the exact length and not the approximate one. Real metadata for an ordinary account runs around
132 to 139 bytes, which is two buckets rather than one, so a reader who can see the sealed lengths
learns a coarse class: one bucket, two, or three. That distinguishes an account with a short
issuer and no colour from one with a long issuer, a long name and a high counter. It does not
distinguish two accounts in the same class, and it never exposes a character of either field. A
reviewer in gate A4 pointed out that the page said why padding exists and never said what remains
after it.

**Unknown JSON fields are ignored, not rejected**, so a later version can add one. An unknown
**magic** is refused, and the item is reported unreadable rather than guessed at.

**The secret half is written once and never rewritten.** A rename, a color change, a reorder or
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
wrappingKey = PBKDF2-HMAC-SHA256(passphrase canonicalized per BACKUP_FORMAT.md,
                                 salt, iterations, 32 bytes)
```

**The vault passphrase is always generated, never chosen.** Trying several candidate derivations
of one typed input against one ciphertext is the shape that produced the key commitment
collision recorded in `BACKUP_FORMAT.md`, and that fix, requiring the plaintext to parse, has no
equivalent for 32 opaque bytes. One generated form means one derivation.

At 120 generated bits the PBKDF2 parameters are belt and braces rather than the thing holding
the door.

### Test vectors

Real values, produced by this implementation and pinned so the format survives a rewrite. A
round trip test proves an implementation agrees with itself, which is exactly what a format
break also does; these prove it agrees with the bytes on this page.

**Nonces and salts are fixed here for reproducibility. A real record generates both from the
system CSPRNG and never reuses either**, which is asserted separately rather than left to the
vector to imply.

**Account record.** Key `00 01 02 … 1f`, account `6F1B0C0A-6D3A-4A1F-9A2E-2A3B4C5D6E7F`,
metadata nonce `a0 a1 … ab`, secret nonce `b0 b1 … bb`, metadata
`{"color":"blue","issuer":"GitHub","name":"octocat"}`, secret the ASCII bytes
`12345678901234567890`. The record is **324 bytes**:

```
4f465631a0a1a2a3a4a5a6a7a8a9aaab00000090e6187c1e3ee961d00e0af5f13d58a2b205c97b3cb0de311fe96b
54a445893268a63e329d8d0e71533ef161ea3358ec9a3374252916f2677e415e0b5ea47085b0b4bc856f30a5e4e0
f4e2ff188fceccbacd0baba4c5c1997aee753e9ab19a4d948f842bab03ae8f9b9edb06508588ed28245061aede35
9b3c2fcfdea4b455f24d3a0515a871126b350b9da248b8860917b0b1b2b3b4b5b6b7b8b9babb0000009099555abf
ddff886b72cea09af46db9f0b7087ce42216b6055ece82f15c82f216054b233a63dea6b8a55ba04a3cb982b52d6d
17c71b3b42f04d8a6c30049b20ffb2e83eb40abc66da19dca25e9e06e2314690c9b2a87875ddf5fb78902b590fbf
63a07e5bced736165e4e1adc92dac0800db6b79773f3cd3a7807f7d91e0e2f2289b1b05aab1d368d0fb8593b65c3
46fb
```

Both halves pad to one 128 byte bucket, so each sealed length reads `00000090`, which is 144:
the bucket plus a 16 byte tag.

**Wrapped key.** Vault key 32 bytes of `2a`, passphrase `YZTR-THFW-WT6E-OXIV-73XD-QCDM`, salt
`c0 c1 … df`, iterations 600,000, nonce `d0 d1 … db`. The record is **100 bytes**:

```
4f464b31c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf000927c0d0d1d2d3d4d5
d6d7d8d9dadb01a685bb1548f10f769b3bc1a1b7fe0a47ca50d52f06e4fd25a85b77ea3b299ddfa536edb22eb16f
ea7eb8d4c7eea3bf
```

`000927c0` at offset 36 is 600,000, and a reader must take the count from there rather than
assume the number it would write with.

## Getting the key onto a device

### The passphrase

Read the wrapped record, ask, derive, unwrap, write the vault key to the container.

**Absent is not wrong.** If the record has not arrived, the app says the vault has not reached
this device yet. A correct passphrase must never be reported as incorrect because a record is
still in flight.

### A paired watch

Typing 24 characters on a wrist is not a design.

*Implemented as `WatchProvisioning` in PR 16d, with the negative controls from gate E7 kept as
tests.*

```
Watch                                            Phone

 generate w_priv / w_pub, and a 16 byte nonce
 ── "OFW1" ‖ nonce ‖ w_pub ───────────────────►                          85 bytes
                                    generate ephemeral p_priv / p_pub
                                    shared     = ECDH(p_priv, w_pub)
                                    transcript = "OFW1" ‖ nonce ‖ w_pub ‖ p_pub
                                    kek        = HKDF-SHA256(shared, salt = empty,
                                                   info = "openfactor.vault.watch.v1" ‖ transcript)
                                    sealed     = AES-256-GCM(kek, vaultKey, aad = transcript)
 ◄── "OFW1" ‖ nonce ‖ p_pub ‖ sealed ──────────                         145 bytes
 check the nonce is the one just sent
 recompute shared and kek, open, write to container, never ask again
```

```
field         size   notes
"OFW1"           4   magic and version. A version 2 changes these rather than reusing them
nonce           16   from the system CSPRNG, fresh per attempt
public key      65   P-256, x963 representation
sealed          60   12 byte nonce, 32 byte ciphertext, 16 byte tag
transcript     150   the four fields above, in the order they were sent
```

**The phone needs its own ephemeral keypair.** The first draft wrote "ECDH, then HKDF, then seal
to the watch's public key" as though that were one primitive. ECDH needs a private key on both
sides; what it described was ECIES with half missing.

**The whole transcript is bound**, version, nonce and both public keys, into the HKDF info and
the AAD. **The HKDF salt is empty**, deliberately: the transcript is already in `info`, and a
salt would be a second place to get the same job wrong. The nonce is what makes a replayed
response detectable, and the watch checks it **before deriving anything**. The phone echoes it in
a refusal too, so a decline of an abandoned attempt cannot end a live one; that is matching rather
than authentication, since a refusal releases nothing.

**The refusal is a third message, and it is not versioned the way the two above are.** The two
payloads carry `OFW1` inside themselves. A refusal is a WatchConnectivity dictionary with a
`status` key, and the echoed nonce rides beside it under a `nonce` key, outside any magic. A
second implementer working from the byte tables above would not know to expect it, which is why
it is written down here:

```
key      type    notes
status   String  "asking", "busy", "needsApp", "noVault" or "declined"
nonce    Data    16 bytes, present on a standalone decline, echoing the request refused
```

**Only a standalone refusal carries the nonce.** A refusal sent as the direct reply to a request
does not, and does not need one: it travels back through the reply handler of the message that
asked, so it is bound to its request by the channel rather than by a field. There is also nothing
to echo, because the only request answered that way is one that failed to parse. Round five of gate
A4 found this page claiming every decline carries a nonce while a current build sent one that did
not.

The compatibility rule is deliberate and asymmetric. **A standalone decline carrying no nonce is
honoured**, because it comes from a phone built before this field existed, and the cost of being
wrong is one
screen that says to try again. An earlier version of this sentence said refusing it would strand a
watch, which is false and was corrected in the code before it was corrected here: the twenty five
second timeout ends every wait at a screen with a button on it. **A decline carrying a nonce that is not this attempt's is
ignored**, which is the whole point of the field. An older watch reads neither and ignores the key
entirely, leaving it exactly the behaviour it already had for declines.

**`busy` is the one answer that changes what an older watch does**, and the compatibility
paragraph above does not cover it, which round three pointed out. A watch built before this answer
existed fails to construct it from the wire value and falls to its rule for anything it cannot
read, which is to treat the answer as a refusal. It shows "not set up, try again" at once where it
would previously have shown a spinner until its own timeout. That is arguably the kinder of the
two, and it is a behaviour change rather than the no-op the nonce key is. A version 2 of the two payloads would
change `OFW1`; this dictionary would need its own answer, and does not have one yet.

### There is no six digit comparison, and what that costs

Earlier versions of this page specified one, and said it was what made routing exclusivity
**defense in depth instead of load bearing**. It is gone. Two reasons, and the second one is the
honest cost.

**It could not do what this page claimed.** The page said the person confirms the strings match
*before the phone releases the sealed key*. The watch derives its string from the transcript,
which contains the phone's public key, and that public key arrives **in the same message as the
sealed key**. At the moment of confirming, the genuine watch has nothing to display. The
comparison could only ever have been after the fact, which is not what was claimed. Making it
work would have taken a third message; that was weighed and rejected below.

**So routing exclusivity is now load bearing.** WatchConnectivity connects an iOS app to its own
companion watch app rather than to arbitrary apps. Gate E5 measured a same-team sibling
activating a session and reaching nothing, and a rogue counterpart would have to ship inside
OpenFactor's own bundle, which is a malicious OpenFactor build and already out of scope. **Apple
does not document this as a security guarantee**, and the rogue counterpart case remains
unmeasured. That is the assumption this exchange rests on, written here rather than implied.

**Why the third message was rejected.** It would have restored the claim at the cost of a six
digit comparison performed on a wrist, which is a step people tap through rather than perform. A
defense that is not carried out is worth less than one that is named honestly and not carried
out at all.

**The human gate is on the phone.** The key file is `.complete` protected, so the phone must be
unlocked and foregrounded to read it, and the app asks before it answers. The key never moves
because two apps happened to be open.

**The interactive channel only.** Queued transfer modes persist payloads to disk while waiting.

**The phone must be foregrounded and unlocked** to read its own container, and says so rather
than failing silently. **If the phone has no key itself**, which happens when both are replaced
together, it says that instead, and the watch retries after the phone is recovered.

The watch's private key is `P256.KeyAgreement.PrivateKey`, CryptoKit's software key, held in
process memory. It is ephemeral, generated per attempt and never persisted. **An earlier version
of this paragraph said it may live in the Secure Enclave; nothing here uses `SecureEnclave.P256`
and nothing ever has.** Found in gate A4, and recorded rather than quietly deleted because a
reader may have relied on it.

**It is not discarded the instant the exchange ends**, and an earlier version of this paragraph
said otherwise. An attempt is deliberately kept through a timeout, because a slow answer is
still a good answer, and `WatchProvisioning.Attempt.open` is non-mutating and enforces nothing
about being opened once. What prevents a stale attempt being spoken for is
`WatchProvisioningFlow`, which issues a token per attempt and ignores any callback carrying an
older one. That is a bound on liveness rather than on secrecy: the key never leaves memory and
never outlives the process either way.

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
way to tell them apart. Both must be labeled where shown and where asked for.

**The watch's empty state does not gain a third cause after all.** This asked for one, on the
assumption that a watch with no key would still reach the list. It does not: `WatchVaultGateView`
stands in front of it, so "no accounts yet" keeps meaning exactly what it meant, and the states
that belong to provisioning have screens of their own. Specified in `docs/UI_SPEC.md`.

*The watch's screens exist as of PR 16d. Asking is automatic, since every message on them ends by
telling somebody to do something on their phone, and returning to the app tries again.*

**A device can hold a key that opens nothing, and must notice.** This page had no word for that
state and the first implementation had no check for it. Replacing the vault, which is what
erasing everything and setting up again does, leaves any other device holding the old key while
every record that arrives is sealed under the new one. Found on hardware: a watch reported zero
accounts while fifteen sat in its Keychain unopened.

**The signal is records present and not one of them readable**, which is
`StoredRecords.suggestsAWrongKey`. Both halves are load bearing. No records at all is an empty
vault or one still arriving, and a device that discarded its key on an empty read would do so
every time it got ahead of iCloud. A mixture is a record from a newer version beside ones this
build understands, which is what `unreadable` was for and has nothing to do with keys.

**A device may act on it once**, and must believe the second answer. The watch re-provisions and
then re-reads; if a freshly installed key still opens nothing, the cause is a format this build
does not understand and asking again would fetch the same key forever.

*Both implement it as of PR 16d.* The phone needs no new screen and no new words for it: the
unlock screen's sentence is true either way, because a device holding the wrong key does not have
the key that unlocks these accounts, and entering the passphrase reads the current wrapped record
and installs over whatever is there.

*The phone's two screens exist as of PR 16d.* `VaultGateView` stands between the app lock and the
account list and renders one of four things, the fourth being the screen for a store that cannot
be read at all, added when gate A4 found a read failure being reported as an empty device. The list is never drawn while the key is missing:
to it a locked device is a shelf of unreadable rows, which is a true statement about the storage
and a frightening and wrong one about somebody's accounts.

**Nothing that holds the passphrase may be owned by a view that can be torn down.** Found by a
tester: he copied it, went to another app to paste it, and came back past the App Lock grace
period to a screen offering to create a vault. App Lock replaces the root view, which destroyed
the object holding the only copy. He was then holding a passphrase that opened nothing, with
nothing on screen to tell him so, which is worse than losing his place.

The state lives on the app now, above the lock. **It is still never persisted**, and it still
does not survive the process being killed; nothing can fix that without writing it down, which is
the one thing this design will not do. What it does survive is every ordinary interruption:
locking, switching apps, and coming back.

**The passphrase is generated before the vault is, not after.** `Vault.create()` creates and then
returns the string, so a process killed in that gap leaves a vault whose passphrase no longer
exists anywhere. The screen therefore generates, shows, waits for the acknowledgement, and only
then calls `Vault.create(with:)`. Until that call nothing has been written and leaving costs
nothing. This is what turns the obligation above from a description into something a test can
assert, and `VaultGateModelTests` asserts it.

**Creation is a button somebody presses and never something the app does on its own.** Absent and
locked are indistinguishable for as long as iCloud Keychain takes to deliver the wrapped record,
measured here at close to half an hour. The setup screen says what waiting looks like, offers to
check again, and states plainly that a second vault would leave the first one's accounts
unreadable. The state is re-read whenever the app comes forward, so a record arriving while the
screen is open moves the device to the unlock question by itself. **Only a record does that.** A
store that cannot be read at that moment leaves the passphrase where it is, because not knowing is
not evidence that the displayed passphrase should be abandoned, and abandoning it silently leaves
somebody holding a string that opens nothing.

**That last sentence was true of one of the two setup screens and claimed both**, which gate A4
found. Re-reading returned early whenever a generated passphrase was on display, so a record
arriving at exactly the moment somebody was writing one down changed nothing, and the button
that followed tried to create a second vault over the first one's record. Two things were done
rather than one: the re-read now moves away from the passphrase screen when a record has actually
arrived, leaving it alone in every other case so that a scene becoming active cannot clear a
passphrase somebody is mid-way through copying; and creation refuses when a record is already
there.

**Both halves were then found insufficient in the next round, and this paragraph is what they were
corrected to.** The re-read's first condition moved away on anything that was not `absent`, which
included a transient read failure, so the screen could still be cleared under somebody's pen; it
now moves only on evidence, meaning a record or a key. And creation's refusal was a check hundreds
of milliseconds before the write, with 600,000 rounds of PBKDF2 in between: a record arriving
inside that window was overwritten by the very save the check was supposed to prevent. Creation
uses a write that refuses to replace anything, rather than a check that hopes nothing changes.

**The setup screen says nothing about iCloud, deliberately.** Sync is off by default, so the
first person to read that screen always has it off, and a paragraph about what iCloud carries
would describe something that is not happening. Two claims were wrong for that reason and are
gone: that the passphrase is the only way to reach your accounts from a new iPhone, which is
false with sync off because nothing reaches a new iPhone at all, and that losing the passphrase
matters only if the iPhone is also lost, which is true only with sync on. What the screen says
instead is true in both configurations: the key never leaves this iPhone, anything else holding
the accounts holds them encrypted, and the passphrase is what rebuilds the key, most often after
a restore.

**The one place iCloud is named is the section about waiting**, because arrival is what that
section is about and arrival only happens with sync on. The condition is stated rather than
assumed: somebody whose other iPhone has sync off will wait forever, and telling them to wait
would be the same false promise in a politer form. Note that whether the record arrives does not
depend on *this* device's sync preference: the record carries its own synchronizable attribute
and `WrappedKeyStore` queries with `kSecAttrSynchronizableAny`, so a phone with sync off still
sees a record another phone synced.

**The locked screen must offer a way out, or the app is a permanent dead end.** A reinstall whose
passphrase is lost can never open its accounts, cannot reach Settings to erase them, and does not
recover by deleting the app: the Keychain outlives it and iCloud returns whatever did clear. The
erase flow is therefore reachable from the locked screen with its Face ID and typed word intact.
It works there because `records()` needs no key and reports every account as unreadable, which is
exactly enough to delete them. The vault is destroyed only **after** the accounts are gone; the
other order would leave ciphertext with no key anywhere and no screen left to remove it from.

**A Debug-only reset exists and must never ship.** `VaultGateModel.forgetEverything(in:)`
removes every account, the vault, and the preferences, returning the device to an install that
has never been run. It exists because the setup screen can otherwise be read once per device and
never again, which makes working on its wording a loop of deleting the app, reinstalling, landing
on the unlock screen and starting over. It is inside `#if DEBUG`, its row in Settings is keyed off
an environment value only the gate sets, and a Release binary is checked to contain neither
string. It sits on the model rather than in the view because a private method on a `View` cannot
be tested, and a destructive path nobody can check is not worth adding even to a Debug build.

*`KeychainSecretStore` has written this format since PR 16d: it seals on write, opens the
metadata half to list, and opens the secret half only in `secret(for:)`. `update` re-seals
metadata and copies the secret half verbatim, so a rename never decrypts a secret.
`kSecAttrGeneric` is never written.*

*The word "converted" used to stand at the head of that sentence, directly above a section titled
"Migration, and why there is no converter". Nothing converts anything: the format changed before
anybody but the maintainer had items, and the next section is the argument for why no converter
was written. A review read the two together and took them for a contradiction, correctly.*

## Migration, and why there is no converter

**There is none, deliberately.** The first draft said plaintext items are erased, and the V1
audit called that blocking because nothing scoped it: the same path would have fired on whoever
installed next, silently, in an app whose erase feature is gated behind Face ID and a typed
word. The objection was to the **silence**, not to the absence of a converter, and the
distinction matters because it changes what is owed.

Who holds plaintext items is a closed set. The app has never been released, so only the two
TestFlight testers do, and both confirmed the data is disposable. Nothing creates more: turning
iCloud sync on flips `kSecAttrSynchronizable` in place and touches no format, a new device is
the passphrase path rather than a conversion, and a later format change is `OFV1` to `OFV2`,
which is what the version bytes are for.

So a converter would run at most twice and then live in the codebase forever as its least
exercised path, in the area where this project's own history says failures happen: PR 14's
access group migration is where "my accounts vanished" came from.

**What exists instead is detection, which the store already does.** A legacy item fails to open
as a record and is reported through `StoredRecords.unreadable`, the same path a record from a
newer version takes, and the account list already shows a row for it. Nothing crashes, nothing
is destroyed, nothing is silently skipped, and the secret stays in the Keychain.

**What that row says had to change.** Before the vault, unreadable could only mean a newer
version had written the record, so the row promised that updating would show it again. That
promise is false for a legacy item, and false for precisely the people who would see one. It now
names both causes, likelier first, and points at export or the existing erase flow rather than
at an update that would not help.

Grok's finding that a conversion must clear `kSecAttrGeneric` is satisfied trivially by there
being no conversion: nothing writes that attribute any more, and a legacy item is erased rather
than rewritten.

**What would reopen this:** adding TestFlight testers before this ships. They would install a
pre-vault build and join the population, and a set that keeps growing is a different argument
from one of two people with disposable data.

## Invariants

- The **vault key** is never written to the Keychain, never synced, never backed up, never
  logged, and never leaves a device except sealed to a confirmed watch public key.
- The **passphrase** is never persisted in any form.
- **No plaintext secret** is ever written to a file, a container, or a log.
- No Keychain item carries **account** metadata in the clear, in `kSecValueData` or in any
  attribute. The service constant and the `"OpenFactor"` label identify the app rather than the
  person's accounts, and both are deliberate and already in the store today.
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
   still unmeasured is a rogue watch app *claiming to be* OpenFactor's counterpart. **This is
   blocking, and it is load bearing.** The sentence here used to call it defense in depth on the
   grounds that the six digit authentication string was the real protection, and to add that
   removing the string would make this blocking again. The string was removed, in the section
   above, and this line was not updated to match: `SECURITY.md` has said routing is load bearing
   since that day. Round three of gate A4 found the two documents disagreeing.
3. **Backup exclusion behaves as documented on a real restore**, and separately under Quick
   Start, which is a different mechanism.
4. ~~A watch can hold a P-256 private key and complete the exchange inside the message size
   limits.~~ **Measured**, `docs/audits/E7-exchange-and-queryability.md`: 85 bytes out and 145
   back against a 65,536 byte limit, both sides agreeing, and the negative control showing that a
   substituted key fails to open. That measurement was taken while the six digit string still
   existed, so it also recorded the string moving with the transcript; that half describes a
   construction this app no longer has, and is left here as history rather than as a property.
5. ~~An opaque service constant with UUID accounts leaves no queryability the store depends
   on.~~ **Settled by reading the store**, same record: it selects only by the service constant,
   the UUID, and the sync flag, and sorts in Swift. `kSecAttrGeneric` was never a selector.
6. **Rewrapping survives the two-writer case**, which this project has never tested, and which
   now applies to every account item rather than one. Blocked on a second device: only the
   iPhone and the watch are paired for development, and the watch is a reader under this design.
   See `docs/audits/E7-exchange-and-queryability.md` for what it would and would not establish.
7. **The container survives a restore and Quick Start.** Narrowed by
   `docs/audits/E6-container-durability.md` rather than closed. Measured there: the protection
   class and the backup exclusion both stick and both survive an update, and an app update
   preserves the data while **moving the container**, so nothing may ever cache the absolute
   path. Offload is not offered for a development install and stays unmeasured, though Apple
   documents it as preserving data. A restore and a Quick Start were not attempted, because
   both require wiping or newly configuring somebody's personal phone. **The backup exclusion
   is therefore verified as a flag and never as a restore**, and this document should not imply
   otherwise.
