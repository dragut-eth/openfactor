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

---

# What was done

**Review commit for round three: `83e5cdd`.** All twelve open items are fixed.

**S4-8, the rejected fix.** A stamp after now is refused rather than clamped: it is treated as
`.distantPast`, which sorts it last and makes it immediately sweepable. The test that replaced the
old one asserts the two properties the clamp version passed while failing, that a genuine share is
the one offered and that the plant is gone after a sweep. Reverting to the clamp makes it red.

**S4-13.** The sweep runs on every activation, not once per process.

**S4-14.** `staleAfter` is `freshness`. One idea, one constant, and a test that fails if they
drift apart.

**S4-15.** `ArrivalQueue` is a value type in the core with five tests. The first arrival keeps the
screen, one more is held behind it, and a third is refused. Both of this item's previous versions
were wrong and neither had a test, because the rule lived in a closure in the scene body.

**S4-17 and S4-18, the fail-open pair.** The backup exclusion is read back and the write refused if
it did not take. `take` opens once and reads a bounded amount through the handle, so there is no
size lookup to skip and no second call for a writer to race.

**S4-12.** The reveal control is disabled while the screen is captured and the field stays secure.
Disabled rather than hidden, so the reason is visible.

**S4-19.** The extension measures the system's file inside the callback and fails closed, before
copying anything.

**S4-20.** A name this app did not write is swept on sight.

**S4-21.** The CI check fails on silence: both build configurations must carry the generation
switch set to NO, so deleting the lines is a failure rather than a pass. The pattern was also
wrong, missing the quotes the project file uses, and would have failed for the wrong reason.

**S4-22.** The migration crash has tests for its bound in both directions. Removing the guard makes
them **trap** rather than fail, which is the original crash reproducing inside the suite.

**S4-16, the six claims.** The extension passes nothing to the app; an item exists until it is
confirmed or swept rather than for seconds; the sweep is not the whole directory at every launch;
the size is known before the copy, which is now true rather than corrected; `&+` is described as
the wrapping add it is; and the clipboard's code lifetime is read by the path that needs it instead
of being pinned by a test and used by nothing.

## For round three

The three questions, and the fourth about convergence. Where to look:

**`take` was rewritten rather than patched**, and it is the path that reads whatever a shared
container holds. It now opens a handle, reads one byte past the limit, and refuses. Check the
refusal, the empty file, and the file that disappears between opening and reading.

**The sweep now runs on every activation and removes unknown names.** It is the only code in this
project that deletes files it did not write, in a directory another process can write to.

**`ArrivalQueue` holds a bound of two with a deliberate refusal beyond it.** Ask whether dropping
the third is better than the alternative, and whether the binding that promotes the next one can
lose an arrival on a redraw.

**The exclusion now throws**, so a share can fail where it previously succeeded quietly. That is
the intended trade and it is worth saying whether the failure is the right one.

**S4-8 was rejected once already.** The question is not whether the new rule is different but
whether it is right: is there a legitimate writer that stamps a file in the future, and does
refusing it lose anything real?

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Grok:
Scope 4, round two

Code under review: 6254706
Checkout read: 6d14a1f (differs only in HANDOFF.md)
Round one read: 74fe841
What-changed file names 8471c33. Source at 6254706 is that commit plus two audit markdown files.

This is the same engine as the Grok pass in A4-scope4-boundaries.md. I am not treating that as authority. Where a fix only looks like a response to something I wrote, that is called out.

───

Finding — Medium

The mtime clamp does not close the freshness attack, and it defeats the new launch sweep.

Where

• Sources/OpenFactorCore/Inbox/SharedInbox.swift pending(now:) lines 174–180
• sweepStale(now:) lines 241–247
• Test that pins only the clamp, not the sweep: Tests/OpenFactorCoreTests/SharedInboxTests.swift futureTimestampsAreClamped

What the fix claimed

Fable’s finding 8: a sibling (or anything that can write the group) sets .modificationDate in the future; pending() sorts it first and collect() treats it as fresh forever. The stated fix was arrived = min(mtime, now). The what-changed note says the clamp “only stops an item claiming the future” and that a back-dated item sweeping sooner is the safe direction.

What it actually does

pending(now:) is called again on every listing. A future mtime is re-clamped to this now every time:

stamped = year 2090
arrived = min(2090, now) = now
age     = now - arrived  = 0

So a future-dated file:

1. Still sorts ahead of a genuine share from ten seconds ago (arrived == now vs arrived == now - 10).
2. Still passes collect’s freshness test (timeIntervalSinceNow == 0 > -600).
3. Never satisfies sweepStale’s now.timeIntervalSince(item.arrived) > 5 * 60.

Call order:

1. Extension writes a real transfer QR at T=0.
2. Sibling (same team, same app group — the attacker this design already names) writes Inbox/<uuid> with modificationDate = now + 86400.
3. Owner opens OpenFactor. sweepStale runs at launch. Poison age is 0. Both files stay.
4. They unlock. collect takes the poison (newest). sweep() deletes the real QR.
5. They never unlock. Launch again an hour later. sweepStale still sees age 0. The poison sits for as long as its mtime stays in the future.

The launch sweep was the fix for the finding all three engines reported. A future timestamp, the one case finding 8 was about, is now the one case that sweep cannot expire.

The new test asserts item.arrived <= now. That is true of an immortal file. There is no test that a future-dated item becomes sweepable.

A clock set forward, a share, then the clock set back produces the same shape without a sibling: the file’s mtime is in the future relative to the corrected clock, and sweepStale will not age it.

Smallest fix

A timestamp after now is untrusted. Treat it as .distantPast (sorts last, immediately stale) or delete the item. Do not re-clamp to now on every read. Add a test: plant mtime = now + 86400, call sweepStale(now: now + staleAfter + 1), expect the file gone.

───

Question 1 — does each change address the finding it claims to?

1. One window scene. Yes, for the reported defect. OpenFactor-Info.plist sets UIApplicationSupportsMultipleScenes to false. Scene-manifest generation is off for iphoneos and iphonesimulator. PrivacyShield.foregroundScene still uses .first, and now says that is only legal because of the plist. Split View beside another app does not need a second OpenFactor scene.

CI reads the source plist and greps the project for Generation[sdk=iphoneos*] = YES. That is not the check that would have caught the original: one engine looked in the project file and was wrong; the shipped artifact was true. Two holes in the net: it never inspects a built Info.plist, and deleting the Generation = NO lines (so Xcode’s SwiftUI default returns) is not = YES, so the grep stays green. I am not sure which side wins a merge if generation comes back while the file still says false. I am sure the CI does not answer the question that mattered last time.

2. Launch sweep. The reported sequence is fixed. .task { SharedInbox().sweepStale() } sits on the root Group next to discardOrphanedFiles(), above the lock, with none of the four collectWhatArrived guards. It only walks Inbox/ UUID names, not the group root. A just-written item survives (freshItemsSurviveTheSweep). A five-minute-old item does not (staleItemsAreSwept).

It does not run again on later scene activations, only at launch. A process that is launched locked, cancelled, and left resident keeps a then-fresh item until the next process start. That is narrower than Fable’s “every launch and every scene activation,” and it is still a bound: the next cold launch after five minutes deletes it. The original “relaunch forever, file stays” is gone — except for finding 8, above.

freshness is still ten minutes; staleAfter is five. collect will still present a six-minute-old item if the process never died. A launch at six minutes deletes it. The what-changed file names that judgment. It is not a hole. It is two clocks for one idea.

3. Backup exclusion. The directory is marked isExcludedFromBackup = true after createDirectory and before the file write. The test reads the flag back. Children of an excluded directory are excluded. That is the right shape, and it matches the vault-key staging argument.

Weaker than the vault key: setResourceValues is try?. If the mark fails, write still stores the QR. VaultKeyStore refuses to write a key it cannot exclude. I did not measure that try? failing on iOS. I record the difference.

4. Bounded take. Size is read from the file system first; oversize throws .tooLarge; defer still deletes. The test plants largestAcceptableBytes + 1 and checks both the throw and the removal. Class of “sibling writes a gigabyte, contents(atPath:) materialises it” is closed when fileSize is present. If resourceValues returns nil, the if let size is skipped and the old full read runs. I do not know of a regular iOS file that has no size. I know the bound is optional in the code.

The bound used here is isWorthLoading (archive ceiling), not the 8 MiB image policy. handleImage then applies the policy. A sibling can still force an ~11 MiB allocation. That is a bound, not the unbound read that was filed.

5. Migration URL crash. Closed. The three batch varints are refused above 10_000 instead of clamped. position is index &+ 1 as a belt. theCrashingPayloadIsRefused is the exact bytes from round one. everyFieldIsBounded covers size, index, and id. At the bound, position == 10001 with no trap.

