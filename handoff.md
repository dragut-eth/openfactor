# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

**Last updated:** 2026-08-14, end of PR 12.

## Where things stand

PR 12 is complete and merged. Fourteen items from Xavier's device testing, plus the
accessibility pass, all recorded in [docs/POLISH.md](docs/POLISH.md). The app icon landed
alongside it, out of band.

**Phase 2 is finished. Every screen in `docs/UI_SPEC.md` exists**, works at accessibility
text sizes, and has been used on a real phone.

**One item in PR 12 was a security matter, and it ended in a decision rather than a fix.**
iOS adds an "Ask Siri" entry to the account card's system context menu, offering to hand
the contents of a two factor code card to an assistant that may process it off device. The
menu was removed, then restored at Xavier's decision, because the replacement cost the lift
and preview animation and the system menu was judged the better product. It is recorded in
`SECURITY.md` as a known and accepted risk with its own threat model entry, and PR 17 owes
either a finding about what the entry transmits or a plain statement that it is unverified.

| Phase | Status |
| --- | --- |
| PR 0, repository bootstrap | Done |
| PR 1, `OpenFactorCore` and Base32 | Done |
| PR 2, HOTP and TOTP | Done |
| PR 3, `otpauth://` parsing | Done |
| PR 4, Keychain storage | Done |
| Gate A1, audit the core | Done and fully closed |
| PR 5, Xcode project and app shell | Done |
| PR 6, design tokens and the card | Done |
| PR 7, account list and live countdown | Done |
| PR 8, add account by QR scan | Done, camera verified on device |
| PR 9, manual setup and counter accounts | Done |
| PR 10, edit mode | Done |
| PR 11, settings sheet | Done |
| PR 12, polish and accessibility | Done |
| PR 13, iCloud Keychain sync | **In progress.** Access group done, sync next |
| PR 14 onward | Not started, see [docs/ROADMAP.md](docs/ROADMAP.md) |

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
  StoredRecords.swift                      What a read returns, readable and not
  KeychainSecretStore.swift                One Keychain item per account
  InMemorySecretStore.swift                For previews and tests. Never used by the app
  AccountMetadata.swift, AccountColor.swift  What is stored beside a secret
Tests/OpenFactorCoreTests/                 106 tests, 12 suites, 17k fuzz iterations
OpenFactor.xcodeproj                       See docs/PROJECT.md, checked in deliberately
OpenFactor/                                App target
  Assets.xcassets/AppIcon.appiconset/      The app icon, single 1024 source
  Design/                                  Tokens, palette, code formatting
  Views/AccountCard.swift                  The card. No state, no timer, no store
  AccountListViewModel.swift               Rows, ticking, search, copying
  AccountListView.swift                    The root screen and the one timer
  CodeClipboard.swift                      The only place codes leave the app
  Scanning/QRDecoder.swift                 Reads QR codes out of an imported image
  Scanning/CameraScannerView.swift         The live camera, and permission state
  Scanning/AddAccountViewModel.swift       Scan, confirm, save. All the judgement
  Scanning/AddAccountView.swift            The add sheet
  Scanning/ManualSetupViewModel.swift      Validation, preview, saving
  Scanning/ManualSetupView.swift           The form, with Advanced collapsed
  Views/EditAccountView.swift              Renaming, and the colour grid
  Settings/SettingsView.swift              Only rows whose features exist
  Settings/Preferences.swift               Sort order and appearance, in UserDefaults
OpenFactorTests/PaletteTests.swift         Contrast asserted, not eyeballed
OpenFactorTests/                           Empty folder. Its sources are Tests/ above
docs/audits/A1.md                          Gate A1 findings and disposition
docs/PROJECT.md                            The project file in plain language
docs/POLISH.md                             Polish items, for PR 12
docs/design/icon.svg                       The app icon, source of truth
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
- The account palette is deeper than Step Two's because every entry must carry white text
  at 4.5 to 1 or better. That is asserted by `PaletteTests`, at both gradient stops and in
  both schemes, so darkening a colour is the only way to add one that fails
- No view hardcodes a colour, radius, or spacing. They all come from `Tokens`, which is
  what makes a light mode regression hard to introduce
- Card gradients only ever darken from the base, so the base is always the worst case for
  contrast and the tests only have to prove two stops
- One timer for the whole list, in the view, ticking the view model once a second. Codes
  are regenerated only when the counter changes, which a test proves by counting Keychain
  reads rather than by inspection
- The view model holds names, colours, and six digits. Never a secret. Asserted by
  reflecting over a row rather than by trusting the comment
- Copied codes are written `localOnly` with an expiry equal to the code's own. Both
  verified: an already expired entry is unreadable, and without `localOnly` the code does
  reach the host clipboard
