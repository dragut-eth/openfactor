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

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

GPT:
Are the items fixed?
S4-42: Yes. pending now admits only entries whose single no-follow fstatat identifies them as regular files. Stale sweeping still obtains timestamps for every stattable entry kind and removes removable entries by age; directories remain nonrecursive and cannot become candidates.
S4-44: Yes. openat(descriptor, ".") creates a new open-file description with an independent directory offset. Descriptor ownership and failure cleanup are correct. The repeat-listing test fails with the former dup implementation, and the sub-second test fails if nanoseconds are removed—even when its writes cross a whole-second boundary.

Does either fix introduce a new high or medium? No. The read/sweep asymmetry is appropriate: only readable candidates must be regular files, while cleanup should still consider other removable entry kinds. Declining AT_REMOVEDIR preserves the nonrecursive deletion boundary. A hostile sibling can leave directories behind, but they can no longer obstruct collection.

No files were changed, and no builds or tests were run.

Fable:
Both fixes verified against the code at cab3312. Here is the deliverable.

Q1 — Is each item fixed?

S4-42: Yes. pending now admits a candidate only through guard let entry = handle.entry(name), entry.isRegularFile else { return nil } (SharedInbox.swift). entry(_:) derives the kind from the same fstatat(..., AT_SYMLINK_NOFOLLOW) that yields the timestamp, so a directory (S_IFDIR), a symlink (S_IFLNK), a pipe, or a socket named with a canonical UUID is no longer a candidate — the genuine share, a regular file, is what a collection reaches for, and the plant can no longer hide it. Checking the two things the brief names:

No non-regular entry can still become a candidate. The gate admits only S_IFMT == S_IFREG, and take independently re-verifies on the opened descriptor (BoundedFile.read(descriptor:) requires S_IFREG), so even a kind that changed between the stat and the open is refused at read rather than mis-handled.
The sweep still removes by age what it should. sweepStale deliberately uses modified(_:) (kind discarded), so it continues to age out foreign leftovers of every removable kind via unlinkat(name, 0). The one kind it cannot remove is a directory, which unlinkat without AT_REMOVEDIR refuses — the declared, accepted limitation, not an incomplete fix. A persistent planted directory is inert: excluded from pending, so it hides nothing, and it holds only what a sibling could already accumulate directly.

S4-44: Yes. Two parts, both addressed. The dup-offset defect is fixed: names() now takes openat(descriptor, ".", O_RDONLY | O_DIRECTORY), which creates a fresh open file description with its own offset, so each listing reads from the start; fdopendir consumes that fresh descriptor and closedir closes it, leaving the type's own descriptor untouched. Checking the brief's three sub-questions:

openat(descriptor, ".", …) genuinely yields an independent offset — a fresh open (unlike dup, which shares the offset), and . resolves to the directory the descriptor already names and cannot be a symlink, so the capability property is preserved.
The new tests fail against the defects they pin — listingIsRepeatable asserts a second listing still returns ["a"], which goes red under the old dup path (second listing starts at end, returns []); subSecondTimestampsAreDistinguishable writes two files 20 ms apart and asserts second > first with a sub-second gap, which goes red under whole-second resolution (identical tv_sec ties them); removingRefusesADirectory asserts both a subdirectory and its contents survive a remove, which goes red if the removal recurses.
The ordering property now has coverage whole-second resolution would break — subSecondTimestampsAreDistinguishable is exactly that coverage; it did not exist before, and the only prior ordering test slept over a second.
Q2 — Does either fix introduce a new high or medium? No.

Working through the surfaces the brief flagged:

entry(_:)/modified(_:) split. modified(_:) is entry(name)?.modified over the same single fstatat, and still returns a Date for any kind, so sweepStale's behaviour is unchanged; pending is the only caller that consumes the kind. No caller relied on the old behaviour in a way this breaks.
names() opening a fresh descriptor per listing. listing is closed exactly once on every path — by closedir on success, by explicit close when fdopendir fails — and the type's own descriptor is never handed to fdopendir, so no leak and no double-close. A spurious openat failure returns [], which is the same fail-safe posture as before (nothing presented, nothing deleted). . cannot resolve to anything but the directory the descriptor names.
The read/sweep asymmetry is correct, not a defect. The reading side must insist on a regular file, because admitting a non-regular newest candidate is the S4-42 hiding bug and because only a regular file is offered to a person; the sweeping side must not, because its job is to age out foreign leftovers of any removable kind, and gating it on regularity would let non-regular junk accumulate. Nothing dangerous reaches presentation, and everything removable is still removed.
Declining AT_REMOVEDIR is the conservative choice. It would add directory-deletion authority to a scope whose high (S4-33) and medium both came from added deletion authority, and it would not even close the accumulation (it removes only empty directories; a sibling can plant a non-empty one). A permanently unremovable inert directory is not a new attacker capability — a sibling can already fill the shared container directly — so it is not worse than the authority its removal would require.

What I checked to conclude nothing: the kind gate and take's re-verification for S4-42; the openat-. offset semantics, the close paths in names(), and each new test's discriminating assertion for S4-44; and the four named surfaces for Q2. I did not review anything outside these two items.

Grok:
1. S4-42: yes. S4-44: yes.

S4-42: pending admits a UUID name only when entry(name).isRegularFile is true, from the same fstatat as the timestamp. A UUID-named directory, FIFO, socket, or symlink is not a candidate; aDirectoryIsNotAnItem plants a newer UUID directory beside a real share and expects only the share. sweepStale still goes through modified, so stale leftover files, links, and sockets are still age-removed. Directories still fail unlinkat without AT_REMOVEDIR and stay, which is the declined half, not an open half of the finding.

S4-44: names() uses openat(descriptor, ".", O_RDONLY | O_DIRECTORY), a new file description with its own offset, not a dup. listingIsRepeatable would fail on the old dup (second listing empty). subSecondTimestampsAreDistinguishable writes 20 ms apart and requires second > first and a gap under one second; whole-second tv_sec would tie them and fail the first of those. fdopendir failure still closes the listing fd; the type’s descriptor is untouched. . relative to an already-open directory fd cannot be a symlink.

2. No.

entry / modified is one stat; the sweep still wants a timestamp regardless of kind, and only the reading side offers an item. That split is right. Declining AT_REMOVEDIR leaves a planted directory in the group forever, unlistable. A sibling that can plant it can already fill the container; restoring directory deletion is the authority this scope has already used to destroy data. The split is not a new medium.
