# OpenFactor

A minimalist two factor authentication app for iPhone and Apple Watch.

Your secrets stay on your device. There is no OpenFactor account, no OpenFactor server,
and no analytics. The only thing that ever leaves your phone is an optional iCloud
Keychain sync, which Apple cannot read.

> **Status: pre alpha.** The repository is being built in public from the first commit.
> Nothing is shippable yet. See [docs/ROADMAP.md](docs/ROADMAP.md) for what is planned
> and [handoff.md](handoff.md) for where the work currently stands.

## Why another authenticator

Most authenticator apps ask you to trust a company. This one asks you to trust code you
can read. Every design decision below follows from that.

## Inspiration

OpenFactor is heavily inspired by [Step Two](https://steptwo.app/), which I use every day
and consider the best two factor authenticator available. The feature set here
deliberately follows its shape.

I asked its creator, Neil Sardesai, more than once over a few years, whether he would open
source Step Two or license it to me so that I could. He declined, politely, and wished me
luck. He has had no involvement in OpenFactor and has not endorsed it. No Step Two source
code, assets, or artwork is used here, and nothing was decompiled or extracted. Everything
is written from the published RFCs.

I built it because if I am going to depend on something as consequential as an
authenticator, I would rather be able to read the source and see how my data is handled.
That is a preference for verification over trust, not a criticism of a very good app.

## Principles

1. **No OpenFactor servers and no OpenFactor cloud.** No backend exists. There is nothing
   to breach, subpoena, or shut down. If you turn on sync, encrypted copies do leave the
   device, through Apple's infrastructure and not ours, which is the next point.
2. **Sync only through iCloud Keychain,** which is end to end encrypted, and Apple cannot
   read the synced items. The keys are escrowed with Apple in a form guarded by hardware
   security modules, so "Apple holds no key" would be too strong a claim; `SECURITY.md`
   sets out what that escrow does and does not mean. Sync is off until you turn it on, and
   the app explains what is synced before you do.
3. **No tracking of any kind.** No analytics, no crash reporting, no first launch ping,
   no anonymous telemetry. The app makes no network requests at all.
4. **Auditable by humans and by AI.** Small files, one concept each, plain naming, and no
   third party dependencies. The cryptography lives in one small package with no UI code
   in it, so an auditor can read the part that matters without reading the app.
5. **No dependencies.** Everything is built on CryptoKit, Foundation, SwiftUI, and the
   Keychain. Every dependency is code you would otherwise have to trust on our word.

## What it deliberately will not do

**There is no Mac app and no browser extension, on purpose.** A second factor is worth
less the moment it lives on the machine asking for it. Reading a code off a phone or a
watch is the separation doing its job, not friction to be designed away.


- Store passwords. This is an authenticator, not a password manager.
- Offer accounts, servers, or a web app.
- Collect data, including the anonymous kind.
- Ship a browser extension.
- Run anywhere but Apple platforms.

## Standards

Codes are generated per the published specifications, and the implementation is verified
against the official test vectors in those documents.

- [RFC 4226](https://datatracker.ietf.org/doc/html/rfc4226), HOTP
- [RFC 6238](https://datatracker.ietf.org/doc/html/rfc6238), TOTP
- [RFC 4648](https://datatracker.ietf.org/doc/html/rfc4648), Base32
- The de facto `otpauth://` URI format, for importing from other apps

## Repository layout

```
Package.swift                  The OpenFactorCore package. No dependencies, and it stays that way.
Sources/OpenFactorCore/        Base32, HOTP, TOTP, otpauth parsing, secret storage.
                               No UI. This is the security sensitive code.
Tests/OpenFactorCoreTests/     Including the published RFC vector tables and the fuzzing.
OpenFactor.xcodeproj           The app project. See docs/PROJECT.md for what is in it.
OpenFactor/                    iOS app target. Views, view models, and the app lock.
OpenFactorShared/              The little both app targets need: colour and contrast
                               arithmetic, and digit grouping. Compiled into each.
OpenFactorWatch Watch App/     watchOS app. Read only: it shows the list and one code.
OpenFactorWatch Complication/  Launches the app. Holds no data and no Keychain entitlement.
OpenFactorTests/               Runs the suite above inside a real app, for the Keychain.
docs/                          Architecture, roadmap, UI specification, audits.
```

## Building

Requires Xcode 26 or later, targeting iOS 18 and watchOS 11. The project uses synchronised
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

## Audits

**OpenFactor has not been audited. Do not trust it with a real account yet.**

That sentence stays exactly as it is until it stops being true. An unaudited security tool
that reads as though it were audited is worse than one that says nothing.

Five review gates are planned, and the plan is public before any of them have happened, in
[docs/ROADMAP.md](docs/ROADMAP.md): the core before anything is built on it, sync, the
export format before any user has a backup, the finished app, and then the diff at every
release after that. Findings get published whether or not they are flattering, and this
section will name the audited commit and who reviewed it.

**Gate A1** ran on 2026-08-14 against the core, tag `audit-a1`: an adversarial model
review, the RFC vector tables re-verified against the IETF documents, and 17,000+ fuzz
iterations. Two defects found and fixed, full findings in
[docs/audits/A1.md](docs/audits/A1.md), and its one open item closed in PR 5 when the
protection class tests first ran for real.

**Gate A2** ran on 2026-08-14 against iCloud Keychain sync, the only feature that lets
secret material leave the device, and again after the watch app was finished. Fourteen
findings across the two passes, in [docs/audits/A2.md](docs/audits/A2.md). None was a path
by which a secret escapes; almost all were sentences the interface or these documents
asserted that the code could not back, which for a security tool is its own kind of defect.
Two remain open and are marked as such wherever they are relied on: what turning sync off
does to copies on other devices, where Apple's documentation and this project's expectation
disagree, and one merge case that needs two devices to settle.

Both were model reviews, not human ones, and they do not soften the warning above.

## Documentation

- [docs/ROADMAP.md](docs/ROADMAP.md), the PR by PR delivery plan
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), how the pieces fit and why
- [docs/UI_SPEC.md](docs/UI_SPEC.md), every screen and its behavior
- [docs/PROJECT.md](docs/PROJECT.md), what is in the Xcode project, in plain language
- [docs/audits/](docs/audits/), findings from each review gate
- [SECURITY.md](SECURITY.md), threat model and how to report a vulnerability
- [CONTRIBUTING.md](CONTRIBUTING.md), how changes get reviewed

## License

MIT. See [LICENSE](LICENSE).
