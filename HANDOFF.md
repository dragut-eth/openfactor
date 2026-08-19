# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

## Where things stand

**Last updated:** 2026-08-18, on TestFlight as `dev.openfactor.app`, 1.0 (4). PR 15b is
complete on `pr-15b-app-lock`, not pushed, and ready to merge on Xavier's word.

**Scope 2 is closed: all eleven of its findings are fixed.** The last five landed together.

**The dropped retry is fixed on the watch rather than the phone**, taking the reviewer's better
suggestion. The phone will not replace the request its alert is asking about, which is correct and
stops a substitution defect, but it answered a later request with "asking" and then discarded it,
so a retry after a timeout was acknowledged and forgotten. Receiving a response for an older
attempt is proof the phone has just finished answering one, so the watch now asks again
immediately, turning a second wasted timeout into an alert the wearer can answer. It cannot spin:
only a delivered response reaches that line.

**A refusal now names the request it refuses.** The decline carried only a status, so it was the
one message in the protocol bound to nothing, and a refusal of an abandoned attempt ended the one
still waiting. It echoes the nonce, and a decline without one is still honoured, since refusing it
would strand a watch on a phone that has already said no. Documented as matching rather than
authentication: a refusal releases nothing.

**Consent expires after two minutes.** A request accepted while App Lock was up could raise its
alert arbitrarily later, so somebody could be asked to release the key for a watch that stopped
asking hours before. Two minutes is longer than the watch's retry cycle and short enough that the
question and the answer belong to each other.

**Both test holes are closed, and both were proved by re-breaking the code.** A static phone
keypair now fails a test that checks the ephemeral public key itself changes between two responses
to one request, not merely that the responses differ. And the HKDF domain-separation label is
pinned by deriving the same secret and transcript without it and requiring a different key. Those
were the two demonstrations that a serious regression could pass the entire suite, and the reason
they could is worth keeping in mind for every other suite here: **a round trip tests two sides
against each other, so anything weakened symmetrically passes.**

**Four more fixed: the watch's protection class, the install ordering, the unmasked code
previews, and two false document claims.**

`VaultKeyStore` has its own `writingOptions` now instead of borrowing the share inbox's, whose
`#if os(iOS)` was narrower than the platforms this file supports, so the watch wrote the vault key
with `.atomic` alone under a comment promising `.complete`. And `install` writes to a staging
file, marks it excluded from backup, then moves it into place, so there is no longer a window in
which a complete key exists unmarked. A rename within a directory is atomic; the previous order
left a usable unexcluded key behind any kill between the two steps, with nothing to retry it.

Every screen that draws a live code now masks it while the screen is captured. It was true of the
account list only; the confirm-add and manual-entry previews drew live digits regardless, and a
code reaches the first of those from any `otpauth://` URL any app can send. All four card sites go
through one `maskedIfCaptured` helper, so a screen added later has something obvious to copy
rather than a rule to remember.

`docs/VAULT.md` no longer says the watch's private key may live in the Secure Enclave; it never
has. And `SECURITY.md` no longer claims the earlier watch review's four fixes were "all now
tested", because two of them had no test at all.

**The crash is fixed, and two small watch defects with it.** `GoogleAuthenticatorImport` read
the three batch header fields with `Int(clamping:)`, which turns an impossible `UInt64.max` into a
perfectly valid `Int.max`, and `Batch.position` then added one and trapped while a SwiftUI sheet
was being built. All three fields are now refused above a deliberately small bound, because
clamping a value somebody else chose converts "this cannot be true" into "this is the largest
thing that can be true", which is still a lie and now an unrefusable one. `position` uses a
saturating add as a belt.

Four tests, including the exact payload the review used, proved by restoring the clamp: two fail,
one of them the reproduction.

Also fixed: the `.noRandomness` catch in `ask()` left a stale attempt behind while telling the
flow a fresh one had failed, so a very late response could install a key with nothing outstanding;
and `responseDidNotOpen` was the one transition in the flow type with no guard of its own, so a
call with nothing outstanding demoted any stage including `.ready`. Both proved by reverting them.

**Multiple window scenes are switched off, which closes the gate's only confidentiality
finding.** The app was shipping with `UIApplicationSupportsMultipleScenes = true` while
`PrivacyShield` kept one lock window and one cover window on `connectedScenes.first`, so a second
iPad window had neither. Xavier chose switching them off over making both per scene: an
authenticator is opened to read a code and left, and the alternative is permanently more surface
in the layer that has produced the most defects here. Split View and Slide Over beside another app
are unaffected; only a second window of OpenFactor is gone.

Done in `OpenFactor-Info.plist` with the reasoning beside it, with Xcode's manifest generation
turned off so the file is authoritative, and **verified in the built artifact rather than the
project file**, which is exactly the mistake one engine made when it looked at this and concluded
scenes were not declared. `PrivacyShield.foregroundScene` now states the assumption where it would
break, and CI fails if the key flips back or if generation is re-enabled. Proved both ways.

