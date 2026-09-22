# X4: a fourth blind, unscoped audit, the first of shipped code

**This is not gate A5**, for the same reason X1, X2 and X3 were not: A5 is the diff since
`audit-a4`, run before each release, and it still wants doing. This was a cold pass over the entire
repository at one commit by a reader with no brief from this project and no sight of `docs/audits/`.

**Audited commit:** `2523491dcaed3786fcf3e0143403c8f836829f0e`, the head of `main` on 2026-09-19,
which is the commit that recorded version 1.1 (9) as released. **It is the first blind audit of
code that is on the App Store**, and the first since every X3 finding was closed.
**Reviewer:** Grok 4.7, with a read-only checkout, told not to modify anything.
**Reported:** 2026-09-22.

## The prompt, verbatim

X1's prompt, changed only in the directory it names. Four cold readers, four lineages, one brief.

> checkout https://github.com/dragut-eth/openfactor.git, in this directory: /tmp/x4-audit readonly
> Record the commit hash you audited.
> Perform an independent security audit of this repository. Start by reading the README and
> security/design documentation to understand the claimed security properties, then inspect the
> actual implementation, entitlements, and tests and try to falsify those claims. Do not assume
> the documentation is correct. Do not read docs/audits/ until you have completed and written down
> your own findings, to avoid being biased by previous reviews. Report each finding with severity,
> affected code, reasoning, and a concrete attack or failure scenario where possible. Also report
> important security claims you were able to verify and claims you could not verify. Do not modify
> any files.

## What is different about this reviewer

**A fourth lineage with no hand in this code**, after Astra was the first. It read the format and
design documents first and checked each obligation they state against the code that is supposed to
honour it, which is where both findings come from: neither is a bug in a function, both are a gap
between a written rule and what the implementation can actually promise.

**It ran things.** The checkout was left read-only and untouched, and beside it sat three TIFF
headers built to claim impossible dimensions, a 400 KB nested JSON, and two compiled Swift probes.
The image probe is why one line in its could-not-verify list names an overflow it tried and could
not reach. Its stated limits: no device, the Xcode suite not run, section hashes not reproduced.

## Result

**One Medium and one Low. Both confirmed against the source before being accepted, none
withdrawn.** Four consecutive cold readers, no false positives.

**The Medium is the residue of OF-X3-01**, which this project rated the most serious finding of the
series because it needs no adversary. X3's fix removed the copy on every read and swept the
directory on every foreground. This reviewer found the window between those two: a file that
arrives while the app is locked on a cold start is never read, and a sweep that keeps young files
does not remove it either. Narrower than X3-01, same consequence, and it says something about the
X3 fix that a fourth reader, told nothing, went straight to the one path it left open.

| ID | Theirs | This project's reading |
| --- | --- | --- |
| OF-X4-01 | Medium | Medium: plaintext secrets in a backed-up directory, no attacker required, on a narrower path than X3-01 |
| OF-X4-02 | Low | Low: a written obligation the estimator's own comment already says it cannot meet |

**The Medium is closed in two parts, both landed, the second awaiting the maintainer's device
pass.** By the rule agreed for X2's verification round only Medium and above is in scope this
week; the Low and the two logged items wait.

## OF-X4-01, medium: a plaintext export can sit in a backed-up directory until the next launch

**Confirmed.** The path, traced in the source: a file opened into the app reaches `.onOpenURL`,
`InboxOpener.arrival(from:)` returns `.file(url)`, and that becomes the `arrival` state. The state
presents `ImportView` as a sheet on `AccountListView`, and `ImportView` calls `read` on creation,
which is where the copy is removed. **`AccountListView` is not in the tree while
`lock.presentsRootLock` is true**: the root is `LockScreenView`, and `docs/APP_LOCK.md` says so. So
on a locked cold start the URL is held and nothing reads it. `DocumentInbox.sweep` runs at the next
foreground and keeps anything younger than `settledAge`, sixty seconds. And **`Documents/Inbox` is
not excluded from backup**: the shared inbox and the vault key directory both set the attribute and
refuse to proceed if it does not read back, and this directory has nothing.

**The reviewer's scenario holds as written.** App Lock on, a plaintext export opened into the app,
Face ID abandoned, the app left within a minute, the process gone before the next foreground, a
backup in between. The next launch deletes the local copy. The backup has it.

**One more way into the same window, which the reviewer did not name.** `.onOpenURL` supersedes a
pending arrival with the new one. A superseded `.file` arrival is dropped from state, and its copy
in the inbox is left for the sweep, which will not touch it for a minute and only at a foreground.
The shared inbox is swept by identifier on that same line; the document copy is not.

