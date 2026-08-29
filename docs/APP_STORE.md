# App Store metadata

Everything App Store Connect asks for, written down so it is reviewed here rather than typed
into a web form at submission time and never seen again. Part of PR 18.

**Submitted for review on 2026-08-23, as `1.0 (7)`.** Gate A4 concluded on 2026-08-21 and X1, a
blind unscoped external audit, ran on 2026-08-22. **This document stopped being a draft to argue
with and became the record of what was entered**, so a change here now means a change in App Store
Connect rather than instead of one.

**It said "nothing here is submitted yet, the app is 1.0 (4) and has not been through gate A4"
until the moment of submission**, which was three builds and one gate out of date. A status line at
the top of a document is the last thing anybody rereads.

**The rule this document exists to enforce.** A store listing is the one place where a project
like this one quietly starts over-claiming, because the form invites a sales pitch and nobody
diffs it against `SECURITY.md`. So: **no sentence here may claim more than the repository already
claims.** In particular the listing must not say audited, must not say unbreakable, and must not
imply the vault has been reviewed by anyone independent. `README.md` carries a status warning and
this listing carries the same one, in the promotional text where it can be updated without a
review cycle.

## The URLs, and where the claims on them come from

**The privacy policy URL is `https://openfactor.dev/privacy`.** Given without the extension
deliberately: `/privacy.html` serves a 308 redirect to it, and Apple should be handed the
destination rather than the redirect.

That sits oddly beside the first principle, "no OpenFactor servers", so it is worth saying
plainly why it does not break it: a static document served by a CDN is not a backend the app
talks to. The app still makes no network requests. What the URL costs is a page someone must
keep current, not an operational service.

The page won over `PRIVACY.md` at a GitHub URL because the same host was needed for the marketing
URL anyway, and one page that can expire is better than an inconsistent pair. The draft at the
end of this document is what `site/privacy.html` was built from.

**The marketing URL is `https://openfactor.dev`.**

**The support URL stays `https://github.com/dragut-eth/openfactor/issues`.** This was reconsidered
when the site went up and deliberately not changed: the site carries no support content, and what
Apple asks for is a page where a person can actually get help.

**But every route on that page needed a GitHub account, which is a real gap for an App Store
app.** Somebody who installs this and has a question should not have to sign up for a developer
platform to ask it. **`info@openfactor.dev` is on the site and on the privacy page**, and it needs
nothing of anybody. **`security.txt` names `security@openfactor.dev` instead**, because RFC 2142
defines that address for vulnerability reports and a researcher will guess it first; both forward
to the same person. The issues page stays the better route for a
bug, because the answer is then public and searchable, and the email is the route for everything
and everyone else.

### The site derives from the repository, never the reverse

There are now three surfaces carrying the same claims: `README.md`, the App Store listing, and
`openfactor.dev`. They agree today for one reason only, which is that the site was built by
copying sentences out of the first two rather than writing them fresh.

**So a claim changes in `README.md` or `SECURITY.md` first, and the site and the listing follow.**
Never the other way round. The failure this rule exists to prevent is somebody softening or
sharpening a sentence on the website because it reads better there, and the website quietly
becoming the one surface that over-claims. It is the same rule as the one at the top of this
document, extended to the surface that did not exist when that rule was written.

### Screenshots

Six iPhone screenshots and **two Apple Watch screenshots are uploaded to App Store Connect**,
confirmed in the listing on 2026-08-29. It was seven until the duplicate account list was dropped,
so that the first two frames are different screens rather than the same one twice.

The stale claim that the watch shots gated a submission
survived in this document and in `HANDOFF.md` for three days after it stopped being true, and then
**this section said "taken" where the iPhone line said "uploaded"**, which left the question open
for another four days. Two verbs in one sentence, meaning two different things, and nobody could
tell from the outside which one was accurate.

