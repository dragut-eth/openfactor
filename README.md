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

## Principles

1. **Nothing is stored online.** No backend exists. There is nothing to breach, subpoena,
   or shut down.
2. **Sync only through iCloud Keychain,** which is end to end encrypted. Apple holds no
   key to it. Sync is off until you turn it on, and the app explains what is synced before
   you do.
3. **No tracking of any kind.** No analytics, no crash reporting, no first launch ping,
   no anonymous telemetry. The app makes no network requests at all.
4. **Auditable by humans and by AI.** Small files, one concept each, plain naming, and no
   third party dependencies. The cryptography lives in one small package with no UI code
   in it, so an auditor can read the part that matters without reading the app.
5. **No dependencies.** Everything is built on CryptoKit, Foundation, SwiftUI, and the
   Keychain. Every dependency is code you would otherwise have to trust on our word.

## What it deliberately will not do

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
OpenFactorCore/    Swift package: Base32, HOTP, TOTP, otpauth parsing, secret storage.
                   No UI, no dependencies. This is the security sensitive code.
App/               iOS app target. Views and view models only.
Watch/             watchOS app target.
docs/              Architecture, roadmap, UI specification, backup format.
```

Nothing above exists yet beyond `docs/`. It arrives PR by PR, per the roadmap.

## Building

Requires Xcode 26 or later, targeting iOS 18 and watchOS 11.

```bash
git clone https://github.com/dragut-eth/openfactor.git
cd openfactor
swift test
```

`swift test` runs the core test suite, including the RFC vectors, without opening Xcode.

## Documentation

- [docs/ROADMAP.md](docs/ROADMAP.md), the PR by PR delivery plan
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), how the pieces fit and why
- [docs/UI_SPEC.md](docs/UI_SPEC.md), every screen and its behavior
- [SECURITY.md](SECURITY.md), threat model and how to report a vulnerability
- [CONTRIBUTING.md](CONTRIBUTING.md), how changes get reviewed

## License

MIT. See [LICENSE](LICENSE).
