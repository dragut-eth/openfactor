# Build provenance

**What a reader can check about the binary they installed, and what they cannot.**

Three independent reviews said the same thing about this project: they read source at named
commits, never saw a shipped binary, and could not confirm the two were related. That is the
correct objection. **A person entrusting their second factors to this app is trusting the build
Apple handed them, not this repository**, and nothing here has connected the two.

This document does not fully connect them either. It records exactly how far the connection can be
taken, and it is written after the measurement rather than before it.

## The measurement, first

**Two Release builds of identical source, same machine, same toolchain, minutes apart. Every
shipping binary differed.**

```
DIFF  OpenFactor.app/OpenFactor
DIFF  OpenFactor.app/PlugIns/OpenFactorShare.appex/OpenFactorShare
DIFF  OpenFactor.app/Watch/OpenFactorWatch.app/OpenFactorWatch
DIFF  OpenFactor.app/Watch/.../OpenFactorComplication.appex/OpenFactorComplication
DIFF  OpenFactorShare.appex/OpenFactorShare
```

**So "reproducible build" is not a promise this project can make**, and saying so before
attempting it would have been a guess. It was attempted.

### Where the difference actually is

The two main binaries are the same size, 5,724,440 bytes, and **1,134 bytes differ out of 5.7
million**. Mapping those offsets onto the segment table:

| Region | File range | Differs | What it is |
| --- | --- | --- | --- |
| `__TEXT` | 0 to 1,261,568 | **only bytes 4481 to 4496** | The compiled code. That 16 byte run is the `LC_UUID` load command |
| `__DATA_CONST` | to 1,310,720 | no | |
| `__DATA` | to 1,523,712 | one run of 331 bytes | |
| `__LLVM_COV` | to 1,622,016 | two runs, 477 bytes | Coverage mapping data |
| `__LINKEDIT` | to 5,724,440 | a long scattered tail | Holds the ad-hoc code signature: `hashes=1387`, `adhoc, linker-signed` |

**The executable code is byte identical between the two builds.** What varies is the UUID the
linker stamps into every Mach-O, a small amount of data, and the signature hashes, which must
change once anything above them changes.

That is a more useful answer than "not reproducible". **The compiler is deterministic here; the
container is not.**

### Two things checked while the binaries were open

**The build path is not embedded.** The two builds used different derived data directories and
neither directory name appears in either binary. Searching for the maintainer's home directory
path in the shipped binary returns **zero** occurrences.

**`__LLVM_COV` is present in a Release build and carries no readable source paths.** The project
file sets no `ENABLE_CODE_COVERAGE`. Why the segment is emitted was not established, and is
recorded here as an open question rather than explained away.

## Why bit for bit will not be reached

**Even a byte identical local build would not settle the question**, because the artifact a person
installs is not the artifact that was uploaded. Apple re-signs the binary with its own certificate
and may thin, re-encrypt or otherwise process it for delivery. A hash computed here and a hash
computed on a device will not match, and no amount of care on this side changes that.

**So the honest target is provenance, not reproducibility**: pin what went in, publish what came
out, and be exact about which of the two a reader is checking.

## What this project pins

**The toolchain, exactly.**

| | |
| --- | --- |
| Xcode | 26.6, build 17F113 |
| Swift | 6.3.3, `swiftlang-6.3.3.1.3 clang-2100.1.1.101` |
| iOS deployment target | 18.0 |
| watchOS deployment target | 11.0 |
| Bundle identifier | `dev.openfactor.app` |

**Zero third party dependencies, enforced.** `Package.swift` declares none, and a CI job fails the
build if one appears, in any of the three ways one can arrive. The supply chain is this
repository, Apple's frameworks and the toolchain above.

**What can ship at all is constrained by checks rather than by intention.** CI asserts the bundle
identifier, both deployment targets, the embedded watch app and share extension, the declared
device families, the usage strings, that the share extension carries no Keychain entitlement, and
that **nothing in the built Release bundle can reach the network**. That last one runs against the
artifact rather than the source, which is the only version of that claim worth anything.

## Building it yourself

The Release build any reader can reproduce, which is the one CI runs:

```bash
xcodebuild build -project OpenFactor.xcodeproj -scheme OpenFactor \
  -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/rel CODE_SIGNING_ALLOWED=NO
```

Comparing two of your own builds, which is the experiment above:

