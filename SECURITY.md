# Security

OpenFactor holds the second factor for every account you add to it. That makes it a high
value target, so this document is meant to be read, not filed.

## Reporting a vulnerability

Report privately through
[GitHub Security Advisories](https://github.com/dragut-eth/openfactor/security/advisories/new).
Please do not open a public issue for a vulnerability.

Include what you did, what happened, and what you expected. A proof of concept helps.

You will get an acknowledgement within 7 days. There is no bug bounty. This is a small
open source project and the honest answer is that the reward is credit in the advisory,
unless you would rather stay anonymous.

Please give a reasonable window to ship a fix before publishing. If a fix is taking too
long, say so and we will agree a date rather than let it sit.

## Threat model

Incomplete while the app is being built. Each entry is finalized in the PR that
implements the relevant behavior, and the whole document is reviewed in PR 17. Claims
marked *planned* are not yet true, because the code does not exist yet.

### What OpenFactor protects

Your TOTP secrets, meaning the shared keys that generate your codes. Anyone holding a
secret can generate valid codes forever, without your phone and without your knowledge.
There is no revocation short of re enrolling with the service.

### Attacker with your locked device

*Implemented and verified by test.* Secrets live in the Keychain with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. They are encrypted with a key derived from
your device passcode and the Secure Enclave, and are unreadable while the device is locked.
An attacker with the hardware and no passcode should get nothing.

**Turning sync on weakens this,** and there is no way to have both. A synchronizable
Keychain item cannot be device only, by definition, so switching sync on moves every
account to `kSecAttrAccessibleWhenUnlocked`. Still unreadable while the device is locked,
still tied to your passcode, but no longer pinned to this one piece of hardware. That is
the actual price of sync, and the settings screen says so in words before you pay it.

Your account names are protected too. The issuer and account name cannot generate a code,
but they say which services you use and under which email address, so they are stored in
the Keychain alongside the secret rather than in an ordinary file. They are encrypted at
rest and absent from unencrypted backups for the same reason the secrets are.

### Attacker with your unlocked device

*Implemented in PR 15.* Two defences, one always on and one opted into.

**The app switcher never contains a code, for anyone.** iOS photographs the app as it
leaves the foreground and shows that photograph to whoever flicks through the switcher.
OpenFactor covers itself the moment it stops being active, so the photograph is a blank
surface. This is not part of App Lock and obeys no setting, because the leak it closes
does not care about settings. Verified empirically: the pre fix snapshot was captured
showing a full settings screen, and the post fix snapshot is blank.

**App Lock, off by default,** requires Face ID, Touch ID, or the device passcode before
anything is shown, on launch and on return from the background after a configurable grace
period. A clock that moved backwards while the app was away counts as expired, because it
is indistinguishable from tampering and the cost of being wrong is one prompt.

**What App Lock is, stated exactly.** A gate in front of the interface, enforced by this
app's code, not encryption. The secrets are protected by the device Keychain with the lock
on or off, and an attacker who can run code as this app is already past both. What the
lock defends is the borrowed phone: handed over unlocked for a call, left on a desk,
snatched while open. The settings footer says this in as many words, because a user
deciding whether they need it deserves the real shape of it.

**It fails closed.** If the device passcode is removed after the lock was enabled, there
is nothing left to authenticate against, and the app stays locked with an explanation
rather than quietly opening. The lock also cannot be enabled on a device with no passcode,
since a lock that cannot lock is a false claim with a switch on it.

**The watch has no App Lock,** deliberately. Its lock is the one watchOS already has:
wrist detection plus the watch passcode, which locks the watch the moment it leaves the
arm. An app level lock on top would add a second prompt without adding a second barrier.

### Attacker with your iCloud account

*Implemented as of PR 13, and only relevant if you turn sync on. Off by default.* Sync uses
iCloud Keychain, which is end
to end encrypted, and Apple cannot read the synced items. Neither can someone who obtains
your iCloud password alone.

**The keys are escrowed with Apple, and saying otherwise would overstate this.** An earlier
version of this paragraph said the keys never leave your devices. Apple's platform security
documentation describes an escrowed copy, guarded by hardware security modules that verify
your device passcode without Apple seeing it, allow ten attempts, and destroy the record
after that. "Apple cannot read them" survives this; "never leave your devices" does not, and
the escrow is what makes recovery possible when every device is lost.

That gives an attacker two routes, and both need more than your iCloud password:

- **Join the circle of trust.** Your iCloud password plus one of your device passcodes adds
  a device that then receives your secrets.
- **Recover through escrow.** Your iCloud password, control of your trusted phone number,
  and a device passcode guessable inside ten attempts recovers the keychain with none of
  your devices present.

Two factor authentication on your Apple Account is therefore part of this app's security
rather than separate from it, and so is your device passcode. A long alphanumeric passcode
is the one thing you control that defends the escrow route directly. Gate A2, F15.

**Turning sync on and off never reads a secret.** The conversion updates each Keychain
item in place, so no secret is decrypted, no secret enters this app's memory, and there is
no moment when an account exists only as a variable that a crash could lose. The obvious
implementation, reading each account out and writing it back, would have all three
problems.

**What turning sync off does, precisely. Observed on real hardware on 2026-08-15.** The
accounts stay on this device, stop being offered to iCloud Keychain, and go back to the
device only protection class.

**They disappear from your other devices.** A paired Apple Watch holding ten accounts was
empty fourteen minutes after the switch was turned off on the phone. This document
previously expected the copies elsewhere to be left alone, and that expectation was wrong.
Apple's documentation for `kSecAttrSynchronizable` was right: updating an item through that
key affects all copies, and withdrawing an item from sync is such an update.

Nothing is deleted in the sense a user means by it. The other device never held an
independent copy, it had access to a shared one, and turning sync off withdraws the item
from the shared space. From the other device, withdrawn and gone are the same thing.

Turning sync back on restores them, and quickly: the same watch repopulated in under a
minute, against the roughly thirty minutes the first synchronisation took. So this is
reversible, but a user who turns sync off to stop copying their data around will find their
watch empty, and the interface has to say so before they do it rather than after they
wonder why their wrist stopped working. Gate A2, F8, closed by experiment.

**Your device preference and the Keychain can disagree, and the app says so rather than
repairing it.** The switch is remembered per device in `UserDefaults` and is written only
after the Keychain work succeeds. Three ways the two come apart: a conversion killed part
way leaves a mixture; an account synced from another device arrives here whatever this
device's switch says; and once sync has ever been on, copies may exist elsewhere regardless
of what the switch reads now.

Running the conversion again repairs the first case, because it is idempotent by design.
The app deliberately does not reconcile at launch: an arrived account is indistinguishable
from a half converted one, and "resolving" it would quietly pull that account out of sync
on every device.

That argument justifies not repairing. It does not justify not telling, which is what gate
A2 found. The settings screen now reads the Keychain rather than the switch when it says
where your accounts are, and says plainly when the two states are mixed. The delete
confirmation reads it too, because whether a deletion reaches your other devices is the one
thing in this app that cannot be undone. Gate A2, F9 and F12.

**Sync is a request, not a delivery.** Marking an item synchronizable offers it to iCloud
Keychain. If iCloud Keychain is off in iOS Settings, the conversion still succeeds and
nothing leaves the device. There is no public API to check that setting, so the app cannot
know and does not claim to. The interface names the prerequisite instead. Gate A2, F10.

### The watch is a device holding your secrets

*Verified on real hardware on 2026-08-14, and a direct consequence of the design chosen in
PR 13.* This is no longer a description of intent. A paired Apple Watch has been observed
reading an account created on the phone. The watch
does not receive secrets from the phone. It reads the same synced Keychain items, through a
shared access group, which is why it keeps working with the phone off or absent. The
consequence is worth stating plainly rather than leaving implicit in an architecture
document: **your paired watch holds your secrets, and it can generate your codes.** Treat a
lost watch the way you would treat a lost phone.

It also means the watch app needs sync on. With sync off there is nothing for it to read,
and it will say that rather than showing an empty list.

Nothing in the interface mentions the watch until the watch app exists. The sync footer
named it before PR 14 had started, which taught a reader their watch already held their
secrets. Gate A2, F11.

We do not use CloudKit for secrets. A CloudKit private database is encrypted, but with a
key Apple holds unless the encrypted fields API is used, and that is a weaker guarantee
than iCloud Keychain gives for free.

### Attacker on the network

There is no network code. The app makes no requests, so there is nothing to intercept.
This is verified in CI rather than asserted: the style job greps every Swift file in the
repository for `URLSession`, the `Network` framework, raw sockets, and logging, and fails
the build if any appears. It sweeps and excludes rather than naming directories, because
the first version named three and the project grew three more in the same pull request
that wrote it, leaving the shared folder and both watch targets unchecked while this
paragraph said the whole tree was covered. Gate A2, F19. Until gate A2 this sentence said the same thing while CI checked nothing, which is
exactly the plan laundered into a fact that the *planned* marker exists to prevent. Gate
A2, F16.

iCloud Keychain traffic is the operating system's, not this app's, which is why the
interface says the app makes no network requests "of its own".

### Malicious or compromised dependency

There are no third party dependencies. Nothing in the supply chain but Apple's own
frameworks and this repository.

Within Apple's frameworks, the cryptography comes from CryptoKit, with one exception:
CryptoKit has no password based key derivation, so the backup format's PBKDF2 comes from
CommonCrypto. Both are Apple's, neither is vendored, and the exception is named here rather
than left for a reader to notice.

### Attacker who publishes a modified build

Verify what you install. Reproducible build notes land in PR 18 so a third party can
confirm that a released binary was built from the tagged source.

### System added menu entries

*Known and accepted, to be re-examined in PR 17.*

Long pressing an account card opens a system context menu. iOS may add entries to such a
menu that this app does not define, and on iOS 26 it adds "Ask Siri". Invoking it may pass
what is on screen, which includes a live code and an account name, to an assistant that can
process requests off device.

This was found during development and the menu was removed. It was then deliberately
restored, because the system menu carries a preview and a lift animation that an app
defined action sheet cannot reproduce, and the alternative was judged the worse product.
The trade is recorded here rather than left implicit.

What is known: the entry exists, and the app does not put it there. What is not known, and
what this project cannot verify from the outside, is exactly what it transmits and when.
Anyone for whom that matters can turn off Apple Intelligence in iOS Settings, which removes
the entry.

PR 17 should either establish what it transmits, or state plainly that it is unverified,
rather than leaving this paragraph as the last word.

### Explicitly out of scope

- A jailbroken or already compromised device. If the OS is owned, nothing in userspace
  helps.
- A malicious Xcode toolchain or a compromised Apple platform.
- Shoulder surfing, screen recording by another app you installed, and physical coercion.
- Your own choice to export secrets in plaintext, which the app permits behind an explicit
  warning and an acknowledgement, because an authenticator you cannot leave is its own kind
  of trap. Gate A2, F17.
- **An archive you have created and stored badly.** Once bytes are in a file, none of the
  protections the rest of this app relies on apply: not the device passcode, not the Secure
  Enclave, not the Keychain's protection class. An encrypted archive is only as good as the
  passphrase and where the file ends up. See `docs/BACKUP_FORMAT.md`, which was written and
  audited before any of it was implemented for exactly this reason.

## The privacy manifest

`OpenFactor/PrivacyInfo.xcprivacy` is the machine readable form of the claims above, and it
is short enough to read in full. No tracking, no tracking domains, **no collected data types
at all**, and one required reason API: `UserDefaults`, for this app's own preferences.

That last one is worth being precise about, because "uses UserDefaults" sounds worse than it
is. What is stored there is the sort order, the appearance, the chosen icon, whether sync is
on, and whether the lock is on and after how long. Never a secret, never an account name.
The file that does it is `OpenFactor/Settings/Preferences.swift`.

## Practices in this repository

- The security sensitive code lives in `OpenFactorCore`, a package with no UI and no
  dependencies, so it can be audited in isolation.
- The cryptography comes from Apple's frameworks: CryptoKit for hashing, HMAC and
  AES-256-GCM, and CommonCrypto for PBKDF2, which CryptoKit does not provide. The one thing
  written by hand is the HOTP construction of RFC 4226, which is dynamic truncation over an
  HMAC the framework computes, and it is verified against the RFC's own test vectors.
- The generators are verified against the official RFC test vectors in CI.
- Secrets are never logged, and never sent to analytics because there is none. They leave
  the Keychain in exactly two places, both of which a person has to ask for: a code copied
  to the clipboard, local to the device and expiring, and an export file, which is deleted
  when the screen that made it goes away and swept at launch if the app was killed first.
- Non secret metadata such as the account color and sort order is stored separately from
  the secret, so drawing the list never requires loading secret material.
- The account card uses a **system context menu**, and iOS may append entries of its own to
  it. On iOS 26 it appends "Ask Siri", which offers to pass the card's contents to an
  assistant that may process them off device. See the threat model entry above.
