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
