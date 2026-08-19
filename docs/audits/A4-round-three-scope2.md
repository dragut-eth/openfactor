# A4 round three, scope 2: what changed and why

Round two reviewed the eleven fixes from round one and changed ten more things. **Those ten have
not been reviewed by anybody.** This is the "what changed" block the round three prompt in
`docs/audits/A4-prompts.md` calls for.

**The code under review is `71e88c3`.** Round two read `350375b`; round one read `74fe841`.

Check out the tip of `a4-fixes`, which is what the reviewing copy holds. It differs from `71e88c3`
only in this file, and only by the paragraph you are reading: a page that names its own commit
cannot be committed at the number it names.

Round two's returns are reproduced in full in `A4-round-two-scope2.md`, and round one's in
`A4-scope2-watch.md`. Both are worth reading before this: round two's three returns disagreed with
each other about whether the same construction was sound, and that disagreement is where the two
most useful changes came from.

## The ten changes

**1. The key is written inside a directory that is excluded before any key material exists.**
Round two found the previous fix insufficient twice over: `replaceItemAt` without
`.usingNewMetadataOnly` keeps the *destination's* metadata, so an existing weakly-protected key
survived the fix that was supposed to correct it; and a kill between writing the staging file and
marking it still left a raw unexcluded key at `.{uuid}`, because `defer` does not run after a kill.
`VaultKeyStore.install` now writes into a `PendingKeys` directory created and marked excluded
*before* anything goes in it, sweeps orphans left by a previous kill, and replaces with
`.usingNewMetadataOnly`.

**2. Reading the key repairs how it is stored.** ChatGPT filed this as the caveat at the end of
its item 1: the new options fix future writes, and nothing repairs a key already on disk. Every
change above governs the *next* write, and a Watch provisioned before these rules were corrected never writes
again, so it would never receive them. `VaultKeyStore.load` now sets the protection class and the
backup exclusion on the existing file. Metadata only: it never opens, rewrites, or replaces the
key.

**3. The consent window is measured on `ContinuousClock`.** All three engines found the `Date`
version fails open on a backward jump, since a negative elapsed time is inside any window forever.
`ValidatedRequest.validatedAt` is a `ContinuousClock.Instant` and is **internal**, so nothing
outside the package can compare a `Date` to it again. `age(now:)` is the only public reading, and
takes the instant so a test can choose it, which answers Fable's L1 about a parser that reads a
clock.

**4. The watch no longer re-asks from inside its response handler.** ChatGPT wrote out the
seven-step sequence: a delayed response arrives, the watch treats it as proof the phone's slot is
free, and abandons a request the phone has genuinely retained and is showing an alert for. The
inference is unsound across an asynchronous channel, whether or not it recurses. Fable and Grok
were separately invited to disbelieve the claim that it cannot spin; both walked the call order,
both correctly found no spin, and the spin was never the problem.

**5. The phone answers `.busy`.** Previously it answered `.asking` for a request it discarded,
which is what made the watch want to infer anything. This is the fix ChatGPT named: make the
phone's direct reply authoritative, so it never claims to be asking about a request it did not
keep. `.busy` is non-terminal: the watch keeps the attempt and keeps waiting, because the answer
may still be coming and the timeout recovers if it is not. It was rejected as over-engineering
when round one proposed it.

**6. `.busy` arriving after a timeout leaves the dead-end screen up.** Found by the test written
for change 5, not by a review. A timed-out attempt stays claimable on purpose, so a late key still
installs; that let a `.busy` answer put a spinner back up whose timer had already fired. The
guard is `stage == .waiting`.

**7. `phoneDeclined` gained the guard its sibling already had**, so a decline arriving with
nothing outstanding cannot demote a `.ready` watch. Tests from both sides.

**8. The backup exclusion is set on the staged file, not only on the directory.** Found by the
suite rather than a review, and it is the sharpest thing in this batch: `.usingNewMetadataOnly`
installs the *staged* file's metadata at the resting path, where there is no excluded directory to
sit inside, so change 1 silently stripped the exclusion off the key it wrote. The existing
"excluded from backups" test went red the first time both changes ran together.

**9. A decline whose nonce is present but unreadable is ignored rather than honoured.** `as? Data`
alone conflated *absent* with *present and of the wrong type*, so a decline carrying a nonce this
build could not read fell into the branch reserved for a phone too old to send one, and was
honoured. ChatGPT asked for the two cases to be separated.

**10. Expired consent declines instead of returning silently.** The window check returned, which
left the alert on screen and the request in memory: the owner taps Approve, nothing is sent, and
nothing says why. Expiry now takes the decline path, which clears the alert, clears the request,
and tells the watch, so it stops waiting at once rather than at its own timeout. ChatGPT asked for
the request and alert to be cleared on expiry.

Alongside these: `messageKeysArePinned` pins the fourth wire key, `SECURITY.md` no longer states
the nonce echo unconditionally or calls the window wall-clock minutes, a comment claiming a watch
would wait forever is corrected to what the timeout actually does, and `docs/VAULT.md`'s protocol
section documents the refusal message, which is a third message carrying no version magic and was
absent from the byte tables.

## What round two concluded

ChatGPT: one medium and three low, with a fix assessment item by item, and it was the only engine
to say of item 2 that it was "not fixed". Fable: nine of eleven complete, one gap, one new medium.
Grok: three of eleven incomplete, plus two documentation mismatches. All three returns are in
`A4-round-two-scope2.md`.

Fable's uncovered path is **narrowed rather than closed**, which is the honest description. Its
sequence still ends with a wearer waiting: a decline echoing attempt A's nonce is correctly
ignored by a watch holding attempt B, and B is never answered. What changed is that B gets `.busy`
rather than `.asking`, so nothing claims a person is being asked about it, and the timeout ends
the wait at a screen with a button. Whether that is sufficient is a fair question for this round.

## Where to look hardest

**The state machine has now been modified on three separate occasions, and every previous round
found that the last round's fixes had introduced defects of their own.** Changes 4, 5, 6 and 7 are
that machine. Change 5 adds a fifth answer to a wire protocol; change 6 is a guard added to it
within the same batch, which is not a reassuring sign about how well change 5 was understood when
it was written.

**The file-writing path has been rewritten three times for the same finding.** Change 1 is the
third attempt at "the key is never on disk unexcluded", and change 8 is a defect that attempt
introduced. Ask whether the current shape is right or merely the first one nobody has broken yet.

**Change 2 runs on every read.** It calls `setAttributes` and `setResourceValues` on the live key
file every time the key is loaded. It is claimed to be incapable of damaging the key. Test that
claim.

**Two of the ten changes came from the test suite rather than from a review**, which is either
evidence the suite is doing its job or evidence that changes 1 and 5 were not thought through
before they were written. Both readings are available and the second one is not being avoided.

**Changes 9 and 10 are in the app targets, where this project's test suite cannot reach**, so they
are argued for in comments and unproven by any test. That is the same condition that hid the two
races round one found in the watch's flow, and the reason `WatchProvisioningFlow` exists at all.
Whether these two belong in the core for the same reason is a fair question to put.

## Question four

Round three asks something the earlier rounds did not: **is this converging?** Scope 2 has had
twenty one changes across three sittings. Say plainly whether the defect surface is shrinking or
moving around. If the answer is that an area has been rewritten three times and is still wrong,
that is the most useful sentence you can write here, and it will not be argued with.
