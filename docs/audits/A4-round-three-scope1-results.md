# A4 round three, scope 1: what three engines found in the fixes

Round three of scope 1 read `29d62e7`. All three engines returned.

**The gate's last two high-severity findings are closed.** S1-1, the wrapped key never syncing,
and S1-6, creation overwriting a record that arrives during the key derivation, were both accepted
by all three. Nothing high is open or awaiting review anywhere in this gate now.

**And this is the first round in five where no engine rejected a fix outright.** Rounds two and
three of scopes 4 and 3 each produced one unanimous rejection. This round produced none.

| Engine | Verdict |
| --- | --- |
| Grok 4.6 | "I would ship this over `46f65a3`. I would not describe `addIfAbsent` as eliminating the twin" |
| Fable 5 | "Nothing medium or above." Two stale comments, one self-healing window, one ignored status |
| ChatGPT 5.6 Sol | Two medium, one low. "Converging, but scope 1 should not close yet" |

## Why the two highs are accepted

Both were fixed by **changing the shape of the mechanism rather than its parameters**, which is
Fable's phrasing and the clearest statement of why this batch is different from the two before it.

Creation went from check-then-write to a write that refuses to replace. The fix no longer depends
on how much time passes between two operations, which is exactly what both previous versions got
wrong. Grok checked the call order and found the arrived record untouched and `keys.install` never
reached; Fable walked the ugliest failure path, where the count throws after a successful add, and
found it recovers correctly because the record written is wrapped under the passphrase still on
screen, so the retry routes to unlock and that passphrase opens it.

The passphrase-screen guard went from enumerating states that clear the screen to requiring
positive evidence that it should be cleared. New states are now safe by default; both previous
versions were unsafe by default. All three confirmed the three new tests would have gone red on
round two's condition.

## The disagreement worth keeping

**How much of the twin problem is left, and how big the remaining window is.**

Grok: narrowed, and the remainder is real and untested. "What is moving rather than dying: the
opposite-flag twin." It would not describe `addIfAbsent` as eliminating it.

Fable: the window is honestly labelled and is not really a race in this code any more, because a
record arriving on a genuinely-absent-looking device is two vaults colliding across a half-hour
sync channel, which no local ordering can arbitrate. Files only the ignored delete status,
informational.

ChatGPT goes furthest and is the one to read: **the window is not the microseconds between the add
and the count.** A record can arrive from iCloud minutes later, after the count has already
returned one. Then two records exist, `load()` uses `kSecMatchLimitOne` over both flags, and it
selects an unspecified one, so a correct passphrase can be tested against the wrong wrap and
reported as wrong. Grok named the same case in one line. The comment in the source claiming a
microsecond window is therefore false.

All three note the same smaller thing: the undo ignores `SecItemDelete`'s status, so a failed
cleanup leaves both records while the caller is told nothing was written.

## What round three added

| # | Finding | Severity | Engines |
| --- | --- | --- | --- |
| S1-12 | two wraps can coexist after creation, and unlock picks one unspecified | medium | all three |
| S1-13 | the launch reconcile abandons a failure silently, leaving a device in the loss shape | medium | ChatGPT |
| S1-14 | the wrapped store's sync flag is a launch-time snapshot | low | Fable |
| S1-15 | the vault key read is bounded only when the file system answers | low | ChatGPT |
| S1-16 | seven comments claim what the code does not do | low | all three |

**S1-13 is contested and worth stating both ways.** ChatGPT rates it medium: an upgraded device
sitting in the original loss shape gets one silent attempt per launch, the error is discarded, and
the owner is never told recovery is still broken. It points at the access-group migration directly
below, which explicitly refuses to hide its failures, and asks why this one may. Grok agrees it is
weaker than the key file's repair-on-read, which surfaces `damaged`. Fable accepts it, on the
grounds that it retries next launch and the off-direction cannot drift because the preference is
only flipped after a successful conversion.

**S1-14 is Fable's, and the app already carries the argument against itself.** `OpenFactorApp.init`
reads the sync preference once and bakes it into the store the vault keeps for the whole session,
while `SyncAwareKeychainStore`'s own header explains that it re-reads the preference on every call
because "there is no cached setting to go stale". Enable sync, erase from Settings, create a new
vault in the same session, and the wrap is written device-only while every new account syncs. It
heals at the next cold start, so the exposure is one session, but a phone lost inside it loses the
vault.

