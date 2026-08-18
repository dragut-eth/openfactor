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

- Docs (`README.md`, `HANDOFF.md`, and anything else affected) are updated in the same
  PR, never as a follow up.
- No file grows past roughly 300 lines. Split instead.
- Anything in `OpenFactorCore` ships with tests in the same PR.
- Nothing is pushed until Xavier says so.

---

## External audit gates

Auditability is only a claim until somebody outside the project acts on it. These are the
five points where the work stops and gets looked at by someone who did not write it.

They are gates, not suggestions. Each one is marked inline in the plan below, and
`HANDOFF.md` always names the next one, so it survives being picked up months later.

| Gate | After | What gets looked at | Who |
| --- | --- | --- | --- |
| **A1** | PR 4 | The whole of `OpenFactorCore`: Base32, HOTP, TOTP, URI parsing, Keychain storage | Independent model review, plus a public call for eyes |
| **A2** | PR 13 | iCloud Keychain sync, and the sync section of the threat model | Independent model review. **Done**, see `docs/audits/A2.md` |
| **A3** | PR 16 | The export format and its cryptography, before any user has a backup in it | Independent model review. **Done**, four passes: three on the document before the code, in `docs/audits/A3.md` and `A3-grok.md`, then one on the implementation, in `A3-implementation.md`. Not professionally reviewed |
| **A4** | PR 17 | The complete threat model against the finished app | Cold review by three vendors' models, two rounds, published in full. Not professionally reviewed |
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
- **Multi-vendor cold review.** The same thing as above, run by models from different
  vendors rather than one, and run twice: once to find, and once more after the fixes with
  each engine told what changed. Different training is what buys genuinely different
  misses, and the second round is what catches a fix that did not address its finding. This
  is what gate A4 is.
- **Paid professional review.** A firm that does applied cryptography and mobile work. The
  strongest option and the one this project has not used.
- **Funded open source audit programmes.** Several organizations fund security audits for
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
4. If a gate is skipped, the reason goes in `HANDOFF.md` and in the README, where users
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
- `HANDOFF.md`: running state of the project for the next session
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

Screens and behavior are specified in `docs/UI_SPEC.md`.

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

### PR 12: Polish and accessibility pass

**The first moment every screen exists,** which is the earliest polishing is worth doing.
Adjusting spacing and copy before the add flow and the settings sheet are next to the list
means renegotiating all of it once they arrive.

Polish and accessibility are one pull request rather than two because they are the same
work. Dynamic Type at accessibility sizes breaks layouts, so separating them means
adjusting the same spacing and truncation twice.

- Everything accumulated in `docs/POLISH.md`, which is added to as things are noticed
  rather than recalled at the end
- Dynamic Type across every screen, including the accessibility sizes where cards reflow
- VoiceOver labels and order, Reduce Motion, contrast audit against real content
- Copy review: every user facing string read once, in order, as a whole

**Structural observations are not deferred to here.** A wrong token, a layout approach that
will not survive Dynamic Type, or an interaction pattern other screens will copy gets fixed
when it is noticed, because everything built afterward inherits it. Only cosmetic items
wait. Anything touching correctness or security is fixed immediately, wherever we are.

---

## Phase 3: Sync, watch, hardening

### PR 13: iCloud Keychain sync, opt in

- **An explicit shared `keychain-access-groups` entitlement, and a migration of every
  existing secret into it.** Decided here rather than in PR 14 because a Keychain item lives
  in the group it was written to, and introducing a shared group after people have accounts
  is a migration whose failure mode is "my accounts vanished". See `docs/ARCHITECTURE.md`
- A settings toggle that flips items to `kSecAttrSynchronizable`, converting them **in
  place** so that no secret is ever decrypted, held in memory, or exposed to a crash
  between a delete and an add
- Plain language explanation in the UI of exactly what leaves the device and who can read
  it, which is to say Apple cannot, and what it costs, which is the device only protection
  class
- What turning sync **off** means, defined rather than left to fall out of the code:
  accounts stay here, stop being offered to iCloud Keychain, and go back to device only.
  What happens to copies already on another device is not something this app controls, so
  it does not claim it either way. See `SECURITY.md`
- Conflict and duplicate handling on merge, **documented rather than solved**: the same
  service enrolled twice is two accounts, a rename is last writer wins, a delete
  propagates. A resolution layer was rejected because it would mean a second source of
  truth about which accounts exist. See `docs/ARCHITECTURE.md`