**`docs/APP_LOCK.md`'s transition table was wrong and is corrected.** It said `didBecomeActive`
sets `coldLock = false`; the code deliberately does not and a test pins it. Since the page declares
itself normative over the code, anyone obeying it would have broken a tested guarantee and
reinstated the orientation latch the page exists to prevent.

**An open question for release, raised by this and bigger than it.** The app ships to iPad,
`UIDeviceFamily` is `[1, 2]`, and nobody has ever run it on one. The multi-scene defect is one
iPad problem three engines happened to be looking for. Either test on an iPad before release, or
ship iPhone-only and add iPad once it has been exercised.

**A4 fixes have started, on branch `a4-fixes`. The first pair is in: the wrapped key now
syncs, and `save` can no longer twin.** They had to land together, and the tests demonstrate why
rather than asserting it.

`WrappedKeyStore.setSynchronizable` is new and moves the record in place, never by delete and
re-add, since a crash between those two would destroy the only route back into the vault.
`SyncAwareKeychainStore` calls it alongside the accounts, **key first when enabling and last when
disabling**, so the intermediate state is always the safe one: the means of reading arrives before
the thing to read, and stops syncing after it.

`save` now looks for an existing record under either sync flag and updates it as found. Two
consequences. It cannot create the twin that `kSecAttrSynchronizable` being part of a Keychain
item's primary key would otherwise allow. And a passphrase change no longer relocates the record
between iCloud and this device as a side effect, because the flag is no longer in the change
dictionary: where the record lives is `setSynchronizable`'s decision alone.

**Seven tests in `OpenFactorTests/WrappedKeySyncTests.swift`, proved in both directions.** With
`setSynchronizable` neutered the suite fails; with `save` restored to its old add-then-update
shape, `savingAfterASyncChangeDoesNotTwin` fails specifically. That second proof is the pairing
made visible: the twin test can only fail once the sync fix exists, because the sync fix is what
creates a differing flag in the first place.

`docs/VAULT.md` needed no change. Its Sync section has always said the wrapped key record follows
the preference; the code now does what the document already promised.

**A4 round one is complete. Scope 4 found the first confidentiality failure of the gate, and it
is mine.** `PrivacyShield` keeps one process-global cover and one process-global lock, both bound
to `connectedScenes.first`. The shipped `Info.plist` declares
`UIApplicationSupportsMultipleScenes = true` for iPhone and iPad, verified in the built artifact.
So on an iPad with two windows, the second has no cover in the app switcher and no lock over it,
which breaks `SECURITY.md`'s "the app switcher card never contains a code" and `APP_LOCK.md`'s R2
in their own words.

**The observation about the tests is the part to keep.** `AppLockPresentation` was extracted so
the lock's decisions could be tested, and that was right; it caught a real leak before it shipped.
But it models *when* to lock, and this defect is about *which surface* gets locked. The tests are
complete for what they cover, and their existence made the uncovered dimension harder to see.

**The inbox is never swept at launch, found by all three engines.** `sweep()` has one caller, the
`defer` inside `collect()`, which four guards can refuse. Open the app with App Lock on, cancel
Face ID, and a transfer QR holding every secret stays in the group container with no upper bound.
Fable added the half nobody else had and it is verified: **nothing sets `isExcludedFromBackup` on
the inbox**, while `VaultKeyStore` sets exactly that on the vault key, so a stranded image is
eligible for the device backup. The extension exists to keep that image out of a persistent
cloud-reachable store, and the inbox reproduces the exposure with a different folder name. Fable
also named the trap in the obvious fix: an unconditional launch sweep would delete a share the
owner is about to unlock into, so the fix is an age-bounded sweep.

**Grok found the crash from scope 3 again from the other side**, and sharpened it: the trap fires
in `ImportView.init` as the sheet is built, and with a warm App Lock the account list is still in
the tree beneath the lock window, so the process can die while the app is showing its lock screen.

**Two more, both mine from 2026-08-18.** The confirm-add screen and the manual-entry preview draw
live codes and never read `isScreenCaptured`, so "codes become bullets while captured" is true of
one screen out of three. And `docs/APP_LOCK.md`'s transition table says `didBecomeActive` sets
`coldLock = false`, which the code deliberately does not and a test pins; the page declares that
where code and page disagree the page wins, so anyone obeying it would break a tested guarantee
and reinstate the orientation latch the page exists to prevent.

**One engine was factually wrong and it is recorded.** Grok asked the multi-scene question,
concluded multiple scenes were not declared, and filed it as a maybe it would not promote. It
reasoned from the project file; the shipped `Info.plist` says otherwise. Its instinct to flag
uncertainty was right and it would still have left the defect in place had it been the only engine.

