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
| Add **App Lock** (Face ID, Touch ID, passcode) | The reference has no lock at all. A found unlocked phone should not hand over every second factor |
| Add **Export and Import** | Users must be able to leave. An authenticator you cannot escape is a trap |
| Add **About and Source**, linking to the GitHub repo and license | The whole point of the project |
| Replace **Send Feedback** with **Report an Issue**, linking to GitHub Issues | No mail composer, no support inbox to run |
| Keep **Rate on the App Store** | Uses `StoreKit`, involves no tracking. Not present until there is a listing to point at, which is PR 18 |
| Add **Appearance** (System, Light, Dark) | The palette was built for both schemes from the start, so honouring a preference costs nothing |
| iCloud row explains in plain words what is synced and that Apple cannot read it | Sync is the one thing that leaves the device, so it gets an explanation, not just a toggle |

**iCloud sync, as built in PR 13.** A single switch, off by default, under a `Sync`
heading, with a footer that changes with its state rather than a fixed line of marketing.
Off, it says what turning it on would do and what it costs: accounts reach your other
devices including the watch, it is end to end encrypted, Apple cannot read it, and in
exchange your accounts become readable whenever this device is unlocked rather than only on
this device. On, it says where they are, that Apple cannot read them, and what switching
off would do.

The footer is the only place in the app where the security trade is spelled out at the
moment someone makes it, which is why it names the cost in the same breath as the benefit
rather than a screen away in a document nobody opens.

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

*Swapped to the current artwork after PR 13. The previous design, six account cards on
black, is kept in the repository history rather than described here as though it were
still the icon.*

The icon is an isometric cube, its three visible faces divided into two by two facets,
twelve facets in the six card colours used twice each. Same canvas as before: #1B1B21
falling to #08080B on the diagonal, with a faint radial glow at the upper left.

Colour does the work that shape cannot. At 29 px thin geometry collapses but hue survives,
so the icon degrades into a spectrum chip that is still recognizably this app. The six
colours are the card palette: red, orange, green, teal, indigo, pink. Grey is excluded
because it spends a facet without saying anything. The icon colours run slightly more vivid
than the in app cards, which are contrast tuned for white text; the icon carries no text.

It keeps distance from every neighbour on the shelf. The lock is Microsoft's, the keyhole
1Password's, the shields belong to Authy and Aegis, the star to Google, and the ring to
Step Two. It also makes no security claim: no lock, no shield, no key. Those are promises,
and an unaudited tool should not make promises.

**It does carry a shape association the previous icon did not,** and that is worth stating
rather than leaving for someone else to notice. A cube with mixed colour facets reads as a
puzzle, and specifically as a Rubik's Cube, which is a strongly associated commercial
product. The rendering here is two facets per edge rather than the classic three, and the
European trade mark on the cube's shape was annulled in 2019, so this is a question to ask
before the App Store submission in PR 18 rather than a known problem. It is recorded here
so the submission does not meet it cold.

One light source at the upper left, as before: the left face is darkened 8 percent, the
right face 20 percent, and every facet gradient is angled a few degrees off vertical toward
the same light. That is what makes twelve shapes read as one object.

Geometry, in the 1024 canvas: apex at 512, 96, centre vertex at 512, 512, bottom at
512, 928, with the widest points at 152 and 872. Every vertex is within 416 of the centre,
comfortably inside the 512 radius inscribed circle, so the same artwork survives the
watchOS circular mask when the watch target arrives in PR 14.

The source of truth is docs/design/icon.svg. The 1024 PNG in the asset catalog is
rendered from it, and any SVG renderer at 1024 by 1024 reproduces it exactly.

### How it is installed

The asset catalog uses the single size format: one 1024 by 1024 image at
`OpenFactor/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, from which Xcode
derives every size the system asks for. The artwork is full bleed and square, with no
pre rounded corners and no padding, because the system applies its own mask and
rounding a second time would show.

Two of the three iOS 18 appearances are declared:

- **Default.** The artwork as rendered.
- **Tinted.** `AppIcon-1024-Tinted.png`, a grayscale rendition the system colours with
  the user's chosen tint. Derived from the same PNG with `sips`, so there is no second
  piece of artwork to keep in step:

  ```bash
  sips --matchTo "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc" \
    AppIcon-1024.png --out AppIcon-1024-Tinted.png
  ```

- **Dark** is deliberately absent. An appearance that is not declared falls back to the
  default, which is exactly what is wanted here: the canvas is already near black, so the
  dark variant would be the same artwork. Declaring it would mean committing a second file
  byte for byte identical to the first, which a reviewer would rightly stop to question.

## Consequences for the data model

Two attributes the roadmap needs to account for in the storage layer (PR 4), both of
which are non secret and therefore stored alongside the metadata, never with the secret:

- `color`: the palette entry chosen for the account
- `sortIndex`: manual ordering, since the reference defaults to sorting manually
