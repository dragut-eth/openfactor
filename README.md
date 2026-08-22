# OpenFactor

A deliberately focused authenticator for iPhone and Apple Watch.

OpenFactor stores verification codes without an OpenFactor account, server, browser extension,
or analytics service. It keeps the authenticator physically separate from the computer asking
for the code, while making it straightforward to import your accounts, back them up, and take
them elsewhere.

The vault is designed so account data is encrypted before it reaches the Keychain. If iCloud
sync is enabled, Keychain carries ciphertext; the vault key remains in each device's private app
container and never syncs.

> **Status: no independent audit yet.** The repository is built in public from the first commit.
> The app works and is being tried on real devices. The encrypted vault is implemented on both
> iPhone and Apple Watch, and the exchange that hands the key to a watch has been run between
> real devices, on its successful path and on both of its refusals. The project has **not** had a
> professional independent security audit. Do not
> entrust it with an account you cannot recover yet. The reviews and hardware experiments so far
> are recorded in [docs/audits](docs/audits). The threat model against the finished app is PR 17
> and build provenance is PR 18: [docs/BUILD_PROVENANCE.md](docs/BUILD_PROVENANCE.md) measures how
> far a binary can be tied to this source and states plainly that a released binary still cannot be
> checked against it. See [docs/ROADMAP.md](docs/ROADMAP.md) for what is planned and
> [HANDOFF.md](HANDOFF.md) for where the work stands.

## Why another authenticator

Most authenticator apps ask you to trust a company and its service. OpenFactor has no service.
Its security claims are meant to be checked against code, tests, specifications, and measurements
rather than accepted from a product page.

## Security model

OpenFactor does not treat Keychain access as its confidentiality boundary. Account data is
encrypted before it is stored there, and the key needed to decrypt it lives only in each app's
private container. Keychain is storage and, when sync is enabled, transport for ciphertext.

That design protects confidentiality if another authorized app can read OpenFactor's Keychain
items. It does not prevent that app from deleting or replaying them. It also does not defend
against a malicious OpenFactor update, a compromised operating system, or somebody using an
already unlocked device. [docs/VAULT.md](docs/VAULT.md) specifies the key hierarchy, record
formats, recovery path, Watch provisioning protocol, and the limits that remain.

The vault is implemented as of PR 16d, on both iPhone and Apple Watch. The Watch exchange has now
been run between a real phone and a real watch: the successful path, a declined request, and a
phone with no vault of its own. No implementation review has happened, so the specification
remains a design claim rather than a claim about a finished release.

## Principles

1. **No OpenFactor servers and no OpenFactor cloud.** No backend exists. There is nothing
   to breach, subpoena, or shut down. If you turn on sync, encrypted copies do leave the
   device, through Apple's infrastructure and not ours, which is the next point.
2. **Sync only through iCloud Keychain.** In the vault design, the items that sync are
   ciphertext and the key needed to open them never syncs. Apple's escrow remains relevant to
   whether those items can be recovered after every device is lost, so `SECURITY.md` sets out
   what it does and does not mean. Sync is off until you turn it on, and the app explains what
   is synced before you do.
3. **No tracking of any kind.** No analytics, no crash reporting, no first launch ping,
   no anonymous telemetry. The app makes no network requests at all.
4. **Designed for review.** Small files, one concept each, plain naming, byte-exact formats,
   and tests for important claims. The security-sensitive code lives in one small package with
   no UI, so an auditor can read the part that matters without first reading the app.
5. **No third-party dependencies.** Everything is built on CryptoKit, Foundation, SwiftUI,
   and the Keychain, plus CommonCrypto for the password-based key derivation that CryptoKit
   does not provide. This keeps the review boundary limited to OpenFactor and Apple's platform
   frameworks.
6. **You can leave.** Export can write an encrypted OpenFactor backup whose format is public,
   or a plaintext Aegis-compatible file for moving to another authenticator. The interface makes
   the difference explicit because portability should not require hiding the security cost.
7. **Secrets exist only for as long as they are needed.** The vault is where account secrets
   live; everything else is temporary by design: a clipboard code, an exported file, an image
   shared in for import. Every feature that handles secret material defines where it lands, how
   long it lives, and what removes it. If a secret never needs to exist, OpenFactor does not
   create it.

## What it deliberately will not do

**There is no Mac app and no browser extension, on purpose.** A second factor is worth less the
moment it lives on the machine asking for it. Reading a code from a phone or watch is the
separation doing its job, not friction to be designed away.

