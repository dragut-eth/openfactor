# A4 round two, scope 3: what three engines found in the fixes

Round two of scope 3 read `6254706`. The account it responded to is `A4-round-two-scope3.md`, and
all three engines returned.

| Engine | Verdict |
| --- | --- |
| Grok 4.6 | One medium, two low. "Three of the eleven fixes handle the instance and leave the class open" |
| ChatGPT 5.6 Sol | Two medium, two low |
| Fable 5 | Nine of eleven genuinely fixed; one medium, four low, one informational |

**All three rejected the same fix, for the second round running.** In scope 4 it was the mtime
clamp. Here it is the writer's ceiling check, and the agreement is again on mechanics rather than
on judgment.

**And for the fourth review round in a row, nothing new is high severity.**

## The rejected fix

**S3-5: the writer bounds the container, and the reader bounds the plaintext.**

The finding was that this app could write an archive it would not read back. The fix added a guard
after sealing:

```
guard archive.count <= maximumFileBytes else { throw BackupError.tooLarge }
```

`maximumFileBytes` is 12,233,388, the whole JSON container. The reader's binding rule is a
different quantity: it refuses decoded ciphertext above `maximumPlaintextBytes`, 8,388,608. GCM
ciphertext is the length of its plaintext, so a payload one byte over 8 MiB still serialises to a
container comfortably under 12.2 MiB. **It writes. It does not read back.** Grok gives the call
order and ends it where it hurts: the originals are on the old phone.

Round one's finding named the fix precisely, "enforce the plaintext limit before sealing", and what
shipped checks a different number in a different place. Fable's phrasing is the one to keep: a fix
that moved a check without checking the thing the finding named, which is the specific shape this
round exists to catch. The comment above it, "the writer refuses what the reader must refuse", is
false inside that window.

There is no test that the writer refuses an oversize payload.

## The two fixes that closed one instance and left another

**S3-7, the sniff.** Round one recorded three ways to defeat it. The byte order mark and the RTF
guard running before the whitespace skip are both closed, verified by all three. The third,
**more than 512 leading whitespace bytes**, is untouched: `JSONSniff` drops whitespace only within
`body.prefix(512)`. ChatGPT named that exact case in round one. So a conforming archive whose only
crime is leading whitespace still routes to the labelled-text reader, and its holder is told no
accounts were found rather than being asked for a passphrase.

**S3-8, the lying refusal reason.** Fixed in the URI parser, Aegis, labelled text and
`BackupPayload`. Missed in `GoogleAuthenticatorImport`, which still reports "contains characters
that are not valid" for a payload of **raw bytes**, where there are no characters at all. The same
lines hardcode `10` instead of reading `AccountLimits.minimumSecretBytes`, which makes that type's
own claim that "there remains exactly one definition" false. The commit that missed it was titled
"the class sweep, not just the instances".

## What round two added

| # | Finding | Severity | Engines |
| --- | --- | --- | --- |
| S3-12 | manual entry accepts what the format forbids, and the export failure blames the past | medium | Grok, Fable |
| S3-13 | the in-memory bound now runs after a full JSON parse | low | Fable |
| S3-14 | the size preflight fails open when the file system will not give a size | medium | ChatGPT |
| S3-15 | four comments claim what the code does not do, two of them written this round | low | Grok, Fable |

**S3-12 is the one that matters.** `AccountLimits` was created so one rule about what an account is
would have one home, and the round-two account said all four enrollment paths read it.
`ManualSetupViewModel` reads neither rule: any decodable non-empty Base32 secret, any `UInt64`
counter. So the class the fix claimed to close is open through the front door, and it is the door
somebody uses when a service prints a secret, which is when a short one is most likely.

What makes it worse is the interaction with the writer guard, which is itself correct. Type in a
short secret today, and every future export fails with `cannotStoreAccount`, whose comment says
"only reachable for an account enrolled before the enrollment paths enforced these rules" and
whose user-facing message says "it was saved before OpenFactor checked for this". Both are false
for an account saved five minutes ago, and **the message then advises re-adding the account from
the service, through the same unguarded screen that created the problem.**

Grok and Fable disagree about severity, and the disagreement is worth keeping: Grok declines to
promote it, on the grounds that the failure now happens at export while the originals are still on
the phone, which is the right moment. Fable files it medium because the class is open and the
explanation is untrue. Both agree the sentence has to change.