**Three of them are also on the site now**, in Apple's iPhone 17 and Watch Ultra 3 bezels. They
are the same images, so the shop window and the landing page show the same app.

**The site and the store lead with different account list screenshots, and that is deliberate
rather than drift.** The site uses the capture with the full palette. **The store leads with a
capture in which every card is the default blue, decided 2026-08-29.** The dark capture that used
to open the store set has been withdrawn from it.

**Recorded here so it is not re-raised as an inconsistency**: the two surfaces differ on purpose,
and the store's frame is the one that changed.

The App Store frames are the one place people will look at this app before installing it, and the
vault setup screen is a strange first impression: the list with real codes is what to show.

**Watch screenshots cannot be produced in a simulator by the obvious route**, and the reason is
recorded under the findings in `HANDOFF.md`: accounts reach the watch through iCloud Keychain,
which simulators do not sync, so a simulated watch sits on "No accounts yet" forever even after a
successful provisioning handshake. That is not flakiness and no amount of retrying fixes it.

## App information

| Field | Value | Note |
| --- | --- | --- |
| Name | `OpenFactor` | 30 character limit, well under |
| Subtitle | none | Left empty on purpose. The field allows 30 characters |
| Primary category | Utilities | Where authenticators sit |
| Secondary category | Productivity | Optional, and low value; leaving it empty is defensible |
| Age rating | 4+ | No objectionable content, no web views, no user generated content |
| Copyright | `2026 ReVeNG System` | The publishing entity, which must match the Apple Developer account exactly |
| Content rights | No third party content | No issuer logos ship: the asset catalog holds the accent color and three app icon sets |
| Price | Free | |
| Availability | All territories | Nothing here is region specific |

**Not "Security" as a category**, because Apple does not offer one and Utilities is where every
comparable app is found.

**The store copyright and `LICENSE` name different holders on purpose.** `LICENSE` says
`OpenFactor contributors`, which covers the source and stays collective so contributions need no
reassignment. The store field covers the published app and names who publishes it. Nothing to
reconcile between them, but the privacy policy is a statement by that same publishing entity and
should name it, which the draft below does not yet do.

**The subtitle was chosen against the competition rather than in the abstract.** Four listings
were read for what they actually do with the field:

| App | Name | Subtitle |
| --- | --- | --- |
| Step Two | Step Two | Simple two-step verification |
| Microsoft Authenticator | Microsoft Authenticator | Protects your online identity |
| Ente Auth | Ente Auth - 2FA Authenticator | Secure sync across devices |
| Raivo | Raivo - 2FA Authenticator app | tOTP, OTP & MFA Authentication |

Two things follow. **The category word lives in the name for most of them**, which is why Ente and
Raivo can spend the subtitle on something else, and it is a disadvantage we carry:
`OpenFactor` is indexed as a brand and nothing more, so the subtitle is the only high weight
field that can say what the app is. And **"2FA" is the term people type**. The polished listings
write it out in prose, but the searches are on the abbreviation.

So the subtitle does both jobs in 27 characters: `2FA` is what it is, and `Open source` and
`no account` are the two things none of those four claim. It is not keyword duplication, because
Apple weights the subtitle above the keyword field, so a term promoted out of keywords into the
subtitle ranks better than the same term sitting in keywords alone.

The alternatives considered, if this reads wrong: `Open source, no account`, `Open source
authenticator`, `Offline two factor codes`.

## Keywords

100 characters, comma separated, no spaces after commas, and the app name is indexed separately
so repeating it wastes the budget.

```
totp,otp,authenticator,two-factor,hotp,mfa,two-step,verification,offline,watch,backup,import,export
```

That is 99 characters.

**`2fa` and `open source` were removed from this list when they moved into the subtitle.** Apple
indexes name, subtitle and keywords as one pool and weights them in that order, so a term in both
the subtitle and the keywords is not indexed twice, it just spends 16 characters of the smaller
budget saying something the higher weighted field already says. Removing them freed room for
`mfa`, `two-step` and `verification`.

