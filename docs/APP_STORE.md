# App Store metadata

Everything App Store Connect asks for, written down so it is reviewed here rather than typed
into a web form at submission time and never seen again. Part of PR 18.

**Nothing here is submitted yet.** The app is `1.0 (4)` on TestFlight and has not been through
gate A4, so this is a draft to argue with, not a listing to paste.

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

Seven iPhone screenshots and **two Apple Watch screenshots are uploaded to App Store Connect**,
confirmed in the listing on 2026-08-22. The stale claim that the watch shots gated a submission
survived in this document and in `HANDOFF.md` for three days after it stopped being true, and then
**this section said "taken" where the iPhone line said "uploaded"**, which left the question open
for another four days. Two verbs in one sentence, meaning two different things, and nobody could
tell from the outside which one was accurate.

**Three of them are also on the site now**, in Apple's iPhone 17 and Watch Ultra 3 bezels. They
are the same images, so the shop window and the landing page show the same app.

**The site and the store lead with different account list screenshots, and that is settled rather
than drift.** The site uses the light capture; **the store keeps the dark one, decided 2026-08-22.**

The case for changing it was that the dark capture is scrolled mid-card, so its top card shows a
six digit code with the label behind the translucent nav bar, and the store's first frame is the
one most people ever see.

**The case for keeping it won, and it rests on something a repository cannot check.** The dark
frame matches the app icon, and at full resolution on a real device it shows the material effect
that a downscaled comparison render flattens away. That was judged on the hardware the screenshot
came from. **Recorded here so it is not re-raised as an inconsistency**: the two differ on purpose.

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
| Subtitle | `Open source 2FA, no account` | 30 character limit, 27 used. See below |
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

Drawn from `README.md` so the two cannot drift into different claims.

**The block below is hard wrapped for this file and must not be pasted that way.** App Store
Connect treats every newline literally, so pasting the wrapped form puts a break in the middle of
most sentences. Paste it with each paragraph on one line and the blank lines between paragraphs
kept. It is 2,042 characters of the 4,000 allowed.

```
OpenFactor is a minimal authenticator for people who want an open source app with no account,
no backend, and nothing holding their accounts hostage.

It generates two factor authentication codes on iPhone and Apple Watch.

It has no account to create, no server, no browser extension, and no analytics. Your accounts
stay on your devices. If you turn on iCloud sync, encrypted account records travel through
iCloud Keychain. The key that decrypts them stays on your devices.

Accounts are encrypted before they are stored. The key that opens them stays in the app's
private container on each device, is never synced, is never written to the Keychain, and is
excluded from device backups.

DESIGN PRINCIPLES

No account.

No backend.

No telemetry.

Open source.

Exports you can take elsewhere.

WHAT IT DOES

Generates TOTP and HOTP codes to the published standards, verified against the test vectors in
those specifications.

Shows one code at a time on Apple Watch, and keeps working with your iPhone off, absent, or out
of range.

Imports from other authenticators, including Google Authenticator transfer codes and Aegis
vaults, and can read a setup code straight from the Camera app or a screenshot.

Exports an encrypted backup whose format is public and documented, or a plain file for moving to
another app. The difference is stated on screen, because portability should not require hiding
the security cost.

Locks behind Face ID, Touch ID, or your passcode.

WHAT IT DELIBERATELY DOES NOT DO

No Mac app and no browser extension. A second factor is worth less the moment it lives on the
machine asking for it.

No password storage and no autofill. This is an authenticator, not a password manager.

No accounts, no telemetry, no crash reporting.

OPEN SOURCE

The source is public and built in the open from the first commit, including the design
documents, the security reviews, and the hardware experiments behind them, with the findings
published whether or not they were flattering. Read it at github.com/dragut-eth/openfactor
```

**A claim was removed here, and the reason generalizes.** The description said iCloud Keychain
carries your accounts "where Apple cannot read them". That is defensible, being Apple's own
description of the service and doubly true once the vault means only ciphertext syncs. It is
still gone, because it is a claim about someone else's platform rather than about this app.

The replacement says what OpenFactor's own design guarantees: encrypted records travel, the key
that decrypts them does not. That is provable from this repository alone. **Every important claim
in a listing should be one the project can prove from its own design**, because a platform
property can change without warning and takes the sentence with it.

## Promotional text

170 characters, editable without submitting a new build, which makes it the right place for a
status that changes.

```
No network, no accounts, no telemetry, no third-party code. Every review published. Not independently audited yet, so keep a tested backup, as with any authenticator.
```

That is 166 characters, and it is the compressed form of the paragraph `README.md` and the site
both open with. **It leads with what the app does rather than with what it lacks**, which is the
same order and for the same reason.

**Why that order, since an earlier draft had it the other way.** Opening with "no independent
audit" is accurate and reads as a confession, and a reader who stops at the first line leaves with
only the warning. **The audit gap is not a counterweight to the transparency, it is another
instance of it**: the same paragraph that says the unflattering findings are published then
publishes an unflattering fact. Written in that order it needs no "but", because the two halves are
not in tension.

**And the closing advice is deliberately about authenticators in general.** "Keep a tested backup"
is true of every one of them, and framing it as a confession specific to this app would be both
scarier and less useful than framing it as the thing anybody should do.

**It used to open with "Beta, in testing" and that had to go.** App Review does not accept an app
that presents itself as a beta, a trial or a demo, and the word would have been a rejection on
metadata rather than on anything the app does.

**What is worth noticing is that removing it cost nothing.** "Beta" was a statement about a release
phase, which stops being true the day this ships. **The sentence underneath it is about the audit
gap, and that stays true until somebody outside this project looks at the code.** The same
substitution was made in `README.md` and on the site, so all three surfaces now lead with the thing
that will still be accurate next year.

## What's New, for 1.0

```
First release.

Two factor codes on iPhone and Apple Watch, with accounts encrypted before they are stored.
Import from other authenticators, encrypted backups you can take elsewhere, and an app lock.
```

Release notes for later versions belong in a changelog rather than being invented at submission
time. There is no `CHANGELOG.md` yet; PR 18 says there should be, and it should be written from
the commit history rather than from memory.

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

Security vulnerabilities: see SECURITY.md in the repository, which asks for private disclosure
through GitHub Security Advisories. Email works if you cannot use that, though it is not
encrypted, so say only that you have found something and let the details follow through the
private channel.

## Changes

This policy is versioned with the source. Its history is visible in the repository.
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

The wording used instead is concrete without the claim: the design documents, the security
reviews, and the hardware experiments behind them, published whether or not they were flattering.
When PR 17 lands and the threat model is complete, this sentence should change and this paragraph
should be deleted.

## What this document is not

It is not the submission checklist. `SECURITY.md` still describes an app with no professional
independent audit, and `README.md` says not to trust it with an account you cannot recover.
Metadata being ready changes none of that. **This paragraph said "Gate A4 comes first" until
2026-08-22**, five days after A4 concluded, which is the third status line in this repository found
outliving its facts in two days.
