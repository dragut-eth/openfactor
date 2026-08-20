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