**A4 scope 3, the parsers, found a data-loss path that needs no attacker.** Fable's pass is in
`docs/audits/A4-scope3-parsers.md`. The backup format demands a secret decode to at least ten
bytes and a counter stay under 2^53. The archive reader enforces both. **Three of the four
enrollment paths do not**, and `BackupPayload.write` serializes whatever the account holds, so an
account with a short secret works every day, exports into a backup, and is refused when that
backup is restored.

**Proved end to end rather than read.** A probe enrolled `otpauth://totp/x?secret=GEZDGNBV`
through the real URI parser, wrote it, and read it back: five-byte secret accepted, payload
written, **zero accounts restored**. The refusal reads `secretNotBase32` for a secret that is
perfectly valid Base32, so the message sends whoever hits it looking for a bad character that does
not exist.

It needs no hostile input, since a service issuing a short secret is enough, and it is discovered
at the worst possible moment: on a new device that no longer has the originals. A hostile QR code
triggers it deliberately, planting an account that silently drops out of every backup.

**Scope 3 is complete, and ChatGPT found the only crash in this project.** A crafted
`otpauth-migration://` payload carrying `batch_index = UInt64.max` is clamped to `Int.max` by
`GoogleAuthenticatorImport`, and `Batch.position` then evaluates `index + 1` and traps.
Reproduced rather than reasoned about: the payload was assembled, wrapped in the real URL, run
through the real parser, and the test process died with signal 5 at exactly that line.

**Any app on the device can trigger it with one URL**, since `otpauth-migration://` is a declared
scheme. It is a denial of service rather than memory corruption, because a Swift overflow trap is
a controlled abort, but it needs no user action beyond opening the link. The mechanism is a clamp
that hides an inconsistency instead of refusing it, and both engines that had examined
`ProtobufReader`'s bounds in detail declared them sound, correctly: the defect is not in the
parser but in the value the parser was allowed to hand onward.

**Three smaller ones, all confirmed.** The import front door caps files at 8 MiB before the
archive sniff while a conforming archive can reach about 12.2 MB, so the routing layer narrows a
bound the format froze; `BackupArchive`'s own comments describe that exact mistake being caught
inside the reader, and it now sits in front of it. A UTF-8 BOM defeats the JSON sniff, so a mangled
archive never reaches the passphrase prompt, even though the layer below strips that BOM
deliberately. And `sortIndex` is read from every format and discarded by the store.

**One finding in scope 3 was reported by all three engines, and the crash by exactly one.** Four
of eleven items were single-engine. Also single-engine: that `BackupArchive.write` never enforces
its own plaintext limit, so the app can export an archive its own importer refuses; that
duplicates within one file bypass detection entirely, since `classify` compares only against what
is stored; that the in-app PhotosPicker path has no size check at all while the share extension
caps the same input at 8 MiB; and that after importing an **encrypted** archive the app tells its
owner the file "contains your secret keys in the clear" and advises deleting it, which is false
and destroys a recovery artifact the person has just verified they can open.

**The pattern of this gate is becoming clear: the audited artifact holds and its neighbours do
not.** The backup format is the most carefully specified thing in this project, with a frozen
document, published vectors and a reader enforcing every rule. Nothing enforces those rules on the
way in.

Two things the pass did beyond its findings are worth keeping: it re-derived both published test
vector keys independently in Python, the first external check of those vectors, and it verified
`UnicodeScalar(Int)` is failable by executing it rather than assuming, which is the difference
between believing a parser is trap-free and knowing it.

**A4 scope 2, the Watch exchange, is two thirds done and found that yesterday's fixes created
two new defects.** Recorded in `docs/audits/A4-scope2-watch.md`. ChatGPT and Fable independently
reached the same one: the `guard pendingRequest == nil else { return .asking }` added yesterday
correctly stops a second request replacing the approved one, and then tells the watch "you are
being asked" while the phone discards it. The watch waits for a message that cannot arrive, and
the wearer's approval seals to the abandoned attempt. Reachable by the ordinary path, because the
watch retries automatically on a raised wrist.

The second is a gap in the flow type written the same day. Every message in the protocol is bound
to its attempt except the one that says no: `decline()` sends a bare status string, and
`phoneDeclined()` takes no token, so a decline of an abandoned attempt clears the current one.

**Fable's best finding was not a defect in shipped code but a hole in the net.** It claimed a
regression giving the phone a static ECDH keypair would pass the entire suite. That was checked
by doing it: with a single static keypair, **all 358 tests pass**. `exchangesAreFresh` varies the
request each time, so responses differ regardless of whether the phone's key is fresh, and its
name claims more than it observes. That is the fourth test in this project found checking less
than its name promised. A static phone key turns a captured response plus a later phone compromise
into vault-key recovery, which is precisely what the ephemeral design exists to prevent.

