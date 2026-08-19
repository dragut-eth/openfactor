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

**This is the PR 17 review.** Every claim below was checked against the code as it stands rather
than carried forward from when it was written, and three of them were wrong and are corrected in
place: that the Watch screens were unbuilt, that nothing here had been reviewed, and that the app
switcher never contains a code.

Claims carry their basis, because "we believe this" and "a machine fails if this stops being
true" are different kinds of statement and a reader deserves to know which one they are getting:

- **Measured** means observed on real hardware, once, by a person. It can rot silently.
- **Tested** means something in this repository fails if it stops being true.
- **Reasoned** means it follows from the design, and nothing checks it automatically.

A statement marked **vault design** describes a property specified in `docs/VAULT.md` that is not
yet built. One remains, the tripwire. There is deliberately no migration path; `docs/VAULT.md`
explains why a converter would be the least exercised code in the project.

**Two independent implementation reviews have happened**, which an earlier version of this
document denied. A second model reviewed App Lock's presentation core and found a real leak, an
unlock landing after backgrounding that tore the lock window down over a live interface, before
that build reached a device. A cold review of the Watch key exchange, run with no prior context,
found no fault in the cryptography and four defects around it, all fixed. **Two of the four were
not covered by any test**, which a later reviewer found by reading this sentence against the code:
the phone's request handling has no tests at all because it lives in the app target, and the
CSPRNG failure path had none either. That is what a claim marked **tested** must never mean, and
it is why the basis labels exist.

**Neither is a professional audit.** Gate A4 in `docs/ROADMAP.md` is that, and it has not
happened. A security design can be sound while the product implementing it is unfinished or
wrong, which is the distinction this whole document turns on.

### Where the five attackers are answered

`docs/ROADMAP.md` names five for this review. They do not map one-to-one onto sections, because
some are answered in several places and some sections answer more than one, so this is the index
rather than a restructuring:

| Attacker | Answered in |
| --- | --- |
| Your unlocked device | Attacker with your unlocked device; The clipboard; System-added menu entries |
| Your locked device | Attacker with your locked device; Another app signed by the same developer team |
| Your iCloud account | Attacker with your iCloud account; What turning sync off does; Deletion, replay, and missing data |
| The App Store binary | Attacker who has the App Store binary; Attacker who publishes a modified build |
| A malicious dependency | Malicious or compromised dependency; Attacker on the network |

Two further attackers are answered here that the roadmap did not name, and both came from
hardware experiments rather than from reasoning: a sibling app signed by the same team, which
gate E1 showed can read this team's Keychain items, and a device holding the vault key that is
not this one, which is the Watch.

### What OpenFactor protects

The primary assets are the HOTP and TOTP secrets that generate verification codes. Anyone holding
one can generate valid codes without the device and without the account owner's knowledge. The
secret can be revoked only by re-enrolling with the service.

Account metadata is sensitive too. Issuers and account names reveal which services someone uses
and often the address or identity used there. The vault therefore encrypts metadata as well as
secrets.

Availability is a separate property. Encryption can prevent a reader from learning a secret. It
cannot stop an authorized Keychain writer from deleting or replaying encrypted records.

### Another app signed by the same developer team

**Implemented on iPhone and Watch in PR 16d. Measured: gates E1 and E4 on real hardware.**
OpenFactor does not treat a Keychain access group as a confidentiality boundary. Gate E1
demonstrated that another app signed by the same team can be authorized to read items in any of
that team's Keychain access groups, including the default group.

The vault is the response. Keychain contains encrypted account records and a wrapped recovery
key. The key that opens account records is stored only in the app's private container. Gate E4
demonstrated that a sibling app holding the exact container path was refused by the operating
system and could not enumerate it.

Reading OpenFactor's Keychain items should therefore reveal ciphertext, record identifiers,
timestamps, and approximate padded sizes, but not account names or secrets.

This does not provide integrity or availability. A sibling app that can read the items can also
replace, replay, or delete them. Those cases are addressed separately below.

### Attacker with your locked device

**Implemented in PR 16d.** The vault key file uses the `.complete` protection class. It is unavailable
while the device is locked and is excluded from device backups. The file is located through
`FileManager` on every access because a real app update was observed preserving the file while
moving the container that held it.

