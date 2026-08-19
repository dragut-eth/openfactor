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
