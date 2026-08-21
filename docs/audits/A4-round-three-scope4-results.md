# A4 round three, scope 4: what three engines found in the fixes

Round three of scope 4 read `83e5cdd`. All three engines returned.

**Eleven of the twelve items are closed, the twelfth turns out never to have been a defect, and
nothing new is high severity.** That is six review rounds in a row without a new high.

| Engine | Verdict |
| --- | --- |
| ChatGPT 5.6 Sol | One medium, five low. "I would run another round if these findings are changed" |
| Grok 4.6 | No new findings promoted. "I would not run a fourth round on this scope for the inbox lifecycle" |
| Fable 5 | Eleven closed, one plausible wedge at the SwiftUI seam, and a retraction of its own round-two finding |

## A reviewer retracted its own finding

**S4-22 was false, and Fable filed it.** At round two it reported that no test exercised the batch
field bound. `MigrationBatchBoundsTests` had covered all three fields in both directions since
`43103dc`, which is an ancestor of the commit round two reviewed. Its greps were piped through
`head` and truncated before the tests existed in the file.

Two consequences, both mine to carry. The two tests added this round **duplicate the existing ones
almost line for line**, harmlessly. And the commit message's claim that removing the guard makes
them trap rather than fail is true of the pre-existing `UInt64.max` reproducer and not of the
over-by-one tests this commit added, which would fail politely.

Recorded here rather than quietly dropped, because the same fault produced it that produces the
defects: a claim made from an incomplete read.

## The one disagreement, and it is a real one

**Whether the future-timestamp rule should tolerate a small skew.**

ChatGPT says the strict rule rejects a legitimate write, and gives the sequence: `sweepStale`
captures `now`, the extension completes its atomic rename a millisecond later, the listing sees the
new file, its honest timestamp is *after* the captured `now`, so it becomes `.distantPast` and the
same sweep deletes a share that was never stale. It wants a tolerated skew.

Grok says the opposite in as many words: a skew allowance would reopen a slice of the same attack,
because a plant stamped two seconds ahead would sort first and stay fresh for nearly the whole
window. Zero tolerance is correct and it would not add one.

Fable sides with Grok on the policy and notes the only real casualty is a share made just before a
backwards clock correction, which costs one re-share.

**The disagreement is smaller than it looks, and the sequence is real either way.** The defect
ChatGPT describes is not the policy but the ordering: `now` is captured *before* the directory and
its attributes are read, so a file that arrives during the read is compared against a moment that
has already passed. Reading the timestamp against an observation taken *after* the attributes
satisfies both positions without a tolerance window.

## What round three added

| # | Finding | Severity | Engines |
| --- | --- | --- | --- |
| S4-23 | `take` can block the main actor on a named pipe, and the deferred removal never runs | medium | ChatGPT |
| S4-24 | `now` is captured before attributes are read, so a share arriving mid-sweep is deleted | low | ChatGPT |
| S4-25 | the unknown-name sweep can delete an in-progress atomic write | low | ChatGPT, Fable, Grok unsure |
| S4-26 | collection's deferred sweep deletes items that arrived after its own snapshot | low | ChatGPT |
| S4-27 | the inbox never fills the queue's second slot, and nothing re-collects after promotion | low | ChatGPT, Grok |
| S4-28 | the queue's promotion rides a SwiftUI binding side effect and can wedge permanently | low to medium, plausible | Fable |
| S4-29 | the extension's preflight accepts a non-regular file representation | low | ChatGPT |
| S4-30 | `pending` accepts a lowercase UUID name that `take` cannot open | low | Fable |
| S4-31 | the documentation trails the code again, in four places | low | all three |
| S4-32 | S4-22 was false; its fix duplicates tests that already existed | informational | Fable |

**S4-23 is the only medium and it is a good one.** `take` was rewritten this round to open one
handle and read through it, which closed the skip and the race. It assumes the name identifies a
regular file. A sibling with access to the app group can create a UUID-named FIFO: `pending`
accepts it, scene activation calls collection synchronously on the main actor, and
`FileHandle(forReadingFrom:)` blocks until a writer appears. The app hangs, and the `defer` that
would remove the file never runs. The fix is to open non-blocking, `fstat` the same descriptor, and
require a regular file.

**S4-28 is the one Fable would carry to a device rather than another round.** Promotion happens as
a side effect of the sheet binding being set to `nil`, so the held arrival must present while the
previous sheet is still animating out. This repository already documents that exact situation in
`AccountListView`: presenting one sheet while another animates out is a request SwiftUI drops. If
it is dropped, `current` stays non-nil with nothing on screen, collection is blocked forever, and
the queue wedges for the life of the process. Fable says plainly it cannot confirm this without a
device, and proposes promoting from `onDisappear`, which is the signal every other sheet here
already uses.

**S4-25 and S4-26 are the cost of the sweep getting more aggressive.** Deleting unknown names on
sight was the fix for S4-20, and Foundation's atomic write stages a temporary file next to its
destination; if the sweep fires while the extension is mid-write, the share fails. Grok explicitly
declines to promote this, saying it did not verify whether Darwin stages in that directory or in
the system temporary directory, and names it as the one new behaviour it would want another pair of
eyes on. **That is the open question to settle by measurement rather than by argument.**

