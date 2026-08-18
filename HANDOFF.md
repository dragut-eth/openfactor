# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

## Where things stand

**Last updated:** 2026-08-17, on TestFlight as `dev.openfactor.app`, 1.0 (4). The day's
work and the PR 15b specification are committed on `pr-15b-app-lock`, not pushed.

**PR 15b is implemented, and the next action is the checklist in `docs/APP_LOCK.md`.**
Xavier reviewed the specification in the morning and said go. The build order was the
spec's own: `AppLockPresentation`, a pure value type wrapping the untouched `AppLockEngine`,
went in first with the required sequences as thirteen passing tests, the first attempt's
black flash and snapshot leak among them by name. Then the glue: `PrivacyShield` now owns
both windows and applies the core's three outputs in the one safe order, shows before
hides, with the lock window built once at `.alert + 2` and the auto prompt driven on the
transition to visible. Cold launches still lock as the root, exactly as PR 15 shipped.
The arrival rule lives in `AccountListView`: an arrival closes every open sheet and
withholds its own until the closing sheet's `onDisappear`, because presenting during
another sheet's dismissal is a request SwiftUI silently drops, which is what broke
share-mid-flow in the first attempt. Ten scenarios in the specification are the one
manual pass that remains; nothing merges before they run on hardware.

**The adversarial review paid for itself before the build reached a phone.** A second
model, asked only whether any event sequence leaves the interface photographable while
unlocked, brute-forced the core's state space and found one: an unlock landing after the
app has already reached the background, a biometric match racing a swipe home, suppressed
the cover through the looser `settling` condition and actively tore the lock window down
with nothing behind it. One line fixed it, `settling` keyed on inactive rather than not
active, a second outcome made inert, and the sequence is now test ten in the suite and in
the specification. Yesterday this class of defect shipped to hardware three times; today
it did not ship at all.

**Also in the day, committed on the same branch:** the Photos and App Group claims narrowed
to what is defensible, at Xavier's direction. The `otpauth` and `otpauth-migration` schemes
declared, routed to the add screen, bounded at eight kilobytes, everything else refused.
The complication's octagon diagnosed as a missing icon, not the drawn mark; icon added,
verification waiting on the next TestFlight build by Xavier's decision. Two rounds went to
the mark before the missing icon was seen, and the finding was in output already printed:
the target had no `ASSETCATALOG_COMPILER_APPICON_NAME` and no asset catalog.

**The storage is being redesigned, and the reason is measured rather than argued.** Gate E1
proved on hardware that a second app signed by the same team reads another app's Keychain
items, including the default group Apple's documentation calls private. Access groups are not a
boundary; the sandboxed container is. `docs/VAULT.md` is the design that follows, encrypting
accounts and keeping the key where no entitlement can reach it. It went through one cold audit
round recorded in `docs/audits/V1.md`, twelve findings, five blocking, three of them data loss,
and then an external round recorded in the `V2-*.md` files.

**PR 16d is implementing it, and the phone now works end to end.** `Sources/OpenFactorCore/Vault/`
holds the record format, the wrapped key, the key file, and `Vault` itself. `KeychainSecretStore`
is converted: it seals on write, opens only the metadata half to list, and opens the secret half
only in `secret(for:)`. `OpenFactor/Vault/` holds the two screens, and `VaultGateView` now stands
between the app lock and the account list so the list is never drawn while the key is missing.
Creating a vault, showing the passphrase once, and unlocking a second device with it all work and
are covered by tests.

**The setup screen's copy was rewritten after Xavier read it on hardware.** He asked whether the
screen appears because his iCloud sync is on. It does not, and the question was the bug report:
sync is off by default, so the first person to see that screen always has it off, and the text
was written as though it were on. `VAULT.md` records what changed and why. The lesson is not
about wording. Two of the sentences were false only in the configuration nobody had looked at,
and both read perfectly well in the one everybody had.

**The screens went through a design pass on hardware, and it produced rules rather than tweaks.**
One prominent button now exists in one place, `PrimaryAction.swift`, used by both the empty
list's "Add an account" and the vault's "Create my vault"; it was a fixed 260pt frame, which
sizes a button to a number instead of to its words, and is padding now. The exported file is
called a **backup** everywhere a person can read it, matching `openfactor.backup.v1` and
`BACKUP_FORMAT.md`, where the interface had been saying "archive". Fields that take a
machine-generated string are monospaced and fields that take a word are not, which added it to
import and removed it from the ERASE confirmation. Spelling is US English throughout the app and
the living docs; `docs/audits/` is left alone, because those are records of what reviewers wrote.

