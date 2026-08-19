# A4 round four, scope 2: what three engines found in the extraction

Round four read `ae90bcb`. All three engines returned.

**All eleven original findings are now accepted**, including the three that had been fixed and
unreviewed since round three. **And this is the first round of the gate to return no medium and no
high at all**: seven new items, every one low.

| Engine | Verdict |
| --- | --- |
| Fable 5 | "The extraction is faithful and the seam is nearly right." Two low, two missing tests |
| Grok 4.6 | One low. "I would not extract these two types again" |
| ChatGPT 5.6 Sol | Two low. "Genuine convergence, while demonstrating that 'everything left is plumbing' is still premature" |

## The fix that does not fire

**Two engines independently found that the consent timer never expires anything.**

`expireConsent` sleeps for exactly the window, 120 seconds, and asks the desk once. `age()`
truncates to whole seconds and `isAnswerable` accepts `elapsed <= 120`. So the timer wakes at
T+120.x, `age()` returns 120, the request is still answerable, `expire` returns `nil`, the one-shot
task ends, and **the alert stays up indefinitely**.

The desk test that proves the deadline takes the question down advances by 121 seconds. The
production timer asks at 120. As Grok put it: the early, wrong-nonce and already-answered no-ops are
tested and real; the successful deadline, as the app actually arms it, is not.

**This is the same shape as two fixes the gate has already rejected**, and it is worth naming as a
pattern rather than an incident. The mtime clamp passed a test that could not see the attack. The
creation check passed a test whose fake never changed. This timer passes a test that asks at a
moment the timer never asks at. Each time the test was written by whoever wrote the fix, and each
time it agreed with the fix rather than with the world.

Nothing is released by it: a tap after the window still refuses and sends the decline. What fails
is the automatic clearing that round three asked for and that this round's account claimed.

## The order the extraction reversed

**Two engines found the key being read before the request is validated.** `Conditions` is built
eagerly, so `keys.load()` runs before `received` checks the length and before it checks whether the
app is frontmost. A malformed forty-byte request reads the vault key before being rejected for its
length; a valid request arriving in the background reads it before being told `.needsApp`.

They disagree about what it costs. ChatGPT rates it low and says it **restores a previously fixed
behaviour** and falsifies three documents: the comment above the method, `docs/VAULT.md`, and
`SECURITY.md` all say the phone validates and foregrounds before it reads the key. Fable found the
same eager read and calls it a wasted read rather than a leak, since a protected file simply reads
as absent in the background.

Both note the same thing about the tests: `rubbishIsRefused` and `backgroundIsNeedsApp` pass
precomputed `Conditions`, so they cannot see when the app evaluated anything.

`approve()` has the same shape: it loads the key before asking the desk whether there is anything
to release.

## All three rejected the same claim

**"What stayed behind in the app is everything that is not a decision" is too strong**, and every
engine said so in its own words. What is still resident and still untestable:

- the condition that arms the expiry timer, `answer == .asking`, whose removal would leave every
  desk test passing and kill auto-clearing entirely
- the rule that sends a refusal even when the desk has nothing to name
- the policy that a phone which cannot read its key refuses rather than asks
- the first reply, which is parsed in `WatchVaultModel` with its own `status as? String` rather
  than through `WatchInbox.classify`, so one wire vocabulary now has two readers
- the whole asking cadence on the watch: `refreshAndAsk`, `keyOpensNothing`, and the
  `hasReplacedStaleKey` latch, which its own comment records as having been wrong once

Fable's summary is the accurate one: **the extraction moved the message-handling rules and left the
cadence rules.**

## What round four added

| # | Finding | Severity | Engines |
| --- | --- | --- | --- |
| S2-12 | the consent timer wakes at the window and finds the request still answerable, so nothing expires | low | Grok, ChatGPT |
| S2-13 | the key is read before the request is validated and before the frontmost check | low | ChatGPT, Fable |
| S2-14 | a current build can send a nonce-less decline, which the protocol says only old builds send | low | Fable |
| S2-15 | a phone that cannot read its key refuses in silence, while the expired path sends a bound refusal | low | all three |
| S2-16 | the first reply is parsed in the model rather than through `WatchInbox`, so one vocabulary has two readers | low | Grok |
| S2-17 | the seam claim is too strong: the timer's arming condition and the asking cadence are decisions still in the app | low | all three |
| S2-18 | two rules have no test: `classify`'s preference order, and the asked-answered-asked cycle | low | Fable, Grok |

