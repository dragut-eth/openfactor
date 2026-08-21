# E9: the launch reconcile repairs a device in the loss shape, measured

**2026-08-19.** An iPhone XS on iOS 18.7.9, paired to the same Apple Account as the phone in E8.

S1-1 was this gate's worst finding: the wrapped key never synced, so a phone that turned sync on
sent every account to iCloud and kept the only means of reading them on one device. Fixing it fixed
future devices. **A phone already in that state would never repair itself**, because the sync toggle
already reads "on" and nobody flips it for no reason, so the app repairs it at launch instead.

S1-13 is the finding against that repair: it swallows its error, so a failure is invisible.

Nothing had ever run it on a device in the state it exists for.

## Manufacturing the loss shape

The state cannot be faked by hand, because the flag is written by code. It was produced by the code
that originally produced it:

1. The phone ran the **TestFlight build, `1.0 (5)`**, which predates every fix in this gate.
2. The existing vault was destroyed from the unlock screen, which removes the wrapped record from
   iCloud as well.
3. A fresh vault was created **on that old build**, which writes the wrapped key device-only.
4. An account was added, then sync was turned on. Under that build, turning sync on moves the
   accounts and never the wrapped key.

At that point: accounts in iCloud Keychain, wrapped key on one device. That is the shape a phone
would be in today if it had enabled sync before the fix shipped.

## The upgrade

The development build was installed **over** the TestFlight one, without deleting it. That detail
decides whether the test measures anything: the sync preference lives in the app's own storage
rather than the Keychain, and a delete would have reset it, leaving the reconcile correctly doing
nothing and a reading that meant nothing.

The app was opened once. No toggle was touched.

## The reading

**"Wrapped key — in iCloud."**

## What this settles

**The reconcile works on a real device in the state it was written for.** The inference is clean:
the old build never writes that flag, no vault was created after the upgrade, and the sync toggle
was not used. The only code that could have moved the record is the launch reconcile.

**It is also the first hardware evidence for the mechanism E8 could only show sideways.** E8 proved
a replacement phone recovers, and could not say whether the record was syncable because it was
created that way or because it had been repaired. This is the repair, observed directly.

## What it does not settle

**S1-13 is about the failure path, and this measured the success path.** A reconcile that fails,
for a locked Keychain at launch or anything else, is still silent, still unretried within that
process, and still invisible to the person holding the phone. Nothing here says how often that
happens.

The instrument that made this observable, the Debug readout of the record's own flag, is Debug-only
and does not exist in a shipped build. Nobody outside a development machine can see this.