**S1-15 is the fail-open shape again**, in the file the class sweep touched last. The size probe is
optional and separate from the read, so a missing size still slurps the file and a stat/read race
exists. Fable reads the same code as correctly shaped, because degrading to the existing
post-read check is not degrading to trust. ChatGPT wants one bounded read of 33 bytes.

**S1-16 collects seven claims**, four of which were written by these fixes: the microsecond window,
`addIfAbsent`'s promise that false means nothing was written, `create(with:)`'s comment still
describing the early check as the mechanism, and the reconcile's description. The other three are
survivors: `VaultGateView` still says it "shows one of three things" seven lines above a switch
with five cases, `refresh`'s method comment still says it does nothing while a passphrase is shown,
and `AccountLabel`'s header still argues that sixty four graphemes are inherently small, which is
the claim round two refuted with a one-character hundred-kilobyte label and which the byte ceiling
forty lines below exists to disprove.

## Convergence

All three said yes, and Fable gave evidence rather than an opinion, which is worth recording as the
clearest account of what changed in the method:

**Fixes by inversion rather than adjustment.** Creation no longer depends on elapsed time; the
refresh guard no longer depends on enumerating states. Fixes of that shape do not regress along the
axis they were wrong on. Rounds one and two were parameter tweaks and both regressed.

**The meta-defect was fixed, not only the defects.** Round two's sharpest finding was a green test
that could not see the race it was written for. This batch gave the fake `duringWrite` and
`writeFailure`, the two capabilities whose absence made that false green expressible, and then
wrote the failing-shape tests on top.

**Defect sizes are strictly decreasing.** Round one found account-destroying paths. Round two found
one high race and one passphrase-discarding guard. Round three found stale comments, a
self-healing one-session window, and an ignored status code.

ChatGPT's reservation is the one to carry forward: **the repeated weak point is the wrapped-key
state machine, which still assumes a one-time observation can settle asynchronously arriving
Keychain state.** Another count will not fix that; conflict detection after creation would.

---

# Found on hardware, not by a reviewer

**S1-17, low: an open list keeps drawing dashes when its records change underneath it.**

Found while manufacturing E9's loss shape, and recorded in
`E10-a-device-holding-the-wrong-key.md`. A second phone replaced the shared vault while the first
was foregrounded and looking at its accounts. The rows had been read while they were still
readable, so they kept drawing, and every attempt to generate a code failed against records that
were gone or sealed under a key this device no longer had. The list showed `------` for each one.

Force-quitting and relaunching produced the correct screen immediately: "Enter your vault
passphrase", because `suggestsAWrongKey` fires when the app comes forward or the gate re-reads.

**The defect is the window, not the rule.** For as long as the app stays foregrounded, it tells
somebody their codes are broken while already knowing how to say the true thing, which is that this
iPhone does not have the key to these accounts.

Reaching it needs another device to replace the vault while this one is open and watching, so it is
rare. It is filed because "your accounts appear broken" is the wrong sentence at that moment, and
because a code that fails to generate is a signal the list could act on rather than render.

---

# S1-12, the last medium in the gate

**Fixed at `dc486b7`.**

Three engines agreed the shape of it and one said the useful thing about the fix: another count
will not settle state that arrives later. So the fix does not count.

**Unlock tries every record, and the passphrase decides.** A wrap only opens under the passphrase
it was sealed with, so with two records the right one identifies itself. Nobody is asked anything,
no conflict screen exists, and the cost is one extra derivation on a path that already runs one,
only when a twin is present.

**The loser is then discarded**, so the conflict cannot outlive the first successful unlock. A
failure to remove it does not fail the unlock: the person is already in, and the next unlock
settles it the same way.

**The refusal is reported on the best evidence across every record tried.** A device holding
rubbish beside a real wrap hears about the passphrase rather than about the rubbish, which is the
same rule S1-9 established for a single record.

