# E6: does the container survive, and do the file attributes stick?

Item 7 of the vault prove list, **partly measured and partly out of reach**. What was measured
produced one finding nobody had raised. Xavier's iPhone 15 Pro, 16 August 2026.

## What was measured

### The two attributes the design leans on are real

```
protection requested:            complete
protection read back:            NSFileProtectionComplete
setResourceValues(isExcludedFromBackup: true): ok
isExcludedFromBackup read back:  true
```

Both read back rather than assumed from a setter that returned without complaining. `.complete`
is the class Fable insisted the document name instead of calling it "strongest", and it is
genuinely applied. The backup exclusion the recovery story depends on is genuinely set.

Both survived a reinstall unchanged, so they are properties of the file rather than of the
session that wrote it.

### An app update preserves the data and **moves the container**

Reinstalling the binary over the top, which is what an App Store or TestFlight update does,
preserved the file exactly:

```
pass 1   wrote fresh: VAULT-KEY-WRITTEN-AT-1786895167
         container:   /var/mobile/Containers/Data/Application/F3CCE27D-5C5F-41E6-A2F6-EEF6DE7E7796

pass 2   file existed before this launch: true
         surviving contents: VAULT-KEY-WRITTEN-AT-1786895167
         container:   /var/mobile/Containers/Data/Application/F7C298C5-634E-4703-957D-FEC091BDAD06
```

**The data is the same and the path is different.** That was not in anybody's review and it has a
direct consequence for the design:

> **The vault key must always be located through `FileManager`'s application support URL, never
> through a remembered absolute path.** Any component that caches or persists the path, in the
> Keychain, in a manifest, or in a preference, breaks at the first update, and it breaks by
> pointing at a container that no longer exists rather than by failing loudly.

This matters most for the tripwire anchor, which is the one part of the design that stores
knowledge *about* the container. It has to key off contents, never location.

## What could not be measured, and why

**Offload App is not offered for a development install.** The option is absent from Settings for
a sideloaded app, and the reason is structural rather than a quirk: offload deletes the binary
and relies on re-downloading it from the App Store, and a sideloaded app has nowhere to come
back from. Measuring it would need the probe shipped through TestFlight.

Apple documents offload as removing the app while keeping its documents and data, and the update
result above is consistent with that. **It stays unverified by us**, and the honest reading is
that the risk here is low and unmeasured rather than closed.

**Restore from a device backup, and Quick Start migration, were not attempted at all.** Both
require wiping or newly configuring a device. Doing that to somebody's personal phone to settle
a design question is not a reasonable trade, and no result would have been worth it.

So the backup exclusion is verified **as a flag** and never **as a restore**. The design should
say that rather than implying the round trip has been exercised.

## Disposition

Item 7 is narrowed rather than closed:

- **Purging under storage pressure**: not a risk, because the key lives in `Application Support`
  rather than `Caches` or `tmp`, which is already what the document requires.
- **App update**: measured, data survives, path moves.
- **Delete App**: removes the container, which is intended and is exactly why the passphrase
  path exists.
- **Offload**: documented by Apple to preserve data, unmeasured here, low risk.
- **Restore and Quick Start**: unmeasured, and deliberately so.
