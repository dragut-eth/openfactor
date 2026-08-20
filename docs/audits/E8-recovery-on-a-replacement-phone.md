# E8: recovery on a replacement phone, measured

**2026-08-19.** Two iPhones on one Apple Account, iCloud Keychain on. Phone one held a vault with
accounts and sync enabled. Phone two was a clean device that had never run OpenFactor.

**This is the first time the recovery path has been exercised on hardware.** Every claim about it
until now rested on reading Keychain semantics, and gate A4's worst finding, S1-1, was that those
semantics had been read wrongly: the wrapped key never synced at all, so a replaced phone received
every account as ciphertext with nothing to unwrap it.

## What was done

1. The current build was installed on phone two.
2. OpenFactor was opened.
3. Phone one's passphrase was entered.
4. A code on phone two was compared against phone one's, for the same account, at the same moment.

## What happened

**Phone two opened directly on "Enter your vault passphrase".** Not the setup screen, and not after
a wait: immediately, on first launch.

**The passphrase opened it**, and the accounts appeared.

**The codes matched**, phone one and phone two, same account, same moment.

## What this settles

**The wrapped key reaches a replacement device, and the passphrase recovers the vault.** S1-1's fix
holds in the only test that counts. Nothing else in this gate has demonstrated that.

**And the propagation delay is not where this project thought it was.** `docs/VAULT.md` records
iCloud Keychain taking close to half an hour to move seven items, measured on this project's own
hardware, and the setup screen warns about exactly that wait. Both are about an item being
*written* and then travelling. A replacement phone is a different case: the record had already
synced into the Apple Account long before, so it was there the moment the app looked. The warning
is right for a second device set up the same day and wrong as a description of replacing a phone.

## What it does not settle

The device under test was healthy: sync on, one wrapped record, written by a build that already had
S1-1's fix. It says nothing about a device already in the loss shape, which is E9's subject and
S1-13's, and nothing about two devices creating a vault at once, which is S1-12's.

A restore from backup, and Quick Start, remain unmeasured and are still not claimed.
