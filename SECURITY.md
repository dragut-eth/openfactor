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

*Planned.* App Lock, if you have enabled it, requires Face ID, Touch ID, or your passcode
before any code is shown, and codes are hidden when the app goes to the background. With
App Lock off, an unlocked phone means full access. This is the single most important
setting in the app.

### Attacker with your iCloud account

*Implemented as of PR 13, and only relevant if you turn sync on. Off by default.* Sync uses
iCloud Keychain, which is end
to end encrypted. The keys are derived from your device passcodes and never leave your
devices, so Apple cannot read the synced items and neither can someone who obtains your
iCloud password alone. An attacker who obtains your iCloud password **and** a device
passcode can add a device to the circle of trust and receive your secrets. Two factor
authentication on your Apple Account is therefore part of this app's security, not
separate from it.

**Turning sync on and off never reads a secret.** The conversion updates each Keychain
item in place, so no secret is decrypted, no secret enters this app's memory, and there is
no moment when an account exists only as a variable that a crash could lose. The obvious
implementation, reading each account out and writing it back, would have all three
problems.

**What turning sync off does, precisely.** The accounts stay on this device and stop being
offered to iCloud Keychain, and their protection class goes back to device only. What
happens to the copies already sitting on your other devices is not something this app
controls or can promise, so the interface does not claim it either way. If you want an
account gone from another device, delete it there. Establishing the exact propagation
behaviour is an open item for gate A2.

**Your device preference and the Keychain can disagree.** The switch is remembered per
device in `UserDefaults`, and it is written only after the Keychain work succeeds. If the
app is killed part way through a conversion, some accounts are converted and some are not,
and the switch will read the old value. Running it again fixes it, because the conversion
is idempotent by design. The app does not silently reconcile the two at launch on purpose:
a synced account arriving from another device would look like a disagreement, and
"resolving" it would quietly pull that account out of sync everywhere.

### The watch is a device holding your secrets

*Relevant from PR 14, and a direct consequence of the design chosen in PR 13.* The watch
does not receive secrets from the phone. It reads the same synced Keychain items, through a
shared access group, which is why it keeps working with the phone off or absent. The
consequence is worth stating plainly rather than leaving implicit in an architecture
document: **your paired watch holds your secrets, and it can generate your codes.** Treat a
lost watch the way you would treat a lost phone.

It also means the watch app needs sync on. With sync off there is nothing for it to read,
and it will say that rather than showing an empty list.

We do not use CloudKit for secrets. A CloudKit private database is encrypted, but with a
key Apple holds unless the encrypted fields API is used, and that is a weaker guarantee
than iCloud Keychain gives for free.

### Attacker on the network

There is no network code. The app makes no requests, so there is nothing to intercept.
This is verified in CI rather than asserted, see PR 17.

### Malicious or compromised dependency

There are no third party dependencies. Nothing in the supply chain but Apple's own
frameworks and this repository.

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
  warning because an authenticator you cannot leave is its own kind of trap.

## Practices in this repository

- The security sensitive code lives in `OpenFactorCore`, a package with no UI and no
  dependencies, so it can be audited in isolation.
- All cryptography comes from CryptoKit. No hand rolled primitives.
- The generators are verified against the official RFC test vectors in CI.
- Secrets are never logged, never sent to analytics because there is none, and never
  written outside the Keychain.
- Non secret metadata such as the account color and sort order is stored separately from
  the secret, so drawing the list never requires loading secret material.
- The account card uses a **system context menu**, and iOS may append entries of its own to
  it. On iOS 26 it appends "Ask Siri", which offers to pass the card's contents to an
  assistant that may process them off device. See the threat model entry above.
