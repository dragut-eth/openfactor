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

## External audit gates

Auditability is only a claim until somebody outside the project acts on it. These are the
five points where the work stops and gets looked at by someone who did not write it.

They are gates, not suggestions. Each one is marked inline in the plan below, and
`handoff.md` always names the next one, so it survives being picked up months later.

| Gate | After | What gets looked at | Who |
| --- | --- | --- | --- |
| **A1** | PR 4 | The whole of `OpenFactorCore`: Base32, HOTP, TOTP, URI parsing, Keychain storage | Independent model review, plus a public call for eyes |
| **A2** | PR 13 | iCloud Keychain sync, and the sync section of the threat model | Independent model review |
| **A3** | PR 16 | The export format and its cryptography, before any user has a backup in it | Paid professional review if fundable, independent model review otherwise |
| **A4** | PR 17 | The complete threat model against the finished app | Paid professional review or a funded open source audit programme |
| **A5** | Before each release | Diff since the last audited tag | Independent model review, escalating to professional if the diff touches secrets |

### Why these five points

**A1 is the cheapest audit in the project.** The core is about 500 lines, has no user
interface wrapped around it, and nothing depends on its API yet. A finding here costs an
afternoon. The same finding after PR 12 costs a rewrite of everything built on top.

**A3 is the one that cannot be repaired later.** Once a user has an encrypted backup, the
format is permanent: you can add a version 2, but every version 1 archive already exists
and must keep opening. Everything else in this app can be fixed in an update.

**A5 exists because an audit is a snapshot, not a property.** "Audited in 2026" on a
README means nothing about the code shipping two years later. The gate is the diff since
the last audited tag, which keeps the claim honest and the work small.

### What each kind of review means here

- **Independent model review.** The finished diff handed to a model that has not seen the
  reasoning behind it, prompted to attack rather than to approve. Cheap, immediate, and
  worth doing on every gate. Its limitation is that it shares failure modes with the model
  that wrote the code, which is exactly why the writer is never the reviewer.
- **A public call for eyes.** Once the repository is public: an issue tagged for review,
  posted somewhere people who read authenticator code will see it. Free, slow, and the
  quality is whoever happens to turn up.
- **Paid professional review.** A firm that does applied cryptography and mobile work.
  Realistically several thousand to several tens of thousands, which is the honest reason
  it is scoped to A3 and A4 rather than every gate.
- **Funded open source audit programmes.** Several organisations fund security audits for
  open source tools, particularly ones with a privacy or safety rationale. Worth applying
  to well before A4, since the lead times are long. Verify current programmes and terms at
  the time rather than trusting a list written here.

### Rules for a gate

1. No code merges past a gate while its findings are open. A gate that can be waived is a
   code comment, not a gate.
2. Findings are recorded in the open, in `SECURITY.md` or a linked advisory, including the
   ones that turned out to be nothing. An audit trail with only good news is not evidence.
3. The audited commit is tagged, so a reader can see exactly what was reviewed rather than
   inferring it from a date.
4. If a gate is skipped, the reason goes in `handoff.md` and in the README, where users
   can see it. Skipping quietly is the failure mode this whole section exists to prevent.

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
- Metadata (issuer, label, color, sort index) kept out of the path that draws the list, so
  the UI never pages in secret material. Delivered as one Keychain item per account with
  the separation enforced by the query rather than by two separate stores, which also
  encrypts the metadata. Reasoning in `docs/ARCHITECTURE.md`
- Tests against a real Keychain in a host app test target

**Done when:** a secret can be written, read, listed, and deleted, and the accessibility
attributes are asserted in tests rather than assumed.

---

## Gate A1: audit the core

**Stop here.** `OpenFactorCore` is complete and nothing is built on it yet, which makes
this the cheapest possible moment to find something wrong with it.

- Independent review of the full package by a model that did not write it, prompted to
  find flaws rather than to confirm the design
