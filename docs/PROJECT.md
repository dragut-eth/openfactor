# The Xcode project, in plain language

`OpenFactor.xcodeproj` is a binary shaped text file that nobody reads in a diff. This
document says in words what is in it, so a reviewer can check the project without opening
Xcode, and CI asserts the load bearing values so this file cannot quietly drift from
reality. If you change one of the settings listed here, you have to change this document
and the `Project settings are what the documentation says` job in `.github/workflows/ci.yml`
in the same pull request. That friction is the point.

## Why the project file is checked in

Decided in PR 5, and the roadmap had leaned the other way.

The plan was to generate the project from a short YAML file, keeping the reviewable
artefact small. Against that: it makes a build tool a prerequisite for opening the
project at all, and for a project whose pitch is that it has no dependencies, requiring
`brew install` before anyone can read the code is a real cost. A generated project is
also only as trustworthy as the generator, which is one more thing an auditor has to take
on faith.

So the project file is checked in, and the auditability it costs is bought back two ways:
this document, and the CI job that asserts the values below still hold. That gives a
reviewer a plain English description they will actually read, plus a machine check that
it is true.

## Targets

| Target | What it is |
| --- | --- |
| `OpenFactor` | The iOS app. SwiftUI, no storyboard |
| `OpenFactorTests` | Unit tests, **hosted by the app** |
| `OpenFactorUITests` | Template placeholder, empty, not run in CI |
| `OpenFactorWatch Watch App` | The watchOS app. Read only, added in PR 14 |
| `OpenFactorWatch Complication` | The watch face complication. Launches the app, holds no data |

### Why hosting matters

`OpenFactorTests` sets `TEST_HOST` to the app, so the tests run inside a real application
with a real bundle identifier and therefore a real Keychain. That is not a detail: reaching
the data protection Keychain requires an entitlement, entitlements come from code signing,
and a plain `swift test` bundle has neither. Six tests asserting the protection class on a
stored secret can only run here. Gate A1 stayed open until they did.

This is why the app target exists at all right now. The interface came second.

## Settings that matter

