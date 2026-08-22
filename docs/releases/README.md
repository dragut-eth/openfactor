# Release records

**One file per successful upload, written by `scripts/ship-testflight.sh` rather than by hand.**
The first is [1.0-6.md](1.0-6.md), from commit `47e1682`.

**The first write found a bug, in the reporting rather than the record.** The script computed the
record's path inside a subshell and named it in the messages outside, where under `set -u` the
variable does not exist. So it died on the line announcing success, after a good upload, and the
closing App Store Connect instructions never printed. The record itself was complete and correct.
CI now runs shellcheck at info level over `scripts/`, which is the level that catches this and the
level `-S warning` is not.

Each record carries the commit, whether the working tree was clean, the toolchain to its build
number, the SHA-256 of the exported archive, and the per-section canonical digests of every
shipping binary.

**What a record is for.** It is the only thing tying a build number to a commit, which is what gate
A5 needs to review the diff between releases. It is also a claim made in public before anybody
could check it, so it can be contradicted later.

**What a record is not.** Proof that the binary Apple served came from that commit. See
[../BUILD_PROVENANCE.md](../BUILD_PROVENANCE.md) for the boundary and
[../../VERIFYING.md](../../VERIFYING.md) for what you can check yourself.