**Grok completed scope 2 and found a second hole in the test net, plus a false claim in
`SECURITY.md`.** Deleting the HKDF domain-separation label was tried and the full suite still
passes: 358 tests. So the label separating this exchange's key derivation from any other use of
the same shared secret is protected by nothing. Both holes share a cause worth naming: the suite
tests the two sides against each other, and any change made symmetrically to both passes. **A
round trip cannot detect a weakened construction, only a disagreement.**

**`SECURITY.md:43` says the four defects from the earlier watch review were "all fixed and all now
tested". That is false.** No test in this repository references `WatchKeyProvider` at all, and the
`.noRandomness` path is untested, so two of the four have no test. The sentence was written the
same day as the fixes. A reviewer found it by reading the document against the code, which is the
strongest argument this gate has produced for the basis labels added in PR 17: **tested** has to
mean a machine fails when the claim stops being true.

**Scope 2 is complete.** Three findings were reported by all three engines, unlike scope 1 where
none were. The most valuable items were still single-engine: both verified test holes came from
one engine each. No engine found a cryptographic defect, and each said so with mechanisms rather
than assurances.

**One methodological cost is now on the record.** Fable opened by noting this scope cannot be read
cold by anyone any more, because the code comments narrate the previous review's findings in
detail. That is true and it is a direct cost of a practice this project otherwise benefits from.
Both engines found the defect sitting directly beneath a comment describing the fix that created
it, and neither found anything in the cryptography, which carries the same density of explanation.
No change proposed; the comments are worth more to a maintainer than cold-review purity is worth
to a gate that runs a handful of times. But a reader comparing scope 1's yield with scope 2's
should know the two were not equally readable.

**Gate A4 has started, and its first pass found a defect that loses every synced account.**
ChatGPT 5.6 Sol reviewed scope 1, the vault at rest, against commit `74fe841`. The pass and the
triage are in `docs/audits/A4-scope1-vault.md`. Eight findings, all eight confirmed against the
code, none rejected: the second consecutive cold review with no false positives.

**The one that matters: the wrapped vault key never syncs.** `WrappedKeyStore` defaults to
`synchronizable: false` and nothing ever changes it, because `setSynchronizable` operates on the
accounts service alone. Enable sync, lose the phone, and the replacement receives every account
as ciphertext with no wrapped key for the passphrase to unwrap. `docs/VAULT.md` promises the
opposite in its Sync section, and the property's own comment three lines above the default says
it follows the account items. The code contradicts a comment directly above it, which is why
nobody reading either noticed.

**This is live.** It affects the maintainer's own phone and build 5 on TestFlight. An encrypted
export is the only recovery path that currently exists, and was advised immediately.

Three mediums and four documentation mismatches are also confirmed. One of the mediums is a
regression introduced the same day: `VaultKeyStore.install` was pointed at
`SharedInbox.writingOptions` when macOS started refusing `completeFileProtection`, and that
helper's `#if os(iOS)` is narrower than the `#if os(iOS) || os(watchOS) || os(tvOS)` branch
around the call, so the watch writes the vault key with no protection class under a comment
claiming `.complete`.

**Fable 5 then ran the same scope and found six things ChatGPT did not**, including the two
sharpest. `replacePassphrase()` saves the new wrap before returning the passphrase string, so a
crash or a torn-down view between them silently invalidates a working recovery credential nobody
ever saw; the project already learned that lesson for `create()` and never applied it to
replacement. And `create(with:)` has no existence check, so on a second device reading the stale
`absent` state, which the design itself measures as lasting close to half an hour, one tap
overwrites an arrived wrapped record.

**The two passes overlap on only two of eight findings each.** ChatGPT found the sync gap Fable
missed; Fable found six ChatGPT missed. That is the multi-vendor argument working rather than
being asserted, and it is recorded in the audit file as the method's own result.

**One finding has a sequencing consequence that must not be lost.** `kSecAttrSynchronizable` is
part of a Keychain item's primary key, so `save()` writing a differing flag produces a twin record
rather than a duplicate error, and `load()` picks between twins unspecified. That cannot fire
today only because the sync gap keeps the flag permanently false. **Fixing the sync gap without
fixing `save()` in the same change would create the twin case.** They land together or not at all.

**A defect in the prompt, not in either review.** Fable flagged that it could not confirm the twin
finding because `SyncAwareKeychainStore` was not among the attached files, and that is precisely
the file showing the sync gap. Scope 1's file list in `A4-prompts.md` also omitted `PBKDF2.swift`
and `BackupPassphrase.swift`, which the pass named as unverifiable assumptions. Later scopes'
file lists should be built by asking what a reviewer would need, not what seems central.

