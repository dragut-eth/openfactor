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

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Grok:
A4, scope 3, round three

Code reviewed: fc844aa
Checkout: d9a239d (differs only in A4-round-two-scope3-results.md)
Round two read: 6254706
Round one read: 74fe841

Nothing in the repository was modified. I am the same engine that filed the writer-ceiling miss last time, so I will not give that fix a pass because I asked for it.

───

The six open items are closed. I did not find a seventh. The writer now refuses the quantity the reader refuses, before anything is sealed. That is the change all three of us rejected last round, done as named.

───

1. Does each change address the finding it claims to?

S3-5, the writer ceiling. Yes. BackupArchive.seal begins with guard plaintext.count <= maximumPlaintextBytes. That is 8,388,608, the same number read applies to decoded ciphertext. GCM ciphertext is the length of its plaintext, so a payload of 8,388,609 bytes — the case I walked last time — now throws .tooLarge before SecRandomCopyBytes runs. The container check against maximumFileBytes is still there afterwards, as a looser belt, and is no longer the only check. writerRefusesAnOversizePayload builds that 8,388,609-byte payload directly and expects .tooLarge. writerAcceptsAtTheCeiling takes the other side. I am not accepting this because I asked for it; I am accepting it because the comparison is now the one the reader makes, in the place round one named.