**A caution for the next interface pass.** Simulator taps are silently dropped below the vertical
midpoint of the screen. A button at 417pt works and the same kind of button at 434pt does nothing,
on an 874pt screen, which reads exactly like a dead control and cost half an hour chasing a
binding that was never broken. Screenshots are reliable; injected touches are not. Anything a
screen owes belongs in a view model test, which is where `VaultGateModelTests` lives.

**The watch exchange is built, and building it found a flaw in the design it implements.**
`SECURITY.md` and `VAULT.md` both said the person compares a six digit string on both screens
*before the phone releases the key*. They could not: the watch derives its string from the
transcript, which contains the phone's public key, and that public key arrived in the same
message as the sealed key. At the moment of confirming, the genuine watch had nothing to display.
The comparison was only ever after the fact.

Xavier chose the simpler resolution rather than a third message: no comparison at all, one
confirmation on the phone, and both documents rewritten to say the cost out loud, which is that
**routing exclusivity is load bearing now** and Apple does not document it as a guarantee. The
alternative was a digit comparison performed on a wrist, which is a step people tap through.

`WatchProvisioning` keeps E7's negative controls as tests rather than as a one-off experiment,
because two halves of one implementation agree with each other whether or not the binding is
real.

**The exchange has now run between a real phone and a real watch**, successfully, which closes
the gap three documents were carrying. Only the successful path; declining and a phone with no
vault of its own have not been tried on hardware.

**Testing it found a hole the design had no word for: a device can hold a key that opens
nothing.** Replacing the vault on the phone leaves the watch with the old key, and every record
that arrives is sealed under the new one. The watch reported zero accounts while fifteen sat in
its Keychain unopened. The signal is now `StoredRecords.suggestsAWrongKey` in the core, with
tests, and both the watch and the phone act on it once and believe the second answer. The phone
needed no new screen: the unlock screen's sentence is true whether a device has no key or the
wrong one.

**Two process failures worth keeping, because both cost real time.** The first diagnosis was
wrong: "forget everything" resets every preference including the sync switch, so accounts
imported afterwards were device-only and never reached the watch at all. Two rounds went into
fixing a stale key that was not yet the problem, because reasoning replaced looking. The second
was worse: the fix marked itself as "already tried" on the attempt rather than on the outcome, so
an attempt nobody completed was enough to make the watch claim the records needed a newer version
of the app, which was frightening and false. A three-line Debug readout of the raw record counts
found both in a minute, and it should have existed before the first fix rather than after the
second.

**PR 16c is built, both halves, and is unpushed on `pr-16c-share-extension`.** Shipped to
TestFlight as 1.0 (3), which is the first build carrying the vault.

**Two bugs from real use, and they were the same bug twice.** App Lock replaces the root view
with the lock screen rather than covering it, so anything owned below it is destroyed. First the
generated vault passphrase: Emmanuel copied his, went to another app to paste it, came back past
the grace period, and was offered a fresh vault, holding a passphrase that opened nothing and
with no way to tell. Then the shared image: collecting it is destructive, so a collection that
ran moments before the lock screen appeared took the image out of the container and was thrown
away with the view that asked for it, and sharing silently did nothing.

**The pattern is worth more than either fix.** Anything the app must not lose belongs above the
lock swap. Both now live on the app, and collecting additionally waits until the app is unlocked
and the vault is open. The next thing added to the account list will be the third instance if
nobody remembers this.

**Also gone: the `openfactor` URL scheme.** Nothing could produce it once the extension turned
out to be unable to open its containing app, while every app on the device could still send one.
Files open through document types, which does not accept arbitrary senders.

**A share extension cannot open its containing app, and that is now measured rather than
assumed.** `extensionContext.open` was refused twice: from the completion handler of
`completeRequest`, where it could be blamed on teardown, and from a live button somebody had just
tapped. So the extension writes the image, says "Ready in OpenFactor", and the app collects for
itself whenever it comes forward. The responder chain trick was considered and rejected: it
reaches for `UIApplication` from a process the sandbox keeps away from it, and this project
cannot answer "how did you launch yourself" with "we went around it".

**One bug in that work is worth remembering because the cause was a name.** `Arrival.data` covered
both a shared image and an opened file, so a shared QR screenshot went into the file importer,
which looked for a backup or a JSON export and reported truthfully that it found no accounts. An
image goes to the add flow, which decodes QR codes; a file goes to the importer, which parses
them. They are `.image` and `.file` now. A backup opens
from Files or Mail through declared document types, and `OpenFactorShare` takes a transfer QR out
of Messages without it ever resting in Photos.

