# Security

OpenFactor holds the second factor for every account added to it. That makes it a high-value
target, so this document is meant to be read, not filed.

## Reporting a vulnerability

Report privately through
[GitHub Security Advisories](https://github.com/dragut-eth/openfactor/security/advisories/new).
Please do not open a public issue for a vulnerability.

Include what you did, what happened, and what you expected. A proof of concept helps.

You will get an acknowledgement within 7 days. There is no bug bounty. This is a small open-source
project, and the available reward is credit in the advisory unless you would rather remain
anonymous.

Please allow a reasonable window to ship a fix before publishing. If a fix is taking too long,
say so and we will agree on a disclosure date rather than let it sit.

## Threat model

This document is incomplete while the app is being built. The complete threat model is reviewed
in PR 17. A statement marked **implemented** describes code that exists. A statement marked
**vault design** describes a property specified in `docs/VAULT.md` that is not a release claim
until the current vault integration, migration, and implementation review are complete.

The distinction matters. A security design can be sound while the product implementing it is
unfinished or wrong.

### What OpenFactor protects

The primary assets are the HOTP and TOTP secrets that generate verification codes. Anyone holding
one can generate valid codes without the device and without the account owner's knowledge. The
secret can be revoked only by re-enrolling with the service.

Account metadata is sensitive too. Issuers and account names reveal which services someone uses
and often the address or identity used there. The vault therefore encrypts metadata as well as
secrets.

Availability is a separate property. Encryption can prevent a reader from learning a secret. It
cannot stop an authorised Keychain writer from deleting or replaying encrypted records.

### Another app signed by the same developer team

**Vault design, supported by hardware experiments.** OpenFactor does not treat a Keychain access
group as a confidentiality boundary. Gate E1 demonstrated that another app signed by the same
team can be authorised to read items in any of that team's Keychain access groups, including the
default group.

The vault is the response. Keychain contains encrypted account records and a wrapped recovery
key. The key that opens account records is stored only in the app's private container. Gate E4
demonstrated that a sibling app holding the exact container path was refused by the operating
system and could not enumerate it.

Reading OpenFactor's Keychain items should therefore reveal ciphertext, record identifiers,
timestamps, and approximate padded sizes, but not account names or secrets.

This does not provide integrity or availability. A sibling app that can read the items can also
replace, replay, or delete them. Those cases are addressed separately below.

### Attacker with your locked device

**Vault design.** The vault key file uses the `.complete` protection class. It is unavailable
while the device is locked and is excluded from device backups. The file is located through
`FileManager` on every access because a real app update was observed preserving the file while
moving the container that held it.

Account records are also protected by the Keychain. With sync off they use
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. With sync on they must use
`kSecAttrAccessibleWhenUnlocked`, because a synchronizable item cannot be tied to one device.
Under the vault design this change affects the ciphertext and its availability elsewhere; it
does not place the vault key in Keychain or cause that key to sync.

The backup exclusion and protection attributes have been verified on a real device. Their
behaviour through a restore and Quick Start has not been measured and is not claimed.

### Attacker with your unlocked device

**Implemented in PR 15.** Two defences exist, one always on and one optional.

**The app switcher never contains a code.** iOS photographs the app as it leaves the foreground
and shows that photograph in the app switcher. OpenFactor covers itself as soon as it stops being
active, so the captured surface is blank. This protection does not depend on App Lock.

**App Lock, off by default,** requires Face ID, Touch ID, or the device passcode before anything
is shown, on launch and on return from the background after a configurable grace period. A clock
that moved backwards while the app was away counts as expired because it is indistinguishable
from tampering and the cost of being wrong is one prompt.

App Lock is a gate in front of the interface, enforced by this app's code. It is not encryption.
It protects against a borrowed phone, a phone left unlocked on a desk, or a phone taken while it
is open. An attacker able to run code as OpenFactor is already past it.

App Lock fails closed. If the device passcode is removed after App Lock was enabled, the app stays
locked with an explanation rather than quietly opening. App Lock cannot be enabled on a device
with no passcode.

The Watch has no separate App Lock. It relies on the Watch passcode and wrist detection, which
locks the device when it leaves the wearer's wrist.

### Attacker with your iCloud account

Sync is off by default. **Vault design:** when it is enabled, iCloud Keychain carries encrypted
account records and the wrapped vault key. The vault key itself never syncs.

Someone who recovers the Keychain material obtains ciphertext and the recovery record, not a
plaintext account. Recovering the vault on a new device also requires the generated vault
passphrase, which is shown once and never persisted by OpenFactor.

This makes Apple's Keychain escrow relevant to availability rather than the confidentiality of
the account plaintext. If every device is lost, the ciphertext and wrapped key must return before
the passphrase has anything to unwrap. A missing wrapped record must be reported as data still in
flight or unavailable, never as a wrong passphrase.

Apple Account security still matters. An attacker able to delete or replace synchronized
Keychain items can damage availability even without opening them. A strong Apple Account password,
two-factor authentication, and a strong device passcode remain important defences.

Turning sync on and off does not decrypt account records. The conversion updates Keychain
attributes in place. Both account records and the wrapped key follow the same sync preference.
The vault key file does not.

### What turning sync off does

**Implemented and observed on real hardware.** The accounts stay on the device where sync was
disabled, stop being offered to iCloud Keychain, and return to the device-only protection class.

They disappear from other devices. A paired Watch became empty after sync was turned off on its
phone, and repopulated after sync was enabled again. Turning sync off therefore affects the Watch
and every other device using those synchronized records. The interface must say so before the
change rather than after another device appears empty.

The device preference and Keychain can disagree. The switch is remembered per device in
`UserDefaults` and written only after the Keychain work succeeds. A conversion stopped part way
can leave a mixture, and an account synchronized from another device can arrive regardless of
this device's preference.

The app reports the observed Keychain state rather than silently reconciling it. An arrived
record is indistinguishable from a half-converted one, and pulling it out of sync automatically
could affect every device.

Sync is a request, not proof of delivery. Marking an item synchronizable offers it to iCloud
Keychain. There is no public API that tells the app whether iCloud Keychain is enabled or whether
a particular item has reached another device, so the interface does not claim either.

### The Watch is another device holding the vault key

**Vault design.** Account records reach the Watch as ciphertext through iCloud Keychain. The
vault key does not. It is provisioned once from an unlocked, foregrounded phone over the
interactive WatchConnectivity channel.

The Watch and phone each generate an ephemeral P-256 keypair, derive a shared secret with ECDH,
and bind the protocol version, request nonce, and both public keys into the HKDF context and
AES-GCM additional data. Both screens show a six-digit authentication string derived from the
same transcript. The person provisioning the Watch confirms that the strings match before the
phone releases a sealed vault key.

The protocol and byte layouts are specified in `docs/VAULT.md`. The cryptographic exchange has
been exercised with negative controls, and a sibling phone app was unable to reach another app's
Watch session. A rogue Watch app claiming to be the counterpart remains unmeasured. The human
authentication string keeps routing exclusivity from being the only defence.

After provisioning, the Watch holds a vault key in its own protected container and can generate
codes without the phone. Treat a lost provisioned Watch as a lost authenticator. The complication
holds no key, no account data, and no Keychain entitlement.

### Deletion, replay, and missing data

**Vault design, not yet complete.** AES-GCM detects modification of a record. It does not detect
an old valid record being replayed, and it cannot stop deletion.

A container-resident anchor is intended to record that a vault exists. If the anchor exists and
Keychain suddenly contains no account records, OpenFactor must report data missing rather than
presenting an empty new vault. Keeping that tripwire accurate across legitimate changes from
multiple devices is not solved yet. Replay detection across multiple writers is also unsolved.

The encrypted export is the recovery backstop. The tripwire detects some destruction; it does not
restore what was deleted.

### Passphrase replacement is not revocation

**Vault design.** Replacing the vault passphrase wraps the same vault key under a new passphrase.
It does not rotate that key. Anyone holding an older wrapped-key record and its old passphrase can
still recover the vault key.

Responding to a suspected compromise requires a new vault key, re-encryption of every account, a
new recovery passphrase, and reprovisioning every other device. Version 1 does not implement that
rotation path and must not present a passphrase replacement as though it did.

### Device loss and recovery

The vault passphrase is generated with 120 bits of entropy, shown once, acknowledged, and never
stored by OpenFactor. A new phone recovers by receiving the wrapped-key record, asking for the
passphrase, unwrapping the vault key, and installing it in the new private container.

With sync off, the wrapped key exists only on that device. Losing the device then loses the vault
unless an encrypted export exists. This is deliberate and must be stated before someone disables
sync.

The vault key is excluded from device backups. Restore and Quick Start behaviour has not been
verified end to end on real hardware, so seamless recovery through either path is not promised.

### Attacker on the network

**Implemented.** There is no network code. The app makes no requests of its own, so there is
nothing from OpenFactor to intercept. CI searches every Swift file for `URLSession`, the
`Network` framework, raw sockets, and logging, and fails if any appears.

iCloud Keychain traffic is the operating system's, not this app's. The interface therefore says
that OpenFactor makes no network requests of its own.

### Malicious or compromised dependency

There are no third-party dependencies. The supply chain is this repository, the Swift toolchain,
and Apple's platform frameworks.

Cryptography comes from CryptoKit, with one exception. CryptoKit has no password-based key
derivation, so PBKDF2 comes from CommonCrypto. Both are Apple frameworks and neither is vendored.
The HOTP dynamic truncation required by RFC 4226 is the only cryptographic construction written
directly in this repository, and it is tested against the RFC vectors.

### Attacker who publishes a modified build

The public source does not prove that a distributed binary was built from it. Reproducible build
notes are planned for PR 18 so a third party can compare a released binary with the tagged source.
Until then, this remains an open supply-chain limitation.

### System-added menu entries

**Known and accepted, to be re-examined in PR 17.**

Long-pressing an account card opens a system context menu. iOS may add entries that OpenFactor
does not define. On current systems that can include an assistant action. Invoking a system-added
action may pass visible content, including a live code and account name, to a service that can
process requests away from the device.

The app does not control those entries and cannot verify externally exactly what they transmit.
Anyone for whom that matters can disable the relevant system assistant features, which removes
the entry. PR 17 must either establish the behaviour or preserve the limitation explicitly.

### Explicitly out of scope

- A jailbroken or already compromised device. If the operating system is controlled, nothing in
  this app can restore the boundary.
- A malicious Xcode toolchain or compromised Apple platform.
- Shoulder surfing, physical coercion, or someone using a device that is already unlocked and
  authenticated to OpenFactor.
- A plaintext export the user deliberately creates after an explicit warning and acknowledgement.
  Portability requires this path, and the resulting file contains every exported secret.
- An archive stored badly. Once bytes are in a file, the device passcode, Secure Enclave, Keychain
  protection class, and vault container no longer protect it. See `docs/BACKUP_FORMAT.md`.
- Phishing. HOTP and TOTP codes can be entered into a convincing fake site. OpenFactor does not
  make these protocols phishing-resistant.

## The privacy manifest

`OpenFactor/PrivacyInfo.xcprivacy` is the machine-readable form of the privacy claims above. It
declares no tracking, no tracking domains, no collected data types, and one required-reason API:
`UserDefaults`, used for the app's own preferences.

Those preferences include sort order, appearance, chosen icon, sync preference, and App Lock
settings. They never include a secret, account name, vault key, or passphrase.

## Credentials and this repository

No credential belongs in this repository. CI refuses private-key blocks, credential files, and
values shaped like the App Store Connect credentials used by the release process.

The Apple development team identifier is the deliberate exception. It is not a secret, appears
inside signed applications, and is documented in `docs/PROJECT.md`.

## Practices in this repository

- Security-sensitive code lives in `OpenFactorCore`, a package with no UI and no third-party
  dependencies, so it can be reviewed in isolation.
- The cryptography comes from CryptoKit and CommonCrypto. Published formats have pinned test
  vectors so a rewrite can be checked against fixed bytes rather than only itself.
- The HOTP and TOTP generators are verified against the official RFC test vectors in CI.
- Secrets are never logged and are never sent to analytics because there is none. Under the vault
  design they are plaintext in memory only while an operation needs them, such as generating a
  code or producing an explicitly requested export.
- Metadata and secrets are sealed separately inside one account record. Drawing the list opens
  only the metadata half. Generating a code opens the secret half for that account only.
- The vault key is never written to Keychain, synchronized, backed up, placed in an App Group, or
  logged. Its only device-to-device path is the authenticated Watch provisioning exchange.
- Findings from design reviews, implementation reviews, and hardware experiments are kept under
  `docs/audits/`, including findings that required the design to change.
- The account card uses a system context menu, and the operating system may append actions of its
  own. The threat model above records the resulting uncertainty rather than attributing those
  actions to OpenFactor.
