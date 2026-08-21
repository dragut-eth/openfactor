# A4, scope 3: everything that parses bytes somebody else wrote

Gate A4 round one, the scope covering the backup format, the three importers, the URI parser, and
Base32. The prompt is `docs/audits/A4/A4-prompts.md`, preamble plus Scope 3, unchanged.

**Commit under review: `74fe841`**, the same commit scopes 1 and 2 read. No source has changed
since; only `docs/audits/` has.

**This is the first scope all three engines can read genuinely cold.** Neither of the earlier
scopes was: scope 2's comments narrate the previous review's findings, and ChatGPT had reviewed
that exchange before. Nothing here has been reviewed by anybody.

**One edit is made to every pass published here.** Absolute paths from the reviewing machine are
rewritten as repository-relative. Nothing else is trimmed, softened, or reordered.

| Engine | Status |
| --- | --- |
| Fable 5 | Returned, below. Triaged |
| ChatGPT 5.6 Sol | Returned, below. Triaged |
| Grok 4.6 | Returned, below. Triaged |

---

## Fable 5

*Read-only pass over commit `74fe841`. Reproduced as returned, abridged in the sections that
enumerate what held.*

> **F1 — Medium. Three importers accept accounts the backup format forbids, the archive writer
> serializes them unchecked, and the app's own reader then refuses them at restore.**
>
> `docs/BACKUP_FORMAT.md` is normative: a `secret` must decode to at least 10 bytes, and `counter`
> must be 0 to 2^53 − 1. The archive reader enforces both, at `BackupPayload.swift:107` and
> `BackupPayload.swift:133`, and so would any independent implementation written from the
> document. But three enrollment paths admit violating values, and `BackupPayload.write` writes
> whatever the account holds:
>
> * `OTPAuthURI.swift:164` refuses only an empty secret; a 5-byte one passes.
>   `OTPAuthURI.swift:248` accepts any `UInt64` counter up to 2^64 − 1.
> * `AegisImport.swift:84` has no minimum secret length, and line 107 no counter ceiling.
> * `LabelledTextImport.swift:127` has no minimum secret length.
>
> Only `GoogleAuthenticatorImport` enforces both, so the app is inconsistent with itself.
>
> Concrete call order: scan `otpauth://totp/x?secret=GEZDGNBV`, eight characters, five bytes, valid
> Base32, passes every check. The account works every day. Export an encrypted backup; the archive
> now carries `"secret":"GEZDGNBV"`, which the format declares invalid. Restore on a new device:
> `BackupPayload.swift:107` refuses the account. The same chain runs for a counter of 2^53.
>
> This is exactly the failure the format's whole design exists to prevent: discovered at restore,
> on a device that no longer has the originals, in the app's most carefully specified path. It
> needs no hostile input, a service that issues a short secret is enough, but a hostile QR code
> triggers it deliberately: an attacker who can get a victim to scan a code has planted an account
> that silently drops out of every backup.
>
> Smallest fix: enforce the floor and the ceiling in the three importers, mirroring the checks
> `GoogleAuthenticatorImport` already has; and make `BackupPayload.write` refuse rather than
> serialize a violating account, since stores may already contain one. Whether the URI path should
> refuse short secrets at enrollment is a policy choice; the writer emitting a nonconforming
> archive is not.
>
> **F2 — Low. The import front door narrows a frozen bound.** `ImportViewModel.swift:111` caps
> every imported file at 8 MiB before the archive sniff, but a conforming version-1 archive can be
> up to `BackupArchive.maximumFileBytes`, about 12.2 MB. Any archive whose plaintext exceeds about
> 6.2 MiB is refused with "That file is too large to be an authenticator export", on both the file
> picker and the share inbox. The comment block at `BackupArchive.swift:40-55` records this precise
> mistake being found and fixed inside `BackupArchive`, and the format document calls a narrowed
> frozen bound "the same offence as widening one and the direction that loses data". The routing
> layer has it today.
>
> **F3 — Low. A BOM-prefixed archive never reaches the passphrase prompt.**
> `ImportViewModel.looksLikeJSON` requires the first non-whitespace byte to be `{`. A UTF-8 BOM
> fails that, so the bytes fall through to the labelled-text reader and the user holding a mangled
> backup is told no accounts were found, never asked for a passphrase. The reader stack below this
> sniff is deliberately lenient about exactly this class of mangling; the sniff in front of it is
> stricter than the reader it guards.
>
> **F4 — Informational. The refusal reason lies for short-but-valid secrets.**
> `BackupPayload.swift:107-109` reports `.secretNotBase32` for a secret that decodes fine but is
> under ten bytes, and its user-facing description says the secret "contains characters that are
> not valid", which is false for that case. A person debugging a refused restore will look for a
> bad character that is not there.
>
> **F5 — Informational. `sortIndex` is read from every format and never applied.**
> `ImportViewModel.confirm` calls `store.add`, and `KeychainSecretStore.add` assigns its own
> append-at-end index, discarding the file's. Order survives round trips only because the export
> writer pre-sorts. Either apply the field or correct the `ImportedAccount` comment. Related nit:
> an unencrypted Aegis vault whose `db` object lacks `entries` is reported as "encrypted", sending
> the user to re-export a vault that was never encrypted.
>
> **On memory and control flow, no crash, trap, unbounded allocation, or non-terminating loop.**
> `ProtobufReader` bounds varints at ten bytes; a claimed length is compared against what remains
> before any copy, so "length = 4 GB" costs one comparison; nested messages are `Data` slices with
> non-zero `startIndex` and both readers index from `startIndex`; the recursive wire types are
> refused. `Base32.decode` checks the remainder class before decoding and never exceeds twelve bits
> of buffer. In `RichTextReader` I verified by execution that `UnicodeScalar(Int)` is failable and
> returns nil for surrogates and out-of-range values rather than trapping, and every branch of
> `readControl` returns an index strictly past its input so termination holds on any input. One
> resource note: `Array(rtf)` materializes about sixteen bytes per `Character`, so the 8 MiB cap
> admits a roughly 128 MB transient allocation, bounded and below jetsam but the largest
> attacker-scalable allocation in the app.
>
> **The backup format's cryptography holds, for stated reasons.** Lengths are enforced; the tag is
> verified with the format string as AAD before any plaintext is touched; GCM is all-or-nothing so
> a modified archive cannot produce a partial import, and nothing is written before the user
> confirms a preview. The KDF parameters are implicitly authenticated because they feed the key.
> The parse-as-payload requirement that mitigates AES-GCM's missing key commitment across the up to
> four derived keys is present and matches the documented attack history. Salt and nonce come fresh
> from `SecRandomCopyBytes` per archive with failure thrown and no fallback. **I re-derived both
> published test-vector keys independently with Python's `hashlib.pbkdf2_hmac`: both match the
> document byte for byte.**
>
> **Format confusion is refusal-safe.** Routing is content-based and first-match, and I could not
> construct an input that parses under the wrong reader: every collision resolves to a refusal or a
> wrong error message, never to wrongly imported accounts. One thing worth knowing: a hostile file
> can present as a locked archive and summon the passphrase prompt. Nothing follows from it, since
> the passphrase goes nowhere and there is no network.
>
> **An importer cannot touch existing data.** Every reader constructs an `ImportResult` and writes
> nothing; the sole write reachable from an import is `store.add`, which only ever `SecItemAdd`s a
> fresh UUID item. No update or delete is reachable, so a hostile file cannot overwrite, merge
> into, or destroy an existing account. Import is not atomic, but adds are purely additive and the
> finished count discloses what happened, so what remains is a subset of what was previewed. One
> observation for scope 1 rather than here: `classify` reads every stored secret into a
> `Data`-keyed dictionary, so the import preview is the one moment outside code generation when all
> secrets coexist in plaintext memory.
>
> **The bounds bound, with one exception in the wrong direction (F2).** Ciphertext string length
> before decoding, decoded length after, file bound before JSON, import gate before any parser,
> protobuf lengths before any copy. The entry points do not bypass each other: share-inbox bytes go
> through the same gate, scanned strings are camera-bounded, and the URL-scheme entry caps codes at
> 8 KB before any base64 work.

