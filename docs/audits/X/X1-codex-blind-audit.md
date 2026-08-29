# X1: a blind, unscoped audit of the whole repository

**This is not gate A5.** A5 is the diff since `audit-a4`, run before each release, and it still
wants doing. This was a cold pass over the entire repository at one commit, by a reader with no
brief from this project and no sight of `docs/audits/`. Recorded because it is what a stranger
does after the repository goes public, and because it found things.

**Audited commit:** `49c4a924886b23a9c11bff48b6544c1794b83ce9`, 2026-08-22.
**Reviewer:** an agent with read-only checkout access, told not to modify anything.

## The prompt, verbatim

Recorded so it can be re-run against a later commit and so anybody can do the same thing to this
project without asking.

> checkout https://github.com/dragut-eth/openfactor.git, in this directory: /Users/<you>/tmp/Codex
> readonly
>
> Perform an independent security audit of this repository. Start by reading the README and
> security/design documentation to understand the claimed security properties, then inspect the
> actual implementation, entitlements, and tests and try to falsify those claims. Do not assume
> the documentation is correct. Do not read docs/audits/ until you have completed and written down
> your own findings, to avoid being biased by previous reviews. Report each finding with severity,
> affected code, reasoning, and a concrete attack or failure scenario where possible. Also report
> important security claims you were able to verify and claims you could not verify. Do not modify
> any files.

**The checkout path above is redacted, visibly rather than silently**, and nothing else in
the prompt is changed. It named a home directory on the machine that ran it. That path is
local noise to anybody re-running this, and a repository does not need to publish one to be
checkable. A verbatim record is worth keeping verbatim, so the substitution is marked
instead of quietly applied.

**The blinding instruction is the part that mattered**, and it was honoured: the findings were
written before `docs/audits/` was opened.

## Result

**No critical or high findings.** One medium, one informational, and one filed as unverified that
turned out to be the most actionable item in the report.

Every finding below was checked independently against the source before being accepted, including
the two that were accepted.

## OF-01, medium: Settings erase keeps the vault; MASVS-PRIVACY-4 said otherwise

**Confirmed as a documentation defect. Rejected as a code defect, deliberately.**

There are two erase paths and they call the same view with different completions:

    Settings -> Erase        EraseAccountsView { onAccountsChanged(); refreshSyncState() }
    Start over (locked)      EraseAccountsView { model.destroyVault() }

Only the second destroys the vault. `docs/MASVS.md`'s MASVS-PRIVACY-4 row claimed "erase, which
removes accounts **and both wrapped records**", which describes the second and asserted it of both.

**What was changed:** the MASVS row now describes each path separately, and the erase screen itself
says the vault and passphrase are kept.

**What was not changed, and why.** The report recommended one erase coordinator that always calls
`Vault.destroy()`. That would push somebody who merely cleared their accounts through vault setup
again and issue them a **new passphrase**, silently invalidating the one they wrote down and put
somewhere safe. **That is a worse failure than the one being fixed, and it lands on the common case
rather than the adversarial one.** Erasing accounts and starting over are different operations. If
a genuine "destroy everything" action is wanted it is a separate, explicit, labelled thing.

**And the attack scenario is weaker than the report states.** It describes a same-team sibling
capturing ciphertext, waiting for an erase, and reinserting it. The sibling cannot read what it
replays: the vault key lives in the private container, not the Keychain, **which the same report
verifies two sections later**. So the sibling restores the victim's accounts into the victim's own
app. That is persistence and integrity, not confidentiality. The sharper version of the harm is the
case `EraseAccountsView`'s own comment names, somebody selling a phone.

Medium is generous for the security half and about right for the claim half.

## OF-02, informational: PROJECT.md described a configuration that had changed

**Confirmed, and the mechanism failure behind it is worth more than the finding.**

`docs/PROJECT.md` still carried the headings "The watch app is not embedded in the phone app yet"
and "Not configured yet: no signing team in the project file". The project file has **five
`Embed Watch Content` phases and twelve `DEVELOPMENT_TEAM` entries**.

**The document's opening paragraph claims it cannot quietly drift**, because CI asserts the load
bearing values and both must change in the same pull request. CI does assert `Embed Watch Content`,
and **passed the entire time**.