**Grok 4.6 completed scope 1**, independently reaching the sync gap by a different route and
adding one nobody else found: `VaultGateModel.refresh()` returns early while a passphrase is on
screen, so an arriving wrapped record does not move the device to unlock, which is the
documentation's own claim and is true only on the intro screen. That is the destructive race in
its most reachable form, and like the twin case it is dormant only because the wrap never
arrives.

**One claim was partly rejected, the first in this gate.** Grok said the page's "collapse into one
bucket" sentence is already false; that sentence describes the published test vector, whose toy
metadata does fit one bucket, and it is accurate. The observation behind it stands and is
accepted: real metadata is 132 to 139 bytes, so an ordinary account spans two buckets and the
residual leak is a coarse size class the page never mentions. Recording the distinction matters,
because "no false positives" had been said twice and should stay precise.

**No finding was reported by all three engines.** The high-severity one was missed by Fable, the
two worst write-ordering defects were each found by exactly one engine, and running any single
engine would have left this scope carrying either a defect that loses every synced account or one
that invalidates a recovery passphrase nobody ever saw. The full matrix is in the audit file.

**Fable's two misses were caused by scope 1's file list**, which omitted `SyncAwareKeychainStore`
and `SharedInbox`, the two files holding the mechanisms in question. It said so at the time. The
other engines found them by reading from disk. Remaining scopes should list what a reviewer needs
to follow a claim to its end, and should say that anything referenced may be opened.

**Scope 1 is complete and fixes begin now**, in an order the findings dictate rather than by
severity: the sync gap and `save()`'s twin behaviour together, since fixing either alone is worse
than fixing neither; then the creation guard and `refresh()`, which protect the same tap; then
`replacePassphrase` split so nothing is written before it is shown; then the error states and the
wrong-passphrase mapping; then the watch protection class and install ordering; then the document
mismatches together.

**CI now refuses statements about the maintainer's circumstances in public documents.** Added
after a sentence explaining why a security gate was met one way rather than another went into the
roadmap, the handoff and a commit message. Nothing had been pushed, which was luck rather than
process. The check is anchored to phrases rather than words, so the character and byte budgets
discussed elsewhere do not match it, and it was proved against six real phrasings and three
legitimate ones. It catches crude wording only and cannot catch the same fact said carefully, so
it is a backstop under a judgment call rather than a replacement for one.

**Gate A4 is now three cold reviews by three vendors, run twice.** Fable 5, Grok 4.6 and
ChatGPT 5.6 Sol, each given the code cold with no history and no account of what previous
reviewers found. Three vendors rather than three prompts to one model, because two models from
the same lab share the blind spot that matters most.

Round one finds, scoped into four areas per engine rather than "audit this app", since a model
asked to review everything returns a plausible survey of nothing; the Watch review that found
four real defects worked because it was narrow. Round two runs the same engines over the same
scopes, told exactly what changed and why, which is what catches a fix that does not address its
finding and a fix that broke something else. Every pass is published whole in `docs/audits/`,
including the ones that found nothing and the findings that dissolved on inspection. Done means a
full round with no new finding that survives triage, not a fixed number of rounds.

Each engine is then asked for a ten to fifteen sentence opinion for `README.md`, published whole
and attributed. **That is the part to watch.** Three model opinions in a README can read as
"reviewed and approved", which is the false confidence `SECURITY.md` exists to prevent, and
models skew flattering when asked for a general impression. So the question is framed as what
they would warn a security-conscious friend about and what they would not trust the app with, the
answers are published unflattering parts included, and there is no re-asking until an opinion
improves.

Three limits are written into the gate rather than left to be discovered: the prompts are still
authored here, so each is published with its pass and a reader can judge whether it was leading;
a model reads code and cannot run the app, so gate E1, the vault key file through a restore and
Quick Start, and WatchConnectivity routing exclusivity stay hand-measured or unmeasured; and
three engines agreeing narrows the gap rather than closing it. The gate says plainly that this is
not a professional audit and that `README.md` must not imply one.

**PR 17's threat model is written, and the job was verification rather than prose.** Every claim
in `SECURITY.md` was checked against the code as it stands, and three were false: that the Watch
screens were not built, that nothing in the document had had an implementation review, and that
the app switcher never contains a code. The last one is the interesting one, because it was true
when written and PR 15b measured the exception: iOS keeps a second snapshot cache behind the home
screen zoom that the cover cannot reach.

Claims now carry their basis. **Measured** means seen once on hardware and can rot silently,
**tested** means something here fails if it stops being true, **reasoned** means nothing checks
it. Making that distinction visible is what turns the document from prose into something an
auditor can work through, and it immediately exposed the weakest claim in it.

**That weakest claim was the supply chain.** "There are no third-party dependencies" was pure
prose sitting beside claims a machine enforces, and a dependency arrives by one line in a pull
request about something else. CI now fails on a remote package in `Package.swift`, a remote
reference in the Xcode project, or a committed `Package.resolved`. Proved both ways, and the
first version failed on a clean tree because it matched `XCSwiftPackageProductDependency`, which
is how the project consumes the local core package.

