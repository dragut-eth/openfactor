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

## What round two changed

Round two reviewed the eleven scope 2 fixes. It found **four of them incomplete and two new
defects introduced by the fixes themselves**, which is the result the round exists to produce: the
first pass at a fix is a hypothesis, and this is the first time this project has tested one.

| Round-two finding | Engines | What it took |
| --- | --- | --- |
| Staging file merely moved the unexcluded key | ChatGPT | An excluded *directory*, created and marked before any key material exists, plus an orphan sweep |
| The watch re-asked from inside a response handler | Fable, Grok | The inference deleted. It was invalid: a delayed response does not prove the phone's slot is free |
| Consent expiry measured on a wall clock | all three | `ContinuousClock`, and `validatedAt` made internal so nothing outside can compare a `Date` again |
| `phoneDeclined` missed the guard its sibling got | Fable | The same `guard outstanding != nil` |
| `messageKeysArePinned` said "these three" against four | Grok | The fourth pinned. Renaming `nonce` compiled everywhere and every decline would have looked nonce-less |
| A comment claimed a watch would wait forever | Fable | Corrected. The twenty five second timeout recovers, so the real reason is smaller |

Two more came out of writing the tests rather than from any review. `.usingNewMetadataOnly` takes
the staged file's metadata, so the fix for the write window silently removed the backup exclusion
from the key it installed, and the suite went red the first time both ran together. And `.busy`,
arriving after a timeout, put a spinner back up whose timer had already fired.

**The item no review raised, and the one that matters most on the maintainer's own wrist:** every
fix above governs the next write, and a Watch provisioned a month ago never writes again. Reading
the key now repairs its protection class and backup exclusion in place. The device least likely to
be fixed was the one already working.

Each of the six fixes was reverted individually and the suite confirmed red for each before being
restored. That check found nothing wrong with the fixes and one thing wrong with a test, which had
been re-reading a cached `URL` snapshot rather than the file.