Four tests, and both halves were reverted individually to watch them go red: reading one record
again reddens the twin test, and removing the discard reddens the resolution test.

**The fake store now holds a list**, with a way to plant a twin carrying the opposite flag. That
case could not be expressed at all while it held one optional value, which is why the twin was
argued about for three rounds rather than tested.

## Still open in this scope

**S1-14**, the wrapped store's sync flag being a launch-time snapshot, and **S1-17**, an open list
drawing dashes when its records change underneath. Both low.

## What a device could still show

The twin case is now reproducible on hardware, and the Debug readout added for E9 reports the
record count. Creating a vault on two phones inside the same propagation window should produce
"2 records", and one unlock should take it back to one.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Grok:
1. Does each change address the finding it claims to?

Overwrite during create — yes. create(with:) still asks state() first, then spends the KDF, but the write is no longer save. It is addIfAbsent, which never updates an existing value. Same-flag arrival during the 600,000 iterations is errSecDuplicateItem and becomes .alreadyExists. The arrived OFK1 bytes stay put; keys.install is not reached (recordArrivingDuringCreationIsNotOverwritten).

That is a different shape from last round, where the check sat hundreds of milliseconds before a replacing write. The check is now on the write.

Opposite-flag twin — narrowed, as they said, and the undo is the part that is not on a test that runs against the Keychain. SecItemAdd cannot see a wrap whose kSecAttrSynchronizable differs. After a successful add they count under Any and, if there are two, delete the item they just wrote, pinned to this store’s own flag.

Call order if the in-flight wrap carries the other flag:

1. addIfAbsent SecItemAdds a new item (not a duplicate).
2. countingBothFlags() sees 2.
3. SecItemDelete of “mine.”
4. Returns false → .alreadyExists.

What prevents a silent overwrite here is that there is no SecItemUpdate on this path at all. What is not prevented: a twin that arrives after the count has already returned 1, and a failed undo. SecItemDelete’s status is discarded:

        guard try countingBothFlags() > 1 else { return true }

        var mine = query()
        mine[kSecAttrSynchronizable as String] = synchronizable
        SecItemDelete(mine as CFDictionary)
        return false

If that delete fails, the method still reports “nothing was written,” create throws .alreadyExists, and both records remain. load() uses kSecMatchLimitOne over Any, so which wrap unlock reads is unspecified. I do not have a realistic way to force that failure in the microseconds between add and count while the owner is on the setup screen; I am not calling it a high finding. I am saying the remainder they asked this round to attack is real, and it is also untested: WrappedKeySyncTests never calls addIfAbsent. InMemoryWrappedStore is one optional Data with no flags, so VaultDecisionTests cannot go red if the undo is removed.

refresh() while a passphrase is shown — yes, and it now has the tests last round said were missing. The guard is inverted: leave only on .locked or .open. .unavailable and .absent stay. unreadableStoreLeavesThePassphraseUp and arrivingRecordMovesToUnlock would have gone red on the round-two condition. isWorking still skips refresh during create; that no longer matters for overwrite, because addIfAbsent is what sees the arrival, and .alreadyExists moves the gate to locked afterwards.

Create writes under the current preference — yes for a new process. OpenFactorApp now builds WrappedKeyStore(synchronizable: UserDefaults…syncEnabled) and hands that instance to Vault. First addIfAbsent uses that flag. The erase-from-locked then recreate path last round named is closed on a launch that already has the preference set.

The store is still built once. A process that launches with sync off, enables it, then somehow creates again in the same process would still add a local wrap. In production, create after a toggle requires destroying the vault first, and destroy-from-locked is the lost-key path, which is a new launch more often than not. I am not treating that as the original total-loss shape still standing.

Launch reconcile — yes for the device already sitting in the loss shape. On cold start, if the preference is on, setSynchronizable(true) runs. That update is the same in-place conversion the toggle uses, so a local wrap becomes the synced one without a second item. A second launch with nothing left to move hits errSecItemNotFound and returns. Errors are swallowed (try?). A conversion that fails (device-locked Keychain at launch) stays in the loss shape until a later launch succeeds, with nothing on screen saying so. That is weaker than “repair on read” for the key file, which surfaces damaged; it is still a real attempt, and it is quiet as claimed.

