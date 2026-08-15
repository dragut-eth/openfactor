# UI Specification

Derived from Step Two reference screenshots (kept locally in `assets/`, which is
gitignored and never committed). The feature set is copied deliberately. The visual
treatment is adapted where noted.

## Screen 1: Account list (root)

**Reference behavior**

- Top bar: search field on the left, settings gear and add button as circular icon
  buttons on the right. No large navigation title. Ours puts the name inline in the bar for
  the same reason: a title row of its own costs a card's worth of screen.
- Vertically scrolling list of full width colored cards, generous spacing between them.
- Each card carries, from top to bottom:
  - Issuer name, bold
  - Account label (email or username), lighter weight, one line
  - The current code, very large, white on the card color
  - A circular countdown ring in the top right corner that depletes over the period
- Card background is a subtle vertical gradient of the account color.
- Dark background throughout. The reference is dark only.

**Adaptations**

| Change | Reason |
| --- | --- |
| Code rendered with monospaced tabular figures, grouped `123 456` | Digits stop shifting on every tick, and grouped digits are easier to carry from screen to keyboard. Six splits into threes, eight into fours, seven is left alone since a lopsided split is worse than none. The separator is a thin space, so the code still reads as one number |
| Ring redraws once per second, not continuously animated | One shared timer for the whole list, far less battery and CPU than a per card animation |
| Ring turns red in the last 5 seconds | Tells the user to wait for the next code rather than start typing one about to expire. Amber was tried first, on the argument that the code is still valid and red says it is not. Red won because it is what people actually read as "hurry", and a second of hesitation costs nothing while a code that expires mid login costs a retry. It is a bright red, since the palette's own red card is dark and a deep red ring would vanish into it |
| Full light mode support, a v1 requirement | The reference is dark only. Light mode costs little if color tokens are defined from the start and is painful to retrofit later |
| Card color meets contrast requirements against white text | Some reference colors are borderline. Every palette entry gets checked |
| The copied confirmation sits across the middle of the card | It confirms the reason the card was tapped, and the reader's eyes are already on the digits. A corner badge was missed |
| Long press opens the system context menu | Kept for the lift and the card preview, which an app defined sheet cannot reproduce. iOS may append entries of its own to it, including "Ask Siri". Recorded as accepted in `SECURITY.md` |
| Dragging a list that is sorting itself adopts the visible order | Refusing the gesture was the worst option. The user has said where they want the card |

**Interactions**

- Tap a card: copy the code to the pasteboard, with a brief confirmation. The entry is
  written with `localOnly` and an `expirationDate` set to the moment the code itself stops
  working, so it neither outlives its usefulness nor travels to the user's other devices.
  Both were verified rather than assumed: an entry written with an expiry already past is
  unreadable, and an entry written without `localOnly` does reach the host clipboard while
  one written with it does not. See `CodeClipboardTests`.
- Search filters by issuer and label.

## Screen 2: Settings (modal sheet)

**Reference rows:** Sort Accounts (value: Manually), iCloud (value: On), Version,
Rate on the App Store, Send Feedback. Each row has a colored rounded icon. `Done` closes.

**Adaptations**

| Change | Reason |
| --- | --- |
| Add **App Lock** (Face ID, Touch ID, passcode) | A found unlocked phone should not hand over every second factor. iOS can already lock any app at the system level, so what this adds is the grace period and, more importantly, the app switcher cover that hides codes for everyone whether they enable the lock or not |
| Add **Export and Import** | Users must be able to leave. An authenticator you cannot escape is a trap |
| Add **About and Source**, linking to the GitHub repo and license | The whole point of the project |
| Replace **Send Feedback** with **Report an Issue**, linking to GitHub Issues | No mail composer, no support inbox to run |
| Keep **Rate on the App Store** | Uses `StoreKit`, involves no tracking. Not present until there is a listing to point at, which is PR 18 |
| Add **Appearance** (System, Light, Dark) | The palette was built for both schemes from the start, so honouring a preference costs nothing |
| iCloud row explains in plain words what is synced and that Apple cannot read it | Sync is the one thing that leaves the device, so it gets an explanation, not just a toggle |

