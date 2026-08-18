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
| Subtitle | `Two factor codes, offline` | 30 character limit, 25 used |
| Primary category | Utilities | Where authenticators sit |
| Secondary category | Productivity | Optional, and low value; leaving it empty is defensible |
| Age rating | 4+ | No objectionable content, no web views, no user generated content |
| Price | Free | |
| Availability | All territories | Nothing here is region specific |

**Not "Security" as a category**, because Apple does not offer one and Utilities is where every
comparable app is found.

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
OpenFactor generates two factor authentication codes on iPhone and Apple Watch.

It has no account to create, no server, no browser extension, and no analytics. Your accounts
stay on your devices. If you turn on iCloud sync, they travel through iCloud Keychain, where
Apple cannot read them.

Accounts are encrypted before they are stored. The key that opens them stays in the app's
private container on each device and is never synced, never written to the Keychain, and never
included in a backup.

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

No password storage, no autofill, no accounts, no telemetry.

OPEN SOURCE

The source is public and built in the open from the first commit, including the design documents
and the findings from each review. Read it at github.com/dragut-eth/openfactor
```

**"Where Apple cannot read them" is the one claim worth checking before submission.** It is
Apple's own description of iCloud Keychain end to end encryption, and `SECURITY.md` discusses the
escrow caveat at length. The sentence is defensible because the vault means what syncs is
ciphertext under a key that never leaves the device, so it is true twice over. If that stops
being true the sentence goes.

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

## A finding: the privacy manifest is now incomplete

`OpenFactor/PrivacyInfo.xcprivacy` declares one required reason API, `UserDefaults` with
`CA92.1`. That was complete when it was written. It is not any more.

`SharedInbox.pending()` reads a file's modification date to decide whether a shared image is
still fresh:

```swift
let arrived = (attributes?[.modificationDate] as? Date) ?? .distantPast
```

File timestamp access is a **required reason API category** in its own right, and reading
`modificationDate` is in it. The manifest declares no such category, so a submission is likely to
draw Apple's automated notice about an incomplete privacy manifest.

**The fix is one entry**, and the reason code that fits exactly is `C617.1`, which covers
timestamps of files inside the app container, an app group container, or a CloudKit container.
The inbox is in an app group container, so that is the case verbatim rather than the nearest
match.

```xml
<dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
        <string>C617.1</string>
    </array>
</dict>
```

**Not applied here**, because this session is documentation only and that file is a shipped
resource. It belongs to whoever picks up PR 18 or the next build, and it should be verified
against Apple's current required reason list rather than trusted from this note: the categories
change, and a manifest that declares the wrong reason is worse than one that declares none,
because it reads as considered.

Two other categories were checked and are genuinely absent: no disk space APIs, and no system
boot time. `UserDefaults` is used in three files and is already declared.

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

OpenFactor collects nothing.

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

## What this document is not

It is not the submission checklist. Gate A4 comes first, `SECURITY.md` still describes an
unaudited app, and `README.md` says not to trust it with an account you cannot recover. Metadata
being ready changes none of that.