- Store passwords or fill codes automatically. This is an authenticator, not a password manager.
- Offer an OpenFactor account, server, cloud, or web app.
- Collect data, including anonymous analytics and crash reports.
- Ship a Mac app or browser extension that generates codes.
- Put vault keys in Keychain, iCloud Drive, or a shared App Group container.

## Android

OpenFactor is built specifically for iPhone and Apple Watch. An Android version is not planned.

If you use Android, [Aegis Authenticator](https://getaegis.app/) is a free, open-source
authenticator worth considering. Aegis is an independent project with no affiliation to
OpenFactor.

OpenFactor uses Aegis's documented vault format as one of its portability targets. Its
Aegis-compatible export is plaintext so another authenticator can import it, and must be handled
accordingly.

## Formats and standards

Codes are generated per the published specifications, and the implementation is verified
against the official test vectors in those documents.

- [RFC 4226](https://datatracker.ietf.org/doc/html/rfc4226), HOTP
- [RFC 6238](https://datatracker.ietf.org/doc/html/rfc6238), TOTP
- [RFC 4648](https://datatracker.ietf.org/doc/html/rfc4648), Base32
- The de facto `otpauth://` URI format, for importing from other apps
- [`docs/VAULT.md`](docs/VAULT.md), device storage, encryption, recovery, and Watch
  provisioning. The record layouts are byte-exact and carry pinned test vectors
- [`docs/BACKUP_FORMAT.md`](docs/BACKUP_FORMAT.md), this project's own encrypted backup.
  Written and reviewed before the code, and carrying a test vector produced by three
  implementations sharing no code, so "openable without this app" is a tested claim rather
  than an intention

## Repository layout

```
Package.swift                  OpenFactorCore. No third-party dependencies, and it stays that way.
Sources/OpenFactorCore/        Base32, HOTP, TOTP, otpauth parsing, and the encrypted vault.
                               No UI. This is the security-sensitive code.
Tests/OpenFactorCoreTests/     Including the published RFC vector tables and the fuzzing.
OpenFactor.xcodeproj           The app project. See docs/PROJECT.md for what is in it.
OpenFactor/                    iOS app target. Views, view models, and the app lock.
OpenFactorShared/              The little both app targets need: color and contrast
                               arithmetic, and digit grouping. Compiled into each.
OpenFactorWatch Watch App/     watchOS app. Read only: it shows the list and one code.
OpenFactorWatch Complication/  Launches the app. Holds no data and no Keychain entitlement.
OpenFactorTests/               Runs the suite above inside a real app, for the Keychain.
docs/                          Architecture, roadmap, UI specification, audits.
site/                          Exactly what openfactor.dev serves. Nothing else is published.
```

## Building

Requires Xcode 26 or later, targeting iOS 18 and watchOS 11. The project uses synchronized
folder groups, which older Xcode versions cannot open.

```bash
git clone https://github.com/dragut-eth/openfactor.git
cd openfactor
swift test
```

`swift test` runs the core suite, including the RFC vectors and the fuzzing, in under a
second and without a simulator.

The watch app builds from the same project, and needs the watchOS platform installed, which
Xcode downloads separately from its SDK:

```bash
xcodebuild -project OpenFactor.xcodeproj -scheme 'OpenFactorWatch Watch App' -destination 'generic/platform=watchOS Simulator' build
```

The tests that assert how secrets are protected in the Keychain **skip** under
`swift test`, because reaching the data protection Keychain needs an entitlement that an
unsigned test bundle does not have. To run those, open `OpenFactor.xcodeproj` and run the
tests, or:

```bash
xcodebuild test -project OpenFactor.xcodeproj -scheme OpenFactor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenFactorTests
```

Same files, two contexts. CI runs both. See [docs/PROJECT.md](docs/PROJECT.md).

## Security review status

**OpenFactor has not received a professional independent security audit. Do not trust it with an
account you cannot recover yet.**

That warning stays until it stops being true. A security tool that presents model reviews as a
professional audit would be worse than one that says nothing.

**And do not make any authenticator your only copy, this one included.** OpenFactor ships an
encrypted export for exactly this reason: generate one, **check that it imports**, and keep it
somewhere this app does not touch. An untested backup is not a backup. Whatever its design, an
authenticator that becomes the single holder of every second factor you own is a single point of
failure, and none of the review gates below change that arithmetic.

The project nevertheless reviews security decisions before and after implementation. Findings
are published whether or not they are flattering, and hardware-dependent claims are measured on
real devices where possible. These are engineering review gates, not substitutes for an audit.

**Gate A1** ran on 2026-08-14 against the core, tag `audit-a1`: an adversarial model
review, the RFC vector tables re-verified against the IETF documents, and 17,000+ fuzz
iterations. Two defects found and fixed, full findings in
[docs/audits/A1.md](docs/audits/A1.md), and its one open item closed in PR 5 when the
protection class tests first ran for real.

**Gate A2** ran on 2026-08-14 against iCloud Keychain sync, the only feature that lets stored
account material leave the device, and again after the watch app was finished. Fourteen findings
across the two passes are recorded in [docs/audits/A2.md](docs/audits/A2.md). Its remaining
single-device questions were later closed by hardware experiments; the broader two-writer case
still needs a second writing device.

**Gate A3** reviewed the encrypted backup format before implementation, then reviewed the
implementation separately. The format carries public test vectors reproduced by independent
implementations. Findings and fixes are recorded in [docs/audits](docs/audits).

**Gate A4** ran from 2026-08-16 to 2026-08-21, tag `audit-a4`, against the vault at rest, the Watch key exchange,
the parsers and the process boundaries. Three independent models, twenty rounds, eleven
closed-question verification briefs, **133 findings and three highs**, all closed, with two waived
and two withdrawn. The conclusion is [docs/audits/A4.md](docs/audits/A4.md) and every finding is
listed in [docs/audits/A4-board.md](docs/audits/A4-board.md). **It also records the gate's own
worst moment**, a day when eight of eleven newly open items were defects in that day's fixes, and
a finding that all three models verified as fixed and that turned out never to have been real.

**The vault design** was reviewed in two rounds before implementation. Those reviews found the
incomplete Watch ECDH exchange, unspecified record layouts, ambiguous wrapped-key sync semantics,
and missing-data detection that could silently report a destroyed vault as empty. The revised
design, its remaining limits, and the hardware probes supporting it are all linked from
[docs/VAULT.md](docs/VAULT.md).

The reviews so far are model-assisted adversarial reviews, not professional human audits, and
they do not soften the warning above.

**Which commit was last audited, and how to check a build yourself.** `audit-a4` is the tag, and
every gate from here reviews the diff since it. **[VERIFYING.md](VERIFYING.md) is the instructions**:
four things you can check, in order of what they cost, from reading a release record to rebuilding
the code and comparing per-section hashes. Two independent Release builds of one commit produce
identical digests in every section that has file bytes.

**What you cannot check is the binary Apple served to your phone**, because its executable is
encrypted on an App Store install. That correspondence **cannot be verified on stock iOS through
public interfaces**, which is narrower than saying it is impossible.
[docs/BUILD_PROVENANCE.md](docs/BUILD_PROVENANCE.md) measures the limit rather than working around
it.

## Documentation

- [docs/ROADMAP.md](docs/ROADMAP.md), the PR by PR delivery plan
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), how the pieces fit and why
- [docs/VAULT.md](docs/VAULT.md), the normative storage and key-management design
- [docs/BACKUP_FORMAT.md](docs/BACKUP_FORMAT.md), the portable encrypted backup format
- [docs/UI_SPEC.md](docs/UI_SPEC.md), every screen and its behavior
- [docs/PROJECT.md](docs/PROJECT.md), what is in the Xcode project, in plain language
- [docs/audits/](docs/audits/), findings from each review gate
- [SECURITY.md](SECURITY.md), threat model and how to report a vulnerability
- [docs/MASVS.md](docs/MASVS.md), a self-assessment against OWASP MASVS v2.1.0, published whole,
  including the two partials, the one fail, and what is deliberately out of scope
- [CONTRIBUTING.md](CONTRIBUTING.md), how changes get reviewed
- [site/README.md](site/README.md), the pages at [openfactor.dev](https://openfactor.dev) and the
  rule they are written under

**The website derives from this repository and never the reverse.** Every claim on
`openfactor.dev` was copied out of this file and `docs/APP_STORE.md` rather than written fresh,
and that is the only reason the website, the App Store listing and this file agree. A claim
changes here or in `SECURITY.md` first, and the other two follow.

## Inspiration

OpenFactor is inspired by [Step Two](https://steptwo.app/), whose focused, Apple-native design I
use every day and admire. It is an independent implementation built from public standards. Step
Two's creator has not participated in or endorsed this project, and no Step Two source code,
assets, or artwork are used here.

I built OpenFactor because if I am going to depend on something as consequential as an
authenticator, I would rather be able to read the source and see how my data is handled. That is
a preference for verification over trust, not a criticism of a very good app.

## License

MIT. See [LICENSE](LICENSE).