- `records()` reports unreadable accounts alongside readable ones rather than failing
- A scan never saves directly. It confirms first, showing a live code that can be checked
  against the service while the enrollment page is still open
- An image with more than one QR code is refused rather than guessed at
- Photo import goes through `PhotosPicker`, so the app never gets photo library access and
  never asks for it. The only usage string is for the camera
- Advancing a counter is a single store call that persists before it returns the code, uses
  checked arithmetic, and cannot be done through a metadata update. See F4 in the audit
- Manual setup shows the parser's own typed errors rather than rewriting them, and stays
  quiet until there is something to validate
- Editing exposes only the labels a person chose. The generator settings came from the
  service and changing them would silently stop the codes matching
- Deletion always goes through a confirmation naming the consequence, including the swipe
- Reordering writes back only the positions that changed, and is unavailable during a
  search
- The list drives edit mode from its own state rather than `EditButton`, which toggles a
  different binding than the one the list reads and silently does nothing
- A settings row appears when its feature does. No greyed rows for iCloud, the app lock, or
  export: a settings screen describes what an app does, and in a security tool an
  aspirational row is a false claim
- Sorting is a view of the list. An automatic order never touches the stored positions, so
  the manual arrangement survives switching away and back
- Preferences are in `UserDefaults` because a sort order and a colour scheme reveal nothing.
  Anything naming a service stays in the Keychain with the secrets

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

**PR 13, iCloud Keychain sync.** The first change to the security posture since PR 4, and
the reason gate A2 sits immediately after it.

It is not a feature that gets added on top. Turning sync on **weakens the protection class
on every secret**, from `WhenUnlockedThisDeviceOnly` to `WhenUnlocked`, because a
synchronizable Keychain item cannot be device only by definition. `SecretAccessibility`
already names both classes so the weakening is a visible decision rather than a side effect
of setting a flag, which is the whole reason it was written that way in PR 4.

Three things to settle before writing much of it:

1. **Does the watch need a shared `keychain-access-groups` entitlement?** Open since PR 5
   and still unverified. A watchOS target has its own bundle identifier and therefore its
   own default access group, and iCloud Keychain syncs within a group rather than across
   them. If the answer is yes, it changes what PR 13 writes and where, and retrofitting it
   after people have secrets stored is a migration rather than an edit. Settle it first.
2. **What happens to existing accounts when sync is turned on, and off again.** Items have
   to be rewritten with the new class, and turning it off has to have a defined meaning:
   does it stop syncing, or does it also pull them back to device only, and what happens to
   the copies already on the other device.
3. **Merge behaviour.** Two devices, the same account added on both, the same account
   renamed on both. Duplicates, conflicts, and deletions that come back.

Suggested effort: **High**, and it is the strongest case yet for a second model at the gate.

**The live camera works.** Verified on Xavier's iPhone 15 Pro on 2026-08-14, which closes
the last unverified path in the add flow. The app is installed there, signed with team
HST4KH9P2X passed on the command line so it stays out of the repo.

**Still unproven, and it is the big one:** no code from this app has ever been accepted by
a real service. Every check so far says our output matches the published RFC vectors. None
says a verifier on someone else's server accepts it. That closes the first time Xavier logs
in somewhere using an OpenFactor code.

**The app icon has landed,** out of band rather than as a numbered pull request, since it
was a design task with no dependencies. `docs/design/icon.svg` is the source of truth and
the 1024 PNG in the asset catalog is rendered from it. The reasoning, geometry, and the one
command that regenerates the tinted variant are in `docs/UI_SPEC.md`.

**Polish is PR 12,** widened from an accessibility pass to cover both, because Dynamic Type
at accessibility sizes breaks layouts and separating them means adjusting the same spacing
twice. Items accumulate in [docs/POLISH.md](docs/POLISH.md) as they are noticed. Structural
observations are still fixed when spotted rather than deferred there.

**All audit findings that had code obligations are now closed.** F1, F2, F3, F4, and F6.
F5 (no zeroization) and F7 (metadata is encrypted under the keychain key rather than the
per item class) are accepted limitations that must appear in the PR 17 threat model.

### Testing the app against a real Keychain

`xcodebuild test` runs on a **throwaway clone** of the simulator, so anything written to
the Keychain during a test is gone afterward and the app on the real simulator will not see
it. Pass `-parallel-testing-enabled NO` to run on the device itself. This cost an hour to
work out; it is not obvious from any error message.

Suggested effort: **Medium**, Opus 5. Fable 5 earns its keep again at gate A2, PR 16, and
PR 17.

Still worth doing at any time: a genuinely cold adversarial review of `Sources/` from a
fresh session, since the A1 review shared this session's context. See the honesty note at
the top of the audit record.