```bash
for i in 1 2; do xcodebuild build -project OpenFactor.xcodeproj -scheme OpenFactor \
  -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath "build/repro$i" CODE_SIGNING_ALLOWED=NO; done
```

The device archive additionally needs a distribution certificate, which is why
`scripts/ship-testflight.sh` is the path for that and why it is a human's job.

## What a reader may and may not conclude

**May:** that the compiled code is deterministic under a fixed toolchain, that the toolchain is
named to the build number, that no third party code is present, that the shipped bundle cannot
reach the network, and that the local build path and the maintainer's home directory do not leak
into the binary.

**May not:** that the build on the App Store came from any particular commit. **Nothing here
establishes that**, and until an artifact hash is published alongside a tagged commit and Apple's
processing is accounted for, nobody should read this document as though it did.

## The half of that gap this project can close, and now does

**The first half is a record, and a record is not a memory.** `scripts/ship-testflight.sh` writes
one on every successful upload, into `docs/releases/`, one file per build. It carries the commit,
whether the working tree was clean, the toolchain to its build number, and the SHA-256 of the
exported archive and of each shipping binary inside it.

**Four binaries, named in the script rather than discovered by walking the bundle**, plus the
exported archive. A search for Mach-O files would quietly record three the day a target stops
being embedded, which is the failure the archive's own watch app check exists for. A binary that
is not there is written out as missing.

**Four rather than the five lines in the comparison above**, and the difference is worth stating
because a reviewer caught this document claiming five. The fifth line,
`OpenFactorShare.appex/OpenFactorShare`, is the standalone build product sitting beside the app
rather than a member of it; the same extension binary appears inside the bundle at
`OpenFactor.app/PlugIns/`. The comparison walked the build products directory and so saw it twice.
**The record hashes what ships**, which is the four inside `OpenFactor.app` and the archive built
from them.

**What this changes, stated narrowly.** A reader still cannot verify their download, for the
reason measured above. What exists now is a claim made at the moment of shipping rather than
reconstructed afterwards: this build number came from this commit under this toolchain, published
where it can be contradicted. **Gate A5 needs exactly that to audit a release diff**, and nothing
was recording it.

**The second half is not closable by this project.** Apple's processing sits between the archive
and the device, and no local hash reaches across it.

## The canonical hash: what a stranger can check

**The container is not deterministic and the compiled code is.** The measurement at the top of this
document found where two builds differ, and it is small and known: the linker's `LC_UUID`, a little
`__DATA`, and the signature that must change once anything above it does. **The instructions
themselves did not move.**

**So the code is hashable even though the binary is not.** `scripts/canonical-hash.sh` hashes the
`__TEXT,__text` section, which is the instructions and nothing else. `LC_UUID` lives in the load
commands rather than in that section, so it is excluded by construction rather than by subtracting
an offset a toolchain update would move.

**Verified rather than asserted.** Two independent Release builds of the same source, and **all six
architecture slices across all four shipping binaries produced identical canonical hashes**, while
every whole binary differed. That is the claim this mechanism rests on and it was run before it was
written down.

**One thing it got wrong first, recorded because it looked exactly like a real finding.** The first
version read the first `__text` stanza and hashed from the start of the file. For the watch app and
the complication, which are universal binaries carrying `arm64_32` and `arm64`, that ran past the
first slice and into the next one's load commands. **The result was sixteen differing bytes between
builds, which read as nondeterministic compiled code and were in fact the second slice's `LC_UUID`
counted as instructions.** The phone app and the share extension are thin, so the fault was
invisible on two binaries out of three. It now thins each slice and hashes them separately.

### What it proves, and what it does not

**Proves**: that the source at a tagged commit, built with the pinned toolchain, produces exactly
the compiled code this project publishes. Anybody can run the script on their own build and
compare. **That is checkable by a stranger with no access to anything of ours.**

**Does not prove**: anything about the binary Apple served to a phone. Apple re-signs it, thins it
per device, and encrypts the main binary of an App Store install, so there is nothing on a device to
hash without a jailbreak. **No mechanism available on this platform closes that**, and this document
will not pretend otherwise.

**The honest way past it is not a hash at all.** Build the tagged commit yourself and run that,
rather than trusting a binary you cannot inspect. The instructions above are the whole of what that
takes.

**This is the gap `docs/MASVS.md` and `SECURITY.md` already name, narrowed and measured rather
than closed.**