**S4-31 is the third consecutive round where the inbox prose trails the inbox code by one fix.**
`SECURITY.md` still says five minutes when the constant is now ten and the sweep runs on every
foreground transition. `SharedInbox`'s header is a broken splice left by my own edit, with the tail
of a deleted sentence hanging mid-paragraph. "An item lives for seconds" survives in `write` and in
`SECURITY.md` after being corrected in two other places. And `sweep()` is still documented as
"removes everything, for launch", which launch does not call.

Fable's suggestion for ending that cycle is the useful one: **a CI check tying the number in
`SECURITY.md` to the constant in the code**, since the pattern says these edits are being made from
the fix account rather than by re-reading the files touched.

## Convergence, and whether to run a fourth round

All three say the surface is shrinking. They disagree on what to do next, and the disagreement is
worth keeping rather than averaging away.

**ChatGPT: run another round.** The inbox and arrival area itself has not converged, because its
third rewrite still treats a concurrently changing directory as a static collection: timestamps
compared against an earlier observation, unknown files deleted without distinguishing active
staging from leftovers, and collection sweeping names that arrived after selection.

**Grok: do not.** The three areas rewritten three times each landed on the construction the reviews
specified rather than on a new guess. It would fix the `SECURITY.md` paragraph, "because a document
that still says five minutes after the code stopped doing that is the rot this gate keeps paying
for", and stop.

**Fable: the pure cores are done, and the remaining risk has migrated to the one boundary no test
in this repository can reach.** The next real defect in this scope, if there is one, will be found
on a device rather than in the suite, and the instrument that closes it is the manual checklist.

The three are not really in conflict about the code. They are in conflict about whether the
cross-process races ChatGPT lists are worth a fourth source round, or whether they are the kind of
thing only a device settles.

---

# Measured on hardware, 2026-08-19

Two of round three's findings were about behaviour no test in this repository can reach, and both
were checked by hand on an iPhone 15 Pro running the build from `83e5cdd`, which is the commit that
introduced `ArrivalQueue`.

## S4-28 does not reproduce

**Four runs, four times the held arrival presented.** The procedure is now item 11 of the manual
checklist in `docs/APP_LOCK.md` so it can be re-run: share a QR image, wait for the import sheet to
appear, open an `otpauth://` link from another app while it is up, return, dismiss the import, and
watch for the add-account screen.

Fable's reasoning for filing it was sound and is worth keeping even though the conclusion did not
hold: promotion happens as a side effect of the sheet binding being set to `nil`, so the held
arrival must present while the previous sheet is animating out, and `AccountListView`'s own comment
records SwiftUI dropping that kind of request. **It does not drop this one.** That comment was
written about a different pairing of sheets, which is the difference.

The second shape it named, SwiftUI writing `nil` twice for one dismissal and silently discarding
the held arrival, would have shown as nothing appearing. It did not appear in four runs either.

**What this measurement does not cover:** one device, one iOS version, four trials, and a timing
dependent behaviour. The checklist item is the guard against that rather than this paragraph.

## S4-27 reproduces, and it is the one that bit

The sequence tried first was a different one: share an image, then open a link **before** OpenFactor
comes forward. The URL takes the arrival slot, `collectWhatArrived` refuses to run while anything is
current, and the shared image is never collected at all. It is not destroyed; it sits in the inbox
for `staleAfter` and presents only if some unrelated event triggers a collection later.

**On one run in four the image did appear after the link was cancelled**, which is exactly what the
finding predicts: cancelling clears the arrival, and any subsequent scene, lock or gate change
runs a collection that picks the image up. **The intermittency is the defect**, not an
observational error. Whether your share survives depends on whether an unrelated event happens to
fire.

That turns S4-27 from a reading of the code into a reproduced observation, and it raises a product
question the code has never actually answered: whether the newer arrival should win outright, or
whether the queue should hold both. The behaviour today is neither.

---

# The arrival rule was decided rather than fixed

**S4-7, S4-15, S4-27 and S4-28 were all about the same question, and the code had never answered
it.** Round one filed a second link destroying a waiting arrival. Round two filed the fix for that
silently dropping the second instead. Round three filed the queue built in answer as unable to fill
its own second slot from the inbox, and as possibly wedging at the SwiftUI seam.

Four findings, one unanswered question: **when two things arrive, which one does the person get?**

## What was decided, 2026-08-19

**The newest arrival wins, and the superseded one is swept.** The queue is removed.

The reasoning, in the order it actually weighed:

**The normative page already said so.** `docs/APP_LOCK.md` has always stated that an arrival takes
precedence and whatever was open closes. The queue was the thing that contradicted it, and building
the queue required amending that page to carry an exception to its own rule.

**The queue was more surface in the place this gate keeps finding defects.** S4-28 exists only
because the queue exists, and so does S4-27. Two findings in the app target no test can reach,
created by a mechanism whose purpose was to avoid losing something recoverable.

**Neither loss is a loss.** A superseded link can be tapped again; a superseded share can be shared
again. Nothing is added without a tap under either rule.

**First-wins is the worse rule against a hostile sender**, which is the opposite of the assumption
behind it. Under first-wins, whatever arrives first occupies the slot and blocks a genuine share
until it is dismissed. That is precisely the sequence reproduced on hardware.

## What this reverses, deliberately

**S4-7 and S4-15 are closed by decision rather than by code.** A second arrival destroying a pending
one was filed as a defect twice, by reviewers reasoning from the code with no rule to check it
against. There is a rule now, it is written in the normative page and in the source, and the
behaviour follows it.