**Xavier corrected the justification twice, and the second correction narrowed the first.** The
roadmap originally called saving to Photos an extra step, which understated it. The replacement
overstated it, asserting that the image would necessarily be replicated everywhere and processed
server-side. What is defensible and now written everywhere: a transfer QR may contain every OTP
secret in the vault, and Photos is a persistent store, so with iCloud Photos enabled the image
can be synced through iCloud to the owner's other devices and reached from iCloud.com, with
deletion retaining it in Recently Deleted for up to 30 days. Avoiding that copy is what pays for
a new signed target.

**The App Group justification was narrowed in the same pass.** It had argued that a sibling
authorized into the group would only learn a QR it could have read from the Messages or Mail
attachment anyway, which assumes something about another app's access to Messages storage that
this project has not established. The security model now states the exposure plainly instead: the
container is not a confidentiality boundary, an authorized sibling could read the inbox item, and
that is accepted because the item is transient, protected, unsynced, free of key material, and
deleted on consumption.

**The extension's security is an absence**, so CI asserts it: its entitlements must contain the
app group and nothing else, checked by parsing the plist rather than grepping it. The grep
version passed while lying, because the comment explaining why the Keychain key is absent
contains the Keychain key. It was then run against a deliberately broken copy to prove it fails.

**What has not been exercised: the extension has never run from a real share sheet.** Opening the
containing app from a share extension is not documented by Apple as supported. The code is
written to be correct when that silently fails, since the app sweeps the inbox at launch, but
whether somebody is actually carried into the app is unmeasured. **That is the first thing to
test.**

**A process note, because it happened twice today.** Two commits went in on top of a failing test
because the commit was chained onto the test run in one command instead of the result being read
first. Neither reached anyone, both were corrected, and the cure is to stop chaining them.

**What is left in PR 16d.** A second model reviewing the exchange,
since one model wrote the design, found its flaw and implemented its own fix. And the tripwire,
which is **not** to be built yet: its container anchor has an unsolved staleness
problem once several devices are churning, and E6 made it worse by showing the container path
changes on update.

**What has no test coverage, stated rather than implied.** The cryptography is covered; the
plumbing is not. `WCSession` is a hard dependency in both `WatchKeyProvider` and
`WatchVaultModel`, so message routing, the status mapping and the phone's alert are verified by
reading them and nothing else.

**One decision was made during the wiring that the design had not covered.** A locked device with
a lost passphrase was a permanent dead end: it cannot open its accounts, cannot reach Settings to
erase them, and does not recover by deleting the app, because the Keychain outlives it and iCloud
returns whatever did clear. The erase flow is now reachable from the locked screen, with its Face
ID and typed word intact, and the vault is destroyed only after the accounts are gone.
`VAULT.md` records it under what the interface owes.

**The external audit round is complete and the design has been revised once, at the end of it.**
ChatGPT, Grok and Fable all approve the central move and all three refused to freeze the page.
Ten further findings, recorded in `docs/audits/V2-chatgpt.md`, `V2-grok.md` and `V2-fable.md`,
all now in `docs/VAULT.md`. They divided almost perfectly: protocol and format precision, then
integration with the code that exists, then semantic errors. None of the three would have been
enough alone.

The three worth knowing without reading the records. The watch exchange was **half a protocol**,
since ECDH needs a private key on both sides. Listing accounts today never loads a secret, a
deliberate property stated in `KeychainSecretStore`'s own header, and the design was **discarding
it without mentioning it**; it is preserved now by sealing each record in two halves under one
key. And **rewrapping is not revocation**: a passphrase change does not rotate the vault key, so
anyone holding an old wrapped item and the old passphrase keeps access forever, which version 1
now states plainly rather than implying otherwise.

**Nothing was implemented until the probes were done.** Seven things had to be proven first, at
the end of `VAULT.md`. **Six are now settled**: E1 the Keychain hole, E4 the container refusing a sibling,
E5 a sibling WatchConnectivity session activating and reaching nothing, E6 the file attributes
sticking and an app update moving the container while preserving the data, and E7 the watch
exchange fitting in 145 bytes against a 65,536 limit with its binding proved by negative
controls, plus the store losing no queryability to an opaque item.

