# The audit record

**Everything this project has had reviewed, and everything it has measured on real hardware.**
Published whether or not it is flattering, which is the only rule this folder has.

**Reviews are model-assisted adversarial reviews, not professional human audits**, and
`README.md` at the root says so in the warning that stays until it stops being true.

## The gates

| Gate | What it reviewed | When | Result |
| --- | --- | --- | --- |
| [A1](A1.md) | the core: TOTP, HOTP, base32, the store | 2026-08-14 | 2 defects, RFC vector tables re-verified, 17,000+ fuzz iterations. Working files: none |
| [A2](A2.md) | iCloud Keychain sync, the only feature that lets account material leave the device | 2026-08-14, and again after the watch app | 14 findings across two passes. Working files: [A2/](A2/) |
| [A3](A3.md) | the encrypted backup format, before implementation and then the implementation | before PR 16 | Public test vectors reproduced by independent implementations. Working files: [A3/](A3/) |
| [A4](A4.md) | the vault at rest, the watch key exchange, the parsers, the process boundaries | 2026-08-16 to 2026-08-21 | **133 findings, three high, all closed.** Two waived, two withdrawn. Working files: [A4/](A4/) |
| [V](V/) | the vault **design**, twice, before any of it was built | before PR 16d | A different instrument from auditing code that exists: it is why the design has the shape it has |

**The closing round is published whole**, both halves: the exit checks in
[A4/A4-closing-opinion-results.md](A4/A4-closing-opinion-results.md), and the reply round that
put their nineteen objections back as closed questions in
[A4/A4-reply-round-results.md](A4/A4-reply-round-results.md). **Each carries what happened when its
claims were checked**, in both directions: four objections did not survive measurement, one was
live and worse than described, and three factual errors in this project's own documents were found
because reviewers were handed citations and told to check them.

**[A4-board.md](A4-board.md) is the register**: all 133 findings in the words they were filed in,
the arc of the counts across twenty nine board redraws, and the standing panels about the gate's
own recurring mistakes. It is kept at this level because it is a reference rather than a working
file.

## The unscoped reviews

**A different instrument again from the gates.** The gates are commissioned and scoped: this
project decides what is reviewed and hands over a brief. These are the opposite. Run cold on the
whole repository, by a reader with no brief and no sight of the gates, told only where the
repository is. **What an outsider finds without being told where to look.**

**None of these is a gate**, and in particular none of them is A5, which is the diff since the last
audited tag and is scoped to it. An unscoped pass is broader and does not do A5's job: a whole
repository review can miss a regression precisely because it is not diffing.

| | What it found |
| --- | --- |
| [X1](X/X1-codex-blind-audit.md) | Blind, whole repository, 2026-08-22. **No critical or high.** Two documentation defects, both the same failure: a claim that was true when written and stopped being true. One resource bound the report itself filed as unverified and which turned out to be its most actionable finding. **Where this project disagreed is recorded inside the entry**, including one recommended fix that was rejected because it would have been worse than the flaw |
| [X2](X/X2-fable-blind-audit.md) | Blind, whole repository, 2026-08-29, by Claude Fable 5.1. **No critical or high**, the second cold pass to say so, and the second with no false positives: all eight findings confirmed at source. **Seven of the eight are one defect**, the code and the documents disagreeing in the direction that is worse for the user, including a comment promising a warning nobody built. Its best finding composes two separately accepted risks into an outcome neither document described: a substituted wrapped record makes the app's own recovery advice the deletion mechanism. **Where this project disagreed is recorded inside the entry**, as is the reason this reviewer is a weaker independence claim than X1 |
| [X3](X/X3-astra-blind-audit.md) | Blind, whole repository, 2026-09-05, by GPT 6-Astra, the first reviewer in the series from a lineage with no hand in this code, and the first to run probes rather than read. **Three Medium and two Low, all five confirmed at source**, the third consecutive cold pass with no false positives. Its principal finding needs no adversary: a plaintext file opened into the app is kept, backed up, after import and after erase. A second is a crash this project had made far more reachable five days earlier. **Where this project disagreed is recorded inside the entry**, including two places it rates a finding above the reviewer |

**Each entry records the prompt verbatim**, so it can be re-run against a later commit, and so
anybody can do the same thing to this project without asking.