**Why Medium and not higher.** X3-01 was reachable by anyone who ever used "Open in" once, with no
other condition. This needs App Lock on, a cold start rather than a return, an import abandoned in
its first minute, and a backup before the app is next opened. Each is ordinary; all four together
are not. The consequence when they line up is the same as X3-01: every secret in the export, in the
clear, in a place the app does not control.

**What the fix has to be, when it is decided.** Two things, both cheap, and either alone is
insufficient:

- **Exclude `Documents/Inbox` from backup**, at launch and again at each arrival, the way the shared
  inbox does, reading the attribute back rather than trusting the write. There is nothing to refuse
  on failure, since iOS writes the copy and not the app. iOS may recreate the directory, so the
  attribute is re-applied rather than set once. This closes the backup half regardless of when the
  file is read.
- **Take the bytes out of the directory at arrival, not at read.** `.onOpenURL` is the one moment
  the app is guaranteed to be running with the copy present. Reading an owned copy into memory
  there, bounded as the import already bounds it, and discarding the file immediately means the
  arrival carries data rather than a path, and no locked cold start can leave a file behind. The
  superseded-arrival case closes with it, since there is no file to supersede.

A third option, discarding a pending file arrival when the scene goes to the background, is not
enough on its own: a process killed without a background transition never runs it.

**Affected code:** `Sources/OpenFactorCore/Inbox/DocumentInbox.swift`,
`OpenFactor/OpenFactorApp.swift` at `.onOpenURL`, `OpenFactor/Import/ImportView.swift`,
`OpenFactor/Import/ImportViewModel.swift`.

**What was changed, part one: the directory is excluded from backup.** `DocumentInbox` gained
`excludeFromBackup`, the same shape as the shared inbox's mark: create the directory if iOS has not
yet, set the attribute, read it back on a fresh URL, and report whether it held. It refuses the same
redirect `owns` refuses, so an inbox that is a link elsewhere is neither created nor marked. The
app calls it at launch, before any delivery can land, on every scene phase change beside the sweep,
and on every file arrival. A backup honours the flag on the directory for everything inside it, so
a copy waiting through a locked cold start is outside any backup taken while it waits.

**Best effort, stated as such.** iOS writes the copy, so there is no write the app can refuse the
way the shared inbox refuses its own; a failure to mark leaves the read path and the sweep as they
were. The return value exists for the tests. Four tests: the mark reads back, a missing directory
is created already marked, a redirected inbox is left alone, and no Documents directory means no
mark. Core suite 485 tests, hosted iOS suite on the simulator, both green.

**What was changed, part two: the bytes leave the directory at arrival.** `InboxOpener.arrival`
now takes the document inbox, and for a file URL the inbox owns it reads the copy under the
importer's own bound and removes it on every way out, success or refusal. The arrival carries
`.document(Result<Data, BoundedFile.ReadError>)` rather than a path; a picked file, which the inbox
does not own, is still `.file(url)` and is still never removed. `ImportViewModel` reads the result
through the same `read(_ data:)` every other byte source uses, and shows a refusal from arrival
with the same two sentences a refusal at read would have used; the two sentences now live in one
place. `.onOpenURL` marks the directory first and then lets the arrival read and remove, so nothing
waits on disk while the app is locked, and a superseded arrival has no file to leave behind. The
second line, `discard` inside `read(_ url:)`, stays for any path that still hands a copy there.

**Three hosted tests:** an owned copy comes back as bytes and is gone, a file elsewhere comes
back as a path and stays, an oversized copy is refused as too large and is gone. Hosted suite 760
tests, core suite 485, both green. **The "Open in" path on hardware is the maintainer's pass**,
since the visible behaviour must be unchanged: the same preview, the same refusals.

## OF-X4-02, low: the custom-passphrase check does not enforce a 2^40 floor

**Confirmed as a mismatch between a written obligation and what the code can promise.**
`docs/BACKUP_FORMAT.md` says a writer must refuse a custom passphrase weaker than 2^40 guesses
under an offline strength estimator, or must not offer the custom path. `PassphraseStrength` is a
short blocklist, a keyboard-walk list, a repeat collapse and a character-class estimate. Its own
header comment says it is a floor and not a guarantee, that it will not recognise a dog's name or a
song lyric, and that the real defence is the generator being the default. The reviewer's table of
season-plus-year and three-word phrases passing at 60 to 80 estimated bits is what that comment
predicts. The numbers were not re-run here; the mismatch does not depend on them.

**Why Low.** The generated 120-bit passphrase is the default and the screen does nothing to steer
people off it. The custom path exists for people who insist, and the estimator removes the
passwords that fall in seconds. What it cannot do is what the format document says it must, and
one of the two has to move.