**S2-14 is the sharpest of the seven.** `decline()` sends unconditionally, so when the desk has
nothing to name the message goes out with a status and no nonce. `docs/VAULT.md`'s byte table says
the nonce is present on a decline, and the watch's compatibility rule honours a nonce-less decline
**because it can only have come from a phone built before the field existed**. So a current phone
can emit exactly the unbound refusal the nonce was added to abolish, and the watch will believe it
against whatever attempt it holds. Fable's path to it is the expiry timer racing a tap on Not now.

**S2-15 is the same rule missing from three call sites**, which is why all three engines touched it
from different directions. Unifying them behind one refusal would close S2-14 as well.

## What survived, checked individually

Fable walked every fix from rounds one through three through the new code rather than trusting the
account, and all of them hold: the watchOS protection class and exclusion-before-content, `.busy`,
the no-replacement rule, the consent window with its backward-clock refusal, the CSPRNG catch, both
flow guards, the decline nonce matching, absent-versus-unreadable, and expiry-as-refusal.

**Two things are better than the account claimed.** Round three's split brain got the structural
cure rather than the one-line fix Fable proposed: attempt lifetime is derived from `flow.isAsking`,
so a sixth answer cannot separate the model from the flow again, and the two flow tests that
asserted a property the shipped watch did not have are now true of the app. And the substitution
test both round-one engines asked for finally exists, four rounds later, "because it finally
could."

## Convergence, and the stop rule

All three say yes, and Fable says it about the whole scope for the first time: this round's
findings are smaller, fewer, and in a different class than the last round's, and the two new types
are the same shape as `WatchProvisioningFlow` and `AppLockPresentation`, which are the two
structures in this project that stopped producing defects after they were built.

Grok: "I would not extract these two types again." ChatGPT: genuine convergence, and the plumbing
claim is premature.

**Against the stop rule proposed earlier, this round half-passes.** It returned nothing above low,
which is the first half. It also called a fix inert, which fails the second. Scope 2 needs one more
pass, and the residue all three describe is small enough to enumerate: unify the three refusal call
sites, make the timer actually expire, run the first reply through `WatchInbox`, decide whether the
asking cadence follows the messages into the core, and add the two one-line tests.

---

# What was done

**The code under review is `9304d6c`.** All seven are fixed.

**S2-12, the timer that expired nothing.** The window is compared as a duration rather than through
`age`'s whole seconds. The new test asks at the instant `Task.sleep(for: .seconds(120))` actually
wakes, which is the moment the old test avoided by asking a second later. Both sides of the
boundary are pinned to the millisecond.

**S2-13.** `Conditions.hasVault` is a closure. The desk asks it only after the request has parsed
and the app is known to be frontmost, and two tests record whether it was asked at all rather than
what it returned.

**S2-14 and S2-15, which were one rule missing from three call sites.** There is one `refuse`
method now. A refusal this phone cannot name is not sent, so the timer-versus-tap race can no
longer emit the unbound decline the watch honours as coming from an older build. And a phone that
cannot read its key refuses rather than going silent, which is what the expired path three lines
away already did.

**S2-16.** The direct reply goes through `WatchInbox.classify`, so the wire vocabulary has one
reader. Anything that is not an answer is treated as a refusal, by the same rule that governs an
answer this build cannot name.

**S2-17.** The claim is gone and the comment lists what actually stayed in the app targets: the
condition that arms the timer, and the watch's asking cadence. **Moving those was considered and
not done**, and the reason is stated rather than implied: neither produced a finding in this gate.

**S2-18.** Both rules pinned.

Each fix was reverted individually and its test confirmed red.

## For round five

This is the round where the scope can meet the gate's exit condition: nothing above low, and no fix
called incomplete. Four questions.

**The timer is the third attempt at the same deadline.** No window at all, then a window checked
only on a tap, then a timer that woke too early to fire. Ask whether the arithmetic is right at
every boundary rather than at the two this batch tested.

**`hasVault` is now a closure held in a value type.** It is called at most once and only after two
guards. Check that it cannot be called twice, and that nothing captured in it outlives the request.

**One `refuse` method serves three callers.** That is the consolidation two rounds asked for, and
consolidation is how four entry points become wrong together.

**The watch's reply path changed reader.** A reply that is not an answer is now treated as a
refusal. Check that no phone this build can talk to sends something that lands there wrongly.
