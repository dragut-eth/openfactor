# V2: the prompt for an external audit of the vault design

Give this, along with `docs/VAULT.md`, `docs/audits/E1-keychain-access-groups.md`,
`docs/audits/V1.md` and `docs/BACKUP_FORMAT.md`, to a reviewer that did not write the design.

The V1 round was two models under one roof. This round is for genuinely independent ones, and
its value is proportional to how little they defer to the document's confidence.

---

You are auditing a **design document, not code**. Nothing has been implemented. The purpose of
auditing now is that this decides how every secret is stored on every device of an open source
two factor authentication app, and it cannot be fixed by an update once people have data.

Read `docs/VAULT.md`. It is normative. Read `docs/audits/E1-keychain-access-groups.md` for the
measured finding it rests on, `docs/audits/V1.md` for the first audit round and what was
already fixed, and `docs/BACKUP_FORMAT.md` for the audited format it deliberately reuses.

**The design in one line:** iOS Keychain access groups are not a boundary between apps of the
same developer team, which was measured rather than assumed, so account secrets are encrypted
and the ciphertext is kept in the Keychain where iCloud syncs it, while the key is kept in each
app's sandboxed container where no entitlement can reach it. A paired watch is handed the key
once over WatchConnectivity; a generated passphrase recovers it on any other device.

## What would be most useful

**Attack the central move.** Is "ciphertext in the Keychain, key in the container" actually
sound on iOS, or is there a mechanism that undermines it? The design assumes the private
container is unreachable by other apps of the same team and durable across the app's life. Both
assumptions are listed as unproven. If either is false the design collapses, so say so plainly.

**Attack the recovery paths**, which is where the first round found the worst problems. Trace
every way a user ends up holding ciphertext they cannot open: reinstall, new phone, restore from
backup, Quick Start migration, replaced watch, sync toggled off then on, an interrupted first
run, two devices set up the same day. The document claims to have closed several of these. Check
it rather than believe it.

**Attack the watch exchange.** A phone hands a 256 bit key to a watch. What authenticates the
requester, what stops a replay, what happens when the phone has no key itself, and is Apple's
pairing actually the boundary the design leans on.

**Attack the cryptography**, including a specific piece of history: this project has already been
bitten by an AES-GCM key commitment collision, documented in `BACKUP_FORMAT.md`. The vault
deliberately avoids it by generating the passphrase rather than accepting one. Check that
reasoning holds and that no other multi-candidate derivation was left in.

**Say what is over-claimed.** The first round found the document asserting more than it
delivered about metadata privacy, and the fix was disclosure rather than cryptography. Look for
remaining sentences that would not survive an auditor running an experiment.

## Ground rules

- Report only what you can justify with a concrete scenario: who does what, in what order, and
  what they get or lose. Try to refute your own finding first.
- Rank findings blocking, major or minor. Blocking means it breaks the security claim or loses
  a user's accounts.
- Say explicitly what you examined and did **not** object to. A list of complaints with no
  statement of coverage cannot be acted on.
- Flag uncertainty as uncertainty. "I could not determine whether iOS does X" is a useful
  finding; a confident wrong answer costs more than silence.
- No third party dependencies: the project has a hard zero-dependency rule, and the argument for
  it is in the README.
- Ignore wording, structure and style. The document's job is to be correct.

## The bar

This project has a habit worth knowing about, because it is the thing an audit here is really
testing. A comment once claimed the opposite of what its code did and survived two reviews. A CI
check used a regular expression feature its tool silently ignored, and reported success against
the exact string it was written to catch. A conclusion that another team owned a bundle
identifier was disproved by trying it under a different prefix. In each case the artefact looked
finished.

So the most valuable thing you can produce is not a list of improvements. It is the one sentence
in this document that is confidently wrong.
