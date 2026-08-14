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

### From Xavier, device testing after PR 10

- **Colour cannot be chosen while adding an account.** It is suggested from the issuer and
  can only be changed afterward, in edit mode. **Deferred to PR 12** as a small feature
  rather than polish, and cheap now that `AccountColorPicker` exists: it needs adding to
  the scan confirmation and to manual setup, and the suggested colour becomes the default
  selection rather than the only one.

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

- **The copied confirmation may be too brief.** It shows for 1.6 seconds, which was chosen
  rather than measured, and it was consistently gone before a screenshot could catch it
  during PR 7. Worth watching on a real device before changing, since a screenshot round
  trip is not a person.
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