Account records are also protected by the Keychain. With sync off they use
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. With sync on they must use
`kSecAttrAccessibleWhenUnlocked`, because a synchronizable item cannot be tied to one device.
Under the vault design this change affects the ciphertext and its availability elsewhere; it
does not place the vault key in Keychain or cause that key to sync.

The key is written into a directory that is excluded from backup before any key material
exists, then moved into place, so there is no instant at which a complete key sits on disk outside
the exclusion. Reading the key also repairs its protection class and exclusion in place, because a
device provisioned before these rules were corrected would otherwise never write again and never
receive them.

The backup exclusion and protection attributes have been verified on a real device. Their
behavior through a restore and Quick Start has not been measured and is not claimed.

### Attacker with your unlocked device

**Implemented in PR 15 and extended in PR 17.** Three defenses exist, two always on and one
optional.

**The app switcher card never contains a code. Measured, repeatedly.** iOS photographs the app as
it leaves the foreground and shows that photograph in the switcher. OpenFactor covers itself as
soon as it stops being active, so that card is blank. This protection does not depend on App Lock.

**It holds because the app has exactly one window.** The lock and the cover are single windows
attached to the app's scene, and gate A4 found that the app was shipping with multiple scenes
enabled, so a second iPad window would have had neither. Multiple scenes are now declared off, the
assumption is stated where it would break, and CI fails if it is ever re-enabled without the lock
and cover being made per scene first. Split View and Slide Over beside another app are unaffected;
only a second window of OpenFactor is gone.

**It does not cover every picture iOS keeps of the app, and an earlier version of this sentence
claimed it did.** iOS holds a second snapshot cache, used for the zoom that plays when the app is
opened from the home screen, written at a moment the cover is not up. A screen recording read
frame by frame showed the previous screen there, with an account legible, for about a sixth of a
second before the lock appeared. It is not reachable from the app: the documented lever,
`ignoreSnapshotOnNextApplicationLaunch`, was tried and did nothing, and the behavior is on record
from iOS 7 onward with no answer from Apple. `docs/APP_LOCK.md` carries the evidence and the
reasoning. The durable artifact, the card anybody can browse to at leisure, stays blank; the leak
is a fraction of a second, visible only to somebody already holding the phone.

**Secrets are hidden while the screen is being captured.** iOS reports when the screen is being
recorded, mirrored, or shared, and OpenFactor follows that: codes become bullets, and a vault or
backup passphrase is withheld entirely and says why. Every screen that draws a live code masks it,
which gate A4 found was true of one screen out of three: the confirm-add and manual-entry previews
drew live digits regardless, and a code reaches the first of those from any `otpauth://` URL any
app can send. Measured on hardware with a screen
recording. This is a defense against **accidental broadcast**, which is the only kind it can be:
somebody sharing their screen in a meeting who opens the app for a code has not decided to show
it to anybody, and no document reaches them in that moment. It is not a defense against somebody
who wants to capture the screen.

The masking is deliberately partial. Cards, issuer names and rings stay visible so that
legitimately mirroring the app still shows something coherent rather than reading as a fault.
That means the list of services an owner holds accounts with is still visible while captured, and
unlike a code that does not expire. Accepted knowingly rather than overlooked.

**Screenshots cannot be prevented on iOS**, by any app, and OpenFactor does not pretend
otherwise. There is no public API for it. The one known technique, hosting content inside a
secure text field's internal layer, was considered and rejected: it depends on the undocumented
internals of a system control, and when Apple changes those it fails silently, keeps claiming
protection, and cannot be verified by any test this project can run. A security property that can
quietly stop working is worse than one honestly absent.

What is done instead is the only thing that helps: **on the two screens that display a
passphrase, a screenshot raises a warning naming the consequence.** The image is in Photos, it
may already be syncing to other devices and reachable from iCloud.com, and deleting it leaves it
in Recently Deleted for thirty days. That warning exists because those screens tell somebody the
passphrase is shown once and never again, which is the most reliable way ever devised to make a
person reach for a screenshot. It fires nowhere else, deliberately: for a code it would say
nothing actionable, and an alert that cries wolf is one people learn to dismiss.

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