**App Lock: a toggle and a grace period, under a Security header.** Off by default, since
everything in this app is opted into. The grace period offers Immediately, 1 minute, and
5 minutes, three categorical values rather than a slider, and the picker only appears while
the lock is on. The toggle refuses to enable on a device with no passcode, with the footer
saying why, because a lock that cannot lock is a false claim with a switch on it.

The footer states what the lock is with no flattery: a gate that keeps codes off the screen
when someone else holds the unlocked phone, while the secrets stay protected by the
Keychain either way. The overclaim would have been easy and it is the one SECURITY.md
forbids.

**The lock screen** is a surface, a lock mark, and one Unlock button. It names no account
and shows nothing of what is behind it, because it is also what the app switcher
photographs while locked. Face ID raises itself once per locked spell; after that the
button re-raises it, so a cancelled prompt does not loop.

**The snapshot cover is not a setting.** The moment the app stops being active, a blank
surface covers everything, including sheets, including manual entry with a half typed
secret in it. It exists because iOS photographs the app for the switcher, and that
photograph must never contain a code. Lock or no lock, everyone gets this.

**App icon: Dark, Light, Automatic.** Duplicating part of the system's own icon appearance
control on purpose. That one applies to every app at once, and someone who wants their
authenticator to look a particular way should not have to make every other icon match.

**iCloud sync, as built in PR 13 and reworded at gate A2.** A single switch, off by
default, under a `Sync` heading, with a footer that changes with its state rather than a
fixed line of marketing. It is the only place in the app where the security trade is
spelled out at the moment someone makes it, which is why it names the cost in the same
breath as the benefit rather than a screen away in a document nobody opens.

Three things the first wording got wrong, all in the same direction, all corrected:

- **It said "puts", and the app can only offer.** Marking an item synchronizable hands it
  to iCloud Keychain; whether anything leaves depends on iCloud Keychain being on in iOS
  Settings, which there is no public API to check. The footer now says "offers", names the
  prerequisite, and says the app cannot verify delivery. The user this protects is the one
  who believes their accounts are backed up, loses the phone, and finds nothing on the new
  one.
- **It promised Apple Watch, and there is no watch app.** An aspirational footer breaks the
  same rule as an aspirational row, and worse: it teaches someone their watch already holds
  their secrets. The mention returns when the watch does.
- **It claimed turning sync off stops the accounts reaching other devices.** Nobody has
  observed that, and Apple's documentation points the other way. It now says turning off
  stops this device offering them and may remove them elsewhere, which is what is actually
  known.

The off state footer also says what the on state does to other devices before the switch is
touched: the accounts reach every device signed in to the Apple Account where OpenFactor is
installed, with nobody doing anything on those devices.

The switch writes the preference only after the Keychain work succeeds, so it never claims
a state the Keychain disagrees with. On failure it stays where it was and a line of red
text appears under it. That text does not say "nothing changed", because conversion runs
account by account and a failure part way through leaves some converted. It says to try
again, which is sound advice: the operation is idempotent.

**A row appears when its feature does.** There is no row for the app lock or export,
because a settings screen is a description of what an app does. A row reading "App
Lock" tells someone their codes are behind Face ID, and a greyed one reading "coming soon"
tells them the app is nearly there. Neither is true yet, and in a security tool that is not
a harmless exaggeration. This is the same rule that kept the add button out of the top bar
until PR 8 and the settings gear out until PR 11.

**Sorting is a view of the list, not a rewrite of it.** Choosing an automatic order does not
touch the stored positions, so switching away and back returns the arrangement someone made
by hand. Dragging is offered only while the order is theirs to set, since a drag into a list
that sorts itself would either be ignored or would silently change the setting.

