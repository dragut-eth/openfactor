# Gate A4: the board, preserved

**This is the dashboard that ran alongside gate A4, written down so it cannot be lost.** It
existed as a rendered widget in a working session, redrawn twenty nine times as the gate moved,
and a rendered widget lives only as long as the session that drew it. Everything below is
recovered from those renders rather than rewritten from memory: the findings carry the words the
board carried, including the wording that was later shown to be wrong.

**It is a record of a board, not a replacement for the results documents.** Each finding's
reasoning, the returns behind it, and what was actually done live in the other files in this
folder. This is the index and the arc.

## Where the gate finished

| | |
| --- | --- |
| **Findings raised** | 133 across four scopes |
| **Review rounds** | 20 across the four scopes, plus 11 closed-question verification briefs |
| **Open highs** | 0 |
| **Open mediums** | 0 |
| **Open lows** | 0 |
| **Waived, with what would reopen each** | 2, S1-33 and S1-40 |
| **Withdrawn as not real** | 2, S1-37 and S1-39 |
| **Void, retracted by the reviewer who filed it** | 1, S4-22 |

**The last board rendered before this file showed one low still open.** S4-45 and S1-34 were
closed after it, which is what the commit for the last two lows means when it says nothing is
left in the gate above a decision. The two waivers are that decision.

## What the board actually tracked

Four scopes, reviewed independently by three models, each scope taking as many rounds as it
needed rather than a fixed number.

| Scope | Subject | Rounds | Findings |
| --- | --- | --- | --- |
| **S1** | the vault at rest | 5, plus verification rounds | 40 |
| **S2** | the watch key exchange | 7 | 27 |
| **S3** | the parsers | 3 | 21 |
| **S4** | the boundaries | 5, plus verification rounds | 45 |

**The scope with the most findings is not the most dangerous one.** Scope 4 ran to forty five
because the boundary surface is wide and mostly prose and comments; scope 1 produced the highs
that would actually have cost somebody their accounts.

## The three counts that mattered, and why they moved backwards

The board carried running counts of accepted, fixed-but-unreviewed and open. **Those counts went
backwards more than once, and that is the most useful thing this record preserves.** A review
round that reads eleven fixes and opens eleven new items is not a failure of the round. It is the
gate working. What it looks like on a dashboard is a number getting worse.

**Three separate times, a fix filed in this gate created the next finding.** Round four of scope
4 opened two mediums, one of which was made by our own fix. Round four of scope 1 opened a high,
found by all three engines, introduced that same session by the fix for S1-12. And S1-39 was
manufactured entirely by the repair for S1-37, a finding that turned out not to be real.

## The register

Severity is the severity the board carried at the time it was filed. Wording is the board's own,
kept even where a later round corrected the diagnosis behind it.

### Scope 1, the vault at rest