**The check only looks one way.** It catches the project changing without the document. It cannot
catch the document being wrong while the project is right, and prose is where that hides. Both
drifted sections were prose asserting configuration, in the one region of the document no check
reaches.

**What was changed:** both sections now describe what is there. `DEVELOPMENT_TEAM` gained a CI
check, which it never had. And the document now states the rule the failure implies: configuration
facts belong in the settings table where each row has a check behind it, and prose must not assert
current configuration.

The report's own framing of the consequence is right and worth preserving: an auditor who reads
"no App Groups" skips reviewing the App Group inbox boundary. **This is an audit-misdirection bug**,
which is worse than a stale sentence.

## OF-03: the report's most actionable finding, filed as unverified

The report listed under "claims not independently verified":

> Image-import resource safety: the 8 MiB bound limits encoded bytes, not decoded pixel dimensions.
> A compressed 8000x8000 test image was accepted and processed without a meaningful slowdown on
> this Mac, so this was not classified as a confirmed vulnerability.

**Checked and confirmed.** `ImportLimits.policyBytes` is `8 * 1024 * 1024` and bounds encoded
bytes. There is **no pixel dimension bound anywhere in the codebase**: no
`CGImageSourceCreateThumbnailAtIndex`, no maximum pixel size. A mostly flat 8000x8000 PNG can be a
few hundred kilobytes encoded and decodes to roughly 256 MB.

**Their Mac shrugged, which is why they could not classify it.** This project has a name for that
reasoning: *it compiles here is not it compiles*. A watch and an older phone are not that Mac.

**Fixed on 2026-08-29, in build 8.** `QRDecoder.payloads(in data:)` now reads `PixelWidth` and
`PixelHeight` from `CGImageSourceCopyPropertiesAtIndex`, which answers from the header without
allocating the bitmap it is deciding about, refuses anything past `ImportLimits.maximumImagePixels`,
and then asks ImageIO for a thumbnail bounded at `workingImageMaxDimension` rather than decoding
the source whole. The reporter's 8000x8000 image now decodes at 4096x4096.

**It downsamples rather than refusing, which is a deliberate departure from the recommendation.**
Refusing on dimensions alone has to reject a full frame from the phone in the user's hand, because
an iPhone shoots 48 megapixels, and "that image is too large" is a poor answer to somebody
photographing a QR code with the camera Apple sold them. The pixel ceiling stays as a backstop
against the absurd; the downsample is what actually bounds the memory, at roughly 67 MB whatever
arrives.

**The bound sits in the decoder, not at a call site.** The share extension carries image bytes
without decoding them, so every decode in the project arrives through that one function. Two tests
cover it, and both go through `payloads(in: Data)` rather than the `CIImage` overload, which is
test-only and carries no bound.

## What the audit verified, and what it could not

**Its separation of the two is the best thing about the report** and is reproduced here because it
is more useful than the findings. Verified at source and configuration level: no third party
dependencies; no network API usage; separate authentication and encryption of metadata and secrets
with record identity and domain binding; the vault key in the private container rather than the
shared group, at Complete Protection with backup exclusion; PBKDF2-SHA256 at 600,000 iterations;
the share extension holding only the App Group entitlement and no Keychain access group; the
complication holding neither account-reading code nor entitlement; 162 tests across 14 suites.

Could not verify, for reasons of hardware, signing, or infrastructure: rogue watch impersonation
over WatchConnectivity, which this project already records as load bearing and unmeasured;
same-team isolation on physical hardware; multi-device iCloud conflict, deletion propagation and
replay; Quick Start and restore exclusion of the vault key; App Store binary provenance; real
device App Lock, snapshot and Face ID behaviour; and binary level confirmation of the no-network
claim.

**That last one is worth a note**: it is confirmable, and `VERIFYING.md` at the repository root
gives the exact commands. CI runs them on every push. The reviewer would have needed a build.

## What this cost and what it caught

Two documentation defects and one real resource bound, from a reader who was told nothing except
where the repository was. **Both documentation defects are the same failure this project spent the
preceding two days finding from the inside**: a claim that was true when written and stopped being
true, with nothing mechanical watching it.

That is six instances in two days from three independent directions. **It is a property of the
project rather than of any one person writing it**, and the response to OF-02 is the first
mechanical answer to it: a check that fails when the published surfaces stop agreeing.
