# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

**Last updated:** 2026-08-14, end of PR 4.

## Where things stand

PR 4 is complete. `OpenFactorCore` is finished. Accounts can be saved, listed, read,
renamed, reordered, and deleted, and the list is drawn without decrypting a single secret.

**Stop here for gate A1 before starting PR 5.**

| Phase | Status |
| --- | --- |
| PR 0, repository bootstrap | Done |
| PR 1, `OpenFactorCore` and Base32 | Done |
| PR 2, HOTP and TOTP | Done |
| PR 3, `otpauth://` parsing | Done |
| PR 4, Keychain storage | Done, with one item deferred, see below |
| Gate A1, audit the core | **Next** |
| PR 5 onward | Not started, see [docs/ROADMAP.md](docs/ROADMAP.md) |

**Next audit gate: A1, now.** The core is complete and nothing is built on it, which is
the cheapest moment it will ever be to find something wrong. The five gates and the rules
for them are in [docs/ROADMAP.md](docs/ROADMAP.md). A gate that gets waived quietly is the
failure this project is trying to avoid, so this line is updated in every pull request.

**The one thing A1 cannot close.** The Keychain protection class on a stored secret is
implemented but unverified: asserting it needs the data protection Keychain, which needs an
entitlement, which needs code signing, which a `swift test` bundle does not have. Six tests
are written and skipped. They run against the host application target that PR 5 adds first,
and A1 stays open on that point until they pass. The macOS legacy Keychain is not a stand
in: it accepts the writes and ignores `kSecAttrAccessible` entirely, so a test against it
would pass while proving nothing.

## What exists

```
Package.swift                              OpenFactorCore, no dependencies
Sources/OpenFactorCore/
  Base32.swift, Base32Error.swift          RFC 4648 decoding and encoding
  OTPAlgorithm.swift, OTPDigits.swift      The parameters a service enrolls with
  HOTP.swift                               RFC 4226, the only hand written cryptography
  TOTP.swift, TOTPConfiguration.swift      RFC 6238, time arithmetic only
  OTPGenerator.swift, OTPAccount.swift     What an account is. OTPAccount is transient
  OTPAuthURI.swift, ...Serialization.swift Import and export, plus OTPAuthURIError
  SecretStore.swift, SecretStoreError.swift  The storage contract
  KeychainSecretStore.swift                One Keychain item per account
  InMemorySecretStore.swift                For previews and tests. Never used by the app
  AccountMetadata.swift, AccountColor.swift  What is stored beside a secret
Tests/OpenFactorCoreTests/                 99 tests across 11 suites, plus 6 skipped
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
- URI parsing is generous about form and strict about meaning. Nothing that changes a
  code is ever guessed, so a counter based account with no counter is refused rather than
  started at zero
- The `issuer` parameter beats the label prefix. A bare colon is the label separator
  wherever one exists, and `%3A` counts only when there is no bare colon
- `OTPAccount` is the one type pairing a secret with metadata, and is deliberately
  transient and not `Codable`
- One Keychain item per account, secret in `kSecValueData` and metadata as JSON in
  `kSecAttrGeneric`. Two items can get out of step, one cannot
- Metadata is in the Keychain too, because account names say which services someone uses
  and under which email, which is sensitive even though it cannot generate a code
- Listing accounts sets `kSecReturnData` to false, so drawing the list decrypts nothing.
  There is deliberately no call that returns every account with its secret
- Decoding stored metadata runs the same validation as constructing it. A record with a
  period of zero is refused rather than dividing by zero later
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

**Gate A1, not a pull request.** The checklist is in [docs/ROADMAP.md](docs/ROADMAP.md).
In short: an independent review of the whole of `OpenFactorCore` by someone or something
that did not write it, `/security-review` over the accumulated diff, the RFC vector tables
re-checked by hand against the published documents rather than against what the tests
assert, fuzzing of the parser and the Base32 decoder, and a check that no secret material
reaches a log or a description. Findings recorded in the open, audited commit tagged.

Then PR 5, whose first job is the host application test target that lets the six skipped
Keychain tests run. Nothing else in PR 5 matters until they pass.

Suggested effort: **High** for the gate itself, then **Medium** from PR 5 onward, where
the work turns into ordinary interface building.