| ID | Finding, in the board's words | Severity | Final |
| --- | --- | --- | --- |
| **S1-1** | the wrapped key never syncs, so a replaced phone loses every account | high | closed |
| **S1-2** | the watch writes the vault key without complete protection | medium | closed |
| **S1-3** | a differing sync flag makes a twin record rather than an error | medium | closed |
| **S1-4** | the key is written before it is excluded from backup | medium | closed |
| **S1-5** | a read failure looks like an empty device, whose remedy destroys it | medium | closed |
| **S1-6** | creation overwrites a record that arrives during the key derivation | high | closed |
| **S1-7** | re-reading the state discards a passphrase that is on screen | medium | closed |
| **S1-8** | a replacement passphrase is saved before anybody has seen it | medium | closed |
| **S1-9** | a record from a newer version is reported as a wrong passphrase | low | closed |
| **S1-10** | the normative page disagrees with the code in five places | low | closed |
| **S1-11** | padding's residual size class is never stated | low | closed |
| **S1-12** | two wraps can coexist after creation, and unlock picks one unspecified | medium | closed |
| **S1-13** | the launch reconcile abandons a failure silently | medium | closed |
| **S1-14** | the wrapped store's sync flag is a launch-time snapshot | low | closed |
| **S1-15** | the vault key read is bounded only when the file system answers | low | closed |
| **S1-16** | seven comments claim what the code does not do, four written this round | low | closed |
| **S1-17** | an open list draws dashes when its records change underneath, found on hardware | low | closed |
| **S1-18** | a successful unlock deletes wraps it has no evidence are dead, and a synced delete reaches every device on the account | high | closed |
| **S1-19** | save with twins updates one of them unspecified: the same destruction, needing no unlock | medium | closed |
| **S1-20** | discard identifies a record by its flag alone, so iCloud writing into that slot means the replacement dies | low | closed |
| **S1-21** | the test builds two live vaults and asserts one is destroyed; the fake cannot show a delete leaving the device | medium | closed |
| **S1-22** | candidates and discard are executed by no test anywhere, in either suite | medium | closed |
| **S1-23** | six claims the code does not make, five of them travelling with the discard | low | closed |
| **S1-24** | the half hour is right about a second device and wrong about a replacement one | low | closed |
| **S1-25** | a synchronizable record is written with a device-only protection class; Apple forbids the pairing | medium | closed |
| **S1-26** | the twin refusal counts, then selects separately, so a record arriving between them is still overwritten | medium | closed |
| **S1-27** | the rollback reads the preference a second time and can delete the record it was meant to protect | low | closed |
| **S1-28** | the twin state breaks the sync toggle forever, and disabling leaves the switch claiming iCloud holds what it does not | low | closed |
| **S1-29** | the refusal's message can read as saying the new passphrase works, and has nowhere to appear | low | closed |
| **S1-30** | the write-time test checks the flag and not the class; nothing covers the toggle under twins | low | closed |
| **S1-31** | a record already written with the broken pairing is never repaired, and nothing detects it | medium | closed |
| **S1-32** | the pairing rule has a fifth home, written out inline where the brief claimed four | low | closed |
| **S1-33** | same-slot substitution: contested between a remaining medium and a named API floor | medium | waived |
| **S1-34** | the seam can express that case and no test does; the existing one plants under the opposite flag | low | closed |
| **S1-35** | the repair swallows a failed update and the toggle converts every account anyway | medium | closed |
| **S1-36** | the new test accepts any error rather than the one it means | low | closed |
| **S1-37** | twenty six Keychain tests execute in no job and on no machine | low | withdrawn |
| **S1-38** | a twin forming between the count and the update collides and is reported as duplicate | low | closed |
| **S1-39** | the Keychain half of SecretStoreTests runs nowhere | low | withdrawn |
| **S1-40** | contested: the disable path can move accounts before the refusal, on an arrival | low | waived |

_40 findings._

### Scope 2, the watch key exchange

| ID | Finding, in the board's words | Severity | Final |
| --- | --- | --- | --- |
| **S2-1** | the watch writes the vault key without complete protection | medium | closed |
| **S2-2** | a kill leaves a complete key on disk outside the backup exclusion | medium | closed |
| **S2-3** | the phone answers "asking" to a request it then discards | medium | closed |
| **S2-4** | a refusal names no request, so it ends the wrong attempt | medium | closed |
| **S2-5** | a randomness failure leaves a stale attempt behind | low | closed |
| **S2-6** | a late failure can demote a watch that is already working | low | closed |
| **S2-7** | consent has no deadline, so an old question still releases the key | medium | closed |
| **S2-8** | a static phone keypair passes the entire test suite | medium | closed |
| **S2-9** | deleting the HKDF label passes the entire test suite | medium | closed |
| **S2-10** | the vault page claims a Secure Enclave key that never existed | low | closed |
| **S2-11** | the security page claims tests that were never written | low | closed |
| **S2-12** | the consent timer wakes at the window and expires nothing | low | closed |
| **S2-13** | the key is read before the request is validated or the app checked | low | closed |
| **S2-14** | a current build can send the nonce-less decline only old builds should send | low | closed |
| **S2-15** | a phone that cannot read its key refuses in silence | low | closed |
| **S2-16** | one wire vocabulary now has two readers | low | closed |
| **S2-17** | the asking cadence and the timer's arming are still decisions in the app | low | closed |
| **S2-18** | two rules have no test | low | closed |
| **S2-19** | the exact consent boundary is inclusive: one engine files it, two call it physics | low | closed |
| **S2-21** | a malformed request is answered with a nonce-less decline, which two documents say means an old build | low | closed |
| **S2-22** | a comment claims only an answer can arrive on the reply path | low | closed |
| **S2-23** | a test anchors on a fresh clock read and can flake red | low | closed |
| **S2-24** | the seam header counts two decisions and there are three, and the twin header lists neither | low | closed |
| **S2-25** | the decline correction reached the markdown and not the four core comments | low | closed |
| **S2-26** | the paragraph under the list says those decisions predate the extraction and produced no finding; two of them do neither | low | closed |
| **S2-27** | "nothing was ever read out of it" is false: a bad public key is rejected after the nonce is read | low | closed |
| **S2-28** | contested: is the watch's reply routing a fourth decision, or is it cadence? one engine says yes, two say no | low | closed |

_27 findings._

### Scope 3, the parsers

