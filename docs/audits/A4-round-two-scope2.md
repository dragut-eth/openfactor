# A4 round two, scope 2: what changed and why

Round one found eleven items in the Watch key exchange. All eleven are fixed. This is the
"what changed" block the round-two prompt in `docs/audits/A4-prompts.md` calls for.

**Review commit `f4710b5`.** Round one read `74fe841`.

Round two asks three questions and only three: does each change address the finding it claims to,
did any change introduce something new, and does any comment or document now claim something the
code stopped doing.

## The eleven, and what was done

**1. The watch wrote the vault key without `.complete` protection.** `VaultKeyStore.install`
borrowed `SharedInbox.writingOptions`, which is `#if os(iOS)`, narrower than the platforms the
call supports. `VaultKeyStore` has its own `writingOptions` now, covering iOS, watchOS and tvOS.

**2. `install` wrote the key before excluding it from backup.** A kill between the two left a
usable key with no exclusion and nothing to retry it. It now writes to a staging file, marks that,
and moves it into place with `replaceItemAt`.

**3. The phone answered "asking" to a request it discarded.** Fixed on the watch instead of the
phone, taking round one's own suggestion: an obsolete response proves the phone has just freed its
slot, so `WatchVaultModel.phoneSent` asks again immediately. The phone's answer is still
imprecise; the watch no longer depends on it.

**4. A decline was bound to nothing.** `WatchProvisioning.MessageKey.nonce` is new; the phone
echoes the refused request's nonce and the watch ignores a decline meant for another attempt.
`Attempt.answers(_:)` does the comparison. A decline carrying no nonce is still honoured.

**5. The `.noRandomness` catch in `ask()` left a stale attempt.** It now clears `attempt` and
`token` before telling the flow the attempt failed.

**6. `responseDidNotOpen` had no `outstanding` guard**, so a call with nothing outstanding could
demote any stage including `.ready`. Guarded, with tests from both sides.

**7. Consent could be arbitrarily stale.** `ValidatedRequest` carries `validatedAt`, and
`approve()` refuses beyond `WatchKeyProvider.consentWindow`, two minutes.

**8. A static phone keypair passed the entire suite.** `responsesToOneRequestAreFresh` now
requires the ephemeral public key itself to differ between two responses to one request, not
merely that the responses differ.

**9. Deleting the HKDF label passed the entire suite.** `theLabelParticipatesInDerivation`
derives from the same shared secret and transcript without the label and requires a different key.

**10. `docs/VAULT.md` claimed the watch's private key may live in the Secure Enclave.** It never
did and does not; the sentence is replaced with what the code actually does.

**11. `SECURITY.md` claimed the earlier review's four fixes were "all now tested".** Two had no
test. The sentence now says so.

## Where to look hardest

Three of these changed a state machine that has now been modified on three separate days, and
round one found that two of the previous day's fixes had created new defects. Items 3, 4, 5 and 6
are that machine.

Item 3 is the one to attack first: it makes the watch send a new request from inside the handler
for a received message. Round one's suggestion was followed, but the reasoning that it cannot spin
is this repository's, not the reviewer's, and it deserves to be disbelieved until checked.

Item 4 adds a field to a message. Whether an older build on either side behaves sanely against a
newer one is worth thinking through, and the claim that a nonce-less decline must still be
honoured is a judgment that could be wrong.

Item 7 introduces a clock into an approval path. Clocks move backwards.

---

# Round two: the returns

**All three engines returned.** An intermediate version of this page said ChatGPT had not run,
which was wrong: its return had not reached the file, and the absence was read as an absence of a
review rather than of a paste. The engine column below is taken from the three returns reproduced
at the end of this file.

**Commit reviewed: `350375b`.** Round one read `74fe841`.

| Engine | Status |
| --- | --- |
| ChatGPT 5.6 Sol | Returned, below. One medium, three low, and the only fix assessment given item by item |
| Fable 5 | Returned, below. Nine of eleven complete, one gap, one new medium |
| Grok 4.6 | Returned, below. Three of eleven incomplete, plus two doc mismatches |

## What the three engines found

