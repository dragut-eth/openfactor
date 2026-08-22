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

**`www.openfactor.dev` returns 301 to the apex**, as of 2026-08-22. It returned 521 until then,
because the hostname was never added to the Pages project. Adding it made `www` *serve* the site,
which left two hostnames returning 200 with identical content, so a **Cloudflare Page Rule** now
redirects it.

    www.openfactor.dev/*   ->   https://openfactor.dev/$1   (301)

**The match pattern carries no scheme on purpose.** Written as `https://www.openfactor.dev/*` it
would match only https, and plain http to `www` would fall through the rule entirely. Without a
scheme it matches both, which is why Cloudflare's own example omits it.

**`$1` belongs only in the destination.** In the match field it is four literal characters, not a
wildcard. Without it in the destination, every `www` URL redirects to the homepage and the path is
silently lost.

**Verified across the cases that actually fail**, not just the bare hostname, which always works and
proves nothing:

    www/                           301 -> https://openfactor.dev/
    www/privacy                    301 -> https://openfactor.dev/privacy
    www/privacy?a=b&c=d            301 -> https://openfactor.dev/privacy?a=b&c=d
    www/.well-known/security.txt   301 -> .../.well-known/security.txt
    http://www/privacy             301 -> https://openfactor.dev/privacy
    apex/privacy                   200, no redirect, so no loop

**The point of this is not SEO.** The canonical tags already told crawlers which host was real.
It is that every check of this domain was two checks, one per hostname, and the day somebody runs
it once is the day the two have quietly diverged. The redirect removes a surface rather than fixing
a fault.

## The site was tracking its visitors, and said it was not

**Found 2026-08-22, live in production.** Cloudflare Web Analytics was injecting a beacon from
`static.cloudflareinsights.com` on every page load, sending real user measurements. Three lines
above it in the same document, the page's own meta description read **"No account, no server, no
tracking."**

The setting was **"Enable, excluding visitor data in the EU"**, which does not inject for EU
visitors and does for everyone else. It is now **Disable**, verified from outside: zero beacon
references on `/`, `/privacy` and a 404 path, no `<script>` tag of any kind, and `github.com` as
the only external host in the served page.

**Why it went unnoticed, which is the part worth keeping.** Cloudflare injects that script only
when the request carries a browser-like `Accept` header. A `curl` without one is served a clean
page. The same URL, same user agent, differing only in `Accept`, returns HTML with and without the
beacon. **Every check run against this site until now was the version that could not see it**, and
the finding came from a browser network tab instead.

**So a claim about a static site is not settled by reading the static file.** What the repository
contains and what the edge serves are two different things, and only the second one is what
visitors get. Check the served bytes, shaped like a browser.

**`_headers` is now the backstop.** `script-src 'self'` does not permit
`static.cloudflareinsights.com`, so the same injection would be blocked in the browser and show up
as a console error rather than silently working.

## Headers and the 404, which are files rather than dashboard settings

**`_headers` sets the response headers** and every value in it was checked against what these
pages actually load. The site references no external host at all, no fonts, no analytics, no CDN,
no embeds, which is what lets the Content Security Policy be `default-src 'none'` and widen only
to `'self'`.

**One inline style attribute was removed to make that honest.** `privacy.html` carried
`style="padding-bottom:2rem"`, and a single style attribute is the difference between
`style-src 'self'` and `style-src 'self' 'unsafe-inline'`. It is a class now.

**Cloudflare's email obfuscation injects one script** from `/cdn-cgi/`, which is same origin and
covered by `script-src 'self'`. Checked against the live page, because a policy that broke that
script would hide the security contact address, which is the opposite of the point.

**HSTS is set for two years with subdomains and deliberately not preloaded.** Preloading is slow
and awkward to reverse, and `www` does not resolve yet. It is worth doing once `www` works.

**`404.html` exists so that a wrong address stops returning the homepage with a 200.** It did,
which meant every typo looked like a real page. Its links are absolute, because a 404 can be
served at any path depth. **If wrong addresses still return 200 after this deploys**, the Pages
project has single page application routing switched on and that setting has to go.

## What the head carries, and why each line is there

**A canonical on every page, absolute, pointing at the apex.** `www` resolves now, so without this
two hostnames served identical content with nothing saying which was real.

**Open Graph and a Twitter card type.** A link to this site pasted into a chat used to render as a
grey rectangle. `og:image` is **absolute**, which is not optional: a relative one silently fails on
most scrapers and is the usual reason a card looks broken. The dimensions are declared so the first
paste renders at the right shape rather than after a re-crawl. `twitter:card` is separate because
Twitter reads its own type instead of inferring one from Open Graph.

**`assets/card.png`, 1200x630**, on the site's white, showing the account list in an iPhone bezel.
The alternative was icon and words only; the screenshot was chosen because for an app nobody has
heard of it does work a paragraph cannot.

**Icons at the sizes actually requested**, a 32px favicon and a 180px apple-touch-icon, rather than
one 1024px image resized by the browser for every use, plus **an SVG favicon with the PNG kept as a
fallback**. The SVG scales to any size; the PNG stays because Safari only gained SVG favicon support
recently and older versions ignore the line entirely.

**The social card is exempt from `Cross-Origin-Resource-Policy`, and that exemption is the whole
point of it existing.** The security headers were applied to `/*`, which put
`Cross-Origin-Resource-Policy: same-origin` on the card too, telling browsers to refuse it when
loaded from another origin. **The card is the one file on this site whose entire purpose is being
displayed on other people's domains.** The failure was quiet: server side scrapers fetched it fine,
so a link scraped correctly and reported the right `og:image`, and then any preview drawn *by a
browser* showed a broken picture. A diagnostic tool scored the page 92 out of 100 and displayed a
broken image at the same time, which is what led to it.

**`color-scheme: light` stated in markup**, because `style.css` decides it deliberately and a
browser should not have to guess.

**`robots.txt` and `sitemap.xml`** name the apex, which reinforces the canonical rather than
repeating it.

**Internal links point at `/privacy`, not `/privacy.html`.** The latter 308s, so every internal
click was taking a redirect hop to reach the URL the canonical already names.

**Not added: a JSON-LD SoftwareApplication block.** Its useful fields are `aggregateRating` and
`offers`, and this app has neither a rating nor a store link yet. Publishing the markup without
them claims a listing that does not exist. Worth revisiting when the App Store link is real.

## security.txt

RFC 9116, at `/.well-known/security.txt`, served as `text/plain; charset=utf-8`. Verified from
outside on 2026-08-22.

**`/security.txt` at the document root returned the homepage with a 200**, because the Pages
project had no 404 page. A scanner asking for a text file got HTML, which reads as no security
contact at all. `_redirects` now sends that path to the real file.

## Google Search Console

Verified 2026-08-22 as a **Domain property**, which covers the apex, `www`, and both protocols in
one, and `sitemap.xml` is submitted.

**Verified by DNS, deliberately.** Search Console offers three methods and the other two put
something on the site: an HTML file at the document root, or a Google `<meta>` tag in the page
head. Neither tracks anybody, but **DNS verification leaves what visitors receive completely
untouched**, which is the only version of this consistent with the rest of these pages.

**Do not delete the `google-site-verification=` TXT record at the apex.** Google re-checks it
periodically and removing it un-verifies the property. It looks like clutter and it is not.

**This is not analytics and the distinction is not a technicality.** Search Console reports
Google's own data about how this site appears in Google's search results: which queries showed it,
what was clicked, what failed to crawl. It ships no script and collects nothing from visitors. The
beacon removed the same day did the opposite, and the two should never be filed together.

**What makes a page indexable here is a three way agreement**, checked after setup: the URL in
`sitemap.xml`, the canonical on the page, and the URL that returns 200 are identical with no
redirect between them. If those ever disagree, that is the first thing to look at.

## The privacy page is not a template

`privacy.html` is a statement by ReVeNG System to the people who install the app it publishes. A
fork must not ship it unedited; it would make promises in someone else's name about software they
did not build. The same applies to `index.html`, which is this project's positioning rather than
a starting point for anyone else's.
