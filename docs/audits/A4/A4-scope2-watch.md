# A4, scope 2: the Watch key exchange

Gate A4 round one, the scope covering handing the vault key from an iPhone to a paired Apple
Watch. The prompt is `docs/audits/A4/A4-prompts.md`, preamble plus Scope 2, unchanged.

**Commit under review: `74fe841`**, the same commit scope 1 read. No code has changed since.

**One edit is made to every pass published here.** Absolute paths from the reviewing machine are
rewritten as repository-relative. Nothing else is trimmed, softened, or reordered.

**This scope is not cold for ChatGPT.** It reviewed this exchange once already, on 2026-08-18,
against an earlier commit, and its four findings from that pass were fixed before this one ran.
Recorded here rather than hidden, because it changes what its result means: this is closer to an
early second look than to a first.

| Engine | Status |
| --- | --- |
| ChatGPT 5.6 Sol | Returned, below. Triaged. Not cold, see above |
| Fable 5 | Returned, below. Triaged |
| Grok 4.6 | Returned, below. Triaged |

---

## ChatGPT 5.6 Sol

*Read-only pass over commit `74fe841`. Reproduced as returned.*

> ### 1. Medium — watchOS does not apply the promised `.complete` protection to the vault key
>
> `Sources/OpenFactorCore/Vault/VaultKeyStore.swift:98` (`install`) enters its protected-platform
> branch on watchOS, but writes using `Sources/OpenFactorCore/Inbox/SharedInbox.swift:113`
> (`writingOptions`). That property enables `.completeFileProtection` only under `os(iOS)`;
> watchOS takes the `else` branch and receives only `.atomic`.
>
> The concrete call path is: `WatchVaultModel.phoneSent` authenticates and opens the 60-byte
> sealed response, calls `VaultKeyStore.install`, and on watchOS the raw 32-byte vault key is
> written without requesting `.completeFileProtection`.
>
> Consequently the code does not establish the documented claim in `docs/VAULT.md:102-105` that
> the key is unavailable while locked and "on watchOS it follows wrist-lock." Its actual
> protection depends on filesystem defaults or inheritance. I have not measured that inherited
> class on watchOS, so I cannot claim every resulting file is readable after wrist-lock; the
> explicit `.complete` guarantee is nevertheless absent. If the inherited class remains available
> after first unlock, filesystem extraction of a locked, previously unlocked Watch yields the
> vault key and therefore every synchronized account secret.
>
> Smallest fix: give `VaultKeyStore` its own platform-correct options and use
> `[.atomic, .completeFileProtection]` for `os(iOS) || os(watchOS) || os(tvOS)`, rather than
> reusing an iOS-share-inbox helper.
>
> Missing test: a watchOS test or device probe that reads back the installed key file's protection
> class and requires `NSFileProtectionComplete`. The macOS-only `VaultKeyStoreTests` explicitly
> cannot catch this regression.
>
> ### 2. Low — the phone acknowledges a retry that it does not retain
>
> In `OpenFactor/Vault/WatchKeyProvider.swift:99` (`answer`), a second request received while
> `pendingRequest` is occupied returns `.asking` but leaves the first request pending.
>
> Concrete failure:
>
> 1. Watch attempt A reaches the phone; the phone stores A and raises the approval alert.
> 2. A times out after 25 seconds.
> 3. The watch begins attempt B.
> 4. The phone still holds A, so it answers B with `.asking` but does not store B.
> 5. The owner taps approval. The phone seals to A.
> 6. B rejects that response as `.notForThisRequest` and correctly preserves its current attempt.
> 7. No response for B can ever arrive because the phone discarded B; it times out again.
>
> This is particularly reachable because returning to the watch automatically retries after the
> timeout. The existing "obsolete response leaves the waiting attempt alone" test assumes a
> genuine response for B subsequently arrives, but the phone-side implementation makes that
> impossible in this sequence.
>
> Smallest fix: retain enough request identity to distinguish a duplicate from a distinct retry.
> Return `.asking` only for the request actually pending; return a terminal busy/declined answer
> for a different request, or queue it explicitly.
>
> Missing negative test: `pending A → receive distinct B → approve → verify B was either retained
> or received a terminal answer`, using an extracted/testable phone-side state machine.
>
> ### 3. Low — a delayed decline is not bound to the request it declines
>
> `OpenFactor/Vault/WatchKeyProvider.swift:75` (`decline`) sends only the string `"declined"`.
> `OpenFactorWatch Watch App/WatchVaultModel.swift:223` (`phoneSent`) accepts that status without
> a version, nonce, attempt, or current-state check, and `WatchProvisioningFlow.phoneDeclined`
> unconditionally clears the outstanding attempt.
>
> Concrete failure:
>
> 1. A times out on the Watch.
> 2. The owner declines A on the phone; that standalone message is in flight.
> 3. Before it arrives, the Watch starts B, which the phone can retain as the new pending request.
> 4. The delayed decline for A reaches the Watch and clears B's private attempt and token.
> 5. Approval of B then sends a valid sealed response, but the Watch has no attempt with which to
>    open it and silently drops it.
>
> Smallest fix: make the second-message decline carry the protocol version and echoed request
> nonce. The Watch must compare it with the current `Attempt` before changing state, treating an
> older nonce exactly like an obsolete encrypted response.
>
> Missing negative test: `begin A → begin B → receive decline carrying A's nonce → assert B
> remains current`.
>
> ### What held up
>
> I found no cryptographic or byte-parsing defect:
>
> * Both messages enforce their exact lengths before any slicing.
> * The nonce is checked before the phone public key is parsed or ECDH is performed.
> * CryptoKit validates both P-256 points.
> * The fixed-width transcript binds the version, request nonce, and both public keys in both HKDF
>   info and AES-GCM AAD.
> * A repeated GCM nonce alone would not repeat under the same KEK because production responses
>   also generate a fresh ephemeral phone keypair, changing the transcript and derived key.
> * The 60-byte sealed field fixes the authenticated plaintext at 32 bytes before installation.
> * Approval is not automatic: the only production call to `approve()` is the affirmative alert
>   button, the pending validated request is not replaceable, and the alert binding is false while
>   App Lock is locked.