S3-7, the 512-byte window. Yes. JSONSniff.body is body.drop(while: \.isASCIIWhitespaceByte) over the whole input. I previously ran Foundation and watched 512 spaces hide an object from the sniff while JSONSerialization accepted it. The new test feeds 511, 512, 513 and 4,096 spaces and requires recognition. The RTF guard still runs after the skip; 4,096 spaces then {\rtf is empty.

S3-8, the lying refusal. Yes. GoogleAuthenticatorImport.parameters calls AccountLimits.isSecretLongEnough and reports .secretTooShort. The test that asserted .secretNotBase32 now asserts the true reason. The comment that claimed one definition no longer has to walk it back.

S3-12, manual entry. Yes, and in both places that have to agree. secretProblem and account both call AccountLimits.isSecretLongEnough. counterProblem and account both call isCounterStorable. GEZDGNBV produces a problem, no OTPAccount, and canSave == false. A form that is quiet cannot describe an account the writer would refuse. BackupError.cannotStoreAccount no longer says the account “was saved before OpenFactor checked for this” and no longer tells the person to re-type it through the screen that caused it.

S3-13, the bound after the parse. Yes. read(_ data:) now does guard data.count <= ImportLimits.largestAcceptableBytes before looksLikeOpenFactorArchive. The JSON copy and parse cannot see more than 12,233,388 bytes. The format-specific bound still runs after recognition, so a 10 MiB Aegis file is still refused by the policy ceiling rather than treated as an archive.

S3-14, fail-open when the file system is silent. The three call sites now fail closed. I reviewed them as asked, because the work landed in another scope.

• ImportViewModel.read(_ url:) requires a fileSize and isWorthLoading. Missing size is a refusal, not a fallthrough to Data(contentsOf:).
• ShareViewController.firstImage asks fileSizeKey on the system URL before copyItem. Missing or oversize: no copy, callback returns nil.
• SharedInbox.take no longer asks the file system for a size at all. It opens a handle and read(upToCount: limit + 1). One byte past the ceiling is .tooLarge, and defer still deletes the item. A writer sharing the container cannot swap the file between a stat and a read, because there is no second lookup.

take is the only one of the three that faces a container another process can write. That is the one that got the stronger shape, and it is the right one.

───

2. Did any change introduce something new?

write and seal compose to the old write, plus the plaintext guard.

write still does, in order: refuse a weak custom passphrase; BackupPayload.write (which still refuses an unstorable account); seal. seal does: refuse plaintext above 8 MiB; fresh salt and nonce from SecRandomCopyBytes with no fallback; the same canonical-or-verbatim derivation; AES.GCM.seal with AAD = the format constant; the same pretty-printed, sorted-key container; refuse a container above maximumFileBytes.

I compared that list to the write I read at 6254706. Nothing cryptographic moved except the new plaintext comparison, which sits before the CSPRNG and the KDF. The product caller is still ExportViewModel.export → BackupArchive.write. I did not find a shipping caller of seal.

The seam the split creates is real and I will name it rather than inflate it: passphrase strength lives only on write. seal will happily encrypt under mode: .custom and a weak string. Today that is a test-only internal function (writerAcceptsAtTheCeiling uses it with 1,000 iterations, which a reader would also refuse). If a second exporter calls seal later, the writer obligation the format states is gone. That is a future footgun, not a current defect.

Manual refuse vs import truncate. The prompt asked whether this inconsistency is right. On secrets there is no inconsistency. Importers already refuse a short secret; they never truncated one, and truncating one would have reopened S3-1 (codes that look right and are rejected forever). Manual now refuses too. That is the same rule, at the door a person can still correct. Labels still truncate on both paths, through OTPAccount → AccountLabel.clamped, including the byte ceiling scope 4 added. A long name must not fail a restore; a short secret must not become an account. Those two fields should not share a policy.

The comment on secretProblem that says “refused here rather than truncated, unlike an import” is the one slightly false sentence this pass produced. An import does not truncate secrets. I am not giving a comment that misnames a neighbour a severity.

Nothing reaches JSONSniff.body without ImportLimits in this app. The production callers are looksLikeOpenFactorArchive, preview, and the unused-looking looksLikeJSON wrapper, all on ImportViewModel, all after the cheap bound in read(_ data:). JSONSniff is public and does not enforce a bound itself. That is a claim about today’s callers, not a type invariant. Today’s callers hold it.

I did not find a new race, a new clamp, or a new path that writes an account the format cannot restore.

───

3. Comments that claim what the code does not do

The four false comments from last round are gone or corrected. JSONSniff now says Foundation accepts a leading mark, and that the archive path relies on that; I measured that last time, and the comment now matches the measurement. AccountLimits no longer has to confess that Google still holds its own ten.

What remains is small: the “unlike an import” clause above, and cannotStoreAccount’s comment that the case is only reachable for accounts enrolled before the limits. That last one is now true of every shipping enrollment path I can reach (OTPAuthURI, Aegis, labelled text, Google, manual). KeychainSecretStore.add still does not consult AccountLimits; a test can still plant a short secret. The writer will refuse to back it up. I am not reopening S3-12 over a store that is not an enrollment door.

───

4. Is this converging?

Yes. The surface is shrinking, not sliding.

The writer has been touched three times: no check, then the container, then the plaintext. The third check is the one the reader uses. The sniff has been touched three times: BOM-blind, then BOM-aware with a 512-byte skip, then a skip over the whole input. The third matches JSONSerialization. Manual entry was the leftover door; it now reads the same two predicates as the parsers, in the two places that have to agree. The bound-after-the-expensive-operation pattern reappeared once inside the commit that was removing it (S3-13) and has been put back in front.

I do not see a fourth rewrite of the same comparison waiting to happen. What would still be worth a pair of eyes later is the seal wrapper if anyone else grows a caller, and take’s handle read if the inbox limit ever diverges from ImportLimits. Those are seams, not open defects.

Round one found the readers sound and the code around them wrong. Round two found the first repairs answering the sentence instead of the failure. This round’s repairs answer the failure. I would ship these six.

Fable:
Scope 3, round three: the fixes, reviewed
Code reviewed: `fc844aa`. The checkout is `d9a239d`, verified to differ only in `docs/audits/A4-round-two-scope3-results.md`. I diffed every file changed since `6254706` (round two's commit), read the split writer, the rewritten sniff, the manual-entry model, and the four new test blocks in full, and followed the round-three brief's four pointers, including the S3-14 call sites this scope never reviewed.
The short version: all six open items are genuinely closed this time, and I could not break any of them. For the first time in three rounds, the fixes introduced nothing of substance — the residue is a dead method, one reused error message, and one misleading comparison in a comment. My answer to the convergence question is yes, with the evidence below.
1. Does each change address the finding it claims to?
S3-5, the fix all three rejected — now correct, and I checked the arithmetic. `BackupArchive.swift:246` bounds the plaintext at `maximumPlaintextBytes` before anything is sealed, which is the quantity the reader's binding rule uses and the words round one asked for. The window is closed exactly: a maximal writer payload of 8,388,608 bytes produces `4·⌈8388608/3⌉ = 11,184,812` base64 characters — precisely `maximumCiphertextCharacters` — so the largest archive the writer will now seal is also the largest the reader accepts, with no gap in either direction. The old container check remains as a second, honestly relabelled belt. The boundary is tested from both sides (`BackupArchiveTests.swift`, at-ceiling accepts, one-past refuses), so removing the guard reddens a test, which was the thing the first attempt lacked.
On the brief's specific question — does `write`/`seal` compose to what `write` did before: yes. The order is unchanged (strength check → `BackupPayload.write`, which enforces `isStorable` → salt, nonce, passphrase form, derivation, seal, container check), with only the plaintext bound inserted. One seam observation below under question 2.
S3-7, the sniff — closed, and the brief's precondition holds. `JSONSniff.swift:49` drops whitespace across the whole input; the 512-byte window is gone and pinned by tests at 511/512/513/4096 spaces, plus the RTF-behind-whitespace interaction. I verified the claim the removal rests on — that nothing reaches `JSONSniff.body` unbounded: its only production callers are `preview` and `looksLikeOpenFactorArchive`, both reachable solely through `read(_ data:)`, whose first statement is now the cheap ceiling check. (The third caller, `looksLikeJSON`, is dead — see question 3.)
S3-8 — closed. `GoogleAuthenticatorImport.swift:241` reads `AccountLimits.isSecretLongEnough` and reports `secretTooShort`; the test that had pinned the lying reason in place now asserts the honest one. `AccountLimits`'s "exactly one definition" claim is finally true — I grepped for stray `10`s and found none.
S3-12, manual entry — closed, in both places it had to be. `ManualSetupViewModel.swift` applies the floor and the ceiling in `secretProblem`/`counterProblem` and in `account`, so a quiet form cannot describe an account the format refuses — the two definitions of "valid" that used to be able to disagree now share the rules. Boundary tests sit at exactly 10 bytes and exactly `maximumCounter`, inside the right suite (I checked the brace placement, given the false-green story). With the door closed, `BackupError.cannotStoreAccount`'s "only reachable for an account enrolled before the checks" comment has become true — I enumerated the paths to `store.add` (URI scan, GA transfer, Aegis, labelled text, archive restore, manual entry) and every one now enforces both limits — and the user-facing message no longer blames the past or advises the screen that caused the problem.
S3-13 — closed by the pattern's own cure: `read(_ data:)` now opens with a format-independent `count <= largestAcceptableBytes` before the sniff's parse and copy (`ImportViewModel.swift:130`).
S3-14 — closed, and I reviewed the three call sites as the brief asked. The import preflight (`ImportViewModel.swift:101`) is a `guard` that refuses when no size comes back. The extension's preflight now measures the system's file inside the callback, before any copy, and fails closed (`ShareViewController.swift`) — round two's version copied first and measured after, and that is genuinely fixed, not moved. `SharedInbox.take` (`SharedInbox.swift:240-247`) is the strongest of the three: one handle, one bounded `read(upToCount: limit + 1)`, refusal one byte past the limit, no separate stat for a writer to race, and destructive removal on every exit path via `defer` — which also answers this scope's question 4 for that path: hostile bytes in the group container are read once, bounded, deleted regardless of outcome, and then hit the same bounded `handleImage` as every other image.
2. Did any change introduce something new?
I hunted specifically for the three shapes previous rounds found in fixes — a bound after the expensive operation, an instance fixed with the class open, a claim the code does not keep — and found none of substance. What I did find:

* The `seal` seam skips two gates by construction. `BackupArchive.seal` performs neither the weak-passphrase check nor the `isStorable` sweep — both live in `write`, above it. Today that is fine: `seal` is internal and its only production caller is `write` (I checked; the multiline call is the single site). But the invariant "no archive exists with a weak custom passphrase" is now enforced in one half of a split API, and nothing on `seal` says so. A one-line doc comment on `seal` naming what it deliberately does not check would keep the next internal caller honest.
* The extension's preflight is looser than its own payload can ever need. It preflights at `largestAcceptableBytes` (~12.2 MB) but the extension handles only images, which the very next check bounds at 8 MiB. A 10 MB share is therefore copied and loaded, then refused — a bounded, ~4 MB-window echo of the old pattern, not a defect. `policyBytes` is the right preflight there, since an image cannot be an archive.
* The fail-closed refusal reuses a message that can be false: a file whose size cannot be read is reported as "too large to be an authenticator export." Refusing is right; the sentence claims something unknown. Cosmetic, but this project's own rule about untrustworthy messages argues for wording like "could not be checked."

3. Is anything claimed that the code does not do?
The four round-two documentation items are all genuinely repaired — the `JSONSniff` comment now records the measured truth about `JSONSerialization` and the BOM (and correctly notes the archive path relies on it), the `&+` comment now names the wrapping semantics and defends the choice honestly, and the two `AccountLimits`/`BackupError` claims have become true by the code catching up to them. Three small new items:

* `looksLikeJSON` is dead code wearing a stale comment. `ImportViewModel.swift:236-243` has no callers, and the doc comment above it is a mashup of the pre-`JSONSniff` text ("The signature is checked before the brace") and the newer redirection. Delete both.
* "Refused here rather than truncated, unlike an import" in `ManualSetupViewModel`'s comment implies importers truncate short secrets. They do not — every importer refuses them, per account; only labels truncate, everywhere. And to answer the brief's question directly: the inconsistency it asks about does not exist. Secrets are refused on every path, labels are truncated on every path, and both rules are right where they are. The comment's comparison clause is the only thing wrong, and the fix is rewording, not code.
* The same comment's "the URI parser, both file importers and the archive writer all did" undercounts the importers and flatters GA, which held its own copy until this very commit. Harmless, but this file's history says loose history in comments compounds.

4. Is this converging?
Yes — and the evidence is in the shape of the residue, not in the count. Round one produced eleven findings including a reproducible crash and a silent data-loss path, with no tests on any bound. Round two's fixes closed eight but were themselves the story: a unanimous rejection, two instance-not-class sweeps, and a fix that reintroduced the pattern it was fixing one function away. This round, every open item closed on first inspection, each closure carries a boundary test on both sides that reddens if the guard is reverted, and the leftovers are a dead method, a reused string, and a comment clause — nothing an attacker or a restoring user can reach. The rules that four files used to disagree about now have one home each (`AccountLimits`, `ImportLimits`, `JSONSniff`), which is why this round's fixes could be verified by reading one file instead of five.
The honest caveat: the import-bounds area was rewritten three times to reach a state one careful pass could have written, and rounds two and three were spent closing gaps the fixes themselves opened. That is churn in process terms. But each rewrite strictly shrank the open set, the third landed with the test discipline the first two lacked — including catching its own false-green suite — and the defect surface is now materially smaller than at `74fe841`: bounded before allocation at every entry point, one definition per rule, and the writer provably unable to produce what the reader refuses. Converging, on the merits; the thing to watch is not this code but the habit, now twice demonstrated, of fixing a finding against its sentence rather than its failure sequence. This round is the first where that habit did not appear.

GPT:
Reviewed `fc844aa` (checkout `d9a239d`) against the cumulative round-one and round-two record.
Findings:

1. Medium — two URL entry points still use a stat-then-read bound.
[ImportViewModel.swift (line 104)](OpenFactor/Import/ImportViewModel.swift:104) checks `fileSizeKey`, then [`:112` (line 112)](OpenFactor/Import/ImportViewModel.swift:112) performs a separate unbounded `Data(contentsOf:)`. Likewise, the share extension checks the provider file at [ShareViewController.swift (line 128)](OpenFactorShare/ShareViewController.swift:128), copies it, then reads the copy unbounded at [`:145` (line 145)](OpenFactorShare/ShareViewController.swift:145). A hostile file provider or sender can replace/grow the file after the size check; the later `data.count` guard runs after allocation. `SharedInbox.take` correctly avoids this with one open handle and `limit + 1` bytes. Use one bounded handle read for the URL paths too.
2. Low — known image routes use the archive ceiling before the policy ceiling.
[ImportLimits.swift (line 42)](Sources/OpenFactorCore/Import/ImportLimits.swift:42) permits 12,233,388 bytes. The share extension uses that before copying at [ShareViewController.swift (line 130)](OpenFactorShare/ShareViewController.swift:130), and `SharedInbox.take` uses it at [SharedInbox.swift (line 245)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:245). But these paths carry only images, whose actual policy is 8 MiB and is checked only after the data is loaded. An 8–12.2 MiB image is therefore copied/read and then rejected. Pass the image policy bound into these routes and bounded-read against it.
3. Informational — a new comment describes behavior that does not exist.
[ManualSetupViewModel.swift (line 60)](OpenFactor/Scanning/ManualSetupViewModel.swift:60) says manual entry refuses a short secret “unlike an import,” which truncates it. The import readers also reject short secrets with `.secretTooShort`; truncation applies to labels through `AccountLabel`, including manual accounts. The refusal behavior is correct, but the comment should be corrected.

The main round-three fixes are otherwise faithful: the writer now checks the exact plaintext ceiling before sealing, manual enrollment applies both account limits, the JSON sniff scans all already-bounded input, and `SharedInbox.take` uses a single bounded handle read. The work is converging, but the URL/image boundary fixes still move the risk between preflight, copying, and reading rather than enforcing one atomic bounded-read primitive.
