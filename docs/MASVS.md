# OWASP MASVS: a self-assessment

**Self-assessed against MASVS v2.1.0, published whole, including what fails and what is out of
scope.**

**OWASP certifies nobody**, and this is not a certification. It is this project's own reading of
its own code against an external control list, published so that a reader can disagree with it.
Every verdict below points at something checkable: a named test, a CI job, a measurement in
`docs/audits/`, or a specific section of a design document. **A verdict whose only support is
reasoning is marked as exactly that**, rather than shown as a pass.

## Why this exists, when gate A4 already happened

**A4 is a review and this is a coverage assessment, and they are different instruments.** A4 sent
three independent models at four scopes and they hunted where they chose to hunt; it produced 118
accepted findings and three highs. **No number of review rounds produces a statement about the
controls nobody looked at.** A fixed list forces a verdict on every control, including "looked,
found nothing", which is the thing a review structurally cannot give you.

**What this is not.** OpenFactor has not had a commissioned human penetration test. That is the gap,
and this document does not close it.

**On self-assessment, stated before the verdicts rather than after.** The person writing this wrote
the code, and during A4 filed a finding, verified it with a table, wrote it into a commit message
and a CI rule, and was wrong, because a claim was reasoned about instead of run. That is recorded in
`docs/audits/A4/A4-verify-final-results.md`. **The evidence-pointer rule below is the response to it**:
if a verdict cannot name something a reader can execute or read, it does not get to be a pass.

## The verdicts

