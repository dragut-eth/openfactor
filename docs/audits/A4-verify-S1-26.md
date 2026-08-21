# A4 verification: S1-26

**This is not a review round.** Two closed questions and nothing else. Do not report low-severity
findings. Do not review anything outside S1-26. **A thin answer is the correct answer**, and one
that says what was checked in order to conclude nothing is worth more than one that manufactures a
finding.

**The code under review is `a72bc3d`.** The finding was filed against `b3e7e08` and is written up in
`A4-round-five-scope1-results.md`. The three previous verification rounds are
`A4-verify-S4-41-results.md`, `A4-verify-S4-42-S4-44-results.md` and `A4-verify-S1-25-results.md`.

Read-only. Do not build and do not run tests; keep the checkout clean.

**Already known and open, so do not spend the round on it:** a wrapped record written before
`07e2972` can carry `kSecAttrSynchronizable = true` beside a device-only class, and nothing repairs
it. That is S1-31, recorded in `A4-verify-S1-25-results.md`. It matters here only if it changes
what `save` should do, which is a question worth one sentence and not more.

## The finding, as filed

`save` guarded on `countingBothFlags() <= 1` and then ran a **separate** `SecItemCopyMatching`
under `Any` with `kSecMatchLimitOne` to choose what to update. Two reads of a store another device
writes into can disagree: a record arriving between them is invisible to the guard and can be what
the second query returns, so `SecItemUpdate` lands on a record nothing counted and nobody examined.
When that record is the synchronizable one it is the other live vault's only recovery credential,
replaced on every device at once.

The filed remedy: fetch `candidates()` once, require exactly one, and update under that candidate's
captured flag rather than performing a second selection. The alternative offered was to withdraw
passphrase replacement until a targeted operation existed.

## What was changed

`save` performs **one** read. `candidates()` supplies both the count and the flag of the record to
write, the refusal is decided from that read, and the update is pinned to the flag that read
observed. A record arriving afterwards lands under the other flag and is not this write's target.
If the observed record has since gone, the update finds nothing and `save` throws.

## The test seam, which is the part most worth disagreeing with

**A non-racy test cannot tell the two versions apart**: both write the same record when nothing
changes underneath, so a test that does not express an arrival is green either way. That is the
failure this gate has found repeatedly, most recently in a test of the author's that passed before
its own fix existed.

So `WrappedKeyStore` gained an internal `duringSave` closure, `nil` on every path that ships,
reachable only through an internal initialiser, firing in the gap between the read and the write.
The hosted test makes it do what iCloud reconciliation does: the observed record is gone, and a
different one is present under the opposite flag.

**This is a test hook in production code and the author knows what that costs.** The argument made
for it is this gate's own finding that untestable code is where defects pool, and that this project
has already paid for it twice, in a vault suite that never ran and in a fake whose `save` could not
represent a twin. **Say if that trade is wrong**, and say what you would have done instead to make
this verifiable.

## The two questions

**1. Is S1-26 fixed? Yes or no.** If no, one sentence on what remains.

Judge the code. Is there any remaining path on which the record written is not the record observed?
What is left in the window between `candidates()` and `SecItemUpdate`, and is what remains
acceptable or merely smaller?

**2. Does the fix introduce a new high or medium?** Yes or no. If yes, name it and give the call
order.

The surfaces where the author is least confident:

- **`save` now throws when the observed record has gone.** Previously it would have found and
  written something. Is failing right, and does any caller handle the throw badly?
- **The add branch.** When `candidates()` returns nothing, `save` adds. A record can arrive between
  that read and the `SecItemAdd`. Nothing was done about it. Say whether that needs the same
  treatment or is a different question.
- **The seam itself**, beyond the trade: an internal `let` on a `Sendable` struct, an internal
  initialiser beside a public one, and a closure called on the write path in every build even
  though it is always `nil`.
- **The fake still cannot express this.** `InMemoryWrappedStore.save` holds one lock across its
  count and its replacement, so it remains atomic where the adapter is not. That divergence was
  named in round five and is unchanged. Say whether the hosted test is sufficient without it.

Nothing else is in scope. Two answers and their reasoning is the whole deliverable.
