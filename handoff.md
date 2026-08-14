# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

**Last updated:** 2026-08-14, end of gate A1.

## Where things stand

Gate A1 has run. Findings, fixes, and the honesty caveats are in
[docs/audits/A1.md](docs/audits/A1.md), and the audited commit is tagged `audit-a1`. Two
defects were found and fixed with regression tests, fuzzing is now a permanent part of the
suite, and the RFC vector tables were re-verified against the IETF documents themselves.

A1 remains open on exactly one point: the six skipped Keychain tests, which need the host
application target that PR 5 builds first.

| Phase | Status |
| --- | --- |
| PR 0, repository bootstrap | Done |
| PR 1, `OpenFactorCore` and Base32 | Done |
| PR 2, HOTP and TOTP | Done |
| PR 3, `otpauth://` parsing | Done |
| PR 4, Keychain storage | Done |
| Gate A1, audit the core | Done, except the item below |
| PR 5, app shell | **Next**, and its first job closes A1 |
| PR 6 onward | Not started, see [docs/ROADMAP.md](docs/ROADMAP.md) |

**Next audit gate: A2, after PR 13.** A1 ran on 2026-08-14 and is recorded in
[docs/audits/A1.md](docs/audits/A1.md), open on one point: the Keychain protection class is
implemented but unverified, because asserting it needs an entitlement an unsigned
`swift test` bundle does not have. Six tests are written and skipped. PR 5's first job is
the host application test target that runs them, and A1 closes when they pass. F3, F4, and
F5 in the audit record carry obligations into PR 7, the HOTP PR, and PR 17 respectively.

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
Tests/OpenFactorCoreTests/                 106 tests across 12 suites, plus 6 skipped,
                                           including 17k iteration deterministic fuzzing
docs/audits/A1.md                          Gate A1 findings and disposition
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

PR 5, the Xcode project and app shell. In order:

1. The host application test target, so the six skipped Keychain tests run. This closes
   A1, and nothing else in the PR matters until they pass. Record the result in
   docs/audits/A1.md.
2. The project format decision (checked in .xcodeproj versus generated). Current lean is
   to generate. Record it in docs/ARCHITECTURE.md.
3. The iOS app target depending on the local package, launching to an empty list.

Suggested effort: **Medium**. This is project plumbing and interface shell. A cold session
adversarial review of Sources/ remains worth doing at any point, see the honesty note in
the audit record.