**S3-13 is a defect the fix introduced**, and it is the scope's own pattern reappearing inside the
commit that was fixing it. Reordering `read(_ data:)` so the format decides the bound put
`looksLikeOpenFactorArchive` first, and that runs a full `Data` copy plus a complete
`JSONSerialization` parse **before** `ImportLimits.isWithinBound` is consulted. On the path where
the file system gave a size this is harmless. On the path the account itself disclosed as a
residual, the unbounded allocation is now an unbounded parse as well.

**S3-15 includes a comment two engines disproved by running Foundation rather than reading it.**
`JSONSniff` says the stripped bytes are returned "because `JSONSerialization` refuses a leading
mark too". It does not: both Grok and Fable handed it BOM-prefixed JSON and got an object back.
The archive path works *because* that comment is wrong, since `read(_ data:)` stores the unstripped
bytes and `BackupArchive.read` parses them mark and all. The others are "saturating add" on `&+`,
which wraps; `AccountLimits`'s "exactly one definition"; and the round-two account's own "all four
enrollment paths read them".

## The eleven, as the three engines left them

| # | Finding | Disposition |
| --- | --- | --- |
| S3-1 | enrollment accepts what the format forbids | restore-loss path closed, all three. The manual door is S3-12 |
| S3-2 | migration crash | closed, all three, with the reproducer pinned |
| S3-3 | the cap retired the frozen ceiling | closed |
| S3-4 | the bound ran after the copy | closed for a URL that reports a size. The fail-open is S3-14 |
| S3-5 | the writer can emit an unreadable archive | **not closed. All three rejected it** |
| S3-6 | duplicates within one file | closed, interleavings checked |
| S3-7 | the sniff is defeatable | **two of three instances closed. The 512-byte window remains** |
| S3-8 | the refusal reason lies | **fixed in four readers, missed in the fifth** |
| S3-9 | the picker path is unbounded | closed, with an honest comment about what it cannot bound |
| S3-10 | "secret keys in the clear" is false for an archive | closed, lifecycle checked for a stale flag |
| S3-11 | `sortIndex` discarded | closed, including the stable-sort argument for formats that set none |

## What this round says about the method

**Two rounds, two unanimous rejections, and both were plausible one-line answers to the finding as
worded.** The mtime clamp answered "it claims to be newer than now" and the writer guard answered
"the archive is too big", and in each case the wording was not the defect. That is now a pattern
worth naming rather than a coincidence: **the fix should be checked against the failure sequence,
not against the sentence describing it.**

**A fix reintroduced the very pattern it was fixing, one function away.** S3-13 is a bound checked
after an expensive operation, added by the commit whose purpose was moving bounds in front of
expensive operations.

**Two engines settled a claim by measurement.** Neither argued about whether `JSONSerialization`
accepts a byte order mark; both ran it. That is the standard this project asks of itself and it
took outside reviewers to apply it here.

---

# What was done

**The code under review is `fc844aa`.** All six open items are fixed, and one needed nothing. The
tip of `a4-fixes` differs from it only in this file, which is where the account you are reading
lives.

**S3-5, the fix all three rejected.** The plaintext is bounded before sealing. The rule had no seam
a test could reach without building eight mebibytes of accounts, **which is why the first attempt
checked the quantity that was reachable**: the finished container. `write` is now split so `seal`
takes a payload, and the boundary is tested from both sides. Removing the guard reddens the test.

**S3-7.** Whitespace is dropped across the whole input. The input is already bounded by
`ImportLimits` before it reaches the sniff, so the 512-byte cap protected nothing and refused
conforming archives.

**S3-8.** `GoogleAuthenticatorImport` reads `AccountLimits` and reports `secretTooShort`. Its test
asserted the wrong reason, so the test changed with the code.

**S3-12.** Manual entry applies both limits, in the problem messages *and* in the account the form
describes, so a form showing no problem cannot still describe an account the format refuses. With
the door closed, `BackupError`'s message no longer claims the account "was saved before OpenFactor
checked for this" and no longer advises re-adding it through the screen that caused it.

**S3-13.** One cheap bound before the format is recognised, which is the pattern the reorder that
introduced it existed to remove.

**S3-14 needed no work.** Closing scope 4 made all three of its call sites fail closed: the import
preflight, the extension's preflight, and `take`'s handle-based read.

