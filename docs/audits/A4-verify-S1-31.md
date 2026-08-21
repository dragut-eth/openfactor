# A4 verification: S1-31

**This is not a review round.** Two closed questions and nothing else. Do not report low-severity
findings. Do not review anything outside S1-31. **A thin answer is the correct answer**, and one
that says what was checked in order to conclude nothing is worth more than one that manufactures a
finding.

**The code under review is `e4bd414`.** S1-31 was filed in `A4-verify-S1-25-results.md`, which also
carries the three verdicts that produced it. The four previous verification rounds are
`A4-verify-S4-41-results.md`, `A4-verify-S4-42-S4-44-results.md`, `A4-verify-S1-25-results.md` and
`A4-verify-S1-26-results.md`.

Read-only. Do not build and do not run tests; keep the checkout clean.

**Already open, so do not spend the round on them:** S1-33, the same-slot substitution window in
`save`, which `A4-verify-S1-26-results.md` records along with the measurement in
`E12-a-compare-and-swap-token.md`; and S1-34, that the seam can express a case no test does. Both
are recorded and neither is in scope here.

## The finding, as filed

Correcting the write did nothing for what was already written. A wrapped record stored with
`kSecAttrSynchronizable = true` beside a device-only protection class is **not** in
`setSynchronizable`'s query, which looks for the opposite flag. So the reconcile that runs on every
foreground passed over it forever: the flag said iCloud, the class kept it on the device, nothing
synced while every account did, and `syncReport` read the flag and called the record synced.

One return scored this as S1-25 not being fixed. The other two called the write fixed and this
unremediated history. All three agreed on the facts.

**One correction to all three, recorded when the finding was filed**: the window is not one day. The
old constructor passed the preference as a `Bool` and never passed an accessibility, so the
device-only default applied then too. Any vault created while sync was already on has produced this
record since the round two fix.

## What was changed

`repairProtectionClasses()` reads every record's flag and class and, where they disagree, updates
**the class alone**, pinned to that record's own flag. It never deletes, never writes the wrap, and
never moves a record between flags.

**The direction is the safety argument.** The flag is the record's own statement of where it
belongs, so the class is brought to the flag rather than the flag to the class. Moving the flag
would decide, on no evidence, that a record marked for iCloud does not belong there, which is the
habit this gate has filed a high and two mediums against.

It runs inside `setSynchronizable`, on both directions, which is what the foreground reconcile
already calls, and touches only records whose pair disagrees.

`syncReport` gained `protectionMatchesFlag`, and the Debug row appends "class does not match" when
it is false, so a device under test can be asked whether it is affected.

## The two questions

**1. Is S1-31 fixed? Yes or no.** If no, one sentence on what remains.

Judge the code. Does every path that can reach a stranded record now repair it, and is there a
state the repair itself can leave a record in that is worse than the one it found?

**2. Does the fix introduce a new high or medium?** Yes or no. If yes, name it and give the call
order.

The surfaces where the author is least confident:

- **The repair runs inside `setSynchronizable`, which the reconcile calls only when the sync
  preference is on.** A device whose preference is off never reaches it. Is that right, or does a
  stranded record on such a device need a route the app actually takes?
- **The twin case.** With two records present, the repair iterates both and pins each update to its
  own flag. Say whether that holds, and whether it interacts with S1-28, the collision that already
  makes `setSynchronizable` throw under twins, in a way that leaves the repair unreached.
- **Loosening a class.** The repair can move a record from device-only to `whenUnlocked`, which is a
  genuine weakening of protection for that item. It is what the flag already promised, and the
  alternative is a record that never syncs while every account does. Say if that trade is wrong.
- **`protectionMatchesFlag` is computed from `forSync`**, so the report and the repair share one
  definition of correct. A wrong definition would make the readout agree with the bug.

## What this fix does not attempt, stated so it is not reported as a finding

It repairs a device that runs this build. **A device that never runs it keeps its record as it is**,
and no phone can repair another, because a record in this state is not syncing. That limit is in the
commit message and in `A4-verify-S1-25-results.md`.

Nothing else is in scope. Two answers and their reasoning is the whole deliverable.
