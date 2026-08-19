# A4 round two, scope 4: what three engines found in the fixes

Round two of scope 4 read `6254706`. The account it responded to is `A4-round-two-scope4.md`, and
all three engines returned.

| Engine | Verdict |
| --- | --- |
| Grok 4.6 | One medium. "The one I would not accept is the mtime clamp" |
| ChatGPT 5.6 Sol | Four medium, five low. "Five of the eleven fixes fully close their findings" |
| Fable 5 | Ten of eleven real and verified; one incomplete, two new, four documentation |

**All three rejected the same fix, and none of the three accepted it.** That has not happened
before in this gate: previous rounds produced disagreement about severity or about whether a
construction was sound. Here the three engines independently walked the same mechanics to the same
conclusion.

## The rejected fix

**S4-8, the mtime clamp, does not close the finding it answers, and it disables the fix for S4-2.**

The finding was that freshness read a timestamp the app did not write, so a file stamped in the
future sorts ahead of everything and looks newer than anything that could really have arrived. The
fix clamped `arrived` to `min(stamped, now)`. Walk it:

```
stamped = year 2090
arrived = min(2090, now) = now      recomputed on every read
age     = now - arrived = 0         on every read, forever
```

So the planted item still sorts first, because every genuine share has `arrived < now` by the time
anything reads it. It still passes the ten minute freshness test. And it can never satisfy
`sweepStale`, which asks whether the age exceeds five minutes. **The item the launch sweep was
built to remove is now the one item in the container the sweep can never remove.**

Grok's sequence: the extension writes a real transfer QR; a sibling in the same app group writes
one stamped a day ahead; the owner launches, the sweep spares both, they unlock, `collect` takes
the planted one because it sorts first, and the deferred sweep deletes the genuine share. Grok
adds a version needing no sibling at all: set the clock forward, share, set it back.

**The test written for this fix asserts `arrived <= now`, which is true of an immortal file.** All
three said so in their own words. The round-two brief for this scope said the clamp "only stops an
item claiming the future" and that a back-dated item sweeping sooner is "the safe direction, and is
worth confirming rather than assuming". Fable's reply: confirmed not to hold.

All three named the same fix: a stamp beyond a small clock skew is impossible for a legitimate
write, so treat it as `.distantPast`, where it sorts last and sweeps immediately.

## What was accepted

Ten of the eleven original findings are closed, with the two that mattered most closed properly.
**S4-1**, the multi-scene lock and cover failure, is closed as a class rather than an instance:
no second scene can exist, the plist declares it, the project file pins the generation off, and CI
checks both. **S4-2**, the unswept inbox, ends the round-one sequence in deletion at the next
launch, with tests pinning both directions.

Also closed: the migration crash and its reproducer, the masking of every live code, the arrival
that used to be destroyed by a second URL, the normative lock table, the bounded `take`, the backup
exclusion, the extension's in-memory bound, and the clipboard rule that decides whether a
passphrase may leave the device.

## The eleven, as the three engines left them

| # | Finding | Disposition |
| --- | --- | --- |
| S4-1 | one window scene | closed, all three. Grok records a CI gap, filed as S4-21 |
| S4-2 | inbox never swept | closed for the reported case. The resident-process gap is S4-13 |
| S4-3 | inbox eligible for backup | closed on the success path. The fail-open is S4-17 |
| S4-4 | `take` unbounded | closed on the success path. The fail-open and race are S4-18 |
| S4-5 | migration crash | closed. The false comment is S4-16, the missing test S4-22 |
| S4-6 | previews never mask | closed for live codes. The surviving class member is S4-12 |
| S4-7 | second URL destroys an arrival | closed. The new silent loss is S4-15 |
| S4-8 | freshness trusts an mtime | **not closed. All three rejected it** |
| S4-9 | the lock's normative table | closed, verified against code and test |
| S4-10 | extension bound after materialization | memory closed. The disk copy is S4-19 |
| S4-11 | `localOnly` pinned by no test | closed. The dead table cell is S4-16 |

## What round two added

Eleven new items, numbered so they can be discussed.

| # | Finding | Severity | Engines |
| --- | --- | --- | --- |
| S4-12 | a manually entered secret stays legible while the screen is captured | medium | ChatGPT, Fable |
| S4-13 | the sweep runs at launch only, so a resident process holds an item indefinitely | medium | ChatGPT, Fable, Grok |
| S4-14 | the sweep deletes at five minutes what the freshness rule presents until ten | low | all three |
| S4-15 | a second arrival is dropped with no signal, and no test | low | all three |
| S4-16 | six documentation and comment claims the code does not do | low | all three |
| S4-17 | the backup exclusion is applied with `try?` and the write proceeds anyway | medium | ChatGPT |
| S4-18 | `take`'s bound is skipped when the size cannot be read, and races a replace | medium | ChatGPT |
| S4-19 | the extension copies the whole attachment to disk before measuring it | low | ChatGPT, Grok, Fable |
| S4-20 | `sweepStale` only considers UUID names, so a planted name persists | low | Grok |
| S4-21 | the CI check cannot catch the regression it was written for | low | Grok |
| S4-22 | the only reproduced crash in this project has no test for its bound | low | Fable |

**S4-12 is the one to read first.** It is a new defect on the screen the masking fix touched, and
it is worse than what was masked: `ManualSetupView` renders the permanent secret in a plain
`TextField` when the eye is tapped, and that branch never consults `isScreenCaptured`. Enter a
secret by hand while mirroring a meeting, tap to check for a typo, and the audience receives the
seed itself rather than a code that expires in seconds. `SECURITY.md`'s updated paragraph opens
with "Secrets are hidden while the screen is being captured", which this contradicts by its own
headline.

**S4-13 and S4-14 are the same disagreement seen twice.** ChatGPT rates the launch-only sweep a
medium and says five minutes "is not a deletion deadline; it is merely a condition evaluated once".
Fable and Grok accept it as a real narrowing and file the residual. Nobody defends the five against
ten split: an item aged between them is worth presenting by one rule and deleted unread by the
other, and which wins depends on whether iOS kept the process alive.

**S4-16 collects six claims**, and one of them has a history worth recording: `SECURITY.md` says
the extension "passes a URL carrying only an identifier", which is false and was **confirmed in
round one**. Fable traced why it survived: it was acknowledged in triage as leftover and never
assigned a number, so it was never on the list of eleven and was never fixed. The others are the
`SharedInbox` header claiming the whole directory is swept at every launch and that an item exists
for seconds, the `write` comment about a URL that no longer leaves the process, the extension
comment saying the size is known before the copy, `APP_LOCK.md` saying items older than ten minutes
are swept and that an arrival always takes precedence, the "saturating add" comment on `&+` which
wraps rather than saturates, and a clipboard lifetime for codes that nothing reads and a test pins.

## What this round says about the method

**The rejected fix is the second time a plausible one-line answer passed its own test.** Scope 1's
creation check tested "a record was already there" while the defect was "a record arrives during
the derivation". This one tested "arrived is not in the future" while the defect is "the item is
always exactly as fresh as now". Both tests were written by whoever wrote the fix. Both passed.
Both were blind in precisely the way the fix was blind.

**And the brief for this round predicted the wrong thing.** It said the mtime clamp only stops an
item claiming the future, that a back-dated item sweeping sooner "is the safe direction", and asked
for that to be confirmed rather than assumed. The safe direction was never the question: the
dangerous direction was forward, and the clamp turned it into a permanent present.