`two-step` and `verification` are separate entries rather than one phrase on purpose, because
Apple combines keywords across the list into phrases. Two entries match "two-step verification"
and also match each word alone.

Deliberately absent: any competitor's name, which Apple rejects, and "secure" and "private",
which are claims rather than search terms.

## Description

**Entered in App Store Connect on 2026-08-23, and this is the text that was pasted.** Drawn from
`README.md` so the two cannot drift into different claims.

**Not hard wrapped.** App Store Connect treats every newline literally, so a wrapped block puts a
break in the middle of most sentences. Each paragraph and each bullet is one line, with blank lines
only between blocks. It is 1811 characters of the 4,000 allowed.

```
OpenFactor generates two-factor authentication codes on iPhone and Apple Watch. No account, no server, no analytics, no third-party code.

Your accounts are encrypted before they are stored. The key that opens them lives in the app's private container on each device, is never synced, is never written to the Keychain, and is excluded from device backups. If you turn on iCloud sync, the encrypted records travel through your own iCloud Keychain and the key does not go with them.

DESIGN PRINCIPLES
· No backend to breach, subpoena, or shut down.
· No telemetry.
· Built in the open from the first commit.
· Your accounts are yours to take elsewhere.

WHAT IT DOES
· Generates TOTP and HOTP codes to the published standards, verified against the test vectors in those specifications.
· Shows one code at a time on Apple Watch, which keeps working with your iPhone off, absent, or out of range.
· Imports from other authenticators, including Google Authenticator transfer codes and Aegis vaults. Scan a setup code with the Camera app, open one from an image, or share an image straight into OpenFactor without saving it to Photos first.
· Exports an encrypted backup whose format is public and documented, or a plain file for moving to another app. The difference is stated on screen, because portability should not require hiding the security cost.
· Locks behind Face ID, Touch ID, or your passcode.

WHAT IT DELIBERATELY DOES NOT DO
· No Mac app and no browser extension. A second factor is worth less the moment it lives on the machine asking for it.
· No password storage and no autofill. This is an authenticator, not a password manager.

OPEN SOURCE
· The source is public, including the design documents, review findings, and hardware experiments behind them. Read it at github.com/dragut-eth/openfactor
```

### What changed on 2026-08-23, and why

**The opening line stopped defining the app by its audience.** It read "an authenticator for people
who want an open source app with no account, no backend, and nothing holding their accounts
hostage", which is market positioning rather than description, and it spent the first line on three
absences before ever saying the app makes codes. That did not arrive until the second paragraph,
below the fold. It now says what the app is in the first eight words.

**Two paragraphs went, because the new opening made them repeat.** "It generates two factor
authentication codes on iPhone and Apple Watch" was saying the first line again one line later,
and the old third and fourth paragraphs both claimed the key stays put, in different words. The
storage explanation is said once now, with the sync explanation beside it.

**The bullets are real bullets.** They were blank-line separated lines, which App Store Connect
renders as loose paragraphs rather than a list.

**Every factual claim was checked against the code rather than carried forward on trust**, which
found nothing wrong but is the reason to say so: `AegisImport` and `AegisExport` both exist;
`WatchAccountListView` shows names while `WatchCodeView` shows a single code, so "one code at a
time" is accurate; `docs/VAULT.md` records that operation never needs the phone after provisioning;
App Lock is `.deviceOwnerAuthentication`, which is biometrics with a passcode fallback; and the
plaintext export sits behind an explicit "I understand this file is not encrypted" toggle.

**The audit caveat is not in the listing, and that is a decision rather than an oversight.** It
lived in the promotional text, which is now empty, and it was deliberately not moved into the
description. `README.md`, `SECURITY.md` and the site all still carry it. **This breaks no rule
here**: the rule at the top of this document forbids the listing claiming *more* than the
repository, and saying less is not that. It does make the App Store page the quietest surface about
it, which is worth knowing rather than rediscovering.