**One remains and it is blocked on hardware.** The two-writer rewrap case needs a second device
signed into the same iCloud account; only the iPhone and the watch are paired for development,
and the watch is a reader under this design. The Vision Pro would serve, with developer mode
enabled and pairing set up. `docs/audits/E7-exchange-and-queryability.md` records what it would
and would not establish, and it matters more after the audit than before, because every account
item is now rewritten on a rename or an HOTP counter rather than only the wrapped key.

**Two probes returned something nobody had asked for.** E5 showed `isPaired` is readable by any
app of any team, so the existence of a watch leaks. E6 showed the container path changes on
update, which means nothing may ever cache it, and the tripwire anchor is the part of the
design most likely to have done so.

**What remains unmeasured, and why.** A rogue watch app claiming to be OpenFactor's counterpart,
which is a day of work and no longer changes the design because of the provisioning code. A
restore and a Quick Start, which need a device wiped or newly configured and are not worth doing
to a personal phone. Offload, which iOS does not offer for development installs at all. The
backup exclusion is therefore verified as a flag and never as a restore, and `VAULT.md` says so
rather than implying the round trip was exercised.

**Everything now reads `dev.openfactor.*`.** The bundle identifiers were renamed because
`com.openfactor.dev` claimed a domain this project does not own, and the Keychain access
group was renamed after them so nothing is left explaining an inconsistency. Both were done
while two people held test data, which is the only reason the group rename was cheap: it
strands every stored account, and after a real release it would have needed a migration.
**The group must never be renamed again**, and `docs/PROJECT.md` says so where somebody
tidying up would find it.

**The app is being tested by someone other than Xavier**, which changes what evidence is
available. Anything about the watch, about iCloud Keychain latency, or about a Google
Authenticator export has until now been proved on one person's devices and one iCloud
account. A second tester is the first chance to separate "it works" from "it works here".

**Uploading no longer needs Xcode.** `scripts/ship-testflight.sh` does the whole cycle. The
credentials it needs are on Xavier's machine and cannot be created by an agent: an App Store
Connect API key authenticates the upload and cannot sign anything, and the distribution
certificate that does the signing is account level and quota limited. The script's header
says which is which, because conflating them is what makes this take an afternoon.

| | |
| --- | --- |
| PR 0 to PR 12 | Done. Core, app, scanning, editing, polish, accessibility |
| PR 13, iCloud Keychain sync | Done |
| Gate A2, audit of sync | Done, twice. Original eleven findings closed except F8 and F13's two device half; three new findings from the re-verification, all fixed |
| PR 14, watchOS app | Feature complete on `pr-14-watch`, re-verified, pushed |
| PR 15, app lock | Built on `pr-15-app-lock`, pushed. Face ID needs a real device |
| PR 16, export and import | **Merged to main.** Format audited three times before the code, then the implementation audited separately: erase, both file importers, the import preview, the encrypted archive reproducing every published test vector value, the export and passphrase screens, and the plain Aegis vault pinned to a fixed revision of their documentation. Five findings from the implementation review, two blocking, all fixed and recorded in `docs/audits/A3-implementation.md` |
| PR 16a, Google Authenticator import | Built on `pr-16a-google-import`. A hand written protobuf reader, the transfer recognized by the + scanner, and the import preview reused unchanged. Verified against a real export from Xavier's phone: eight accounts, no refusals. Parts are rescanned rather than collected, and the finish screen says which part of how many arrived |
| PR 16b, Steam Guard, and PR 16c, a share extension | Both planned in `docs/ROADMAP.md`, neither started. Steam Guard is parked. Small in core, and it ripples into storage, the card, the watch and the backup format's `type` enumeration. 16c stops a transfer QR having to rest in the photo library, and its design is mostly a list of what the extension is forbidden to do |
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

### Gate A3 ran twice, and the second pass found what the first pass's fix broke

Two independent reviews of `docs/BACKUP_FORMAT.md`, Fable then Grok, plus a third from a
model Xavier ran outside the repository. Reports are `docs/audits/A3.md` and
`docs/audits/A3-grok.md`. **All findings from both are fixed.**

The sequence is the lesson. Fable found the test vector had been built by feeding the key
derivation the hyphenated passphrase, contradicting the document's own rule. The fix
specified passphrase entry precisely and recorded the mode in a header field. Grok then
found that the fix was worse than the gap: a mandatory unauthenticated header bit meant one
character edited in a text editor bricks the archive forever, and that "remove Unicode
whitespace" is not one algorithm, since `Character.isWhitespace` and
`CharacterSet.whitespaces` disagree about zero width space and line feed. Verified on this
machine before acting.

