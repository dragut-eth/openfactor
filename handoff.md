# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

**Last updated:** 2026-08-14, after gate A2 and its follow up.

## Where things stand

**Gate A2 is done and its follow up has landed.** The report is
`docs/audits/A2.md`, findings F8 to F18. It found no path by which a secret leaves the
device beyond what the switch is documented to do, and confirmed `setSynchronizable(_:)`
reads no secret on any branch. Every finding was a sentence the interface or the documents
asserted that the code or Apple's documentation could not back.

Nine of eleven are fixed: F9 through F12 and F14 through F18. Two remain open because they
need a second device on the same Apple Account, and both are in the experiment at the end of
the report:

- **F8, what turning sync off does to copies elsewhere.** Apple's `kSecAttrSynchronizable`
  documentation says updates through that key affect all copies, which is the opposite of
  what this project first expected. The interface no longer claims either way.
- **F13, a two device state that may defeat the repair claim.** Off on A, copies re-arrive
  from B, A holds a local and a synced item with the same UUID. Whether turning sync back on
  then wedges is unknown. The single device half of the repair claim is now tested.

**Do not let either harden into fact by being repeated.** Both are written as unknown in
`SECURITY.md` and `docs/ARCHITECTURE.md`.

PR 13 is complete. Sync is built, off by default, and the two
documents that make claims about it, `SECURITY.md` and `docs/ARCHITECTURE.md`, were
rewritten to say what the code does rather than what was planned.

**The one thing worth knowing before touching it again:** switching sync never reads a
secret. `setSynchronizable(_:)` lists accounts with `kSecReturnData` explicitly false and
calls `SecItemUpdate` on each one. Read, delete, re-add is the obvious shape and is wrong
three times over: it decrypts every secret, holds them all in memory at once, and a crash
between the delete and the add loses an account outright. If a future change makes that
method read data, that is the regression to catch.

**The switch itself has not been operated by a human.** Synthetic taps do not reach a
SwiftUI `Toggle` in this simulator harness, the same limitation that made the long press
untestable in PR 12. The path behind it was proved instead, by a temporary button calling
the identical binding: the Keychain items converted, the preference flipped, and the list
still read them back afterwards. That leaves the switch's own behaviour as the one thing
Xavier should check on device before A2.

Proving it that way found a real bug and is the reason `SyncAwareKeychainStore` exists. The
first version made the root view's identity depend on the preference, so flipping sync
rebuilt the view tree and dismissed the settings sheet the instant the switch was touched.

**Two claims in the sync documentation are still reasoned, not observed,** because they need
a second device and there is one. Gate A2 settled the third: Apple's documentation says
watchOS 7 and later synchronizes keychain items, so the watch design stands, and what is left
to prove there is the access group itself in PR 14. That turning sync off on this device leaves the copies on
another device alone; that the merge behaviour is what iCloud Keychain's service plus
account keying implies; and that a watchOS target in the same access group actually sees
the phone's items. All three are written down as unverified, in `SECURITY.md` and
`docs/ARCHITECTURE.md`, and all three are on gate A2. Do not let them harden into fact by
being repeated.

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
| PR 13, iCloud Keychain sync | Done |
| Gate A2, audit of sync | Done. Nine of eleven findings fixed, F8 and F13 need two devices |
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
OpenFactorTests/                           App only tests, eight files. Palette contrast,
                                           add and manual setup, settings, clipboard,
                                           edit, and the sync aware store
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
- `docs/UI_SPEC.md` justifies App Lock with "the reference has no lock at all", which
  overstates it. iOS 18 can lock any individual app with Face ID at the system level, so
  the real case for App Lock is the configurable grace period and hiding codes on return
  from background. Reword when PR 15 lands.
- Nothing has been pushed to the remote. Do not push without asking Xavier.
- No em dashes anywhere. CI enforces this, as it does trailing whitespace.
- The RFC vector tables are the authority. If a change breaks one, the change is wrong.
- RFC 6238 Appendix B uses a **different seed per algorithm**, 20, 32, and 64 bytes.
  Running the whole table against the 20 byte seed is the usual way to get it wrong.

## Polish landed after PR 13

Small items Xavier raised while testing the sync build, before PR 14 starts.

- **The app icon was swapped to the cube artwork.** `docs/UI_SPEC.md` describes it, and
  records one thing the previous icon did not have to answer for: a mixed colour cube reads
  as a Rubik's Cube, which is a question for the App Store submission in PR 18 rather than
  a known problem.
- **The context menu no longer lifts the row, only the card.** The row is full width and
  square cornered, so lifting it showed a bright margin down each side in light mode where
  the row's background sat either side of the inset card. `contentShape` already named a
  shape for the drag preview and not for the context menu preview; it now names both, which
  is the fix for the same underlying cause in the other direction.

## Next step

**PR 14, the watchOS app.** Read only, and it starts by proving the access group assumption
rather than assuming it. That stub is also the second device the two open findings need, so
running the F8 and F13 experiment is part of PR 14 rather than a separate errand.

If Xavier has an iPad or a second iPhone on the same Apple Account, the experiment can run
before PR 14 instead, which would settle F8 and F13 sooner and cheaper.

## What gate A2 was for, kept for reference

**It was a stop rather than a formality.** Sync is the only feature that lets
secret material off the device, and the interface now makes explicit promises about it in
the settings footer. Those promises have to be true, not reassuring.

Run it cold, on a fresh session, with a model that has not just written the code. Fable 5,
as with A1. **The prompt is written and ready in `docs/audits/A2-prompt.md`**: paste it
whole rather than describing the task from memory, since the point of the gate is a second
opinion and a summary of what to look for would smuggle in the author's conclusions. What
it is for:

1. **The three unverified claims listed above.** They are the weakest part of this PR. Each
   is written from reasoning about how iCloud Keychain works, and reasoning about Apple's
   Keychain has been wrong in this project before.
2. **Check the claims against Apple's current documentation,** rather than against what
   this repository asserts about end to end encryption and what Apple can read.
3. **`setSynchronizable(_:)` specifically.** It is the only method that touches every
   account at once. Confirm no path through it reads secret data, and that a failure part
   way through leaves a state that running it again repairs.
4. **The settings footer text.** Read it as a user would, and ask whether anything in it is
   more comforting than the code justifies.

After A2, **PR 14, the watchOS app.** Read only, and it starts by proving the access group
assumption rather than assuming it.

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