**A reviewer may well file it again**, and that is expected rather than a problem. The answer is
this section: it is a decision with reasons, taken by the person whose app it is, after using it on
a phone.

**S4-28's measurement stands and is now moot.** Four runs out of four showed the queue promoting
correctly. That measurement is what proved the queue worked, and the queue was removed anyway,
because working was never the question.

**S4-27 is closed by the sweep.** The intermittent reappearance was the superseded share sitting in
the inbox waiting for an unrelated event. It is taken off the device at the moment it is
superseded.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

GPT:
Round-three result
Scope 4 is converging, but it is not ready to stop. The confidentiality fixes are materially better, yet the third inbox/arrival rewrite still contains one Medium and five Low defects. In particular, the mtime replacement rejects legitimate concurrent writes, and the new aggressive sweep can race the extension’s own write.
Findings
Medium — take can block the main actor indefinitely on a special file
[SharedInbox.swift (line 218)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:218), [OpenFactorApp.swift (line 208)](OpenFactor/OpenFactorApp.swift:208)
The new implementation correctly removes the regular-file check/read race, but it assumes the UUID name identifies a regular file. The App Group is explicitly writable by an untrusted sibling.
Concrete sequence:
A sibling creates a fresh UUID-named FIFO in Inbox.
pending() accepts it because its name and mtime are ordinary.
Scene activation synchronously calls collectWhatArrived() on the main actor.
FileHandle(forReadingFrom:) blocks opening the FIFO until a writer appears, or read(upToCount:) blocks waiting for bytes.
The main actor is stuck, and the deferred removal is never reached while the call remains blocked.
The single descriptor and limit + 1 read correctly bound ordinary files, but not the control flow of special files.
Smallest fix: open with O_NONBLOCK | O_NOFOLLOW, fstat that same descriptor, require a regular file, then perform the bounded read. Remove and refuse FIFOs, sockets, directories, and symlinks.
For the cases explicitly named in the round-three brief: an empty regular file is safely bounded and removed whether Foundation returns empty Data or EOF; disappearance before open becomes notFound, while disappearance after open does not invalidate the already-open inode.
Low — The strict future-mtime rule rejects a legitimate concurrent extension write
[SharedInbox.swift (line 186)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:186), [SharedInbox.swift (line 281)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:281)
The replacement fixes the immortal-plant behavior, but “Nothing legitimate writes a stamp in the future” is false because now is captured before the directory and attributes are read.
Concrete race:
sweepStale(now:) captures now = t0.
The extension completes its atomic rename at t0 + 1 ms.
The sweep’s directory listing sees that new file.
pending(now: t0) reads its legitimate mtime, t0 + 1 ms.
Because stamped > now, it becomes .distantPast.
The same sweep calculates an enormous age and deletes it immediately.
InboxOpener.collect() has the equivalent failure: a file completed after pending() captures its default now is treated as stale, fails freshness, and is then deleted by the deferred sweep. Clock correction after a legitimate share is another non-malicious way to produce the same ordering.
Smallest fix: tolerate a small positive skew. Compare the stamp with a time observed after reading its attributes; clamp a near-future stamp to that observation time, and reserve .distantPast for a stamp beyond a defined tolerance. Test both the concurrent-write-sized skew and the far-future plant.
Low — Both sweep paths can delete a transfer written concurrently
[SharedInbox.swift (line 281)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:281), [InboxOpener.swift (line 43)](OpenFactor/Import/InboxOpener.swift:43)
There are two concrete races.
First, Data.write(..., .atomic) writes an auxiliary file and renames it to the UUID destination. The new sweepStale deletes every non-UUID name on sight. If activation overlaps the extension’s atomic write, the sweep can remove that auxiliary file before its rename, causing the share to fail.
Second:
InboxOpener.collect() snapshots pending items and chooses A.
The extension finishes a later item B.
The app takes A.
The unconditional deferred inbox.sweep() enumerates again and deletes B, even though B did not exist in the selection snapshot.
Disabling multiple OpenFactor scenes does not prevent either race: an iPad can run OpenFactor beside the extension’s host app, and process transitions can overlap as the share finishes.
Smallest fix: have collection delete only identifiers present in its original snapshot. Unknown names should be age-bounded rather than removed immediately, so a fresh atomic staging file survives while an abandoned one is eventually removed. A producer-specific staging convention or cross-process file coordination would be stronger.
Low — ArrivalQueue is not wired to all arrivals, and its refusal is still silent
[ArrivalQueue.swift (line 28)](Sources/OpenFactorCore/Inbox/ArrivalQueue.swift:28), [OpenFactorApp.swift (line 227)](OpenFactor/OpenFactorApp.swift:227), [OpenFactorApp.swift (line 271)](OpenFactor/OpenFactorApp.swift:271)
The value type correctly retains two values when callers feed it. The app wiring does not implement that rule uniformly:
URL arrivals call arrivals.arrived, so a second URL occupies next.
Inbox collection is guarded by arrivals.current == nil, so a shared image is never collected into an empty next slot.
Finishing the current arrival promotes the queued value but does not trigger another inbox collection. An image left on disk can therefore appear to do nothing until another activation and can later age into deletion.
When the queue is full, arrived returns false, but onOpenURL ignores that result. The third arrival remains silently lost despite the test comment saying the refusal “says so.”
A hostile app can fill current and next with two URLs, after which a genuine Camera-delivered setup link is silently discarded. A bound of two is defensible against flooding; an invisible refusal is not.
Smallest fix: expose queue capacity, collect an inbox image whenever either slot is available, and retry collection when finished() opens capacity. Consume the Boolean refusal by presenting explicit feedback. The pure queue tests should be supplemented by an app-level test of the binding/promotion wiring.
I could not prove from static SwiftUI code that promoting next inside the binding’s nil setter is itself lost during sheet dismissal. That interaction still lacks an integration test, but I am not promoting it as a finding without a reproduced sequence.
Low — The extension’s preflight still accepts a recursively copied directory
[ShareViewController.swift (line 101)](OpenFactorShare/ShareViewController.swift:101)
For an ordinary immutable file representation, checking the system temporary file before copying closes the reported disk-copy issue. The code does not require the representation to be a regular file, however.
A malicious NSItemProvider can advertise conformance to an image type while returning a directory representation. The directory entry’s fileSize can be small enough to pass, after which copyItem recursively duplicates its arbitrarily large contents. Data(contentsOf:) fails only after that copy.
Smallest fix: request and verify .isRegularFileKey together with the size. A bounded streamed copy remains preferable because it enforces the limit on bytes actually copied rather than on metadata supplied before the operation.
Low — The updated lifecycle documentation still makes false timing claims
[SharedInbox.swift (line 46)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:46), [SharedInbox.swift (line 107)](Sources/OpenFactorCore/Inbox/SharedInbox.swift:107), [SECURITY.md (line 540)](SECURITY.md:540)
Several round-two claims remain or became stale:
SharedInbox says an item lasts “at most staleAfter before a sweep removes it.” Sweeping is activation-driven, not scheduled, so an item can remain longer when the app gets no execution opportunity. The accurate claim is “removed on the first sweep after staleAfter.”
The backup-exclusion comment still says an item “lives for seconds,” while the corrected lifecycle explicitly permits ten minutes plus time until the next activation.
SECURITY.md still says the launch sweep removes items older than five minutes. staleAfter is now ten minutes and the sweep also runs on every activation.
The queue test says the third refusal is reported, while the application discards the returned Boolean.
These are not cosmetic: the first two overstate the lifetime bound of plaintext containing every OTP seed, and the last obscures an intentional availability limit.
Disposition of the twelve round-two items
Item	Round-three disposition
S4-8 future mtime	Previous immortal plant fixed, but strict comparison introduces the legitimate concurrent-write race above.
S4-12 captured manual secret	Closed. The clear field requires !isScreenCaptured, and the reveal control is disabled with an accessible explanation.
S4-13 resident-process sweep	Closed for repeated activations. It remains an execution-opportunity bound, not a wall-clock deadline.
S4-14 five/ten-minute split	Closed. staleAfter is the same constant as freshness.
S4-15 silent second arrival	Core queue behavior is sound, but the integration omits inbox arrivals and silently refuses the third.
S4-16 false claims	Incomplete; the timing and refusal claims above remain false.
S4-17 backup fail-open	Closed. Exclusion is set and read back before bytes are written; either failure prevents the write.
S4-18 bounded take	Closed for regular files and replacement races; incomplete for blocking special files.
S4-19 extension disk copy	Closed for regular system file representations; non-regular representations bypass the intended bound.
S4-20 unknown names	The planted-name persistence is closed, but deleting unknown names on sight creates an atomic-write race.
S4-21 CI regression check	Closed for the reviewed iPhone build configurations: both source plist and both SDK-qualified generation settings are checked.
S4-22 migration bound tests	Closed. All three fields are tested at and above the 10,000 ceiling, before Int conversion and position.


