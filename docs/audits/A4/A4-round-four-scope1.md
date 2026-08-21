# A4 round four, scope 1: the vault at rest, and a suite that was never running

**The code under review is `a90dd70`.** Round three read `29d62e7`, round two `46f65a3`, round one
`74fe841`. Every prior round's results are in `docs/audits/`, including the full text of all three
returns.

**Files:** the scope 1 list in `A4-prompts.md`, plus `Sources/OpenFactorCore/Vault/`
`WrappedRecordStore.swift` and `Sources/OpenFactorCore/Import/BoundedFile.swift`, which are new
since round three and are both in this scope's path. `Tests/OpenFactorCoreTests/`
`VaultDecisionTests.swift` and `InMemoryWrappedStore.swift` are the new tests and are worth
reading, for the reason in the first section below.

Read-only. Do not build and do not run the test suite; keep the checkout clean.

## How this round is scored

**A finding that lives only in a comment or a document is recorded but does not hold this scope
open.** That floor was added after scope 2 ran four rounds finding no code defect while its comment
corrections generated the next round's findings at close to one for one. Report false claims if you
find them, and expect them to be fixed. Do not treat hunting them as the job.

## The thing to read first: `VaultTests` was never running

While writing tests for round three's findings, every fix in this scope was reverted one at a time
to watch its own test go red. Several did not. **`VaultTests` had never executed a single assertion
on the machine that runs the suite**, because the test binary is unsigned and every Keychain call
returned `errSecMissingEntitlement`. The suite reported success throughout.

`WrappedRecordStore` exists because of that: a protocol so `Vault`'s decisions can be tested
without a Keychain, with `InMemoryWrappedStore` behind it and `VaultDecisionTests` in front.

**Two questions follow, and they are the most valuable thing this round can answer.** Does the fake
store actually behave like `WrappedKeyStore` in the ways the decisions depend on, or does it agree
with the code by construction? And is there anything else in this scope whose only coverage runs
through a Keychain call that silently fails in the same way?

## What changed

**S1-12, two wraps can coexist and unlock picks one unspecified.** Earlier rounds argued about
detecting the conflict by counting records. It is not settled by counting. `Vault.unlock` now
fetches every wrapped record and tries the passphrase against each: a wrap only opens under its own
passphrase, so the right record identifies itself. The losers are then discarded, so the conflict
cannot outlive the first successful unlock. The refusal is reported on the best evidence across all
records, so a device holding rubbish beside a real wrap is told about the passphrase rather than
about the rubbish.

**Attack the discard.** If the removal can take the wrong record, or can run when the unlock did
not actually succeed, that is the finding this round is for.

**S1-13, the launch reconcile abandoned a failure in silence.** It now retries on every foreground
rather than once per process. This was contested at round three: one engine rated it medium, one
accepted it, and one called it weaker than the key file's repair-on-read.

**S1-15, the vault key read is now one bounded read** through `BoundedFile`, the primitive that
replaced four different bound shapes across three scopes. Scope 4's round four attacked that
primitive from its own side and found no defect in it, but raised one thing that belongs to you:
`VaultKeyStore.load` maps `.unreadable` to `nil`, so **a key file that exists and cannot be read is
reported as no key at all.** Two engines called it benign because the gate distinguishes locked
from introducing by record presence rather than by that return. Decide whether they are right.

**S1-16, seven comments corrected.**

## What is open and unfixed

Listed so the round is not spent rediscovering them:

- **S1-14**, the wrapped store's sync flag is a launch-time snapshot.
- **S1-17**, an open list draws dashes when its records change underneath. Found on hardware.

## Hardware evidence that did not exist at round three

Three experiments were run on two physical phones and are written up in `docs/audits/`:
`../E/E8-recovery-on-a-replacement-phone.md`, `../E/E9-the-reconcile-repairs-a-real-device.md`, and
`../E/E10-a-device-holding-the-wrong-key.md`. They are the first measurements of all three legs of
recovery.

**One measured claim contradicts a document.** iCloud Keychain propagation to a replacement device
was effectively instant, not the roughly thirty minutes previously written down, because the item
is already in the account. If anything else in `docs/VAULT.md` or `SECURITY.md` still depends on
the old figure, say so.

**Read these adversarially rather than as reassurance.** A measurement on two devices in one
iCloud account establishes less than it appears to, and saying what it does not establish is in
scope.

## What to answer

1. **Does each change address the finding it claims to?** A fix that moves a check without changing
   what is checked, or that handles the reported case while leaving the class open, is a finding.

2. **Did any change introduce something new?** This gate has now had four fixes produce the next
   defect, the most recent one in scope 4 last round, where closing a main-actor hang made a
   `defer` reachable that then deleted more than it should have. Look for that shape here.

3. **Do the new tests test the code, or do they agree with it?** Three fixes in this gate were
   caught passing tests written by whoever wrote the fix. `VaultDecisionTests` and
   `InMemoryWrappedStore` were both written alongside the fix they cover.

4. **Is anything claimed in a comment or document that the code does not do?** Report it; see the
   scoring note above for how it is weighed.

5. **Is this converging, or moving around?**

You are not bound by any previous round's conclusion, including your own. This gate has had a
reviewer retract its own finding, and has rejected fixes that came with passing tests. **Saying
that an earlier conclusion was wrong is in scope.**