### Triage

**F1 confirmed, and proved end to end rather than read.** A probe was written against the core:
enroll `otpauth://totp/x?secret=GEZDGNBV` through the real URI parser, hand the result to
`BackupPayload.write`, then read the payload back with `BackupPayload.read`.

```
PROBE enrolled via URI. secret bytes: 5
PROBE writer produced a payload of 131 bytes
PROBE restored accounts: 0
PROBE refusals: [position 1, label "x", reason secretNotBase32]
```

The account enrolls, works, exports, and vanishes on restore. **This is the most serious defect
found in scope 3 and it is a data-loss path that requires no attacker**: a service issuing a short
secret is enough, and the loss is discovered on a new device that no longer has the originals.

**F4 is confirmed by the same run**, which is why the two belong together. The refusal reads
`secretNotBase32` for a secret that is unimpeachable Base32. Somebody debugging that restore is
sent looking for an invalid character that does not exist.

**F2 confirmed.** `ImportViewModel.swift:111` gates at `8 * 1024 * 1024` before the archive sniff,
while `BackupArchive.maximumFileBytes` is `maximumCiphertextCharacters + 1024 * 1024`. Two bounds
for one artifact, the outer one smaller, and the outer one is not the one the format froze. The
irony recorded in the pass is real: `BackupArchive`'s own comments describe this exact mistake
being caught inside the reader, and it now sits in front of it.