6. Confirm and manual previews. Closed on the phone. Both call maskedIfCaptured(isScreenCaptured). The list uses the same helper. Passphrase screens still withhold rather than bullet. I did not find that helper on WatchCodeView. SECURITY.md now says every screen that draws a live code masks it. I am not sure watchOS exposes an equivalent capture flag. If it does, the new sentence is false on the wrist. I am not promoting that.

7. onOpenURL vs a pending arrival. Closed. guard arrival == nil else { return } is before parse. A second URL does not replace a held image. A first URL blocks collectWhatArrived (arrival == nil is still required there), so a sitting inbox file is not taken and then thrown away. The second arrival is dropped with no signal. That is the rule they chose. There is no test for it.

8. Future mtime. Incomplete. See the finding.

9. APP_LOCK.md table. Closed. The didBecomeActive row now says coldLock is untouched in both directions, and a paragraph under the table says why the old row was the dangerous one. The code and coldLockStaysColdWithoutAnUnlock still match. The coverVisible formula in the same page still omits phase != .launching; the code still excludes launching. Same leftover as round one, still not a leak.

10. Extension bound after materialisation. The RAM class is closed. loadFileRepresentation puts the payload on disk; fileSize is consulted before Data(contentsOf:). The copy is not after the check. In the callback they copyItem the system file to a UUID in tmp, then (outside the callback) read the size and maybe load. A multi-gigabyte share is still copied in full onto disk before anyone looks at fileSize. The comment on firstImage says “the size is known before the copy.” That is false. run still does a second, in-memory, policy check, which is fine as defense in depth.

11. localOnly test. The boolean now lives in CodeClipboard.rules(for:). Both public copy functions read it. The new test asserts rules(.passphrase).localOnly and !rules(.code).localOnly. Changing the table fails the test. Changing copy(passphrase:) to stop calling rules does not. The tidy-looking “make the two call sites consistent” that the finding was about would now be editing rules, and that is what is pinned. I would rather have seen the pasteboard option itself asserted; I cannot tell from this process whether UIPasteboard exposes localOnly for a readback. The class is mostly closed.

───

Question 2 — did any change introduce something new?

The mtime clamp did. A future timestamp used to be “always newest and always fresh.” It is now “arrived just now, every time you look,” which is the same for ordering and worse for the new sweeper. That is a fix that handles the reported comparison (arrived <= now) and leaves the class open.

First-arrival-wins can hide a share behind a hostile otpauth:// that got there first. The inbox file is no longer destroyed; it waits for the next collect trigger after arrival becomes nil (scene / lock / vault), or for sweepStale on a later launch. That is a lost import, not a lost secret. It is the trade they named.

sweepStale only considers UUID names. sweep() still deletes everything in Inbox/, and still runs only from collect(). A non-UUID file planted in that directory is the original leftover, under another name, until someone unlocks and collects. This app never writes those names. A sibling can.

Five versus ten minutes is not a new race. It is two constants that used to be one idea.

I walked AppLockPresentation only enough to see the table and the code still agree on coldLock. I did not re-derive every sequence.

───

Question 3 — claims the code does not do

┌─────────────────────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Claim                                                                       │ Fact                                                                                                                    │
├─────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ SECURITY.md share-extension paragraph: “passes a URL carrying only an       │ Still false. write’s UUID is discarded. The app polls. Round one named this; the sweep paragraph next to it was         │
│ identifier”                                                                 │ rewritten and this sentence was not.                                                                                    │
├─────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ SharedInbox header: “the whole directory swept at every launch”             │ Launch runs sweepStale, not sweep. Items younger than five minutes stay.                                                │
├─────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Same header / entitlements comment: item “exists for seconds”               │ The enforced bound is five minutes, and only on a launch.                                                               │
├─────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ SharedInbox.write: “The URL that follows it is the only thing that leaves   │ No URL leaves. Leftover from the removed scheme.                                                                        │
│ this process”                                                               │                                                                                                                         │
├─────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ ShareViewController.firstImage: “the size is known before the copy”         │ copyItem runs, then fileSize is read.                                                                                   │
├─────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ SECURITY.md: leftovers swept at launch, older than five minutes             │ This one is now true, except for a future mtime (the finding).                                                          │
└─────────────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

