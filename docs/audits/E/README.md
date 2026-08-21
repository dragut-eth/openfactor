# The hardware probes, and what re-running each one would take

**A reviewer put the objection better than this folder had.** Reading the design, the questions
that decide whether it holds live in Apple's Keychain, iCloud and WatchConnectivity, "which I read
as comments, not as behaviour". The measurements in this folder are real, and to somebody outside
they are still prose describing something that happened once on somebody else's phone.

**This page does not close that. It says exactly what each probe would take to run again**, so a
reader can tell the difference between a measurement nobody has bothered to automate and one that
cannot be automated at all. Most are the second, and the reason is the same in every case: the
thing being measured is a relationship between two apps, two devices, or two installs, and a test
bundle is one app, on one device, in one install.

## The rule this folder now follows

**A probe becomes a test the moment it can be one.** Two already have. Where that is impossible,
the reason is a topology, and the topology is named below rather than left as "measured on
hardware".

## What is already runnable

| Probe | Where it runs now |
| --- | --- |
| **E12**, whether `kSecAttrGeneric` can carry a compare and swap token | `OpenFactorTests/GenericAttributeExperiment.swift`. A hosted test in the simulator, both flag states, including the case the idea rests on: a write carrying a stale token lands nowhere |
| **E7 item 4**, the watch exchange and its transcript binding | `Tests/OpenFactorCoreTests/WatchProvisioningTests.swift`. The negative controls are tests, and the construction is now pinned to a fixed vector, so a changed label, salt, layout or output length reddens rather than round trips |
| **E7 item 5**, what an opaque item costs queryability | Never a hardware question. It asks what the code puts in a Keychain query, which is visible in `KeychainSecretStore` |
| **E1's defence**, what a sibling actually finds in a stored item | `OpenFactorTests/KeychainSecretStoreTests.swift`, `theStoredBytesAreOpaque`. Added because of this objection. See below |

### The one added because of the objection

**E1's finding cannot be a test and its defence can, and nothing was testing the defence.**

E1 measured that a sibling of the same team can read this app's Keychain items. The vault exists
to make that reading worthless, and every assertion in the Keychain suite examined an item's
**attributes**: the protection class, the access group, the sync flag, the label. The helper the
suite uses to read an item does not even ask for the data. **Nobody had ever looked at the bytes.**

`theStoredBytesAreOpaque` writes an account with distinctive strings, reads the stored blob the
way a sibling would, and asserts that the issuer, the account name and the shared secret are all
absent from it.

**It carries its own positive control**, because three assertions that a needle is absent prove
nothing unless the same search can find a needle that is present. It also asserts the record's
magic **is** found, and that the store can still read back what it wrote, so opacity cannot be
mistaken for either a broken search or a corrupted item.

## What cannot be a test, and precisely why

| Probe | What it measured | What running it again takes |
| --- | --- | --- |
| **E1** | Keychain access groups are not a boundary between apps of the same team | **A second signed app.** Two bundle identifiers under one team, both installed. The whole point is what a *different* app can read, and a test bundle cannot be a different app |
| **E4** | A sibling cannot reach another app's private container | **A second signed app**, knowing the victim's exact container path, on an unlocked device |
| **E5** | A sibling phone app activating `WCSession` finds it inert | **A second signed app with its own embedded watch app**, installed to a paired watch. Priced in E5 itself at a day of work rather than an hour. **Deliberately not run**, with the reasoning labelled as reasoning and the remedy written down: see the decision at the end of E5 |
| **E6**, the update half | An app update preserves the data and moves the container | **Two installs of the same app over each other**, which is what an App Store or TestFlight update does. A test runs inside one install and cannot outlive it |
| **E8** | Recovery on a replacement phone | **Two iPhones on one Apple Account**, iCloud Keychain on, one of them clean and never having run the app |
| **E9** | The launch reconcile repairs a device already in the loss shape | **A second device already carrying the broken state**, which a fresh install cannot be put into, because the state is what the fix prevents |
| **E10** | A device holding the wrong key notices, asks and recovers | **Two devices on one Apple Account**, one of which replaced the vault after the other stopped watching |
| **E11** | A link arriving over a shared image | **The share extension and the app as separate processes**, with a real share sheet delivering a real attachment |
| **E13** | Whether either device held a record with a split pair | **Two devices**, and a question about their existing contents rather than about anything a test could set up |

## The one that is measured as unconvertible

**E6's attribute half looks like the easiest thing on this page and is the trap.** Whether the
vault key file carries `.complete` and the backup exclusion reads back is exactly the sort of
claim that should be a test, and it cannot be one:

**macOS reports `NSFileProtectionComplete` for a file it does not protect, and the iOS simulator
reports nothing for a file it writes with the option set.** An assertion either way passes on one
platform, fails on the other, and proves nothing on either. That was found by writing the test
twice and being wrong twice, and it is why `VaultKeyStoreTests` and `SharedInboxTests` both open by
saying what they cannot see.

**So the backup exclusion is asserted by test and the protection class is not.** The class was read
back on hardware in E6, and that is the only place it has ever been observed.

## The one anybody can reproduce

**E14** needs no second app, no second device and no signing: turn on the system per-app lock, turn
this app's App Lock off, record the launch, and step through the frames. It answers a question this
project had asserted twice and measured zero times, and it answers it against this app rather than
in its favour: **the system does that job better than the app can, and immediately.**

## Not a probe yet, and the next one worth running

**Whether other authenticators leak the same app switcher window.** Two opposite claims are on
the record with no evidence behind either: a reviewer says a peer that blanks its snapshot has no
such window, and the maintainer says this is system wide and no peer does better. **Neither has
measured a peer.** E14 settled the other half of that argument and left this half exactly where it
was. The method is the one PR 15b already used here, and it needs no second signed
app and no second device, which puts it in a different class from everything in the table above.
Written up in `docs/APP_LOCK.md`.

## What a reader is entitled to conclude

**That two of these are checkable by anybody with this repository**, and the rest are not, for
reasons that are about hardware topology rather than about effort.

**That the unconvertible ones remain single observations on one person's devices**, at one moment,
on one OS version. Nothing here says how any of them behave after an OS upgrade or in a second
household. That gap was raised in the same review and is recorded rather than answered.

**That "measured on hardware" is a weaker claim than "there is a test"**, and this folder should
stop using the two as though they were interchangeable.