### The clipboard

**The one place this app deliberately hands secret material to the rest of the system**, and the
behaviour below was measured on real devices rather than taken from documentation.

**A copied code may reach your other devices.** With Universal Clipboard enabled, a code copied on
the iPhone can be pasted on a Mac or iPad signed into the same Apple Account. This is deliberate.
The same bargain is already accepted for iCloud Keychain sync: Apple's transport, off until its
owner turns it on, documented rather than forbidden. Refusing it here while permitting it there
would be an inconsistency with no principle behind it, and it overrides a choice its owner already
made at the system level. It is also what every comparable authenticator does, so the earlier
behaviour read as OpenFactor being broken rather than as a protection.

**A copied code expires, but only on the device it was copied on.** The clipboard entry carries an
expiration set to the moment the code itself stops working, and the originating iPhone clears it
then. Measured: that expiry does **not** travel. On a Mac that received the code it remains on the
clipboard until something else replaces it.

**So the exposure, named rather than implied:** macOS shows no paste notification and lets any app
read the clipboard silently, and clipboard managers are common and keep their history on disk.
A code can therefore land in a searchable plaintext store and outlive its own validity there. This
is accepted for codes. Six digits that stop working in seconds are close to worthless once used,
and the person is typing them into that same Mac in any case.

**A backup passphrase never travels.** It is copied device-local, and that rule is load bearing
rather than tidy, precisely because the expiry does not propagate: a passphrase that reached
another device would sit in its clipboard, and in any clipboard manager's history, indefinitely.
A passphrase opens an archive holding every secret its owner has and never expires on its own, so
it is the one thing here that must not leave the device it was shown on.

**OpenFactor never reads the clipboard.** Nothing in the app inspects what is on it, so there is no
paste-snooping surface and no reason for the system to attribute a paste to this app. The Watch
app cannot copy at all.

### Attacker with your iCloud account

Sync is off by default. **Implemented in PR 16d:** when it is enabled, iCloud Keychain carries encrypted
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
two-factor authentication, and a strong device passcode remain important defenses.

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

**Implemented in PR 16d, screens included, and exercised on hardware.** The successful path, a
declined request, and a phone with no vault of its own have all run between a real phone and a
real Watch, along with recovery: the passphrase restored a dropped key, and a Watch that had just
been refused twice was provisioned afterwards with no reset and no reinstall, so a refusal is not
a dead end. Account records reach the Watch as ciphertext through iCloud Keychain. The vault key
does not. It is provisioned once from an unlocked, foregrounded phone over the interactive
WatchConnectivity channel.

The Watch and phone each generate an ephemeral P-256 keypair, derive a shared secret with ECDH,
and bind the protocol version, request nonce, and both public keys into the HKDF context and the
AES-GCM additional data. The Watch rejects a response that does not echo the nonce it just sent,
before deriving anything.

**A refusal names the request it refuses**, for the same reason. The decline message used to
carry only a status, so a refusal of an attempt the Watch had already abandoned ended the one it
was still waiting on. It echoes the nonce of the request being refused, and the Watch ignores a decline
meant for anything else. A decline carrying no nonce comes from an older build and is honoured,
which is a deliberate mixed-version choice rather than an oversight. This is matching rather than authentication, and is not claimed as more: a refusal releases
nothing, and the worst a forged one can do is end an exchange that can be started again.

**Consent expires.** A request that arrives while App Lock is up is accepted and its alert
suppressed until the phone is unlocked, with nothing previously bounding how much later that was.
Somebody could be asked to release the key on behalf of a Watch that stopped asking hours
earlier. A request is now answerable for two minutes of elapsed time, measured on a clock
that cannot be moved backwards, comfortably longer than the Watch's own retry cycle and short
enough that the question and the answer belong to each other.

The protocol and byte layouts are specified in `docs/VAULT.md`. The negative controls that make
the binding meaningful are kept as tests rather than only as a one-off experiment: a substituted
phone public key does not open the payload, a substituted Watch public key does not open with the
original attempt, an altered transcript derives a different key, and a response to a different
request is refused before any key material is derived.

