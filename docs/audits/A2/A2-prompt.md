# Gate A2 prompt

Paste the block below into a **fresh session**, with no memory of the work being audited.
Recommended: Fable 5, effort High.

Written at the end of PR 13. It deliberately does not tell you what the author believes is
correct, beyond what is checkable in the repository, because the point of this gate is a
second opinion rather than a confirmation.

---

You are auditing an open source iOS two factor authentication app, OpenFactor, at
`/Users/<you>/OpenFactor`, on branch `pr-13-sync` *(path redacted, visibly; nothing else changed)*. You did not write
any of it. Read it as someone who has never seen it before and whose job is to find what is
wrong.

The feature under audit is **iCloud Keychain sync**, added in the two commits `1b6dd21` and
`101223b`. It is the only feature that lets secret material leave the device, so the claims
made about it in the interface and in `SECURITY.md` have to be true rather than
reassuring. A TOTP secret cannot be revoked: anyone holding one generates valid codes
forever, without the phone and without the owner's knowledge. Weigh findings against that.

Start with `handoff.md`, which states where the project is and what its author believes is
unverified. Treat that document as a claim to be tested, not as briefing material.

## What this gate is for

1. **The three claims the author admits are reasoned rather than observed.** They are named
   in `handoff.md` and in `SECURITY.md`: what turning sync off does to copies on another
   device, how iCloud Keychain merges two devices' items, and whether a watchOS target in
   the same access group sees the phone's synced items. Establish what is actually true,
   against Apple's current documentation rather than against this repository's assertions.
   Where the documentation does not settle it, say so plainly and say what experiment
   would.
2. **`setSynchronizable(_:)` in `Sources/OpenFactorCore/KeychainSecretStore.swift`.** The
   only method that touches every account at once. Confirm no path through it reads secret
   data. Confirm that a failure part way through leaves a state that running it again
   repairs, and that repairing it cannot cross wire a secret onto another account's
   metadata. Consider what happens if it runs while the device locks.
3. **Verify the security claims made in the interface**, in `OpenFactor/Settings/SettingsView.swift`.
   Read the two sync footers and the About footer as a user would. Is anything in them more
   comforting than the code justifies? Is anything a user would need to know before
   flipping the switch missing from them? An accurate sentence that leaves the wrong
   impression counts as a finding.
4. **The preference and the Keychain can disagree.** The app stores the switch in
   `UserDefaults` and deliberately does not reconcile it with the Keychain at launch. The
   reasoning is in `SECURITY.md`. Decide whether that reasoning holds, and whether the
   divergence can mislead a user about where their secrets are.
5. **The threat model in `SECURITY.md` as a whole.** It was rewritten in this PR. Check
   that every claim in it is still true of the code, including ones not about sync.

## How to work

- Read `Sources/OpenFactorCore/` in full. It is the security core, roughly 1,900 lines
  including its documentation comments, no third party dependencies, and it is meant to be
  auditable in one sitting. The app target
  is thin by design, but `OpenFactor/Settings/` is in scope because that is where the sync
  decisions surface.
- `docs/ARCHITECTURE.md` explains the design decisions and why alternatives were rejected.
  Where you disagree with a rejection, say so.
- Tests are in `Tests/OpenFactorCoreTests/` and `OpenFactorTests/`. Run them with:

      xcodebuild test -project OpenFactor.xcodeproj -scheme OpenFactor \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO

  Keychain protection classes can only be asserted from the app hosted target, so a bare
  `swift test` proves nothing about them.
- A missing test is a finding when the untested behaviour is load bearing. Say which
  assertion is missing, not that coverage is low.
- Where you cannot establish something from the repository and the documentation, write
  down that it is unestablished and what would settle it. Do not resolve it by assuming.

## What to produce

Write `docs/audits/A2.md`, following the shape of `docs/audits/A1.md`. Findings numbered,
each with what is wrong, why it matters given that a leaked TOTP secret is permanent, and
what would fix it. Separate what you verified from what you could not. Say plainly if you
found nothing in a section rather than manufacturing a finding to fill it.

Do not change any code. This gate produces a report; the author decides what to act on.