**F3 confirmed.** `looksLikeJSON` takes the first byte that is not ASCII whitespace and requires
`{`. A UTF-8 BOM's first byte is `0xEF`, which is not whitespace and is not `{`, so a BOM-prefixed
archive is routed to the labelled-text reader and its holder is told no accounts were found. The
layer below strips exactly this BOM, deliberately, because recovery files get mangled; the sniff
above it does not.

**F5 confirmed.** `sortIndex` is carried into `ImportedAccount` and then discarded by
`KeychainSecretStore.add`, which assigns `(existing.max ?? -1) + 1`. Order survives only because
the export writer happens to pre-sort.

**Nothing was rejected.** The pass also did two things worth noting beyond its findings: it
re-derived both published test-vector keys independently in another language, which is the first
external check of those vectors, and it verified `UnicodeScalar(Int)`'s failability by executing it
rather than assuming it, which is the difference between believing a parser is trap-free and
knowing it.

---

## Grok 4.6

*Read-only pass over commit `74fe841`. Reproduced as returned, abridged in the sections
enumerating what held.*

> I would rather file two defects that I can point at than a survey. Both are in the import entry
> point, which is the only place the parsers actually meet the user.
>
> **Finding 1 — High. The 8 MiB cap is applied after the file is already in memory, and it is
> tighter than the format's frozen ceiling.**
>
> **1a. The bound runs after the allocation it claims to prevent.** `read(_ url:)` does
> `Data(contentsOf: url)` first. That copies the whole file. The `8 * 1024 * 1024` check is the
> next line of a different method. Call order, from either the document picker or "Open in
> OpenFactor": `InboxOpener.arrival(from:)` returns `.file(url)` with no size check;
> `ImportView.init` calls `model.read(url)`; `Data(contentsOf:)` allocates whatever the URL names;
> only then does `read(_ data:)` look at `data.count`.
>
> A 400 MB attachment opened into this app is a 400 MB allocation. The comment on `read(_ data:)`,
> "Bounded before anything parses it", is true about parsing and false about the thing that
> actually hurts: the copy. On a phone that allocation is a jetsam, not a "too large" message.
>
> I did not run this to jetsam. I did read both call sites. There is no `fileSize` resource-value
> check, no `FileHandle` cap, and no `.alwaysMapped`. `BackupArchive.read` does check `data.count`
> first, but it never sees a file the UI refused to finish loading.
>
> **1b. The same number silently retires the format's frozen ceiling.** [As recorded in the Fable
> pass.] Gate A3 found exactly that mistake inside `BackupArchive.read` and it was fixed;
> `ceilingSizedArchivesArePassedOn` proves the reader no longer refuses a ceiling-sized ciphertext.
> That test never goes through `ImportViewModel`. Even a 6 MiB payload already encodes to 8,388,608
> characters of base64, and the wrapper pushes the file over the UI cap. A person holding a valid
> version 1 archive produced by any writer that followed only the document gets "That file is too
> large to be an authenticator export." The passphrase screen is never shown. The file is
> indistinguishable, to the owner, from garbage. That is the same class A3 called blocking, moved
> one layer up.
>
> Smallest fix: refuse on `URLResourceValues.fileSize` before `Data(contentsOf:)`; and do not apply
> 8 MiB to a file that is an OpenFactor archive, either by sniffing `format` first or by letting
> `BackupArchive.read` enforce the format's own three checks in order. Keep 8 MiB for Aegis and
> labelled text if you want a policy bound there; those formats never claimed the frozen ceiling.
> The existing ceiling-sized test should drive `ImportViewModel.read(_:)`, not only
> `BackupArchive.read`.
>
> **Finding 2 — Medium. Aegis and labelled-text import will accept a secret shorter than RFC
> 4226's 10-byte floor, and the import preview does not show a code, so the failure is silent
> until a login.** `Base32.decode("GEZDGNBV")` succeeds. That account is offered as "Will be
> added"; `ImportView.review` draws issuer and name only, unlike the single-account confirmation
> screen, which shows a live code. A damaged export that lost the tail of a secret takes the same
> path, and that is the truncated-secret case the backup reader was written to refuse.
>
> `OTPAuthURI.account(from:)` and manual setup have the same missing floor, but both show a live
> code before save. **I am not promoting those to this finding.** The file preview is the path
> where the user cannot see the failure.
>
> **On the entry points.** URL schemes are bounded before the expensive work, at 8,192 bytes, and
> that is the path any other app on the device can drive. The share extension checks 8 MiB after
> `loadDataRepresentation` returns, the same shape as 1a with a smaller blast radius. **The in-app
> PhotosPicker path has no size check at all**, straight into `CIImage(data:)`. A different entry
> point, unbounded. I did not make this a third finding because it is the same mistake as 1a on a
> path that only feeds a QR detector, not the vault.
>
> **On what an importer can do to existing data.** Importers return an `ImportResult` and write
> nothing; `confirm` calls only `store.add`, which mints a new UUID and does `SecItemAdd`, never
> update, never delete, never reusing an identifier. A hostile file cannot overwrite a secret,
> rename an account, or empty the vault. Import is not atomic, but that is a partial add, not a
> partial destroy.
>
> **One user-facing sentence is false.** After any file import, including an encrypted
> `.openfactor` archive, `ImportView.finishedAdvice` for `.file` says "That file contains your
> secret keys in the clear." An archive does not. It does not change what is stored, but **it can
> talk someone into deleting the only copy they just proved they can open.**
>
> **What I measured rather than assumed.** `JSONSerialization` throws at nesting depth 512 rather
> than overflowing the stack, so a hostile 8 MiB JSON file is a parse failure once loaded. And I
> checked the Aegis HOTP counter path before declining to file it: Foundation keeps large integers
> as `SInt64`, and `JSONDecoder` returned 9007199254740993 and even `UInt64.max` exactly, so there
> is no silent counter corruption to report.

