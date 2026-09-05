# X3: a third blind, unscoped audit of the whole repository

**This is not gate A5**, for the same reason X1 and X2 were not: A5 is the diff since `audit-a4`,
run before each release, and it still wants doing. This was a cold pass over the entire repository
at one commit by a reader with no brief from this project and no sight of `docs/audits/`.

**Audited commit:** `b6731428d44c0f7e209c1628406a810e7baae3ed`, the head of `main` on 2026-09-04.
**Reviewer:** GPT 6-Astra, with a read-only checkout, told not to modify anything.
**Reported:** 2026-09-05.

## The prompt, verbatim

X1's prompt, changed only in the directory it names. Three cold readers, three lineages, one brief,
which is what makes the three reports comparable.

> checkout https://github.com/dragut-eth/openfactor.git, in this directory: /tmp/x3-audit readonly
> Record the commit hash you audited.
> Perform an independent security audit of this repository. Start by reading the README and
> security/design documentation to understand the claimed security properties, then inspect the
> actual implementation, entitlements, and tests and try to falsify those claims. Do not assume
> the documentation is correct. Do not read docs/audits/ until you have completed and written down
> your own findings, to avoid being biased by previous reviews. Report each finding with severity,
> affected code, reasoning, and a concrete attack or failure scenario where possible. Also report
> important security claims you were able to verify and claims you could not verify. Do not modify
> any files.

## What is different about this reviewer, and why it found more

**It is the first reviewer in the series from a lineage with no hand in this code**, which X2's
own caveat named as what the series was missing. And **it ran things rather than reading them**:
every finding below carries a probe output, including a reproduced fatal error and an actual
counter value. X1 and X2 were careful readers and found no Medium between them. This reviewer found
three, all in behaviour that a reader can reason past and an executed probe cannot.

**Its own stated limits are worth keeping.** The full core suite timed out in its environment and
it counted 147 tests across 12 selected suites instead, and said so rather than rounding up. No
hosted iOS tests and no physical device. The iOS delivery and backup half of OF-X3-01 is inferred
from Apple's documentation, not observed.

## Result

**Three Medium and two Low. All five confirmed against the source before being accepted, none
withdrawn.** Three consecutive cold readers, no false positives.

**Two corrections to the report's own framing, both making it more serious.** OF-X3-01 needs no
adversary at all, where every other finding in three audits needed a same-team sibling this project
had already accepted; by this project's threat model it is the most serious thing the series has
found. And OF-X3-02's trap was old but rarely reachable until this project's own foreground reload,
added five days earlier for E16, made the second load happen on every return to the app. The
reviewer audited HEAD without the history and could not have known that.

| ID | Theirs | This project's reading |
| --- | --- | --- |
| OF-X3-01 | Medium | The highest here: plaintext secrets, backed up, no attacker required |
| OF-X3-02 | Medium | A crash this project made far more reachable |
| OF-X3-03 | Medium | Medium |
| OF-X3-04 | Low | Low |
| OF-X3-05 | Low | Low |

## OF-X3-01, medium: imported plaintext files remain outside the encrypted vault

**Confirmed. Open.**

`LSSupportsOpeningDocumentsInPlace` is false, so a document opened into the app arrives as a copy
in `Documents/Inbox`, a location Apple documents as backed up. The import reads it and never
deletes it. Cleanup exists for the App Group inbox and for the Exports directory and reaches
neither this directory nor this file. Erasing accounts does not touch it either.

**Why this outranks the reviewer's own Medium.** Every other finding in X1, X2 and X3 needed a
same-team sibling with Keychain access, an adversary this project accepted in `SECURITY.md`. This
one needs nobody. Import a plaintext Aegis export, a documented and supported path, and every
secret in it sits in the clear in a backed-up directory after the import, after the original is
deleted, and after the accounts are erased. The app's central claim is that secrets are encrypted
before they are stored. Here they are stored unencrypted somewhere the app never looks again.

**The reviewer's limit stands as stated:** the retention was reproduced against the real import
model; the iOS delivery and backup consequence follows from the configured behaviour and Apple's
documentation and was not observed on a device.

## OF-X3-02, medium: duplicate account UUIDs crash the account list on reload

**Confirmed. Addressed, with the storage question left open on purpose.**

