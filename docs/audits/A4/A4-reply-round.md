# A4: the reply round

**The nineteen objections from the closing opinions, put back as closed questions.**

**Why this round exists.** The closing opinions' open half produced criticism that had never been
checked, in either direction. This project's own rule is that a claim resting on reasoning is
marked as reasoning, and that rule had only ever been applied to claims of strength. Applying it to
claims of weakness is what this round is.

**The design choices worth naming.** Each objection is restated with the change in front of it and
answered yes or no, which is the format eleven verification briefs used without once producing a
backlog. **Four platform facts are given with citations and an instruction to check them**, because
several objections measured this app against an unbounded ideal rather than against what an iOS app
can do, and handing over a conclusion would have been coaching. **The live finding leads**, ahead of
the corrections, so that the three places this project pushes back land as findings rather than as
defensiveness.

**Sent to each engine separately**, against a named commit, in the session that produced its own
closing opinion, because the questions ask whether *your* objection is answered and a fresh
instance cannot own one.

## The brief

```
**This is not a new review, and please do not treat it as one.** You gave a closing opinion on
this project. Every objection in it was taken seriously, checked one at a time, and either
answered, contested or accepted as permanent. This round asks you to score that work.

**The format is closed questions, because that is the one that has worked here.** Eleven
verification rounds used it and none produced a backlog. For each numbered item: **answer yes or
no on the first line**, then at most two lines of reasoning. A plain "no" is more useful to this
project than a hedged yes.

---

## Before the questions: what checking your objections actually found

**One of them was live, and worse than you described. It is the most important thing in this
document, so it goes first.**

`WatchProvisioning.respond` is overloaded. One overload takes raw bytes and validates them; the
other takes a `ValidatedRequest` that has already been parsed and approved. **Each generates its
own ephemeral phone key.** The freshness test called the raw bytes overload.
`WatchKeyProvider.approve` calls the validated one, because the phone parses the request, asks its
owner, and seals after the tap.

So the test guarded a path the app never takes. **A static phone keypair on the shipping path
passed all 457 tests.** That was measured by applying the mutation, not inferred.

**Four objections did not survive checking**, and in three of those cases this project's own
wording invited the error. Those are marked below and you are asked to accept or reject the
correction. **Do not accept one because we made it.** Citations are given so you can check.

**Three cannot be closed by anything this project can build**, and they are listed unchanged at
the end rather than quietly dropped.

---

## The platform ceilings, as facts to check rather than a conclusion to accept

Several objections measured this app against an unbounded ideal. That is a fair instrument and it
is not the only one, so here are four platform facts with sources. **Check them.** They are not
offered as an excuse and no question below asks you to be lenient.

1. **App Store apps update automatically by default** on iPhone and iPad, controlled at Settings,
   then Apps, then App Store, then App Updates. `https://support.apple.com/en-us/102629`
2. **Complete Protection**: Apple states the class key "is protected with a key derived from the
   user passcode or password and the device UID", and the decrypted class key is discarded shortly
   after the device locks.
   `https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web`
3. **The Secure Enclave holds P-256 keys, not arbitrary symmetric keys.** Storing a 32 byte vault
   key "in the Enclave" is not an available operation; wrapping it under an Enclave key is.
4. **WatchConnectivity** is documented as two way communication between an app and its **paired
   counterpart**. Apple documents the functional relationship and says nothing about what enforces
   it or how to authenticate the other side.

---

## Part 1: the objections, and whether they are answered

For each: **is the objection answered? Yes or no.**

**1. The crypto coverage blind spot.** You said a static ephemeral key and a deleted HKDF domain
separation label each passed the entire suite. The label half was already caught by a test that
spells the derivation out a second way, verified by mutation. The static key half was live, for
the overload reason above. The freshness property now runs over both entry points by name, and the
watch exchange gained a fixed input, fixed output vector pinning the request bytes, the derived
wrapping key and the response bytes. Changing the HKDF salt from empty to the magic bytes is
invisible to all 28 other tests in that suite and reddens only the vector. The vault wrapping half
was already anchored to published vectors, also verified by mutation.
See `Tests/OpenFactorCoreTests/WatchProvisioningTests.swift`.

**2. Build provenance.** `docs/BUILD_PROVENANCE.md` predates your read. It measured two Release
builds of identical source minutes apart, found every shipping binary differed, and refuses the
phrase "reproducible build" rather than promising it. The gap it names against itself, a hash
recorded against the commit that produced it, was not being recorded by anything;
`scripts/ship-testflight.sh` now writes one on every successful upload. **A reader still cannot
verify their download**, and the document says so.

**3. The platform assumptions were read as prose, not behaviour.**
`docs/audits/E-probes-what-can-be-rerun.md` now states, for each of eleven hardware probes, exactly
what re-running it would take. Most need a second signed app, two devices, or two installs over
each other, which a test bundle cannot be. One conversion was found: gate E1's finding cannot be a
test, but E1's *defence* can, and nothing was testing it. `theStoredBytesAreOpaque` now reads the
stored blob the way a sibling would and asserts the issuer, account name and secret are absent,
with a positive control.