### Triage

**All three confirmed. Two of them are defects introduced or left behind by the fixes made to this
exact file the previous day**, which is worth stating plainly rather than filing as ordinary
findings.

**Finding 1 confirmed, and this is its fourth independent confirmation.** ChatGPT and Grok both
reported it in scope 1, and it appears here again from a different direction, following the call
path from `phoneSent` into `install` rather than reading `VaultKeyStore` directly. The addition
worth keeping is the test observation: `VaultKeyStoreTests` runs on macOS, where data protection
does not exist, so no test in this repository can catch this regression and none ever could have.
That is a fact about the test rig of the kind this project has learned to write down.

**Finding 2 confirmed, and the cause is a fix made on 2026-08-18.** The line
`guard pendingRequest == nil else { return .asking }` was added that day to close a request
substitution defect: a second request used to replace the one the owner's alert was asking about.
The fix is correct about not replacing, and wrong about what to tell the watch. It answers
`.asking`, which means "you are being asked, wait", while the phone quietly discards the request.
The comment written above it, that "the watch's own retry supersedes it from the other side", is
simply false: nothing on the phone side ever adopts B.

The result is a watch that waits for a message that cannot arrive, and it is reachable by the
ordinary path, because the watch retries automatically when the wearer raises their wrist after a
timeout.

**Finding 3 confirmed, and it is a gap in the flow type written the same day.**
`WatchProvisioningFlow` protects the callbacks with a generation token and protects the encrypted
response by treating a nonce mismatch as obsolete rather than as failure. The decline has neither.
It carries no nonce, so nothing can tell a decline of the current attempt from a decline of an
abandoned one, and `phoneDeclined()` takes no token, so it clears whatever is outstanding.

**Every message in this protocol is bound to its attempt except the one that says no.** That is the
sentence the design was missing.

### What this says about the fixes of 2026-08-18

Three of the four defects fixed that day were races in which a stale message disturbed a current
attempt. The fixes addressed the paths that existed. Findings 2 and 3 are the same class on the
two paths that were not examined: the phone's answer to a request it declines to hold, and the
decline message itself.