- `SECURITY.md` updated with the sync threat model, including that the watch becomes a
  device holding secrets

#### Gate A2: audit sync

**Stop here.** This is the only feature that lets secret material leave the device, so the
claims made about it in the interface and in `SECURITY.md` have to be true rather than
reassuring.

- Independent review of the sync code and of the sync section of the threat model
- Verify against Apple's current documentation that the guarantees claimed for iCloud
  Keychain are the guarantees it actually gives, rather than what this repository asserts
- Confirm the merge behavior described in `docs/ARCHITECTURE.md` is what actually
  happens, rather than what this repository assumes, and that nothing can cross wire a
  secret onto another account's metadata
- Confirm that turning sync off behaves on a second device the way the interface implies,
  which is the one claim here written from reasoning rather than from observation
- Confirm the device preference and the Keychain cannot disagree in a way that misleads,
  given the app deliberately does not reconcile them at launch
- Tag and record findings

### PR 14: watchOS app

**Read only. No adding, no editing, no deleting, and no copying.** The watch shows the list
and a code, and that is the whole surface. Decided from Xavier's design, and it is a
security property as much as a scope decision: the smallest device with the weakest lock
gets the fewest capabilities.

- Watch target reading the same synchronizable Keychain items from the shared access group,
  rather than shuttling secrets over WatchConnectivity, which would be a second transport
  for secret material to leak through
- **It must work with the phone off, absent, or out of range.** That is what rules out the
  alternative where the watch holds nothing and asks the phone for each code
- List: near black rows, issuer in the account's color, account name in white beneath.
  Not a resized phone card. The palette inverts, so the vivid variants that fail as a card
  background under white text are the right values for colored text on black
- Code screen: code large at the top, countdown ring beside it, issuer and name beneath,
  back to the list. Nothing else
- **Complications need deciding rather than assuming.** One showing a live code puts a
  second factor on a watch face readable by anyone glancing at a wrist, which is against
  the spirit of the rest of this. One that only launches the app is harmless

#### A note for anyone verifying the complication

**A watchOS complication cannot be verified from a Debug build installed with `devicectl`.** The
extension carries `OpenFactorComplication.debug.dylib` and `__preview.dylib` in Debug, and a
widget extension launched by the system rather than by Xcode cannot use that indirection, so
watchOS draws its placeholder: an octagon with an exclamation mark, whatever the code says.
Confirmed on 2026-08-18, when build 5 through TestFlight rendered the mark correctly and at the
right size after four rounds of diagnosis had chased the drawn mark and then a missing app icon.
The complication needs no icon of its own: extensions do not carry one on watchOS, the picker
uses the containing app's, and this one draws its mark in SwiftUI shapes with no image asset at
all.


### PR 15: App lock

**App Lock ships off by default.** An independent review argued for on by default, and the
argument is real: a borrowed unlocked phone is exactly the case the lock defends, and a
default nobody changes protects nobody. It stays off for two reasons. Everything in this app
is opted into rather than imposed, and the app switcher cover, which is the leak that
affected every user, is already unconditional. Xavier's additional reason is the one that
settles it: managed deployment may later need to *enforce* the lock through a configuration
profile, and a feature whose default the user chose is a cleaner thing to override than one
that was always on.

- Face ID, Touch ID, and passcode fallback on launch and on return from background
- Codes blurred until authenticated
- Configurable grace period

### PR 15b: App Lock resumes where you left

**Reopened after the vault made the lock destructive in practice.** The shipped lock swaps
the root view, which destroys everything beneath it, and the vault added screens people
type secrets and passphrases into. Four losses were found in the field in one day, all the
same cause. A first attempt at the fix was built without a design, shipped three defects,
regressed the app switcher snapshot, and was reverted the same day.

The design is `docs/APP_LOCK.md`, written after that failure and normative: a lock window
above an untouched view tree for locks on return, the root swap kept for cold launches
where nothing exists to preserve, a pure tested decision core with the first attempt's
three defects as required regression tests, and one rule for arrivals, they close what is
open and present clean. Status: **complete on `pr-15b-app-lock`, ten of ten
on hardware.** Xavier reviewed the specification, the decision core went in first with the
required sequences as tests, the glue followed, and the checklist passed. One finding is
accepted rather than fixed and documented in full: a second iOS snapshot cache, the one
behind the home screen zoom, briefly shows the previous screen and is not reachable from
the app. The switcher card stays blank.

