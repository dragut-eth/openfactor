# E11: a link arriving over a shared image, measured on hardware

**Date:** 2026-08-19. **Device:** Xavier's iPhone 15 Pro, build from `4b8317f`, installed by
`devicectl` rather than TestFlight, so the code under test is the code in the commit.

## What was being answered

Round four of scope 4 filed S4-37, and it was the one finding in that round no test in this
repository could answer.

With the arrival queue removed, a link arriving over a shown image sheet changes `arrival` from one
identity to another. Both kinds present through a single `sheet(item:)`, and
`AccountListView`'s deferral only engages when a *different kind* of sheet is open, so an
image-to-link swap relies on SwiftUI cleanly exchanging one sheet item for another mid-flight.

**This scope has repeatedly found SwiftUI dropping that kind of transition**, and the code's own
comment on `canPresentArrival` documents it dropping one. If it were dropped here, `arrival` would
stay non-nil with nothing on screen and `collectWhatArrived` would be blocked for the life of the
process. That is the wedge, reachable with no queue at all.

**The existing measurement did not answer it.** Checklist item 11 recorded four runs out of four,
and its own parenthetical said those runs were taken against the queue that has since been removed.
That is a different sheet pairing, and round three's record notes that SwiftUI's drop behaviour
depends on the specific pairing. The number did not transfer.

## The procedure

With the vault unlocked and the account list showing:

1. Share a QR image to OpenFactor from another app. The share sheet closes and the app is not
   opened, because an extension may not open its containing app.
2. Open OpenFactor. The Add account panel presents, filled in from the QR in that image.
3. Leaving that panel on screen and adding nothing, switch to another app and open an
   `otpauth://` link.
4. Look at what iOS switches back to, and touch nothing.

Three outcomes were named in advance, so the result could not be read generously:

1. The panel is up, showing the account from the link.
2. No panel at all, just the account list. **The wedge.**
3. The panel is up, still showing the account from the image. The link ignored.

## The result

**Four runs, four times outcome one.** The panel stayed on screen and its contents changed from the
image's account to the link's.

**The fourth run was a variant the tester improvised, and it is worth more than the repeat.** The
QR image was shared and OpenFactor was *not* opened in between, so the image was still sitting
uncollected in the inbox when the link arrived. Outcome one again: the link presented.

That run exercises a different path from the other three. Nothing was on screen to be swapped;
`onOpenURL` superseded an item that had never been collected, which is the disk half of the
last-wins rule and the path that `sweep(_:)` was rewritten for in `4b8317f`. It is checklist item
12 rather than item 11, and it passed on the first attempt against the current build.

## What this closes and what it does not

**S4-37 is closed.** The swap does not drop, in the pairing that ships, at four runs out of four.

**Four runs is what the standard here has been**, and it is the same count that showed the queue
working. It is not proof of a race being impossible. The defect this replaced showed at one run in
four, so four clean runs is evidence against a fault of that frequency and not against a rarer one.
Stated rather than rounded up.

**Checklist item 11 is now measured against the build that ships**, and its parenthetical no longer
carries a measurement of something else.
