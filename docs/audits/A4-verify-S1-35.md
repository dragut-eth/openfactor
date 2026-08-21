# A4 verification: S1-35

**This is not a review round.** Two closed questions and nothing else. Do not report low-severity
findings. Do not review anything outside S1-35. **A thin answer is the correct answer**, and one
that says what was checked in order to conclude nothing is worth more than one that manufactures a
finding.

**Sent to two engines rather than three, deliberately.** The change is small and its blast radius is
one enumerable question, so the round is narrower than usual. That is a stated limit rather than a
claim of full coverage.

**The code under review is `bb10d82`.** S1-35 was filed in `A4-verify-S1-31-results.md`, which also
carries the three verdicts that produced it. The five previous verification rounds are in the same
directory.

Read-only. Do not build and do not run tests; keep the checkout clean.

**Already decided, so do not report either:** S1-33 is **waived**, with its reasoning recorded at
the end of `A4-verify-S1-31-results.md`. S1-28, the twin collision that makes `setSynchronizable`
throw and leaves the switch overstating protection on the disable direction, is **open and filed**.
Both are named below where they touch this change.

## The finding, as filed

`repairProtectionClasses()` counted a failed `SecItemUpdate` as nothing-to-repair and said nothing.
`setSynchronizable` then returned normally, because its own move query legitimately finds nothing to
move for a stranded record, and `SyncAwareKeychainStore` converted **every account** to iCloud on
the strength of that return before the interface committed the preference.

Accounts in iCloud, wrapped key device-only, switch reading on. That is S1-1, reached through the
repair that exists to prevent it.

The filed remedy: require `errSecSuccess` for every attempted repair and throw otherwise, so account
conversion and the preference commitment both stop when the wrapped record was not repaired.

## What was changed

The repair throws on any status that is not `errSecSuccess`.

The test seam was **generalised rather than duplicated**: `duringSave` became `beforeWrite` and is
now called at two gaps, the one in `save` and the one in the repair. One optional closure, two call
sites, still `nil` on every shipping path, still reachable only through the internal initialiser.
The alternative was a second hook to test three lines.

## The interaction the author already found, disclosed rather than left to be caught

**On the disable direction the throw arrives after the accounts have already moved.**
`SyncAwareKeychainStore` converts accounts first when turning sync off and the wrapped key second.
So a failed repair on that path throws with every account already local while the preference, which
flips only after success, still reads on.

That is **S1-28's shape**, already filed and open. The judgement made was that this adds one route
to an existing finding rather than creating or widening one, and that the alternative is the silence
that made S1-35 a medium.

**Say if that judgement is wrong**, and in particular whether a throw arriving after a partial
conversion is worse than the silence it replaced.

## The two questions

**1. Is S1-35 fixed? Yes or no.** If no, one sentence on what remains.

Judge the code. Does the throw actually reach the caller that mattered, so that neither the account
conversion nor the preference commitment happens? Is there any remaining path on which a repair
fails and something still proceeds as though it had not?

**2. Does the fix introduce a new high or medium?** Yes or no. If yes, name it and give the call
order.

**This is the question this round is really for**, because turning silence into a throw is a
blast-radius change. The surfaces:

- **Every caller of `setSynchronizable`**, on both stores and both directions, including the
  foreground reconcile, the Settings toggle, and anything in the vault or the app that reaches it
  indirectly. Does a throw now escape somewhere that previously could not fail, and is any of them
  worse for it?
- **The reconcile specifically.** It swallows with `try?` and runs every foreground. A record that
  can never be repaired now means a throw on every foreground, forever. Harmless, or a new shape?
- **The generalised seam.** One closure now fires on two write paths rather than one. Confirm it is
  still `nil` everywhere that ships, and that firing inside the repair loop is placed where the
  test needs it and nowhere a shipping build reaches.
- **Partial repair.** With two records needing repair, the first succeeding and the second throwing
  leaves one repaired and one not, and the caller sees only the throw. Is that the right shape?

Nothing else is in scope. Two answers and their reasoning is the whole deliverable.
