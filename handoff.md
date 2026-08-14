# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

**Last updated:** 2026-08-14, end of PR 2.

## Where things stand

PR 2 is complete. The app can generate codes. `HOTP` and `TOTP` are verified against the
full RFC 4226 Appendix D and RFC 6238 Appendix B vector tables, for all three algorithms.

| Phase | Status |
| --- | --- |
| PR 0, repository bootstrap | Done |
| PR 1, `OpenFactorCore` and Base32 | Done |
| PR 2, HOTP and TOTP | Done |
| PR 3, `otpauth://` parsing | Next |
| PR 4 onward | Not started, see [docs/ROADMAP.md](docs/ROADMAP.md) |

**Next audit gate: A1, immediately after PR 4.** The core gets reviewed by someone who did
not write it before anything is built on top of it. The five gates and the rules for them
are in [docs/ROADMAP.md](docs/ROADMAP.md). A gate that gets waived quietly is the failure
this project is trying to avoid, so this line is updated in every pull request.

## What exists

```
Package.swift                              OpenFactorCore, no dependencies
Sources/OpenFactorCore/
  Base32.swift, Base32Error.swift          RFC 4648 decoding and encoding
  OTPAlgorithm.swift, OTPDigits.swift      The parameters a service enrolls with
  HOTP.swift                               RFC 4226, the only hand written cryptography
  TOTP.swift, TOTPConfiguration.swift      RFC 6238, time arithmetic only
Tests/OpenFactorCoreTests/                 32 tests across 4 suites, all passing
LICENSE, README.md, SECURITY.md, CONTRIBUTING.md, handoff.md
docs/ROADMAP.md, docs/ARCHITECTURE.md, docs/UI_SPEC.md
.github/workflows/ci.yml                   Style checks, then build and test
```

Run the suite with `swift test`. It takes about a tenth of a second and needs no simulator.

## Decisions locked in

- iOS 18 and watchOS 11 minimum, macOS 15 declared only so the suite runs in CI
- MIT license
- Zero third party dependencies. Swift Testing ships with the toolchain, so it is not one
- Typed throws throughout the core, so every failure a caller must handle is in the
  signature
- Base32 accepts lowercase, spaces, and hyphens, rejects anything else with a specific
  error, and discards the leftover bits at the end of a secret
- The moment to generate a code for is always a parameter. Nothing in the core calls
  `Date()`. This replaced the clock protocol the roadmap originally called for
- The secret is never stored in a configuration object, only passed to the function that
  needs it
- Codes are `String`, never `Int`, so a leading zero survives
- Digit counts are an enumeration of 6, 7, and 8, so an unsupported length cannot be built
- Periods are validated on construction, 1 second to 1 hour
- Light mode is a v1 requirement, not a later addition
- Sync through iCloud Keychain, not CloudKit
- Squash merges into `main`, Conventional Commits

## Decisions still open

- Whether the `.xcodeproj` is checked in or generated from a spec. Decided in PR 5,
  current lean is to generate
- The encrypted export format. Decided in PR 16

## Effort and model, by pull request

Xavier sets the reasoning effort himself and can switch between Opus 5 and Fable 5. The
recommendation for each pull request is stated before it starts, so the lever gets pulled
deliberately rather than left where it happened to be.

| Pull request | Suggested effort | Note |
| --- | --- | --- |
| PR 3, URI parsing | High | The only place untrusted input enters the app. Currently set to High |
| PR 4, Keychain | High | Accessibility attributes fail silently and hand over secrets |
| PR 5 to PR 12, interface | Medium | Ordinary app work, and mechanical once the spec is settled |
| PR 13, sync | High | Changes the threat model |
| PR 15, app lock | High | The interesting part is the bypass paths, not the Face ID call |
| PR 16, export | High | Applied cryptography, and the one decision that cannot be undone |
| PR 17, threat model | High | Where a wrong claim becomes a published promise |

The reviewer at a gate is never the model that wrote the code. A writer and a reviewer
sharing a model share their blind spots.

## Notes for whoever works on this next

- `assets/` holds Step Two reference screenshots. It is gitignored on purpose and must
  never be committed. `docs/UI_SPEC.md` captures everything needed from it.
- Nothing has been pushed to the remote. Do not push without asking Xavier.
- No em dashes anywhere. CI enforces this, as it does trailing whitespace.
- The RFC vector tables are the authority. If a change breaks one, the change is wrong.
- RFC 6238 Appendix B uses a **different seed per algorithm**, 20, 32, and 64 bytes.
  Running the whole table against the 20 byte seed is the usual way to get it wrong.

## Next step

PR 3: `OTPAuthURI`, parsing and serializing `otpauth://` URIs. Parsing must be total,
meaning every input yields either a fully valid account or a typed error, never a
partially populated one. The messy cases to cover are an issuer that appears both as a
label prefix and as a query parameter and disagrees, percent encoding, and missing
optional parameters. Test against a corpus of URIs as emitted by Google Authenticator,
1Password, GitHub, and AWS. The period validation in `TOTPConfiguration` is already
typed, so the parser should surface that error rather than inventing its own.