Each fix was reverted individually and its test confirmed red. **One of those checks caught a test
that was not running at all**: four new tests had been appended to the wrong suite in the same
file, and a filter naming a suite that does not exist reports success rather than failure, which is
the same shape as every other false green this gate has found.

## For round three

The three questions, and the fourth about convergence.

**`BackupArchive.write` was split to make a bound testable.** That is a refactor of the writer for
the sake of a test, which is exactly the kind of change that can be faithful and still wrong. Check
that `write` and `seal` compose to what `write` did before.

**Manual entry now refuses rather than truncates**, unlike the importers, which truncate. Both
choices are defended in comments; ask whether the inconsistency is right. A person looking at a
field can correct it, and a file cannot.

**The sniff no longer caps how much whitespace it will skip.** The bound is entirely
`ImportLimits`', one layer up. Check that nothing reaches `JSONSniff.body` without passing it.

**S3-14 was closed by work in another scope**, so nobody has reviewed those three call sites
against this scope's own question about what an importer does with hostile bytes.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Grok:
A4, scope 3, round two

Code reviewed: 6254706
Checkout: cf356d9 (differs from 6254706 only in HANDOFF.md and the scope 3 file list in A4-prompts.md)
Round one read: 74fe841
Fixes themselves: 19310b5, 43103dc, a848a88, f5658fa (source is the same at 8471c33 / 6254706)

Nothing in the repository was modified.

───

The crash is closed. The restore-loss path that needed no attacker is closed at the writer, and at three of the four enrollment doors. The 8 MiB UI cap no longer retires the format’s ceiling. Duplicate detection now looks inward as well as at the store. The done screen no longer tells someone to delete the backup they just opened.

Three of the eleven fixes handle the instance and leave the class open. One of those is the same defect ChatGPT filed against the writer, still reachable.

───

Finding 1 — Medium

The writer still emits an archive its own reader must refuse. The check they added measures the container, not the plaintext the format froze.

Sources/OpenFactorCore/Backup/BackupArchive.swift, write, the guard at the end:

        // **The writer refuses what the reader must refuse.** Nothing checked this, so the app
        // could produce an archive it would not read back, and the person holding it would find
        // that out on the device they were restoring to. A review found it by reading the two
        // halves against each other; the format states the ceiling as an obligation on both.
        guard archive.count <= maximumFileBytes else { throw BackupError.tooLarge }

ChatGPT’s finding 1, accepted in triage: BackupArchive.write does not reject plaintext over its own 8 MiB limit. The requested fix was “enforce the plaintext limit before sealing.” Round two’s account of the change says that finding is fixed.

What shipped is a check that archive.count <= maximumFileBytes (12,233,388), after sealing. The reader still has a separate, stricter rule:

        guard ciphertext.count <= maximumPlaintextBytes else { throw .tooLarge }

maximumPlaintextBytes is 8,388,608. GCM ciphertext is the same length as the plaintext. A payload of 8,388,609 bytes therefore:

1. Encodes to 11,184,812 base64 characters — the same string length as a legal 8 MiB payload, because 8,388,608 leaves a remainder of 2 and already occupies a full final quartet.
2. Produces a pretty-printed container well under 12.2 MiB.
3. Passes the new writer guard.
4. Fails ciphertext.count <= maximumPlaintextBytes on read.

Call order: ExportViewModel.export → BackupArchive.write succeeds → person stores the file → new device → ImportViewModel recognises it (it is under the frozen container ceiling) → passphrase screen → BackupArchive.read throws .tooLarge. The originals are on the old phone.

That is the defect they said was closed, with the check moved to a different number. There is no test that the writer refuses an oversize payload. BackupArchiveTests only proves the reader refuses a 13 MiB blob and an overlong ciphertext string.

Smallest fix: before AES.GCM.seal, guard plaintext.count <= maximumPlaintextBytes else { throw .tooLarge }. The container check can stay; it is a different bound.

I did not construct an 8 MiB-plus account list. The inequality does not need one. The same “fifty thousand accounts” argument was why the reader’s narrowed ceiling survived until A3, and they correctly refused it then.

───

Finding 2 — Low

JSONSniff is still stricter than the parser it guards, on the exact axis ChatGPT named.