The unchanged App Lock state machine still preserves show-before-hide ordering, the one-scene build assumption remains enforced, URL payload length is checked before either parser, and passphrase clipboard writes still structurally reach .localOnly = true.
Convergence
This is reducing the defect surface, not merely churning: backup persistence, manual-seed capture, the regular-file read bound, the five/ten-minute contradiction, CI silence, and the migration-crash regression gap are all materially closed.
The inbox and arrival area itself has not converged. Its third rewrite fixes the previous single-instance failures but still treats a concurrently changing directory as a static collection: timestamps are compared against an earlier observation, unknown files are deleted without distinguishing active staging from leftovers, and collection sweeps names that arrived after selection. ArrivalQueue similarly makes the local value rule testable while leaving two source-specific behaviors in scene glue.
I would run another round if these findings are changed. The remaining work is narrower, but stopping now would ship a third version of the same boundary with new cross-process loss sequences still present.
I reviewed the exact 83e5cdd10dddc6526de064ff16436bf8233b3c16 Git object. 0d05a05 differs from it only in audit documents. No file was modified, created, or deleted.

Grok:
Scope 4, round three

Code under review: 83e5cdd
Checkout read: 0d05a05 (differs only in audit documents)
Round two read: 6254706
Round one read: 74fe841

I wrote the round-two pass that rejected the mtime clamp. I am not treating that as authority. The question this round is whether the replacement is right, not whether it matches what I asked for.

───

Question 1 — does each change address the finding it claims to?

S4-8, the rejected clamp. Closed, and the new rule is the right one.

pending(now:) now does stamped > now ? .distantPast : stamped. A future stamp sorts last. now.timeIntervalSince(.distantPast) is larger than staleAfter, so sweepStale removes it on sight. The test that replaced the old one plants a file at now + 86400 next to a genuine write and asserts the two properties the clamp version passed while failing: pending().first is the genuine id, and after sweepStale only the genuine id remains.