| ID | Finding, in the board's words | Severity | Final |
| --- | --- | --- | --- |
| **S3-1** | an account can be enrolled that its own backup will refuse to restore | high | closed |
| **S3-2** | a crafted migration link crashes the app, from any other app | high | closed |
| **S3-3** | the import cap silently retires the backup format's frozen ceiling | medium | closed |
| **S3-4** | the size bound runs after the file is already copied into memory | high | closed |
| **S3-5** | the writer can emit an archive this app will not read back | low | closed |
| **S3-6** | the same account twice in one file is added twice | low | closed |
| **S3-7** | a byte order mark or whitespace defeats the format sniff | medium | closed |
| **S3-8** | a short secret is refused for a reason that is not true | low | closed |
| **S3-9** | the photo picker path has no size bound at all | low | closed |
| **S3-10** | the app tells people to delete the encrypted backup they just used | low | closed |
| **S3-11** | the order accounts were arranged in is read and thrown away | low | closed |
| **S3-12** | manual entry accepts what the format forbids, and export blames the past | medium | closed |
| **S3-13** | the in-memory bound now runs after a full JSON parse | low | closed |
| **S3-14** | the size preflight fails open when no size is available | medium | closed |
| **S3-15** | four comments claim what the code does not do, two written this round | low | closed |
| **S3-16** | two URL paths stat then read separately, filed by one engine, passed by two | medium | closed |
| **S3-17** | image routes preflight at the archive ceiling, so a large image is copied then refused | low | closed |
| **S3-18** | seal skips the passphrase and storable checks, and nothing says so | low | closed |
| **S3-19** | looksLikeJSON is dead code wearing a stale comment | low | closed |
| **S3-20** | the refusal says "too large" when the size could not be read | low | closed |
| **S3-21** | a comment claims importers truncate secrets; they refuse them | low | closed |

_21 findings._

### Scope 4, the boundaries

| ID | Finding, in the board's words | Severity | Final |
| --- | --- | --- | --- |
| **S4-1** | the lock and the snapshot cover protect only one window scene | high | closed |
| **S4-2** | shared inbox leftovers are never swept, despite two documents saying so | medium | closed |
| **S4-3** | a shared QR of every secret is eligible for device backup | medium | closed |
| **S4-4** | taking an inbox item reads it with no bound | medium | closed |
| **S4-5** | a crafted migration link crashes the app, from any other app | high | closed |
| **S4-6** | two preview screens show live codes while the screen is recorded | medium | closed |
| **S4-7** | a second link silently destroys an arrival waiting to be confirmed | low | closed |
| **S4-8** | freshness believes a timestamp the app did not write | low | closed |
| **S4-9** | the lock's normative table would break working code if followed | low | closed |
| **S4-10** | the extension measures an attachment after loading all of it | low | closed |
| **S4-11** | whether a passphrase may leave the device is pinned by no test | low | closed |
| **S4-12** | a hand-entered secret stays legible while the screen is captured | medium | closed |
| **S4-13** | the sweep runs at launch only, so a resident process keeps an item | medium | closed |
| **S4-14** | deleted at five minutes, still presented until ten | low | closed |
| **S4-15** | a second arrival is dropped with no signal and no test | low | closed |
| **S4-16** | six comments and documents claim things the code does not do | low | closed |
| **S4-17** | the backup exclusion fails open and the write proceeds anyway | medium | closed |
| **S4-18** | take's bound is skipped when the size cannot be read, and races | medium | closed |
| **S4-19** | the extension copies the whole attachment to disk before measuring | low | closed |
| **S4-20** | the sweep only considers UUID names, so a planted name persists | low | closed |
| **S4-21** | the CI check cannot catch the regression it was written for | low | closed |
| **S4-22** | the only reproduced crash has no test for its bound | low | void |
| **S4-23** | take blocks the main actor on a named pipe, and never removes it | medium | closed |
| **S4-24** | now is captured before attributes, so a share arriving mid-sweep is deleted | low | closed |
| **S4-25** | the unknown-name sweep can delete an in-progress atomic write | low | closed |
| **S4-26** | collection's deferred sweep deletes what arrived after its snapshot | low | closed |
| **S4-27** | the inbox never fills the queue's second slot | low | closed |
| **S4-28** | the queue's promotion rides a SwiftUI side effect and can wedge | low/med | closed |
| **S4-29** | the extension's preflight accepts a non-regular file representation | low | closed |
| **S4-30** | a lowercase UUID name is listed but cannot be taken | low | closed |
| **S4-31** | the inbox prose trails the code by one fix, for the third round | low | closed |
| **S4-32** | a failed take still runs the full sweep, so one poison file deletes every real share, reachable because we fixed the hang | medium | closed |
| **S4-33** | the inbox is resolved by pathname, so a replaced directory redirects the sweep out of the container | medium | closed |
| **S4-34** | last wins is built for URLs only; a share arriving after a URL waits, and nothing re-runs collection | low | closed |
| **S4-35** | onOpenURL's unconditional sweep is a fourth site racing the extension's write, added this round | low | closed |
| **S4-36** | the supersede destroys the only copy of a pending import; three engines score it three ways | low | closed |
| **S4-37** | the wedge returns through the sheet swap, and the four-of-four measurement was of the queue, not of this | low | closed |
| **S4-38** | APP_LOCK says the newest wins on line 42 and nothing else pending on line 233; the code does both | low | closed |
| **S4-39** | BoundedFile claims the read cannot be raced and that excess bytes were never held; neither is exact | low | closed |
| **S4-40** | three files still describe the lock as replacing the root; SECURITY.md still sweeps at launch | low | closed |
| **S4-41** | the clock is sampled before the listing, so a share written during the pass reads as ancient and is deleted | medium | closed |
| **S4-42** | a UUID-named directory is admitted as a candidate, refused by the reader, and can never be removed | low | closed |
| **S4-43** | the exact directory entry is still not carried through: the name read and the name deleted can differ | low | closed |
| **S4-44** | the whole-seconds ordering bug I disclosed has no regression test, and nothing tests the primitive directly | low | closed |
| **S4-45** | seven false claims, two written by this change, and two stale lock sentences S4-40 missed | low | closed |