Sources/OpenFactorCore/Import/JSONSniff.swift, body(of:):

        let head = body.prefix(512).drop(while: \.isASCIIWhitespaceByte)

        if head.starts(with: Array("{\\rtf".utf8)) { return Data() }
        guard head.first == UInt8(ascii: "{") else { return Data() }

        return Data(body)

BOM is stripped. A few spaces are skipped. The RTF check now runs after both. Those two reported cases are fixed; I confirmed the tests hit them.

The 512-byte window is not. I ran Foundation on this machine:

• JSONSerialization.jsonObject accepts a leading UTF-8 BOM, 20 spaces, 512 spaces, and 513 spaces.
• The sniff, given 512 0x20 bytes then {"format":…}, returns empty (empty-not-brace).

So a conforming archive (or Aegis vault) whose only crime is 512 bytes of leading whitespace — the format says whitespace is not significant — is still routed to labelled text and reported as “could not find any accounts.” The holder is never asked for a passphrase.

Round one found three ways to defeat one sniff. Two were closed. The third was the one ChatGPT wrote down: “more than 512 leading whitespace bytes.” JSONSniffTests.leadingWhitespace uses "  \n\t".

Smallest fix: skip whitespace (and the BOM) over the whole input, then inspect the next five bytes. Do not cap the skip at 512.

The comment in the same function is also false, and the preamble puts that in scope. It says the stripped bytes are returned “because JSONSerialization refuses a leading mark too.” I handed JSONSerialization a UTF-8 BOM plus a one-field object; it returned the object. BackupArchive.read is then given the unmodified bytes from .locked(data), and that happens to work because the comment is wrong. Aegis is given the stripped body, which is the right instinct applied inconsistently.

───

Finding 3 — Low

Finding 8 was fixed in three readers and left in the fourth, and the fourth’s test pins the lie in place.

GoogleAuthenticatorImport.parameters still does this, after a successful decode of raw bytes:

        guard secret.count >= 10 else {
            return .failure(Failure(label: label, reason: .secretNotBase32))
        }

ImportRefusal.Reason.secretTooShort exists now, with a description that tells the truth. Backup, Aegis, and labelled text use it. Google Authenticator import still reports “the secret key contains characters that are not valid” for a nine-byte secret that has no characters at all — the payload field is raw bytes. GoogleAuthenticatorImportTests.refusesShortSecrets asserts .secretNotBase32.

It also still says >= 10 instead of AccountLimits.isSecretLongEnough. AccountLimits exists so that number has one home. This is the path that already had a floor; they updated the others and walked past it.

Smallest fix: AccountLimits.isSecretLongEnough and .secretTooShort. Change the test.

───

The eleven, against the claims

1. Enrollment vs the format. Closed for OTPAuthURI, AegisImport, LabelledTextImport, and BackupPayload.write. The probe from triage — otpauth://totp/x?secret=GEZDGNBV → write → read — now dies at the URI parser, and the writer would refuse it if it ever arrived. I am satisfied that restore-loss path is gone.

It is not true that every way into the store reads AccountLimits. ManualSetupViewModel.account still accepts any non-empty Base32 secret and any UInt64 counter. KeychainSecretStore.add does not consult the limits. So a person can still type GEZDGNBV, see a live code, and save. Export then throws cannotStoreAccount, whose comment and user-facing text say this is “only reachable for an account enrolled before the enrollment paths enforced these rules” and “saved before OpenFactor checked for this.” That is false today. The failure is now at export, while the originals are still on the phone, which is the right moment. I am not promoting this to a finding on the same level as the original; the writer is doing the job they said was load-bearing. The comment should not claim the door is bricked.

2. The migration crash. Closed. UInt64.max in field 4 is .malformed. All three batch fields refuse above maximumBatchField (10,000). position is index &+ 1. The exact payload from triage is a test. I do not see another Int(clamping:) in this scope that can reach a + 1 on the UI path.

3 / 4 / 5 / 9. The bound family. The UI no longer applies 8 MiB before asking what the file is. An archive is held to BackupArchive.maximumFileBytes. Aegis and labelled text stay on the policy 8 MiB. read(_ url:) asks fileSizeKey after startAccessingSecurityScopedResource and before Data(contentsOf:). That is the reported 400 MB attachment, for a URL that reports a size.

Two residuals I looked at and am not elevating:

