# A4 verification: S1-37 and S1-28, answered

Reviewed commits: `c4360dd` for S1-28, `f75ce5b` for S1-37.

## The answers

| Engine | S1-37 fixed? | S1-28 fixed? | New high or medium? |
| --- | --- | --- | --- |
| ChatGPT | **Not fully** | **No** | No |
| Fable | Yes | Yes | No |
| Grok | Yes | Yes | No |

**Nobody found a new high or medium**, and the third round running has ended two to one with the
same engine dissenting. As before, the dissent is specific and one half of it is right.

## S1-38 (low): a twin forming between the count and the update still collides, and is misnamed

**Found by ChatGPT alone. Verified here, and Grok's contrary reading is wrong.**

`setSynchronizable` repairs, counts at one point, and updates at another:

```
guard try countingBothFlags() <= 1 else { throw .twinnedRecord }     // line 14
...
let status = SecItemUpdate(find as CFDictionary, changes as CFDictionary)   // line 26
guard status == errSecSuccess else { throw error(for: status) }
```

A record arriving between those two lines is invisible to the count, the update then collides with
it, `SecItemUpdate` returns `errSecDuplicateItem`, and `error(for:)` maps that to `.duplicate`.
`message(for:)` special-cases only `.twinnedRecord`, **so the retry advice that S1-28 removed comes
back in exactly this window.**

Grok wrote that in this situation the conversion "throws `twinnedRecord` rather than colliding".
That is true only if the count sees the pair, which by construction it does not. **The count-then-act
shape is the same one S1-26 was about**, and it was closed there by making one read serve both
purposes. It cannot be closed the same way here, because a count and an update are inherently two
calls.

**But the naming can be fixed cheaply and completely**: a collision at this update *is* the twin
case, by construction, so mapping `errSecDuplicateItem` to `.twinnedRecord` in this method makes the
answer honest whether the pair was there at the count or arrived after it. That does not close the
race and does close the misleading advice.

## S1-39 (low): the Keychain half of `SecretStoreTests` still runs nowhere

Numbered so it can be tracked. This is the remainder disclosed when S1-37 was fixed, not a new
discovery, and all three engines describe it identically.

`StoreUnderTest` is now a one-case list, so fifteen `SecretStoreTests` cases run against the
in-memory store only. The probe that used to narrow it silently is gone and the file says plainly
that the Keychain half is not covered anywhere.

**ChatGPT scores S1-37 "not fully fixed" on this**, which is a labelling difference rather than a
disagreement: it also confirms the twenty six moved tests now run unconditionally in a job that
executes, and that the CI rule cannot detect this shape. Fable's phrasing is the one worth keeping:
a probe that silently narrowed has become **a stated list that admits its limit**, which converts
hidden non-coverage into recorded non-coverage.

## S1-40 (low, contested): the disable path can still move accounts before the refusal

Disclosed in the brief. All three name it and they score it differently.

`precheckConversion()` succeeds, a second record arrives, the accounts convert to local, and the
wrapped store's own count then finds the pair and refuses. **The accounts have moved while the
preference still reads on**, which is the state S1-28 was filed about, reached through an arrival
rather than a pre-existing pair.

- **ChatGPT**: this reproduces the filed inconsistency, so S1-28 is not fixed.
- **Fable**: the class is closed and what remains is the API's concurrency floor. Its framing is
  the most useful thing in the round: the finding has gone from **"any pre-existing pair,
  permanently, with wrong advice"** to **"an arrival landing inside one conversion span, once,
  honestly labelled, with retries refusing safely"**.
- **Grok**: not the filed path, and it does not restore the retry loop.

**No cheaper construction exists**, and Fable says why: the Keychain offers no transaction spanning
two stores. Closing it would need the accounts conversion and the wrapped conversion to be one
atomic operation, which the platform does not provide.

## What was confirmed

**S1-37's mechanics, by all three.** Both files are genuine renames with the gate line removed and
nothing else touched; the probe file itself is deleted, so nothing is left to skip on; the hosted job
runs the target they now live in; and the count checks out at fifteen plus eleven. Fable verified
target membership is by the project's synchronised folder groups, the same mechanism that carried
every test file added in prior rounds into jobs that demonstrably ran.