| Finding | Engine | What it took |
| --- | --- | --- |
| Consent expiry measured on a wall clock | **all three** | `ContinuousClock`. `validatedAt` is internal now, so nothing outside the package can compare a `Date` to it again |
| A kill still leaves a raw unexcluded key at `.{uuid}`, because `defer` does not run after a kill | ChatGPT, Grok | The key is written inside a directory excluded *before* any key material exists, and orphans are swept. Both proposed exactly this |
| `replaceItemAt` without `.usingNewMetadataOnly` keeps the *old* file's protection class | Grok | The option |
| Nothing repairs an already weakly-protected `vault.key` | ChatGPT | Reading the key now repairs its protection class and exclusion in place |
| The re-ask abandons a request the phone really retained | ChatGPT | The inference removed, and the phone answers `.busy`, which is the fix ChatGPT named |
| `phoneDeclined` never got the guard its sibling got | ChatGPT, Grok | The same `guard outstanding != nil`, with a test from both sides |
| `messageKeysArePinned` said "exactly these three" against four | ChatGPT, Grok | The fourth pinned. Renaming `nonce` compiled everywhere, and every decline from a newer phone would have looked nonce-less |
| A nonce present but of the wrong type was treated as absent, so it was honoured | ChatGPT | Presence and readability are separated: a nonce that is there and cannot be read is ignored |
| Expired consent returned silently, leaving the alert up and the owner unanswered | ChatGPT | Expiry declines, which clears the alert and tells the watch |
| The comment claiming a watch would wait forever is false | ChatGPT, Fable | Corrected. The twenty five second timeout recovers |
| `SECURITY.md` stated the nonce echo unconditionally | Fable | The sentence says what the code does |
| `SECURITY.md` said "two minutes" of wall-clock minutes | Grok | Says elapsed, on a clock that cannot be moved |
| `validate()` became a parser that reads a clock | Fable | `age(now:)` takes the instant, so a test chooses it |
| The refusal message is a third message, unversioned, and absent from the protocol tables | Fable | `docs/VAULT.md` documents the dictionary and the compatibility rule |

**Two engines cleared the re-ask; the third had already broken it.** Fable and Grok were both
invited to disbelieve the claim that re-asking from inside a response handler cannot spin. Both
walked the call order, both correctly found no spin, and both said so. ChatGPT was not looking for
a spin: it wrote out the seven-step sequence in which a delayed response makes the watch abandon a
request the phone has genuinely retained, and named the fix, which is that the phone must stop
answering `.asking` for a request it does not keep.

That is the removal that shipped, and the reasoning behind it is ChatGPT's rather than this
repository's. **An intermediate version of this page claimed the opposite** — that no review had
asked for it and it was removed on the maintainer's own reading. That was written while ChatGPT's
return was missing from the record, and it is exactly the kind of claim that should not have been
made from an incomplete file.

**Fable's uncovered path is narrowed rather than closed, and that is the honest description.** Its
sequence still ends with a wearer waiting: a decline echoing attempt A's nonce is correctly
ignored by a watch holding attempt B, and B is never answered. What changed is that B now gets
`.busy` rather than `.asking`, so nothing claims a person is being asked about it, and the twenty
five second timeout ends the wait at a screen with a button on it. The dead end is bounded, not
removed.

## What the reviews did not find

Two fixes came from writing the tests rather than from any review. `.usingNewMetadataOnly` installs the *staged*
file's metadata, so the fix for the write window stripped the backup exclusion off the key it
wrote, and the suite went red the first time both changes ran together. And a `.busy` answer
arriving after a timeout restored a spinner whose timer had already fired.

**The repair of an already-written key was ChatGPT's, filed as a caveat rather than a finding.**
It is the last line of its item 1: the new options fix future writes, and no code repairs an
existing weakly protected `vault.key`, so a Watch that already holds one keeps it forever. Grok
came at the same fact from the other side, noting such a watch "can be re-provisioned", which is a
repair that requires somebody to know they need it. Reading the key now repairs its protection
class and backup exclusion in place: metadata only, so it cannot damage the key it repairs.
**Another intermediate version of this page called this the item no review raised.** It was
raised, in the return that was missing.

Each fix with a test was reverted individually and the suite confirmed red for it. That check
found nothing wrong with the fixes and one thing wrong with a new test, which had been re-reading a
cached `URL` snapshot instead of the file.

---

## ChatGPT 5.6 Sol

