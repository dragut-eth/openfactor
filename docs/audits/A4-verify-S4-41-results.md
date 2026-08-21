# A4 verification: S4-41, answered

Reviewed commit: `c759ead`. The finding was filed against `4b8317f` and is written up in
`A4-round-five-scope4-results.md`.

## The answers

| Engine | Fixed? | New high or medium? |
| --- | --- | --- |
| ChatGPT | Yes | No |
| Grok | Yes | No |
| Fable | Yes | No |

**Unanimous on both questions, and no engine reported anything else**, which is what the format
exists to produce.

## What they checked

All three confirmed the same two properties the brief asked about, independently.

**No remaining path observes a comparison clock before the timestamp it judges.** Both functions
stat, then sample, then compare, per entry. Fable adds the check I had not done myself: it walked
**all three production call sites**, `sweepStale()` at `OpenFactorApp.swift:226` and `:245`, and
`pending()` via `InboxOpener.swift:61` and `OpenFactorApp.swift:288`, and confirmed none of them
captures a `Date` to pass in. Nothing reintroduces the early sample from outside. It also confirmed
that `sweep(_:)` and `take` perform no timestamp comparison at all, so these two functions are the
whole surface.

**The anti-plant branch still refuses a plant.** A file stamped in 2090 exceeds every observation,
becomes `.distantPast`, sorts last in `pending` and is immediately past `staleAfter` in
`sweepStale`. Fable's phrasing: the fix discriminates the genuine mid-pass share from the plant
**by call order alone, with no tolerance window**, which is what the finding asked for.

Grok names both ways a mid-pass arrival is now safe: either it is not in `names()` yet, because the
listing finished before any clock read, or it is listed and judged against a clock taken after its
own stat.

## The two surfaces the brief handed over

**The clock read many times per pass.** All three say nothing in either function needed a single
consistent `now`. Fable gives the reason rather than the verdict: `pending` sorts by each entry's
absolute stamp, not by an age relative to a shared instant, so a per-entry observation cannot change
the ordering, and the future-clamp classification is identical whichever microsecond the
observation falls in, because a real file always satisfies `stamped <= observed` and a plant always
exceeds it. In `sweepStale` the per-entry clock is **strictly more correct**, since each file is
judged by its true age at the moment it is examined.

**`pending` dropping an entry it cannot stat.** All three accept it and none promotes it. Fable
adds the detail that makes it comfortable: an entry that can be listed but not `fstatat`-ed is
almost always one already unlinked in the race, so there is usually nothing there to sweep. The
residual is an unstattable file lingering in the container, which every engine classes as hygiene
rather than data loss, and explicitly below the threshold this round reports.

## On the format

**This was the first verification round, and it did what it was for.**

Three engines, three answers, no new findings, nothing to triage. Every previous round in this gate
returned work; this one returned a verdict. The two closed questions were both load bearing: the
first settled the fix, and the second is the one that has caught real damage five times in this
gate, so it stays.

The one thing worth watching is that a bounded question invites a bounded look. Fable listed what
it inspected and what it did not, which is the right shape for that risk: **the round's coverage is
stated rather than assumed.**

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

GPT:
Is S4-41 fixed? Yes. Both pending and sweepStale now read each entry’s timestamp before sampling the clock that judges it. A genuine mid-pass arrival is no longer mistaken for future-dated, while an actual future-dated plant still maps to .distantPast. pending also omits entries it cannot stat instead of inventing an age.

Does the fix introduce a new high or medium? No. Neither operation requires one pass-wide now; its decisions are entry-local. Calling the clock per entry preserves ordering and freshness semantics. An unstatable entry may remain until a later pass, but that is not a new high or medium.

No files were changed, and no builds or tests were run.

Grok:
1. Yes.

pending and sweepStale both stat (modified(name)), then call now(), then compare. Nothing in either function samples the comparison clock before the timestamp it judges. A plant at now + 86400 is still stamped > observed, still .distantPast, still sorted last and removed; futureTimestampsAreRefused still describes that.

A share that lands during the pass is either not in names() yet (listing finished before any now()), or is listed and then judged against a clock taken after its own stat, so an honest mtime is not the future branch.

2. No.

Per-entry now() does not need a single pass-wide sample: each age is a property of that file. Dropping an entry pending cannot stat means it is neither presented nor identity-swept, and sweepStale already skipped it; that is leftover occupancy, not a new high or medium.

Fable:
Both questions verified against the code at c759ead. Here is the deliverable.

Q1 — Is S4-41 fixed? Yes.

In both pending (SharedInbox.swift:207) and sweepStale (:309) the clock is now @Sendable () -> Date and is read via now() after the entry's own fstatat (handle.modified(name)), per entry — stat first, then sample, then compare, exactly the filed remedy.

Checking the two things the brief names:

No remaining path observes a comparison clock before the timestamp it judges. These are the only two functions that compare a timestamp against a clock. In each, let observed = now() sits strictly after handle.modified(name), inside the per-entry body, so a share that lands mid-pass has stamped ≤ observed and is treated as ordinary (in sweepStale its age is then seconds, below staleAfter, so it is kept; in pending it is not mapped to .distantPast, so it does not fall into the superseded set). sweep(_:) and take do no timestamp comparison. All three production call sites pass the default live clock — sweepStale() at OpenFactorApp.swift:226 and :245, and pending() via InboxOpener.swift:61 and OpenFactorApp.swift:288 — none captures a stale Date, so nothing reintroduces the early sample.
The future-timestamp branch still refuses a genuine plant. stamped > observed ? .distantPast : stamped is unchanged in effect: a file stamped in 2090 exceeds every observed, becomes .distantPast, and is therefore sorted last in pending and immediately over staleAfter in sweepStale. The fix discriminates the genuine mid-pass share from the plant by call order alone, with no tolerance window, which is precisely what the finding asked for.
Q2 — Does the fix introduce a new high or medium? No.
Clock read many times per pass rather than once. Nothing in either function needs a single consistent now. pending sorts by each entry's absolute stamped, not by an age relative to a shared instant, so per-entry observed cannot change the ordering; the future-clamp classification is identical whichever microsecond observed falls in, because a real file always satisfies stamped ≤ observed and a plant always exceeds it. In sweepStale the per-entry clock is strictly more correct — each file is judged by its true age at the moment it is examined — which is the fix, not a regression. now is a pure @Sendable read with no shared mutable state, so the repeated calls raise no concurrency issue.
pending dropping an entry it cannot stat. This is the safe direction and was the explicitly requested change: the prior code invented .distantPast and could then delete such an entry for an age nobody measured, whereas now it leaves it. sweepStale independently skips the same unstat-able entry (guard let modified … else { continue }), so the two agree, and an entry that can be listed but not fstatat-ed is almost always one already unlinked in the race (nothing to sweep). The worst residual is an unstat-able file lingering un-swept in the app-group container — an availability/hygiene nit at most, not a confidentiality or data-loss defect, and below the threshold this round reports.

I checked the two comparison sites in SharedInbox.swift, the three production callers' clock argument, and the anti-plant branch's behaviour under the reordering; I did not review anything outside S4-41.