**The About footer describes the Keychain, not the switch.** It reads the stored accounts'
actual sync state and says one of four things: on this device only, in iCloud Keychain as
well, a mixture, or, if the query fails, nothing about location at all. "On this device
only" is the strongest security sentence in the app, and it used to be the one sentence
asserted without looking. A mixture is not an error to be repaired, see `SECURITY.md`, but
it is something to say out loud.

**The delete confirmation names the blast radius.** Deleting is the only irreversible act in
the app, and under sync it reaches every device. The alert reads the account's sync state
and says "from this device" or "from this device and from your other devices" accordingly.
If that read fails it uses the wider warning, because overstating the consequence of an
irreversible act is the safe direction to be wrong in. The person this protects is the one
keeping a second device precisely as their fallback.

**Preferences live in `UserDefaults`, secrets do not.** A sort order and a colour scheme
reveal nothing, not even that any accounts exist. Anything that would say which services
someone uses is in the Keychain with the secrets, which is why the account metadata is there
and not here.

## Screen 3: QR scanner

**Reference behavior:** full screen camera, `Cancel` top left, `Manual Setup` top right,
both as translucent pill buttons. No frame overlay, no instructions.

**Adaptations**

- Add a scanning frame and a one line hint. The bare camera gives no feedback about
  whether anything is happening. Verified working on device, 2026-08-14.
- Add import from a photo, since services often show the QR on the same phone. It goes
  through `PhotosPicker`, so the app never gets access to the photo library itself and
  never asks for it.
- Handle the camera denied path with a clear route to Settings and to manual entry, rather
  than a black screen.
- **A scan does not save. It confirms first,** showing the issuer, the account name, and a
  live code. A QR code is unreadable to a human, so this is the only chance to see what was
  actually in it, and the code can be checked against what the service is showing while the
  enrollment page is still open. After that page closes, a wrongly imported account is
  discovered at a login. The reference saves immediately; this costs one tap and buys the
  only verification opportunity the flow has.
- An image holding more than one QR code is refused rather than guessed at. Which account
  gets added should not be a coin toss.
- The confirmation carries a **swatch strip directly under the card**, so a colour choice
  lands on the thing being chosen for. A picker that covered the card would hide it.

## Screen 4: Manual setup

**Reference fields:** Secret Key, Account Name, Email Address or Username. `Cancel` and
`Save` as pill buttons. Nothing else is exposed.

**Adaptations**

- Add an **Advanced** disclosure, collapsed by default, holding algorithm
  (SHA1, SHA256, SHA512), digit count (6, 7, 8), period, and TOTP versus HOTP.
  The reference silently assumes the defaults, which breaks for a real minority of
  services. Hidden by default, so the simple path stays as simple as the reference.
- Validate the secret as the user types and say precisely what is wrong, since a bad
  Base32 secret otherwise fails silently and produces codes that never work. The message
  is the parser's own typed error, not a rewritten one, so it names the offending
  character and its position.
- An untouched field says nothing. Validation appears once there is something to validate,
  and Save is simply unavailable until the form describes a real account.
- Show a live preview of the generated code before saving, so the user can confirm it
  matches the service before losing access to the enrollment page.
- A **colour row opening the grid**, rather than the strip the scan screen uses. In a form
  a disclosure row is the native idiom, and the preview card is far enough down that a
  strip would not sit next to what it changes. The colour follows the service name until
  somebody picks one, then stops, because a choice that reverted on the next keystroke
  would be worse than no choice.
- **Counter based accounts get a next code button in the list, not a countdown ring.**
  Their codes advance when asked for rather than with the clock, so a ring would be a lie.
  The counter is persisted before the new code is shown, for the reasons in
  `docs/audits/A1.md` under F4.

## Screen 5: Edit mode

