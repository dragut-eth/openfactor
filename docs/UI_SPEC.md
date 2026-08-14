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
| Code rendered with monospaced tabular figures, grouped `123 456` | Digits stop shifting on every tick, and grouped digits are measurably easier to transcribe |
| Ring redraws once per second, not continuously animated | One shared timer for the whole list, far less battery and CPU than a per card animation |
| Ring turns amber in the last 5 seconds | Tells the user to wait for the next code rather than start typing one about to expire |
| Full light mode support, a v1 requirement | The reference is dark only. Light mode costs little if color tokens are defined from the start and is painful to retrofit later |
| Card color meets contrast requirements against white text | Some reference colors are borderline. Every palette entry gets checked |

**Interactions**

- Tap a card: copy the code to the pasteboard, with a brief confirmation. The pasteboard
  entry is marked as expiring, so it does not linger or sync to other devices.
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
  whether anything is happening.
- Add import from a photo, since services often show the QR on the same phone.
- Handle the camera denied path with a clear route to Settings and to manual entry.

## Screen 4: Manual setup

**Reference fields:** Secret Key, Account Name, Email Address or Username. `Cancel` and
`Save` as pill buttons. Nothing else is exposed.

**Adaptations**

- Add an **Advanced** disclosure, collapsed by default, holding algorithm
  (SHA1, SHA256, SHA512), digit count (6, 7, 8), period, and TOTP versus HOTP.
  The reference silently assumes the defaults, which breaks for a real minority of
  services. Hidden by default, so the simple path stays as simple as the reference.
- Validate the secret as the user types and say precisely what is wrong, since a bad
  Base32 secret otherwise fails silently and produces codes that never work.
- Show a live preview of the generated code before saving, so the user can confirm it
  matches the service before losing access to the enrollment page.

## Screen 5: Edit mode

**Reference behavior:** entered from somewhere on the list, `Done` top right. Cards dim
and each grows a `...` button at its top left corner. That button opens an action sheet:
Change Color, Edit Account Info, Remove "<issuer>" in red, Cancel. Reordering by drag is
implied by the Sort Accounts setting.

**Adaptations**

- Removal requires a typed or explicit second confirmation, naming the consequence:
  losing access to the account if no other factor exists. The reference uses a single
  destructive tap.
- Change Color offers the palette as a grid rather than a nested list.

## Design tokens

Defined once in the app and never hardcoded at a call site, so a design change is a one
file diff and so light mode is possible at all.

- **Account palette:** red, orange, yellow, green, teal, blue, indigo, purple, pink, gray.
  Each entry ships a light and a dark variant, since a card color that reads well against
  a near black background is usually too pale against white. Every variant is contrast
  checked against the text drawn on it.
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
