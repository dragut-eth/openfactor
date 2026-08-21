# A4: the closing opinion, as it came back

**Three engines, one brief, reproduced whole.** The brief is in `A4-closing-opinion.md`.

**These were held back and are published late, and that needs saying rather than hiding.** They
were collected on 21 August and not committed at once. The reason was not the criticism: it was
that several statements in them turned out to be wrong when checked, and publishing a document
this project knew to contain false claims, unannotated, would have been a different way of
misinforming a reader. **The answer was to adjudicate rather than to withhold**, which is what
every other round in this folder does, and to publish both this round and the reply round that
followed it together. That is what has happened.

**One redaction, disclosed.** Where a return names a competing product this project does not name
anywhere, the name is replaced with `[a competitor]`. Nothing else is altered, cut, or reordered.

---

# The returns, as they came back

## Fable

I've read my four scope passes, the triage, the nine verification rounds, and the three documents I was pointed at. Before the opinion, the three answers the brief asks for by name.

S1-37 — yes, that reviewer was me. The false premise is mine. In A4-verify-S1-36-S1-32-S4-43-results.md:15, I followed a disclosed coverage asymmetry and concluded that KeychainSecretStoreTests and VaultTests "execute in no job and on no machine" — because swift test skips them and the hosted job passes -only-testing:OpenFactorTests. Two of those facts I checked. The third, that the package test group was not compiled into the hosted target, I inferred and never ran. It was false: the target's fileSystemSynchronizedGroups had listed both groups since the project was created, and the suites ran twenty-six times all along. All three of us then verified S1-37 "fixed," the maintainer wrote it into a commit message and a CI rule, and the fix deleted a probe that was quietly carrying fifteen Keychain executions — so the repair removed real coverage and manufactured S1-39. I wrote the sharpest self-correction in the gate about inheriting an unchecked premise, and made the same class of error one section later. I am recording that plainly because it is the most important caveat I can give you about this whole record, including my part in it.

The two waivers — I accept both. S1-33 (iCloud replacing bytes at the same key during a concurrent passphrase change) needs a race window inside a feature that has no user interface at all, and the only real fix rests on two unmeasured platform assumptions; deferring it and pinning the current behaviour with a test is the right call, not entrenchment. S1-40 (the disable path moving accounts before the refusal) is a genuine platform floor: the Keychain offers no transaction spanning two stores, so there is no cheaper construction, and the finding has shrunk from "any pre-existing pair, permanently, with wrong advice" to "one honestly-labelled span on an unlucky arrival." Both waivers name what would reopen them, which is what a waiver is supposed to do.

MASVS — I believe it, with the limits it states about itself. Every verdict points at something I can execute or read, it publishes an outright fail (CODE-2) instead of laundering it into "not applicable," and it flags the app-switcher cache as an accepted, unfixed gap rather than hiding it. It is honest. It is also a self-assessment by the person who wrote the code, and it says so; nobody independent has checked the verdicts, and I have not either.

Opinion, for a security-conscious friend deciding whether to trust this with their 2FA codes.

I would use this for ordinary personal two-factor, and I would tell you why in the same breath as what I would not lean on it for. The architecture is the good kind of boring: no network at all (enforced in CI, not just claimed), no third-party dependencies, sync that carries only ciphertext, and RFC test vectors that actually run — which is more than most authenticators will let you verify at all. But understand what the review found before the review happened: four serious defects in security-critical paths, including one that would have silently lost every account when you replaced your phone, and a crash any other app on the device could trigger. Those are fixed now, but they tell you the author writes real bugs into the parts that matter, like everyone does, and the subtle write-ordering and cross-store race classes are exactly where two issues remain waived as platform floors. The thing that would actually keep me up is the test suite's demonstrated blind spot: a deliberately weakened crypto construction — a static ephemeral key on the phone side, and a deleted HKDF domain-separation label — passed the entire suite, because the Watch exchange is tested by round-tripping both sides against each other. So "all tests pass" is weaker evidence for the vault-wrapping and Watch-provisioning crypto than it looks, even though the TOTP/HOTP/base32 vector tables anchor the code-generation side well.

There are things I could not assess from what I was shown, and they matter. I read source at specific commits; I never saw the shipped binary, and there are no reproducible-build notes, so nobody — me included — can confirm the app in the App Store was built from this code. There has been no independent human penetration test; this is one developer's code plus three language models, and I have just shown you that the models (me) can agree confidently on something false. And by explicit design the app offers no resistance on a compromised or jailbroken device, so if your phone is owned, so are your codes. The residual leaks that remain are small — a fraction of a second of issuer-and-name in the app-switcher snapshot, accepted rather than fixed — and I would not lose sleep over them. None of my findings were rejected in triage, so I am not sitting on a dismissed finding I still believe; my discomfort points the other way, at a finding of mine that was accepted and wrong. Net: I would trust it with my codes, I would keep a tested encrypted export elsewhere rather than treat it as my only copy of my accounts, and I would not describe it as independently verified — because it isn't yet, and the one thing that would change that, a reproducible build plus an outside pentest, is precisely the gap the project's own documents admit they haven't closed.

## ChatGPT