| Control | Verdict | Evidence |
| --- | --- | --- |
| **MASVS-STORAGE-1** The app securely stores sensitive data. | Pass | `docs/VAULT.md`; `KeychainSecretStoreTests` (protection class, access group, sync class); `VaultTests`; `VaultVectorTests`; `docs/audits/E/E1-keychain-access-groups.md` |
| **MASVS-STORAGE-2** The app prevents leakage of sensitive data. | **Partial** | `docs/APP_LOCK.md`; `PrivacyShield`; `ScreenCaptureMonitor`; `CodeClipboard`; `SharedInbox` backup exclusion, refused on failure. **The known gap**: PR 15b measured the app switcher's zoom-from-home-screen cache showing issuer and name for about a sixth of a second, recorded as accepted rather than fixed. CI asserts no logging. |
| **MASVS-CRYPTO-1** The app employs current strong cryptography and uses it according to industry best practices. | Pass | AES-256-GCM, HKDF-SHA256, P-256 ECDH via CryptoKit; PBKDF2-SHA256 at 600,000 iterations. Published RFC vector tables: `TOTPTests`, `HOTPTests`, `Base32Tests`, `BackupVectorTests`, `VaultVectorTests` |
| **MASVS-CRYPTO-2** The app performs key management according to industry best practices. | **Partial, by decision** | `docs/VAULT.md` key hierarchy; `WrappedVaultKeyTests`; `WrappedKeySyncTests`; hardware measurements `E8`, `E9`, `E10`. **The decision**: the vault key is a `.complete`-protected file in the app's private container rather than held as a Secure Enclave key, because it must be recoverable from a passphrase on a replacement device. That is a recovery requirement, not an oversight, and it is the trade `docs/VAULT.md` argues. **What "a file in a container" does not convey, and should**: under Complete Protection, Apple states the class key "is protected with a key derived from the user passcode or password and the device UID", and the decrypted class key is discarded shortly after the device locks ([Apple Platform Security](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web)). So the file cannot be read while the device is locked and cannot be decrypted off the device at all. **What the Secure Enclave would add, corrected after a reviewer refused an earlier version of this sentence.** The Enclave holds P-256 keys, not arbitrary symmetric ones, so this means wrapping the vault key under an Enclave key rather than storing it there. **An earlier version of this cell said that would harden nothing on an unlocked device, and that was wrong**: an Enclave key created with a `.userPresence` access control requires a biometric or passcode check on every use ([SecureEnclave.P256](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/keyagreement/privatekey), [.userPresence](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/userpresence)), so code running as this app on an unlocked phone could not silently unwrap. **It would harden a container imaged while unlocked and analysed elsewhere**, because the key material cannot leave the phone. **The trade was then examined properly and declined, and the reason is measured rather than argued.** `docs/audits/E/E15-the-enclave-and-a-sibling.md` put two apps of one developer team on a device: the second found the first's Enclave key and decrypted a message sealed to it, and requiring user presence changed only that the phone asked for a passcode first. **An Enclave key persists as a Keychain item**, so wrapping the vault key under one would move its protection from the app container, measured as a real boundary in `E4`, onto the Keychain, measured as no boundary against this team in `E1` and again in `E15`. **It would make this app weaker against the attacker it actually names.** So the verdict is partial because the master key is not hardware bound in its own right, and because the available way to bind it is one this platform does not make exclusive to the app that created it. |
| **MASVS-AUTH-1** The app uses secure authentication and authorization protocols and follows the relevant best practices. | **Not applicable** | There is no OpenFactor account, no server and no remote authorization. CI asserts the app makes no network requests. |
| **MASVS-AUTH-2** The app performs local authentication securely according to the platform best practices. | Pass | App Lock via `LocalAuthentication`, off by default; `AppLockEngineTests`, `AppLockPresentationTests`; `docs/APP_LOCK.md` |
| **MASVS-AUTH-3** The app secures sensitive operations with additional authentication. | **Partial**, downgraded by review | **Two reviewers independently put this at partial and they are right.** First: `AppLockAvailability.authenticate` **returns true on a device with no passcode**, deliberately and with the reasoning written down at `OpenFactor/Lock/AppLockController.swift:141`, because refusing would deny somebody a backup or the ability to wipe a phone they are selling on a device already open to anyone holding it. That is a defensible product decision and it still means a sensitive operation carries no additional authentication on such a device, which an unconditional pass would deny. Second: **releasing the vault key to a watch is gated by a tap, and a tap is consent rather than proof of identity.** What is genuinely there: erase requires identity confirmation **and then** a typed word, in that order: `EraseGate` and `EraseGateTests`, which cover the refused-identity path, the order the two gates run in, and that records this version cannot decode are erased too. Releasing the vault key to a watch requires a human tap inside a bounded consent window (`ProvisioningDeskTests`, `WatchProvisioningTests`). **This citation was weak until a reviewer said so**: it named `EraseAccountsTests`, which proves deletion deletes and nothing about what guarded it, because both gates lived in a SwiftUI view no test could reach |
| **MASVS-NETWORK-1** The app secures all network traffic according to the current best practices. | Pass, vacuously and enforced | **The app makes no network requests.** CI job "No network code, and no logging of anything" refuses `URLSession`, `NSURLConnection`, `import Network`, `CFSocket`; a second job asserts nothing in the built bundle can reach the network. |
| **MASVS-NETWORK-2** The app performs identity pinning for all remote endpoints under the developer's control. | **Not applicable** | There are no remote endpoints. |
| **MASVS-PLATFORM-1** The app uses IPC mechanisms securely. | **Partial**, downgraded by review | **Two reviewers independently put this at partial and they are right.** WatchConnectivity is IPC and it is in scope, and the exclusivity the key exchange rests on is **load bearing and unmeasured in one direction**: a rogue watch app claiming to be this app's counterpart has never been tested. `docs/VAULT.md` lists that as a blocking item on a list of things to prove before implementation, and the implementation shipped. A pass here would have been the laundering this document refuses elsewhere. The rest is genuinely covered: the App Group inbox, the share extension and URL schemes were gate A4's scope 4, five rounds and two verification rounds. `InboxDirectory` and its tests; `SharedInboxTests`; CI asserts the share extension declares one entitlement and never the Keychain. |
| **MASVS-PLATFORM-2** The app uses WebViews securely. | **Not applicable** | There are no WebViews. Verified: zero occurrences of `WKWebView`, `UIWebView` or `SFSafariViewController` in the tree. |
| **MASVS-PLATFORM-3** The app uses the user interface securely. | **Partial** | `ScreenCaptureMonitor` hides codes while the screen is recorded, mirrored or shared; `PrivacyShield` covers the app switcher; two camera and Face ID usage strings are asserted present by CI. Same known gap as STORAGE-2. |
| **MASVS-CODE-1** The app requires an up-to-date platform version. | Pass | iOS 18.0 and watchOS 11.0 minimums, asserted by the CI job "Project settings are what the documentation says" |
| **MASVS-CODE-2** The app has a mechanism for enforcing app updates. | **Fail, with the platform's part stated** | **The app has no mechanism of its own**, and will not get one: it has no server to learn a minimum version from and no way to notice it is out of date or refuse to run, and building either would mean a network call, which the first principle refuses. **What exists is Apple's rather than this project's, and it is not nothing.** App Store apps update automatically by default on iPhone and iPad, controlled by the person at Settings, then Apps, then App Store, then App Updates ([Apple Support](https://support.apple.com/en-us/102629)). A fix therefore reaches a default configured device with nobody doing anything, and reaches a device whose owner turned that off when they choose to. **This is still a genuine fail rather than a not-applicable**, because the control asks for a mechanism the app itself has, and it is stated as one. |
| **MASVS-CODE-3** The app only uses software components without known vulnerabilities. | Pass, and enforced | **Zero third-party dependencies.** `Package.swift` declares none, and CI job "No third-party dependencies" fails the build if one appears. The supply chain is this repository, the Swift toolchain and Apple's frameworks, which is what `SECURITY.md` claims. |
| **MASVS-CODE-4** The app validates and sanitizes all untrusted inputs. | Pass | Gate A4's scope 3, three rounds. `OTPAuthURI`, `Base32`, the three importers, `BackupArchive`, `JSONSniff`, `ImportLimits`, `BoundedFile`; `FuzzTests`; `OTPAuthURIRejectionTests`; `AccountLimits` enforced at every enrolment path |
| **MASVS-RESILIENCE-1** The app validates the integrity of the platform. | **Out of scope, deliberately** | See below. |
| **MASVS-RESILIENCE-2** The app implements anti-tampering mechanisms. | **Out of scope, deliberately** | See below. |
| **MASVS-RESILIENCE-3** The app implements anti-static analysis mechanisms. | **Out of scope, deliberately** | See below. |
| **MASVS-RESILIENCE-4** The app implements anti-dynamic analysis techniques. | **Out of scope, deliberately** | See below. |
| **MASVS-PRIVACY-1** The app minimizes access to sensitive data and resources. | Pass | Two permissions in total, camera and Face ID, both asserted present by CI and both used only where the feature requires them. No analytics, no tracking, no network. |
| **MASVS-PRIVACY-2** The app prevents identification of the user. | Pass | There is no account, no identifier generated or transmitted, and nothing leaves the device except through iCloud Keychain, which carries ciphertext. Inbox file names are fresh UUIDs carrying no information about their contents. |
| **MASVS-PRIVACY-3** The app is transparent about data collection and usage. | Pass | `openfactor.dev/privacy`; `SECURITY.md`; `README.md`; the App Store listing drafted in `docs/APP_STORE.md` under the rule that no listing sentence may claim more than the repository claims |
| **MASVS-PRIVACY-4** The app offers user control over their data. | Pass | Encrypted export and import; the iCloud sync toggle in both directions with the protection class following the flag; and two erases that differ, stated separately because this row claimed the stronger one of both until 2026-08-22. **Settings erase removes every account record and keeps the vault**, so the passphrase somebody wrote down still opens the app they are still using. **Start over, on the locked recovery screen, removes the accounts and then destroys the vault**, both wrapped records included, which is the only escape from a vault whose passphrase is lost |