Label byte ceiling — yes. "a" + 50,000 combining acutes is still one Character; clamped now cuts to 4,096 UTF-8 bytes. Both the single-monster-grapheme case and sixty-four expensive characters are asserted. Scalars are used only when one grapheme is larger than the whole budget; a UTF-8 scalar is at most 4 bytes, so that loop cannot overshoot maximumBytes. Ordinary labels are unchanged. A planted account can still be spotted by sitting in a far larger padding class than 1/2/3 buckets (two 4 KB fields), not by being a hundred kilobytes.

save no longer writes accessibility. Only kSecValueData changes. Protection class stays with setSynchronizable. I cannot execute against securityd here either; I can see the construction-time whenUnlockedThisDeviceOnly is no longer in that dictionary.

One-shot replacePassphrase() is no longer public. Internal, @testable for the two-step tests. The app cannot pick it.

derivationFailed is .storage, not .wrongPassphrase. The out-of-range iteration count has its own test.

Docs from last round. records() returning data, kSecAttrGeneric “never written, and never read,” four states on Vault and in VAULT.md — those were updated. VaultGateView was not (question 3).

VaultKeyStore.load size check. If fileSize is present and greater than 32, it throws damaged before contents(atPath:). If fileSize is missing, it still slurp-reads, then checks the count. In this app’s own container that is a consistency pass, not a hostile-file bound.

───

2. Did any change introduce something new?

Create and passphrase-change are different writes now. That is the point. save still replaces, which a passphrase change needs; addIfAbsent does not. I did not find a caller of create going through save, or a caller of replace going through addIfAbsent.

addIfAbsent can leave a wrap with no key if the post-add count throws. create then reports .storage, the setup screen says try again, and the wrap is already there. A second tap gets .alreadyExists and jumps to unlock. If the person used “show me a different one” after the first failure, they are holding a string that does not open the wrap they accidentally wrote. Same class of “string that opens nothing,” triggered by a Keychain error between add and count rather than by .unavailable on refresh. I have not shown that error is common. It is new, because last round a failed save wrote nothing.

Launch reconcile writes the Keychain from a .task on the WindowGroup, including under App Lock. It does not create items; it only flips a flag on one that exists. I do not see it racing create into an overwrite. I do see it able to run while the owner is on setup with no wrap yet, in which case setSynchronizable is a no-op.

The label clamp’s scalar fallback can store a 4 KB combining sequence that is ugly to render. They said they are not considering rendering. At rest it is bounded. I am not inflating that into an at-rest leak.

refresh() has been rewritten three times for the same screen. This version matches the rule the documentation now states, and the two directions have tests. I do not see a fourth state that still drops the passphrase.

───

3. Does any comment or document now claim something the code does not do?

VaultGateView still says it “shows one of three things.” The view switches on five stages, including .unavailable. docs/VAULT.md was corrected to four. Last round named this file; the page moved, the view header did not.

VaultGateModel.refresh’s method comment still says it “Deliberately does nothing while a passphrase is on screen.” The body leaves on .locked and .open. The paragraph below the if isWorking line tells the truth; the doc comment on the method does not.

Those are the ones I would not let stand. The historical “save replaces, so without this check…” block above create(with:) is now describing why addIfAbsent exists, and is easy to read as if the state() check were still the load-bearing one. It is not.

VAULT.md still does not name addIfAbsent. It says “a write that refuses to replace anything,” which is what the method does.

───

4. Is this converging?

Yes. Last round the defect was: a test was green, the wrap was still overwritten, two engines independently walked the same call order. This round that call order hits a write that cannot replace. The gate’s passphrase screen, which had been wrong twice in two rounds, now has the inverted guard and tests that fail on the old guard.

What is shrinking: destructive create, lost wrap on sync-on recreate, lost wrap on devices that enabled sync before the toggle path existed, passphrase discarded on .unavailable, save stuffing ThisDeviceOnly onto a synced item, public one-shot replace, wrong-passphrase for a KDF failure, the five false claims they listed.

