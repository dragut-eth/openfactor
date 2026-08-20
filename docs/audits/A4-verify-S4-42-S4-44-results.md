# A4 verification: S4-42 and S4-44, answered

Reviewed commit: `cab3312`. Both findings were filed against `4b8317f` and are written up in
`A4-round-five-scope4-results.md`.

## The answers

| Engine | S4-42 fixed? | S4-44 fixed? | New high or medium? |
| --- | --- | --- | --- |
| ChatGPT | Yes | Yes | No |
| Fable | Yes | Yes | No |
| Grok | Yes | Yes | No |

**Unanimous on every question, and no engine reported anything else.** Second verification round in
a row that returned a verdict rather than a backlog.

## Two things they found that the fix did not know about itself

**`take` re-verifies the kind on the opened descriptor**, so the gate in `pending` is not the only
thing standing between a plant and a read. Fable's point: even an entry whose kind changed between
the `fstatat` and the `openat` is refused at read, because `BoundedFile.read(descriptor:)` requires
`S_IFREG` on the descriptor it was handed. **That is a time-of-check window closed by a check that
was already there**, and it was not part of the reasoning for the fix.

**The sub-second test discriminates even across a second boundary.** ChatGPT checked the case I had
not: if the two writes happen to straddle a whole second, `tv_sec` alone would give different
values and `second > first` would still hold. The test survives that because it also asserts the
gap is under a second, which whole-second resolution makes exactly 1.0. **The test is stronger than
the reasoning I wrote for it.**

## The declined `AT_REMOVEDIR`, which the brief asked them to disagree with

All three back the decision, and two give a reason better than the one I gave.

I argued from deletion authority: this scope produced a high and a medium by adding exactly that,
and non-recursion is the property the primitive's tests now pin. All three accept that.

**Fable adds that the flag would not even work.** `AT_REMOVEDIR` removes only *empty* directories,
and a sibling can plant a non-empty one. So it buys back deletion authority without closing the
accumulation it was proposed to close.

**Grok and ChatGPT both make the capability point**: a sibling that can plant a directory can
already fill the container directly, so an inert unremovable directory is not a new attacker
capability. Grok's summary of the trade: restoring directory deletion is the authority this scope
has already used to destroy data.

## The read and sweep asymmetry

All three call it correct rather than tolerable, and give the same account of why: the reading side
must insist on a regular file because only a regular file is offered to a person, and admitting a
non-regular newest candidate is the hiding bug itself. The sweeping side must not, because its job
is to age out foreign leftovers of any removable kind, and gating it on regularity would let
non-regular junk accumulate.

Fable states the resulting invariant plainly: nothing dangerous reaches presentation, and
everything removable is still removed.

## The rest of what was checked

**`names()` opening a fresh descriptor.** All three confirm `openat(descriptor, ".", …)` creates a
new open file description with its own offset rather than sharing one, that `.` cannot resolve to
anything but the directory the descriptor already names, and that the listing descriptor is closed
exactly once on every path: by `closedir` on success and by an explicit `close` when `fdopendir`
fails. Fable adds that a failed `openat` returns an empty list, which is the same fail-safe posture
as before: nothing presented, nothing deleted.

**`entry(_:)` and `modified(_:)`.** One `fstatat`, kind discarded for the sweep, and no caller
relied on the old behaviour in a way the split breaks.

**The new tests.** Each engine walked what each one would go red against: the repeat listing under
the old `dup`, the ordering under whole-second resolution, and the removal if it recursed.

## On the format, after two uses

Two rounds, six answers, no new work. The thing worth continuing to watch is the one recorded last
time: **a bounded question invites a bounded look.** The mitigation is holding, in that Fable again
closed with what it checked in order to conclude nothing and what it did not review. ChatGPT's
second-boundary check and Fable's `take` observation are both evidence that a narrow question does
not have to produce a shallow answer.
