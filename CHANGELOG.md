# Changelog

What changed in each version of OpenFactor on the App Store, newest first.

Each released version links to its provenance record in [docs/releases/](docs/releases/), which
ties the build to the exact commit it was made from. Where a change came from an audit, the audit
is named, and its record in [docs/audits/](docs/audits/) holds the reasoning, the evidence, and what
was decided against. Builds that reached TestFlight only are not listed here; they are in
`docs/releases/` too.

## Unreleased: 1.1.3

### Fixed

- **The camera picks up the next code after "Try again" and after canceling a transfer preview.** It
  used to stay live on screen and report nothing until the add screen was closed and reopened.
  Audit X5, B1.
- **A canceled Face ID prompt on a cold start no longer leaves a blank screen.** With App Lock on,
  opening the app after it had been closed and canceling the prompt showed a blank screen with no
  way out but force quitting. The lock screen and its Unlock button now show. Audit X5, N1.
- **App Lock is no longer a dead end after the device passcode is removed and set again.** The
  Unlock button stays under the explanation, so setting the passcode again leads somewhere.
  Audit X5, S1.
- **Apple Watch asks the iPhone again after the vault on the iPhone is replaced**, instead of showing
  "No accounts yet" until watchOS restarts the app. Audit X5, S2.
- **Reordering while searching no longer moves the wrong accounts.** Edit mode ends when a search
  begins. Audit X5, S6 and B7.
- **The import preview no longer decrypts every stored account once a second while it is open.**
  Audit X5, S3.
- **The vault screens no longer carry an old passphrase or error message onto a later screen.**
  Audit X5, B9 and B10.
- **The Apple Watch list no longer flashes an error while the wrist is down.** Audit X5, B20.
- **A failed "Add account" says so.** It used to leave the confirmation screen as it was, with
  nothing saved and no message. Audit X5, B16.
- **Manual entry accepts any refresh period a scanned code can carry**, 1 to 3600 seconds. It used
  to stop at 5 to 300. Audit X5, B17.

### Changed

- **The vault key file's protection is checked once per launch** instead of at every code. Audit
  X5, S10.

### Security

- **The backup writer refuses anything but a full generated passphrase in generated mode.** It used
  to trust the mode, so an empty passphrase could seal an archive. Unreachable from the app's export
  screen, which always holds a generated passphrase; now the writer's own rule.

## 1.1.2 (11), 2026-10-03

[Provenance record](docs/releases/1.1.2-11.md).

### Fixed

- **Canceling the import of accounts from a shared Google Authenticator transfer code works as
  expected**, instead of reopening the import. Found by the maintainer on hardware.
- **A color chosen for a new account stays chosen.** Same cause as the line above.

## 1.1.1 (10), released by 2026-10-02

[Provenance record](docs/releases/1.1.1-10.md). Submitted 2026-09-27; the exact day of release was
not recorded.

### Security

- **A file opened into OpenFactor to import is read and removed the moment it arrives, even while
  the app is locked, and is kept out of the iPhone's backups.** Audit X4, OF-X4-01.
- **Imported images that claim impossible sizes are refused cleanly.** Audit X4.

## 1.1 (9), 2026-09-19

[Provenance record](docs/releases/1.1-9.md).

### Added

- **The account list keeps up with other devices.** It reloads when the app comes back to the
  front, and drops an account deleted elsewhere at the next code boundary. Measured in E16.
- **OpenFactor says so if the vault's recovery record goes missing**, while there is still time to
  make a backup. Audit X2.

### Changed

- **Passphrase fields are masked, with a button to reveal them.** Audit X2.
- **Starting over needs a passcode on the iPhone**, because it removes accounts from every device.
  Audit X2.

### Fixed

- **Apple Watch no longer asks to be set up when it already is.** Audit X2.
- **A file opened into OpenFactor to import is removed once it has been read.** Audit X3, OF-X3-01.
- **The account list no longer crashes when one account is stored twice.** Audit X3, OF-X3-02.
- **A counter based account whose counter reaches the storage limit stops advancing** instead of
  making every later backup fail. Audit X3, OF-X3-03.
- **Imports read Google Authenticator batch identifiers across their full range, and an Aegis file
  with one malformed entry imports the rest** instead of being refused whole. Audit X3, OF-X3-04
  and OF-X3-05.

## 1.0 (8), 2026-09-16

[Provenance record](docs/releases/1.0-8.md). The first release.

Two factor codes on iPhone and Apple Watch, with no account, no server and no network code.
Accounts are encrypted before they are stored, and the key that opens them stays on the device.
iCloud Keychain sync is off by default; when it is on, only encrypted records travel. Import from
Google Authenticator transfer codes, Aegis vaults and labeled text exports; export to an encrypted
backup in a documented format, or to a plain file for moving to another authenticator. Optional
App Lock with Face ID, Touch ID or the device passcode.
