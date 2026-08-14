# UI Specification

Derived from Step Two reference screenshots (kept locally in `assets/`, which is
gitignored and never committed). The feature set is copied deliberately. The visual
treatment is adapted where noted.

## Screen 1: Account list (root)

**Reference behavior**

- Top bar: search field on the left, settings gear and add button as circular icon
  buttons on the right. No large navigation title.
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
| Ring turns amber in the last 5 seconds | Tells the user to wait for the next code rather than start typing one about to expire. Amber rather than red, because the code is still perfectly valid and red would say it is not |
| Full light mode support, a v1 requirement | The reference is dark only. Light mode costs little if color tokens are defined from the start and is painful to retrofit later |
| Card color meets contrast requirements against white text | Some reference colors are borderline. Every palette entry gets checked |

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
| Keep **Rate on the App Store** | Uses `StoreKit`, involves no tracking |
| iCloud row explains in plain words what is synced and that Apple cannot read it | Sync is the one thing that leaves the device, so it gets an explanation, not just a toggle |

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
  responds to accessibility text sizes rather than shipping fixed point sizes.

## Consequences for the data model

Two attributes the roadmap needs to account for in the storage layer (PR 4), both of
which are non secret and therefore stored alongside the metadata, never with the secret:

- `color`: the palette entry chosen for the account
- `sortIndex`: manual ordering, since the reference defaults to sorting manually
