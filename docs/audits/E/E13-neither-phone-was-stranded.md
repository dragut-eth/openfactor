# E13: whether either device held a record with a split pair

**Date:** 2026-08-20. **Devices:** iPhone 15 Pro and iPhone XS, both on the build from `2196b97`,
installed by `devicectl` rather than TestFlight.

## What was being answered

S1-25 was that a vault created while the sync preference was already on wrote its wrapped record
with `kSecAttrSynchronizable = true` beside a device-only protection class. The Keychain accepts
that pairing, so the record was flagged for iCloud and kept off it: nothing synced while every
account did, and `syncReport` read the flag and called the record synced.

S1-31 was that nothing repaired a record already in that state. One review return guessed the
affected population was knowable and **likely included the E-series test phones**, and the filing
here corrected all three returns on the window: it was not one day, because the old constructor
passed the preference as a `Bool` and never passed an accessibility, so any vault created with sync
already on had produced this since the round two fix.

**So: are either of these two phones actually in it?**

## The instrument, and the flaw found while using it

The Debug row reports the record's flag, the record count, and now whether the protection class
matches the flag.

**The first reading, on the 15 Pro, could not have answered the question**, and that is a defect in
the instrument rather than in the phone. The repair runs on the first foreground, before Settings
can be reached, so by the time the row is drawn any stranded record has already been corrected. **A
device that was stranded and a device that never was read identically.**

That is a readout unable to show the state it exists to reveal, which is a shape this gate has
filed against twice. It was fixed before the second device was touched: the reconcile now asks for
the repair first, remembers how many records needed one, and the row appends "repaired N".

## The readings

| Device | Row | Reading |
| --- | --- | --- |
| iPhone 15 Pro | Wrapped key | `in iCloud` |
| iPhone XS | Wrapped key | `in iCloud` |

**Neither shows a mismatch, neither shows a repair, and neither shows a record count**, so each
holds exactly one record whose flag and class agree.

The XS is the meaningful one. It ran this build for the first time, with the counter already in
place, and reported nothing repaired. **It was never stranded**, rather than having been quietly
fixed on the way to the screen.

## What this establishes, and what it does not

**Neither device we have was affected.** The guess that the E-series phones were likely in this
state was wrong, and so was the implication of my own correction about the window: the code path
was open for weeks, and it did not catch either phone.

**The prediction was recorded before the reading.** E8 measured the wrapped key reaching the XS
through iCloud, which means its flag and class agreed at that moment, so being stranded now would
have required a vault created on it with sync already on at some point afterwards. It was stated
that this was not expected, and it did not happen.

**It says nothing about whether the defect was reachable.** It was, and a hosted test reproduces
it against the real Keychain by planting the shape with a raw `SecItemAdd`. Two devices not being
in a state is not evidence that the state is unreachable.

**The repair itself remains unexercised on hardware**, because it had nothing to do. Its correctness
rests on three hosted tests against the real Keychain and a mutation, not on a device.

**And the counter's display path has never fired.** "repaired N" has been reasoned about and
compiled, and no device has ever drawn it, because no device needed it. Low stakes for a Debug row,
recorded rather than implied.

## The useful negative

A measurement that comes back boring is still a measurement, and this one narrows the population:
**the two devices closest to the defect, including one erased and re-set-up three times during
E8 through E10, are both clean.** Whoever installs from here is protected by the fix; whoever ran an
earlier build is repaired on their first foreground with sync on. Nobody known is in the state.
