# Polish list

Things noticed while building, to be dealt with in **PR 12**, the polish and accessibility
pass. This file exists because the observations get made while the work is happening and
then evaporate. A polish round that starts from memory polishes whatever was most recently
annoying, which is not the same as whatever is worst.

## How items are sorted

Not everything waits for PR 12.

| Kind | When it gets fixed |
| --- | --- |
| **Correctness or security** | Immediately, wherever we are |
| **Structural** | When noticed. A wrong token, a layout approach that will not survive Dynamic Type, or an interaction pattern other screens will copy. Everything built afterward inherits it, so the cost compounds |
| **Cosmetic** | Here, in PR 12. Spacing, weights, radii, animation timing, wording |

## Open

### From Xavier, device testing after PR 11

1. **The app name takes a whole row to itself.** Move it into the top bar so the list starts
   higher.
2. **A black notch at the corner of a card while dragging.** The rounded corner reveals the
   drag preview's own opaque backing.
3. **The Edit button is text where everything else is an icon.** Wants a hamburger styled
   like the settings gear.
4. **Dragging while sorted automatically does nothing,** because the Edit button is hidden
   in that state. It should switch to manual order instead of refusing.
5. **The copied confirmation is small and tucked in a corner.** Wants it larger and centred.
6. **Cancel and Enter manually are set in different weights** on the scan screen.
7. **Colour cannot be chosen while adding an account.** Done. Two treatments, chosen after
   a proposal: a swatch strip directly under the card on the scan confirmation, where the
   point is watching the choice land on the card above it, and a disclosure row opening the
   grid in manual setup, where a `Form` row is the native idiom and the preview is too far
   down for a strip to sit next to what it changes.

### Fixed in PR 12

1. Name moved into the top bar, inline, so the list starts higher.
2. Drag preview given the card's own shape, so the corner no longer shows its backing.
3. Edit is an icon matching the gear, a hamburger that becomes a checkmark while editing.
4. Dragging a sorted list now adopts the order on screen and switches to manual, rather
   than the affordance being hidden. Refusing the gesture was the worst of the options: the
   user has said plainly where they want the card.
5. The copied confirmation is larger, centred on the card, and lasts 2.2 seconds rather
   than 1.6. The old duration was a guess and was consistently gone before it could be
   observed.
6. Both scan buttons in the same weight. Enter manually was a confirmation action, which
   renders bold and made it read as the primary action next to a regular weight Cancel.
8. Code digits larger and the ring thicker. The code is scaled with `@ScaledMetric` rather
   than pinned, so it still follows the reader's text size.
9. The expiring ring is red rather than amber, at Xavier's call. Bright red, because the
   palette's own red card is dark and a deep red ring vanishes into it. Verified against
   the red card, which is the worst case.
7. Colour is choosable in both add paths, and in manual setup it follows the issuer until
   somebody picks one. A choice that silently reverted on the next keystroke in the service
   field would be worse than not offering it.
10. "Ask Siri" in the card's context menu. Removed the context menu, then restored it at
    Xavier's decision once it was clear the replacement cost the lift and preview
    animation. The trade is recorded in `SECURITY.md` as an accepted risk rather than left
    implicit, and PR 17 should establish what the entry actually transmits.
11. Wider margins on the cards, to Apple Weather's proportions. The margin does the most
    work in edit mode, where the delete control and the drag handle otherwise crowd the
    card's edges.
12. Uneven margins between the two scan screen buttons. Cancel was a `Button` and Enter
    manually a `NavigationLink`, and the two pad their labels differently. Both are buttons
    now, with the navigation driven by state.
13. The scroll indicator drew on top of the cards.
14. Haptic feedback when a code is copied, at Xavier's request. `sensoryFeedback`, so it
    honours the system haptics setting. It was drawing exactly where it should:
    padding the list had moved the list's own trailing edge inward to meet the cards. The
    margins now belong to the rows, leaving the list full width and the indicator beside
    the cards rather than over them.

### Fixed on sight rather than deferred

- **The add sheet's title truncated to "Add acc...".** Cancel on one side and Enter
  manually on the other left no room. Fixed by removing the title: the two buttons say what
  the screen is, and a truncated word reads as a bug rather than as a tight layout.
- **A dark rectangle around a card while dragging it.** The row was taller than the card,
  because the gap between cards came from row insets, so lifting one showed the list's own
  background in the margin. Fixed by giving the gap to `listRowSpacing` and letting the row
  be exactly the card. Structural rather than cosmetic: it was the layout approach, and
  every list built on it would have inherited the same seam.

### Noticed while building

- **Empty issuer and name in the manual setup preview** was fixed during PR 9 rather than
  deferred, because a card rendering as blank lines reads as broken. Noted here only as a
  precedent for where the line sits.
- **The counter based next code button has no feedback.** Tapping it swaps the digits with
  no motion at all, so on a fast glance it is not obvious anything happened.
- **`UnreadableAccountRow` has never been seen by a human.** It is covered by tests and by
  nothing else, since producing one requires metadata this version cannot parse. Worth
  building one deliberately during PR 12 to check the row actually reads well.

### Deferred deliberately, with a reason

- **The list has no animation when accounts are added or removed.** Deliberate for now:
  motion is easier to judge once the screens around it are settled.

## Done

- **No app icon.** Landed out of band, since it was a design task with no dependencies on
  the roadmap. Source at `docs/design/icon.svg`, reasoning in `docs/UI_SPEC.md`.

Items move here as PR 12 clears them, with a line saying what changed, so the file stays a
record rather than a wish list.