What is moving rather than dying: the opposite-flag twin, which used to be “look then add” on save and is now “add then count then maybe delete” on addIfAbsent. The window went from the whole PBKDF2 to the time between SecItemAdd and the following copy. That is smaller. It is also the one place in this batch whose load-bearing remainder has no Keychain test, and whose undo does not check whether the delete happened. If this scope has another round, that is the line, not refresh().

I would ship this over 46f65a3. I would not describe addIfAbsent as eliminating the twin.

Fable:
Scope 1, round three — commit 29d62e7 (round two read 46f65a3, round one read 74fe841)

Recording the same asymmetry as last round: this is the same conversation for all three of my passes, and this round I am grading fixes made partly to my own findings, with the results document in view. Where that matters — R1's accessibility fix, R4's reconcile — I re-derived the verdict from the bytes at 29d62e7, not from whether the fix matches what I asked for.

Summary: every round-two finding is addressed, and the two hardest ones are fixed by changing the shape of the mechanism rather than its parameters, which is what was missing in the previous two rounds. What I found this time is strictly smaller than what round two found: two stale comments, one self-healing staleness window, and one ignored error status. Nothing medium or above. My answer to question four is that this is converging, with the evidence below.

Question 1: does each change address its finding?

The high — creation overwriting an arriving wrap. Addressed, and by the right mechanism. create(with:) now commits through addIfAbsent (Vault.swift:146), a write that refuses to replace: SecItemAdd is atomic against a same-flag duplicate, and the opposite-flag twin — which SecItemAdd cannot see because the sync flag is part of the primary key — is caught by the count-under-Any afterwards, with the undo pinned to the store's own flag so the arrived record is never the one deleted (WrappedKeyStore.swift:176). The check is now part of the write instead of 600,000 PBKDF2 iterations before it, which closes the class, not the case. I also walked the ugliest failure path and it recovers correctly: if the count throws after a successful add, create throws with a record already written — but that record is wrapped under the passphrase that was on screen, the retry hits .alreadyExists at the state check, the gate routes to the unlock screen, and the passphrase the person just wrote down opens it. That is a genuinely well-behaved failure mode and I could not construct a call order through this path that loses data. The remaining window — an arrival in the microseconds between the add and the count, or after the count entirely — is honestly labeled a narrowing, and it is also not really a race in this code any more: a record arriving after a successful creation on a genuinely-absent-looking device is two vaults colliding across a half-hour sync channel, which no local ordering can arbitrate and which the human gate and the .alreadyExists wording already own.

The medium — refresh() discarding the passphrase on .unavailable. Addressed, with the inversion all three engines asked for. The guard is now state != .locked, state != .open → return (VaultGateModel.swift:107): leave the screen only on affirmative evidence. The three new tests in the app target cover all three directions — unavailable stays and it is the same string, arrival moves to .locked, absent stays — so the coverage claim that was false in round two's account is true this time, and the tests were placed in the target where the code lives, which was the structural reason the previous claim was false.

My R1 — the accessibility clobber. Addressed structurally. save's update dictionary now contains only kSecValueData (WrappedKeyStore.swift:146). I asked for the found accessibility to be carried, or for the key to be dropped from the changes; dropping it is the better of the two, because the property is now structural — there is no accessibility write to get wrong — rather than a copied value to keep correct. The read-back test I asked for was not added, and with this shape it is no longer load-bearing. The device-run question that kept R1 at PLAUSIBLE is moot: whatever securityd does with the mismatch, nothing produces the mismatch now.

Grok's create-path sync flag. Addressed at the wiring (OpenFactorApp.swift: the app now builds WrappedKeyStore(synchronizable:) from the preference and hands it to Vault), with a residual I file below as F3.

My R4 — the reconcile. Addressed. One idempotent setSynchronizable(true) per cold start when the preference says sync, errors swallowed and therefore retried next launch. Reconciling only the on-direction is justified: I checked the off-direction and it cannot drift silently, because SettingsView.syncBinding flips the preference only after the conversion succeeds, so a failed withdrawal leaves the switch honestly reading "on".