### PR 16: Encrypted export and import

*Done and merged. The format document is `docs/BACKUP_FORMAT.md`, the audits are
`docs/audits/A3.md`, `A3-grok.md` and `A3-implementation.md`.*

**The format is written and audited before the code.** `docs/BACKUP_FORMAT.md` exists as of
this PR and is the artefact gate A3 reviews. It carries a test vector produced by three
implementations sharing no code, which is what makes "decryptable without this app" a tested
claim rather than an intention.

- Export as an encrypted archive: PBKDF2-HMAC-SHA256 at 600,000 iterations, AES-256-GCM,
  JSON envelope. PBKDF2 rather than Argon2id **on purpose**, because universal availability
  is what makes an archive recoverable by a stranger's implementation, and because the
  generated passphrase, not the KDF, is where the strength actually lives
- **The app generates the passphrase**, 120 bits in Base32 groups, with the user's own as
  the fallback. Base32 because that alphabet was designed to be transcribed by hand
- Export gated behind Face ID or the passcode, since producing a file containing every
  secret is categorically different from reading one code. Import is not gated: it reveals
  nothing
- Import of the same format, plus **Aegis plain JSON** and **labeled text or RTF exports**
  (the shape Step Two writes, matched by its labels rather than by its name), and
  export as Aegis plain JSON
- **The plain `otpauth://` export was dropped.** Aegis JSON is a better escape hatch, since
  other apps actually import it, and a second plaintext path is a second thing to warn
  about and get wrong
- Aegis **encrypted** vaults are refused by name, not silently: they use scrypt, which this
  project cannot provide without a dependency. The message says to export unencrypted
- Duplicates are matched on **secret**, not on name, because a re-enrolment produces a
  genuinely different secret. But the secret alone is not the account: the same secret with
  a different algorithm, digit count, period, type or counter is a different authenticator
  and would generate different codes. An exact match is skipped silently; a secret that
  matches while any code affecting parameter differs is surfaced in the import preview as a
  conflict, for the user to resolve. Raised by an independent review after the rule was
  first settled as secret alone
- An import preview before anything is written: how many found, how many will import, which
  will not and why. Built here, and it is also what PR 16a needs for forty accounts at once
- **Erase all accounts**, in the app, behind Face ID and a typed confirmation. Deleting the
  app does not clear the Keychain, and with sync on anything cleared returns, so without
  this there is no way to start over. It says plainly that erasing removes the accounts from
  synced devices too. **Built first**, because testing an import twice is impossible without
  it

### PR 16a: Import from Google Authenticator

*Done. Verified against a real export: eight accounts, no refusals.*

**One decision changed during the build.** The plan below says to collect the parts of a
multi code export and say which are missing. That is not what was built, because each code
carries whole accounts rather than fragments and the import preview's duplicate detection
already does the work: scan the second code after the first and the new accounts arrive
while the ones already there are skipped. Three passes reach the same place one collected
pass would have, and nothing holds secrets in memory between scans. What was kept is the
sentence, since the field is parsed anyway: that was part 1 of 3, scan the others.

Split from PR 16 rather than folded into it, because it is a second binary parser rather
than more of the same format, and mixing the two would make both harder to review. Do it
after PR 16, or before, but not inside it.

**The argument for it is the argument the project already makes about export.** An
authenticator you cannot leave is a trap, and that applies just as much to arriving.
Google Authenticator is where most people would be arriving from, and today its export is
rejected as "not a setup code", which is true and useless at exactly the wrong moment.