## Where each claim lives, and why the surfaces differ

**The three surfaces answer different questions.** The App Store page answers what the app is.
`openfactor.dev` answers why anybody should believe it. The repository answers prove it. The
audience narrows at each step, and so does the question.

**That is why the audit caveat is not in the listing.** It is not an answer to "what is this", and
a reader at that stage cannot act on it: they cannot evaluate what a professional audit would have
found. It is on the site, in `README.md` and in `SECURITY.md`, where the question it answers is the
one being asked.

**The rule this does not break.** No surface may claim more than the repository claims. That is a
ceiling, not a requirement that every surface say the same amount. Every drift found in this
project has been a contradiction or an overclaim, never one surface saying less than another.

**The URL fields already encode it.** Marketing URL goes to `openfactor.dev`, support URL to the
GitHub issues, and the description text to the source. A browsing reader is sent to the site;
somebody with a problem is sent to the repository.

**The one caution.** Readers do not respect the order. Anybody reading adversarially starts at the
App Store, because it is the most quotable and least contextualised page, so the ceiling matters
most on the widest surface rather than least.

## Promotional text: deliberately empty

**170 characters, editable without submitting a new build, and left blank on 2026-08-23.**

**The reason is that it renders as one block with the description**, immediately above it, and
nothing on the page marks the seam. A draft carried "No network, no accounts, no telemetry, no
third-party code" and the description then opened with "No account, no server, no analytics, no
third-party code": **the same list twice inside three hundred characters, with the reader not
learning what the app is until the fourth sentence.**

**Splitting the jobs was tried first and worked.** The promotional text would carry only what
changes, the audit status, and the description only what does not. That is what the field is for:
Apple's own guidance is "the latest news about your app", and it updates without a build.

**It was dropped anyway, and the trade is worth recording.** One fewer surface to keep in step,
against losing the one place the audit caveat appeared above the fold. The caveat is not in the
description either, which makes the App Store listing the only surface that does not carry it.
`README.md`, `SECURITY.md` and `openfactor.dev` all still do.

**If it is ever filled in, it must not repeat the description's opening.** They are read as one
paragraph, and the only way to know where one ends is that the writing stops making sense.

**It used to open with "Beta, in testing" and that had to go.** App Review does not accept an app
that presents itself as a beta, a trial or a demo, and the word would have been a rejection on
metadata rather than on anything the app does. Removing it cost nothing: "beta" was a statement
about a release phase, which stops being true the day this ships.

## What's New: there is no such field for a first release

**App Store Connect does not offer release notes on a first submission**, and there was nowhere to
put the block this document carried until 2026-08-23. It had been drafted without anybody looking
at the form.

**It was raised and half acted on.** The same message that said "remove the mention of beta,
App Store does not accept a beta application" also said release notes are not available on a first
release. The beta half was fixed that day. This half was not, and survived until it was noticed
again at submission.

**The drafted text is deleted rather than saved for the first update.** It read "First release. Two
factor codes on iPhone and Apple Watch, with accounts encrypted before they are stored", which
describes the app rather than a change. Release notes for an update say what changed, so none of it
would have survived anyway.

**Release notes for later versions belong in a changelog** rather than being invented at submission
time. There is no `CHANGELOG.md` yet; PR 18 says there should be, and it should be written from the
commit history rather than from memory.

## App Privacy, the nutrition label

App Store Connect asks this separately from the privacy manifest and does not read the manifest
to answer it. Both must say the same thing, so here is the mapping.

| Question | Answer | Why |
| --- | --- | --- |
| Do you or your third party partners collect data from this app? | **No** | Nothing leaves the device. iCloud Keychain sync is Apple's transport, chosen by the person, and is not collection by this app |
| Tracking | **No** | `NSPrivacyTracking` is `false` and there are no tracking domains |
| Third party SDKs | **None** | No third party dependencies at all, which `Package.swift` enforces and CI checks |