## The hardware measurements

**[E/](E/) is evidence rather than paperwork**, which is why it is not filed under the gate that
happened to produce it. E1 predates A4 and is what the whole vault design answers. E12 and E13 came
out of A4. Two of them are still live: E5 carries a reopening condition that has already fired once,
and E12 carries a precondition nobody has measured.

**[E/README.md](E/README.md) says what re-running each one would take**, which is the honest answer
to a reviewer who pointed out that these read as comments rather than as behaviour. Most need a
second signed app, two devices, or two installs over each other, and a test bundle is one app on
one device in one install.

| | What it answered |
| --- | --- |
| [E1](E/E1-keychain-access-groups.md) | **No**, a Keychain access group is not a boundary between apps of the same team. The finding the vault design exists to answer |
| [E4](E/E4-container-isolation.md) | **No**, a sibling cannot reach another app's private container, even knowing the exact path |
| [E5](E/E5-watchconnectivity-routing.md) | A sibling phone app activates `WCSession` and finds it inert. **The rogue watch direction was never run** |
| [E6](E/E6-container-durability.md) | The protection class and backup exclusion are real and read back. **An app update preserves the data and moves the container** |
| [E7](E/E7-exchange-and-queryability.md) | The watch exchange fits in the message limits, the transcript binding works, and an opaque item costs no queryability |
| [E8](E/E8-recovery-on-a-replacement-phone.md) | Recovery on a clean second phone, on two devices and one Apple Account |
| [E9](E/E9-the-reconcile-repairs-a-real-device.md) | The launch reconcile repairs a device already in the loss shape |
| [E10](E/E10-a-device-holding-the-wrong-key.md) | A device holding the wrong key notices, asks, and recovers |
| [E11](E/E11-two-arrivals-of-different-kinds.md) | A link arriving over a shared image, four runs out of four |
| [E12](E/E12-a-compare-and-swap-token.md) | **Yes**, `kSecAttrGeneric` can carry a compare and swap token, which disproved a reviewer's claim that no shape of the code could close a window |
| [E13](E/E13-neither-phone-was-stranded.md) | Neither device held a record with a split pair |
| [E14](E/E14-the-system-lock-and-the-switcher.md) | **Yes**, iOS's per-app Face ID lock removes the app switcher exposure completely, from the first frame. The only probe here anybody can reproduce in two minutes |
| [E15](E/E15-the-enclave-and-a-sibling.md) | **Yes**, a same team sibling can find and use another app's Secure Enclave key and read the plaintext. User presence only adds a prompt. This is why the Enclave wrap was declined |
| [E16](E/E16-two-writers-and-what-a-list-shows.md) | **Two writing iPhones, at last.** Additions merge, the same record edited on both resolves last writer wins, and nothing anywhere says a conflict happened. Closes the gap A2 opened and A4, X1 and X2 all named. It also found what nobody was looking for: the account list is read when its view is created and at no other time, so App Lock is what makes a phone look like it syncs live. The watch already keys its load on the scene phase and the phone does not. Deletion reached a second phone in about a minute, against A2's fourteen |

**E2 and E3 do not exist, and nothing in this repository says why.** They were never committed and
never mentioned; the series jumps from E1, added alongside the vault design on 16 August, straight
to E4. **The numbering does not track the vault prove list either**, since E5 answers item 2, E7
answers items 4 and 5, and E6 answers item 7, so the gap cannot be explained that way.

**It is recorded as an unexplained gap rather than renumbered or given a plausible reason.** An
evidence series that renumbers itself after the fact stops being one, and inventing an explanation
for a gap is the exact habit gate A4 spent five days finding in this project's own documents.

## How to read a findings document

**A finding's identifier is stable and never reused.** `S1-33` is scope 1, finding 33, for the
life of the project.

**Returns are reproduced whole**, under a heading saying so, rather than summarised. For a stretch
of gate A4 that promise was not kept, and the repair is recorded in the files it applies to.

**A claim carries its basis.** Measured means observed on hardware once, by a person, and it can
rot silently. Tested means something in this repository fails if it stops being true. Reasoned
means it follows from the design and nothing checks it. Those three are not interchangeable, and
gate A4 spent most of its worst days learning that.