**Reference behavior:** entered from somewhere on the list, `Done` top right. Cards dim
and each grows a `...` button at its top left corner. That button opens an action sheet:
Change Color, Edit Account Info, Remove "<issuer>" in red, Cancel. Reordering by drag is
implied by the Sort Accounts setting.

**Adaptations**

- Removal takes an explicit second confirmation naming the consequence, that the secret is
  deleted from the device and cannot be recovered, and that access to the account is lost
  if this is the only way in. The reference uses a single destructive tap. Deletion is the
  only irreversible thing in the app, so the word "remove" is not left to carry that alone.
- Swiping to delete exists too, and routes through the same confirmation. A swipe is a
  convenient gesture, not a decision to lose an account.
- Change Color offers the palette as a grid rather than a nested list. Ten swatches fit on
  one screen, so nobody should have to scroll a list of colour names.
- **Reordering uses the system's drag handles rather than a custom drag.** The reference
  implies dragging with no visible affordance. The native handles are familiar, work with
  VoiceOver, and cost nothing to adopt.
- Reordering is unavailable while a search is filtering the list, since rearranging a list
  you can only partly see is not a coherent gesture.
- Only positions that actually changed are written back, because each one is a Keychain
  round trip and dragging one card to the top would otherwise rewrite every account.
- Editing exposes only the service and account names. Algorithm, digits, period, and
  counter came from the service at enrolment; changing them here would not change what the
  service expects, it would just stop the codes matching.

**Edit mode is the three things iOS already provides, and nothing else.** A delete control
on the left, a drag handle on the right, and a row that opens its details when tapped, which
is how Reminders and Contacts behave.

There was briefly a fourth thing, an ellipsis menu on each card. It was not decoration, it
was covering a gap: in edit mode a long press is a drag, so the context menu is unreachable
and Change colour and Edit details had nowhere to live. Filling that gap with a new control
was the wrong instinct twice over. The ellipsis is a navigation bar idiom rather than an
edit mode one, and it sat exactly where the countdown ring sits, so the ring appeared to
mutate into a button. Tapping the row is what iOS users already reach for, and it removes a
control instead of adding one.

**Tapping a card means copy normally and edit while editing.** The meaning changes with the
mode, which is the same split iOS uses, so the VoiceOver hint changes with it: "Copies the
code" becomes "Opens details".

**The edit screen holds the colour.** Previously "Edit details" and "Change colour" were two
destinations for one idea, which was tolerable while the only way in was a menu offering
both, and stopped being tolerable when a tap had to choose one of them. Change colour in the
context menu is now a shortcut into a screen that holds everything, rather than the only way
to reach the colour at all. One grid of swatches, used inline by the edit screen and wrapped
in a sheet by the shortcut, so the two cannot drift apart.

## Screens 6 and 7: the watch

**Read only, and that is a security property rather than a scope cut.** The watch shows the
list and one code. It cannot add, edit, delete, or copy. The smallest device with the
weakest lock gets the fewest capabilities.

It holds its own copy of the secrets and works with the phone off, absent, or out of range.
Those copies arrive through iCloud Keychain in the shared access group, not over
WatchConnectivity, which would have meant a second transport for secret material.

**The list is not a resized phone card.** A card is a coloured rectangle carrying white
text; at this size that would be a colour swatch with unreadable writing on it. So the
screen stays the black it already is and the colour moves to the type: issuer in the
account's colour, account name in white beneath it.

The palette inverts for the same reason. The phone's entries are dark enough for white text
to sit on them, which is precisely the wrong thing against black. `WatchPalette` holds the
vivid variants, chosen to clear contrast against black rather than under white. Only the
issuer is coloured. The account name and the code are white, because a code read at a glance
in bad light needs contrast more than it needs identity.

**No code appears in the list.** The phone shows every code at once, because a phone is held
deliberately and put away. A watch is on a wrist that is visible to whoever is standing next
to you. One code, when you ask for it, is the whole difference.