• If fileSize is nil, the preflight is skipped and the second bound runs after the copy. The what-changed block already says so. I did not find a default Files / document-picker URL that omits fileSize after the security-scope call, so I will not claim a crash I cannot name a caller for.
• AddAccountViewModel.handleImage now refuses before CIImage. The bytes have already been materialised by Photos; the comment is honest about that.

The share extension is closer to incomplete. firstImage switched to loadFileRepresentation, which is the right API, then copyItems the system file in the callback before asking fileSizeKey on the copy. The system URL is live in that callback; its size is readable; the comment says “the size is known before the copy.” The copy they mean is theirs. A 400 MB image is still a 400 MB disk duplicate in the extension’s temp directory, then discarded. Measure url first, then copy.

6. Duplicates in one file. Closed. classify keeps seenInThisFile keyed by secret, and feeds those generators into the same disposition function as the store. Two identical accounts → one .new, one .duplicate. Same secret, different period → .conflict. Tests cover both. confirm still only store.adds. Existing records cannot be overwritten or deleted.

7. The sniff. See Finding 2. BOM and RTF-behind-whitespace are closed. The 512-byte skip is not.

8. The lying refusal. See Finding 3.

10. “Keys in the clear.” Closed. sourceWasEncrypted is set only on a successful archive unlock. The .file finish screen then says keep the backup and the passphrase. Plaintext exports still get the deletion advice. I did not find a path that leaves the flag set across a second file on the same model; each ImportView constructs a new view model.

11. sortIndex. Closed as far as restore order goes. confirm sorts by the file’s sortIndex and then add appends in that sequence. Absolute indices are still rewritten by the store, which is what “place it at the end” means when the vault is not empty. Aegis and labelled text still default every account to 0; Swift’s sorted(by:) is stable, so file order survives.

───

What I did not treat as a finding

• ImportLimits as a single chokepoint. The rule is the one they intended: load up to the largest ceiling, then apply the format’s own. I do not see a way to make isWorthLoading and isWithinBound disagree that would accept a file the reader must refuse, except Finding 1, which is not ImportLimits’s mistake.
• A new crash in the batch header. Int(value) after value <= 10_000 cannot overflow. The leftover position += 1 in the account loop is a different integer, bounded by the payload size.
• JSONSniff returning bytes. For Aegis they parse what they stripped. For the archive they sniff the stripped body and decrypt the original. That combination is safe because Foundation accepts a BOM, not because of the comment.
• Anything in the backup cryptography that the first pass called sound. The KDF bounds, the AAD, the parse-after-tag, and the advisory passphrase hint were not touched by these fixes.

───

Smallest set of patches: check plaintext length in BackupArchive.write; skip whitespace without a 512-byte cap in JSONSniff; use secretTooShort and AccountLimits in GoogleAuthenticatorImport; ask fileSizeKey on the system URL before copyItem in the share extension; point ManualSetupViewModel at AccountLimits so the writer’s “saved before we checked” sentence becomes true

GPT:
Reviewed `6254706` (checkout `cf356d9`) against the round-one result.
Findings:

1. Medium — the writer can still produce an archive its reader must reject.
[BackupArchive.swift (line 218)](Sources/OpenFactorCore/Backup/BackupArchive.swift:218) only checks the serialized container size at [`:268` (line 268)](Sources/OpenFactorCore/Backup/BackupArchive.swift:268). The reader separately rejects decoded ciphertext over 8 MiB at [`:125` (line 125)](Sources/OpenFactorCore/Backup/BackupArchive.swift:125). A plaintext of 8,388,609 bytes produces 11,184,812 Base64 characters, while the container remains below the 12,233,388-byte file ceiling; writing succeeds, restoring throws `.tooLarge`. Check `plaintext.count <= maximumPlaintextBytes` immediately after `BackupPayload.write`, before KDF/sealing.
2. Low — `JSONSniff` still fails on valid JSON with more than 512 leading whitespace bytes.
[JSONSniff.swift (line 35)](Sources/OpenFactorCore/Import/JSONSniff.swift:35) examines only `body.prefix(512)`. `513` spaces followed by a valid OpenFactor JSON object therefore return an empty body, sending the file through labelled-text import instead of the passphrase flow. Scan leading whitespace across the already bounded input.
3. Low — the share extension still copies an oversized attachment before checking its size.
[ShareViewController.swift (line 117)](OpenFactorShare/ShareViewController.swift:117)–[`125` (line 125)](OpenFactorShare/ShareViewController.swift:125) copies the provider file; the `fileSizeKey` check occurs only at [`:132` (line 132)](OpenFactorShare/ShareViewController.swift:132). A large shared image can consume extension temporary storage before rejection. Check the provider URL’s size inside the callback before `copyItem`, failing closed if unavailable.
4. Medium (provider-dependent) — file-size preflight fails open when `fileSizeKey` is unavailable.
[ImportViewModel.swift (line 100)](OpenFactor/Import/ImportViewModel.swift:100), [ShareViewController.swift (line 132)](OpenFactorShare/ShareViewController.swift:132), and [SharedInbox.swift (line 198)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:198) use `if let size`; a missing size proceeds to `Data(contentsOf:)` or `contents(atPath:)` without a pre-read bound. Require a known acceptable size, or use bounded streaming reads.