The localOnly lifetime for codes (30) is in rules and in a test, and copy(_:expiring:) still takes the caller’s expiry (TOTP period end). The test pins a number the code path for codes does not use. That is not a security lie; it is a test of a table cell the write ignores.

───

The launch sweep, the backup flag, the bounded take, the batch refusal, the capture helper, the arrival guard, the scene plist, and the lock table are real fixes for the cases as filed. The one I would not accept is the mtime clamp: it is the plausible one-line response to finding 8, it has a test that cannot fail the way the attack works, and it leaves a transfer QR in the group with no expiry.

Gpt:
Round-two result
Scope 4 is not clear at 6254706. I found four Medium and five Low issues. Five of the eleven fixes fully close their findings; five remain incomplete, and the first-arrival change replaces the original overwrite with a different silent loss.
Findings
Medium — The launch sweep still does not bound an inbox item’s lifetime
[OpenFactorApp.swift (line 177)](OpenFactor/OpenFactorApp.swift:177), [OpenFactorApp.swift (line 193)](OpenFactor/OpenFactorApp.swift:193), [SharedInbox.swift (line 241)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:241)
Concrete sequence:
The extension writes a transfer QR.
The app launches ten seconds later with App Lock enabled.
The one .task calls sweepStale; the item is fresh, so it remains.
Face ID is cancelled. collectWhatArrived() returns because the app is locked.
The app backgrounds. Later activations call collection but never sweepStale.
The item can therefore remain indefinitely in the non-confidential App Group container. The five-minute value is not a deletion deadline; it is merely a condition evaluated once when this view’s task starts. This leaves the original finding’s class open and makes [SharedInbox.swift (line 31)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:31) (“whole directory swept at every launch”) materially misleading.
Smallest fix: run sweepStale unconditionally before collection on every scene activation, independent of lock and vault state. If five minutes is meant as an actual deadline while the process remains runnable, schedule the next expiry too; otherwise document that cleanup occurs only at the next execution opportunity.
Medium — Backup exclusion fails open
[SharedInbox.swift (line 94)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:94)
write discards any error from:
try? marked.setResourceValues(values)
and then writes the plaintext transfer QR anyway. Any metadata failure that does not also prevent ordinary file writes produces a backup-eligible image containing every OTP seed. The test exercises only the successful filesystem path.
This contradicts both the nearby “Excluded before anything is put in it” comment and the round-two account’s unconditional claim.
Smallest fix: propagate the exclusion error and refuse to write. Reading the value back before committing the item would make this fail closed even on a filesystem that silently ignores the property.
Medium — take still performs an unbounded check-then-read
[SharedInbox.swift (line 190)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:190)
The new bound is an optional fileSize lookup followed by a separate FileManager.contents call. It fails open when metadata cannot be read and has a race even when it succeeds.
A sibling app authorized for the group can:
Create a small, fresh UUID-named file.
Let OpenFactor obtain its small fileSize.
Atomically replace it with a very large file before contents(atPath:).
Make OpenFactor materialize the replacement without a bound.
If memory pressure terminates the process, the defer is not guaranteed to clean up the poison item.
Smallest fix: open the item once, reject non-regular files, and read at most largestAcceptableBytes + 1 from that same descriptor. The metadata check may remain as an optimization, but cannot be the enforced bound.
Medium — A manually revealed OTP seed remains visible during capture
[ManualSetupView.swift (line 71)](OpenFactor/Scanning/ManualSetupView.swift:71), [SECURITY.md (line 157)](SECURITY.md:157)
The preview code is now correctly masked, but the same view renders the permanent OTP seed in a plain TextField whenever isSecretRevealed is true. That branch does not consult isScreenCaptured.
Concrete sequence: while mirroring a meeting screen, enter a seed manually and tap the eye button to check for a typo. The remote audience receives the seed, which is more durable than the live code the fix masks. This falsifies the broad claim that “Secrets are hidden while the screen is being captured.”
Smallest fix: permit the plain field only when isSecretRevealed && !isScreenCaptured, hide it immediately when capture starts, and disable or explain the reveal button while captured.
Low — Clamping a future mtime to now preserves both original attacks
[SharedInbox.swift (line 165)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:165)
For a file stamped in 2100, every invocation computes arrived = min(stamped, now), so its apparent age is always zero. It is never stale. It also sorts ahead of a legitimate item because its clamped timestamp is the exact now used for that enumeration, while the legitimate file’s timestamp is slightly earlier.
InboxOpener.collect() consequently takes the planted file and its deferred sweep deletes the genuine share. The added test checks only arrived <= now, so it proves the clamp ran without proving either security property.
Smallest fix: reject/delete timestamps beyond a small tolerated clock skew, or map them to .distantPast; do not convert them into “arrived exactly now.” Test both ordering against a genuine item and eventual sweeping.
Low — The new five-minute sweep contradicts the ten-minute freshness contract
[SharedInbox.swift (line 150)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:150), [SharedInbox.swift (line 224)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:224), [APP_LOCK.md (line 242)](docs/APP_LOCK.md:242)
freshness is ten minutes, the normative App Lock document says items older than ten minutes are swept, but staleAfter is five minutes.
A person who shares an image, waits six minutes, and then opens the locked app loses an item that the collection policy still considers fresh. The launch task deletes it before the user can unlock.
Smallest fix: use one constant for presentation and stale sweeping, or require staleAfter >= freshness. The test should cover an item between five and ten minutes old.
Low — The extension copies the complete attachment before checking its size
[ShareViewController.swift (line 116)](OpenFactorShare/ShareViewController.swift:116)
loadFileRepresentation avoids an immediate in-memory Data, but the callback then calls copyItem before the size lookup at line 132. A provider can therefore cause an arbitrarily large copy into the extension’s temporary directory before any bound runs. The fix changes memory exhaustion into unbounded disk I/O and disk pressure rather than closing the class.
Smallest fix: perform a bounded streaming copy from the provider URL, stopping after largestAcceptableBytes + 1. A preliminary source-size check is useful but should not replace the bounded copy.
Low — First-arrival-wins silently destroys the second valid arrival
[OpenFactorApp.swift (line 211)](OpenFactor/OpenFactorApp.swift:211)
The original overwrite is fixed: a hostile URL can no longer destroy the first pending image. But if a second legitimate otpauth:// or migration URL arrives, the guard returns before retaining it or notifying the user. The OS has already delivered the link, so it is simply lost.
Smallest fix: retain one bounded queued arrival, or provide explicit feedback that the new link could not be accepted. Do not restore overwrite behavior.
Low — Two security-mechanism claims remain false
[GoogleAuthenticatorImport.swift (line 84)](Sources/OpenFactorCore/Import/GoogleAuthenticatorImport.swift:84) calls index &+ 1 a “saturating add.” &+ wraps; it does not saturate. The current maximumBatchField guard prevents an actual overflow, so the crash fix works, but the claimed second safety belt does not exist. Use ordinary + under the proven invariant or implement a real overflow policy.
[SECURITY.md (line 519)](SECURITY.md:519) says the extension “passes a URL carrying only an identifier.” It does not: the returned UUID is discarded, the extension cannot open the app, and the app later polls the group container. The document should describe that actual mechanism.
Disposition of the eleven fixes
#	Result	Why
1	Closed	The shipped plist explicitly disables multiple scenes, and CI rejects re-enabling the generated manifest.
2	Incomplete	The sweep runs once, not on later activations or when a retained item crosses the age threshold.
3	Incomplete	Backup-exclusion failure is swallowed and writing proceeds.
4	Incomplete	A mutable or metadata-less item can still reach an unbounded read.
5	Closed behaviorally	Batch fields are rejected above 10,000 before conversion; the &+ comment is nevertheless false.
6	Closed for live codes	All three live-code cards now use the masking helper; the raw manual seed remains exposed.
7	Original issue closed; new loss	The first item survives, but the second is silently discarded.
8	Incomplete	A future timestamp remains perpetually fresh and wins ordering.
9	Closed	The normative transition table now matches the tested coldLock behavior.
10	Incomplete	Memory materialization was avoided, but an unbounded temporary-file copy still precedes the check.
11	Closed in current code	Passphrases resolve to localOnly = true, which is forwarded into the pasteboard options; codes deliberately resolve to false.
The URL scheme allowlist and pre-parser 8 KiB bound remain sound, and I found no new App Lock state-transition failure beyond the accepted second snapshot cache.
I reviewed the exact 6254706432b618e12101e7752c573e413327f010 Git object. Its code is the same as 8471c33; it adds only the round-two audit accounts, and 6d14a1f differs from it only in HANDOFF.md. No repository files were modified, created, or deleted.

