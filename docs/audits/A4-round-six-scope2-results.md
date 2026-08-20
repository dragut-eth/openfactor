# A4 round six, scope 2: what three cold readers found in the five

Reviewed commit: `1f7e65f`, delivered as checkout `a644d88` (the same tree plus the round five
results file). Round five read `9304d6c`. The chain from `74fe841` is unbroken.

Sent to Fable, ChatGPT and Grok. All three read the same five fixes: S2-17, S2-19, S2-21, S2-22,
S2-23.

## The short version

**No code defect.** Nothing above low. The entire code delta this round reviewed is one comparison
character, one internal accessor, comments, and test re-anchoring, and all three engines read all
of it rather than sampling.

**Two new low findings, both false claims in comments, both found independently.** They are
recorded below as S2-24 and S2-25.

**The engines split on the exit condition**, which is the interesting part of the round.

## S2-24 (low): the seam header counts two decisions and there are three

Found by Fable and ChatGPT independently. Verified here.

`WatchKeyProvider.swift:38` says what stayed in the app target is "the session, the alert, the key
file, the sending, **and two decisions**": arming the expiry timer on `answer == .asking`, and not
sending a refusal it cannot name.

There is a third, in `approve()`'s release path at `WatchKeyProvider.swift:87-93`. A phone that
cannot read its own key, or cannot build a response, sends a named refusal rather than going quiet.
That is a policy choice with a wire consequence, it was itself finding S2-15 once, and it meets the
header's own stated bar for what must be listed: delete the `refuse` call from that guard and every
test in the package stays green while the S2-15 silence returns.

Fable adds a second half. `ProvisioningDesk`'s twin header at `ProvisioningDesk.swift:18-30`
enumerates what stayed behind as the timer arming and the watch's asking cadence, and names neither
refusal rule, under an intro line that reads as complete. **The two headers now disagree with each
other**, which is the same shape as the finding that held this scope open in round five: a sentence
corrected in one file and not its twin.

Nothing in the code is wrong. Each of the three decisions is correctly documented at its own site.
What is wrong is a count, and a second enumeration that does not match it.

## S2-25 (low): the core's decline comments still say "an old phone"

Found by ChatGPT. Verified here.

`VAULT.md` and `SECURITY.md` were corrected in round five to distinguish a standalone refusal, which
always carries a nonce, from a direct reply to a request that failed to parse, which carries none
and needs none. **That distinction was not propagated into the core.** Four comments still state the
pre-correction rule without qualification:

- `WatchInbox.swift:30`, `Nonce.absent`: "a phone built before the field existed"
- `WatchInbox.swift:43`, `Message.decline`: "The second message, refusing"
- `WatchInbox.swift:81`, `shouldHonourDecline`: a nonce-less decline comes from an old phone
- `WatchProvisioning.swift:116`, `MessageKey.nonce`: the same unqualified compatibility claim

The path that makes them false is current, not hypothetical: a malformed request makes
`ProvisioningDesk.received` return `.declined`, the phone replies `["status": "declined"]`, and
`WatchInbox.classify` reads that as `.decline(.absent)`. So `.absent` and `.decline` now describe a
current direct reply and not only an old phone's standalone second message.

**The behaviour stays correct**, and all three engines checked this rather than assuming it. The
reply lands in `phoneAnswered`, which is bound to its own attempt's token by the reply closure and
guards `flow.isCurrent(token)` before anything else, and which never consults
`shouldHonourDecline` at all. A nonce-less decline on that path can only ever end the attempt that
asked for it.

## The five, as each engine scored them

**S2-17**: the false sentence is gone from `WatchKeyProvider` and the history is recorded in the
file. The two decisions it names are real and accurately described. The replacement miscounts, which
is S2-24. Grok scored it complete. Fable filed the miscount as a finding but declined to score the
fix incomplete. ChatGPT scored it incomplete.