*Read-only pass over commit `350375b`. Reproduced as returned, with absolute paths made
repository-relative.*

> Reviewed commit `350375b`; its source is unchanged from the fix commit `f4710b5`. Round one read `74fe841`.
>
> Findings
>
> 1. Medium — the backup-exclusion fix preserves the original kill window in the staging file
>
> `VaultKeyStore.install` (line 98) now writes the raw key to a randomly named staging file, then excludes that file from backup:
>
> 1. Line 116 writes the complete 32-byte key.
> 2. Line 124 applies `isExcludedFromBackup`.
> 3. Line 129 moves it to `vault.key`.
>
> A process kill between steps 1 and 2 does not execute the `defer` at line 114. It therefore leaves a complete, unexcluded raw vault key in Application Support indefinitely. Backups enumerate the container, not merely the filename `vault.key`, so changing the name to `.<UUID>` does not address the reported exposure. This is the same failure as round one: `write raw key -> process killed -> unexcluded key survives`. It has merely moved to a staging pathname.
>
> Smallest fix: create and mark a dedicated excluded staging directory before placing any key material inside it, then stage and atomically replace from there. Sweep orphaned staging entries on launch as defense in depth. A fault-injection test should terminate the install after the write and verify that every surviving file containing the key is already excluded.
>
> Related caveat: the new `.completeFileProtection` options fix future writes, but no code repairs an existing weakly protected `vault.key`. If a build containing the old write shipped, updating alone leaves that Watch's file unchanged.
>
> 2. Low — retrying on every obsolete response can abandon a request the phone really retained
>
> The new logic at `WatchVaultModel.phoneSent` (line 209) assumes an obsolete response proves the phone's pending slot "is free right now," then immediately calls `ask()`. That inference is invalid across an asynchronous channel:
>
> 1. Attempt A times out.
> 2. The owner approves A; response A is sent and delayed, and the phone clears its slot.
> 3. Before response A arrives, the wearer starts B. The phone retains B and displays its alert.
> 4. Delayed response A reaches the Watch and is obsolete relative to B.
> 5. The new fix abandons B and starts C.
> 6. The phone still holds B, so it answers C with `.asking` and discards C.
> 7. Approval of B now produces another obsolete response; the Watch starts D and needs another approval.
>
> Thus the fix for item 3 creates another retry race and can turn an otherwise successful retained request into repeated prompts. "Only a delivered response reaches this line" prevents a self-sustaining local loop, but does not prove the phone has not refilled its slot since sending that response.
>
> Smallest fix: make the phone's direct reply authoritative. It must not answer `.asking` for an unretained request — return a distinct busy/terminal status, or queue the latest request separately without replacing the request currently covered by the alert.
>
> Missing test: `A response delayed -> B retained by phone -> A response arrives -> B approval still completes without another request`.
>
> 3. Low — decline matching remains incomplete and can still demote a ready Watch
>
> At `WatchVaultModel.phoneSent` (line 244), a nonce-bearing decline is rejected only when an `attempt` exists and the nonce differs:
>
>     if let declined = ... as? Data,
>         let attempt, !attempt.answers(declined) {
>         return
>     }
>
> If `attempt == nil`, the condition fails and execution proceeds to the unguarded `flow.phoneDeclined()`. A delayed decline received after successful provisioning therefore changes `.ready` to `.notSetUp`. This is the same missing-outstanding-guard class that item 6 fixed for `responseDidNotOpen`, left open on the decline transition.
>
> Mixed-version behavior also leaves the original stale-decline defect intact: a new Watch honors every nonce-less decline from an older phone. The comment's claim that ignoring one would leave the Watch "waiting forever" is false; the existing 25-second timer already provides recovery.
>
> Smallest fix:
>
> * Require a current attempt before processing any second-message decline.
> * Add an `outstanding` guard inside `WatchProvisioningFlow.phoneDeclined()`.
> * Ignore nonce-less declines and let the timeout recover, or honor them only when the model can prove no attempt has been superseded.
> * Reject a present-but-wrongly-typed nonce rather than treating it as absent.
>
> Missing tests: `ready -> delayed decline -> remains ready`, and `B current -> nonce-less decline from A -> B remains current`. The wire-value suite should also pin the new `"nonce"` key; it still asserts only the original three keys despite the enum now having four.
>
> 4. Low — wall-clock rollback defeats the consent deadline
>
> `WatchKeyProvider.approve` (line 75) checks:
>
>     Date().timeIntervalSince(request.validatedAt) <= 120
>
> There is no lower bound and `Date` is wall time. If the clock moves backward after validation, the interval is negative and remains `<= 120`, potentially for hours or days. The stale request can therefore still release the vault key after the claimed two-minute consent window when the owner taps the lingering alert.
>
> Smallest fix: measure the deadline with a monotonic clock such as `ContinuousClock`, inject that clock for testing, and automatically clear the pending request and alert when the deadline expires.
>
> Missing test: validate at T, move the injected wall clock backward, advance monotonic time beyond two minutes, and require approval to send nothing.
>
> Fix assessment
>
> * Item 1: correct for newly written files; existing weak files are not migrated.
> * Item 2: not fixed — the staging file retains the exact write-before-exclusion kill window.
> * Item 3: addresses the reported sequence but introduces the new retained-request race above.
> * Item 4: works for two current builds when an attempt exists, but remains incomplete for no-attempt and mixed-version cases.
> * Items 5 and 6: the reported paths are correctly fixed.
> * Item 7: incomplete because it uses a reversible wall clock.
> * Items 8 and 9: the new negative tests correctly catch a static phone key and removal of the HKDF label.
> * Items 10 and 11: the documentation corrections match the code.
>
> The cryptographic construction and byte parsers remain unchanged and sound for the reasons recorded in round one: exact lengths precede slicing, P-256 points are validated, the request nonce is checked before derivation, and the fixed-width transcript binds both public keys and the nonce in HKDF and GCM AAD. Approval still has only the affirmative alert button as a production call site.
>
> No build or test command was run because the requested review prohibited creating files.

