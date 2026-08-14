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

*Planned.* Secrets live in the Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
They are encrypted with a key derived from your device passcode and the Secure Enclave,
and are unreadable while the device is locked. An attacker with the hardware and no
passcode should get nothing.

### Attacker with your unlocked device

*Planned.* App Lock, if you have enabled it, requires Face ID, Touch ID, or your passcode
before any code is shown, and codes are hidden when the app goes to the background. With
App Lock off, an unlocked phone means full access. This is the single most important
setting in the app.

### Attacker with your iCloud account

*Planned, and only relevant if you turn sync on.* Sync uses iCloud Keychain, which is end
to end encrypted. The keys are derived from your device passcodes and never leave your
devices, so Apple cannot read the synced items and neither can someone who obtains your
iCloud password alone. An attacker who obtains your iCloud password **and** a device
passcode can add a device to the circle of trust and receive your secrets. Two factor
authentication on your Apple Account is therefore part of this app's security, not
separate from it.

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