**Two long-deferred items are closed rather than deferred again.** The context menu's exposure to
system-added entries cannot be established from inside the app, so the limitation is preserved
with the reason it cannot be verified, and the existing narrowing is stated: the preview is the
card with its digits masked. And the roadmap's five attackers now have an index at the top of the
threat model, because they never mapped one-to-one onto sections and pretending otherwise would
have meant restructuring a document that is organised sensibly already.

**Secrets are now hidden while the screen is captured, and a screenshot of a passphrase warns
you.** Three things on one mechanism, all measured on hardware: codes become bullets during a
screen recording, a vault or backup passphrase is withheld with an explanation rather than
blanked, and a screenshot on either passphrase screen raises an alert naming Photos, iCloud
Photos and the thirty days in Recently Deleted. The negative control was checked too, since it is
the half that decides whether the alert is worth having: screenshotting the account list raises
nothing.

**The reasoning changed twice while deciding this, both times because looking beat arguing.**
The first framing was that codes are shown to be read and die in seconds, so capture hardly
matters. That ignored the account list, which names the services somebody holds accounts with and
never expires. And screenshot detection was dismissed as buying nothing actionable, which is true
for a code and exactly wrong for a passphrase: the app itself tells people it is shown once and
never again, which is the most reliable way ever devised to make somebody screenshot it, and the
consequence, a photo syncing through iCloud and surviving thirty days in Recently Deleted, is the
same argument that justified building the share extension.

**One technique was considered and rejected, which is worth not re-litigating.** Hosting content
inside a secure text field's internal layer does block screenshots and recordings outright, and
it is better UX than blanking because the owner still sees the passphrase. It depends on the
undocumented internals of a system control, so when Apple changes them it fails silently, keeps
claiming protection, and cannot be verified by any test this project can run. Rejected on the
silent failure, not on being a hack.

**Codes now reach other devices through Universal Clipboard; passphrases still do not.** PR 17's
pasteboard audit found the copy path already doing everything right, all three copies through one
type, both narrowing options set, the app never reading the clipboard, and the watch unable to
copy at all. What it also found was that `localOnly` on codes was the wrong call, and the argument
is Xavier's: this project already accepts Apple's transport for iCloud Keychain sync, off by
default and enabled by its owner, so forbidding the same shape of thing for the clipboard is an
inconsistency with no principle behind it, and it overrides a choice made at the system level.
Every comparable authenticator allows the paste, which is why the old behaviour was first
reported here as OpenFactor being broken.

**Three facts were measured on hardware, with a positive control, and the third changed the
reasoning.** A code now reaches the Mac. The expiry clears the originating phone. The expiry does
**not** travel, so a code stays on the Mac's clipboard until something replaces it. That last one
turns the passphrase rule from belt-and-braces into the only thing standing between a passphrase
and a permanent entry in a Mac clipboard and any clipboard manager watching it, so it was tested
in its own right rather than assumed: a copied passphrase does not paste on the Mac.

The first attempt at this test was worthless and worth remembering. Universal Clipboard was not
enabled on the Mac, so nothing pasted from anywhere, and "the code did not arrive" looked
identical to the protection working. The positive control, pasting from Notes first, is what made
the later measurements mean anything. Same failure mode as a CI check that passes while lying.

`SECURITY.md` has a clipboard section now, which the audit found was the one real documentation
gap: the design was exemplary and entirely unwritten, so an auditor would have flagged the
best-handled surface in the app as an open question.

**The no-network claim is now enforced against the shipped artifact, not only the source.**
PR 17's CI item is done: a `binary` job builds Release unsigned, finds every Mach-O in the
bundle rather than naming them, and fails on any linked networking framework or referenced
networking symbol. Proving it earned its keep twice. The first probe was dead-stripped by the
Release link and the check passed, which is correct, and is why the source grep and the binary
check are complementary rather than redundant. The second probe, actually reachable, exposed
that the guessed pattern missed `_OBJC_CLASS_$_NSURLSession`, the shape Swift actually emits,
so the pattern was rewritten from `nm` output and the check now goes red on that build and
green on the real one. The source sweep also gained `dlsym`, `dlopen` and `NSClassFromString`,
which are how a symbol check gets evaded and which the binary check cannot flag because the
Swift runtime itself references `dlsym`.

