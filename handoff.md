# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

**Last updated:** 2026-08-14, end of PR 1.

## Where things stand

PR 1 is complete. The `OpenFactorCore` package exists with Base32 decoding and encoding,
verified against the RFC 4648 vector table. CI builds and tests for real now, with no
guard on the test step.

| Phase | Status |
| --- | --- |
| PR 0, repository bootstrap | Done |
| PR 1, `OpenFactorCore` and Base32 | Done |
| PR 2, HOTP and TOTP | Next |
| PR 3 onward | Not started, see [docs/ROADMAP.md](docs/ROADMAP.md) |

## What exists

```
Package.swift                          OpenFactorCore, no dependencies
Sources/OpenFactorCore/Base32.swift    RFC 4648 decoding and encoding
Sources/OpenFactorCore/Base32Error.swift   Typed errors, each with a user readable message
Tests/OpenFactorCoreTests/Base32Tests.swift  13 tests, 137 cases, all passing
LICENSE, README.md, SECURITY.md, CONTRIBUTING.md, handoff.md
docs/ROADMAP.md, docs/ARCHITECTURE.md, docs/UI_SPEC.md
.github/workflows/ci.yml               Style checks, then build and test
```

Run the suite with `swift test`. It takes well under a second and needs no simulator.

## Decisions locked in

- iOS 18 and watchOS 11 minimum, macOS 15 declared only so the suite runs in CI
- MIT license
- Zero third party dependencies. Swift Testing is used for tests and ships with the
  toolchain, so it is not a dependency
- Typed throws throughout the core, so every failure a caller must handle is visible in
  the signature
- Base32 accepts lowercase, spaces, and hyphens, and rejects anything else with a specific
  error. Leftover bits at the end of a secret are discarded, not rejected. Reasoning is in
  `docs/ARCHITECTURE.md` and repeated at the code
- Light mode is a v1 requirement, not a later addition
- Sync through iCloud Keychain, not CloudKit
- Squash merges into `main`, Conventional Commits

## Decisions still open

- Whether the `.xcodeproj` is checked in or generated from a spec. Decided in PR 5,
  current lean is to generate
- The encrypted export format. Decided in PR 16

## Notes for whoever works on this next

- `assets/` holds Step Two reference screenshots. It is gitignored on purpose and must
  never be committed. `docs/UI_SPEC.md` captures everything needed from it.
- Nothing has been pushed to the remote. Do not push without asking Xavier.
- No em dashes anywhere. CI enforces this, as it does trailing whitespace.
- The RFC vector tables are the authority. If a change breaks one, the change is wrong.

## Next step

PR 2: `HOTP` implementing RFC 4226 dynamic truncation over CryptoKit HMAC for SHA1,
SHA256, and SHA512, then `TOTP` on top of it with the clock injected rather than read from
`Date()` directly. Tests are the full RFC 4226 Appendix D and RFC 6238 Appendix B tables.
The seed those tables use already has a decoding test in `Base32Tests`.
