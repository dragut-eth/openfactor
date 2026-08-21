# A4: the closing opinion

**Asked once per engine, in a fresh conversation**, pointing the engine at its own published record
rather than continuing one of its passes.

Continuing a pass was the first plan and it was wrong. An engine's last conversation holds one
scope, so its opinion would rest on a fraction of what it looked at, and which fraction would
depend on the order the scopes happened to run in. Reading its own record gives it everything it
found, and gives the opinion the property a published one ought to have: **anybody can reproduce it
from this repository** rather than taking on trust a conversation only one person saw.

**The record is larger than it was when this was designed.** The original said "four scopes and two
rounds". It is now four scopes, up to seven review rounds each, nine verification rounds, thirteen
hardware experiments, two waivers with their reasons, and two findings withdrawn.

## What the engine is told

Everything below is deliberate. The last three paragraphs exist to make praise the harder answer
rather than the easy one.

```
In docs/audits/ of this repository is the record of the review you did of this app, and of what
happened to what you found. Read your own passes across all four scopes, the triage notes beneath
them saying which findings were accepted and which rejected and why, and the verification rounds,
where fixes were put back to you as closed questions.

Read three things in particular, because they are the ones an opinion should account for.

A4-verify-final-results.md records that a finding all three reviewers verified as fixed was not
real, that one reviewer supplied the premise, and that the work done in its name removed test
coverage. If that reviewer was you, say so.

Two findings were waived rather than fixed, with reasons: S1-33 and S1-40, recorded in
A4-verify-S1-31-results.md. Say whether you accept those reasons.

docs/MASVS.md is a self-assessment against an external control list, written by the same person
who wrote the code, published with two partials and one outright fail. Say whether you believe it.

Then write a short opinion, ten to fifteen sentences, for somebody deciding whether to trust this
app with their two-factor codes.

Write it for a security-conscious friend rather than for the developer. Say what you would warn
them about and what you would not trust this app with. Name what you could not assess from what
you were shown, and why that matters. If any of your findings were rejected and you still think
you were right, say so.

Do not summarise the project's own claims back to me; assume the reader can read the README. Do
not grade the process: the question is whether the app is trustworthy, not whether the review was
thorough. A review that found three highs is evidence about the code before the review, not a
reason for confidence on its own.

This is published whole under your name, including anything unflattering, so write what you
actually think rather than what would be encouraging. If your honest answer is that you would not
yet trust it, that is a publishable answer and the one this project most needs to hear.
```

## What is published, and how

**Whole, attributed, unedited except for one thing**: absolute paths from the reviewing machine are
rewritten as repository-relative, which is the same edit made to every pass in this directory.

**A bland opinion is a fact about the method worth publishing, not a reason to ask again.** Nothing
here is re-asked until it improves, and nothing is trimmed to read better.

**If an opinion contradicts this project's own claims, the opinion is published and the claim is
re-examined**, not the other way round.