### Triage of the Grok 4.6 pass

**Finding 1a confirmed, and it is the more serious half of the finding.** `read(_ url:)` at line 94
does `Data(contentsOf: url)` and calls `read(data)` at line 99; the cap is the first statement of
that second method. The comment above the cap says the file is "bounded before anything parses
it", which is true and beside the point: the allocation is the cost, and it is already paid. This
was missed by the pass that found 1b, which read the bound but not the order of the two methods.

**Finding 1b confirmed**, matching the other pass independently.

**Finding 2 confirmed**, overlapping the other pass's F1 by root cause but scoped differently and
arguably better. Where the other pass followed the short secret into the backup and out again,
this one stops at the preview and observes that the file-import screen shows issuer and name
without a code, so nothing on screen can reveal that the account will never work. **Both are
right, and the two together describe the whole defect**: it enters silently, and it leaves
silently.

**The engines disagree on scope, and the disagreement is a judgment rather than a contradiction.**
The other pass included `otpauth://` in the finding; this one deliberately excludes it, because
that path shows a live code before saving. That reasoning is sound. It does not change the fix,
since a shared floor is one helper either way, but it is worth recording that one engine drew the
line at "can the user see it fail" and the other at "does the format forbid it".

**The unbounded PhotosPicker path is confirmed and is worth more than the pass gave it.**
`AddAccountViewModel.handleImage` goes straight to `QRDecoder.payloads(in:)` and `CIImage(data:)`
with no size check, while `OpenFactorShare/ShareViewController.swift:66` caps the same kind of
input at 8 MiB. Two paths to one decoder, one bounded and one not, and the unbounded one is the
in-app path.