**S2-19**: complete, unanimously, and Fable withdrew its round five abstention. The comparison is
strict, both sides of the exact instant are pinned by tests anchored on the request's own instant,
and the comment states the trade honestly: a tap at exactly the window now refuses, which is equally
unreachable and is the fail-closed side. Grok still believes the instant is unreachable and still
does not ask for `<=` back. Both callers were checked: approve at the window refuses, expire at the
window fires.

**S2-21**: the reasoning survived the attack the brief invited. All three engines verified in code
rather than accepting the claim, and reached the same place: the reply channel binds a declined
answer to its request at least as strongly as a nonce would, resting on the same delivery guarantee
the exchange already declares load bearing. Changing the wire would mean inventing a nonce for a
request that failed to parse and has none. The documents were the right thing to fix. ChatGPT scores
the documentation half incomplete because the correction stopped at the two markdown files, which is
S2-25.

**S2-22**: complete, unanimously. The comment names the declined reply, explains why the outcome is
right by rule rather than by coincidence, and carries the sealed-key footnote.

**S2-23**: complete, unanimously. `pendingInstant` is internal and read only, exposes nothing that
was not already internal, and all five window tests now anchor on it. The flake path is gone.

## Nothing was introduced

All three engines looked and none found anything. The `OpenFactorApp` changes visible in the diff
are scope 1 and scope 4 work landing in a file this scope reads, and Fable checked the specific
dependency: the watch alert block, its `isAsking && !lock.isLocked` binding, and the
`scenePhaseChanged` to `PrivacyShield.apply` ordering ahead of it are untouched, and the reconcile
call added to the scene phase handler runs after the shield is applied.

## The exit condition, and where the engines part

The rule as written: a scope closes when a round returns nothing above low **and** no fix is called
incomplete.

- **Grok: stop.** Against the rule as written, this pass meets it.
- **Fable: close, contingent on the correction being made in both files.** Its argument is that the
  rule exists to stop unreviewed substantial change from shipping, that the remedy here is a
  documentation edit with no code path and no wire byte, and that holding three engines open for a
  count would be the rule serving its letter against its purpose. It states plainly that if the
  maintainer reads the rule more strictly, round seven is a review of one sentence, and it is
  willing to be the engine that says so now.
- **ChatGPT: do not close.** Two fixes are incomplete, therefore the second half of the rule fails.

So the rule as written does not clear. One engine called two fixes incomplete, and the fact that
the incompleteness is a count in a comment does not change what the rule says.

## The trajectory

Six rounds, twenty six accepted findings. The state machine has produced no code defect since the
extraction. Round four found a false claim about what stayed in the app target. Round five found the
same claim uncorrected in its twin file. Round six found a count in the corrected replacement and a
correction that stopped at the markdown and did not reach the core.

**The defect class this scope now returns is a sentence corrected in one place and not the other.**
That is the fourth consecutive round in that family, and it is the reason any remedy here has to be
applied to both headers at once and checked, rather than to the one the finding names.

## What was fixed

Both findings, and both headers together, because the class is the twin.

**S2-24.** `WatchKeyProvider`'s header now names three decisions rather than two, as a list, each
with the deletion that would remove it while leaving the suite green: the timer arm, the unnamed
refusal, and the release-path refusal that was S2-15. It also records that the count has now been
wrong twice in opposite directions, first claiming everything moved and then claiming two.
`ProvisioningDesk`'s enumeration gained the same two phone-side entries in the same words, and a
closing line saying that neither list is edited alone.

**S2-25.** `Nonce.absent` now documents both ways a nonce can be missing and says which one
`shouldHonourDecline` is deciding about. `Message.decline` no longer calls itself the second
message. `shouldHonourDecline`'s own comment states that only standalone refusals reach it, and
names the other path and what binds it. `MessageKey.nonce` distinguishes the standalone refusal,
which always carries the field, from the direct reply, which carries none and needs none.

No code changed. 465 core tests pass, the iOS target builds, the watch app builds.