**The code screen is the code, a countdown ring, the issuer and the account, and the way
back.** Nothing else. The ring turns red for the last five seconds, as on the phone, because
a code you are halfway through typing is about to stop working.

**The complication launches the app and shows nothing.** Decided by Xavier, and it is the
same call as codes being absent from the list, for the same reason: a watch face is readable
by anyone standing next to you, glanced at over a shoulder, photographed across a table. A
live code sitting there permanently is a second factor shown to the room all day.

The design makes that structural rather than a promise. The complication is a separate
extension with **no `keychain-access-groups` entitlement**, so it cannot reach the secrets
even if a future change asked it to, and its timeline is a single entry with a `.never`
refresh policy, so it has no reason to wake up at all. Anything that gives that target
Keychain access is reversing a security decision and should be reviewed as one, not merged
as a feature.

**The watch scales the way the phone learned to in PR 12.** The code and ring sizes are
scaled metrics rather than constants, and at accessibility sizes the pair stacks vertically
instead of sharing a row, since a grown code beside a grown ring does not fit a watch and
shrinking the code would undo the setting the wearer asked for. Verified by screenshot at
the largest accessibility size, not assumed.

The verification itself needed scaffolding worth knowing about: the watchOS simulator
refuses `simctl ui content_size`, and its keychain holds no accounts. The watch app
therefore has a DEBUG only rehearsal mode, behind `--layout-rehearsal` and `--ax-text`
launch arguments, which swaps in an in memory store of fakes and pins the largest text
size. It does not exist in a release build, and the fakes' secret is the RFC test vector,
the one secret on earth that protects nothing.

**One thing on the watch is the platform's and is left alone.** Scrolled rows flash to full
opacity for a frame during a push, as watchOS drops its own scroll edge treatment before the
transition finishes. Checked against a stock watch app, which does the same, rather than
assumed. Defeating it would mean drawing our own edge treatment and fighting the platform's,
which is not worth it for a single frame.

**The empty state is load bearing, and it is written for the person whose accounts are
merely late.** An empty watch and a broken watch look identical. iCloud Keychain took close
to half an hour to carry seven accounts across during PR 14, arriving one at a time with no
error reported anywhere, and that latency fooled the people building it twice in a row. So
the screen says nothing has arrived yet and names the likely reason, and deliberately does
not send anyone off to re-check settings that are already correct.

## Design tokens

Defined once in the app and never hardcoded at a call site, so a design change is a one
file diff and so light mode is possible at all.

- **Account palette:** red, orange, yellow, green, teal, blue, indigo, purple, pink, gray.
  Each entry ships a light and a dark variant. Every variant, at both ends of its gradient,
  is asserted at 4.5 to 1 or better against the white text drawn on it, by a test rather
  than by eye. See `OpenFactor/Design/Palette.swift`.

  **This is why the palette is visibly deeper than the reference.** Holding white text to
  WCAG AA rules out the bright yellow and light orange an authenticator would reach for
  first. That is a deliberate trade: a code that cannot be read at arm's length in sunlight
  is a broken feature in an app whose whole job is showing six digits.
- **Surfaces:** background, card, elevated, separator. Every one defined for both schemes.
  No color is ever hardcoded at a call site, so a scheme is a one file change.
- **Scheme override:** a setting offering System, Light, and Dark, defaulting to System.
- **Type:** issuer, label, code, and UI scales, all built on Dynamic Type so the app
  responds to accessibility text sizes rather than shipping fixed point sizes. The code is
  a scaled point size rather than a text style, because it should be larger than
  `.largeTitle` and that is the largest style there is.

## Accessibility

Not a pass at the end. The rules the interface follows.

- **The card reflows at accessibility sizes.** Normally the countdown ring sits beside the
  text. At accessibility sizes it stacks underneath instead, because a fixed element beside
  growing text squeezes the text into a column and an issuer starts wrapping mid name. The
  per card menu button follows the ring.