**A cold independent review of this exchange found no fault in the cryptography** and four
defects around it, all fixed. The transcript binding is complete, the nonce is checked before
anything is derived, the transcript is the AEAD's additional data as well as the HKDF context,
and both parsers enforce exact length before any slice arithmetic. What it found instead were two
races in the Watch's asking flow that no test could reach while that logic lived in the Watch
target, a request substitution against the phone's own approval alert, malformed bytes reaching
the vault key and the human prompt before being parsed, and a discarded `SecRandomCopyBytes`
result that would have shipped a predictable nonce had the system ever refused. The flow
decisions now live in a tested value type in the core.

**Routing exclusivity is load bearing here, and that is a change.** An earlier design had both
screens show a six-digit authentication string so that routing would be defense in depth. That
comparison could not do what it claimed, because the Watch cannot derive the string until the
message that already carries the key, and restoring it would have cost a third message and a
digit comparison performed on a wrist. It was removed rather than kept as theater.

What the exchange now rests on is that WatchConnectivity connects an iOS app to its own companion
Watch app rather than to arbitrary apps. A sibling phone app was measured activating a session
and reaching nothing. **Apple does not document this as a security guarantee**, and a rogue Watch
app claiming to be the counterpart remains unmeasured; such an app would have to ship inside
OpenFactor's own bundle, which is a malicious build and separately out of scope.

The human gate is on the phone. The key file is unreadable while the device is locked, so the
phone must be unlocked and foregrounded, and the app asks before it answers.

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

**Implemented in PR 16d.** Replacing the vault passphrase wraps the same vault key under a new passphrase.
It does not rotate that key. Anyone holding an older wrapped-key record and its old passphrase can
still recover the vault key.

Responding to a suspected compromise requires a new vault key, re-encryption of every account, a
new recovery passphrase, and reprovisioning every other device. Version 1 does not implement that
rotation path and must not present a passphrase replacement as though it did.

### Device loss and recovery

**Reasoned, with one part measured.** The vault passphrase is generated with 120 bits of entropy,
shown once, acknowledged, and never stored by OpenFactor. A new phone recovers by receiving the
wrapped-key record, asking for the passphrase, unwrapping the vault key, and installing it in the
new private container.

With sync off, the wrapped key exists only on that device. Losing the device then loses the vault
unless an encrypted export exists. This is deliberate and must be stated before someone disables
sync.

The vault key is excluded from device backups. Restore and Quick Start behavior has not been
verified end to end on real hardware, so seamless recovery through either path is not promised.

A device holding records it cannot open must not become a dead end. It cannot reach Settings to
erase them, and deleting the app does not help, because the Keychain outlives it and sync
returns whatever did clear. The unlock screen therefore offers the same erase flow, behind the
same authentication and typed confirmation, and destroys the vault only after the accounts are
gone.

### Attacker on the network

**Implemented, and checked at two layers.** There is no network code. The app makes no requests
of its own, so there is nothing from OpenFactor to intercept.

CI enforces this against the source and against the artifact, and the two cover each other's
blind spot. The source check searches every Swift file for `URLSession`, the `Network`
framework, raw sockets, dynamic symbol lookup, and logging, and fails if any appears. The
binary check builds Release, finds every Mach-O in the bundle rather than naming them, and
fails if any links a networking framework or references a networking symbol; its patterns were
measured from a deliberately broken build that called `URLSession`, not guessed, because the
first draft missed the Objective-C class reference Swift actually emits and passed while lying.
The source check sees code the linker would strip; the binary check sees what ships.

What no check here can claim: iOS offers no entitlement that denies an app the network, so this
is evidence rather than a sandbox, and it says nothing about traffic Apple's own frameworks
produce on the system's behalf.

iCloud Keychain traffic is the operating system's, not this app's. The interface therefore says
that OpenFactor makes no network requests of its own.

### Malicious or compromised dependency

**Tested.** There are no third-party dependencies. The supply chain is this repository, the Swift
toolchain, and Apple's platform frameworks.

