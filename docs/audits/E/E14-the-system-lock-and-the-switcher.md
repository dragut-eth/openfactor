# E14: does iOS's per-app Face ID lock remove the app switcher exposure?

**Yes, completely, and from the first frame.** With the system per-app lock enabled on
OpenFactor's icon and this app's own App Lock switched **off**, the zoom out from the home screen
never shows a previous screen: the card carries iOS's own "Face ID Required to open OpenFactor"
placeholder from the moment it begins to expand. The app switcher card is the same.

**Measured on Xavier's iPhone 15 Pro, 21 August 2026.** A 2.48 second screen recording at
1180 by 2556, plus a still of the app switcher.

## Why it was run

**Because the project had asserted it twice and measured it zero times.** `docs/APP_LOCK.md`
records an exposure PR 15b measured and accepted: roughly a sixth of a second of the previous
screen, showing an issuer and an account name, in the zoom out from the home screen. It is a cache
iOS captures and the app cannot reach.

During gate A4's reply round, the maintainer said the system lock is the stronger protection and
that an app cannot enforce it. A reviewer then said the same thing. **Two people agreeing is not a
measurement**, and this folder's standard is that a claim resting on reasoning is marked as
reasoning. So it was left as an open question in `docs/APP_LOCK.md` rather than written up as an
answer, and this is that question run.

## The configuration

| | |
| --- | --- |
| OpenFactor's own App Lock | **off** |
| iOS per-app lock | **on**, set by holding the app icon and choosing Require Face ID |
| Action | launch from the home screen, then authenticate |

**The app's own cover is not what is being tested here.** With App Lock off, the app is in the
configuration most people are in, and the question is what the system does around it.

## What the frames show

The recording was sampled twice. **Once across the whole clip at ten frames a second**, and then
**again across the transition at sixty frames a second**, from 0.15 to 0.75 seconds, because the
exposure being looked for is about a sixth of a second and would span roughly ten frames at that
rate. Thirty six frames cover that window.

| Frames | What is on screen |
| --- | --- |
| before the tap | the home screen, OpenFactor's icon among the others |
| the first frame of the expanding card | already black, already carrying "Face ID Required to open OpenFactor" |
| every frame until authentication | the same placeholder, then black while Face ID runs |
| after authentication | the account list |

**No account content appears at any point between the home screen and the authenticated app.** Not
a partial frame, not a blurred one. The exposure is not reduced; there is no window for it to
happen in.

**The app switcher still is the same picture**: the OpenFactor card fully covered by the system's
placeholder rather than by this app's cover.

## Why it behaves this way, and the limit of that explanation

**The system appears to replace the snapshot pipeline for a locked app rather than covering it
afterwards**, which is why there is no interval to leak in. An app's own cover is necessarily a
reaction: it is raised in response to a lifecycle event, and the cache in question is captured by
the system on its own schedule. **That part is reasoning and is marked as such.** What was measured
is the absence of the exposure, not the mechanism behind it.

## What this does not establish

**Nothing about the vault key.** The system lock gates opening the app. It does not change that the
vault key is a Complete Protection file readable by the process whenever the device is unlocked,
which is the separate finding all three reviewers of gate A4 reached independently.

**Nothing about other authenticators.** Whether a peer leaks the way this app does with the system
lock off is still unmeasured, and two opposite claims about it are on the record with no evidence
behind either. That half of `docs/APP_LOCK.md`'s open measurement stays open.

**Nothing about defaults.** The system lock is off until somebody turns it on, and **an app cannot
enable it, prompt for it, or detect it.** The only thing this app can do about it is say it exists.

**One device, one OS version, once.** The same caveat every measurement in this folder carries.

## Reproducing it

**No second app, no second device, no signing.** Hold the OpenFactor icon on the home screen,
choose Require Face ID, turn this app's App Lock off in Settings, start a screen recording, return
to the home screen, and launch the app. Then step the recording frame by frame through the zoom.
That is the whole method, which puts this in a different class from every other probe in
`README.md`'s table.

**The recording and the switcher still are not in this repository.** They show the maintainer's
home screen and their own accounts. The frames that carry the finding contain nothing but a black
card and Apple's own text, and the finding is reproducible in about two minutes by anybody holding
an iPhone, which is worth more than a published artifact.