**The false advice string is confirmed and is the item this triage rates highest of the three
smaller ones.** After importing an encrypted archive, the app tells its owner the file contains
their secret keys in the clear and advises deleting it. That is false for the one file format this
project designed to be safe to keep, and acting on the advice destroys a recovery artifact whose
correctness the person has just personally verified by opening it. The pass declined to give it a
severity; on the evidence it deserves one.

**Nothing was rejected**, and two of the pass's non-findings are worth keeping for the discipline
they show: it measured `JSONSerialization`'s nesting behaviour rather than assuming a stack
overflow, and it checked `JSONDecoder`'s large-integer handling before declining to report a
counter bug it could not produce.

---

## ChatGPT 5.6 Sol

*Read-only pass over commit `74fe841`. Reproduced as returned.*

> **1. Medium — valid large backups cannot be restored, and exports can create them.**
> `ImportViewModel.read(_:)` rejects every file over 8 MiB before recognizing its format, while
> `BACKUP_FORMAT.md` permits up to 8 MiB of decoded ciphertext, about 11,184,812 Base64
> characters, and `BackupArchive` allows containers around 12 MiB. **`BackupArchive.write` also
> does not reject plaintext over its own 8 MiB limit, so the app can export a backup that its
> importer refuses.** The same whole-file guard can reject otherwise-valid archives containing
> large ignored fields. Use a format-specific bound and enforce the plaintext limit before sealing.
>
> **2. Medium — file size is checked only after the entire file is loaded.**
> `ImportViewModel.read(_ url:)` calls `Data(contentsOf:)` before the 8 MiB check. A hostile file
> provider or user-selected multi-gigabyte file can consume memory and I/O before the intended
> bound runs. Read through a bounded stream, or preflight and then enforce a bounded read to handle
> races.
>
> **3. Medium — a crafted Google migration payload crashes the app through integer overflow.**
> Payload bytes `0a 00 20 ff ff ff ff ff ff ff ff ff 01`, URL-safe Base64 `CgAg____________AQ`,
> contain an empty account record plus `batch_index = UInt64.max`.
> `GoogleAuthenticatorImport.read` clamps this to `Int.max`; `Batch.position` then evaluates
> `index + 1`, trapping. The normal URL entry point accepts this payload, and `ImportView` accesses
> `batch.position`. Reject out-of-range indices, and inconsistent `index >= size`, before
> constructing `Batch`, or use checked arithmetic.
>
> **4. Low — duplicate records within one hostile import bypass duplicate detection.**
> `classify` compares each imported account only with records already stored, not with earlier
> candidates from the same file. A file containing the same account twice marks both as `.new`;
> `confirm` then calls `store.add` twice, creating two UUID-backed cards generating identical
> codes. Deduplicate candidates using secret plus generator parameters, or recheck that fingerprint
> while confirming.
>
> **5. Low — format sniffing rejects valid JSON and can route text to the wrong parser.**
> `looksLikeJSON` examines only the first 512 bytes. A valid JSON, Aegis, or archive file with more
> than 512 leading whitespace bytes is sent to the labelled-text parser and rejected, despite the
> format document saying whitespace is insignificant. Conversely, RTF preceded by whitespace is
> classified as JSON and fails as "not Aegis" without trying the RTF reader. Scan leading
> whitespace and BOM across the bounded input, and preserve a fallback between JSON and text
> parsing.
>
> **What held up.** The backup cryptographic sequence is sound: required fields and KDF bounds are
> checked before PBKDF2; AES-GCM authenticates the format string; plaintext is parsed only after
> authentication; and the passphrase hint is advisory. Protobuf length-delimited fields are checked
> before slicing or copying, and malformed varints are bounded. Import parsing performs no writes
> until explicit confirmation, and existing records are neither overwritten nor deleted.