| Setting | Value | Why |
| --- | --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` | `dev.openfactor.app` | Matches the App Store Connect record. The default Keychain access group derives from it, so changing it after release would make every stored secret unreadable and silently lose users their accounts |
| `IPHONEOS_DEPLOYMENT_TARGET` | `18.0` | The documented minimum. Xcode defaults new projects to the SDK version, which would have restricted the app to iOS 26.5 and newer |
| `TEST_HOST` | the app | See above |
| `CODE_SIGN_ENTITLEMENTS` | `OpenFactor/OpenFactor.entitlements` | Declares one shared Keychain access group, `$(AppIdentifierPrefix)dev.openfactor.shared`. **Never rename this group again.** It matches the bundle identifiers today, which is tidy and is not what makes it correct: the name is arbitrary and its only real requirement is that it never changes. Every account on every device and in iCloud Keychain lives inside it, and a rename strands all of them behind a migration whose failure mode reads as "my accounts vanished". It was renamed once, from `com.openfactor.shared`, deliberately and while only two people held test data. The watch app has its own bundle identifier and would otherwise look in its own group and find nothing. The group is named only here: the app writes without specifying one, and the Keychain uses the first entitlement group as the default, so the group name is never written down twice |
| `DEVELOPMENT_TEAM` | the maintainer's team | Present on the watch target only, written there by Xcode when signing was set up. Kept rather than stripped: Xcode rewrites it whenever signing is touched, and a team identifier is not a secret, it ships in every binary. A fork will get a signing error until it sets its own, which is a clearer failure than a mysterious one |
| Local package `relativePath` | `.` | Xcode wrote `../OpenFactor`, which only resolves if the checkout folder happens to be named `OpenFactor`. Anyone cloning into `openfactor` on a case sensitive filesystem, or into a renamed fork, would have got a broken project |
| App has an **Embed Watch Content** copy files phase | `dstSubfolderSpec = 16`, path `$(CONTENTS_FOLDER_PATH)/Watch` | **The setting whose absence shipped a watchless build.** For three pull requests the watch app was a sibling target rather than an embedded one, and nothing local could see it: the project builds, the tests pass, and Xcode happily installs the watch app onto a paired watch when you run it. Distribution is the only thing that cares, because a watch app reaches a stranger's wrist only by riding inside the phone app's bundle. TestFlight reported "Apple Watch: No" on a build already sent to a tester. Asserted in CI now, alongside the target dependency that makes the watch app build first |
| Watch `PRODUCT_BUNDLE_IDENTIFIER` | `dev.openfactor.app.watchkitapp` | A watch app's identifier has to be the companion app's with a suffix, or the pairing is not recognized |
| Watch `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` | `dev.openfactor.app` | Names the phone app it belongs to |
| Watch `INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp` | `YES` | The watch app has to work with the phone off, absent, or out of range. That requirement is what ruled out asking the phone for each code, and it is why the watch holds its own copy of the secrets |
| Watch `CODE_SIGN_ENTITLEMENTS` | `OpenFactorWatch Watch App/OpenFactorWatch.entitlements` | Declares the same shared Keychain access group as the phone. This is the entire mechanism by which the watch sees the phone's accounts, so it is the one setting that, if wrong, produces a watch app that runs perfectly and shows nothing |
| Watch `WATCHOS_DEPLOYMENT_TARGET` | `11.0` | Matches the package |
| Complication `PRODUCT_BUNDLE_IDENTIFIER` | `dev.openfactor.app.watchkitapp.watchface` | It must begin with the watch app's identifier, or the extension is not recognized as belonging to it. The suffix is `watchface` rather than the obvious `complication` because **Apple will not register an identifier ending in `.complication`**. It was refused under `com.openfactor.dev.watchkitapp.` and then, after the rename, refused again under `dev.openfactor.app.watchkitapp.`, while every sibling identifier registered in the same attempt. Two prefixes rules out the first explanation, that another team held the string. Do not try to tidy this back to `complication`: the failure appears only at export, long after everything local has succeeded |
| Complication has **no** `CODE_SIGN_ENTITLEMENTS` | absent | The complication never reads the Keychain, and the absence of the entitlement is what guarantees it. A live code on a watch face is a second factor shown to anyone who glances at your wrist. Adding an entitlement here reverses a security decision |
| `INFOPLIST_KEY_NSFaceIDUsageDescription` | set | App Lock authenticates with `LocalAuthentication`. Absent, the Face ID prompt is a crash, not a warning, and only on a real device |
| `INFOPLIST_KEY_NSCameraUsageDescription` | set | The camera is used to scan setup codes. A missing usage string is not a warning, it is a crash the first time the app asks, and only on a real device where nobody is looking |

## Folder layout

Xcode's own names are kept rather than renamed to something tidier, because renaming a
synchronized folder means hand editing the project file, and hand edits to that file are
exactly what this document exists to compensate for.

```
OpenFactor/            App sources
OpenFactorShare/       Share extension. Writes an image to the group inbox, nothing else
OpenFactorTests/       Test target. Empty on disk, see below
OpenFactorUITests/     Template placeholder
Sources/OpenFactorCore/    The package. Where everything security sensitive lives
Tests/OpenFactorCoreTests/ The test suite, run twice, see below
```

Two plists sit at the repository root rather than beside their targets:
`OpenFactor-Info.plist` and `OpenFactorShare-Info.plist`, joining the complication's. A plist
inside a file system synchronized folder is also copied as a resource, so the build fails with
"multiple commands produce Info.plist". The root is where it has to live, not a preference.

## The share extension, and the entitlement it must never have

`OpenFactorShare` is an app extension embedded in the iOS app, bundle identifier
`dev.openfactor.app.share`. It exists so a transfer QR never has to rest in Photos; the reasoning
is in `docs/ROADMAP.md` and the code.

**Its entitlements file must contain exactly one key**, the app group. It must never gain
`keychain-access-groups`: the extension cannot be allowed to read an account or write one, and
the absence of the entitlement is what enforces that rather than any code in it. CI asserts this
structurally, by parsing the plist and comparing the key set, because the first version of that
check counted a string and passed while lying, the comment in the file being the thing that
contained it.

## How one test suite runs in two places

`OpenFactorTests` is an empty folder. Its sources are `Tests/OpenFactorCoreTests`, attached
to the target as a second synchronized folder, so the same files run in both contexts:

- `swift test` runs them unsigned. Fast, no simulator, and the Keychain tests skip.
- `xcodebuild test` runs them inside the app. Slower, and the Keychain tests execute.

One set of files, no duplication, nothing to drift. Xcode's `Add Files` dialog cannot
express this, since it refuses to reference files it considers owned by the package, so
the second synchronized folder was added to the project file directly.

CI runs both jobs. If you find yourself making the Keychain tests pass under `swift test`,
stop: they are supposed to skip there, and the only way to make them pass would be to
weaken what they assert.

## Folders shared between targets

`OpenFactorShared` holds the small amount of interface code both app targets need:
`PaletteColor`, which is the color and contrast maths, and `CodeFormatting`, which groups
digits for transcription. It is attached to the phone and watch targets as a synchronized
folder, the same mechanism that attaches the core's test sources to the app test target.

It exists so those two are not written twice. The watch palette's values differ from the
phone's on purpose, since the color is text there rather than background, but the arithmetic
that decides whether either is legible is the same arithmetic and there should be one of it.

## The watch app is not embedded in the phone app yet

An App Store build ships the watch app inside the phone app, through an `Embed Watch
Content` copy phase and a target dependency. Both were written in PR 14 and then removed
again, deliberately, and this records why so nobody re-adds them without knowing.

The moment the phone target depends on the watch target, building the phone app requires
the full watchOS platform to be installed, not just its SDK. Xcode 26 downloads platforms
separately, and without it every build of the iOS app fails at scheme resolution, including
in CI, including for anyone cloning the repository to read it. That is a heavy prerequisite
to impose on a project whose pitch is that it has no dependencies.

Until then the watch app is built and installed on its own, which
`INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp` already supports and which is enough to
answer the question PR 14 exists to answer. The embed phase returns in PR 18, where
installing the platform is unavoidable anyway.

## Not configured yet

- **No signing team in the project file.** Simulator builds do not need one, and leaving it
  out keeps a personal team identifier out of a public repository.
- **No capabilities.** No push, no background modes, no App Groups, and above all no
  network entitlement to notice the absence of.
- **No photo library usage string, deliberately.** Importing a picture of a QR code goes
  through `PhotosPicker`, which runs out of process and hands back only the one image the
  user chose. The app never gets access to the library, so it does not ask for any.