**No cross-suite interference**, checked by all three: both moved suites isolate every case behind
UUID-suffixed service names and temp directories, which is the convention the existing hosted suites
already follow.

**The move strengthens rather than weakens what they assert**, which I had not considered. Fable's
point: protection-class assertions now run against a Keychain that actually implements protection
classes, where the never-reached macOS path could not have honoured them.

**The CI rule is the right rule and not too blunt**, unanimously. Fable's reason: it follows this
CI's own idiom, where every absence check is a deliberate barrier with a documented override, and
the override here shifts the burden to proving execution, **which is the burden this finding existed
to impose**.

**The method reads coherently after five consecutive changes**, which was the surface I was least
sure of. Fable calls it the cleanest the method has been: four orthogonal stages in stated order,
repair, refuse-if-ambiguous, move, report, with each stage's position carrying its own argument. It
also confirms the reordering cannot invalidate the guard, **because the repair touches no
primary-key attribute and therefore cannot change the count the guard reads**.

**The new tests do not re-admit the agree-with-the-code shape.** All three assert named errors, which
is the S1-36 lesson holding, and the disable test pins the accounts-untouched property that is the
heart of the finding.

## Where the gate stands

**No high, no medium. Five lows and one waiver.**

| Item | Scope | What it is |
| --- | --- | --- |
| S1-34 | 1 | the seam can express the same-slot case and no test does |
| S1-38 | 1 | a twin forming between the count and the update collides and is reported as `.duplicate` |
| S1-39 | 1 | the Keychain half of `SecretStoreTests` runs nowhere |
| S1-40 | 1 | contested: the disable path can move accounts before the refusal, on an arrival |
| S4-45 | 4 | five false claims left |
| S1-33 | 1 | **waived**, with its reasoning and what would reopen it |

**S1-38 is the only one of these with a clean cheap fix**, and it is a one-line mapping rather than
a race to close.

## What was done: S1-38, and S1-40 waived

### S1-38: the collision is named for what it is

A collision at that update **is** the twin case, by construction: the update moves one record into
the opposite slot, and the only way that slot is occupied is by a second record. So
`errSecDuplicateItem` there is evidence of a pair rather than a separate kind of failure, and it now
throws `.twinnedRecord`.

**The race is not closed and cannot be by this shape**, because a count and an update are two calls.
What is closed is answering it with the wrong name, which is what sent a person the retry advice
this method exists to stop.

**The test was red for the wrong reason twice before it was right.** `beforeWrite` fires inside the
repair loop, which only runs for a record whose pair disagrees, so a test planting a correctly
paired record never fired the seam at all: the conversion simply succeeded, and the assertion failed
identically before and after the fix. The seam now also fires between the count and the update,
which is the gap this finding is about, and the test discriminates: removing the mapping reddens it.

**That is the fourth test this week that did not discriminate on its first writing.** The pattern is
consistent enough to name: each time, the seam or the side effect was placed somewhere the code
under test does not reach on the path being exercised. Running the mutation is what caught all four.

### S1-40 is waived

**Decision: recorded, not fixed.** The disable path can still move accounts before the wrapped
record refuses, when a second record arrives after `precheckConversion` has already passed.

**Why it is not being fixed.** Closing it needs the accounts conversion and the wrapped conversion
to be one atomic operation, and **the Keychain offers no transaction spanning two stores.** No
cheaper construction exists, and both engines that examined it reached that independently.

**What it costs, stated rather than minimised.** The accounts are local, the preference still reads
on, and the switch overstates protection until the next attempt. The next attempt refuses before
moving anything, so it is one span rather than a loop, and the message is now honest.

**What changed about it, which is the reason to accept it.** The finding has gone from *any
pre-existing pair, permanently, with wrong advice* to *an arrival landing inside one conversion
span, once, honestly labelled, with retries refusing safely*. The class is closed; what remains is
the platform's floor.

**What would reopen it.** A Keychain transaction spanning two services, or a redesign that puts the
wrapped record and the accounts under one primary key. Neither is contemplated.
