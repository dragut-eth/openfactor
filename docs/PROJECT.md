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
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.openfactor.dev` | Matches the App Store Connect record. The default Keychain access group derives from it, so changing it after release would make every stored secret unreadable and silently lose users their accounts |
| `IPHONEOS_DEPLOYMENT_TARGET` | `18.0` | The documented minimum. Xcode defaults new projects to the SDK version, which would have restricted the app to iOS 26.5 and newer |
| `TEST_HOST` | the app | See above |
| Local package `relativePath` | `.` | Xcode wrote `../OpenFactor`, which only resolves if the checkout folder happens to be named `OpenFactor`. Anyone cloning into `openfactor` on a case sensitive filesystem, or into a renamed fork, would have got a broken project |
| `INFOPLIST_KEY_NSCameraUsageDescription` | set | The camera is used to scan setup codes. A missing usage string is not a warning, it is a crash the first time the app asks, and only on a real device where nobody is looking |

## Folder layout

Xcode's own names are kept rather than renamed to something tidier, because renaming a
synchronised folder means hand editing the project file, and hand edits to that file are
exactly what this document exists to compensate for.

```
OpenFactor/            App sources
OpenFactorTests/       Test target. Empty on disk, see below
OpenFactorUITests/     Template placeholder
Sources/OpenFactorCore/    The package. Where everything security sensitive lives
Tests/OpenFactorCoreTests/ The test suite, run twice, see below
```

## How one test suite runs in two places

`OpenFactorTests` is an empty folder. Its sources are `Tests/OpenFactorCoreTests`, attached
to the target as a second synchronised folder, so the same files run in both contexts:

- `swift test` runs them unsigned. Fast, no simulator, and the Keychain tests skip.
- `xcodebuild test` runs them inside the app. Slower, and the Keychain tests execute.

One set of files, no duplication, nothing to drift. Xcode's `Add Files` dialog cannot
express this, since it refuses to reference files it considers owned by the package, so
the second synchronised folder was added to the project file directly.

CI runs both jobs. If you find yourself making the Keychain tests pass under `swift test`,
stop: they are supposed to skip there, and the only way to make them pass would be to
weaken what they assert.

## Not configured yet

- **No entitlements file.** The app uses the default Keychain access group. A shared
  `keychain-access-groups` entitlement is likely needed before the watch app in PR 14,
  since a watchOS target has its own bundle identifier and therefore its own access group.
  Unverified, see `handoff.md`.
- **No signing team in the project file.** Simulator builds do not need one, and leaving it
  out keeps a personal team identifier out of a public repository.
- **No capabilities.** No push, no background modes, no App Groups, and above all no
  network entitlement to notice the absence of.
- **No photo library usage string, deliberately.** Importing a picture of a QR code goes
  through `PhotosPicker`, which runs out of process and hands back only the one image the
  user chose. The app never gets access to the library, so it does not ask for any.
