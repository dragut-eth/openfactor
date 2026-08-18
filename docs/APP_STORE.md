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

## Blocked, and these need decisions rather than drafting

**A privacy policy URL is required** and the project has none. App Store Connect will not accept
a submission without one, and it must be a public page.

That sits oddly beside the first principle, "no OpenFactor servers", so it is worth saying
plainly why it does not break it: a static document served by GitHub is not a backend the app
talks to. The app still makes no network requests. What the URL costs is a page someone must
keep current, not an operational service.

Two options, and I would take the first:

- **`PRIVACY.md` in the repository**, linked at its GitHub URL. Nothing new to run, it is
  versioned alongside the code it describes, and a reviewer can see its history. A draft is at
  the end of this document.
- **GitHub Pages on `openfactor.dev`.** Prettier, and one more thing that can expire or break.

**A support URL is required too.** The repository's issues page is the honest answer, since that
is where support actually happens: `https://github.com/dragut-eth/openfactor/issues`.

**Screenshots do not exist.** Apple needs 6.7 inch iPhone screenshots at minimum, and Apple Watch
screenshots if the watch app is listed. `assets/` is gitignored, so wherever these are produced
they are not committed. Worth noting that the App Store frames are the one place people will look
at this app before installing it, and the vault setup screen is a strange first impression: the
list with real codes is what to show.

## App information

| Field | Value | Note |
| --- | --- | --- |
| Name | `OpenFactor` | 30 character limit, well under |
| Subtitle | `Two factor codes, open source` | 30 character limit, 29 used. See below |
| Primary category | Utilities | Where authenticators sit |
| Secondary category | Productivity | Optional, and low value; leaving it empty is defensible |
| Age rating | 4+ | No objectionable content, no web views, no user generated content |
| Price | Free | |
| Availability | All territories | Nothing here is region specific |

**Not "Security" as a category**, because Apple does not offer one and Utilities is where every
comparable app is found.

**The subtitle changed from "offline" to "open source", and it is a positioning call rather than
a correctness one.** Both are true. Plenty of authenticators work offline, so that word says
little about which one this is; few publish their source, their design documents and their
review findings, so that word does. It also costs nothing in search, because "two factor" stays
in the subtitle and "2fa", "totp" and "authenticator" are all in the keywords.

The alternatives considered, if this reads wrong: `Offline authenticator`, `Open source
authenticator`, `Offline two factor codes`.

## Keywords

100 characters, comma separated, no spaces after commas, and the app name is indexed separately
so repeating it wastes the budget.

```
2fa,totp,otp,authenticator,two-factor,hotp,offline,open source,watch,backup,import,export
```

That is 89 characters. Deliberately absent: any competitor's name, which Apple rejects, and
"secure" and "private", which are claims rather than search terms.

## Description

Drawn from `README.md` so the two cannot drift into different claims.

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

Locks behind Face ID, Touch ID, or your passcode, and never lets a code appear in the app
switcher.

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
Beta, in testing. OpenFactor has not had an independent security audit. Do not trust it with an
account you cannot recover yet. Source and findings on GitHub.
```

That is 158 characters. It is a strange thing to put in a store listing and it is the honest one,
and it matches the warning at the top of `README.md` rather than softening it for the shop
window.

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

**Whether it qualifies for an exemption is a determination for Xavier, not for me.** The usual
route for an app in this shape is the exemption for software using only encryption available in
Apple's operating systems, with no proprietary or non standard implementation, but that is a
legal classification with export consequences and it should not be settled by an assistant's
confidence. What can be said without qualification is the list above, and that it is complete.

**Once decided, it belongs in the Info.plist** as `ITSAppUsesNonExemptEncryption` so App Store
Connect stops asking on every upload and the answer is versioned with the source rather than
re-entered by hand. That is a code change and is not made here.

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

Questions and reports: https://github.com/dragut-eth/openfactor/issues

Security vulnerabilities: see SECURITY.md in the repository, which asks for private disclosure
through GitHub Security Advisories.

## Changes

This policy is versioned with the source. Its history is visible in the repository.
```

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

It is not the submission checklist. Gate A4 comes first, `SECURITY.md` still describes an
unaudited app, and `README.md` says not to trust it with an account you cannot recover. Metadata
being ready changes none of that.
