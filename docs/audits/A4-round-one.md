# A4 round one: what three engines found, and what that says about the method

Round one of gate A4 is complete: three engines, four scopes, twelve passes, all against commit
`74fe841`. The passes and their triage are in `A4-scope1-vault.md`, `A4-scope2-watch.md`,
`A4-scope3-parsers.md` and `A4-scope4-boundaries.md`.

**44 distinct items were confirmed against the code.** The counts below are taken from the summary
matrix at the end of each scope file, not from memory, and "unique" means exactly one engine
reported it.

## The count

| Scope | ChatGPT 5.6 Sol | Fable 5 | Grok 4.6 | Items |
| --- | --- | --- | --- | --- |
| 1, the vault at rest | 5 found, 1 unique | 6 found, 3 unique | 6 found, 2 unique | 11 |
| 2, the Watch exchange | 4 found, 0 unique | 7 found, 3 unique | 8 found, 2 unique | 11 |
| 3, the parsers | 6 found, 3 unique | 5 found, 1 unique | 6 found, 2 unique | 11 |
| 4, the boundaries | 5 found, 1 unique | 6 found, 2 unique | 6 found, 4 unique | 11 |
| **Total** | **20 found, 5 unique** | **24 found, 9 unique** | **26 found, 10 unique** | **44** |

**Only three of the 44 were reported by all three engines**: the watchOS protection class, the
phone answering "asking" to a request it discards, and the inbox never being swept at launch.

## Accuracy

ChatGPT and Fable had nothing rejected in triage.

Grok had two. Its claim that the padding document's "collapse into one bucket" sentence was
already false does not hold, because that sentence describes the published test vector, whose toy
metadata genuinely does fit one bucket; the observation behind it was accepted. And it concluded
that multiple scenes were not declared, reasoning from `TARGETED_DEVICE_FAMILY` in the project
file, when the shipped `Info.plist` declares `UIApplicationSupportsMultipleScenes = true`. It
filed that one as a maybe it would not promote, which is the right instinct on an uncertain
reading, and it was still wrong.

## Severity inverts the ranking

Four findings stand above the rest: the wrapped key never syncing, which loses every account when
a phone is replaced; the `otpauth-migration://` crash any app on the device can trigger; App Lock
and the cover protecting only one window scene; and enrollment accepting accounts the backup
format refuses to restore.

**ChatGPT found three of those four.** It has the fewest findings and the highest value per
finding.

## Rating

**Grok 4.6, best overall.** The most findings, the most unique findings, and something nobody else
had in all four scopes. It produced the two sharpest meta-findings of the gate: that deleting the
HKDF domain-separation label passes the entire test suite, and that `SECURITY.md`'s claim about
its own tests was false. Against that, both accuracy slips were its.

**Fable 5, close second, and the one whose claims needed the least checking.** The best
verification discipline of the three: it re-derived both published backup test-vector keys
independently in Python, established `UnicodeScalar(Int)`'s failability by executing it rather
than assuming, and verified the git state before reading a line. Nothing rejected. Its findings
clustered on write-ordering defects, which are the hardest class to see and the ones most likely
to destroy data.

**ChatGPT 5.6 Sol, fewest findings, biggest hits.** The only crash and the only confidentiality
failure were both its, and it was right about multiple scenes where another engine looked and
concluded otherwise. Terser and less exhaustive; the best instinct for what actually matters.

## What the gate was testing, and what it found out

The gate argued for three vendors on the grounds that two models from the same lab share the blind
spot that matters most. That was a prediction, and it can now be checked.

**Any single engine, run alone, leaves at least one catastrophic defect in the code.** ChatGPT
alone misses `replacePassphrase` invalidating a recovery credential nobody ever saw. Fable alone
misses both the sync gap and the crash. Grok alone misses the multi-scene lock failure. Three
findings in 44 were common to all three, and the overlap between any two was small.

**The single most useful thing was not a defect at all**, but two demonstrations that the test
suite would not notice a serious regression: a static ephemeral key on the phone side, and a
deleted HKDF label, each of which passes all 358 tests. Both share one cause, which is worth
stating on its own: the suite tests the two sides of an exchange against each other, so any change
applied symmetrically to both sides passes. A round trip detects a disagreement, never a weakened
construction.

**A prompt defect cost real findings, and it is recorded rather than smoothed over.** Scope 1's
file list named what was central to the subject rather than what a reviewer needs to follow a
claim to its end, and the one engine that stayed inside its list missed the most serious defect in
that scope and said so at the time. The lists for scopes 2, 3 and 4 were rebuilt before those
scopes ran, and every scope now says that anything an attached file references may be opened.

**One scope could not be read cold by anybody**, and an engine said so unprompted. Scope 2's code
comments narrate the previous review's findings in detail, which anchors a reviewer toward the
defect classes already found. That is a real cost of a practice this project otherwise benefits
from, and a reader comparing yields between scopes should know the two were not equally readable.
