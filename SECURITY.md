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

**What turning sync off does, precisely, and what is still unknown.** The accounts stay on
this device, stop being offered to iCloud Keychain, and go back to the device only
protection class.

What happens to the copies on your other devices is **not established**, and this document
previously expected them to be left alone. Gate A2 found that Apple's documentation for
`kSecAttrSynchronizable` points the other way: updating or deleting an item through that
key affects all copies. Nobody has observed which happens, so the interface now says only
that turning sync off may remove them elsewhere and that OpenFactor does not control it. If
you want an account gone from another device, the reliable move is to delete it there.
Settling this needs two devices and is the first step of the experiment recorded in
`docs/audits/A2.md`. Gate A2, F8.

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

*Relevant from PR 14, and a direct consequence of the design chosen in PR 13.* The watch
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
This is verified in CI rather than asserted: the style job greps the whole source tree for
`URLSession`, the `Network` framework, raw sockets, and logging, and fails the build if any
appears. Until gate A2 this sentence said the same thing while CI checked nothing, which is
exactly the plan laundered into a fact that the *planned* marker exists to prevent. Gate
A2, F16.

iCloud Keychain traffic is the operating system's, not this app's, which is why the
interface says the app makes no network requests "of its own".

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
- *Planned.* Your own choice to export secrets in plaintext, which the app will permit
  behind an explicit warning because an authenticator you cannot leave is its own kind of
  trap. There is no export of any kind until PR 16. Gate A2, F17.

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