The rest, briefly, all verified as done: the one-shot replacePassphrase() is internal with the warning intact; derivationFailed now reports as .storage rather than blaming the typist; the iteration-range route into recordNotUnderstood has its own test and its byte offset (36..<40) is correct against the record layout; creatingRefusesWhileUnreadable now expects the exact error; the fake gained writeFailure and the record-before-key ordering — which I called the most consequential unverified decision left — now has a test proving a failed record write installs no key and leaves the device recoverable; discard() sweeps PendingKeys, with a test; and VaultKeyStore.load gained the size-before-read check from the class sweep, correctly shaped (a failed size probe degrades to the existing post-read check rather than to trust).

Question 2: did any change introduce something new?

F3 — Low. The wrapped store's sync flag is a launch-time snapshot, and the app already owns a warning against exactly this. OpenFactorApp.init reads the preference once and bakes it into the WrappedKeyStore the vault keeps for the whole session. SyncAwareKeychainStore's own header explains why it re-reads the preference on every call: "there is no cached setting to go stale." So: launch with sync off, enable sync, erase everything from Settings, create a new vault in the same session — the wrap is written device-only while every new account syncs, which is Grok's total-loss shape reproduced one level up. It heals silently at the next cold start, when reconcileWrappedKeySync moves the record, so the exposure is bounded to one session — but a phone lost inside that window loses the vault, and nothing signals it. Smallest fix: read the preference at write time, the way the account store does — pass a closure into the store, or have the gate build the Vault it creates with at the moment of creation.

F4 — Informational. The addIfAbsent undo ignores its delete status. WrappedKeyStore.swift:194: if SecItemDelete fails, the twin pair persists, the caller still gets .alreadyExists, and load() thereafter picks between twins unspecified — the exact symptom the twin work exists to prevent, surviving on a path nothing observes. One guard turning a failed undo into a thrown error would surface it.

Beyond those, I looked for new defects in the reshaped code and did not find one: the scalar-fallback stage of AccountLabel.clamped keeps well-formed text, counts bytes correctly, and cannot run with a stale byte counter (the character loop that precedes it appended nothing when the fallback triggers); the new tests' premises are asserted, not assumed; the FailingStore/duringWrite fakes model the arrival at the right moment — before the commit check — which is what made round two's false green expressible at all.

Question 3: does anything claim what the code does not do?

Round two found five surviving false claims after a pass that said it removed them all, and told this round to assume there are more. There are two more.

F1 — VaultGateView.swift:4 still opens with "shows one of three things", seven lines above a switch with five cases. docs/VAULT.md was corrected to "one of four things" in this very batch; the view's own header — the nearest comment to the code — was the one instance missed. Trivial to fix, and worth fixing precisely because this scope's history shows stale comments here get believed.

F2 — AccountLabel.swift:32: the "Characters, not bytes" section still argues that grapheme counting "costs a little precision about the eventual byte size" and that "sixty-four of even the most expensive graphemes is still trivially small" — the exact claim round two refuted with a one-character, hundred-kilobyte label, and which the maximumBytes documentation forty lines below explicitly calls out as having been false. The file now contradicts itself: the header says character counting suffices; the byte ceiling exists because it does not. The header section needs its last sentence replaced with a pointer to maximumBytes.

Everything else I checked against the code now holds: the kSecReturnData sentence is corrected in both places it lived, the kSecAttrGeneric row says "never written, and never read", the vault's state table has four rows, VAULT.md's creation paragraph describes addIfAbsent accurately including its honest history, and the new refresh paragraph — "only a record does that" — matches the implemented guard. One deliberate nuance to leave alone: VAULT.md's "one, two, or three buckets" padding class describes ordinary accounts, and a hostile-but-accepted imported label can now reach ~4 KB per field, stretching a planted account into a distinctive size class of tens of buckets. That is inherent to truncate-rather-than-reject and bounded where it used to be unbounded; a half-sentence in the padding paragraph would make the page exact.

Question 4: is this converging?

Yes, and I will say specifically why I believe that rather than assert it.

