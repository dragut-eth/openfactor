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

## Still needed

- **Screenshots.** The "See it" section of `index.html` is commented out because
  `assets/screenshots/list.png`, `watch.png` and `add.png` do not exist. Live, they would render
  as broken images. They are the same images App Store Connect needs, so this waits on that work
  either way. Uncomment the section once they are in place.
- **A copy pass**, which should begin by deciding who the page is for.

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