Fable:
Scope 4, round two: the fixes at the app's boundaries

Code under review: 6254706. Verified: the checkout is at 6d14a1f, whose only difference from 6254706 is HANDOFF.md, and the fix commits for this scope are 88ea969 (one scene), 0924c1b (masking), a848a88 (bounds family), b41f84d (the remaining seven), and 8471c33 (the class sweep). I read each fix as a diff against round one's 74fe841 and then read the current files whole.

One method note before anything else, because the round-two prompt exists to catch exactly this hazard: the prompt specifies a fresh conversation, and this is not one — it is the same session that wrote the Fable 5 round-one pass. I am reviewing fixes to findings I filed, with my own reasoning in context. I have weighted the pass accordingly, toward trying to refute the fixes rather than recognize them, but the reader should know the condition under which this was written, and the published method says the opposite.

The verdict in one line: ten of the eleven fixes are real and verified; one — the mtime clamp — does not fix the finding it answers, and I say so below as finding R1.

Question 1: does each change address its finding?

1. Multi-scene — fixed, and enforced. OpenFactor-Info.plist now declares UIApplicationSupportsMultipleScenes = false, the project file sets INFOPLIST_KEY_UIApplicationSceneManifest_Generation = NO for both configurations so the file cannot be silently overridden, and CI checks both: plutil extracts the key from the source plist and fails on anything but false, and a grep fails if generation flips back to YES. The assumption is written at the point it would break (PrivacyShield.swift:119), and docs/APP_LOCK.md R1/R2 now state the single-scene dependency. With one scene, connectedScenes.first is that scene and the round-one analysis of the window machinery stands. This closes the class (no second scene can exist), not just the instance, and choosing removal over per-scene plumbing is the lower-surface option. Sound.

