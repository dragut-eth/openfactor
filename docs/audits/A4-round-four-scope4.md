# A4 round four, scope 4: the boundaries, and a reversal

**The code under review is `1bf4b26`.** Round three read `83e5cdd`, round two `43103dc`'s
descendant, round one `74fe841`. Every prior round's results are in `docs/audits/`, including the
full text of all three returns.

**Files:** `OpenFactorShare/ShareViewController.swift` and `OpenFactorShare.entitlements`;
`Sources/OpenFactorCore/Inbox/SharedInbox.swift`;
`Sources/OpenFactorCore/Import/BoundedFile.swift`; `OpenFactor/Import/InboxOpener.swift`;
`OpenFactor/Lock/` (all four); `OpenFactor/CodeClipboard.swift`;
`OpenFactor/Design/ScreenCapture.swift`; `OpenFactor/OpenFactorApp.swift`, where the lock, the
cover, the arrival and the capture flag are wired together; `OpenFactor/AccountListView.swift` and
`OpenFactor/Scanning/AddAccountSession.swift`; the matching tests; and `docs/APP_LOCK.md`, which
is the normative design for the lock.

Read-only. Do not build and do not run the test suite; keep the checkout clean.

## Two things about how this round is scored, both new

**A finding that lives only in a comment or a document is recorded but does not hold this scope
open.** That is a change made after scope 2 ran four rounds finding no code defect at all while
its comment corrections generated the next round's findings at close to one for one. Report false
claims in comments if you find them, and expect them to be fixed. Do not treat hunting them as the
job.

**This scope contains a change that deliberately reverses two findings this gate previously
accepted.** It is described below and it is the thing most worth your attention. Attacking it is
explicitly in scope and will not be treated as relitigating a settled question.

## The reversal: the arrival rule is last wins

Earlier rounds filed findings against dropping a queued share. Those findings were accepted and
fixed with an `ArrivalQueue` that promoted pending arrivals in order. **The queue has since been
deleted** and the rule is now that the most recent arrival takes precedence and the rest are swept.

The reasoning was the maintainer's own: a person who shares a second QR code while the first is
still on screen means the second one. **The queue was also measured on hardware before it was
removed, four runs of four, and it promoted correctly every time.** So this is not a fix that
failed. It is a working mechanism removed because the behaviour it implemented was judged wrong.

Say whether you agree. If last wins is correct, say what it costs: what a person loses, and
whether anything is deleted that they would expect to still be there. **If a queued arrival can
now be destroyed in a way the person cannot recover from, that is the finding this round is for.**

## The class sweep: `BoundedFile`

One primitive replaced four different file-reading bound shapes. It opens with
`O_RDONLY | O_NONBLOCK | O_NOFOLLOW`, `fstat`s, refuses anything that is not a regular file, and
reads `limit + 1` bytes so that hitting the limit is detectable rather than silently truncating.
Its four callers are `ImportViewModel.read`, `ShareViewController.firstImage`, `SharedInbox.take`,
and `VaultKeyStore.load`. It closed five findings at once, including a main-actor hang on a named
pipe a sibling process could plant.

**Attack the primitive rather than its callers.** A single shared read path is a single point of
failure: if the bound, the symlink refusal, the file-kind check, or the off-by-one on `limit + 1`
is wrong, it is wrong in four places at once. Then check that each caller passes a limit that
makes sense for what it reads.

## The inbox

`SharedInbox` changed in several ways: a future mtime clamps to `distantPast`, staleness is
measured against a single freshness constant, the sweep removes files whose names it does not
recognise, and a failure to exclude the staging directory from backup is now an error rather than
ignored.

## Three findings are open and unfixed

Listed so the round is not spent rediscovering them:

- **S4-24**, `now` is captured before the file attributes are read, so a share arriving mid-sweep
  can be deleted.
- **S4-25**, the unknown-name sweep can delete a file that an atomic write is still in the middle
  of producing.
- **S4-26**, the deferred sweep after collection deletes what arrived after its snapshot was taken.

All three are races between the sweep and a concurrent writer. **What is useful is not confirming
them.** It is telling us whether the class is bigger than these three: whether there is a fourth
shape, whether any of them can destroy something already accepted into the vault rather than
something still in the staging directory, and whether the right remedy is three separate guards or
one rule about when the sweep may run at all.

## What to answer

1. **Does each change address the finding it claims to?** A fix that moves a check without
   changing what is checked, or that handles the reported case while leaving the class open, is a
   finding.

2. **Did any change introduce something new?** This scope's code has been modified in three
   separate rounds, and in two of them a previous round's fix introduced a defect of its own.

3. **Is anything claimed in a comment or document that the code does not do?** Report it; see the
   scoring note above for how it is weighed.

4. **Is this converging, or moving around?** If the same area has been rewritten three times and is
   still wrong, that is the most useful thing you can say and it will not be argued with.

5. **The reversal, answered directly: is last wins right, and what does it cost?**

You are not bound by any previous round's conclusion, including your own. This gate has had a
reviewer retract its own finding, and has rejected fixes that came with passing tests written by
whoever wrote the fix. **Saying that an earlier conclusion was wrong is in scope.**