**Two ways to close it, not decided.** Reword the format document's obligation to what a
wordlist-free estimator can honour, and say plainly that a chosen passphrase is the person's own
risk above that floor. Or extend the estimator to the patterns the reviewer used, season and year,
word and year, a longer list, accepting that it still will not know anybody's dog. The first is
honest and small; the second is better and never finished. Deferred under the Medium-and-above rule.

**Affected:** `Sources/OpenFactorCore/Backup/PassphraseStrength.swift`,
`OpenFactor/Export/ExportViewModel.swift`, `docs/BACKUP_FORMAT.md`.

## Logged from the could-not-verify list, with severity

Two items the reviewer placed among unverified claims are worth carrying as work, both Low:

- **`width * height` in `QRDecoder` can trap on overflow** if a header claims dimensions past
  about 2^31 on each side. The reviewer built a TIFF to try it and ImageIO refused the header before
  the multiply ran, so no crash was shown. A `multipliedReportingOverflow` guard is one line and
  removes the dependence on ImageIO's refusal.
- **The CI network grep does not name `Data(contentsOf:)` or `String(contentsOf:)`.** The
  reviewer confirmed the app reads files through bounded descriptors and never through those, so
  adding the pattern to the grep costs nothing today and catches a future remote fetch that the
  present pattern would miss.

## What the audit verified

The reviewer's own list, checked against the implementation rather than the documents, and quoted
here in summary because it is the most complete cross-check of the vault design any of the four
reports has made:

- The vault key: random bytes, written only under `VaultKeyStore`, staging directory excluded from
  backup before any key byte is written, the write refused if the exclusion does not read back,
  complete protection on both platforms, never in the Keychain, the app group or defaults.
- The record layouts, separate metadata and secret seals, AAD domain separation including the
  account identifier, fresh nonces on reseal, the secret half copied verbatim on rename, recolour,
  reorder and counter update, and listing that opens only the metadata half.
- The wrapped key: PBKDF2 at 600,000 iterations on write, the reader clamp of 100,000 to
  2,000,000, salt and iterations in the additional data, canonicalised passphrase, `addIfAbsent`
  creation, the wrapped record written before the key file, a missing record not reported as a
  wrong passphrase.
- The backup reader: format, KDF and cipher checked before any derivation, ciphertext length capped
  before decode, GCM verified and the plaintext parsed before acceptance, fresh salt and nonce per
  archive.
- The watch exchange: P-256 ECDH, HKDF over the transcript, AES-GCM with the transcript as
  additional data, nonce checked before derivation, malformed requests refused before the key is
  read, a second request not replacing the one on screen, consent on a monotonic clock re-checked at
  approval, dismissal not treated as approval, the sealed key sent only after the tap. The
  complication has no entitlements and no Keychain use.
- The share extension: one entitlement, size-capped complete-protection writes refused if backup
  exclusion does not stick, reads and sweeps through a directory descriptor with `O_NOFOLLOW`.
- App Lock off by default, locking on a backward clock, multiple scenes off, capture masking on the
  list, confirm-add, manual entry and both passphrase screens, context-menu previews without the
  code, passphrases local-only on the pasteboard with a 120 second expiry, the pasteboard never
  read outside a debug view.
- Sync off by default, records and the wrapped key following the flag, the protection class
  switching with it, the vault key file never syncing, and the passphrase replacement path present
  in the core and reachable from no screen, which is what the design says.
- No networking, no logging, no dynamic loading, no remote packages, the privacy manifest declaring
  nothing collected, HOTP truncation matching the RFC, the counter stored before the code is
  returned.
- Parsers: protobuf lengths checked against remaining bytes, varints capped at ten bytes, groups
  rejected, codes capped at 8 KB, files read through a bounded descriptor, image decode through a
  thumbnail cap, short secrets refused, confirmation before every `add`, erase checking the typed
  word before authentication.

## What it could not verify

Nothing on hardware: file protection, backup exclusion surviving an update or restore, Keychain
access-group behaviour, clipboard expiry, the app-switcher snapshot, WatchConnectivity routing,
whether a same-team sibling is refused by the container, whether a rogue watch app can complete
provisioning. The exchange has no peer authentication and the phone's prompt is the only consent,
which the design states. No container anchor and no generation counter, so deletion of every record
looks like an empty vault and an old sealed record still verifies, both stated as unsolved. The
snapshot timing was not remeasured. CI and the suite were not run. Section hashes were not
reproduced and no store binary was compared.

**Its closing sentence, quoted and not adopted:** "The cryptography that is in the tree is careful
and mostly matches its own spec. The gap that still puts every secret somewhere a backup can take
them is the document inbox, not the Keychain."