**PR 15b passed its checklist, ten of ten on hardware.** Xavier reviewed the specification
and said go, and the build order was the spec's own: `AppLockPresentation`, a pure value
type wrapping the untouched `AppLockEngine`, went in first with the required sequences as
tests, the first attempt's black flash and snapshot leak among them by name. Then the
glue: `PrivacyShield` owns both windows and applies the core's three outputs in the one
safe order, shows before hides, with the lock window built once at `.alert + 2` and the
auto prompt driven on the transition to visible. Cold launches still lock as the root,
exactly as PR 15 shipped. The arrival rule lives in `AccountListView`: an arrival closes
every open sheet and withholds its own until the closing sheet's `onDisappear`, because
presenting during another sheet's dismissal is a request SwiftUI silently drops, which is
what broke share-mid-flow in the first attempt. Typed text now survives a lock because
nothing is torn down, which is what the whole PR was for.

**One finding survived the checklist and is accepted rather than fixed**, written up in
full in `docs/APP_LOCK.md` under what the cover cannot reach. iOS keeps a second snapshot
cache, the one behind the zoom from the home screen, written at a moment the cover is not
up; a screen recording read frame by frame showed the previous screen for about a sixth of
a second before the lock appeared. It is not our window ordering, and the frame that proves
it is the lock already drawn while that content is still crossfading out underneath, which
only happens when the system is dissolving its own snapshot. The documented lever,
`ignoreSnapshotOnNextApplicationLaunch`, did nothing and was removed rather than left
looking like protection. The behavior is on record from iOS 7 onward with no Apple answer.
The switcher card, the artifact anyone can browse to, stays blank.

**A cold independent review of the watch key exchange found four real defects, all now
fixed.** Run by Xavier on a fresh model with no context, after two attempts from here died on
server errors. Nothing it reported dissolved on inspection, which is the first time that has
happened in this project, and it found nothing wrong with the cryptography itself: the
transcript binding, the ordering of the nonce check, the AEAD's additional data and the exact
length guards all hold.

**The one that mattered was a pair of races in the watch's asking flow**, needing no attacker
and reachable by walking away and coming back. A timer started for one attempt checked only
whether the stage was still `waiting`, which is true again the moment a new attempt begins, so
it demoted its own replacement. And a late response to an abandoned attempt failed to open,
correctly, then landed in one generic catch that cleared the attempt still waiting, so the
genuine answer that followed had nothing to open it with and was dropped in silence. Two
ordinary taps and the watch could not be provisioned until the app was restarted.

Those decisions now live in `WatchProvisioningFlow` in the core, for the reason
`AppLockPresentation` exists: they were scene state in the watch target, where no test could
reach them, which is why nothing caught this. Both sequences are tests, and both were proved to
fail against the old behavior before the fix was kept.

**Three smaller ones.** The phone overwrote the request its alert was asking about, so a second
request could substitute the key a tap had been offered for; harmless under routing exclusivity,
and exactly the defect that converts a weakening of it into key exfiltration, which is why
`SECURITY.md` calls that exclusivity load bearing. The phone loaded its vault key and put a
question on screen before parsing the request at all, so malformed bytes reached the human path
and, once approved, produced no reply and left the watch on a spinner; there is a
`ValidatedRequest` before any of that now. And `SecRandomCopyBytes`'s result was discarded in
`Attempt.init`, where the buffer starts as sixteen zero bytes, so a refusal would have shipped a
predictable nonce while claiming freshness; `VaultKeyStore.create` checks the same call, so the
project disagreed with itself.

**Two comments were materially false and are corrected**, in this file's own terms: an attempt
does outlive the two messages on every path but success, and `open` enforces nothing about being
used once.

**The sharpest observation was about a test rather than the code.** One test's name claimed the
nonce is checked before anything is derived, and its response carried a valid public key, so it
could not observe that ordering at all. The replacement is wrong in both ways at once, so the
error names which check ran first. Writing the new binding test also produced a wrong assertion
of mine, caught by the suite: a response built on a substituted watch key cannot be opened by the
holder of that key either, because the nonce still binds it to the original attempt. The code was
right and the test was wrong.

**Settled: the complication's octagon was the Debug build, and the icon diagnosis was wrong
twice over.** Build 5 on TestFlight renders the mark correctly and at the right size, which is
the measurement that closes this.

What was claimed on 2026-08-17 was that the complication gained an app icon set and the build
setting pointing at it. **Neither landed.** There is no `Assets.xcassets` under
`OpenFactorWatch Complication` in any commit on any branch, and the complication target's own
build configurations carry no `ASSETCATALOG_COMPILER_APPICON_NAME`. An intermediate account
written the next morning said the setting had landed and only the catalog was missing; that was
also wrong, from reading a setting that belonged to a neighbouring target's configuration block.

**The complication never needed an icon at all**, which the working Release build now proves.
App extensions carry no icon of their own on watchOS, the picker uses the containing app's, and
the watch app's `Assets.car` and `CFBundleIconName` were correct throughout. The complication
also draws its mark entirely in SwiftUI shapes with no image asset anywhere in it, so a missing
icon could never have been what failed to render. An attempt to add the catalog was made and
reverted once those three facts were checked.