Answering "No data collected" produces the "Data Not Collected" label, which is the strongest
one available and the only one consistent with `OpenFactor/PrivacyInfo.xcprivacy`.

**A trap worth naming.** The form asks about data collected *by the app or its partners*, not
about data the app stores locally. Account secrets are stored, not collected. Answering yes
because the app "handles sensitive data" would be wrong and would attach a data type to this
listing that never leaves the phone.

## The privacy manifest, and the check that now guards it

**Resolved.** `OpenFactor/PrivacyInfo.xcprivacy` declared one required reason API,
`UserDefaults` with `CA92.1`, which was complete when written and stopped being complete when
`SharedInbox` gained its freshness window. `SharedInbox.pending()` reads a file's modification
date to sort what the share extension left newest first, and file timestamps are a required
reason category in their own right:

```swift
let arrived = (attributes?[.modificationDate] as? Date) ?? .distantPast
```

The manifest now declares `NSPrivacyAccessedAPICategoryFileTimestamp` with `C617.1`.

**Verified against Apple's published list rather than a summary of it**, because a manifest
declaring the wrong reason is worse than one declaring none: it reads as though somebody
considered the question. Two things were confirmed at the source. `modificationDate` and
`NSFileModificationDate` are named in the file timestamp category, alongside the `getattrlist`
and `stat` family. And `C617.1` is the reason for timestamps of files inside the app container,
an app group container, or a CloudKit container, which is the inbox verbatim. The neighbouring
codes are different cases rather than near misses: `DDA9.1` is displaying a timestamp to the
person, and `3B52.1` is a file they picked themselves through a document picker.

A first pass at reading Apple's data paired each reason code with the wrong text, because the
codes sit **after** the prose they belong to. The pairing that shipped was checked in document
order, which is the only reason the manifest does not now say `DDA9.1`.

**The whole codebase was swept, not just the reported line.** One file timestamp call site, in
`SharedInbox`. No system boot time, no disk space, no active keyboard. `UserDefaults` appears in
six files rather than the three first reported, which changes nothing because it was already
declared. The share extension declares nothing of its own: it only writes to the inbox, and
reading the timestamp happens in the app.

**CI now fails when a required reason API appears in source without a matching manifest entry.**
This defect was invisible by construction. It built, it ran, it passed every test, and it would
have surfaced as an automated notice from Apple at upload, which is the worst moment to find it.
It also arrived by addition rather than by edit, so no review of a diff would have caught it
either. The check parses the manifest rather than grepping it, for the reason the share
extension's entitlement check records: the comments in that file name the very categories it
declares, so a grep would pass while lying. It was proved in both directions, against the real
tree and against a copy with the entry removed.

Only one direction is checked. A declared category that is no longer used is untidy rather than
a submission problem, and failing on it would make the check argue with anyone deleting code.

## Export compliance

App Store Connect asks this on every build, and the answer has been clicked through by hand each
time. Writing it down once is most of the value.

**What the app actually uses**, so the question is answered from fact rather than instinct:

- AES-256-GCM, HKDF, HMAC, SHA-256 and P-256 ECDH, all from Apple's CryptoKit.
- PBKDF2 from CommonCrypto, because CryptoKit has no password based key derivation.
- No cryptography implemented in this repository except RFC 4226 dynamic truncation, which is
  arithmetic on an HMAC output and is not encryption.

So the app **does** use encryption, and the "no encryption" answer is wrong.

**Whether it qualifies for an exemption was a determination for Xavier, not for me.** The usual
route for an app in this shape is the exemption for software using only encryption available in
Apple's operating systems, with no proprietary or non standard implementation, but that is a legal
classification with export consequences and it should not be settled by an assistant's confidence.
What can be said without qualification is the list above, and that it is complete.