2. The launch sweep — fixed for the reported case. SharedInbox.sweepStale() (SharedInbox.swift:230) deletes items older than five minutes and is called from an unconditional .task on the root Group (OpenFactorApp.swift:177), which I verified runs on a cold-locked launch too, since the modifiers sit on the Group containing both the lock-root and gate branches. The age bound is what makes an unconditional sweep safe, and tests pin both directions (stale swept, fresh survives). The share-to-a-locked-phone sequence from round one now ends with deletion at the next launch. Two residuals, neither reopening the finding: the sweep runs only at launch, so a process that stays alive for days with the vault never opening holds an item until relaunch — much narrower than before, but the account's "removes what nobody is coming for" is per-launch, not per-day; and the five-versus-ten incoherence below (N1) is new.

3. Backup exclusion — fixed. isExcludedFromBackup is set on the inbox directory before the write (SharedInbox.swift:106), mark-before-write in the order that leaves no window, and a test asserts the resource value after a write. One deliberate softness worth recording: the mark is try?-silenced, so a failed mark lets the write proceed unexcluded with nothing reporting it. Refusing the write on a failed mark would be the conservative rule for a file that is a QR of every secret; against that, the item now lives at most five minutes plus one launch. I record the judgment rather than contest it.

4. Unbounded take() — fixed. The size is read from the file system before the load (SharedInbox.swift:194), and an oversized item is removed rather than left for the next attempt, which the test pins. The bound used is the archive ceiling (ImportLimits.largestAcceptableBytes, roughly 12–13MB) rather than the 8MiB image policy — deliberate, since the core type does not know the format — and the decoder is still protected because handleImage now applies the 8MiB policy bound before CIImage (AddAccountViewModel.swift:107), which also closes round one's "no app-side bound" gap and makes the extension's "bounded here as well as in the app" comment true at last. Layered correctly.

5. The migration-URL crash — the primary fix is right; the belt is mislabeled. The batch fields are now refused at the varint when above maximumBatchField = 10_000 (GoogleAuthenticatorImport.swift:153-160), with the correct reasoning written above it: refusal, not clamping, for a value somebody else chose. Two defects remain around it. First, the comment on position says "written as a saturating add anyway" — &+ is the wrapping operator, not a saturating one: Int.max &+ 1 is Int.min, so if the invariant ever moved, position would silently go hugely negative rather than stop at a ceiling. The belt is described as doing something it does not do, which is in scope by this review's own rule about comments. Second, I found no test that feeds a batch field above maximumBatchField — GoogleAuthenticatorImportTests tests lying lengths, endless varints, and unspecified enumerations, but not the oversized batch_index that produced the only reproduced crash in this project. The crash's reproducer is not pinned. (Scope 3's round two may already carry this; the crash was reachable through this scope's URL scheme, so I record it here regardless.)

