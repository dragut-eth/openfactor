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

**Two engines returned, not three.** ChatGPT 5.6 Sol was not run on this round. An earlier version
of this page said "all three" against one finding and named ChatGPT against another; both were
wrong and are corrected below. The engine column here is taken from the two returns reproduced at
the end of this file, not from memory.

**Commit reviewed: `350375b`.** Round one read `74fe841`.

| Engine | Status |
| --- | --- |
| Fable 5 | Returned, below. Nine of eleven complete, one gap, one new medium |
| Grok 4.6 | Returned, below. Three of eleven incomplete, plus two doc mismatches |
| ChatGPT 5.6 Sol | Not run this round |

## What the two engines found

| Finding | Engine | What it took |
| --- | --- | --- |
| Consent expiry measured on a wall clock | **both** | `ContinuousClock`. `validatedAt` is internal now, so nothing outside the package can compare a `Date` to it again |
| `replaceItemAt` without `.usingNewMetadataOnly` keeps the *old* file's protection class, so an existing weak key survives the fix | Grok | The option, plus the repair below |
| A kill still leaves a raw unexcluded key at `.{uuid}`, because `defer` does not run after a kill | Grok | The key is written inside a directory excluded *before* any key material exists, and orphans are swept |
| `phoneDeclined` never got the guard its sibling got | Grok | The same `guard outstanding != nil`, with a test from both sides |
| `messageKeysArePinned` said "exactly these three" against four | Grok | The fourth pinned. Renaming `nonce` compiled everywhere, and every decline from a newer phone would have looked nonce-less |
| `SECURITY.md` stated the nonce echo unconditionally; the code echoes it only when something is pending | both | The sentence now says what the code does |
| `SECURITY.md` said "two minutes" of wall-clock minutes | Grok | Says elapsed, measured on a clock that cannot be moved |
| `validate()` became a parser that reads a clock | Fable | `age(now:)` takes the instant, so a test chooses it and the parser's contract stays checkable |
| The refusal message is a third message, unversioned, and absent from the protocol tables | Fable | `docs/VAULT.md` now documents the `status`/`nonce` dictionary and the asymmetric compatibility rule |

**Both engines cleared the re-ask, and it was removed anyway.** Round one had suggested fixing the
dropped retry on the watch, by asking again the moment an obsolete response arrives. Round two was
invited to disbelieve the claim that this cannot spin. Fable walked the call order and found two
independent brakes; Grok did the same and said "one extra alert, not a spin". Neither asked for
the removal.

It was removed on this repository's own reading, which the returns should be weighed against: the
re-ask infers that the phone's slot is free from the fact that a response was obsolete, and across
an asynchronous channel that inference is not sound. A response merely delayed proves nothing
about what the phone holds *now*, and if the phone has since retained a newer request, the re-ask
abandons the very request its alert is showing. **Two reviewers looked for a spin, found none, and
were right; the objection is to the inference rather than to recursion.** The phone answering
`.busy` instead of lying with `.asking` is what removed the need to infer anything.

**Fable's uncovered path is narrowed rather than closed, and that is the honest description.** Its
sequence still ends with a wearer waiting: a decline echoing attempt A's nonce is correctly
ignored by a watch holding attempt B, and B is never answered. What changed is that B now gets
`.busy` rather than `.asking`, so nothing claims a person is being asked about it, and the twenty
five second timeout ends the wait at a screen with a button on it. The dead end is bounded, not
removed.

## What the reviews did not find

Two of the eight fixes came from writing the tests. `.usingNewMetadataOnly` installs the *staged*
file's metadata, so the fix for the write window stripped the backup exclusion off the key it
wrote, and the suite went red the first time both changes ran together. And a `.busy` answer
arriving after a timeout restored a spinner whose timer had already fired.

**The item neither engine raised is the one that matters most on the maintainer's own wrist.**
Every fix above governs the *next* write, and a Watch provisioned a month ago never writes again.
Grok came closest, noting that a watch holding an old key "can be re-provisioned" to fix it, which
is a repair that requires somebody to know they need it. Reading the key now repairs its protection
class and backup exclusion in place: metadata only, so it cannot damage the key it is repairing.

Each of the eight fixes was reverted individually and the suite confirmed red for it. That check
found nothing wrong with the fixes and one thing wrong with a new test, which had been re-reading a
cached `URL` snapshot instead of the file.

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