My honest advice is not to trust OpenFactor yet as the sole home for the two-factor credentials protecting your most important accounts.
I would consider it only for lower-impact accounts, with independently tested recovery through backup codes or an encrypted export stored elsewhere.
The earlier high-severity defects reportedly were fixed, but they show that the code once failed at its core job in both directions: it could strand every synced secret after device loss and expose codes through an uncovered iPad window.
The remaining acknowledged risks are narrower but material: brief app-switcher exposure, a recoverable vault key outside the Secure Enclave, no enforced security updates, and no protection on a compromised device beyond iOS itself.
I accept the S1-33 waiver for the current product because the race requires an unshipped passphrase-change interface and an extraordinarily tight cross-device replacement window, but it must be reopened if that interface ships or token synchronization is validated.
I accept S1-40 more reluctantly because Keychain provides no transaction across the two stores and the surviving race is extremely narrow, although the resulting mismatch between actual account location and the displayed sync state remains real.
I was one of the reviewers who accepted the false S1-37 account during verification, though I marked its fix "not fully"; I did not supply the premise—Fable did—and the resulting work temporarily removed fifteen genuine Keychain test executions before they were restored.
One rejected finding I still stand by is S4-36: an unsolicited newer URL can destroy the only in-memory copy of an unconfirmed import, which is genuine data-loss behavior even though it cannot erase accounts already in the vault.
I believe MASVS.md is candid about its limitations and probably accurate on many source-level facts, but I do not accept its Pass labels as independent security assurance because the author assessed their own code and the same evidence chain has already supported a demonstrably false conclusion.
I could not assess whether the distributed App Store binary actually derives from the reviewed source because no reproducible-build provenance was shown, and users entrust their secrets to that binary rather than to the repository.
I also could not assess the app through a skilled human penetration test, across long-term iCloud and Watch behavior on varied hardware and OS releases, or on a physically compromised device, all of which matter when an authenticator becomes a recovery bottleneck.
I would not put my primary email, password manager, financial accounts, cloud administration, identity provider, or cryptocurrency recovery behind OpenFactor as my only TOTP holder.
If you use it today, treat it as one component in a redundant recovery plan, not as your root of trust.

## Grok

I was not the reviewer who invented the claim that twenty-six Keychain tests ran on no machine. Fable supplied that premise. I was one of the two who accepted it and marked the "fix" closed, and the work done in its name deleted coverage that had been running the whole time.

I accept the reasons S1-33 and S1-40 were waived, as shipping decisions, not as "those windows are safe." S1-33 needs a passphrase-change screen that does not exist, and the compare-and-swap that could close it has two unmeasured preconditions; the day that screen ships, the waiver is void. S1-40 is the Keychain's refusal to make two stores one transaction. What remains is one conversion span where the switch can lie, then a retry that refuses honestly. That is cheaper than inventing a protocol the platform does not have. It is not the same as the toggle being trustworthy under twins.

docs/MASVS.md is the author scoring the author's code. I believe the fail and the two partials, because they cost something to write. I do not treat a Pass in that table as independently true.

I would not yet put the only copy of my real two-factor secrets in this app. The only shape I would even consider is a single phone, sync off, and an encrypted export kept somewhere this app does not touch — and even then only for accounts I can recover another way. The on-device wrapping is the part I would actually defend: I could follow the bytes, and they do what they claim. iCloud sync of the recovery record is the part I would not. That path did not work when I first read it, and after the repairs those two races are still there on purpose. App Lock is a curtain, off unless you turn it on, and the app switcher can still flash an issuer and a name. The Watch holds a copy of the vault key after one tap on the phone, with nothing to compare between the two screens, and nobody measured whether a watch app that claims to be this one can sit on that channel. I did not run this on a device, I have not seen a store binary, there is no way yet to check that a build you download is this source, and a compromised iPhone is out of scope by decision — those are the questions that decide whether the leftover design is a lock or a story, and they live in Apple's Keychain, iCloud, and WatchConnectivity, which I read as comments, not as behaviour. I have no rejected finding I still want to argue: I was wrong that multiple scenes were undeclared, and I was wrong that a padding sentence about a test vector was already false. Nothing forces you to update this app if a bug is found after you install it, and the key that opens everything is a file in the app's container rather than a Secure Enclave key, because recovery from a passphrase requires that. That is a real trade. It is not a reason to treat the hardware as holding the secret.

---

# What was done with them

**The three closed questions behaved like the eleven verification briefs before them.** All three
placed the S1-37 premise correctly, all three accepted both waivers as shipping decisions, and all
three believed the published fail and partials while refusing to treat a pass as independent
assurance. Nothing needed adjudicating.

**The open question produced a reflex rather than a reading.** Asked separately what they would
recommend instead, all three named a hardware token, which cannot do the thing they were asked
about because it has no passphrase recovery path. **How much of the trust paragraphs would have
changed if the engine had read no source at all is the useful test**, and for those paragraphs the
answer is: not much.

**The open half raised nineteen distinct objections, and every one was checked.** Rather than
answering them in prose, each was put back to the same three engines as a closed question with the
change in front of it. That is `A4-reply-round.md`, and what came back is
`A4-reply-round-results.md`.

**Four of the nineteen did not survive measurement**, three of them because this project's own
wording invited the error. **One was live and worse than described.** Both outcomes are recorded in
the reply round rather than here, because they are answers rather than opinions.