Three signals distinguish this batch from the previous two. First, the two repeat-offender areas were fixed by inversion, not adjustment. Creation went from check-then-write to a write that refuses — the fix no longer depends on how much time passes between two operations, which is what both previous versions got wrong. The refresh guard went from enumerating states that clear the screen to requiring positive evidence — new states are now safe by default, where both previous versions were unsafe by default. Fixes of that shape do not regress along the axis they were wrong on; parameter-tweaks do, and rounds one and two were parameter-tweaks. Second, the meta-defect was fixed, not just the defects: round two's sharpest lesson was a green test that could not see the race it was written for, and this batch extended the fake with duringWrite and writeFailure — the two capabilities whose absence made that false green possible — then wrote the failing-shape tests on top. Third, the defect sizes are strictly decreasing across rounds: round one found account-destroying paths, round two found one high race and one passphrase-discarding guard, this round found stale comments, a self-healing one-session window, and an ignored status code. Nothing I found this round destroys data on any call order I could construct.

Two honest qualifiers. VaultGateModel.refresh has now changed in all three rounds, which is the churn pattern this question exists to name — but the third change is the inversion plus three direction-covering tests, so the risk of a fourth is bounded in a way it was not before; I would still not touch that function again without a reason stated in writing. And convergence here is convergence of what a reader can verify: the Keychain-real behavior of addIfAbsent's twin handling and the reconcile rests on the hosted simulator suite and on Apple's documented primary-key semantics, and the microsecond window is accepted rather than closed, on reasoning I checked and agree with. The defect surface is shrinking, the fixes are the right shape, and the remaining items — F1 through F4 — are a morning's work, none of it in cryptography and none of it in the storage decisions this scope exists to protect.