**Decided on 2026-08-21: exempt.** `ITSAppUsesNonExemptEncryption` is `false` in
`OpenFactor-Info.plist`, with the facts it rests on repeated in a comment beside it. App Store
Connect stops asking on every upload, and **the answer is versioned with the source rather than
re-entered by hand**, which means it cannot quietly diverge from what was decided.

**If the cryptography ever changes, that key is part of the change.** The comment in the plist says
so, because a determination recorded once and never revisited is how a true answer becomes a false
one.

## Draft privacy policy

For `PRIVACY.md` at the repository root, if that is the option chosen above. Written to be true
rather than to be short, and deliberately not in legal boilerplate, since a policy nobody reads
protects nobody.

```markdown
# Privacy policy

OpenFactor collects no data.

There is no OpenFactor account, no OpenFactor server, and no analytics, crash reporting, or
telemetry of any kind. The app makes no network requests of its own. This is checked
automatically: continuous integration searches every source file for networking and logging
code and fails the build if any appears.

OpenFactor contains no crash reporting code. iOS can send crash logs to any app's developer if you
have Share iPhone Analytics turned on. That is a setting in Privacy and Security, not something
this app does, and not something it can turn off for you.

## What is stored, and where

Your accounts and their secrets are stored on your devices, encrypted, in the iOS Keychain. The
key that decrypts them is held in the app's private container on each device. It is never
synced, never written to the Keychain, and never included in a device backup.

Your preferences, meaning sort order, appearance, chosen icon, whether sync is on, and the app
lock settings, are stored on the device. They never include an account name or a secret.

## iCloud

iCloud sync is off until you turn it on. When it is on, your encrypted accounts are offered to
iCloud Keychain, which is Apple's service and is end to end encrypted. OpenFactor does not
operate it and cannot read what it carries. Apple's own privacy policy governs it.

Turning sync off stops offering new changes to iCloud Keychain and returns the accounts on that
device to device only protection.

## Sharing

Nothing is shared with anyone. There are no third party libraries in this app, so no other
company's code runs inside it.

When you export a backup, that file is yours and goes wherever you send it. When you import
one, it is read on the device.

## Children

The app collects no data from anyone, including children.

## Contact

Questions, problems and anything else: info@openfactor.dev

Bugs and feature requests are better as issues at
https://github.com/dragut-eth/openfactor/issues, where the discussion is public and searchable,
but the address needs no account and reaches a person.

Security vulnerabilities: see
[SECURITY.md](https://github.com/dragut-eth/openfactor/blob/main/SECURITY.md), which asks for
private disclosure through GitHub Security Advisories. security@openfactor.dev works if you cannot
use that, though it is not encrypted, so say only that you have found something and let the details
follow through the private channel.

**The address here is `security@`, not `info@`.** RFC 2142 defines `security@` for exactly this, so
it is what a researcher guesses before reading anything, and `security.txt` names it. This
paragraph said only "email", which resolved to the `info@` in the paragraph above and disagreed
with `security.txt` from the moment that file changed. Both forward to the same person; the point
is that the surfaces say the same thing. `info@` remains the address for everything that is not a
vulnerability.

## Changes

This policy is versioned with the source. Its
[history](https://github.com/dragut-eth/openfactor/commits/main/site/privacy.html) is visible in the
repository.

**A link rather than a date and a version number**, which is the conventional thing and the weaker
one. A version number says a change happened. That page says what changed, when, and why, with the
diff, and it cannot be back-dated without the history showing it. For a document whose credibility
rests on being checkable, the checkable option wins.
```

## A claim removed after PR 15b measured it

The description said the app "never lets a code appear in the app switcher". That is gone, at
Xavier's direction, and the reason belongs on the record because it is the rule at the top of
this document working as intended.

PR 15b's checklist found that iOS keeps a second snapshot cache, the one behind the zoom from the
home screen, written at a moment the cover is not up. A screen recording read frame by frame
showed the previous screen for roughly a sixth of a second before the lock appeared. The finding
is accepted rather than fixed, and written up in `docs/APP_LOCK.md`.

