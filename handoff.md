# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

## Where things stand

**Last updated:** 2026-08-15, PR 15 built and awaiting Xavier's device pass.

| | |
| --- | --- |
| PR 0 to PR 12 | Done. Core, app, scanning, editing, polish, accessibility |
| PR 13, iCloud Keychain sync | Done |
| Gate A2, audit of sync | Done, twice. Original eleven findings closed except F8 and F13's two device half; three new findings from the re-verification, all fixed |
| PR 14, watchOS app | Feature complete on `pr-14-watch`, re-verified, pushed |
| PR 15, app lock | Built on `pr-15-app-lock`, pushed. Face ID needs a real device |
| PR 16, export and import | Format written and pushed on `pr-16-backup-format`. **Gate A3 next.** No code yet, on purpose |
| PR 17 onward | Not started, see [docs/ROADMAP.md](docs/ROADMAP.md) |

**What only Xavier can verify in PR 15:** Face ID and passcode unlock, the grace periods,
and that no frame of the account list escapes before the lock screen on real hardware. The
simulator has no biometrics, so everything about the lock has been proved by the engine's
tests and by burst screenshots, never by a face.

**Two things remain genuinely open, and both need a second device rather than more code.**
Gate A2's F8, what turning sync off does to copies elsewhere, where this project's
documentation and Apple's point in opposite directions, and F13's two device half, a same
UUID twin that may defeat the repair claim. The experiment is written at the end of
`docs/audits/A2.md`. Xavier now has the watch, so it is runnable.

### Gate A3 reported, and the format is not frozen yet

**Verdict: not yet safe to make permanent**, on two blocking findings, both now fixed.
`docs/audits/A3.md` has the full report, findings F22 to F32.

F22 is the one worth remembering. The published test vector had been produced by feeding
the key derivation the *displayed* passphrase, hyphens included, while the document's own
rule says hyphens are not part of it, and the vector's caption claimed the stripped form had
been used. Anyone following the rule would have failed to reach the published bytes and
assumed their own error; anyone reaching them would have shipped the bug the rule exists to
prevent. Two conforming readers, disagreeing forever about which archives open. Exactly what
this gate was scheduled to catch.

F24, the passphrase entry contradiction, was found independently by A3 and by a review
Xavier commissioned elsewhere. The format now carries a `passphrase` mode field, so a reader
never has to guess which canonicalisation produced the key.

The vector was regenerated and re-verified from the *displayed* form through the
canonicalisation, by CommonCrypto, Python and Node, so the check now exercises the rule
instead of bypassing it.

**Two open items remain**, unchanged by A3: gate A2's F8 and F13, which need the two device
experiment. The watch exists now, so they are runnable.

### PR 16 is inverted, and that is the design

The format was written before the implementation, because an archive in a user's hands makes
version 1 permanent. `docs/BACKUP_FORMAT.md` is the artefact gate A3 audits, and the prompt
is ready in `docs/audits/A3-prompt.md`.

The document carries a test vector produced by three implementations sharing no code:
CommonCrypto and Python's `hashlib` agree on the derived key, and Node's OpenSSL decrypts
what CryptoKit sealed with the tag and AAD verified. The task set for the auditor is to
write a fourth decryptor from the page alone and see whether it reaches those bytes. Every
ambiguity they have to guess at is a finding.

Settled with Xavier before writing it: PBKDF2 rather than Argon2id, argued rather than
apologised for; the app generates the passphrase; the plain `otpauth://` export is dropped
in favour of Aegis JSON; export is gated on Face ID and import is not; duplicates skip on
secret; and erase all accounts joins this PR because deleting the app does not clear the
Keychain.

### Three things learned the hard way, kept because they will recur

**iCloud Keychain propagation is slow enough to look like breakage.** Seven accounts took
close to half an hour to reach the watch, arriving one at a time with no error anywhere.
Two confident theories were wrong before that was understood, with a diagnostic showing the
correct state the whole time. It is recorded in `docs/ARCHITECTURE.md` as a design
constraint on the watch's empty state, not as an anecdote.

