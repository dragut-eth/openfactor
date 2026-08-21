# A4 round four, scope 2: the extraction

Round three closed with all three engines saying a version of the same thing, and one of them
saying it as the most useful sentence it could write: the defect surface in this scope is not
moving around at random, it is pooling exactly where the tests cannot go, and the next defect is
predictable to be in `WatchVaultModel` or `WatchKeyProvider` because that is where the last five
were.

**This round reviews the answer to that.** It is the only change since `71e88c3` other than round
three's own fixes.

**The code under review is the tip of `a4-fixes`.** Round three read `71e88c3`, round two
`350375b`, round one `74fe841`.

## What moved

**`ProvisioningDesk`, in the core, holds the phone's rules.** Which request is being asked about;
that the request on screen is never replaced by a later one; what a second request is told; whether
a tap still releases, refuses, or does nothing; what a refusal names; and whether a deadline that
fires belongs to the request still on the desk. Gate A4 found five defects in those rules, every
one by a person reading `WatchKeyProvider`, because nothing else could reach them.

**`WatchInbox`, in the core, holds the watch's reading of a message** and the rule for believing a
refusal. A decline's nonce has three states, absent, unreadable and present, with three different
answers, and merging any two of them has been a defect once already.

**What stayed in the app targets is everything that is not a decision**: the WatchConnectivity
session, the alert, the key file, the sending, the drawing, and the timer that wakes up to ask the
desk whether a deadline has passed. The two files are about two hundred lines smaller between
them.

Nineteen tests came with the two types. Each rule was reverted in turn to watch its own test fail:
the pending request overwritten again, the consent window removed, unreadable merged back into
absent.

## The four questions, and a fifth for this round

Rounds two and three asked three questions; round three added a fourth about convergence. This
round adds one more, because a refactor can be faithful and still be the wrong shape.

1. **Does the behaviour survive?** A refactor that changes what the code does while claiming only
   to move it is the failure this round exists to catch. The previous rounds' findings are the
   specification: every fix from rounds one, two and three should still hold, and any that
   silently did not survive the move is the most important thing you can report.

2. **Is the seam in the right place?** What stayed behind in the app targets is claimed to be
   free of decisions. Check that claim rather than accept it. A conditional, a comparison, or an
   ordering that still lives in `WatchVaultModel` or `WatchKeyProvider` and matters to
   correctness is a finding, and the argument that "it is only plumbing" is exactly what was said
   about the code that produced five defects.

3. **Do the new tests actually pin the rules?** Nineteen tests are claimed to cover rules that had
   none. A test that passes against a broken implementation is worse than no test, because it is
   also a claim. `ProvisioningDeskTests` and `WatchInboxTests` are the place to attack.

4. **Did the move introduce anything?** Two new public types in the core, both `Sendable`, one
   mutating value type held by a `@MainActor` observable object, and a timer that now asks a value
   type rather than reading its own state.

5. **Is this converging?** Same question as round three. Twenty five changes in this scope across
   four sittings, and this one is structural rather than a fix. Say plainly whether the structure
   is now right, or whether this is the fourth rewrite of the same area under a new name.

## Where to look hardest

**`ProvisioningDesk.approve` clears the desk before deciding what to return.** That is deliberate,
so a second tap on a lingering alert releases nothing, and it means a refusal and a release both
end the question. Check the case where the window has passed: the desk is cleared and a nonce is
returned to refuse with, and nothing else may happen afterwards.

**`expire` is asked by a timer that knows only a nonce.** The three ways a timer can be wrong are
firing early, firing for a request the desk no longer holds, and firing after the person already
answered. All three are claimed to do nothing.

**The watch's decline path now compares an empty `Data` when there is no nonce to compare.**
`answers(_:)` is length-checked and constant-time, so an empty value fails it, and the absent and
unreadable cases are decided before the comparison is reached. Verify that reasoning rather than
take it.

**Nothing in the two app files was covered by a test before this change, and nothing is now
either.** What changed is how little is left in them. If something important is still there, this
round is where it gets caught.

## Two files in this scope moved after the extraction, and neither came from this scope

Both are named here rather than left to be discovered, because a reviewer finding an unexplained
change has to work out whether it belongs to the round.

**`VaultKeyStore.load` gained a size check before it reads.** That came from a class sweep run
while closing scopes 3 and 4, which went through every whole-file read in the project looking for
the mistake those scopes kept producing: a bound applied after the allocation it claims to prevent.
This file was the last one and the least dangerous, since it reads a file this app writes into its
own container. Scope 1's round three filed a residual against it, that the check is skipped when
the file system gives no size and is separate from the read.

**`OpenFactorApp` gained an inbox sweep on activation, an arrival queue, and a wrapped-key
reconcile at launch.** All three are scope 4 and scope 1 work landing in a file this scope also
reads, because it is where the watch provider is wired. The provisioning alert, the routing, and
`PrivacyShield.apply` are untouched. If any of that has disturbed the ordering this scope depends
on, that is a finding worth more than anything else in this round.
