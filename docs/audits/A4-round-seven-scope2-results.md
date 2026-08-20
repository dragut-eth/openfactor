# A4 round seven, scope 2: the two corrections, read by three

Reviewed commit: `51d34b1`. Round six read `1f7e65f`. The chain from `74fe841` is unbroken.

Round seven was deliberately narrow. The change under review was comments and nothing else: four
files, no executable line, no test. The round existed to settle round six's three-way split on the
exit condition, and the prompt said so, and said plainly that a thin answer would be the correct
answer.

## The short version

**All three engines confirmed the three substantive things the round asked about.** Three is the
right number of phone-side decisions under the header's own bar, each having independently
constructed candidates and rejected them rather than checking the list. The two headers agree in
substance, so the twin-divergence class that ran four rounds is closed. And the four core comments
are true of every path that reaches them: a nonce-less decline arises exactly two ways, no third
producer exists, and no direct reply can reach `shouldHonourDecline` by any route.

**Three new findings, all low, all in comments.** Two are confirmed here against the code. The
third is contested between engines on the definition of the bar, and is recorded as contested
rather than resolved.

**The split did not move.** Two engines close, one does not, and it is the same engine as last
round.

## S2-26 (low): the paragraph under the list now contradicts the list

Found by Fable. Verified here, and it is collateral from the round six fix rather than something
that survived it.

`ProvisioningDesk.swift` gained two bullets naming the phone's refusal rules. Directly beneath the
list, unchanged, sits the paragraph written in round five for the two-bullet version:

> Those are decisions. They predate this extraction and none of them produced a finding in this
> gate, which is the reason they were not moved.

**That is false twice over for the two entries just inserted above it.** Both refusal rules
postdate the extraction, having been created by round five's fixes in `9304d6c`, and both exist
*because* of findings, S2-14 and S2-15, one of which the bullet three lines above cites by number.
The header asserts and refutes the same fact within one screen.

The stated reason-not-to-move also silently stops covering them. Their actual reason is different
and defensible: they wrap the `WCSession` send itself.

**This is the fifth instance of the class, in its smallest form yet.** Not a twin file left
behind, but a neighbouring sentence left behind by the edit made to close the twin problem.

## S2-27 (low): "nothing was ever read out of it" is false for one refusal path

Found by ChatGPT. Verified here against `WatchProvisioning.validate`.

`WatchInbox.Nonce.absent` says a current phone replies `declined` with no nonce to a request that
failed to parse, "because nothing was ever read out of it". `MessageKey.nonce` makes the same
inference: the request failed to parse, "so there is nothing to echo".

`validate` refuses three ways, and the claim is only true of two of them. Wrong length throws
`.malformed` before anything is read, and a bad magic throws `.unsupportedVersion` after four
bytes. But an 85 byte request with the right magic and an invalid P-256 point reaches
`take(nonceCount)` first: **the nonce is read, and then the public key check throws.** ChatGPT's
example is `"OFW1" || nonce(16) || 0xAA x 65`.

**The behaviour is right and only the rationale is wrong.** What is true is the narrower statement:
no validated request and no retained nonce ever returns to the caller, so the caller has nothing to
echo. The reason is the caller's hands being empty, not the parser's eyes being closed.

## S2-28 (low, contested): is the watch's reply routing a fourth app-target decision?

Found by ChatGPT. Explicitly excluded by Fable and by Grok, each having gone looking for a fourth
and reported none. Recorded as a disagreement rather than settled, because the disagreement is
about the bar and not about the code.

`WatchVaultModel.phoneAnswered` decides that any direct reply not classified as `.answer` becomes
`flow.phoneAnswered(nil)`, terminating the attempt at once. ChatGPT's case: delete that routing and
a nonce-less direct decline stops terminating the attempt, which then waits for the 25 second
timeout instead. The package suite stays green either way, because nothing here is reachable by it.

**ChatGPT's reading**: that satisfies the header's stated bar, so an enumeration presenting itself
as exhaustive is missing an entry, and both headers share the omission rather than diverging.

**Fable's and Grok's reading**: the bar is deletable, suite green, *and the protocol behaves
differently*. This routing sends nothing. It changes what the wearer waits through, not what
travels on the wire, which is the same reason Fable excluded the 25 second timeout arming and put
it under the watch cadence bullet. Fable's excluded list also names the `isAsking` mirrors, the
`isFrontmost` and `hasVault` bindings, and the reply wrapper's empty answer, with a reason for
each.

**The unresolved part is real.** The desk header's watch bullet names three specific things, when
to ask, `keyOpensNothing`, and the `hasReplacedStaleKey` latch. Reply routing is not obviously one
of them, so if ChatGPT's reading of the bar is taken, neither header covers it.

## What all three confirmed

**The count.** Every engine constructed its own candidates rather than verifying the list, which is
what the prompt asked for. The three that qualify are the timer arming, the unnamed-refusal guard,
and the failed-release refusal.

**The headers.** Word for word on the second entry, the same rules in slightly different prose on
the first and third, and both carrying the not-edited-alone rule. Fable, which made closing
contingent on both files being corrected together, states the contingency was met.