- Run `/security-review` on the accumulated diff
- Every RFC vector table re-checked against the published documents by hand, not against
  what the tests assert. A transcription error in a vector table makes the whole suite
  agree with itself and with nothing else
- Fuzz the `otpauth://` parser and the Base32 decoder. Neither may crash, hang, or return
  a partially populated account on any input
- Confirm no secret material reaches a log, an error message, or a description
- Tag the audited commit and record findings

**Ran 2026-08-14. Fully closed**, findings in `docs/audits/A1.md`, audited commit tagged
`audit-a1`. Two defects found and fixed, fuzzing added permanently, and the one item that
could not close at the time, the Keychain protection class, was verified at the start of
PR 5 as planned.

---

## Phase 2: iOS app

Screens and behavior are specified in `docs/UI_SPEC.md`, derived from the Step Two
reference screenshots. Feature parity is the goal, with the adaptations listed there.

### PR 5: Xcode project and app shell

**Goal:** something that launches.

- **First job: a host application test target,** so the Keychain tests written in PR 4 can
  finally run. They are the last open item on gate A1 and nothing else in this PR matters
  until they pass
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

#### Gate A2: audit sync

**Stop here.** This is the only feature that lets secret material leave the device, so the
claims made about it in the interface and in `SECURITY.md` have to be true rather than
reassuring.

- Independent review of the sync code and of the sync section of the threat model
- Verify against Apple's current documentation that the guarantees claimed for iCloud
  Keychain are the guarantees it actually gives, rather than what this repository asserts
- Confirm the merge path cannot duplicate, drop, or cross wire an account
- Tag and record findings

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

#### Gate A3: audit the export format

**Stop here, and stop hardest here.** Every other mistake in this project is fixable in an
update. This one is not: the moment a user has an archive, the format is permanent, since
a version 2 can be added but every version 1 archive still has to open.

- Review of the format before the code is written, not after. The document is the artefact
  under audit
- Paid professional review if it can be funded, since this is applied cryptography and the
  failure mode is every secret at once
- Independent model review regardless
- Verify the format can be decrypted by an independent implementation written only from
  `docs/BACKUP_FORMAT.md`, which is the real test of whether the document is complete
- Tag and record findings

**No user facing build ships export until this gate closes.**

### PR 17: Security review and threat model

- Complete `SECURITY.md`: attacker with the unlocked device, the locked device, the iCloud
  account, the App Store binary, or a malicious dependency
- Pasteboard, screenshot, and background snapshot behavior audited
- Confirmation in writing that the binary makes no network calls, with the check automated
  in CI if practical

#### Gate A4: audit the finished app

**Stop here.** Everything above is built. This is the last point where a finding can
change the app before strangers depend on it.

- Paid professional review, or a funded open source audit programme. Apply early, the lead
  times are months rather than weeks
- The whole threat model tested against the built app rather than against the source
- Every claim in `README.md` and `SECURITY.md` verified, particularly "makes no network
  requests" and "nothing is stored online". A false claim in a security README is worse
  than no README
- Findings published, including the ones that came to nothing
- Tag the audited commit. This is the tag every later diff is measured against

### PR 18: Release preparation

- App Store metadata, privacy nutrition label declaring no data collected
- Reproducible build notes so a third party can verify the shipped binary
- Version tagging and changelog

#### Gate A5: audit the diff, every release after this one

An audit is a snapshot, not a property of the project. "Audited in 2026" says nothing
about the build shipping two years later.

- Every release, review the diff since the last audited tag
- Independent model review if the diff leaves secrets alone, professional review if it
  touches storage, sync, export, or the lock
- `README.md` states which commit was last audited and by whom, so a reader can check
  rather than trust

---

## Deliberately out of scope for v1

Listed so the scope stays honest and these do not creep in.

- Password storage of any kind
- Accounts, servers, or any backend
- Analytics or crash reporting, including the anonymous kind
- Browser extensions
- Cross platform (Android, web)
