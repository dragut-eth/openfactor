# Release records

**One file per successful upload, written by `scripts/ship-testflight.sh` rather than by hand.**
Empty until the first release after that script gained the step.

Each record carries the commit, whether the working tree was clean, the toolchain to its build
number, the SHA-256 of the exported archive, and the per-section canonical digests of every
shipping binary.

**What a record is for.** It is the only thing tying a build number to a commit, which is what gate
A5 needs to review the diff between releases. It is also a claim made in public before anybody
could check it, so it can be contradicted later.

**What a record is not.** Proof that the binary Apple served came from that commit. See
[../BUILD_PROVENANCE.md](../BUILD_PROVENANCE.md) for the boundary and
[../../VERIFYING.md](../../VERIFYING.md) for what you can check yourself.
