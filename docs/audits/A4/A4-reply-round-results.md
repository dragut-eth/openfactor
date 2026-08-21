# A4: the reply round, as it came back

**Three engines, twenty two items each, reproduced whole.** The brief is in `A4-reply-round.md`.

**One redaction, disclosed.** Where a return names a competing product this project does not name
anywhere, the name is replaced with `[a competitor]`. Nothing else is altered, cut, or reordered.

**One return was collected before a correction it caused.** Grok answered against `7c3180e`; its
item 12 corrected a Settings path that was wrong in this project's documents, and the fix landed
before the other two engines were asked. That is why only one return carries that correction.

---

# The returns, as they came back

## Grok

1.
Yes.
responsesToOneRequestAreFresh now calls both overloads by name; WatchKeyProvider.approve uses the validated one, and each generates its own P256.KeyAgreement.PrivateKey(). The pinned vector is the only test that would see an empty-salt change; I counted 29 @Tests in that file.

2.
Yes.
docs/BUILD_PROVENANCE.md refuses "reproducible build" from a measured two-build diff, and scripts/ship-testflight.sh writes commit, tree state, toolchain and SHA-256 after a successful upload. It still cannot let a reader check their download, and it says so.

3.
Yes.
docs/audits/E-probes-what-can-be-rerun.md states a topology, not an intention, for each probe; theStoredBytesAreOpaque reads kSecReturnData and carries a positive control on the OFV1 magic. E1's finding still cannot be a test; its defence now is one.

4.
Yes.
The reopening trigger sits in docs/VAULT.md next to rewrapping, and it says the waiver is void the day a passphrase-change screen ships.

5.
Yes.
A4-verify-S1-37-S1-28-results.md now says a shipping decision, not a safe window, and not the same as the toggle being trustworthy under twins.

6.
Yes.
SECURITY.md says in its own voice that sync off is the smaller surface, that both waivers live on that path, and that the least surface is one phone, sync off, plus an encrypted export.

7.
Yes.
E5 now records that its own reopening condition fired when the six-digit string was removed, that the measurement is load-bearing again, and that the rogue-watch direction was never run.

8.
No.
Labelling the gap is not a substitute for measuring a property this design now admits is load-bearing, on a probe whose own trigger already fired once and was ignored. The three-message remedy is a design that is not built.

9.
Yes.
docs/APP_LOCK.md now puts default-off and the app-switcher cache in one sentence and says that is the out-of-the-box posture.

10.
Yes.
README.md tells the reader not to make any authenticator their only copy, this one included, and to check that the export imports.

11.
Yes.
I did not dissent: I called this the price of the rule. Recording ChatGPT's remaining dissent next to a standing rejection is the honest shape, and it does not need a policy change.

12.
Yes.
Apple's page does say App Store apps update automatically by default; the MASVS fail stays because the app still has no mechanism of its own. The cited path is slightly wrong: it is Settings → Apps → App Store → App Updates, not Settings → App Store → Automatic Updates.

13.
Yes.
Complete Protection is the class they request, and Apple does say that class key is passcode-plus-UID and discarded after lock; the Enclave does not hold an arbitrary 32-byte key. That made "a file rather than Secure Enclave" sound unprotected, which it is not; the verdict staying partial is still right, because the local copy is not hardware-bound in its own right.

14.
Yes.
A locked-device compromise does not yield a Complete Protection file; an unlocked one, or one that also has the passcode, does. I had collapsed those.

15.
Yes.
KeychainSecretStoreTests, VaultTests, VaultVectorTests and E1 together show ciphertext at rest, a protection class, and an access group; STORAGE-2 and CRYPTO-2 already carry the remaining gaps.

16.
Yes.
There is no URLSession in the Swift tree; CI job "No network code, and no logging of anything" greps for it, and "Nothing in the bundle can reach the network" checks the built binary.

17.
Yes.
Zero matches for WKWebView, UIWebView or SFSafariViewController in the tree.

18.
Yes.
Erase calls AppLockAvailability.authenticate then a typed ERASE; the watch path is a tap inside ProvisioningDesk.consentWindow. EraseAccountsTests covers deletion, not Face ID; the view is what requires re-authentication.