Nothing legitimate writes a stamp in the future. The extension and SharedInbox.write both get their mtime from the file system at the moment of the write. A sibling, or a clock set forward, a share, and a clock set back, are evidence about the writer, not about when the file arrived. Refusing those does not lose a real share.

A “small clock skew” allowance would reopen a slice of the same attack: now + 2s would sort first and stay fresh for almost the whole window. Zero tolerance is correct. I would not add one.

S4-13. Closed for the case that was filed. sweepStale() runs from the launch .task and from onChange(of: scenePhase) with initial: true, with none of the four collect guards. A threshold evaluated only at process start is gone.

It is still not a timer. Age is rechecked when the scene phase changes, not while the scene sits still. Cancel Face ID and leave the lock screen in the foreground for fifteen minutes and the file is not looked at again until the next phase change or an unlock that reaches collect. That is much narrower than “held for the life of the process.” I am not reopening S4-13 on it.

S4-14. Closed. staleAfter is freshness. oneThresholdRatherThanTwo fails if they drift.

S4-15. Closed as a class, with one leftover in the wiring.

ArrivalQueue is a value type. First keeps the screen, second is held, third returns false. Five tests pin all three, plus empty finished() and one-at-a-time. onOpenURL always calls arrived. That is the finding: a second URL is no longer destroyed and no longer dropped.

collectWhatArrived still returns unless arrivals.current == nil. An inbox image cannot occupy next behind a URL. After the URL is dismissed, finished() clears current and nothing calls collect until the next scene, lock, or gate event. The file is still on disk. It is not the silent destroy of round one. It is a share that waits for another activation. The comment on collect still says that is deliberate.

The app ignores arrived’s Bool. A third URL is refused with no UI. For a flood that is the right behaviour. The “says so” in the tests is the queue’s, not the person’s.

S4-17. Closed. setResourceValues is try, then a fresh URL is read back, and isExcludedFromBackup != true throws .notExcludedFromBackup before any file is written. The extension surfaces that as “Could not save it.” A share that cannot be kept out of backup must fail. That is the right failure. There is no test of the throw, only of the success path. I cannot inject a failing exclusion in this tree; I am not treating the missing test as a hole in the rule.

S4-18. Closed. take opens one FileHandle, reads limit + 1 bytes through it, refuses if the extra byte arrives, and still deletes in defer. A missing size cannot skip the bound because there is no size lookup. A replace between two calls has only one call. An empty file returns empty Data (count 0 ≤ limit). A file unlinked after open is still readable through the handle on Darwin, then defer removes whatever path remains. The oversized test still holds.

S4-12. Closed. Reveal is isSecretRevealed && !isScreenCaptured. The eye is .disabled(isScreenCaptured) with an accessibility label that says why. Capture starting while revealed forces SecureField again. Capture ending leaves isSecretRevealed as the person left it.

S4-19. Closed. Size is read from the system file inside the loadFileRepresentation callback; no size or a size over the ceiling resumes nil and copies nothing. run still applies the in-memory policy bound.

S4-20. Closed for the planted-name case. sweepStale lists the directory, not pending(). A name that is not a UUID is removed. unknownNamesAreSwept pins that a not-a-uuid file is gone and a real write is not.

S4-21. Closed. For each of iphoneos and iphonesimulator, grep must find the generation switch set to NO at least twice (Debug and Release). Silence is a failure. The pattern includes the quotes the project file actually uses. I counted the two NO lines per SDK in the OpenFactor target. I still do not see a check of a built Info.plist. That is the artifact that fooled an engine in round one. The generation-off requirement is what makes the source file authoritative, so I am not reopening S4-21 on it.

S4-22. Closed. oversizedBatchFieldIsRefused and batchFieldAtTheMaximumIsAccepted cover fields 3, 4, and 5 in both directions. Removing the guard on UInt64.max would trap in Int(value) inside read, which is the original crash inside the suite.

S4-16. Mostly closed. The URL sentence in SECURITY.md is rewritten and names why it survived. write no longer describes a URL leaving the process. &+ is described as wrapping. The clipboard code lifetime is the HOTP fallback in copyCode. APP_LOCK.md bounds now cite staleAfter and say it is the same constant as presentation. Two leftovers are under question 3.

───

Question 2 — did any change introduce something new?

The arrival binding is the one the brief asked about. I cannot prove a loss.

get: { arrivals.current }
set: { if $0 == nil { arrivals.finished() } }

AccountListView wraps that again as presentedArrival, whose get returns nil while canPresentArrival is false and whose set forwards any write, including nil.

sheet(item:) writing nil on dismiss is the intended promote: dismiss A, finished(), current becomes B. That is not the watch-alert bug. There, SwiftUI wrote false before the button. Here, nil is the dismiss.

I walked the sequences I can run in my head. An arrival landing while settings is up sets canPresentArrival = false without an arrival sheet on screen, so SwiftUI has nothing to dismiss and no reason to write nil. Dismissing A while B is queued promotes in the same write; onChange(of: arrival?.id) then sees B. I do not have a SwiftUI write of nil after that promote that I can point at in this source. I will not file a defect I cannot exhibit. If one exists it is a second set(nil) in the same dismiss turning B into finished() of B. The queue itself is fine. The glue is the only place that could drop it, and it is untested against SwiftUI.

