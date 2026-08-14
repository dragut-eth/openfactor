# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

**Last updated:** 2026-08-14, end of PR 5.

## Where things stand

PR 5 is complete and **gate A1 is fully closed.** There is an Xcode project, the app
launches on the simulator and shows an empty state read from the real Keychain, and the six
Keychain tests that could only ever skip before now pass against the data protection
Keychain. 407 test cases hosted, none skipped.

| Phase | Status |
| --- | --- |
| PR 0, repository bootstrap | Done |
| PR 1, `OpenFactorCore` and Base32 | Done |
| PR 2, HOTP and TOTP | Done |
| PR 3, `otpauth://` parsing | Done |
| PR 4, Keychain storage | Done |
| Gate A1, audit the core | Done and fully closed |
| PR 5, Xcode project and app shell | Done |
| PR 6, design tokens and the card | **Next** |
| PR 7 onward | Not started, see [docs/ROADMAP.md](docs/ROADMAP.md) |

**Next audit gate: A2, after PR 13.** A1 is recorded in
[docs/audits/A1.md](docs/audits/A1.md) and fully closed, with a `/security-review` addendum
that found nothing. F3, F4, F5, and F7 in that record carry obligations into PR 7, the HOTP
PR, and PR 17 respectively. Read them before starting those.

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
Tests/OpenFactorCoreTests/                 106 tests, 12 suites, 17k fuzz iterations
OpenFactor.xcodeproj                       See docs/PROJECT.md, checked in deliberately
OpenFactor/                                App shell: entry point and an empty list
OpenFactorTests/                           Empty folder. Its sources are Tests/ above
docs/audits/A1.md                          Gate A1 findings and disposition
docs/PROJECT.md                            The project file in plain language
LICENSE, README.md, SECURITY.md, CONTRIBUTING.md, handoff.md
docs/ROADMAP.md, docs/ARCHITECTURE.md, docs/UI_SPEC.md
.github/workflows/ci.yml                   Style checks, then build and test
```

Run the suite two ways, and CI runs both:

- `swift test`, under a second, no simulator, Keychain tests **skip**
- `xcodebuild test -project OpenFactor.xcodeproj -scheme OpenFactor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenFactorTests`, about 25 seconds, Keychain tests **run**

Same files both times. `OpenFactorTests` is an empty folder whose sources are
`Tests/OpenFactorCoreTests`, attached as a second synchronised folder. Do not "fix" the
skip under `swift test`: it is correct, and the only way to make those tests pass there
would be to weaken what they assert.

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
- The `.xcodeproj` is checked in rather than generated, reversing the earlier lean. A
  generator would make `brew install` a prerequisite for opening the project. The cost is
  paid back by `docs/PROJECT.md` and a CI job asserting the settings it describes
- Bundle identifier `com.openfactor.dev`, fixed by the App Store Connect record

## Decisions still open

- Whether the watch needs a shared `keychain-access-groups` entitlement to see the phone's
  accounts. Likely yes, unverified. Settle before PR 14, and PR 13 should not assume
  otherwise. See `docs/ARCHITECTURE.md`
- The encrypted export format. Decided in PR 16

## Effort and model, by pull request

Xavier sets the reasoning effort himself and can switch between Opus 5 and Fable 5. The
recommendation for each pull request is stated before it starts, so the lever gets pulled
deliberately rather than left where it happened to be.

| Pull request | Suggested effort | Note |
| --- | --- | --- |
| PR 6 to PR 12, interface | Medium | Ordinary app work, and mechanical once the spec is settled |
| PR 13, sync | High | Changes the threat model |
| PR 15, app lock | High | The interesting part is the bypass paths, not the Face ID call |
| PR 16, export | High | Applied cryptography, and the one decision that cannot be undone |
| PR 17, threat model | High | Where a wrong claim becomes a published promise |

The reviewer at a gate is never the model that wrote the code. A writer and a reviewer
sharing a model share their blind spots.

## Notes for whoever works on this next

- `assets/` holds Step Two reference screenshots. It is gitignored on purpose and must
  never be committed. `docs/UI_SPEC.md` captures everything needed from it.
- `README.md` has an Inspiration section stating what OpenFactor took from Step Two, that
  its creator declined to license it, and that he has no involvement in or endorsement of
  this project. **The App Store description and any other public copy must not imply an
  association either.** Add that to the PR 18 checklist. Do not weaken the sentence about
  no code, assets, or artwork being used: it is the substantive claim in that section and
  it is verifiable against the source.
- `docs/UI_SPEC.md` justifies App Lock with "the reference has no lock at all", which
  overstates it. iOS 18 can lock any individual app with Face ID at the system level, so
  the real case for App Lock is the configurable grace period and hiding codes on return
  from background. Reword when PR 15 lands.
- Nothing has been pushed to the remote. Do not push without asking Xavier.
- No em dashes anywhere. CI enforces this, as it does trailing whitespace.
- The RFC vector tables are the authority. If a change breaks one, the change is wrong.
- RFC 6238 Appendix B uses a **different seed per algorithm**, 20, 32, and 64 bytes.
  Running the whole table against the 20 byte seed is the usual way to get it wrong.

## Next step

PR 6, design tokens and the account card, per `docs/UI_SPEC.md`. Tokens for colour, type,
and spacing defined once for both light and dark, the ten entry account palette with each
entry contrast checked against the text drawn on it, and the card view itself driven by
static preview data so it can be reviewed without a store.

Nothing in `AccountListView.swift` is meant to survive PR 6 and PR 7. It is a shell that
proves the app launches and reads the Keychain.

Suggested effort: **Medium**, and Opus 5 is the right seat for it. Fable 5 earns its keep
again at gate A2, PR 16, and PR 17.

Still worth doing at any time: a genuinely cold adversarial review of `Sources/` from a
fresh session, since the A1 review shared this session's context. See the honesty note at
the top of the audit record.