This was the one claim in this document that nothing enforced, sitting beside claims a machine
checks, and the supply chain is where a promise in prose is worth least: a dependency arrives by
somebody adding one line in a pull request about something else. CI now fails if `Package.swift`
declares a remote package, if the Xcode project gains a remote package reference, or if a
`Package.resolved` is ever committed. Proved in both directions, and the first version of the
check failed on a clean tree because it matched the reference kind the local core package uses.

Cryptography comes from CryptoKit, with one exception. CryptoKit has no password-based key
derivation, so PBKDF2 comes from CommonCrypto. Both are Apple frameworks and neither is vendored.
The HOTP dynamic truncation required by RFC 4226 is the only cryptographic construction written
directly in this repository, and it is tested against the RFC vectors.

### Attacker who has the App Store binary

**Reasoned, and the answer is that it matters less here than almost anywhere.** Anybody can
download the app and take it apart. They will find the same thing a reader of this repository
finds, because the source is public and the binary is built from it.

**Nothing secret is embedded in the shipped binary**, and there is nothing that could be: no API
key, no server, no account, no shared secret, no license check, and no obfuscation standing in
for any of those. Every secret this app handles arrives from its owner and lives in the Keychain
or the vault key file on their device. CI refuses credential-shaped strings and credential files
in the repository, so the same property is enforced upstream of the build rather than hoped for.

**Obfuscation is deliberately absent, and that is a position rather than an omission.** An
authenticator whose security depended on nobody reading it would be making the opposite claim to
the one on the front of this repository. Reverse engineering the binary yields the design, and
the design is meant to survive being known.

The one thing an attacker does learn from a binary they could not learn from the source is which
commit it was built from, and only approximately. See below.

### Attacker who publishes a modified build

The public source does not prove that a distributed binary was built from it. Reproducible build
notes are planned for PR 18 so a third party can compare a released binary with the tagged source.
Until then, this remains an open supply-chain limitation.

### System-added menu entries

**Re-examined in PR 17. The limitation is preserved rather than established, and this says why.**

Long-pressing an account card opens a system context menu. iOS may add entries OpenFactor does
not define, which on current systems can include an assistant action. Invoking one may pass
visible content, including a live code and an account name, to a service that can process
requests away from the device.

PR 17 was supposed to either establish the behavior or preserve the limitation explicitly. It
cannot establish it. What a system service transmits is not observable from inside the app, and
the network checks in this document deliberately prove something about OpenFactor's own binary,
which says nothing about what a system service does on its own behalf. Claiming to have verified
it would be the kind of false confidence this document exists to avoid.

**What is done rather than claimed:** the menu's preview is the card with its digits masked, so
a preview handed to a system feature carries the account but not a live code. That is a
narrowing, not a fix; the underlying view still holds the code, and an action that reads the row
rather than the preview is unaffected.

The menu is kept because the lift and preview are what make an account list feel native, and
removing it to defend against an entry the person can turn off in their own settings is a poor
trade. Anyone for whom it matters can disable the relevant assistant features, which removes the
entry entirely.

### Opening a file from elsewhere

**Implemented in PR 16c.** OpenFactor declares document types so a backup can be opened from
Files or a mail attachment. It declares `LSSupportsOpeningDocumentsInPlace` as `NO`, so the
system hands it a copy rather than the original, and the app never holds write access to a
document somebody else owns. The importer reads the copy, which is bounded before it is parsed,
and the same parser handles it as any other import.

### The share extension

**Implemented in PR 16c.** It exists so a transfer QR does not have to be saved to Photos first.
A transfer QR may contain every OTP secret in the vault, and Photos is a persistent store: with
iCloud Photos enabled the image can become part of the user's synchronized photo library,
accessible across their devices and through iCloud.com, and deleting it retains it in Recently
Deleted for up to 30 days. Avoiding that copy is the point of the extension.

**The app declares the two standard authenticator schemes and none of its own.** `otpauth` and
`otpauth-migration` are declared so iOS offers OpenFactor when the Camera app or Photos finds one
in a QR code. An earlier `openfactor` scheme, used to hand the app an item by name, was removed
once an extension turned out to be unable to open its containing app: nothing could produce it,
while every app on the device could still send one.