### Triage of the ChatGPT pass

**Finding 3 is the standout of this entire scope, and it was reproduced rather than reasoned
about.** The exact payload was assembled, wrapped in an `otpauth-migration://` URL, and run
through the real parser:

```
PROBE uri: otpauth-migration://offline?data=CgAg%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FAQ%3D%3D
PROBE parsed. size: 1 id: 0
PROBE about to evaluate position = index + 1
```

The process then died with signal 5. `position` never printed.

**This is a crash any app on the device can trigger with a single URL.** `otpauth-migration://`
is a declared scheme, so no user action beyond opening the link is required. It is a denial of
service rather than memory corruption, because a Swift overflow trap is a controlled abort, but it
is trivially reachable and it is the first crash found anywhere in this project.

The mechanism is a clamp that hides an inconsistency instead of refusing it.
`Int(clamping: value)` turns `UInt64.max` into `Int.max`, which is a valid `Int` and a nonsensical
batch index, and `position` then adds one to it. Neither engine that reviewed this file before
found it, and both had examined `ProtobufReader`'s bounds carefully; the defect is not in the
parser but in the value the parser was allowed to hand onward.

**Findings 1 and 2 confirmed**, matching the other two passes on the bound and its ordering.
**Finding 1 adds something neither other pass had:** `BackupArchive.write` does not enforce its own
8 MiB plaintext limit before sealing, so the app can produce an archive that exceeds the format and
that its own importer will refuse. That is the same defect as scope 3's first finding, in the
other direction: the writer emitting something the reader must reject.

**Finding 4 confirmed.** `classify` reads `store.records().readable` and compares each candidate
against `existing` only. Two identical accounts in one file are both `.new`, and `confirm` adds
both. A hostile file can therefore plant a pile of identical cards, and an honest but duplicated
export produces silent duplicates.

**Finding 5 confirmed, and it completes the picture the other pass started.** `looksLikeJSON`
inspects `data.prefix(512)`. The other engine found that a BOM defeats the sniff; this one found
that so does 512 bytes of leading whitespace, and that RTF behind whitespace is misrouted to the
Aegis reader with no fallback. One sniff, three ways to defeat it, found by two engines from
different directions.

**Nothing was rejected.**

### What this scope says so far

The three earlier scopes found defects in the code that reads hostile bytes. **This one found the
readers sound and the code around them wrong**, which is the same shape scope 2 produced and is
becoming the pattern of this gate: the audited artifact holds and its neighbours do not.

F1 is the sharpest example. The backup format is the most carefully specified thing in this
project, with a frozen document, published vectors, and a reader that enforces every rule. The
defect is that nothing enforces those rules on the way *in*, so the app can hold an account it
cannot back up, and only says so when it is too late to matter.

### Not yet acted on

## Scope 3 complete

| Finding | Fable 5 | Grok 4.6 | ChatGPT |
| --- | --- | --- | --- |
| Enrollment accepts what the format forbids | Found | Found, file paths only | Missed |
| Migration payload crashes the app | Missed | Missed | **Found** |
| 8 MiB cap narrows the frozen ceiling | Found | Found | Found |
| The cap runs after the file is loaded | Missed | Found | Found |
| The writer can emit an over-size archive | Missed | Missed | Found |
| Duplicates within one file bypass detection | Missed | Missed | Found |
| The JSON sniff is defeatable | Found, by BOM | Missed | Found, by whitespace and RTF |
| Refusal reason lies for a short secret | Found | Missed | Missed |
| PhotosPicker path is unbounded | Missed | Found | Missed |
| "Secret keys in the clear" is false for an archive | Missed | Found | Missed |
| `sortIndex` is read and discarded | Found | Found | Missed |

**One finding was reported by all three.** The only crash in the project was found by exactly one
engine, and so were four of the eleven items. Two engines examined `ProtobufReader`'s bounds in
detail and declared them sound, correctly, while the defect sat one layer above in a value the
parser was permitted to hand onward.

### Not yet acted on

**Nothing has been changed.** Fixes begin when round one is complete, and the crash joins the
ordered list at the top: it is the only finding in this gate that an unrelated app can trigger
without the owner doing anything.