_45 findings._
## The twenty nine boards, in order

**The captions are the gate's narrative.** Read down the right hand column and the shape of
the whole gate is there: findings, regressions, corrections, and the day three reviewers made
the same mistake.

| # | Board | What it said |
| --- | --- | --- |
| 1 | `a4_gate_status_dashboard` | 44 round-one findings across four scopes, 21 fixed and 23 open, with scope 2 alone having been through two further review rounds and a third now in flight. |
| 2 | `a4_gate_status_after_scope1` | Scopes 1 and 2 are closed at 11 of 11 findings each, scopes 3 and 4 have 16 open between them, scope 2 has survived three review rounds and scope 1 is ready for its second. |
| 3 | `a4_gate_four_rounds_status` | Gate A4 across four rounds: round one found 44 findings, round two overturned 5 of the 22 fixes it read, round three found one defect all three engines reached independently, and round four is in flight on the extraction. |
| 4 | `a4_per_issue_status_board` | All 44 findings listed by scope with a unique number, severity, and whether an external session has accepted the fix. |
| 5 | `a4_issue_board_after_scope4_round2` | After scope 4's round two: 10 of its 11 findings accepted, one fix rejected by all three engines, and eleven new items opened. |
| 6 | `a4_issue_board_after_scope3_round2` | After scope 3's round two: both reviewed scopes now carry open items, with one fix in each rejected by all three engines, and no new high severity findings. |
| 7 | `a4_issue_board_after_scope1_round3` | After scope 1's round three: every high severity finding is now accepted, no fix was rejected this round, and twelve items remain open across three scopes. |
| 8 | `a4_issue_board_after_scope4_round3` | After scope 4's round three: eleven of twelve items closed, one finding retracted by the reviewer who filed it, ten new items opened and only one medium. |
| 9 | `a4_issue_board_after_scope2_round4` | After scope 2's round four: all eleven original findings accepted, seven new items all low severity, and the first round of the gate with no medium or high. |
| 10 | `a4_board_morning_open_items` | 25 items open across four scopes, six of them medium, none high, with the four documentation items closed. |
| 11 | `a4_board_corrected_review_status` | Corrected: 53 items accepted by reviewers, 9 fixed but not yet reviewed, and 19 still open. |
| 12 | `a4_board_after_scope3_round3` | After scope 3's round three: 59 items accepted, 3 fixed but unreviewed, 25 open with four mediums, and no engine rejected a fix this round. |
| 13 | `a4_board_after_both_blocks` | After both fix blocks: 59 accepted, 16 fixed but not yet reviewed, and 12 still open with two mediums. |
| 14 | `a4_board_after_round_five` | After scope 2's round five: 76 accepted, 14 fixed but unreviewed, 11 open, no highs and no mediums anywhere except one in scope 1. |
| 15 | `gate_a4_board_after_scope2_round_six` | After scope 2's round six: 75 accepted, 13 fixed but unreviewed, 7 open, all low, no highs and no mediums anywhere. |
| 16 | `gate_a4_board_after_scope2_round_seven` | After scope 2's round seven: 76 accepted, 14 fixed but unreviewed or contested, 8 open and all low, nothing above low anywhere. |
| 17 | `gate_a4_board_after_scope4_round_four` | After scope 4's round four: two mediums are back, twelve items open in scope 4, and one of the mediums was created by our own fix. |
| 18 | `gate_a4_board_after_scope1_round_four` | After scope 1's round four: a high is open, found by all three engines, and it was introduced this session by the fix for S1-12. |
| 19 | `gate_a4_board_after_scope4_round_five` | After scope 4's round five: S4-24 was never fixed, the comment above it describes the fix that was not made, and the engines split three ways on the verdict. |
| 20 | `gate_a4_board_after_scope1_round_five` | After scope 1's round five: the high is gone and all three engines agree, but the S1-14 fix wrote a synchronizable record with a device-only protection class. |
| 21 | `gate_a4_board_after_s4_41_verified` | After S4-41 was verified fixed by all three engines: two mediums remain, both in scope 1, and no round returned new work. |
| 22 | `gate_a4_board_after_s4_42_s4_44_verified` | After S4-42 and S4-44 were verified fixed by all three engines: eight items open, two mediums, both in scope 1. |
| 23 | `gate_a4_board_after_s1_25_verified` | After the S1-25 verification: the write is fixed but records already written stay broken, so one medium is open again. |
| 24 | `gate_a4_board_after_s1_26_verified` | After the S1-26 verification: the second selection is gone, a same-slot remainder survives, and one engine calls it a floor that may not be one. |
| 25 | `gate_a4_board_after_s1_31_verified` | After the S1-31 verification: the repair works but swallows its own failure, so an explicit sync enable can convert every account while the wrapped key stays device-only. |
| 26 | `gate_a4_no_highs_no_mediums` | After S1-35 was verified: no high and no medium is open anywhere, leaving eight lows and one waiver to triage. |
| 27 | `gate_a4_six_lows_and_a_coverage_void` | After three items were verified fixed: six lows remain, and one of them is that twenty six Keychain tests execute nowhere. |
| 28 | `gate_a4_five_lows_remaining` | After S1-37 and S1-28 were verified: no highs or mediums, five lows remain, and one engine found a race between the count and the update. |
| 29 | `gate_a4_one_low_open` | After the final verification: the correction is unanimously confirmed, one low remains open, and three people made the same reasoning error in one day. |

