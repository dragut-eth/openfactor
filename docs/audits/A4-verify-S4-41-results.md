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