**4. The S1-33 waiver.** Its reopening trigger moved out of the audit folder and into
`docs/VAULT.md`, next to the passphrase replacement section, where whoever builds that screen will
be reading.

**5. The S1-40 waiver.** It now states what accepting it does not mean: a shipping decision rather
than a safe window, and not the same as the toggle being trustworthy under twins.

**6. The synced recovery record.** `SECURITY.md` now says in the project's own voice that sync off
is the smaller surface, that both waived findings live on that one path, and that the least
surface this app can offer is a single phone with sync off plus an encrypted export.

**7. E5 described itself as measuring something the design no longer depends on.** It did, and its
own reopening condition had fired unnoticed when the six digit string was removed. Corrected, with
the miss recorded rather than quietly patched.

**8. Nobody measured whether a rogue watch app can sit on that channel.** Still true, and now a
recorded decision rather than an open question. The probe is not being run; the reasoning is
labelled as reasoning; the remedy if the answer were bad is written down, being a third message so
both sides hold the transcript before the key travels. **Is refusing to measure this, on those
terms, acceptable? Yes or no.**

**9. App Lock is a curtain, off unless you turn it on.** `docs/APP_LOCK.md` now pairs default-off
with the app switcher cache in one sentence and says the out of the box posture is the one with
least in front of it.

**10. Nobody should make this their only TOTP holder.** `README.md` now says so in the project's
own voice, before any reviewer says it, and tells the reader to test that the export imports.

**11. S4-36, for whoever raised it.** The rejection stands, on the reasoning already published:
bounded retention means keeping a transfer QR, every secret in one image, alive longer than the
design permits. **Your dissent is now recorded next to the rejection**, which previously read as
closed. **Is recording the dissent, without changing the policy, an acceptable resolution? Yes or
no.**

---

## Part 2: three corrections, where this project says the objection was wrong

**Reject these if you think they are wrong.** Each verdict below is unchanged; only the
characterisation of the residual risk changed.

**12. Update enforcement.** "Nothing forces you to update this app" is true about forcing and
misleading about outcomes, because of fact 1 above. The MASVS verdict stays **fail**, since the
control asks for a mechanism the app itself has and this app has none and will get none. **Do you
accept that the objection overstated the exposure? Yes or no.**

**13. The vault key's protection.** "A file in the app's container rather than Secure Enclave
backed" is true about the key's form and misleading about its protection, because of facts 2 and
3. The verdict stays **partial**. The argument against this project is also written down: the
recovery requirement explains the passphrase wrapped copy, not automatically the local one.
**Do you accept the correction? Yes or no.**

**14. The compromised device.** "If your phone is owned, so are your codes" is true of a
compromise with the device unlocked and false of one holding it locked, because of fact 2. The
scope decision is unchanged. **Do you accept the correction? Yes or no.**

---

## Part 3: the MASVS self-assessment, sampled

`docs/MASVS.md` says nobody independent has checked its verdicts. This is that check, on a sample.
For each: **does the evidence named support the verdict? Yes or no.**

**15. MASVS-STORAGE-1**, pass.
**16. MASVS-NETWORK-1**, pass, vacuously and enforced.
**17. MASVS-PLATFORM-2**, not applicable.
**18. MASVS-AUTH-3**, pass.
**19. MASVS-CODE-3**, pass, and enforced.

**20. Is there any verdict in that table you would change?** Name it and say to what. "No" is a
complete answer.

---

## Part 4: two open questions, and only two

**21. Within the software authenticator class**, not hardware tokens, **what does OpenFactor do
worse than its peers?** Give a pointer to the file or behaviour. If the answer is nothing you can
identify from the source, say that.

**22. What would have to become true for your overall verdict to change?** State conditions
somebody could check, not impressions. If a condition is one this project cannot reach, say so.

---

## What this round is not asking

**Do not relitigate the two waivers.** All three reviewers accepted them and nothing about them
has changed except the wording in items 4 and 5.

**Do not soften anything because a correction was offered.** Three corrections are proposed in
Part 2 and each is a claim you can check against a cited source. If a citation does not say what
this document claims, that is the most valuable thing you can report.

**Three objections were accepted and cannot be closed**, and are not up for discussion because
there is nothing to discuss: no commissioned human penetration test, the four serious defects that
existed in critical paths before the review, and the fact that this evidence chain has already
produced a confidently false shared conclusion. A fourth, long term iCloud and Watch behaviour
across hardware and OS releases, is accepted and waits on an OS release.

**Where you cannot check something, write "cannot check" rather than estimating.** That answer is
worth more here than a guess, and this project has already paid once for a reviewer reasoning
where they could have run something.

```