Round two exists to catch fixes that introduce new problems. This one was caught in round one of a
different scope, by an engine that had reviewed the earlier version, which is an argument for the
scopes overlapping rather than partitioning cleanly.

---

## Fable 5

*Read-only pass over commit `74fe841`. Reproduced as returned, abridged where it repeats a finding
already recorded above.*

> **An honesty note before the findings: this scope cannot be read cold by anyone any more.** The
> code's own comments narrate the previous review's findings in detail ("a second request used to
> replace it silently…", "the result of `SecRandomCopyBytes` used to be discarded…"), which anchors
> any reviewer toward the already-found defect classes. I have tried to attack the current code
> rather than re-verify the narrated fixes, but the anchoring is real and worth recording alongside
> the ChatGPT asymmetry the prompts file already notes.
>
> Summary: no defect in the cryptography and no path by which a key is sealed to an unapproved
> public key or installed from an unverified message. Two small state-machine defects, both
> liveness and neither key-releasing; one flow-contract weakness; two documentation inaccuracies;
> and a test gap that would let a meaningful cryptographic regression ship silently.
>
> **F1 — Low. The phone promises "asking" to a request it will never answer, and the approval tap
> is silently wasted.** [Same defect as the ChatGPT pass's finding 2, reached independently.] The
> non-replacement of `pendingRequest` is correct and must stay: replacing it is the substitution
> defect the previous review found. The defect is only that "asking" is answered for a request the
> phone has already decided to discard, so one human approval produces nothing and the alert comes
> back.
>
> Smallest fix, and it differs from the obvious one: on the watch, when a response is obsolete,
> re-ask immediately instead of continuing to wait. An obsolete response is positive evidence that
> the phone has just finished answering an older request, so its `pendingRequest` slot is now free
> and a fresh request will raise the alert at once instead of after a wasted timeout.
>
> **F2 — Low. The CSPRNG-failure path abandons an attempt without clearing it, and the comment
> above the property then makes a false claim.** `WatchVaultModel.swift:120-124`. The doc comment
> on `attempt` states that "a send error, a refusal and an unreadable reply all clear it". The
> `catch` in `ask()` synthesizes a send failure but clears neither `self.attempt` nor `self.token`.
>
> Reachable: attempt A times out and is deliberately kept; the wearer taps Try again;
> `Attempt()` throws `.noRandomness`; the flow is told a fresh attempt began and instantly failed,
> so `outstanding` is nil, while stale attempt A is still stored. A very late response to A then
> arrives, `phoneSent` finds `attempt` non-nil, the nonce matches, and the key installs with no
> outstanding attempt anywhere in the flow. This is exactly the shape question 3 names, "can the
> watch install a key from an attempt it abandoned", and the answer is yes in this one corner. The
> security consequence is nil: the response was human-approved and sealed to this watch's own
> ephemeral key. It breaks the invariant the comment claims.
>
> **F3 — Low. `responseDidNotOpen(obsolete: false)` can demote any stage, including `.ready`, with
> nothing outstanding.** `WatchProvisioningFlow.swift:158-162`. Every other transition in this type
> is guarded by a token or by `outstanding`; this one is guarded only by the `obsolete` flag. I
> traced whether the model can reach it today and concluded it cannot. So this is a weakness in the
> tested contract rather than a reachable defect, but the flow type exists precisely to be the
> place where these guarantees are tested, and this method is the one that does not carry its own
> guard.
>
> **F4 — Informational. `pendingRequest` has no expiry, and the alert's sentence can become
> untrue.** A request arriving while App Lock is up is accepted and answered "asking", and the
> alert is suppressed until unlock with nothing bounding how much later that is. Hours later the
> person is shown "Your Apple Watch is asking for the key to your accounts" when it stopped asking
> long ago. The human gate is the one defense the design kept, and a consent prompt whose premise
> has expired is a slightly weaker gate than the design describes.
>
> **F5 — Informational, documentation.** `VAULT.md:357` says "The watch's private key may live in
> the Secure Enclave rather than the container." The implementation is
> `P256.KeyAgreement.PrivateKey()`, CryptoKit's software key, in process memory. Nothing uses
> `SecureEnclave.P256`. Either delete the sentence or mark it explicitly as a possible future
> change. One nit below reporting threshold on its own: a malformed request is answered
> `.declined` while `Answer.declined` is documented as "The person said no." Nobody was asked.
>
> **What I attacked and found sound.** All four transcript fields are fixed length and
> concatenated in send order, so no two field boundaries can be reinterpreted; the GCM nonce is
> not in the transcript but is bound anyway, because the tag depends on it. The nonce is checked
> before the public key is parsed, and `nonceIsCheckedBeforeParsingTheKey` actually observes the
> ordering by making the message wrong in both ways at once. GCM nonce reuse under one kek is
> impossible in production because every `respond` generates a fresh phone key, so the kek is
> single-use by construction. P-256 has cofactor 1, so there is no small-subgroup point to send.
> `approve()` has exactly one call site, the alert's affirmative button, and the binding's setter
> is deliberately a no-op so dismissal cannot resolve the question either way. A misdelivered
> response is inert bytes, since the sealed payload opens only with the requesting attempt's
> in-memory private key.
>
> **Missing negative tests, most valuable first.**
>
> 1. **Two responses to the same request must differ.** This is the sharpest gap: a regression
>    that gave the phone a static ECDH keypair would pass the entire current suite.
>    `exchangesAreFresh` varies the requests, so the responses still differ. A static phone key
>    converts a captured response plus a later phone compromise into vault-key recovery, which the
>    ephemeral design exists to prevent.
> 2. **An attempt survives a failed open.** The whole "a slow answer is still a good answer" design
>    rests on `Attempt` being reusable after an obsolete response, and nothing pins it.
> 3. **Late callbacks cannot demote `.ready`.**
> 4. **`responseDidNotOpen(obsolete: false)` with nothing outstanding.**
> 5. **The phone's decision-making has no tests at all.** `WatchKeyProvider.answer`'s state machine
>    is asserted only in comments, because it lives in the app target. This is precisely the
>    situation that got `WatchProvisioningFlow` and `AppLockPresentation` extracted into the core.
>    Until then the "never overwritten while it is set" invariant, the one standing between a
>    routing-exclusivity failure and key exfiltration by `SECURITY.md`'s own analysis, is protected
>    by nothing that runs.

### Triage of the Fable 5 pass

**F1 confirmed**, independently reaching the same defect as the ChatGPT pass. Its proposed fix is
better than the obvious one and is the one to take: rather than making the phone queue or refuse,
have the watch re-ask on an obsolete response. An obsolete response is positive evidence that the
phone has just answered something else and its slot is now free, which turns a wasted 25-second
timeout into an immediate retry.

**F2 confirmed.** The `catch` at `WatchVaultModel.swift:121` calls
`flow.sendFailed(flow.beganAsking())` and clears neither `self.attempt` nor `self.token`, three
lines above a `sendFailed(_:)` helper that does exactly that. Written the same day as the comment
it contradicts.

**F3 confirmed as a contract gap.** `responseDidNotOpen` has no `outstanding` guard while every
sibling transition does. Fable's own conclusion that it is unreachable today matches: the failure
path requires a stored attempt. Accepted as written, including the honest reachability analysis.

**F4 accepted as informational and worth acting on.** A request accepted while App Lock is up can
raise its alert arbitrarily later, so the human gate can be asked about a question that expired
hours ago. The gate is the one defense this design kept after the authentication string was
removed, which makes a stale gate more than cosmetic.

**F5 confirmed.** `docs/VAULT.md:357` still says the watch's private key may live in the Secure
Enclave; the code has always used CryptoKit's software key. That paragraph was rewritten on
2026-08-18 and the stale sentence was carried through rather than caught. The `.declined` nit is
also real: a malformed request is answered with a value documented as meaning a person said no.

**The test gap is confirmed empirically, not by reading.** The phone's ephemeral key was replaced
with a single static keypair and the full suite was run: **358 tests, all passing.** Fable's claim
is exactly right, and this is the most valuable item in the pass, because it is not a defect in
shipped code but a hole in the net that would let a serious one ship in silence.

`exchangesAreFresh` is the test that should have caught it, and its name claims more than it
observes: it varies the request each time, so the responses differ regardless of whether the
phone's key is fresh. That is the fourth test in this project found to be checking less than its
name promised, after the App Lock ordering test, the SharedInbox protection assertion, and the
watch nonce-ordering test this same suite fixed yesterday.

### The anchoring problem, which is about the method rather than the code

Fable opened by recording that this scope can no longer be read cold by anybody, because the code
comments narrate the previous review's findings in detail. That is correct and it is a direct cost
of a practice this project otherwise benefits from: comments here explain what went wrong before
and why the current shape exists.

The effect is real in both directions. It anchors a reviewer toward the classes of defect already
found, and it hands them the previous reviewer's conclusions rather than making them derive their
own. Both ChatGPT and Fable found F1, which sits directly beneath a comment describing the fix
that created it, and neither found anything in the cryptography, which carries the same density of
explanation.

No change is proposed. The comments are worth more to a maintainer than cold-review purity is
worth to a gate that runs a handful of times. But it belongs in the record, because a future
reader comparing scope 1's yield against scope 2's should know that the two scopes were not
equally readable.

---

## Grok 4.6

*Read-only pass over commit `74fe841`. Reproduced as returned, abridged where it repeats findings
already recorded above.*

> **Medium — the watch installs the vault key without requesting `.complete` protection.**
> [Same defect as both passes above, reached by following `phoneSent` into `install`.] The
> provisioned key is written with `[.atomic]` only. The comment immediately above the call, and
> `docs/VAULT.md:102-106`, both say the opposite, including that
> `.completeUntilFirstUserAuthentication` "is a materially weaker and different promise and is not
> what this means."
>
> The phone path is not this bug. I did not read the protection class back on a watch. There is no
> `NSFileProtection*` key in the watch target, so the usual default is complete-until-first-unlock,
> which stays readable after first unlock while the watch is locked. I am not claiming a
> demonstrated extraction.
>
> Related, same function, weaker: `install` writes the 32 bytes first and only then sets
> `isExcludedFromBackup`. A kill between those two leaves a usable key that a later `load` will
> accept, so nothing retries the exclusion. On the watch it is how a restored watch could come back
> already provisioned.
>
> **On the cryptography.** The transcript binding is complete; the only response field not in the
> transcript is `sealed`, and that is GCM with the transcript as AAD. The nonce is compared before
> the public key is parsed and before HKDF, and the two-fault test returns `.notForThisRequest`,
> which is only possible if the nonce check runs first. A response from one exchange cannot be
> replayed into another. HKDF info is label plus a fixed-width transcript, and neither side parses
> info, so an attacker cannot choose a different split. GCM nonces cannot repeat under one derived
> key in production, since each `respond` creates a new private key. P-256 has cofactor 1. I did
> not find a cryptographic break.
>
> **On parsing.** Both directions require exact length before any slice, magic is checked before
> the layout is trusted, and a 65-byte field of zeros becomes `.invalidPublicKey` rather than a
> trap. A request that is not `Data` never reaches the parser. I did not find a crash or a slice
> that can run off the buffer.
>
> **On the state machine.** The phone does not seal to a request that arrived after the alert was
> shown; `approve` copies the stored request before the `defer` clears it, and the type is
> `@MainActor`, so a later answer cannot arrive in between. `approve()` has one call site, the
> affirmative button. The alert binding's setter is a no-op, so SwiftUI clearing `isPresented`
> cannot approve. `watchAsking` is false while App Lock is up. Queued WatchConnectivity modes have
> no handlers at all, so a key cannot be installed from a persisted queue.
>
> Two things that are not key theft but are real: the first-message status is a bare string with no
> nonce, so a retry while the phone still holds the first request is told `.asking` about a request
> the phone is not actually asking about, and `pendingRequest` has no lifetime short of process
> death. And `phoneDeclined()` takes no token while every other watch callback is token-gated, so
> it is the one second-message path that cannot tell a stale decline from a current one.
>
> **Tests that would catch a real regression.**
>
> 1. `WatchKeyProvider`: a second valid request must not change what `approve` seals to. This is
>    the substitution bug that already shipped once. It has no test. `SECURITY.md` says the four
>    review fixes are "all now tested"; this one is not. The type lives in the app target, which is
>    why. Pulling the pending-request rule into a core value type, the way the watch flow was
>    pulled out, is the same fix they already made once.
> 2. `answer` must never produce a 145-byte payload. Only `approve` may call `respond`.
> 3. `applicationState != .active` must not set `pendingRequest`.
> 4. **The HKDF label is domain separation and is untested.** `wrappingKey` with the same ECDH
>    secret and transcript but a different label must yield a different key. Today both sides share
>    one function; deleting `label +` would still pass every existing test.
> 5. Decide whether a stale decline may kill a newer attempt, then test that.
> 6. Two `respond` calls on the same `ValidatedRequest` must produce different responses, and both
>    must open.
>
> The exchange itself is doing what it claims. The defect is on the far side of a successful open:
> the watch writes the delivered key without the protection class the design says that write uses.

### Triage of the Grok 4.6 pass

**The protection-class finding is confirmed for the third time in this scope and the fifth overall.**
No engine has missed it once it had `SharedInbox` in reach.

**The two state-machine observations match findings already recorded**, reached independently: the
phone answering `.asking` to a request it discards, and `phoneDeclined()` being the one untokened
path. Grok adds the sentence that names the shape best: it is the one second-message path that
cannot tell a stale decline from a current one.

**Test gap 4 is confirmed empirically, exactly as gap 1 was in the Fable pass.** The
domain-separation label was deleted from the HKDF info and the full suite was run: **358 tests,
all passing.** So the label that separates this exchange's key derivation from every other use of
the same shared secret is protected by nothing. Both sides build the info from one function, so
its removal is symmetric and invisible to every round-trip test in the suite.

**That is the second hole of this kind found in one scope**, after the static ephemeral key. Both
share a cause worth naming: the suite tests the two sides against each other, and any change made
symmetrically to both sides passes. A round trip cannot detect a weakened construction, only a
disagreement.

**Test gap 1 contains a claim about this repository's own documentation, and it is correct.**
`SECURITY.md:43` says the four defects from the earlier watch review were "all fixed and all now
tested". No test in this repository references `WatchKeyProvider` at all, and the `.noRandomness`
path is not tested either. **Two of those four fixes have no test**, and the sentence claiming
otherwise was written the same day the fixes were.

That is a false claim in the security document, about the review process the document describes,
found by a reviewer reading the document against the code. It is the strongest single argument in
this gate for the basis labels added in PR 17, and for the rule that a claim carrying **tested**
must mean a machine fails when it stops being true.

## Scope 2 complete

| Finding | ChatGPT | Fable 5 | Grok 4.6 |
| --- | --- | --- | --- |
| watchOS protection class | Found | Found | Found |
| Phone answers "asking" to a request it drops | Found | Found | Found |
| Decline is not bound to its attempt | Found | Missed | Found |
| Install writes before excluding from backup | Found, scope 1 | Missed | Found |
| CSPRNG catch leaves a stale attempt | Missed | Found | Missed |
| `responseDidNotOpen` has no outstanding guard | Missed | Found | Missed |
| Consent can be arbitrarily stale | Missed | Found | Found |
| Secure Enclave sentence is untrue | Missed | Found | Missed |
| Static phone key would pass the suite | Missed | Found | Found, as gap 6 |
| Removing the HKDF label would pass the suite | Missed | Missed | Found |
| `SECURITY.md` "all now tested" is false | Missed | Missed | Found |

**Three findings were reported by all three engines**, unlike scope 1 where none were. The most
valuable items were still single-engine: the two verified holes in the test suite came from one
engine each, and neither would have been found by running any single engine alone.

**No engine found a cryptographic defect**, and all three said so with specific mechanisms rather
than assurances. That is the strongest statement available about this exchange so far, and it is
worth exactly what three code reviews are worth: nothing about behaviour on hardware, and nothing
about the routing assumption the design rests on.

### Not yet acted on

**Nothing has been changed.** Scopes 3 and 4 run against the same commit. Fixes begin when round
one is complete, and findings 2 and 3 join the ordered list in
`docs/audits/A4/A4-scope1-vault.md`, which they belong beside: they are the same family as the twin
record and the creation race, all of them a message or a tap arriving against state that has moved
on.
