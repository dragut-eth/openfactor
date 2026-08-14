# OpenFactor Roadmap

A PR by PR delivery plan. Every PR is meant to be small enough that a human or an AI
reviewer can read the whole diff in one sitting. That is a hard constraint, not a
preference: the project's value proposition is that the source is auditable.

## Working assumptions

These are defaults chosen so work can start. Say the word and they change.

| Decision | Default | Reason |
| --- | --- | --- |
| Deployment target | iOS 18, watchOS 11 | Modern SwiftUI, still covers the vast majority of active devices |
| License | MIT | Friendliest for an auditable security tool, no barrier to inspection or reuse |
| Dependencies | Zero third party | Every dependency is code an auditor has to trust. CryptoKit covers our needs |
| Project format | Xcode project generated from a checked in spec, or plain `.xcodeproj` | Decided in PR 5, see note there |
| Branching | Short lived branches off `main`, squash merge | Clean, readable history |
| Commits | Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`) | Machine readable changelog |

## Conventions applied to every PR

- Docs (`README.md`, `handoff.md`, and anything else affected) are updated in the same
  PR, never as a follow up.
- No file grows past roughly 300 lines. Split instead.
- Anything in `OpenFactorCore` ships with tests in the same PR.
- Nothing is pushed until Xavier says so.

---

## Phase 1: Foundation

Independent of the mockups, so it can proceed now.

### PR 0: Repository bootstrap

**Goal:** an empty but complete open source repo skeleton.

- `git init`, `.gitignore` for Xcode and Swift
- `LICENSE` (MIT)
- `README.md`: what OpenFactor is, what it deliberately does not do, build instructions
- `SECURITY.md`: vulnerability reporting process, placeholder threat model
- `CONTRIBUTING.md`: how to review, what a security sensitive change requires
- `handoff.md`: running state of the project for the next session
- `docs/ROADMAP.md` (this file), `docs/ARCHITECTURE.md` skeleton
- GitHub Actions workflow: build and test on macOS runner, SwiftLint or swift-format check

**Done when:** CI is green on an empty test suite.

### PR 1: `OpenFactorCore` package skeleton and Base32

**Goal:** the Swift package exists and can decode the one encoding TOTP secrets use.

- `Package.swift` defining `OpenFactorCore`, no dependencies
- `Base32.swift`: RFC 4648 decode, and encode for the export path later
- Tests: RFC 4648 test vectors, padded and unpadded input, invalid characters,
  lowercase input, whitespace tolerance

**Done when:** every RFC 4648 vector passes and malformed input returns an error rather
than throwing away bytes silently.

### PR 2: HOTP and TOTP generators

**Goal:** the cryptographic heart of the app, provably correct.

- `HOTP.swift`: RFC 4226 truncation, SHA1, SHA256, SHA512 via CryptoKit
- `TOTP.swift`: RFC 6238 time step, configurable period and digit count
- The moment to generate for is a parameter rather than something read from `Date()`, so
  tests are deterministic and a clock skew correction stays a call site concern. Delivered
  as a plain `Date` parameter rather than the clock protocol originally planned here, see
  `docs/ARCHITECTURE.md`
- Tests: the full RFC 4226 Appendix D and RFC 6238 Appendix B vector tables

**Done when:** all published vectors pass for all three hash algorithms.

### PR 3: `otpauth://` URI parsing and serialization

**Goal:** import from any QR code the rest of the ecosystem produces.

- `OTPAuthURI.swift`: parse issuer, label, secret, algorithm, digits, period, counter
- Handle the messy real world cases: issuer in both the label prefix and the query
  parameter and disagreeing, percent encoding, missing optional parameters
- Serialization back to a URI for the export path
- Tests: round trip, plus a corpus of URIs as emitted by Google Authenticator, 1Password,
  GitHub, AWS

**Done when:** parsing is total, meaning every input either produces a valid account or a
typed error, never a partially populated account.

### PR 4: Keychain storage layer

**Goal:** secrets at rest, correctly.