The format, per [Alex Bakker's write up](https://alexbakker.me/post/parsing-google-auth-export-qr-code.html):
`otpauth-migration://offline?data=` followed by base64 protobuf. A `MigrationPayload` holds
repeated `OtpParameters` (secret, name, issuer, algorithm, digits, type, counter) plus
`version`, `batch_size`, `batch_index`, and `batch_id`.

- **No dependency.** The schema uses only varints and length delimited fields, so a minimal
  reader is roughly 150 lines. Adding SwiftProtobuf to save that would break the rule that
  every dependency is code a user has to trust without choosing to
- **Treat it as hostile input.** This is a second binary parser fed by a camera, which is a
  wider attack surface than the URI parser. Bounds checked throughout, no allocation sized
  by an attacker supplied length, and added to the existing fuzzing suite in the same pull
  request
- **Batches.** A large export spans several QR codes. Collect them, track `batch_index`
  against `batch_size`, refuse codes carrying a different `batch_id`, and say plainly which
  ones are still missing
- **Their enumerations are not ours.** They permit MD5, which this app deliberately does not
  implement, and their digit count is only 6 or 8. Refuse those accounts by name rather than
  guessing or silently mangling them
- **Bulk confirmation.** Adding forty accounts at once is a different problem from adding
  one, and the scan confirmation screen does not answer it
- Recognize the `otpauth-migration` scheme even before it is supported, so the error names
  what the code actually is rather than saying it is not a setup code
- The import preview from PR 16 is a prerequisite, not a nicety: forty accounts arriving at
  once is the case it was designed for

#### Gate A3: audit the export format

**Stop here, and stop hardest here.** Every other mistake in this project is fixable in an
update. This one is not: the moment a user has an archive, the format is permanent, since
a version 2 can be added but every version 1 archive still has to open.

- Review of the format before the code is written, not after. The document is the artefact
  under audit
- Paid professional review would suit this gate, since it is applied cryptography and the
  failure mode is every secret at once. Not used
- Independent model review regardless
- Verify the format can be decrypted by an independent implementation written only from
  `docs/BACKUP_FORMAT.md`, which is the real test of whether the document is complete
- Tag and record findings

**No user facing build ships export until this gate closes.**

### PR 16b: Steam Guard

Parked, and small in core: the same HMAC over the same time counter, the same dynamic
truncation, then five characters out of a 26 character alphabet instead of `mod 10^digits`.
About twenty lines.

The cost is the ripple, and it is why this is its own pull request rather than a rider.
`OTPGenerator` gains a case, which touches the stored metadata encoding, the card, manual
setup, the watch, and the `otpauth://` reader. Codes stop being digits, so `CodeFormatting`
and the monospaced digit styling need a second shape. Aegis exports these with
`type: "steam"`, which is currently refused by name, so the importer and one of its tests
change. And `docs/BACKUP_FORMAT.md` needs a `steam` type documented, which its own rules
bless as additive, but which is still an edit to a normative document that has been reviewed
four times.

Yandex, Mobile-OTP and Blizzard are **not** planned. Yandex needs a PIN mixed into the key,
motp is MD5, and Blizzard has no `otpauth://` representation to import from at all.

### PR 16c: A share extension, so a QR never has to rest in Photos

**The problem, stated precisely.** A transfer QR is every secret its owner has, in the
clear, in one image. When one arrives by Messages, Mail, AirDrop or Files, the only route
into OpenFactor without this is to save it to Photos first.

**Photos is a persistent store, and calling this "a step saved" understates it.** With iCloud
Photos enabled the image can be synced through iCloud to the owner's other devices and made
accessible from iCloud.com, and deleting it retains it in Recently Deleted for up to 30 days.

So the choice is not between two equivalent places to keep a file. It is between a durable item
in a synchronized library, holding what may be every OTP secret in the vault, and a transient
item in a container. That is what pays for a new signed target, a new entitlement, and the audit
surface named below.

**What it does not fix, said up front.** An image already in Photos stays there. The
ordinary case, pointing the camera at another phone's screen, never creates a file at all
and is unaffected. And the image still passes through the sending app's own storage; this
removes the *additional* copy, not every copy.

#### The design, which is mostly about what the extension is not allowed to do

- **No Keychain entitlement on the extension.** The same rule the watch complication
  follows, and for the same reason: the absence of the entitlement is the security property,
  not a promise in a comment. The extension cannot read an account and cannot write one.
- **The extension does not parse.** It does not decode the QR, does not read protobuf, does
  not touch `otpauth-migration`. All of that stays in the app, in one place, already fuzzed.
  A second process parsing hostile input is a second attack surface for no gain.
- **What it actually does:** writes the received image into a dedicated `Inbox` directory in
  a shared app group container, with the strongest file protection class. Nothing else leaves
  the extension.
- **A URL may carry a name, never a payload.** The original design handed the app an opaque
  item UUID as `openfactor://inbox?item=<uuid>`, on the rule that a URL can be logged, appears
  in handoff, and ends up in diagnostic bundles, so it must never carry content. **The rule
  stands and the URL is gone:** a share extension cannot open its containing app, measured
  twice, so the scheme was removed rather than left declared for anything on the device to
  send. The app collects from the inbox itself instead.
- **The app reads it once and deletes it**, then sweeps the whole directory at launch, which
  is the same lifecycle the export file already has and can reuse.
- **No queued or persistent handling.** The interactive path only; nothing that would leave the
  image sitting somewhere waiting to be delivered.

**Why the shared container is acceptable when Photos is not**, corrected after gate E1. The
original justification said the container is "app private". **It is not**, and that is exactly
the claim E1 demolished about Keychain access groups: an App Group is a grant the account holder
controls, not a boundary, so a sibling app can be authorized into it. `docs/VAULT.md` records it
as a grant for that reason.

**The shared App Group container is therefore not treated as a confidentiality boundary.** A
sibling app explicitly authorized into that App Group could read the temporary inbox item. That
is an accepted exposure, and these are the reasons it is accepted: the image exists there only
during an explicit share operation, uses complete file protection, is never synced by OpenFactor,
contains no OpenFactor key material, and is deleted immediately after the containing app consumes
it. Any leftovers are swept when OpenFactor launches.

**Photos creates a different exposure.** When iCloud Photos is enabled, the image can become part
of the user's persistent synchronized photo library, accessible across their devices and through
iCloud.com, and deletion retains it in Recently Deleted for up to 30 days. The comparison is
between a transient item in a container and a durable item in a synchronized store.

#### Recognized as a handler for scanned codes

**Declaring `otpauth` and `otpauth-migration` is what makes iOS offer OpenFactor** when the
Camera app or Photos finds one of them in a QR code. Without it, a setup code scanned outside
this app has no route in except retyping it.

Both go to the add screen, which already tells a single account from a transfer because the
payload names its own format. Nothing is saved without the confirm screen, which is what makes
accepting an incoming URL defensible at all.

**Two costs, stated rather than buried.** A declared scheme is an entry point every app on the
device can use. And an `otpauth://` URL carries the secret in the clear, so accepting the scheme
means the secret passes through the system rather than staying inside this process as it does
when this app's own camera decodes the frame. That is unavoidable if the scheme is supported,
and it is why OpenFactor declares the two standard schemes and none of its own: the `openfactor`
scheme was removed once nothing could produce it, and must not return through this door.

#### The cheaper half, worth doing in the same pull request

**Document types**, which need no extension and no new process at all. Declaring an exported
type for `.openfactor` and accepting Aegis JSON means an archive can be opened straight from
Files or from a mail attachment with "Open in OpenFactor", rather than going through the
in-app picker. Info.plist only.

**Status: built.** Both halves. Document types and the exported `.openfactor` identifier let a
backup open from Files or Mail; `SharedInbox` in the core is the container; `OpenFactorShare` is
the extension; and `InboxOpener` turns either arrival into the one import screen that parses
anything. CI asserts the extension is embedded and that its entitlements contain the app group
and nothing else.

**Exercised on hardware, and one assumption died.** A share extension **cannot** open its
containing app. `extensionContext.open` was refused from the completion handler of
`completeRequest` and refused again from a live button. So the extension shows one screen saying
the image is ready, and the app collects for itself whenever it comes forward, taking the newest
item and sweeping the rest. The responder chain workaround was rejected on principle.

Shipped to TestFlight as 1.0 (3). Apple's upload check then pointed out that declaring document
types without answering `LSSupportsOpeningDocumentsInPlace` is incomplete; it is `NO` now, so
files arrive as copies and the app never holds write access to somebody else's document.

#### Two risks to name before starting

**Touching entitlements is how sync broke before.** Adding an app group sits beside the
Keychain access group that PR 13 got wrong and PR 14 spent a migration fixing. They are
different entitlements and should not interfere, but "should not" is exactly the phrase that
preceded the last one. The access group tests exist and must stay green, and it is worth
checking the watch on hardware afterwards rather than assuming.

**A new signed target is new audit surface.** Gate A4 has to cover it, and PR 18's
reproducible build notes gain another binary to account for.

### PR 16d: The vault

**Storage stops being plaintext in a shared Keychain group.** Gate E1 measured that access
groups are not a boundary between apps of one team, so accounts are encrypted with a key kept
in the app's private container, which is a boundary. The design is `docs/VAULT.md`, written
before the code and audited before the code, as the backup format was.

- The passphrase, PBKDF2 and AES-GCM come from the archive and are already audited four times.
  This is one new layer, not a new subsystem
- Six assumptions must be settled by probe before implementation, including whether a sibling
  app can reach another app's container at all. That belief has the same shape as the one E1
  destroyed
- The watch is handed the key once over WatchConnectivity and never needs the phone again
- Not a fix for a malicious update, which reads its own container. That is answered by
  reproducible builds in PR 18, not by cryptography

**Status: the iPhone half is built.** `Sources/OpenFactorCore/Vault/` holds the record format,
the wrapped key, the key file and `Vault`. `KeychainSecretStore` is converted: it seals on write,
opens only the metadata half to list, and opens the secret half only in `secret(for:)`. Six of
the seven probes are settled; the two-writer rewrap case is blocked on a second development
device. `OpenFactor/Vault/` holds the gate and its three screens, specified in
`docs/UI_SPEC.md`.

**The watch exchange is built too.** `WatchProvisioning` carries gate E7's negative controls as
tests, the watch has a gate of its own in front of the list, and the phone asks before it
answers. The six digit comparison was removed, because it could not do what the design claimed;
`docs/VAULT.md` records what that costs, which is that routing exclusivity is now load bearing.
The watch's third empty state turned out not to be needed: the gate stands in front of the list,
so "no accounts yet" keeps its old meaning.

**What remains in this pull request:**

- **Done: the failure paths of the exchange on hardware.** The successful path, a declined
  request, and a phone with no vault of its own have all now run between a real phone and a real
  watch. Declining shows "Not set up", and a phone whose key has been dropped answers by itself
  without raising an alert, which is what it should do: there is no key to offer and so nothing
  to ask about. Both were reachable without destroying anything, because the Debug row that
  drops the phone's key keeps the accounts and the passphrase brings it back. Recovery ran in the
  same session and is the more important half: the passphrase restored the key, and a watch that
  had just been refused twice was then provisioned successfully with no reset and no reinstall,
  so a refusal is not a dead end
- **Done: a second model reviewed the exchange.** Run cold by Xavier on a fresh model with no
  context, which is what the shared blind spot argument asks for. It found no fault in the
  cryptography and four real defects around it: two races in the watch's asking flow that no test
  could reach while that logic lived in the watch target, a request substitution against the
  phone's own alert, malformed bytes reaching the vault key and the human prompt before being
  parsed, and a discarded `SecRandomCopyBytes` result that would have shipped a predictable nonce
  on failure. All fixed, with the two races extracted into `WatchProvisioningFlow` in the core and
  proved to fail there before the fix was kept
- **The tripwire is deliberately not being built yet.** Its container anchor has an unsolved
  staleness problem once several devices are writing, and E6 made it worse by measuring the
  container path changing on update. A tripwire that cries wolf is worse than none

### PR 17: Security review and threat model

- Done: `SECURITY.md` completed for all five attackers, with an index at the top of the threat
  model mapping each to the sections that answer it. Every claim was checked against the code
  rather than carried forward, and three were wrong and are corrected in place: that the Watch
  screens were unbuilt, that nothing had been reviewed, and that the app switcher never contains
  a code. Claims now carry their basis, measured, tested, or reasoned, so a reader can tell which
  kind of statement they are reading. Two sections were added, the attacker who has the shipped
  binary and the index; two deferred items were resolved, the context menu limitation preserved
  with its reasoning rather than deferred again, and the zero-dependency claim turned from prose
  into a CI check
- Done: pasteboard, screenshot, and background snapshot behavior audited. The pasteboard
  audit is written up in `SECURITY.md` and changed one decision, codes may now travel through
  Universal Clipboard while passphrases may not, with all three behaviours measured on hardware
  against a positive control. Screenshots cannot be prevented on iOS and are not detected here,
  deliberately: detection buys nothing actionable once the image exists. Snapshots were settled
  in PR 15b, including the limitation `docs/APP_LOCK.md` records. That deferred decision is now closed, and the
  reasoning changed while making it: the exposure is not only the code but the account list,
  which does not expire. Capture blanking is built for codes and passphrases, screenshots on the
  passphrase screens raise a warning naming Photos and Recently Deleted, and the secure-text-field
  trick that would block screenshots outright was rejected for failing silently. All three
  measured on hardware, including the negative control that the warning stays quiet on the list
- Done: confirmation in writing that the binary makes no network calls, with the check
  automated in CI. The `binary` job builds Release unsigned, sweeps every Mach-O in the
  bundle, and fails on any networking framework or symbol; proved in both directions,
  including against a build that called `URLSession`, which the first draft of the pattern
  missed. `SECURITY.md` records what the check can and cannot claim

#### Gate A4: cold review by three engines

**Stop here.** Everything above is built. This is the last point where a finding can
change the app before strangers depend on it.

The gate is met by independent passes from three frontier models, each from a different vendor,
each given the code cold. Findings are digested and fixed, then every engine runs again knowing
what changed.

**The three engines: Fable 5, Grok 4.6, and ChatGPT 5.6 Sol.** Three vendors rather than three
prompts to one, because the point is not volume. Two models trained by the same lab share the
blind spot that matters most, the one nobody in the room knows they have. Different training
gives genuinely different things missed.

**Cold means cold.** Each is given the repository and a scope, with no conversation history, no
summary of what was already believed to be safe, and no account of what previous reviewers found.
The prompts are written from the code rather than from the design's own claims, so a model is not
being asked to agree.

##### Round one, finding

Scoped rather than "audit this app", because a model asked to review everything returns a
plausible survey of nothing. One pass per area, per engine:

- The vault: record format, key wrapping, the key file, and what a device holds at rest
- The Watch key exchange, which already had one cold review and gets another from two more
- Import and export: the backup format, the three importers, and everything that parses bytes
  somebody else wrote
- The app's own boundaries: the share extension, URL schemes, the lock, and the clipboard

Every finding is triaged rather than accepted. A finding that survives inspection is fixed; one
that does not is recorded with the reason it was rejected, because a review's false positives
say as much about the method as its hits.

##### Round two, verifying

The same three engines, the same scopes, now told exactly what changed and why. This is the
round that catches the two things a single pass cannot: a fix that does not actually address the
finding, and a fix that introduced something new. A model that accepts its own finding as
resolved without checking is itself a finding about the method.

##### Publication

Each pass is published in `docs/audits/`, whole: what was asked, what came back, what was fixed,
what was rejected and why. Including the passes that found nothing, and including the findings
that dissolved on inspection. A review that came to nothing is evidence.

##### The closing opinion

Each engine is asked, last, for a short comprehensive opinion of ten to fifteen sentences, written
for somebody deciding whether to trust the app. Those go in `README.md`, published whole and
attributed to the engine that wrote them, unflattering parts included. If an opinion is bland,
that is a fact about it worth publishing rather than a reason to re-ask until it improves.

**The question is framed so that praise is not the easy answer.** Each is asked what it would
warn a security-conscious friend about, and what it would not trust this app with, rather than
for a general impression.

##### What this is and is not

**It is not a professional audit and `README.md` must not imply one.** The honest description is
independent review by three models from three vendors, published in full, with no commissioned
human audit.

Three limits, stated rather than left for a reader to discover:

- **The prompts are still written here.** That is the residual dependence no amount of vendor
  diversity removes, which is why every prompt is published with its pass. A reader can then
  judge whether the questions were leading.
- **A model reads code and cannot run the app.** It finds nothing about behavior on hardware, so
  the platform assumptions stay where they are: gate E1 on Keychain access groups, the vault key
  file through a restore and Quick Start, and WatchConnectivity routing exclusivity all remain
  measured by hand or not at all.
- **Agreement is not proof.** Three engines missing the same thing is likelier than three
  independent humans missing it, and less likely than one. It narrows the gap; it does not close
  it.

**Done means a full round where no engine reports a new finding that survives triage.** Not a
fixed number of rounds.

##### Then tag it

Tag the reviewed commit, with a name that says what it was rather than implying more. This is the
reference Gate A5 measures every later diff against.

#### An open question this raised, not yet answered

**People screenshot the vault passphrase because the app tells them it is shown once and never
again.** The warning treats the symptom. Whether the constraint itself has to be that absolute is
a question for `docs/VAULT.md` rather than for the interface: if a passphrase could be shown
again under authentication while the vault is open, most of the pressure to photograph it would
go away. Not investigated, and it should be read from the design rationale rather than guessed at.

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