sweepStale now deletes names this process did not write, on every phase change, in a directory the extension writes to. That is new. Data.write(..., options: .atomic) on some Apple paths stages a hidden temp next to the destination. A name like .<uuid> does not parse as a UUID, so this sweep would treat it as planted and remove it. I did not verify that Darwin stages the temp in Inbox/ rather than NSTemporaryDirectory(). If it stages in system tmp, there is no race. If it stages in Inbox/, opening the app while the extension is still writing can fail a legitimate share. Unsure. I am not promoting it.

I did not find a new defect in take. One open, one bounded read, delete either way.

───

Question 3 — claims the code does not do

SECURITY.md still says leftovers are swept at launch and that the sweep “removes anything older than five minutes.” That paragraph was the S4-16 item about the inbox lifecycle. The code now sweeps on every scene-phase change and staleAfter is ten minutes. The URL sentence above it was rewritten in this commit. This one was not.

SharedInbox’s header is a broken splice:

/// Written by the extension, taken **once** by the app, and swept whenever the app comes
/// forward. **The sweep removes what is older than `staleAfter` rather than everything**, so
/// it cannot take the item somebody shared a moment ago.
/// killed between the extension writing and the app reading. ...

The last lines are the tail of the sentence they replaced. A comment nobody can parse is a comment nobody can trust.

write still says “An item lives for seconds” in the exclusion comment. The type’s own appGroup comment now says “until confirmed, and at most staleAfter.” Those two sentences in the same file disagree. The second is the one the code implements.

sweep() is still documented as “Removes everything, for launch.” Launch does not call it. collect does.

───

Question 4 — is this converging?

Yes.

The inbox has been rewritten three times: no sweep, then a launch sweep plus a clamp, then an activation sweep plus refuse-the-future plus unknown names plus a handle-based take. The third pass closed the one fix all three engines rejected, and it closed it by changing the rule, not by moving the same check. The two clocks are one clock. The arrival rule is a value type with tests, which is why round one and round two each shipped a different untested half.

What is left is documentation that did not finish the walk, a collect path that still will not fill the queue’s second slot from the inbox, and a sweep that deletes foreign names — the last of those being the only new behaviour I would want another pair of eyes on, and only if Darwin stages atomic writes in that directory.

This is not the same core still being wrong. I would not run a fourth round on this scope for the inbox lifecycle. I would fix the SECURITY.md paragraph, because a document that still says five minutes after the code stopped doing that is the rot this gate keeps paying for.

Fable:
I'll run round three of Scope 4. First the updated prompts file's Round three section and the round-two results document.

Ran 2 commands, read A4-round-two-scope4-results.md

Now the fix commit itself.

Ran 2 commands, read 3 files

Now the app wiring for the queue, and the other changed files.

Read OpenFactorApp.swift, ran 8 commands
Scope 4, round three: the fixes to the fixes

Code under review: 83e5cdd. Verified: the checkout at 0d05a05 differs only in audit documents. I read the fix commit whole, then re-read the current SharedInbox, ArrivalQueue, OpenFactorApp, ShareViewController, ManualSetupView, ImportViewModel, the CI workflow, the batch parser and both test files, against the twelve-item account in A4-round-two-scope4-results.md.

Method note, and a correction to the record I myself wrote. This is the same conversation that produced the Fable 5 passes in rounds one and two, not the fresh session the prompt prescribes. The round-three prompt says I am not bound by the previous round's conclusions — including mine. I am using that: S4-22 was a false finding, and I filed it. Details under question 1.

The verdict in one line: eleven of the twelve items are genuinely closed, the one that was rejected by all three engines is now fixed correctly, one item (S4-22) turns out to have been fixed before it was filed — and the two things worth attention now are a plausible arrival-queue wedge at the SwiftUI boundary and a fresh round of documentation left behind, including in the paragraph that brags about having been corrected once.

Question 1: does each change address its finding?

S4-8, the fix nobody accepted — now fixed correctly. SharedInbox.swift:207: a stamp after now becomes .distantPast. Walking the round-two attack through it: the planted file sorts last (distantPast under everything genuine), fails collect's freshness test, and sweepStale computes its age as effectively infinite, so it is removed on the first sweep. The replacement test asserts exactly the two properties the clamp version passed while failing — the genuine share is the one offered, and the plant is gone after a sweep — and I checked that reverting to the clamp reddens both assertions, as claimed. On the brief's question of whether refusal loses anything real: the extension and the app share one device clock, so no legitimate writer can stamp the future; the only casualty is a share made just before a backwards clock correction, which is swept and costs one re-share — the same "cost of being wrong is one prompt" trade AppLockEngine already makes for backwards clocks. The implemented rule has no skew allowance at all, and needs none for a same-device writer. Closed.

S4-13 — closed, slightly better than claimed. sweepStale now runs from .onChange(of: scenePhase) (OpenFactorApp.swift:211), which fires on every phase transition, a superset of "every activation." The launch .task call is now redundant — two sweeps at launch, harmless. A resident process holds an item for at most ten minutes plus one phase change.

S4-14 — closed in code, left behind in one document. staleAfter = freshness (SharedInbox.swift:268), a test pins the equality, and docs/APP_LOCK.md now names the constant. The unification widened the sweep window from five minutes back to ten — the coherent choice, made openly. But SECURITY.md line 551 still says "removes anything older than five minutes" — see question 3.