The actual cause is what the appex carries in a Debug build: `OpenFactorComplication.debug.dylib`
and `__preview.dylib`. A widget extension launched by the system rather than by Xcode cannot use
that indirection, so watchOS drew its placeholder, which is the octagon.

**The reusable fact, which is the only part worth remembering: a watchOS complication cannot be
verified from a Debug build installed with `devicectl`.** It has to be a Release build through
TestFlight. Four rounds of diagnosis went into this, three of them guessing at the drawn mark and
one at an icon, and every one of them was working from a build that could not have rendered
correctly whatever the code said. This belongs with the caution about simulator taps below:
know what your test rig cannot show you before you trust what it does.

**The privacy manifest was incomplete, and is now declared and guarded.** Reported by the
session doing PR 18 metadata work, verified here against Apple's published data rather than
the report: `SharedInbox.pending()` reads a file modification date, file timestamps are a
required reason category, and the manifest declared only `UserDefaults`. It now declares
`NSPrivacyAccessedAPICategoryFileTimestamp` with `C617.1`, the app group container reason,
which is the inbox verbatim. Worth knowing for the next one of these: a first reading of
Apple's data paired every reason code with the wrong text, because the codes sit after the
prose they belong to, and only checking the pairing in document order caught it. A wrong
reason code is worse than none.

**CI now fails when a required reason API appears in source without a manifest entry**, in
the same shape as the share extension's entitlement check and for the same reason. The
defect was invisible by construction: it built, it ran, it passed every test, it arrived by
addition rather than by edit so no diff review would show it, and it would have surfaced as
an automated notice from Apple at upload. Proved in both directions before commit. The
whole codebase was swept while there: no boot time, no disk space, no active keyboard.

**The phone and the watch now share one answer vocabulary instead of two copies of it.**
Found while preparing to test the failure paths, which is exactly where it would have bitten.
The two targets agreed only through separate hand written string literals, and the watch fell
through to "Not set up" for anything it did not recognise, so a rename on either side would
have compiled, shipped, and told somebody their watch was not set up when the truth was that
their phone had no vault. A wrong answer that reads as a plausible one. `WatchProvisioning.Answer`
and `MessageKey` are the single declaration now, the watch switches exhaustively over the enum
so the compiler catches a mismatch, and tests pin the wire values so a rename cannot quietly
change what an older watch build receives. Same argument as `SharedInbox.appGroup`.

**Account labels are now bounded, and the reason is the import path rather than typing.**
Xavier asked whether the Service field had a character limit. It did not, at any layer, and
a label grew a stored record byte for byte: a hundred thousand characters produced about a
hundred kilobytes of sealed metadata in one Keychain item, synced if sync is on. What made
it worth fixing was not somebody typing but an imported transfer or a restored backup, where
labels arrive from a file bounded only by the eight megabyte file limit. `AccountLabel` caps
both issuer and name at sixty-four characters in the core, so typing, scanning, importing,
restoring and renaming all pass through one number. Both text fields stop at the same bound,
so nothing is silently cut at save time.

The rename path is the one an initializer alone would have missed, since it assigns to a
property of an existing value; `didSet` covers it and there is a test for exactly that.

**A pre-existing build quirk, found while verifying and left alone:** the
`OpenFactorWatch Watch App` scheme cannot be built directly, failing with a watchOS object
linked into an iOS binary. It fails identically on a clean tree with no local changes and a
fresh derived data path, so it is not new. The watch is built through the `OpenFactor`
scheme, which is how it reaches the device and TestFlight, and that path builds the watch
app and the complication correctly.

**Two speculative fixes were spent on that flash before anyone looked at it**, and both
were reverted. The lesson is the project's oldest one and it repeated exactly: a screen
recording pulled apart frame by frame answered in one pass what two builds of reasoning
did not. Look, then reason.

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
The complication was changed only in its drawn mark, which keeps the other session's measured
0.703 proportion. The icon claims made that day were wrong in both halves: see below.

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
the gap three documents were carrying. **All three paths have now run on hardware:** the
successful one, a declined request, which leaves the watch on "Not set up", and a phone with no
vault of its own, which answers "Set up your iPhone first" without raising an alert at all,
because there is no key to offer and therefore nothing to ask about.

**Recovery was tested as part of the same run, and it matters more than either refusal.** The
passphrase restored the dropped key on the phone and the accounts opened as before, and the watch,
having been refused twice, was then provisioned successfully without being reset or reinstalled.
That is the path that would otherwise strand somebody: a refusal that left a watch unable to ask
again would need an uninstall to recover, and it does not.

Neither failure path needed anything destroyed, which is worth remembering next time. The Debug
row's "Lock this iPhone" drops the key and keeps the accounts, so it reaches the same state the
phone would be in with no vault, and the passphrase brings it back. Declining needs no reset
either: the watch only asks when it has no key, so it stays askable afterwards.

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