`kSecAttrSynchronizable` is part of a Keychain item's primary key, so the same account can exist
once in each sync slot: anything able to write the group can copy a valid item across with its UUID
and ciphertext intact, and both still authenticate. `records()` returns both. The first `load`
carried both rows. The second built `Dictionary(uniqueKeysWithValues:)` over them and trapped on
the duplicate key, inside a `do` that cannot catch a trap. The reviewer reproduced the fatal error
against the real view model.

**What this project added to the finding.** The trap was old. Until 2026-09-02 the second load
needed a sheet to open and close, or the view to be recreated. E16's foreground reload runs `load`
on every return to the app, and the boundary reload runs it again after any code failure. A
condition that took deliberate navigation to reach became a crash on the next launch, repeatedly.
This is the interaction X2's verification round was positioned to catch and did not, because it
read a diff rather than reaching for a duplicate.

**What was changed.** The dictionary is built with `uniquingKeysWith`, keeping the first row, and
the listing is deduplicated by identifier before rows are made, so one account shows once however
many items carry it and nothing traps. A test hands the view model a store whose listing returns
every record twice and loads it three times; finishing is the assertion.

**What was not changed, and why it is recorded rather than decided.** The reviewer asks for an
explicit conflict policy at the storage boundary: which slot wins when both hold the same UUID.
That is a real question and the display fix does not answer it, it only stops the answer from
being a crash. Nothing here deletes either item. Choosing a winner means choosing which of two
authenticating records to destroy, on inference, and the last time this project faced that shape,
the surviving twin in `unlock`, it chose to keep both. The policy is open.

## OF-X3-03, medium: advancing an accepted HOTP counter makes the vault unexportable

**Confirmed. Open.**

Enrolment accepts a counter up to `AccountLimits.maximumCounter`, `2^53 - 1`, the largest integer
the backup format can hold. `advanceCounter` checks only for `UInt64` overflow, so one advance from
the ceiling persists `2^53`. The encrypted backup writer then refuses the whole export with
`cannotStoreAccount`, by design, because it holds that a backup missing accounts is worse than none.
The reviewer's probe: import the URI at the ceiling, advance once, export refused, plaintext
re-import refuses the account.

**The two limits were each tested and never connected**, which the reviewer noted and which is the
useful part. A crafted enrolment, after one ordinary tap, disables backups of every unrelated
account.

## OF-X3-04, low: Google Authenticator batch identifiers are incorrectly capped

**Confirmed. Open.**

One bound, `maximumBatchField`, is applied to protobuf fields 3, 4 and 5: batch size, batch index
and batch identifier. The comment beside it reasons about how many QR codes a person could scan,
which is a bound on a count and not on an identifier. A valid transfer carrying a large identifier
is refused whole as malformed, and the existing bounds test pins the wrong behaviour.

## OF-X3-05, low: one malformed Aegis entry rejects the whole file as encrypted

**Confirmed. Open.**

`Database.init(from:)` tries to decode the whole `Contents` and falls back to `.encrypted` on any
failure, so one entry with a string where a number belongs makes the entire plaintext file report
as encrypted, with advice to disable encryption that cannot help a file that has none. It
contradicts `ImportResult`'s own words, that a file of ten where one is unusable must still yield
nine. The per-entry refusal loop exists and is reached only after the decode that defeats it.

## What the audit verified

At source and by executing selected suites: separate AES-GCM seals with UUID-bound AAD and fresh
nonces on every normal Keychain write; listing opening only the metadata half; the watch exchange
binding version, nonce and both public keys into the derivation and the AAD, with substitution and
malformed-message tests passing; backup cryptography matching the published vectors; 120 bits of
system randomness behind a generated passphrase, with the failure checked; no third party packages
and no direct network or logging code; extensions lacking the vault's Keychain group, with the
accurate qualification that this does not mean no Keychain group at all.

## What it could not verify

Signed-release entitlements and correspondence with an App Store binary; container isolation
against a signed sibling, file protection on a locked device, and backup exclusion through restore
or Quick Start; WatchConnectivity exclusivity against a rogue counterpart; multi-device sync races
and deletion propagation, which E16 has since measured on hardware; snapshot, capture and App Lock
behaviour on a device; the account tripwire, which it correctly reports as absent; and secure
zeroisation of secret bytes, which Swift object lifetimes do not provide.