## The panels that were not findings

The board carried standing panels for things that were not a defect in the code but a pattern in
the work. They are the part of the dashboard least likely to survive anywhere else, so they are
kept here in full.

### A static check standing in for a dynamic one

**Four times in one day, by three different reviewers including the author.**

- Checked which CI jobs run a suite, inferred where that suite executes, never checked target
  membership. That inference became S1-37, a finding that was not real.
- Checked what can be admitted as a candidate, inferred what can be present when it is used.
- One engine cleared the same sentence the same way.
- One engine wrote the gate's most rigorous passage on inheriting an unchecked premise, and then
  did exactly that one section later.

**The shape is always the same**: something checkable by running it gets settled by reading it,
and the reading is correct about every fact it names while being wrong about the fact it did not
name.

### The App Lock family

**Nine sentences, six files, three correction passes, three still wrong afterwards.**

Every previous correction had been a partial sweep of a set nobody had enumerated. The fix was
not a fourth sweep: it was to make `docs/APP_LOCK.md` the single description and give every
dependent a local consequence plus a pointer. All three engines recommended that over correcting
three more sentences.

**The same move as `forSync`**, where one pairing rule lived at five call sites and had drifted at
two of them. Class sweeps beat instance fixes, repeatedly, across this whole gate.

### The verification round

**The closed-question rounds never produced a backlog.** The format was one finding, the change
in front of it, and a yes or no. Three of those rounds ended two to one, and
each time the dissent was specific and each time it was right.

**The open questions produced the opposite.** The value came out of the closed ones.

## What this board never showed

**Nothing about the trust question.** The board tracked findings, and a gate of findings does not
say whether somebody should put their accounts in this app. That was asked separately, at the
end, and answered separately.

**Nothing about coverage.** Twenty review rounds say nothing about the controls nobody chose
to look at, which is why `docs/MASVS.md` exists as a different instrument rather than as a
summary of this one.

## Where the reasoning lives

Every finding above has its returns, its analysis and its fix recorded elsewhere in this folder.
The round files carry the reviews as they came back, the `A4-verify-*` files carry the
closed-question rounds, and the `E*` files carry the hardware measurements the arguments rested
on.