6. Masking while captured — fixed at every code site, with the class not quite closed. All four card sites route through one maskedIfCaptured helper (AccountCard.swift:54), verified at the list card, the context-menu preview, ConfirmAccountView, and the manual-entry preview, and the helper's existence gives the next screen "one obvious thing to copy," which is the right shape of fix. But on the very screen the fix touched, the class has a surviving member: R2 below.

7. onOpenURL destroying a pending arrival — fixed. guard arrival == nil else { return } (OpenFactorApp.swift:218) makes both entry points first-wins; the destructively-collected image can no longer be overwritten. The cost the fix account itself names — a silently dropped second arrival — is real and is a documentation defect now (D1 below), not a code one: the person who taps "Open in OpenFactor" in Files while an image waits gets foregrounded into the app and nothing happens, with no sign why.

8. The mtime clamp — this fix is incomplete, and I am filing it as such. See R1.

9. The APP_LOCK.md table — fixed. The didBecomeActive row now says coldLock is untouched in both directions, matching AppLockPresentation.swift:137 and the coldLockStaysColdWithoutAnUnlock test, and a correction note records that the page's own supremacy rule would have made the error destructive. Verified against the code and the test.

10. The extension's bound — fixed. firstImage asks for a file representation, copies it inside the callback (correctly, since the system deletes its file when the callback returns), reads the size off disk before any load, and the in-memory policy check in run is now the second of two (ShareViewController.swift:107-135). One residual shape, noted rather than promoted: if resourceValues fails on an existing file, size is nil and the guard is skipped, so Data(contentsOf:) runs unbounded — the exact shape this sweep hunted, surviving in the fallback path. Practically negligible (the copy just succeeded on the same volume), and the same nil-skips-check shape exists in take(). A guard let size else { continue } would close it for one line each.

11. localOnly pinned — fixed for the boolean that matters. rules(for:) extracts the decision into a value (CodeClipboard.swift:52), both call sites read it, and the test asserts passphrase.localOnly == true and code.localOnly == false. The tidy-change hazard the finding described is now something a test fails on. One wrinkle it introduced: D3 below — half the table is dead.

Question 2: did any change introduce something new?

R1 — Low, and the round's one incomplete fix: the mtime clamp is behaviorally inert against the attack it answers, and it makes the planted item immortal against the new sweep.

The finding was that a future-dated file "sorts ahead of everything and looks newer than anything that could actually have arrived." The fix clamps arrived to min(stamped, now) (SharedInbox.swift:180). Walk the attack through the clamped code: a sibling-written file stamped one year ahead reports arrived == now on every pending() call. Every genuine share has arrived < now by the time anything reads it. Sorted descending, the planted item still sorts first, collect() still takes it, and the deferred sweep still deletes the genuine share behind it — the identical outcome to round one, byte for byte. The clamp changed what Pending.arrived reports, not what happens.

And it adds one thing: sweepStale computes age as now - min(stamped, now) = 0 on every pass, so the planted item is never stale — the one file in the container that the new launch sweep can never remove, for as long as its stamp stays in the future. The test pins item.arrived <= now, which is the cosmetic property, not the adversarial one.

The fix that closes it is the one round one named: a future stamp (beyond small skew) is impossible for a legitimate write, so treat it as .distantPast — it then sorts last and sweeps immediately. The missing test: plant a future-dated item beside a fresh genuine one; assert collect takes the genuine one; assert sweepStale removes the plant. Severity stays Low for round one's reason — the writer is a same-team sibling, an accepted-attacker position — but the answer to "does the change address the finding" is no, and the fix account's own "worth confirming rather than assuming" is answered: confirmed not to hold.

R2 — Low, new: the revealed manual-entry secret stays legible while the screen is captured, on the screen the masking fix touched.

ManualSetupView.swift:77: when isSecretRevealed is on, the secret is a plain TextField, and nothing consults isScreenCaptured — the same view reads that environment value four lines up and applies it only to the code preview at line 195. A base32 secret is strictly more valuable than any code derived from it, and the app's own hierarchy says permanent credentials get the stronger treatment: passphrases are withheld while captured. The fix commit's claim, "every live code masked," is literally true; the class — permanent secret legible while captured — kept a member. And SECURITY.md's updated paragraph now opens with "Secrets are hidden while the screen is being captured" (line 157), which this contradicts by its own headline. Smallest fix: force the SecureField branch (or flip isSecretRevealed off) while isScreenCaptured.