The current rule is blunter and has no such seams: **keep the Base32 characters, discard
everything else**, and the mode field is a hint that orders two attempts rather than a gate
that forbids one. Measured against seven ways a real person hands a passphrase back,
including iOS smart punctuation turning hyphens into en dashes, all seven now reach the same
key. Three of them did not before.

The vector grew teeth to match: a second vector for the verbatim path, a table of inputs
that must all succeed, and a list of things that must fail, every item of which was run and
confirmed to fail.

### The earlier state, kept for the record

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
never has to guess which canonicalization produced the key.

The vector was regenerated and re-verified from the *displayed* form through the
canonicalization, by CommonCrypto, Python and Node, so the check now exercises the rule
instead of bypassing it.

**Gate A2's F8 and F13 are closed**, by experiment on real hardware on 2026-08-15. Results
are appended to `docs/audits/A2.md`.

F8 went against this project: turning sync off **does** remove the accounts from other
devices, within fourteen minutes on a paired watch. Apple's documentation was right and ours
was wrong, and the settings footer now states it plainly instead of hedging.

F13 came out clean: no twin, no duplicates, no error. It is closed for one writing device
and one reader; two writing devices, and the rename and delete propagation steps, still need
an iPad or a second iPhone.

The experiment also found a defect nobody predicted: the watch's empty state told the wearer
to wait for accounts that, with sync off, were never coming. Both causes are now named. It
was invisible to review and to testing, and appeared only from standing in the state.

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
apologized for; the app generates the passphrase; the plain `otpauth://` export is dropped
in favor of Aegis JSON; export is gated on Face ID and import is not; duplicates skip on
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

**A document that survives three reviews says nothing about the code under it.** Gate A3
reviewed the backup format three times before a line of it existed, which is the right order
and leaves an obvious hole. The published test vector closes part of it: it proves this
implementation reaches the same bytes as three others. It cannot see a nonce reused between
two exports, a file that outlives its screen, or an acknowledgement referring to a passphrase
that no longer exists. Reviewing the implementation separately, by a different model, found
five of those, two of them blocking. Neither was reachable from the vector.

**Some settings are only wrong in distribution.** The watch app was a sibling target of the
iOS app rather than an embedded one, from PR 14 until a TestFlight build said "Apple Watch:
No". Nothing local could have caught it: the project built, every test passed, and running
from Xcode installed the watch app onto a paired watch exactly as expected, because Xcode
installs each target it builds. Only a distributed build cares, because that is the only
path where the watch app has to ride inside the phone app's bundle. It is asserted in CI
now. When a setting only matters to the App Store, the local evidence is not evidence.

**A comment can be the bug.** The labeled text reader defaulted sha1, 6 and 30 when a
label was absent, under a comment claiming it did the opposite. Both audits read the comment
and moved on. An absent label in a human readable report means the parse failed, not that
the writer meant the default, so the reader now refuses and names the setting it could not
find. Aegis defaults on purpose, and says why in the same words, because the two look
inconsistent side by side.

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
  Import/ImportResult.swift                What a reader returns: accounts and refusals
  Import/LabelledTextImport.swift          Text or RTF listing accounts under English
                                           labels. Named for its shape, not for an app
  Import/RichTextReader.swift              Just enough RTF to recover the text. Not a
                                           parser, and must not grow into one
  Import/AegisImport.swift                 Aegis vaults. Strict, and refuses encrypted
  Import/ProtobufReader.swift              Four wire types, bounds checked. Not a
                                           protobuf implementation, and must not become
  Import/GoogleAuthenticatorImport.swift   Their export QR. Raw secrets, batches, and
                                           their enumerations refused where not ours
  Export/AegisExport.swift                 The way out. Plaintext, and pinned to a
                                           fixed revision of the Aegis documentation
  Backup/BackupArchive.swift               The encrypted archive, read and written
  Backup/BackupPayload.swift               The accounts inside one
  Backup/BackupPassphrase.swift            The exact bytes the KDF receives
  Backup/PassphraseStrength.swift          The floor on the custom passphrase path
  Backup/PBKDF2.swift                      CommonCrypto. CryptoKit has no password KDF
  Backup/BackupBase64.swift                Strict out, lenient in
  Backup/BackupError.swift                 Why an archive would not open
  Vault/VaultRecord.swift                  One account, sealed in two halves so a
                                           list never decrypts a secret
  Vault/WrappedVaultKey.swift              The vault key sealed under a passphrase,
                                           one record so it cannot arrive in pieces
  Vault/VaultPadding.swift                 Length prefixed, so a size says less
  Vault/VaultKeyStore.swift                The key in the container. Asks FileManager
                                           every time, because E6 saw a container move