19.
Yes.
Package.swift declares no packages; CI refuses .package(, XCRemoteSwiftPackageReference, and a tracked Package.resolved.

20.
MASVS-PLATFORM-1, Pass → Partial.
WatchConnectivity is in-scope IPC, routing exclusivity is load-bearing, and the counterpart direction is still unmeasured reasoning.

21.
The vault key is a Complete Protection file the process can read whenever the phone is unlocked (VaultKeyStore.load); daily use never re-derives from the passphrase. Password-gated peers (Aegis, Ente, Proton Authenticator) do not hand every secret to whoever can run as the app merely because the device is unlocked. The Watch then copies that same key after one undifferentiated tap (WatchProvisioning.respond).

22.
A published human pentest of a named build; the rogue-watch probe actually run, or the three-message comparison built; and one major iOS/watchOS release with the E-probes re-run. A reader-checkable store binary cannot be reached from this side of Apple's re-sign. "Only copy of the secrets" would not change: that is a class problem this project has now accepted.

## Fable

I read the working tree at `7c3180e` (clean), not GitHub, and checked each citation against the code. `assets/` left unread. Answers below in the format asked: yes/no first, then at most two lines.

On the live finding first: I accept it, and it is the sharpest correction in the set. My "static ephemeral key passes the suite" claim was true and worse than I framed it, because the freshness test exercised `respond(to: Data)` while `WatchKeyProvider.approve` calls `respond(to: ValidatedRequest)` — a different overload with its own `P256.KeyAgreement.PrivateKey()`. The suite guarded a path the app never takes. That is the same shape as my S1-37 error: a property checked on the reachable-looking artifact rather than the shipping one.

Part 1 — objections answered

1. Yes. `responsesToOneRequestAreFresh` now runs freshness over both overloads by name, and `exchangeVector` pins request bytes, derived key and response bytes as constants; the label test spells the derivation a second way. A static keypair on either path now reddens by name.
2. Yes. `BUILD_PROVENANCE.md` measured the two builds, found every shipping binary differed, refuses "reproducible build," and `ship-testflight.sh` writes a commit+toolchain+SHA-256 record per upload. It states plainly a reader still cannot verify their download.
3. Yes. `E-probes-what-can-be-rerun.md` states per-probe what re-running takes, and `theStoredBytesAreOpaque` reads the raw blob, asserts issuer/name/secret absent, carries a positive control (the `OFV1` magic) and a read-back. Honest about which probes cannot be tests.
4. Yes. The reopening trigger is now in `VAULT.md:89` beside the passphrase-replacement note, not only in the audit folder — where whoever builds that screen will actually read it.
5. Yes. The waiver now states "what accepting it does not mean" (`A4-verify-S1-37-S1-28-results.md:171`): a shipping decision, not a safe window, and not the toggle being trustworthy under twins.
6. Yes. `SECURITY.md:290` says sync off is the smaller surface, that both waived findings live on the synchronized record, and names the least surface as a single phone with sync off plus an encrypted export.
7. Yes. `E5:11-17` records that its own reopening condition (removal of the six-digit string) fired unnoticed, and corrects the miss rather than quietly patching it.
8. Yes. Refusing to measure the rogue-watch channel is acceptable on these terms: the probe is priced, the reasoning is labelled as reasoning not measurement, the remedy (a third message so both sides hold the transcript before the key travels) is written down, and the trigger is attached to the A5 release-diff process rather than to memory. It remains the largest unmeasured assumption in the design, and a user who never pairs a watch avoids it entirely — but the install bar (a rogue counterpart must ship inside an OpenFactor-branded bundle onto the victim's own devices) makes the deferral defensible.
9. Yes. `APP_LOCK.md:20` pairs default-off with the ~1/6-second switcher cache in one sentence and names the out-of-the-box posture as the one with least in front of it.
10. Yes. `README.md:175` says in the project's own voice not to make any authenticator your only copy, this one included, and to check that the export imports before relying on it.
11. Yes. Recording the dissent without changing the policy is acceptable: destroying the superseded transfer-QR copy is sound retention discipline, the one unrecoverable case (a pending import whose source can't regenerate) is now documented honestly, and `A4-round-four-scope4-results.md:246` preserves ChatGPT's objection so the section reads as a decision, not a consensus. For the record, the dissenter was ChatGPT; I found no unrecoverable loss.

Part 2 — corrections

12. Yes. Fact 1 holds: iOS auto-updates apps by default, so "nothing forces you to update" overstated the practical exposure. The verdict staying fail is right — a no-server app genuinely cannot compel an update to a user who disables auto-update.
13. Yes. Facts 2 and 3 hold: a `.complete` file is encrypted under a passcode+UID class key, and the Enclave cannot hold an arbitrary 32-byte key (only wrap it). "A file in the container" was misleading about protection. The residual the doc itself keeps is real: the local copy could additionally be Enclave-wrapped, and recovery only justifies the passphrase-wrapped copy — so partial is correct.
14. Yes. Fact 2 holds: on a locked device the class key is discarded, so "phone owned, codes owned" is false for a locked/BFU compromise and true only for a live unlocked one. The scope decision is unchanged and correct — on an unlocked compromised device it offers no resistance by design.

Part 3 — MASVS sample

15. Yes. STORAGE-1: `usesTheStrictestProtectionClass` pins `whenUnlockedThisDeviceOnly`, `theStoredBytesAreOpaque` proves the blob is unreadable, vault vectors cover the sealing. The evidence supports the pass.
16. Yes. NETWORK-1: CI's "No network in the binary" job runs `otool` against the built Release bundle for both frameworks and symbol references (proven against a deliberately broken build), on top of the source grep. Enforced against the artifact, which is the version worth anything.
17. Yes. PLATFORM-2: grep of the source targets returns zero `WKWebView`/`UIWebView`/`SFSafariViewController`. Not-applicable is accurate.
18. Yes. AUTH-3: the load-bearing leg (releasing the vault key) is genuinely gated and tested — `ProvisioningDeskTests` covers the bounded window, a backward clock, and second-tap. Caveat: the cited `EraseAccountsTests` proves erasure mechanics, not the Face-ID-plus-typed-word gate, which lives untested in `EraseAccountsView.swift:35`; the verdict holds on the watch leg, but that citation is weak.
19. Yes. CODE-3: `Package.swift` declares no package-level dependencies (only the internal `OpenFactorCore` target dep), and CI's "No third-party dependencies" job fails the build if one appears. Supported and enforced.
20. No verdict I would flip. The one thing I would change is not a verdict but the AUTH-3 evidence: cite the erase gate's actual code, or add a test that exercises the typed word plus identity check, so the erase leg stops resting on prose the way the project's own standard warns against.

Part 4

21. Two things it does worse than peers, both source-identifiable. Behaviorally: the app-switcher snapshot leaks issuer and account name for ~1/6 second on the home-screen zoom-out, accepted-not-fixed (`APP_LOCK.md:20`, `PrivacyShield`); an authenticator that fully blanks its switcher snapshot has no such window. Structurally: it is iOS/watchOS only — no Android target in the project — so unlike Aegis, [a competitor] or Ente it cannot follow you across an ecosystem switch, which for an authenticator is a real portability deficit even though the encrypted export mitigates lock-in.
22. Conditions somebody could check, that would move my verdict from "trust with caveats" toward "trust plainly":

* A commissioned independent human penetration test, published — the project names this as the open gap (`README.md:169`). Checkable: a report exists.
* The provenance chain actually exercised: `docs/releases/` is currently absent/empty, so the mechanism has never run on a shipped build. Checkable: a release record tied to a tagged commit appears.
* The E5 rogue-watch measurement run, or the three-message consent shipped. Checkable: an E5 result or a diff to the exchange.
* The last "prose not run" sensitive-op gate (erase Face-ID + word) covered by a test.

Conditions the project cannot reach, and this matters because no effort on its side closes them: a bit-for-bit verifiable download (Apple re-signs what it distributes — `BUILD_PROVENANCE.md:60` proves this is out of reach), and long-term iCloud/Watch behavior across hardware and OS releases, which only time and OS updates can settle.

## ChatGPT

1. Yes.
Both public overloads now have explicit freshness coverage, the shipping caller uses the validated overload, and the 29 targeted Watch tests—including the fixed vector—pass.
2. No.
The work improves provenance but still cannot connect an installed App Store binary to this source. Also, `BUILD_PROVENANCE.md` says five binaries are named while the script names four Mach-O binaries plus the IPA.
3. No.
The new test closes the E1 ciphertext-defense gap, but most platform assumptions remain single-device observations that cannot be independently rerun from this tree.
4. Yes.
The S1-33 trigger is now beside the passphrase-replacement design in `docs/VAULT.md`, explicitly voiding the waiver if that interface ships.
5. Yes.
The record now states accurately that S1-40 is an accepted shipping risk, not a safe window or proof that the toggle is trustworthy under twins.
6. Yes.
`SECURITY.md` clearly identifies sync-off plus an external encrypted export as the configuration with the smallest attack surface.
7. Yes.
E5 now says the six-digit comparison was removed, routing exclusivity became load-bearing again, and its prior reopening condition was missed.
8. No.
Apple documents paired-counterpart behavior but not authentication guarantees, and `docs/VAULT.md` still calls the unmeasured property "blocking." Recording a feasible probe and then declining to run it does not resolve that contradiction.
9. Yes.
`docs/APP_LOCK.md` now puts default-off and the accepted app-switcher cache exposure together, accurately describing the out-of-box posture.
10. Yes.
The README now gives the right operational advice: retain another recovery path and actually test the encrypted export by importing it.
11. Yes.
Recording my dissent beside the rejection is an acceptable policy resolution; it preserves that the loss is real while making clear it affects an unconfirmed import, not stored accounts.
12. Yes.
Automatic App Store updates materially reduce typical exposure, although they do not guarantee prompt installation and remain user-disableable; the MASVS fail therefore remains correct.
13. No.
Complete Protection materially corrects my earlier characterization, but "Secure Enclave wrapping would harden nothing" is too broad: Secure Enclave keys can require user-presence authentication, which can harden the unlocked-device case.
14. Yes.
Apple's protection-class description supports the locked-versus-unlocked distinction, provided the compromise did not already execute while unlocked and retain the key.
15. Yes.
The implementation seals metadata and secrets, protects and backup-excludes the vault key, and the named tests and vectors substantively exercise those properties.
16. Yes.
The source-wide exclusions and Release-bundle symbol inspection support the vacuous pass: the app initiates no network traffic of its own.
17. Yes.
No WebView API occurs in the shipping Swift source, so not applicable is supported.
18. No.
`AppLockAvailability.authenticate` returns success when device authentication is unavailable, and the Watch's human tap is consent rather than additional authentication; that does not support an unconditional MASVS-AUTH-3 pass.
19. Yes.
`Package.swift` has no dependencies, the project has no remote package reference or resolved file, and CI enforces those three entry points.
20. Yes.
Change MASVS-PLATFORM-1 to Partial because its load-bearing WatchConnectivity exclusivity remains unmeasured, and MASVS-AUTH-3 to Partial for the no-passcode and consent-only cases above.
21. OpenFactor is worse than at least Aegis against someone holding an unlocked phone: `docs/APP_LOCK.md` makes its curtain optional and default-off, while Aegis defaults onboarding to password protection or biometrics when available. I cannot generalize that difference to every software authenticator.
22. For me to trust it with important accounts as a redundant holder: an independent human assessment of a tagged release with public remediation verification, and either a successful rogue-Watch probe or an authenticated third-message design; the hardware probes should also be repeated for each supported major OS release. Verifying that an installed App Store binary came from the reviewed source requires provenance Apple does not presently expose, so this project cannot meet that condition alone, and my "never the sole TOTP holder" verdict is permanent.

### ChatGPT, on item 21, after being told Aegis is an Android app

You're right. I withdraw my answer to item 21: comparing Aegis's Android vault-lock model with OpenFactor's iOS behavior did not establish a peer disadvantage.

21. Nothing I can identify from the source.
On iOS, the stronger system-level protection is enabled by the user by holding the app icon and selecting "Require Face ID"; an app cannot programmatically enforce that setting. Apple documents that mechanism here. I did not compare OpenFactor against equivalent iOS authenticators, so my Aegis claim was unsupported and should not stand.

---

# What was done with them

**Sixty six answers across three engines. Five No's, all from one engine, and three of those five
were substantive.** Every checkable claim in every return was checked before anything was written
here.

## What the round found in this project

**Three factual errors in this project's own documents**, all found because Part 2 handed over
citations and told reviewers to check them rather than accept them. **The first item carrying a
citation turned out to be wrong**, which is a better argument for the format than the nineteen
confirmations.

| Found | What was wrong | Fixed in |
| --- | --- | --- |
| Settings path | `MASVS-CODE-2` cited "Settings, then App Store, then Automatic Updates". iOS 18 moved per-app settings under Apps, so the path is Settings, then Apps, then App Store, then App Updates | `docs/MASVS.md` |
| Binary count | `BUILD_PROVENANCE.md` said the ship script names five binaries; it names four plus the exported archive. The fifth line in the two-build comparison is the standalone build product beside the app, counted twice | `docs/BUILD_PROVENANCE.md` |
| Secure Enclave | `MASVS-CRYPTO-2` said an Enclave wrap "would harden nothing" on an unlocked device. **False**: an Enclave key with a `.userPresence` access control requires a check on every use, so code running as this app could not silently unwrap | `docs/MASVS.md` |

**The third is the most consequential, and it was written while correcting somebody else's
overstatement.** It turned a real hardening this project has declined into one the platform
supposedly refuses. It is now recorded as a trade with its cost stated: the vault key is read to
generate codes, so a per use presence check sits in the path of the app's primary action.

**Two MASVS verdicts came down**, each reached by two engines independently.

**MASVS-AUTH-3 to partial.** `AppLockAvailability.authenticate` returns true on a device with no
passcode. That is deliberate and the reasoning is recorded in the code: refusing would deny
somebody a backup or the ability to wipe a phone they are selling, on a device already open to
anyone holding it. **It is still true that a sensitive operation carries no additional
authentication there.** And releasing the vault key to a watch is gated by a tap, which is consent
rather than proof of identity.

**MASVS-PLATFORM-1 to partial.** WatchConnectivity is in scope IPC and the exclusivity the key
exchange rests on is load bearing and unmeasured in one direction.

**One weak citation, fixed by extraction.** Two engines noticed that `MASVS-AUTH-3` cited
`EraseAccountsTests`, which proves deletion deletes and nothing about what guarded it, because both
gates lived in a SwiftUI view where no test could reach them and where **no test bundle can make a
real Face ID prompt fail**. `EraseGate` is the fourth extraction of that shape in this project, and
`EraseGateTests` covers the refused identity path, the order the two gates run in, and that records
this version cannot decode are erased too. Two mutations were run to prove the tests discriminate.

**And one contradiction this round is responsible for surfacing.** `docs/VAULT.md` lists
WatchConnectivity routing exclusivity on a list titled what must be proven before implementation.
The implementation shipped. **That is now stated in that document rather than resolved by softening
the word**, along with the decision not to run the probe and the fact that two of three reviewers
rejected that decision.

## What the round found in the objections

**Four of the nineteen did not survive measurement**, and in three of those cases this project's
own wording invited the error. That is a direction of failure this folder had not seen before: the
habit of stating limits sharply overshooting into conceding things that are not true.

**All three engines accepted the corrections on update enforcement, the vault key's protection and
the compromised-device scope**, each after checking the cited source. One rejected the Secure
Enclave half and was right to.

**Item 21 is recorded as it actually happened, and this is the part most easily told wrong.**

One engine answered that OpenFactor is worse than Aegis against somebody holding an unlocked phone,
because this app's lock is optional and off by default while Aegis defaults to password or
biometrics. **Aegis is an Android app**, so it cannot establish an iOS peer disadvantage, and on
being told so the engine withdrew the comparison. Correctly.

**It then withdrew to "nothing I can identify from the source", and that goes too far.** A second
engine had identified the same weakness independently and cited a file: the vault key is a Complete
Protection file the process can read whenever the phone is unlocked, and daily use never re-derives
it from the passphrase. **The engine that withdrew had itself named the remedy two items earlier.**

**So one of three supporting arguments died, not the finding.** Recorded this way deliberately:
filing it as withdrawn would let this record say the sharpest criticism of the app evaporated under
questioning, and that is not what happened.

**The comparison was also wrong about the mechanism**, before Aegis was ruled out. Aegis's password
is not a lock, it is the key: it derives the vault encryption key, so an unlocked phone without it
yields ciphertext. This project's App Lock is a gate in front of the interface and says so in its
own first line. **Turning it on by default would therefore close nothing.** A fix aimed at the
default would have cost a worse first run and answered none of it.

**Two of the five No's are a difference of definition rather than of fact.** One engine read
"answered" as "the gap is closed" and said no to build provenance and to the hardware probes on
that basis, while saying in the same breath that both had improved. The other two read it as
"adequately addressed" and said yes on the same evidence. **The brief did not define the word**,
which is a flaw in the brief.

## What is still asserted and not measured

**That requiring Face ID for an individual app from the home screen suppresses the app switcher
cache.** The maintainer says it and one engine now says it. **Nobody has checked.** Two people
agreeing is not a measurement, and `docs/APP_LOCK.md` carries it as an open measurement along with
the peer comparison neither side of that argument has run.

## The convergence

**All three engines reached the same place by three different routes**, and none of them was asked
to. The vault key is readable by the process whenever the phone is unlocked; the app switcher
window; a named peer whose lock is on by default. **The unlocked-device posture is the finding of
the whole exercise.**

Its remedy is `MASVS-CRYPTO-2`'s Enclave wrap with user presence, named by the engine that spent
item 13 correcting this project about it. **It is not built.** It is a product decision rather than
a defect, and it belongs to the roadmap and to gate A5 rather than to this gate, which is stated in
`A4.md` rather than left implicit.