**A narrower sentence would still be true**, since the switcher card itself, the artifact anyone
can browse to, does stay blank. It is still not in the listing. A store description is read once,
by somebody deciding whether to trust the app, and "never" is what they will remember rather than
the qualification. The lock is worth mentioning; the guarantee is not ours to make.

**This is the third time the same shape of error has been caught here**, after the Photos claim
and the App Group justification. Each was written from what the design intended rather than from
what had been measured, and each was narrowed by somebody who had looked. The rule at the top of
this document is not decoration.

## Entered into App Store Connect, and what still gates a submission

The text fields were entered on 2026-08-18, field by field, against the `dev.openfactor.app`
listing: subtitle, promotional text, keywords, description, categories, age rating, content
rights, copyright, the support and marketing URLs, and the review notes. Everything in this
document that is a value to paste is now in the form.

**No build is attached and none should be yet.** This is metadata work, well ahead of a
submission. Attaching a build is the last step, once there is one worth shipping and the export
compliance call has been made.

**Nothing in this document gates a submission any more.** Both things that once did are closed:

- **Apple Watch screenshots** exist and are uploaded, two of them.
- **The export compliance answer** was decided exempt on 2026-08-21 and is now carried by
  `ITSAppUsesNonExemptEncryption` in the plist. **Build 6 came back from App Store Connect with
  `usesNonExemptEncryption = False` already set**, so the question is not asked on upload at all.
  Versioning the answer with the source rather than clicking it each time paid off on its first
  build.
- **App Privacy** was published on 2026-08-22 as "Data Not Collected", which matches
  `OpenFactor/PrivacyInfo.xcprivacy`: no collected data types, tracking false, and two
  required-reason API declarations that are not collection and correctly do not appear.

**The privacy policy URL no longer gates anything.** It is `https://openfactor.dev/privacy`,
live, and recorded above with the marketing URL.

The copyright was entered as `2026 ReVeNG System`, the publishing entity, which must match the
Apple Developer account.

## Review, and the one suggestion declined

This document was reviewed externally on 2026-08-17. Seven suggestions were taken, most of them
above. Two are worth recording because of what they say about the failure mode this document
exists to prevent.

**The one that mattered: "Apple cannot read them".** The reviewer said an important claim should
rest on OpenFactor's own design rather than on a platform property, and they were right. Worse,
this document had already flagged that sentence as "the one claim worth checking" and then kept
it anyway. Flagging a risk is not the same as acting on one, and a note that says "worth
checking" will be read later as "checked".

**The one declined: describing the published material as a "threat model".** The suggestion was
to replace "the findings from each review" with "design documents, threat model, and security
reviews", on the grounds that it is more concrete. It is more concrete and it is not yet true.
`SECURITY.md` opens by saying the threat model is incomplete and that PR 17 completes it. Putting
the phrase in a store listing would claim a finished artifact that does not exist, which is
exactly what the rule at the top of this document forbids, and the fact that the suggestion came
from a review does not exempt it.

The wording used instead is concrete without the claim: the design documents, the review findings,
and the hardware experiments behind them. When PR 17 lands and the threat model is complete, this
sentence should change and this paragraph should be deleted.

**"Published whether or not they were flattering" is no longer in the listing either.** It moved
into the promotional text while that field was being drafted and did not come back when the field
was abandoned. The claim is still made in `README.md` and on the site, and it is still true of
`docs/audits/`; the App Store description simply does not make it.

## What this document is not

It is not the submission checklist. `SECURITY.md` still describes an app with no professional
independent audit, and `README.md` says not to trust it with an account you cannot recover.
Metadata being ready changes none of that. **This paragraph said "Gate A4 comes first" until
2026-08-22**, five days after A4 concluded, which is the third status line in this repository found
outliving its facts in two days.