## MASVS-RESILIENCE is out of scope, and here is the reason

**An open source authenticator whose entire argument is that you can check it does not obfuscate
itself.** Anti-tampering, anti-static-analysis and anti-dynamic-analysis measures work by making the
binary harder to understand, and this project's claim is that its security rests on code, tests,
specifications and measurements that anyone can read. Those two positions cannot both be held.

**Platform integrity validation is refused for a second reason**: it would mean judging the person's
own device and refusing to work on it. An authenticator that will not open on a device somebody
owns is a way to lose access to every account they have.

**This is a design decision and it has a cost.** On a compromised device, OpenFactor offers no
resistance beyond what iOS itself provides. `SECURITY.md` says the same in its own words, and
nothing here should be read as claiming otherwise.

**What iOS provides here is not nothing, and "compromised device" hides two different cases.**
The vault key file is Complete Protection, so its class key is discarded shortly after the device
locks and is derived from the passcode and the device UID. **A compromise that has the device
locked does not yield the vault key**, and cannot take the file elsewhere to work on it. A
compromise with the device unlocked, or one that also has the passcode, does. That distinction is
the whole of what this control gives up, and it is smaller than "if your phone is owned, so are
your codes" implies. `SECURITY.md` draws it correctly under the locked-device attacker; this
paragraph previously did not.

## What this document does not establish

**It is a self-assessment, and a sample of it has now been checked.** Five verdicts were put to
the same three models the audit gate used, as closed questions rather than as a review, along with
an open invitation to change any verdict in the table. **The sampled five were confirmed against
the evidence named, and two others were taken down**, which is recorded below. Nobody independent
has checked the rest, and the evidence pointers exist so that anyone can.

**It says nothing about a released binary.** [docs/BUILD_PROVENANCE.md](BUILD_PROVENANCE.md)
narrows this rather than closing it: the toolchain is pinned to its build number, the compiled code
is deterministic under it, and two builds of identical source still differ because of the linker's
UUID and the ad-hoc signature. **Bit for bit reproducibility is not reachable**, since Apple
re-signs and processes what it distributes. A reader still cannot verify that a build on the App
Store came from this source.

**Five controls are partial and one fails**, and none of the six is hidden in prose. The app
switcher's brief cache accounts for two of them, MASVS-STORAGE-2 and MASVS-PLATFORM-3. The vault
key's storage location is MASVS-CRYPTO-2 and the absence of an update-enforcement mechanism in the
app itself is the fail. **The remaining two, MASVS-AUTH-3 and MASVS-PLATFORM-1, were passes until
outside review took them down.**

**Those two downgrades are the answer to the question this section opens with.** The verdicts
were put to the same three models as closed questions, and two of them independently reached
partial on both. **The self-assessment was too generous in exactly the way a self-assessment is
expected to be**, and it was wrong in the direction that flatters the author. That is worth more
than the verdicts they confirmed.

**The fail is the narrowest of the six**, because the platform delivers updates automatically
unless somebody turns that off, and it should not be read as though a fix could not reach an
installed device.

## Related standards this project does claim

**RFC 6238 and RFC 4226 conformance.** The published vector tables from both specifications run as
tests: `TOTPTests` and `HOTPTests`. RFC 4648 base32 decoding is covered by `Base32Tests`.

**RFC 9116.** A `security.txt` at `/.well-known/security.txt` on `openfactor.dev` points at the
GitHub Security Advisories channel that `SECURITY.md` already names.