Tests/OpenFactorCoreTests/                 The shared core suites, 17k fuzz iterations
OpenFactor.xcodeproj                       See docs/PROJECT.md, checked in deliberately
OpenFactor/                                App target
  Assets.xcassets/AppIcon.appiconset/      The app icon, single 1024 source
  PrivacyInfo.xcprivacy                    No tracking, no collected data, one
                                           required reason API. Read it, it is short
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
  Import/ImportViewModel.swift             Format sniff, the preview, and every judgement
  Import/ImportView.swift                  Choose, review, confirm. Writes nothing early
  Export/ExportViewModel.swift             The passphrase, the file, and the file's life
  Export/ExportView.swift                  Explain, passphrase, share. Gated on Face ID
  Views/EditAccountView.swift              Renaming, and the color grid
  Settings/SettingsView.swift              Only rows whose features exist
  Settings/Preferences.swift               Preferences, in UserDefaults. Never secrets
  Settings/SyncAwareKeychainStore.swift    Reads the sync preference per call
  Settings/AppIconChanger.swift            Alternate icons, and the alert iOS insists on
  Lock/AppLockEngine.swift                 Every lock decision. Pure, no clock, tested
  Lock/AppLockController.swift             Scene phases and LocalAuthentication. Thin
  Lock/PrivacyShield.swift                 The app switcher cover. The only UIKit window
OpenFactorShared/                          Compiled into both app targets
  PaletteColor.swift                       Color and contrast arithmetic
  CodeFormatting.swift                     Digit grouping for transcription
  WatchPalette.swift                       The palette inverted for text on black
  WatchList.swift                          Which accounts the watch can finish, and the
                                           order it puts them in. Shown, never hidden
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
docs/audits/A3-implementation.md           A3's second half: the code, not the
                                           page. Five findings, all fixed
scripts/ship-testflight.sh                 Archive, export, validate, upload. Read
                                           its header before running it once
docs/PROJECT.md                            The project file in plain language
docs/POLISH.md                             Polish items, for PR 12
docs/design/icon-dark.svg, icon-light.svg  The app icon, source of truth
docs/design/icon-watch.svg                 The watch icon: the extracted piece
LICENSE, README.md, SECURITY.md, CONTRIBUTING.md, HANDOFF.md
docs/ROADMAP.md, docs/ARCHITECTURE.md, docs/UI_SPEC.md
.github/workflows/ci.yml                   Style checks, then build and test
```

Run the suite two ways, and CI runs both:

- `swift test`, under a second, no simulator, Keychain tests **skip**
- `xcodebuild test -project OpenFactor.xcodeproj -scheme OpenFactor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenFactorTests`, about 25 seconds, Keychain tests **run**

The shared core suites run twice. `OpenFactorTests` also holds app only suites whose sources are
`Tests/OpenFactorCoreTests`, attached as a second synchronized folder. Do not "fix" the
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
- Bundle identifier `dev.openfactor.app`, fixed by the App Store Connect record
- No view hardcodes a color, radius, or spacing. They all come from `Tokens`, which is
  what makes a light mode regression hard to introduce
- Card gradients only ever darken from the base, so the base is always the worst case for
  contrast and the tests only have to prove two stops
- One timer for the whole list, in the view, ticking the view model once a second. Codes
  are regenerated only when the counter changes, which a test proves by counting Keychain
  reads rather than by inspection
- The view model holds names, colors, and six digits. Never a secret. Asserted by
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
- Preferences are in `UserDefaults` because a sort order and a color scheme reveal nothing.
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

- Do not push without asking Xavier. Branches are pushed only when he says so.
- No em dashes anywhere. CI enforces this, as it does trailing whitespace.
- The RFC vector tables are the authority. If a change breaks one, the change is wrong.
- RFC 6238 Appendix B uses a **different seed per algorithm**, 20, 32, and 64 bytes.
  Running the whole table against the 20 byte seed is the usual way to get it wrong.
- **Do not trust simulator taps to prove an interface works.** Verifying the vault screens by
  hand, taps below roughly the top 45 per cent of the screen silently never landed while taps
  above it worked, which reads exactly like a dead control and cost half an hour chasing a
  binding that was never broken. Screenshots are trustworthy; injected touches are not. Anything
  a screen owes belongs in a test against the view model, which is where `VaultGateModelTests`
  now lives.