**The core comments.** `refuse(naming:)` takes a non-optional nonce and is the only standalone
decline constructor in the project, grep-verified again at this commit. `received` returns
`.declined` only on a validate failure. `shouldHonourDecline` has one call site, in `phoneSent`,
reachable only from the no-reply delegate method. A reply arrives only in the `sendMessage` reply
closure. There is no route from one to the other.

**Nothing was introduced by the comment edits**, beyond S2-26 above, which was introduced by what
the insertion made false around it rather than by anything written. Every added comment sits in an
existing doc block on the same declaration, so the doc-comment placement hazard did not arise.

**Two engines noted they could not verify the commit message's build and test claims**, having been
told to keep the checkout clean. That is correct and worth recording: those claims are this
repository's, not theirs.

## The exit condition

- **Fable: close.** The contingency it set was met. It scores both fixes complete and files S2-26
  as a new low rather than as incompleteness, consistent with how this gate scored the equivalent
  situation in rounds four and six. It adds that the stop rule's test, whether shipping unreviewed
  would be the bet the gate refuses, cannot be met by a paragraph correction.
- **Grok: close.** Nothing above low, no fix incomplete, both fixes complete in every file.
- **ChatGPT: do not close.** Both fixes it called incomplete in round six remain narrowly
  incomplete: the enumeration still claims to be exhaustive and misses a decision, and the parse
  rationale replaced a false claim with an overstatement.

Two to one, unchanged from round six, with the same engine dissenting for a consistent reason.

## The structural recommendation, which is the most useful thing this round returned

Fable's closing point, recorded because it is about the method rather than about a finding:

**This class has now recurred five times, and every instance was a history-narrating comment.** Who
found what, when a rule was born, why it stayed. Code comments have to track a moving codebase.
Append-only history already has a home in `docs/audits/`.

Headers that state only what is true now, and point at the audit record for how it came to be,
would remove the entire class rather than its latest instance. Fable's own words for what that
would look like: three decisions stay here, deleting any leaves the suite green.

**The security content of this scope stopped producing findings three rounds ago.** The comments
about its history are the only thing this gate can still catch.

## Scope 2 is closed

Closed on 2026-08-19, after seven rounds and twenty six accepted findings, on the amended exit
condition recorded in `docs/ROADMAP.md`.

**What closed it was not this round's verdict.** Two engines said close and one said do not, the
same two to one as round six, with the same engine dissenting for the same consistent reason. The
rule as first written could not resolve that, and the reason it could not is the finding this
scope ends on.

**The rule had no severity floor on its second half.** "No fix called incomplete" is a condition
that three independent readers looking at prose can always fail, because there is always a
sentence one of them would sharpen. It is not a stop rule, it is a treadmill. The floor now says a
finding that lives only in a comment or a document is recorded and does not hold a scope open.

**The evidence for the floor is this scope's own last four rounds.** Rounds four through seven
produced no code defect at all. Every finding in them was a false claim in a comment, and by round
six the fixes were creating the next round's findings at close to one for one: S2-26 was created
by the fix for S2-24, which was created by the fix for S2-17. The gate had begun reviewing its own
exhaust, and the exhaust was text written during the gate.

### The three findings, and how they were dealt with

**S2-26 and S2-27 are fixed**, not because they held the scope open but because they are false and
a false comment gets corrected. The rationale in `Nonce.absent` and `MessageKey.nonce` now says
what is actually true: the parser may well read the nonce bytes before rejecting the public key
after them, and what makes the reply nonce-less is that no validated request reaches the caller.
Empty hands, not closed eyes.

**S2-28 is dissolved rather than decided.** It asked whether an enumeration presenting itself as
exhaustive had missed a decision. The enumerations no longer present themselves as exhaustive.
Both now say the entries are listed because each is removable with the suite still green, and say
in as many words that this is not a claim the list is complete. An exhaustive claim about a
surface no test reaches is a claim that has to be re-verified by a person forever, which is the
mechanism that produced this class in the first place.

### The comments were rewritten, which is the real remedy

**All five instances of the surviving class were history-narrating comments.** Who found what,
which round rejected which sentence, what a paragraph used to say. History is append-only and code
is not, so every such sentence is falsified by the next change to the thing it describes, and
nothing catches it.

The scope 2 files now state what is true in the present tense and point at `docs/audits/` for how
it came to be. The reasoning that makes a rule non-obvious stayed, because that is what stops
somebody deleting the rule. What left is the narration: round numbers, finding numbers, which
engine said what, and any sentence whose truth depended on a state the code has left.

**The same narration exists throughout the vault and parser files and was deliberately not touched
here.** Scopes 1 and 4 are still open, and putting a large unreviewed prose diff into files three
cold readers are about to read would be the same bet this gate exists to refuse. It is the first
thing to do when those scopes close.

### What the scope actually returned

Seven rounds. Twenty six accepted findings. Two races, a consent window on a wall clock, a refusal
that could end an attempt it did not name, a nonce merged with its own absence, an answer that
left the watch waiting for a message that could never arrive.

**The last code defect was found in round three.** Rounds one to three earned the gate. Rounds
four to seven bought the knowledge that this scope was finished, which is worth something, and
three rounds of prose correction, which is worth less than the reviewer time it took. The floor
exists so the next scope does not pay for that lesson twice.