---

## Fable 5

*Read-only pass over commit `350375b`. Reproduced as returned, with absolute paths made
repository-relative.*

> Round two, scope 2: the Watch key exchange
> Commit reviewed: 350375b, read from .. Verified: HEAD is 350375b, the tree is clean, and git diff 74fe841..350375b touches the files claimed. All eleven changes verified against the diff, not against the summary.
> Answering the three questions in order.
> 1. Does each change address the finding it claims to?
> Nine of eleven: yes. Two have gaps.
> Item 3 — the dropped retry — is fixed for the sequence round one described, and leaves one path uncovered.
> The re-ask is real and cannot spin: ask() is reached only from receiving a response, WCSession delivers on the main queue, WatchVaultModel is @MainActor, and each re-ask sends exactly one message. The prompt invited me to disbelieve the no-spin claim; I tried, and it holds. Two independent brakes: `ask()` returns early when `flow.stage == .ready`, and reaching the re-ask requires a delivered `response` key, which only `approve()` sends and only after a human tap.
> The uncovered path: the phone still answers `.asking` to a request it discards, and if approve() is never called, no response is ever delivered, so the re-ask never fires.
>
> 1. Watch A → phone stores A, alert up.
> 2. A times out (25 s). Watch keeps A, shows needsPhoneApp.
> 3. Wearer taps Try again → B. Phone answers `.asking`, discards B.
> 4. Owner taps Not now.
> 5. `decline()` sends `status: declined` plus **A's nonce** (the item-4 fix).
> 6. Watch holds B. `attempt.answers(A's nonce)` is false → the decline is ignored (correct: it is not B's).
> 7. Watch waits out another 25 s on a phone whose slot is now free and which will never speak again.
>
> The wearer sees the same "phone not answering" dead end round one reported, one branch over. Not a regression — the pre-fix code had the same dead end via a different route — but item 3's claim to have fixed "the dropped retry" is broader than what shipped. The decline path was not part of round one's sequence, so this is a gap in coverage rather than a fix that fails.
> Item 7 — consent expiry — fixes the stale-consent finding and introduces a new failure mode (see question 2).
> The remaining nine: verified individually, each does what it claims. Item 1's `writingOptions` is correctly `os(iOS) || os(watchOS) || os(tvOS)`, and `SharedInbox` keeps its own narrower rule, which is right — the share inbox genuinely is iOS-only. Item 2's staging write is correct and the ordering is now impossible to get wrong: the file at `url` has always been through both steps, because `replaceItemAt` is the only thing that puts it there. Item 4's `answers(_:)` is constant-time and length-checked. Item 5 clears both `attempt` and `token`. Item 6's guard matches its siblings. Items 8 and 9 are the two tests that now fail against the regressions they were written for — I re-derived both by hand and they do observe what they claim. Items 10 and 11 are accurate.
> 2. Did any change introduce something new?
> Yes. One medium, one low, one observation.
> M1 — Consent expiry uses wall-clock time and fails open on a backward clock jump.
> `WatchKeyProvider.swift:88` (`validatedAt`, set from `Date()` in `WatchProvisioning.validate`), checked at `WatchKeyProvider.swift:75`:
>
>     guard Date().timeIntervalSince(request.validatedAt) <= Self.consentWindow else { return }
>
> If the clock moves backwards between validation and approval — NTP correction, timezone-adjacent DST handling, manual change, or a device that syncs time late in boot — the elapsed value is negative, `-3600 <= 120` is true, and the request is answerable indefinitely. The bound only holds for a monotonically forward clock.
> This is the exact defect class `AppLockEngine` already got right, and its comment says so: *"A negative elapsed time means the clock moved backwards while the app was away. That is indistinguishable from tampering, so it locks rather than reasons about it."* The lock fails closed on a backward jump; consent expiry fails open on the same input.
> Severity is medium rather than high because the window it reopens is the pre-fix behaviour, not something worse, and reaching it needs a clock change during a live provisioning attempt. But the fix is one comparison and the precedent is in this repository.
> Smallest fix: use a monotonic source (`ContinuousClock.now` or `DispatchTime.now().uptimeNanoseconds`) for the elapsed measurement, or reject negative elapsed the way `AppLockEngine` does. Monotonic is better here: it also survives the device sleeping, which `Date()` handles but `uptimeNanoseconds` does not — so `ContinuousClock` specifically, not `SuspendingClock`.
> L1 — `validate()` now stamps a timestamp, which makes it non-deterministic and slightly widens its contract.
> `WatchProvisioning.validate` is a pure parser in the core that now calls `Date()`. Two consequences, neither serious: a test cannot construct a `ValidatedRequest` with a chosen timestamp without also controlling the clock, and the phone's *validation* time rather than the *arrival* time is what the window measures — those differ only by the guard checks between them, so this is a naming quibble rather than a behavioural one. Worth noting because a parser that reads a clock is a small surprise in a file whose other function is byte-exact.
> O1 — The `nonce` message key sits outside the versioned envelope, and the compatibility argument is sound but undocumented in the protocol section.
> The two protocol messages are versioned by the `OFW1` magic inside their payloads. `MessageKey.nonce` is a *dictionary* key alongside `status`, so it carries no version marker. The chosen rule — an absent nonce is honoured, a mismatched one is ignored — is the right one and I could not construct a failure from it: an old phone with a new watch sends no nonce and is honoured; a new phone with an old watch sends a nonce the old watch ignores, which is exactly the pre-fix behaviour it already had. But `docs/VAULT.md`'s protocol section documents the two messages byte by byte and does not mention that a third field can appear in the second one. A second implementer working from that section would not know to expect it.
> 3. Does any comment or document now claim something the code stopped doing?
> Two, both small.
> D1 — `SECURITY.md:283-289` says the decline "echoes the nonce now". The code echoes it only when `pendingRequest` is non-nil.
> `WatchKeyProvider.decline()`:
>
>     var message: [String: Any] = [ ... status: declined ... ]
>     if let pendingRequest {
>         message[MessageKey.nonce] = pendingRequest.requestNonce
>     }
>
> `decline()` is reachable from the alert's "Not now" button, where `pendingRequest` is set, so in practice the nonce is always there. But the document states it unconditionally and the code does not. Either make it unconditional (return early if there is nothing pending — there is nothing to decline) or say "when there is a request to decline".
> D2 — `WatchProvisioning.MessageKey.nonce`'s doc comment says "Absent from a build older than this, which the watch honours rather than ignoring." True, but it describes only the old-phone case; the new-phone-to-old-watch direction (the nonce is present and ignored) is the other half of the compatibility story and is not stated anywhere in the protocol files. Minor, and it is the same gap as O1.
> What I checked and found clean
>
> * The four state-machine items (3, 4, 5, 6) do not interact badly. I walked every ordering of {timeout, send error, obsolete response, decline with matching nonce, decline with stale nonce, terminal answer} against `WatchProvisioningFlow` and `WatchVaultModel` and found no sequence where an attempt is cleared while the flow believes it outstanding, or retained while the flow believes it finished. The `token`/`attempt` pair is now cleared together on every path — I checked all seven.
> * Item 3's re-ask cannot recurse: `ask()` sends a message and returns; the response that would trigger another re-ask arrives on a later main-queue turn, not within the call.
> * `answers(_:)` compares against `nonce` (the attempt's own), not against the response's echoed copy, so it cannot be satisfied by an attacker-supplied pair.
> * No test was weakened. `responsesToOneRequestAreFresh` and `theLabelParticipatesInDerivation` are genuinely new coverage, and the existing negative controls are unchanged.
> * The `consentWindow` of 120 s is longer than the watch's 25 s timeout, so a live exchange cannot be cut off by it — the interaction I most expected to be wrong.
>
> Verdict: nine of eleven fixes are complete and correct. Item 3 fixes its reported sequence but leaves the decline-path dead end. Item 7 fixes its finding and introduces M1, a backward-clock hole that this repository already knows how to close — `AppLockEngine` closes the identical case three files away.

---

---

## Grok 4.6

*Read-only pass over commit `350375b`. Reproduced as returned, with absolute paths made
repository-relative.*

> 1. Does each change address the finding it claims to?
>
> 1. Watch .complete protection — incomplete. VaultKeyStore.writingOptions is now #if os(iOS) || os(watchOS) || os(tvOS) with .completeFileProtection. That is the right condition. A first-time install, when vault.key does not exist, replaceItemAt is a move and the new attributes should land.
>
> The ordinary path is an overwrite. The comment at install says so: “installing over an existing key is the ordinary path: a watch re-provisioned, or a passphrase unlocking a device that already held a key.” That call is:
>
>         _ = try FileManager.default.replaceItemAt(url, withItemAt: marked)
>
> No options. Apple’s default is to keep the original item’s metadata (creation date, permissions, and similar). usingNewMetadataOnly is what would keep the staging file’s protection class. A watch that already has a key written under the old .atomic-only path can be re-provisioned and keep complete-until-first-unlock, which is the class the original finding was about. The excludedFromBackup test only ever creates a new file in a new directory, so it cannot see this.
>
> 2. Backup exclusion ordering — incomplete, same function. Staging, then mark, then replace does close the reported case on the canonical path for a first write: load() never sees vault.key unmarked. On overwrite, the same default replaceItemAt can keep the old file’s exclusion bit. A kill between write and setResourceValues still leaves a .{uuid} file in Application Support that contains the raw key and is not yet excluded; defer does not run after a kill. Narrower than “vault.key is live and unmarked,” not gone.
>
> 3. Phone answered .asking then discarded — addressed, and it does not spin. phoneSent calls ask() only after open returned .notForThisRequest. That happens on a delivered 145-byte response whose nonce is not this attempt’s. approve has already cleared pendingRequest, so the new request is a new slot, not a loop. ask() cannot re-enter phoneSent. One extra alert, not a spin. I disbelieved the “cannot spin” claim until that call order.
>
> 4. Decline bound to nothing — addresses the live-attempt case; the compatibility choice is real. New phone puts pendingRequest.requestNonce on the decline. New watch ignores it when attempt.answers is false. Old watch ignores the extra key and still honours a decline. A nonce-less decline is still honoured, so an old phone can still kill a newer attempt. That is the mixed-version bug left on purpose. The comment that refusing those would leave the watch “waiting forever” is false: timedOut fires at 25 seconds.
>
> 5. CSPRNG catch left a stale attempt — addressed. The catch now nils attempt and token before sendFailed(beganAsking()). A late response then hits let attempt false and cannot install.
>
> 6. responseDidNotOpen unguarded — addressed for that method. outstanding != nil is there, with tests from both sides. phoneDeclined() still has no such guard (see below).
>
> 7. Stale consent — incomplete. validatedAt is Date() and approve uses Date().timeIntervalSince. That is wall-clock. A backward jump (Settings, time zone, NTP) makes an hours-old pendingRequest look fresh again, which is the finding they were closing. A forward jump of more than two minutes makes a live tap send nothing while defer still clears the slot; the owner thinks they approved. Reboot resets uptime and also drops the in-memory pending request, so a monotonic clock (ProcessInfo.systemUptime or ContinuousClock) would actually be “two minutes of elapsed time.”
>
> 8 and 9. Tests — they do the job. responsesToOneRequestAreFresh compares the 65-byte phone public-key field, not just the whole 145 bytes. theLabelParticipatesInDerivation derives once through wrappingKey and once as HKDF of the raw shared secret with sharedInfo: transcript only.
>
> 10 and 11. Docs — they match. VAULT.md now says software P256.KeyAgreement.PrivateKey, not Secure Enclave. SECURITY.md no longer says the earlier four fixes were all tested.
>
> ───
>
> Finding
>
> Medium — install still does not put the staging file’s protection (or exclusion) on an existing vault.key
>
> Where: VaultKeyStore.install, Sources/OpenFactorCore/Vault/VaultKeyStore.swift:129.
>
> Call order: write staging with writingOptions (complete + atomic) → set isExcludedFromBackup on staging → replaceItemAt(url, withItemAt: marked) with default options.
>
> What fails: Re-provision, or unlock onto a device that already has vault.key. The API’s default is to keep the original’s metadata. The file the rest of the vault then load()s can keep the old protection class and the old exclusion flag. That is exactly the watch that already got a key under the round-one bug, and exactly the path the new comment calls ordinary.
>
> I did not read the attributes back on a watch. I am not claiming a measured leftover class. I am claiming the write they added cannot, as documented, overwrite that class on the path that already has a file.
>
> Smallest fix: pass [.usingNewMetadataOnly], or delete url then move, then confirm NSFileProtectionComplete and isExcludedFromBackup on hardware after an overwrite. The first-install test is not enough.
>
> ───
>
> 2. Did any change introduce something new?
>
> ask() from phoneSent does not spin on a genuine phone. It can send a second request the moment an obsolete response arrives, which is the point. A flood of wrong-nonce 145-byte messages would flood ask(); that needs the WC injection the scope is not treating as a given.
>
> Expired approve is a silent no-op. The defer clears pendingRequest and isAsking even when the window has elapsed, so the alert vanishes and nothing is sent. New liveness hole, not a leak. Fail closed.
>
> phoneDeclined() can still demote .ready. Item 6’s guard was not applied here. The nonce filter is:
>
>             if let declined = message[WatchProvisioning.MessageKey.nonce] as? Data,
>                 let attempt, !attempt.answers(declined)
>             {
>                 return
>             }
>
>             attempt = nil
>             token = nil
>             flow.phoneDeclined()
>
> After a successful install, attempt is nil, so the filter does not run. A late decline (nonce-less, or nonce-bearing for an old attempt) calls phoneDeclined() and the list is replaced with “Not set up” even though the key is on disk. refreshAndAsk on the next wrist raise will foundWorkingKey() if the key still opens. Not theft. Same unguarded-demotion class item 6 was meant to close.
>
> I do not see a new way to install an unverified key, to substitute pendingRequest, or to approve without the button.
>
> ───
>
> 3. Claims the code does not do
>
> • install (“There is no moment when a complete key exists there unmarked”) is true of a first write to vault.key. It is not what default replaceItemAt is documented to do on overwrite, and it is not true of a .{uuid} leftover after a kill mid-stage.
> • WatchVaultModel (“refusing [a nonce-less decline] would leave a watch waiting forever”): the 25-second timer still runs.
> • WatchAnswerVocabularyTests.messageKeysArePinned is still named “exactly these three strings” and does not pin MessageKey.nonce. Renaming that wire key would compile, and every new-phone decline would look nonce-less to the watch, which is the item-4 regression.
> • SECURITY.md (“A request is now answerable for two minutes”) is wall-clock minutes, not elapsed minutes.
>
> ───
>
> Items 3, 5, 8, 9, 10, and 11 do what they claim. Item 4 does, for two new builds. The change that does not close the finding it cites is install: the staging file is marked, then replaceItemAt is asked to put it where a key already lives, without usingNewMetadataOnly.

---

---
