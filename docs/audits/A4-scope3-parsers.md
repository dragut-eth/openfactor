# A4, scope 3: everything that parses bytes somebody else wrote

Gate A4 round one, the scope covering the backup format, the three importers, the URI parser, and
Base32. The prompt is `docs/audits/A4-prompts.md`, preamble plus Scope 3, unchanged.

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
| ChatGPT 5.6 Sol | Not yet run |
| Grok 4.6 | Not yet run |

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

### What this scope says so far

The three earlier scopes found defects in the code that reads hostile bytes. **This one found the
readers sound and the code around them wrong**, which is the same shape scope 2 produced and is
becoming the pattern of this gate: the audited artifact holds and its neighbours do not.

F1 is the sharpest example. The backup format is the most carefully specified thing in this
project, with a frozen document, published vectors, and a reader that enforces every rule. The
defect is that nothing enforces those rules on the way *in*, so the app can hold an account it
cannot back up, and only says so when it is too late to matter.

### Not yet acted on

**Nothing has been changed.** ChatGPT and Grok run this scope against the same commit. Fixes begin
when round one is complete.