GPT:
Round-three verdict
Review target: 29d62e75163d464cc619bc3bdaf3b49c9a80ffff.
This is converging, but Scope 1 should not close yet. The previous destructive overwrite is materially reduced, the passphrase-screen rule is now correct, and the label byte bound works. I found two medium-severity recovery defects and one low-severity incomplete bound, plus several false behavioral comments.
1. Medium — addIfAbsent still cannot uphold its insert-only contract
Files/functions:
[WrappedKeyStore.swift (line 164)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:164), addIfAbsent
[WrappedKeyStore.swift (line 67)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:67), load
[WrappedRecordStore.swift (line 37)](Sources/OpenFactorCore/Vault/WrappedRecordStore.swift:37), contract
The atomic SecItemAdd closes the reported overwrite when a same-flag record is already locally visible. The opposite-flag handling remains incomplete in two concrete ways.
First, the remaining arrival window is not merely the microseconds between add and count:
The new record is added.
countingBothFlags() sees one item, so addIfAbsent returns true.
The generated key is installed.
Minutes later, the older synchronizable record arrives from iCloud under the opposite flag.
Two records now exist.
load() uses kSecMatchLimitOne, so it selects an unspecified record. A correct passphrase can be tested against the wrong wrap and reported as wrong.
Nothing after line 187 monitors for this later arrival. I cannot establish from this source how iCloud resolves the still more serious same-flag conflict, so I am not assigning severity based on possible remote replacement.
Second, even a twin detected during the count is not reliably undone. Line 194 ignores SecItemDelete’s result and returns false regardless. If deletion fails, the protocol’s promise—“nothing was written”—is false, the vault installs no matching key, and both records remain.
Smallest safe fix:
Check deletion status and verify the postcondition before returning false.
Make load/save enumerate both flags and report an explicit conflict whenever the count is not exactly one, instead of selecting an arbitrary item.
Stop claiming the count excludes later iCloud delivery. Resolving that requires conflict detection after creation or an explicit generation/conflict-resolution mechanism, not another one-time count.
2. Medium — Launch reconciliation silently leaves existing devices in the original loss state
File/function: [OpenFactorApp.swift (line 68)](OpenFactor/OpenFactorApp.swift:68), reconcileWrappedKeySync.
Concrete failure:
An upgraded device has sync enabled, synced account ciphertext, and a pre-fix local-only wrapped key.
At launch, setSynchronizable(true) fails—for example from a transient Keychain error or an existing conflicting item.
try? at line 84 discards the error. There is no alert, success marker, or retry while that process remains alive.
The app continues working from its container key, so the owner receives no indication that recovery remains broken.
If the device is then lost, iCloud has the accounts but not necessarily their wrapped key; the correct passphrase has nothing to unwrap.
The idempotent operation is appropriate, but silently attempting it once is not a completed migration. This is the same failure mode the access-group migration immediately below explicitly refuses to hide.
Smallest fix: surface reconciliation failure and retry it on later active transitions until success. At minimum, retain a failure state and warn that sync recovery is incomplete rather than treating the attempt as sufficient.
3. Low — The new file-size bound is optional and separated from the read
File/function: [VaultKeyStore.swift (line 78)](Sources/OpenFactorCore/Vault/VaultKeyStore.swift:78), load.
The new check does not close the “bound before allocation” class unconditionally:
resourceValues fails and try? turns the failure into nil, or the file changes after the stat.
Execution proceeds to FileManager.contents.
The entire file is allocated.
Only afterward does data.count != 32 reject it.
Exploitability is low under the stated threat model because the file is in the app’s private container. The sibling-app adversary cannot place data there. Nevertheless, the claimed class-wide bound is not actually enforced.
Smallest fix: open the file and perform one bounded read of at most 33 bytes, rejecting anything other than exactly 32. That removes both the swallowed-stat path and the stat/read race.
False behavioral claims
Low severity:
[WrappedKeyStore.swift (line 172)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:172) says the remaining twin window is between add and count and measured in microseconds. An iCloud item may arrive after the count, so the window is unbounded.
[WrappedRecordStore.swift (line 39)](Sources/OpenFactorCore/Vault/WrappedRecordStore.swift:39) promises that false means nothing was written. A failed cleanup violates that promise.
[Vault.swift (line 119)](Sources/OpenFactorCore/Vault/Vault.swift:119) still describes the early existence check and replacing save as the refusal mechanism, although the actual fix is the later addIfAbsent.
[OpenFactorApp.swift (line 68)](OpenFactor/OpenFactorApp.swift:68) says reconciliation brings the item into line with the preference. It does nothing when the preference is false and silently abandons failures when true.
[VaultGateModel.swift (line 85)](OpenFactor/Vault/VaultGateModel.swift:85) says refresh does nothing while a passphrase is displayed. It correctly moves to .locked or .open; only the detailed comment below describes the implemented rule.
[AccountLabel.swift (line 32)](Sources/OpenFactorCore/AccountLabel.swift:32) says labels are never cut through a grapheme and that 64 graphemes are inherently small. The new scalar fallback deliberately cuts an oversized grapheme precisely because neither statement is true.
Fix-by-fix assessment
Wrapped-key sync toggle and creation preference: fixed for new writes.
Existing-device wrapped-key reconciliation: incomplete because failures are silent.
Creation overwrite during PBKDF2: the direct replacing write is fixed; the asynchronous twin class remains.
save accessibility corruption: fixed; only the value is updated.
Passphrase-screen refresh: fixed. .absent and .unavailable preserve the same string; .locked and .open move away.
Label storage bound: fixed at 4,096 UTF-8 bytes; the scalar fallback remains valid UTF-8 and bounded.
One-shot replacement visibility, PBKDF2 error classification, iteration-path testing, and exact refusal assertion: fixed.
Record-before-key failure ordering and pending-key erase sweep: fixed.
Whole-file key read: only partially fixed as described above.
Original specification mismatches were corrected, but the new/stale behavioral comments listed above remain.
The core at-rest confidentiality construction otherwise resisted this pass: Keychain attributes expose constants and UUIDs rather than issuer/name/secret; record size leaks exact account count and 68 + metadata bucket + secret bucket, not field contents; AAD separates metadata (0x6d) from secrets (0x73) and binds both to the UUID; listing opens only metadata; and wrapped-key parsing validates the exact 100-byte record and iteration range before slicing or running PBKDF2.
Overall, the defect surface is shrinking rather than merely moving. The former high-severity overwrite has become a narrower but still real conflict-state problem, and most other changes now have mechanisms matching their claims. The repeated weak point remains the wrapped-key state machine: it still assumes a one-time observation can settle asynchronously arriving Keychain state. I would require that conflict handling and the silent migration failure to be fixed before closing this scope.
I did not run the test suite because it would create build artifacts, contrary to the read-only requirement. The repository remained unmodified.