The migration-field fix now rejects the reproduced crashing payload before conversion, and backup parsing checks size limits before PBKDF2 and authenticates before payload parsing. Duplicate detection now includes both stored accounts and earlier entries in the same file.

Fable:
This is round two for scope 3. I'll read the round-two account of changes and round one's recorded pass with its triage, then verify the fixes in the review checkout.
Ran a command, read 2 files
The round-one record and change account are read. Now I'll diff the fix commits against round one's commit and read every changed file in scope.
Ran 11 commands, read ManualSetupViewModel.swift
One last round of exact line references for the report:
Collected exact line numbers for citations
Scope 3, round two: the fixes, reviewed
Code reviewed: `6254706`. The checkout is `cf356d9`, which I verified differs from `6254706` only in `HANDOFF.md` and `docs/audits/A4-prompts.md` — no source differs. Round one read `74fe841`; the fix commits between are `a848a88`, `f5658fa`, `b41f84d`, `8471c33`. I diffed every in-scope file across that range and read the three new types (`AccountLimits`, `ImportLimits`, `JSONSniff`) whole.
The short version: nine of the eleven items are genuinely fixed, and I verified each rather than pattern-matched the diff. Two fixes are incomplete in ways that matter to their own claims, one fix regressed an ordering on a disclosed-residual path, and four comments or documents now claim things the code does not do — one of which I disproved by running Foundation rather than reading it.
R1 — Medium. The enrollment sweep missed the front door: manual entry still accepts what the format forbids, and the writer's new guard turns that account into a full export outage explained by a false sentence
The what-changed document says "all four enrollment paths read them." `ManualSetupViewModel.swift` reads neither rule: `account` (line 79) accepts any non-empty Base32 secret — `secretProblem` at line 56 checks only decodability and non-emptiness — and line 83 accepts any `UInt64` counter, including `UInt64.max`. `save()` goes straight to `store.add`. Typing in an account by hand is the archetypal enrollment path, and it is exactly the screen a person uses when a service prints a secret, which is also when a short secret is most likely.
Call order today: manual-add with secret `GEZDGNBV` (or counter `18446744073709551615`) → account enrolls and generates codes → any later export reaches the new guard at `BackupPayload.swift:210` → `cannotStoreAccount` → the entire export fails, every time, until that account is deleted. Failing the whole export is the design's stated position and I am not disputing it — loud-at-export beats silent-at-restore, which is a real improvement over round one. But two things are wrong with the combination:

1. The class the fix claims closed is open. An account that "works every day and cannot be preserved" can still be created, today, on the current build.
2. The explanation is false. `BackupError.swift:43` says the case is "Only reachable for an account enrolled before the enrollment paths enforced these rules," and the user-facing message says "It was saved before OpenFactor checked for this." Both are untrue for an account saved through manual entry five minutes ago, and the message then advises the person to re-add the account "from the service" — which, through the same unguarded screen, reproduces the problem.