- `SecretStore.swift`: protocol plus a Keychain backed implementation
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` by default
- The `synchronizable` flag exposed but left off, wired up in PR 11
- Non secret metadata (issuer, label, color, sort index) stored separately from the secret
  so the UI never needs to page in secret material to draw a list. The color and manual
  sort index are required by the design, see `docs/UI_SPEC.md`
- Tests against a real Keychain in a host app test target

**Done when:** a secret can be written, read, listed, and deleted, and the accessibility
attributes are asserted in tests rather than assumed.

---

## Phase 2: iOS app

Screens and behavior are specified in `docs/UI_SPEC.md`, derived from the Step Two
reference screenshots. Feature parity is the goal, with the adaptations listed there.

### PR 5: Xcode project and app shell

**Goal:** something that launches.

- Xcode project with the iOS app target, depending on the local `OpenFactorCore` package
- App entry point, root navigation, empty state
- Decision recorded in `docs/ARCHITECTURE.md`: whether the project file is checked in
  directly or generated from a spec. A generated project keeps the diff readable, which
  serves auditability, at the cost of an extra tool

**Done when:** the app builds and runs on the simulator and shows an empty list.

### PR 6: Design tokens and the account card

**Goal:** the visual language, in isolation, before it is wired to anything.

- Color, type, and spacing tokens in one place, every one defined for both light and dark
- The ten entry account palette, a light and a dark variant each, all contrast checked
- Previews rendered in both schemes, so a regression in either is visible in review
- The card view: issuer, label, code, countdown ring, gradient background
- Driven by static preview data, so the card can be reviewed without a store

### PR 7: Account list and live countdown

**Goal:** the root screen, functionally.

- Observable view model over `SecretStore` plus `TOTP`
- One shared timer for the whole list, never one per row
- Search filtering by issuer and label
- Top bar: search, settings, add
- Tap to copy, with an expiring pasteboard entry and a confirmation
- View model tests, including that no secret material reaches the view layer

### PR 8: Add account by QR scan

- `AVFoundation` scanner with a scanning frame and hint, feeding the PR 3 parser
- Import a QR from a photo, since services often show the QR on the same phone
- Camera denied path routed to Settings and to manual entry

### PR 9: Manual setup

- Secret Key, Account Name, Email or Username, matching the reference
- Advanced disclosure, collapsed: algorithm, digits, period, TOTP or HOTP
- Inline validation using the PR 3 typed errors
- Live code preview before saving

### PR 10: Edit mode

- `Done` bar, dimmed cards, per card `...` menu
- Change Color, Edit Account Info, Remove
- Drag to reorder, persisted to `sortIndex`
- Removal takes an explicit second confirmation naming the consequence

### PR 11: Settings sheet

- Sort Accounts, Appearance, iCloud, App Lock, Export and Import, About and Source,
  Report an Issue, Rate on the App Store
- Rows are wired to real state as the features land, so this PR delivers the shell plus
  Sort Accounts, Appearance, About, and Report an Issue

### PR 12: Accessibility pass

- Dynamic Type across every screen, VoiceOver labels, Reduce Motion, contrast audit
- Not deferred past this point, since retrofitting it later is far more expensive

---

## Phase 3: Sync, watch, hardening

### PR 13: iCloud Keychain sync, opt in

- A settings toggle that flips items to `kSecAttrSynchronizable`
- Plain language explanation in the UI of exactly what leaves the device and who can read
  it, which is to say Apple cannot
- Conflict and duplicate handling on merge
- `SECURITY.md` updated with the sync threat model

### PR 14: watchOS app

- Watch target reading the same synchronizable Keychain items rather than shuttling
  secrets over WatchConnectivity
- List and countdown, scaled to the watch
- Complication showing the next code or a launch shortcut

### PR 15: App lock

- Face ID, Touch ID, and passcode fallback on launch and on return from background
- Codes blurred until authenticated
- Configurable grace period

### PR 16: Encrypted export and import

- Export as an encrypted archive, passphrase derived with a strong KDF
- Plain `otpauth://` export behind an explicit warning, since users need an escape hatch
- Import of the same format, plus other apps' plain URI lists
- The format documented in `docs/BACKUP_FORMAT.md` so it can be decrypted without this app

### PR 17: Security review and threat model

- Complete `SECURITY.md`: attacker with the unlocked device, the locked device, the iCloud
  account, the App Store binary, or a malicious dependency
- Pasteboard, screenshot, and background snapshot behavior audited
- Confirmation in writing that the binary makes no network calls, with the check automated
  in CI if practical

### PR 18: Release preparation

- App Store metadata, privacy nutrition label declaring no data collected
- Reproducible build notes so a third party can verify the shipped binary
- Version tagging and changelog

---

## Deliberately out of scope for v1

Listed so the scope stays honest and these do not creep in.

- Password storage of any kind
- Accounts, servers, or any backend
- Analytics or crash reporting, including the anonymous kind
- Browser extensions
- Cross platform (Android, web)