S4-15 — the value type is right; the wiring carries this round's one real open risk. ArrivalQueue is correct as a value: first keeps the screen, one held, a third refused with the refusal reported, five tests covering both prior defects. The bound of two is defensible — whatever sends a third can send a thousand, and the refused case is a URL, which its sender can re-open. The risk is in the binding (OpenFactorApp.swift:49): see N1 under question 2.

S4-17 — closed properly. The exclusion mark now throws, is read back on a deliberately fresh URL to defeat cached resource values, and the write is refused with its own error case (SharedInbox.swift:118-130). Is the failure the right one? Yes: the extension already shows "Could not save it," retry is one gesture, and the alternative was a backup-eligible image of every seed. The corner it creates — a device where exclusion never takes can never use the share extension — is the correct corner to be stuck in.

S4-18 — closed properly, and this is the best rewrite in the commit. take opens one handle, reads limit + 1 bytes through it, and refuses on the extra byte (SharedInbox.swift:231-238). There is no size lookup to skip and no second call to race: the bytes are the bytes of the file that was opened. The brief's three probes: refusal — tested, including the replaced-file case that defeats the old shape; the empty file — read(upToCount:) returns nil at immediate EOF, so it throws notFound and the defer removes it, which is right for a zero-byte image; the file disappearing between open and read — the open file descriptor survives an unlink on APFS, the read returns the opened file's contents, and the defer's remove silently no-ops. All three behave.

S4-12 — closed, and more thoroughly than the account says. Not only is the reveal control disabled: the field itself falls back to SecureField whenever capture is on (ManualSetupView.swift:83), so a capture that starts mid-reveal re-masks immediately rather than waiting for a tap. That is the stronger property and it is the one that matters. One nit: "disabled rather than hidden, so the reason is visible" — the reason is in the accessibility label, so it is audible to VoiceOver and invisible to a sighted user, who sees a greyed eye. Cosmetic.

S4-19 — closed. The size is read from the system's own file inside the callback and fails closed on an unreadable size, before any copy (ShareViewController.swift:124-131). The system's materialized file is not attacker-writable inside the extension sandbox, so the measure-then-copy gap is not a TOCTOU that matters here.

S4-20 — closed, with two small new races it creates; see N2 and N3.

S4-21 — closed. The CI check now requires the generation switch to be present and NO twice per SDK, so deleting the lines — which would restore Xcode's default and regenerate the manifest — fails instead of passing (ci.yml). I checked the quoted pattern against the actual pbxproj lines; it matches, and grep -c … || true behaves under set -e. Silence is now a failure, which was the point.

S4-22 — the finding was false, and I am the one who filed it. At round two I reported that no test exercises the batch-field bound. That was wrong: MigrationBatchBoundsTests — with theCrashingPayloadIsRefused (the literal UInt64.max payload), everyFieldIsBounded (all three fields, one past the bound), and theBoundItselfIsAccepted — was added in 43103dc, which is an ancestor of round two's review commit 6254706. My greps at round two were piped through head and truncated before line 330 of the test file, and I reported the absence of something I had simply not scrolled to. Consequences in this commit: the two new tests (GoogleAuthenticatorImportTests.swift:410-427) duplicate everyFieldIsBounded and theBoundItselfIsAccepted almost line for line in the same file — harmless, redundant. And the commit's sentence "removing the guard makes them trap rather than fail" is true of the pre-existing UInt64.max reproducer (whose Int(value) conversion traps without the guard), not of the new over-by-one tests, which would fail politely. The record — my round-two pass, the triage table, and the results document — carries my error forward, and this is the correction.

S4-16, the six claims — five fixed, with fresh residue. Verified fixed: the extension-passes-nothing rewrite in SECURITY.md and in write()'s comment; the clipboard code lifetime now genuinely consumed by the HOTP path (AccountListViewModel.swift:357), making the rules table true; the &+ comment now correctly names it a wrapping add and defends keeping it (a defensible choice — the invariant is guarded upstream and tested, and a trap during sheet construction is the worst failure mode available); APP_LOCK.md's ten-minute bound now cites the constant; R5 amended for the queue. The residue is in question 3.

Question 2: did any change introduce something new?

N1 — Low-to-Medium, plausible, unverifiable from source alone: the queue's promotion can be dropped by the exact SwiftUI behavior this codebase already documents, wedging all arrivals for the process lifetime. Promotion happens as a side effect of the sheet binding being set to nil (OpenFactorApp.swift:52): dismissal writes nil, finished() promotes the held arrival, current changes identity, and sheet(item:) must present the new item while the old sheet's dismissal is still animating. AccountListView's own canPresentArrival comment states the project's measured position on that situation: "presenting one sheet while another animates out is a request SwiftUI drops on the floor." That machinery protects the arrival sheet from other sheets' dismissals — nothing protects the promoted arrival from the arrival sheet's own. If the present is dropped, current stays non-nil with nothing on screen, collectWhatArrived is blocked by arrivals.current == nil forever, one more URL fills next, and every arrival after that is refused: the queue is wedged until the process dies. A second, related shape: if SwiftUI ever writes nil twice for one dismissal, the second finished() silently discards the held arrival. Both stem from one root — promotion is driven by a binding side effect rather than by a completed-dismissal signal. I cannot confirm either without a device, and I say so plainly; but the failure mode the design relies on avoiding is one this repository has already measured and worked around elsewhere. Smallest fix: promote from the arrival sheet's onDisappear (the signal sheetDidClose already uses for every other sheet), making finished() idempotent per presentation; that routes the queue through the same machinery that already exists for exactly this problem. This is the item I would carry to the manual checklist regardless: share an image, open a link while its sheet is up, dismiss, and watch whether the link presents.