Smallest fix: apply `AccountLimits` in `ManualSetupViewModel` — `secretProblem` gains a too-short branch (the screen already exists to explain problems, and `OTPAuthURIError.secretTooShort`'s wording is right there to reuse), and `counterProblem` gains `isCounterStorable`. Then the `BackupError` comment becomes true instead of needing rewording.
R2 — Low. The writer's ceiling check bounds the wrong quantity in the wrong place, and the window it leaves is exactly the claim it makes
Round one (ChatGPT's half of the finding) was precise: "enforce the plaintext limit before sealing." The fix, `BackupArchive.swift:268`, checks the finished container against `maximumFileBytes` (≈12,233,388 bytes) after sealing. The reader's binding bounds are the ciphertext ones: it refuses decoded ciphertext over 8 MiB, i.e. any plaintext over 8,388,608 bytes. Arithmetic on the gap: plaintext `P` produces a base64 field of `4·⌈P/3⌉` characters plus ~400 bytes of wrapper, so the writer's guard passes anything up to `P ≈ 9,17x,xxx` — roughly 786 KB of plaintext, a few thousand accounts, that the writer will seal and every conforming reader, including this one, must refuse. The comment above the guard, "The writer refuses what the reader must refuse," is false in that window.
Practical reach is the same absurd tier as round one's F2 (fifty-odd thousand accounts), so this is low — but it is a fix that moved a check without checking the thing the finding named, which is the specific shape this round exists to catch. Smallest fix: `guard plaintext.count <= maximumPlaintextBytes else { throw BackupError.tooLarge }` before `AES.GCM.seal`; the container guard can stay as a second belt.
R3 — Low. The "class sweep" for the lying refusal reason missed one of its two instances
`8471c33` is titled "the class sweep, not just the instances." The lying-reason class — `.secretNotBase32` reported for a secret that decodes perfectly but is short — existed in two files. It was fixed in `BackupPayload`, `AegisImport`, `LabelledTextImport`, and the URI parser, all of which now say `secretTooShort`. It survives at `GoogleAuthenticatorImport.swift:231-233`: a migration payload carrying a 5-byte secret is still refused as "the secret key contains characters that are not valid." The same lines hardcode `10` instead of reading `AccountLimits.minimumSecretBytes`, so `AccountLimits.swift:26`'s claim that "there remains exactly one definition" is off by one — value-identical today, free to drift tomorrow. Two-line fix.
R4 — Low. On the path the fix itself names as residual, the in-memory bound now runs after a full JSON parse
The what-changed document honestly discloses that "a URL whose size cannot be read is allowed through to the second bound" — `ImportViewModel.swift:100` swallows both the throw and the nil. But the second bound moved. Round one's code checked `data.count` first and sniffed second; the fixed code at lines 131-133 computes `looksLikeOpenFactorArchive(data)` — which runs `JSONSniff.body` (a full `Data` copy for JSON-looking input) and a complete `JSONSerialization.jsonObject` parse — before `ImportLimits.isWithinBound` is consulted. On the readable-size path this is harmless (the preflight already bounds the copy at ~12.2 MB). On the unreadable-size path, the unbounded allocation was the disclosed residual, but the unbounded parse plus second copy in front of the backstop is new this round, and it is the scope's question-5 pattern — a bound checked after the expensive operation — reintroduced by the commit that was fixing it. Smallest fix: `guard data.count <= ImportLimits.largestAcceptableBytes` at the top of `read(_ data:)`, cheap and format-independent, then sniff, then apply the format-specific bound as now.
R5 — Low. Four claims the code does not back, one of them disproved by measurement
The preamble puts false behavioral claims in scope, and round two's third question asks for them specifically:

1. `JSONSniff.swift:27-30` and the what-changed document both claim `JSONSerialization` "refuses a leading mark too." I tested it: Foundation on this platform parses BOM-prefixed JSON without complaint. The code itself is the counterexample to its own comment — `read(_ data:)` stores the unstripped bytes in `.locked`, `BackupArchive.read` later parses them BOM and all, and a BOM-prefixed archive opens fine, because the comment is wrong. The design rationale "returns bytes rather than a verdict, because recognising and then parsing unmodified bytes has the bug back" therefore describes a hazard that does not exist, and the next maintainer who reads it will either "fix" the locked path needlessly or distrust the stripping that Aegis's `JSONDecoder` path may actually need. The fix is a comment that states what was measured.
2. `GoogleAuthenticatorImport.swift:87-90`: "written as a saturating add anyway" — `&+` is a wrapping add. Swift has no saturating operator. `Int.max &+ 1` is `Int.min`, so the belt the comment promises would, if the invariant ever moved, display a negative part number rather than clamping. Unreachable today (`index ≤ 10,000`), but a comment invented this round that misdescribes the operator it annotates.
3. `BackupError.swift:43`: "Only reachable for an account enrolled before…" — false via manual entry (R1).
4. "The writer refuses what the reader must refuse" at `BackupArchive.swift:263` — false in R2's window; and the round-two document's "all four enrollment paths read them" overstates: Google Authenticator reads neither symbol (R3), and the manual path reads nothing (R1).

R6 — Informational. The sniff is still stricter than the parser it guards, in one remaining way
`JSONSniff` fixed the BOM and the whitespace-before-RTF instances, and moved the decision where a test can reach it — all three claims check out. But the third instance round one recorded remains: whitespace is dropped only within `body.prefix(512)`, so a JSON file with more than 512 bytes of leading whitespace still routes to the labelled-text reader, while `JSONSerialization` accepts arbitrary leading whitespace and the format document says whitespace is not significant. Nobody has such a file; I note it because the commit message claims the class, and the class is "sniff stricter than reader," of which this is the last survivor I could find.
What I verified and found genuinely fixed
Taking the eleven in the round-two document's order, with what I checked rather than assumed:
1. Enrollment limits — real for the URI parser (`OTPAuthURI.swift:176`, `268`), Aegis (both rules), and labelled text; the refusals carry the new honest reason. Incomplete per R1/R3. 2. The batch crash — fixed correctly: values over 10,000 are refused at parse time with `throw .malformed` (valid in the typed-throws context), before any `Batch` exists, so round one's reproducing payload (`batch_index = UInt64.max`) now yields the "could not read" message instead of a trap. Refusing rather than clamping is the right instinct and the comment explaining why is accurate — except for the "saturating" word (R5.2). 3/4/5/9. The bounds family — the preflight asks the file system before `Data(contentsOf:)`; the archive is held to the frozen ceiling and nothing else, so round one's F2 is genuinely closed on both the picker and inbox paths; the share extension now takes a file representation, copies it inside the callback (correct — the system deletes its file on return), checks the size on disk, and deletes its copy on every exit path via `defer`, which I traced through the nil-URL and failed-copy branches; the PhotosPicker path is bounded with a comment that honestly names what it cannot bound. Residuals per R2/R4. 6. In-file duplicates — fixed correctly: `classify` now folds each candidate's generator into `seenInThisFile` and dispositions later candidates against stored-plus-earlier, so a doubled account previews as one `.new` and one `.duplicate`, and same-secret-different-parameters within one file surfaces as a conflict. I checked the interleavings; they are right. 7. The sniff — BOM and whitespace-order instances fixed, decision moved to the core, stripped bytes correctly handed to `AegisImport`; the BOM archive now reaches the passphrase screen and opens end-to-end (verified via the measurement in R5.1). 8. The refusal reason — fixed in four places, missed in one (R3). 10. The finished-screen advice — fixed: encrypted archives get "keep it somewhere safe," and I checked the `sourceWasEncrypted` lifecycle (set false on both plaintext paths, true only on successful unlock, masked by the `origin` switch for transfer-fed previews) for a stale-flag path and found none. 11. `sortIndex` — fixed: `confirm` sorts by the file's indices before adding. I checked the two formats that never set one (Aegis, labelled text — every entry 0): Swift's `sorted` is documented stable since Swift 5, so file order is preserved, and hostile out-of-range indices order only the save loop and never persist, since `add` still assigns its own position.
Nothing else regressed that I could find. I re-checked the surfaces the fixes touched against round one's sound-verdicts: `ProtobufReader` is unchanged; the archive reader's refuse-before-derive ordering is unchanged; importers still write nothing but `store.add`; the `.sortedKeys` change to `KeychainSecretStore.encode` (scope 1's item) does not affect any import path, since key order never affects decoding.
Summary for triage. The two fixes I would reopen are R1 (the enrollment class is open through manual entry, and the new writer guard — itself correct — now makes that account block every backup while blaming the past) and R2 (the writer bounds the container, not the plaintext, leaving exactly the window it claims closed). R3 and R4 are small and mechanical. R5 is comments — but this project's stated rule is that a comment nobody can trust is worse than none, and two of the four were written this round, in the fixes themselves, which is the failure mode the round-two prompt predicts: fixes made under time pressure leaving claims the code does not keep.
