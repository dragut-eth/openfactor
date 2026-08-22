# site

The pages served at `openfactor.dev`. Plain HTML and one stylesheet, no framework, no build
step, no dependencies.

**What is here is exactly what is served.** `site/index.html` is `openfactor.dev/index.html`,
`site/privacy.html` is `openfactor.dev/privacy.html`. Nothing outside this folder is ever
published, which is why the engineering documents in `docs/` stay unpublished while living in
the same public repository.

## The rule: this derives from the repository, never the reverse

Every claim on these pages was copied out of `README.md` and `docs/APP_STORE.md` rather than
written fresh, which is the only reason three surfaces currently agree with each other.

**A claim changes in `README.md` or `SECURITY.md` first, and this follows.** The failure to
prevent is somebody sharpening a sentence here because it reads better on a landing page, and
this becoming the one surface that over-claims. `docs/APP_STORE.md` states the same rule for the
listing.

## Status

**Live at `openfactor.dev`. The copy has not had a proper pass.**

The structure, the stylesheet and the layout are settled. The text was drawn from `README.md`
and `docs/APP_STORE.md`, so every factual claim in it was checked against what the repository
already claims, which is the rule `docs/APP_STORE.md` is written under. What it has not had is a
pass for voice: it reads like the README because it came from the README.

The first question a rewrite should answer is who the page is for. Somebody arriving from a
discussion thread who wants to know whether the design is sound, and somebody arriving from the
App Store deciding whether to install, want measurably different pages.

**The page is light only, deliberately.** The app icon used here has a near-white background, so
a dark palette would put a bright tile on a dark ground. `color-scheme: light` is set so the
browser does not darken scrollbars and controls when the operating system is in dark mode.
Re-adding a dark palette means revisiting the icon at the same time.

## The order of the page, and why

**What it is comes before the statement.** A reader who has just arrived needs to know what the
thing does before being told how far to trust it. The statement then answers a question they are
actually asking rather than one nobody had yet.

**The statement is green, not amber.** It was styled as a warning when it opened with what the app
lacked. It now opens with what the app is and closes with the audit caveat, and an alert palette
contradicted its first sentence before anybody read it.

**It is left aligned.** It sat inside the centred hero and inherited that, which turns a paragraph
of prose into a centred block nobody finishes.

**The screenshots have no heading and no caption.** "See it" labelled three pictures of an app as
pictures of an app. The caption about the accounts being invented came out too: the App Store
frames carry no such note and the demo data reads as demo data.

**The hero has one button.** Privacy was there and is in the footer, which is where people look
for it.

## Still needed

- ~~Screenshots.~~ **Done, in Apple's own product bezels.** `list.png`, `watch.png` and
  `add.png` are the App Store originals composited into the iPhone 17 in Black and the Apple Watch
  Ultra 3 with the Green Neon Trail Loop, taken from Apple's Design Resources.

  **The devices are at their true relative size, which took work to get right.** An earlier
  version exported all three at the same height, so the Ultra rendered as tall as the iPhone and a
  49 mm watch looked like a tablet. The phone bezel spans about 152 mm and the watch about 75 mm,
  so the images are exported in that ratio, 840 against 412, and the CSS sizes them **by height
  with width following**. A grid that stretches each image to a column width destroys this, which
  is what the previous layout did.

  The screen holes were located by flood filling the transparent region of each bezel rather than
  by hardcoding an offset a future bezel would move, and **the screenshot is masked to that
  region's real shape**. An earlier version pasted into its bounding box instead, so the square
  corners of the screenshot sat outside the rounded screen and poked past the bezel. The phone
  screenshot's aspect matches its screen to within a rounding error; the watch is scaled to cover
  and centre cropped, because a letterbox inside a device frame reads as a bug.

  The band is the Trail Loop in Green Neon. The row aligns to the top, so the three screens start
  on the same line rather than the watch floating up from a shared baseline.

  **The list screenshot is the light one, and that was a capture decision rather than a taste
  one.** The dark version is scrolled mid-card, so the toolbar sits over a partial card and the
  first thing a viewer sees is a six digit number with its label hidden behind the translucent
  nav bar, with the bottom card cut by the search field. The light one starts and ends on complete
  cards. It also matches the add-account screen beside it, so the three read as one set rather
  than as two appearances nobody chose. Both are in App Store Connect, so either was available.

  **The same images the store shows**, so the landing page and the shop window cannot drift apart.
  Explicit `width` and `height` so the page does not reflow while they load, and a caption says
  the accounts in them are invented, because a grid of plausible bank codes should say so.
- **A copy pass**, which should begin by deciding who the page is for.

## security.txt

`.well-known/security.txt` is RFC 9116, and it points at the GitHub Security Advisories channel
`SECURITY.md` already names rather than introducing a second one: security reporting stays on one
good channel.

**`Expires` is required by the RFC and is a real deadline**, not decoration. A file past its expiry
is worse than none, because it advertises a channel nobody has confirmed is still watched. The date
here is 2027-08-21 and moving it is a deliberate act of saying the channel is still live.

## Deploying

Cloudflare Pages, building from `main`, build output directory `site`, no build command. Nothing
in these files assumes that host: they are static and relative linked, so any static host serves
them.

The privacy policy URL given to App Store Connect is `https://openfactor.dev/privacy`, without
the extension, because `/privacy.html` 308-redirects to it and Apple should be handed the
destination.

**Build watch paths should be set to `site/*`.** Without them every commit to the repository
redeploys the site, which is harmless and wasteful. The warning that matters is the other
direction: **if the site ever moves out of `site/`, deploys will stop silently** and nothing will
report an error. Whoever moves it changes the watch path in the same breath.

**`www.openfactor.dev` currently returns 521** and needs adding as a second custom domain in
Cloudflare Pages. The apex is fine. A person typing `www` gets an error page.

## The privacy page is not a template

`privacy.html` is a statement by ReVeNG System to the people who install the app it publishes. A
fork must not ship it unedited; it would make promises in someone else's name about software they
did not build. The same applies to `index.html`, which is this project's positioning rather than
a starting point for anyone else's.