**The phone cannot see an access group bug, and neither can the test suite.** PR 13
declared the shared group and shipped no migration, so older accounts stayed in the app's
bundle group. The phone reads every group it can reach, so it looked correct; the hosted
tests run inside the app, so they looked correct too. Only the watch, which shares exactly
one group, could see it. `migrateToDefaultAccessGroup()` is the fix.

**Three findings across two audits were the same mistake:** a check whose name promised
more than it did. A2's F13 found the idempotency test only re-running a finished
conversion, F21 found the migration test asserting the no-op path, and F19 found a CI grep
that named directories the project then outgrew. When writing a test or a check here, read
its name back and ask whether it could pass against code that does nothing.

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
Tests/OpenFactorCoreTests/                 The shared core suites, 17k fuzz iterations
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
  Settings/Preferences.swift               Preferences, in UserDefaults. Never secrets
  Settings/SyncAwareKeychainStore.swift    Reads the sync preference per call
  Settings/AppIconChanger.swift            Alternate icons, and the alert iOS insists on
  Lock/AppLockEngine.swift                 Every lock decision. Pure, no clock, tested
  Lock/AppLockController.swift             Scene phases and LocalAuthentication. Thin
  Lock/PrivacyShield.swift                 The app switcher cover. The only UIKit window
OpenFactorShared/                          Compiled into both app targets
  PaletteColor.swift                       Colour and contrast arithmetic
  CodeFormatting.swift                     Digit grouping for transcription
  WatchPalette.swift                       The palette inverted for text on black
OpenFactorWatch Watch App/                 watchOS target. Read only by design
  WatchAccountListView.swift               Tinted rows, and an empty state written for
                                           accounts that are merely still in flight
  WatchCodeView.swift                      One code. Stores no clock, see the file
OpenFactorWatch Complication/              Launches the app. Holds no data, no entitlement
OpenFactorTests/                           App only tests: palette and watch palette
                                           contrast, add and manual setup, settings,
                                           clipboard, edit, sync aware store, access
                                           group migration, and the lock engine
docs/audits/A1.md                          Gate A1 findings and disposition
docs/audits/A2.md                          Gate A2, plus the dated re-verification
docs/audits/A2-prompt.md                   The prompt A2 was run with
docs/PROJECT.md                            The project file in plain language
docs/POLISH.md                             Polish items, for PR 12
docs/design/icon-dark.svg, icon-light.svg  The app icon, source of truth
docs/design/icon-watch.svg                 The watch icon: the extracted piece
LICENSE, README.md, SECURITY.md, CONTRIBUTING.md, handoff.md
docs/ROADMAP.md, docs/ARCHITECTURE.md, docs/UI_SPEC.md
.github/workflows/ci.yml                   Style checks, then build and test
```

Run the suite two ways, and CI runs both:

- `swift test`, under a second, no simulator, Keychain tests **skip**
- `xcodebuild test -project OpenFactor.xcodeproj -scheme OpenFactor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenFactorTests`, about 25 seconds, Keychain tests **run**

The shared core suites run twice. `OpenFactorTests` also holds app only suites whose sources are
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

- Whether a watchOS target in the shared `keychain-access-groups` group actually sees the
  phone's synced items. The entitlement is in place and the phone writes to the group, so
  the decision is made; what is missing is the proof. First thing PR 14 does, before
  anything is built on top of it
- Whether the device preference and the Keychain should ever be reconciled at launch.
  Deliberately not done, because an account arriving from another device looks identical to
  a disagreement, and "fixing" it would pull that account out of sync everywhere. Revisit
  only with evidence that the divergence confuses people in practice
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
- Do not push without asking Xavier. Branches are pushed only when he says so.
- No em dashes anywhere. CI enforces this, as it does trailing whitespace.
- The RFC vector tables are the authority. If a change breaks one, the change is wrong.
- RFC 6238 Appendix B uses a **different seed per algorithm**, 20, 32, and 64 bytes.
  Running the whole table against the 20 byte seed is the usual way to get it wrong.