N2 — Low: the unknown-name sweep can race the extension's atomic write. sweepStale now deletes any name that doesn't map to a pending UUID, on sight (SharedInbox.swift:296), and it runs on every phase transition — which is precisely the moment a share completes: the person leaves the host app for OpenFactor while the extension may still be finishing. Foundation's .atomic write stages a temporary file in the destination directory before renaming; that temp name is not a UUID, so a sweep firing in the window deletes it mid-write and the share fails with "Could not save it." Rare, availability-only, one-gesture recovery. Age-gating unknown names (delete only when older than, say, a minute — their creation date is readable) removes the race without weakening the property.

N3 — Low, pre-existing but newly load-bearing: the UUID round-trip is not the identity for lowercase names. pending() accepts any name that parses as a UUID, but Pending.id.uuidString re-serializes uppercase, and take() builds its path from that (SharedInbox.swift:219). A sibling-written file with a lowercase UUID name is listed by pending(), un-takeable by take() (wrong-case path, notFound), and — if it sorts newest — turns collect() into a failed take followed by its deferred full sweep(), deleting every genuine share behind it. The new unknown-name logic accidentally half-fixes this: the ages dictionary is keyed by uppercase strings, so a lowercase name misses the map and is swept on sight, and in the activation path the sweep runs before collect. But collect also fires from the lock and gate onChanges with no sweep in front of it, so a narrow window remains. The clean fix is to stop re-serializing: key everything by the literal file name (or require name == id.uuidString in pending()).

N4 — nits, recorded for the churn ledger: the redundant launch sweep (.task plus onChange(initial: true)), and the duplicated batch-bound tests from the false S4-22. Neither costs anything at runtime.

The rest of the commit introduces nothing: the ImportViewModel guard is a strict tightening with the right (recoverable) failure; the reveal fix cannot regress the passphrase paths, which never had a reveal; the CI change is additive.

Question 3: what is now claimed that the code does not do?

D1 — SECURITY.md still says the sweep "removes anything older than five minutes" (line 551). The constant is now ten. This sentence sits inside the paragraph that opens "Leftovers are swept at launch, and until gate A4 that sentence was not true" — a paragraph about its own past falsehood, now false again in its number, and understated in its trigger (the sweep runs on every foreground transition, not only launch — the safe direction, but still not what it says). This is the third consecutive round in which the inbox lifecycle prose trails the inbox lifecycle code by exactly one fix.

D2 — the SharedInbox header was mangled by this commit's own edit. Lines 31–35: "…and swept whenever the app comes forward. The sweep removes what is older than staleAfter rather than everything, so it cannot take the item somebody shared a moment ago. killed between the extension writing and the app reading. That is the same lifecycle…" — the bolded fragment is an orphan from the deleted sentence, mid-paragraph, in the file's front-page documentation.

D3 — "an item lives for seconds" survives in two of the four places it was supposed to die. The commit's account says this claim was corrected to "until it is confirmed or swept." It was — in the header and the appGroup comment. It still stands verbatim in write()'s comment (SharedInbox.swift:108: "An item lives for seconds, but a backup taken during those seconds…") and in SECURITY.md's exposure paragraph ("a backup taken during those seconds does not carry it away"). An uncollected item now lives up to ten minutes. The backup-exclusion fix makes the consequence claim true regardless, which is why this is a documentation finding and not a code one.

D4 — the commit message's "removing the guard makes them trap" is accurate only through the pre-existing UInt64.max reproducer, not the tests this commit added — covered under S4-22 above, along with the false premise it rests on, which was mine.

D5 — minor: APP_LOCK.md's amended R5 documents the held second arrival but not the refused third, so the normative document describes a queue with no bound; and the round-two results table's "closed" rows for S4-5/S4-22 inherit my false finding.

Question 4: is this converging?

Yes — and I can point at what converged rather than assert it. The three areas touched three times each all ended at the construction the reviews specified, not at a new guess: the timestamp rule went wrong-once (trust), wrong-twice (clamp), then landed on the reviewer-prescribed .distantPast with a test that pins the adversarial property instead of the cosmetic one; the arrival rule went wrong-once (replace), wrong-twice (drop), then became a tested value type; take went unbounded, then racy-and-skippable, then a single bounded read with nothing to skip and nothing to race. Fail-open has been eliminated as a class — ImportViewModel, the extension, and the inbox all now share the same guard let … else refuse shape, which round two found inverted in all three places. And the process itself corrected: the tests written this round assert what an attacker experiences, not what the fix author intended, which is the exact failure the two rejected fixes shared.

Two things are still moving, and naming them is more useful than the reassurance. First, documentation converges one round behind code, every round: round two left "ten minutes" stale, this round leaves "five minutes" stale, and the file that explains the inbox now contains a broken sentence. The pattern suggests doc edits are done from the fix account rather than by re-reading the files touched; a CI grep tying SECURITY.md's number to the constant would end the cycle. Second, the remaining risk has migrated to the one boundary no test in this repository can reach: the seam between a correct value type and SwiftUI's presentation timing, where N1 lives and where the project's own canPresentArrival workaround already testifies that the framework drops requests. That is not churn — the pure cores are demonstrably done — but it means the next real defect in this scope, if there is one, will be found on a device, not in this suite. The manual checklist, not another source round, is the instrument that closes it.