**Accepting a scheme is an entry point, and `otpauth://` carries the secret in the clear.** Two
consequences follow, and neither is avoidable while the scheme is supported. Any app on the
device can send OpenFactor a setup code; the guard is that it lands on the confirm screen and
nothing is saved until somebody has read the issuer and name. And the secret passes through the
system on its way in, rather than staying inside this process as it does when this app's own
camera decodes the frame. Anything that is not one of those two schemes, or a file URL, is
refused.

**An incoming code is bounded.** Every other untrusted input is: an imported file and a shared
image both cap at 8MB. The scanned path never needed a bound because a QR code cannot physically
hold more than about three kilobytes, and declaring a scheme removed that ceiling without
replacing it. A code arriving by URL is now capped at eight kilobytes, comfortably above a QR
code's alphanumeric capacity, so nothing that could really have been scanned is turned away and
no unbounded work is done on a sender's say so.

Files also open through declared document types, which is a different mechanism and does not
accept arbitrary senders.

Its security is what it cannot do. It declares one entitlement, the app group, and no Keychain
access, so it can neither read an account nor write one. It does not parse the QR, decode the
image, or read any import format; those stay in the app. It writes the bytes it was handed to a
group container with complete file protection and passes a URL carrying only an identifier.

**The shared App Group container is not treated as a confidentiality boundary.** A sibling app
explicitly authorized into that App Group could read the temporary inbox item. That is an
accepted exposure: the image exists there only during an explicit share operation, uses complete
file protection, is never synced by OpenFactor, contains no OpenFactor key material, and is
deleted immediately after the containing app consumes it. Any leftovers are swept when OpenFactor
launches.

Photos creates a different exposure. When iCloud Photos is enabled, the image can become part of
the user's persistent synchronized photo library, accessible across their devices and through
iCloud.com, and deletion retains it in Recently Deleted for up to 30 days.

**New signed target, new audit surface.** Gate A4 must cover it, and PR 18's reproducible build
notes gain another binary.

### Explicitly out of scope

- A jailbroken or already compromised device. If the operating system is controlled, nothing in
  this app can restore the boundary.
- A malicious Xcode toolchain or compromised Apple platform.
- Shoulder surfing, physical coercion, or someone using a device that is already unlocked and
  authenticated to OpenFactor.
- A plaintext export the user deliberately creates after an explicit warning and acknowledgement.
  Portability requires this path, and the resulting file contains every exported secret.
- A backup stored badly. Once bytes are in a file, the device passcode, Secure Enclave, Keychain
  protection class, and vault container no longer protect it. See `docs/BACKUP_FORMAT.md`.
- Phishing. HOTP and TOTP codes can be entered into a convincing fake site. OpenFactor does not
  make these protocols phishing-resistant.

## The privacy manifest

`OpenFactor/PrivacyInfo.xcprivacy` is the machine-readable form of the privacy claims above. It
declares no tracking, no tracking domains, no collected data types, and two required-reason
APIs.

`UserDefaults`, with `CA92.1`, for the app's own preferences: sort order, appearance, chosen
icon, sync preference, and App Lock settings. They never include a secret, account name, vault
key, or passphrase.

File timestamps, with `C617.1`, for one line: `SharedInbox.pending()` reads a modification date
to sort what the share extension left newest first and to sweep anything past the freshness
window unread. `C617.1` is the reason for files inside an app group container, which is where
the inbox lives.

That second entry was missing for as long as the freshness window existed, and nothing noticed,
because a missing declaration builds and runs and passes every test. CI now fails when a
required-reason API appears in source without a matching manifest entry, which is the same
answer this project gives elsewhere: an invariant that cannot be seen in review is asserted by a
machine rather than promised in a comment.

## Credentials and this repository

No credential belongs in this repository. CI refuses private-key blocks, credential files, and
values shaped like the App Store Connect credentials used by the release process.

**Nor does anything about the maintainer's circumstances.** A public repository reaches everybody
who clones it, and a document should say what was done and what it does not claim rather than why
some other option was not taken. CI refuses the crude phrasings, which is a backstop under a
judgment call rather than a substitute for one: the same fact said carefully would pass. It was
added after such a sentence was written into the roadmap, the handoff and a commit message, and
caught before any of it was pushed.

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