- **A code never wraps.** Six digits split across two lines get read wrong more often than
  they get read slowly, so the code shrinks to fit rather than reflowing. It is the one
  place Dynamic Type is allowed to lose, and the only one.
- **An account name wraps rather than truncating at accessibility sizes.** Truncating an
  email address to a few characters helps nobody, and the extra height is what the reader
  asked for by turning the text up.
- **VoiceOver reads a card as one element**: issuer and name as the label, the code spoken
  one digit at a time and the seconds remaining as the value. Without digit by digit,
  `751702` is read as "seven hundred fifty one thousand, seven hundred two", which nobody
  can type into a login form. The ring is hidden from VoiceOver, since its information is
  already in the value.
- **Reduce Motion removes scaling, not feedback.** The copied confirmation still appears,
  by fading rather than scaling. The setting exists because movement makes some people ill,
  not because they dislike it.
- **A copy is confirmed by touch as well as sight.** Tapping a card produces no visible
  change except a badge that fades, so it also triggers system haptic feedback, which
  honours the user's own haptics setting rather than buzzing regardless.

## App icon

The icon is the app made physical: a two by two assembly of colored pieces, built
from the card palette, with one corner piece taken out.

Count the pieces and you get the design's reason. A full two by two shows seven
pieces from this angle, the eighth is hidden at the back. Take one out and exactly
six remain in view. Six pieces, six digits of a one-time code. The extracted piece
is the second factor, the one only you hold. What the world sees is an incomplete
puzzle.

The colors are the account card palette, red, orange, green, teal, indigo, pink,
and each appears exactly twice across the twelve visible faces. The extracted piece
carried a green face and a pink face away, and the two faces it exposed give one
green and one pink back. Gray is excluded; it spends a face without saying anything.
The icon colors run slightly more vivid than the in-app cards, which are contrast
tuned for white text. The icon carries no text.

The icon makes no metaphorical claim. No lock, no shield, no key, and no promise,
because an unaudited tool should not make promises. It also keeps its distance from
every neighbor on the shelf: the lock is Microsoft's, the keyhole is 1Password's,
the shields belong to Authy and Aegis, the star to Google, the ring to Step Two.
It keeps distance from the Rubik's Cube as well: two by two rather than three by
three, this palette rather than theirs, seams of open canvas rather than black
plastic.

Hue survives small sizes where shape dies. At 29 px the icon degrades into a
stepped polychrome block that is still recognizably this app, and the missing
corner keeps the silhouette asymmetric where a full cube would be a symmetric blob.

One light source at the upper left. Right-facing faces carry 20 percent shade,
left-facing faces 8 percent, top faces none, and the faces exposed by the notch
follow the same rule.

There are two appearances of one object. The dark appearance sets the assembly on
a charcoal canvas falling from #1B1B21 to #08080B. The light appearance sets it on
white falling to #E9E9EE. The seams between faces are the canvas showing through,
dark in dark, white in light. Nothing about the object changes.

Geometry, in the 1024 canvas before scaling: apex at 512, 96, center vertex at
512, 512, bottom at 512, 928, horizontal extremes at x 152 and 872, and the whole
assembly scaled to 90 percent about the canvas center. Its farthest point sits
about 375 px from center against an inscribed-circle radius of 512, so the artwork
would survive a circular mask. The watch does not use it, see below, but the
headroom stays deliberate: it is what keeps the assembly clear of the squircle's
corners.

The sources of truth are docs/design/icon-dark.svg and docs/design/icon-light.svg.
The 1024 PNGs in the asset catalog are rendered from them, and any SVG renderer at
1024 by 1024 reproduces them exactly.

### The watch icon is the extracted piece

Xavier's idea, and it completes the design rather than shrinking it. The phone
shows the assembly with a piece missing; the watch shows the piece. The story the
icon tells is that the extracted piece is the second factor, the one only you
hold, and the watch is the device you hold on your body. Two devices, one idea,
split the way the idea itself splits.