N1 — Low, new: the sweep threshold undercuts the freshness window, and the normative document contradicts both.

staleAfter is five minutes (SharedInbox.swift:225); freshness is still ten (SharedInbox.swift:159), documented as "how long an item is still worth presenting." An item aged between five and ten minutes is therefore worth presenting by one rule and deleted unread by the other, and which one wins depends on process history: if the app was merely backgrounded, collect presents it; if the phone relaunched the app, sweepStale and the gate-opening collect race on the main actor at launch, and the sweep usually gets there first. Share a QR, get interrupted for six minutes, open the app — whether your share survived depends on whether iOS kept the process alive. Nothing ties the two constants, and no test would fail if they drifted further. Either raise staleAfter to freshness, or lower freshness to staleAfter, and pin the relation (staleAfter >= freshness, or one constant) with a test. Meanwhile docs/APP_LOCK.md still says "inbox items older than ten minutes are swept unread" — see D1.

Beyond these: the wrapped-key reconcile added to OpenFactorApp (scope 1's fix landing in a scope-4 file) touches neither the lock, the cover, nor the arrival ordering — the onChange wiring and PrivacyShield.apply call sites are unchanged from the state round one verified. The CodeClipboard refactor preserves both call sites' behavior exactly. The extension's new temp copy is deleted in a defer, lives in a directory the system purges and backups exclude, and a kill between copy and defer leaves nothing worse than the system's own already-materialized provider file.

Question 3: what do the documents now claim that the code does not do?

D1 — docs/APP_LOCK.md's arrivals section is now wrong twice, and it is the document that declares itself normative. It still says "inbox items older than ten minutes are swept unread" — the launch sweep now deletes at five, so the normative bound and the code disagree by a factor of two. And its headline rule, "An arrival takes precedence. Whatever was open closes," now has an undocumented exception the fix account itself flagged as the thing that "hides a lost link": a second arrival is silently dropped while one is pending. This page just finished demonstrating, via the coldLock row, what its supremacy clause does to a reader when a row is wrong; it now has two fresh rows in the same condition. Both are one-sentence fixes.

D2 — SECURITY.md still says the extension "passes a URL carrying only an identifier" (line 522), and it does not. write()'s returned UUID is discarded at the call site (ShareViewController.swift:74, @discardableResult); no URL is passed anywhere; the app polls the container. Grok found this in round one, the triage acknowledged it as "false and leftover," and it did not make the list of eleven — the one confirmed round-one item that fell through the crack between triage and fix. The behavior is safer than the claim, which is exactly why a stale sentence survives: nothing breaks while it lies.

D3 — CodeClipboard.rules(for: .code).lifetime is a claim with no consumer, pinned by a test. copy(_:expiring:) takes the expiry from its caller — the TOTP rollover moment, or now + 30 for HOTP via a separate constant in AccountListViewModel.swift:354 — and reads only localOnly from the table. The table's lifetime: 30 for codes governs nothing, yet lifetimesAreStated asserts it, so the suite pins a dead value and a reader of rules is told a rule the code does not route through. Either route the HOTP fallback through rules(for: .code).lifetime, making the table true, or remove the code lifetime from the table and the test. The passphrase half is wired and true.

D4 — the "saturating add" comment, recorded under finding 5 above: &+ wraps.

For completeness on round one's remaining doc findings: SECURITY.md's sweep paragraph is rewritten and now true, including its honest "until gate A4 that sentence was not true"; the "both cap at 8MB" sentence is now true in substance — 8MiB is what gets accepted and decoded, though a file may be read up to the larger archive ceiling before format-specific refusal decides; and the captured-codes paragraph correctly narrows its history, subject to R2's caveat about its opening words.

Summary. The two findings that mattered most — the multi-scene confidentiality leak and the unswept inbox — are genuinely closed, with CI holding the first and tests holding the second, and the fixes chose the smaller-surface option both times. The bounds family is closed as a class, which is better than the four instances were filed as. Against that: one fix (the mtime clamp) answers its finding without changing the attack's outcome and should be redone as .distantPast; one new inconsistency (five-versus-ten) makes a share's survival depend on process lifetime; one class member survived the masking sweep on the screen that was being fixed; the normative lock document is wrong again in two places; and one confirmed round-one documentation falsehood was never assigned a number and so was never fixed. None of these is a secret leaking. All of them are the kind of thing round two exists to say out loud.
