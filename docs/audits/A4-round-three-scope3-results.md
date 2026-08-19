# A4 round three, scope 3: what three engines found in the fixes

Round three read `fc844aa`. All three engines returned.

**All six open items are closed, and no engine rejected a fix.** That is the second round in a row
across the gate without a rejection, and the first time this scope has had one.

| Engine | Verdict |
| --- | --- |
| Grok 4.6 | "The six open items are closed. I did not find a seventh. I would ship these six" |
| Fable 5 | "All six genuinely closed this time, and I could not break any of them" |
| ChatGPT 5.6 Sol | One medium, one low, one informational. "Converging, but the boundary fixes still move risk between preflight, copying and reading" |

## What was verified rather than accepted

**Fable checked the arithmetic on S3-5 and it closes exactly.** A maximal writer payload of
8,388,608 bytes produces 4·⌈8388608/3⌉ = 11,184,812 base64 characters, which is precisely
`maximumCiphertextCharacters`. So the largest archive the writer will seal is also the largest the
reader accepts, with no gap in either direction.

**Grok re-derived the composition of the split writer.** `write` still does, in order: refuse a
weak custom passphrase, `BackupPayload.write` with its storable sweep, then `seal`. Nothing
cryptographic moved except the new plaintext comparison, which sits before the CSPRNG and the KDF.

**Fable enumerated every path to `store.add`** — URI scan, Google transfer, Aegis, labelled text,
archive restore, manual entry — and confirmed all six now enforce both limits, which is what makes
`BackupError`'s comment true rather than merely reworded.

**Both checked the precondition the sniff's fix rests on**: nothing reaches `JSONSniff.body`
without passing the cheap ceiling in `read(_ data:)` first.

## The disagreement, and it is the useful kind

**Whether a stat-then-read bound is good enough on the two URL paths.**

ChatGPT files it as a medium: `ImportViewModel` checks `fileSizeKey` and then performs a separate
unbounded `Data(contentsOf:)`, and the extension checks the provider's file, copies it, then reads
the copy. A hostile file provider or sender can replace or grow the file between the check and the
read, so the later `data.count` guard runs after the allocation. It points at `SharedInbox.take`,
which does it correctly with one handle and `limit + 1` bytes, and asks for the same shape
everywhere.

**Grok looked at the same three call sites and passed two of them deliberately**: "take is the only
one of the three that faces a container another process can write. That is the one that got the
stronger shape, and it is the right one." Fable also reviewed all three and accepted them.

So the question is not whether the code differs — everyone agrees it does — but whether a document
picker URL or an `NSItemProvider` file is attacker-mutable. ChatGPT says a hostile provider
extension makes it so. The other two treat the group container as the only hostile-writer surface.
**That is a factual question about iOS, and it is settleable rather than a matter of taste.**

## What round three added

| # | Finding | Severity | Engines |
| --- | --- | --- | --- |
| S3-16 | two URL entry points stat and then read separately, so the file can change in between | medium | ChatGPT, disputed by Grok and Fable |
| S3-17 | image routes preflight at the archive ceiling, so an 8 to 12.2 MiB image is copied and then refused | low | ChatGPT, Fable |
| S3-18 | `seal` skips the weak-passphrase and storable checks by construction, and nothing says so | low | Fable, Grok |
| S3-19 | `looksLikeJSON` is dead code wearing a stale comment | low | Fable |
| S3-20 | the fail-closed refusal says "too large" when the size could not be read | low | Fable |
| S3-21 | the "unlike an import" comment claims importers truncate secrets, which they do not | low | all three |

**S3-18 is the seam the split created**, and both engines that found it call it a future footgun
rather than a present defect. `seal` performs neither the weak-passphrase check nor the storable
sweep; both live in `write` above it. Today `seal` is internal with one production caller. If a
second exporter grows, the writer obligation the format states is gone silently. One doc comment
naming what `seal` deliberately does not check keeps the next caller honest.

**S3-21 is the one all three found, and it is mine from this morning.** The comment on
`secretProblem` says manual entry refuses "unlike an import". No importer truncates a secret; every
one refuses it. Only labels truncate, on every path. **The brief asked whether that inconsistency
was right, and the answer all three gave is that the inconsistency does not exist** — secrets are
refused everywhere, labels truncated everywhere, and both rules are correct where they are. What is
wrong is the sentence I wrote asking about it.

**Grok recorded one thing it declined to file.** `KeychainSecretStore.add` does not consult
`AccountLimits`, so a test can still plant a short secret, and the writer will refuse to back it
up. It is not an enrollment door, so it did not reopen S3-12 over it.

## Convergence

All three say yes. Grok: the writer has been touched three times, no check, then the container,
then the plaintext, and the third is the one the reader uses; the sniff three times, BOM-blind,
then a 512-byte skip, then the whole input, and the third matches Foundation. It sees no fourth
rewrite of the same comparison waiting to happen.

Fable's is the assessment worth keeping, because it is about the habit rather than the code:

> The import-bounds area was rewritten three times to reach a state one careful pass could have
> written, and rounds two and three were spent closing gaps the fixes themselves opened. That is
> churn in process terms. But each rewrite strictly shrank the open set, the third landed with the
> test discipline the first two lacked, including catching its own false-green suite.

And its closing line, which is the standing lesson of this gate:

> The thing to watch is not this code but the habit, now twice demonstrated, of fixing a finding
> against its sentence rather than its failure sequence. **This round is the first where that habit
> did not appear.**