The colours are not a choice, except one. The assembly's spec records that the
extracted piece carried a green face and a pink face away, so green and pink are
canon: this is the piece, not a piece. Only the third face, never visible while it
sat in the assembly, is free, and it is indigo. Pink sits on the right, indigo on
the left, and the shading stays with the side rather than the colour, because the
light does not move: nothing on top, 8 percent on the left, 20 percent on the
right.

The geometry matches the assembly exactly, slope 0.57763 and edge ratio 1.1547.
Scale was set by eye on the watch itself: at 88 percent of the mask radius the
piece read as a hexagon filling the disc, so it sits at 70 percent, every vertex
360 from centre, and the air around it is what makes it read as an object rather
than a tiling. One piece with three faces also survives 44 px where twelve facets
would mush.

watchOS takes a single image, no appearances, so the dark canvas is the only
canvas. The source of truth is docs/design/icon-watch.svg, same rules as the
others.

**The complication is the same piece, drawn as a template.** The system tints
complications with the watch face's colour, so it is supplied as shape and opacity
rather than colour: three white faces at 100, 72, and 45 percent, which is the
icon's light rule restated in opacity. On a plain face it reads as shades of grey,
on a coloured face as shades of that colour, and in both it stays a solid with a
light on it rather than a flat hexagon. The shape is drawn in code, in unit terms
that make it auditable against the SVG by arithmetic: the bounding box is root
three over two, side vertices at one and three quarters of the height, everything
else a corner or a midpoint.

### How it is installed

The asset catalog uses the single size format: one 1024 by 1024 image per appearance
in `OpenFactor/Assets.xcassets/AppIcon.appiconset`, from which Xcode derives every
size the system asks for. The artwork is full bleed and square, with no pre rounded
corners and no padding, because the system applies its own mask and rounding a second
time would show.

**The dark canvas is the primary icon**, so it is what the App Store shows and what an
untouched install gets. The first version made the light one primary, reasoning that a white
canvas was safer against an unknown background. That was a fudge: the background is not
unknown, the Any Appearance slot is specifically the light appearance slot. The better
argument runs the other way. The App Store's own chrome is near white, so a white canvas
loses its silhouette there and floats, while the charcoal one holds an edge and reads as an
object.

**Three icon sets, because the choice is offered rather than assumed:**

| Set | Contents |
| --- | --- |
| `AppIcon` | The primary. Dark artwork in Any and Dark, so it is dark whatever the system is doing |
| `AppIconLight` | The light artwork, for someone who wants it light |
| `AppIconAuto` | Light in Any, dark in Dark, so it follows the system |

The tinted rendition belongs to the primary only, and is derived from the **dark** artwork
with `sips`. Deriving it from the light one, as the first version did, was wrong: tinted home
screens are dark, and the system drives the tint from luminance, so a near white canvas
becomes a solid slab of the user's colour with the cube as a hole in it. Light element on
dark ground is what a tinted icon has to be.

```bash
sips --matchTo "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc" \
  AppIcon-1024.png --out AppIcon-1024-Tinted.png
```

**Changing the icon shows a system alert that cannot be suppressed.** iOS puts up "You have
changed the icon" every time `setAlternateIconName` is called. Apps that hide it swizzle a
private method, which this one will not do: a security tool that reaches for private API to
avoid a dialog has its priorities the wrong way round, and the alert is honest, since
something did change on the home screen. The setting therefore does nothing when the chosen
icon is already the current one, so that opening this screen never raises an alert.

## Consequences for the data model

Two attributes the roadmap needs to account for in the storage layer (PR 4), both of
which are non secret and therefore stored alongside the metadata, never with the secret:

- `color`: the palette entry chosen for the account
- `sortIndex`: manual ordering, since the reference defaults to sorting manually
