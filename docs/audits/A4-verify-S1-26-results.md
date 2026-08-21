# A4 verification: S1-26, answered

Reviewed commit: `a72bc3d`. The finding was filed against `b3e7e08` and is written up in
`A4-round-five-scope1-results.md`.

## The answers

| Engine | S1-26 fixed? | New high or medium? |
| --- | --- | --- |
| ChatGPT | **No** | No |
| Fable | Yes | No |
| Grok | Yes | No |

**Nobody found a new high or medium**, and all three describe the same remaining window. The split
is again about whether that window is the finding or its floor, which is the second verification
round running to end that way.

## What all three confirmed

**The second selection is gone.** `save` performs one `candidates()` read that supplies both the
count and the target, and the update is pinned to the observed candidate's flag. There is no path
left on which the *slot* written is a slot nobody examined.

**An arrival under the opposite flag is not this write's target**, and the result is a twin pair,
which the system now tolerates non-destructively everywhere.

**Throwing when the observed record has gone is right**, and Fable gives the reason the fix did not:
falling through to the add branch would re-create a wrapped record on a device where a deliberate,
authenticated erase had just propagated, **resurrecting a credential somebody chose to destroy**.
It also notes the existing test pins this, since an exact-array assertion would redden if `save`
ever added instead of throwing.

**The add branch does not need the same treatment.** Both engines that addressed it reached the
same place: a same-flag arrival makes `SecItemAdd` return duplicate and nothing is touched, and an
opposite-flag arrival forms a twin, which is tolerated. **Nothing is overwritten or destroyed on
either path**, which is the property that made the update branch a medium and does not transfer.

**S1-31 does not change what `save` should do.** Fable's reason is the better one: repairing a
stranded pairing there would hand `setSynchronizable`'s job to a second owner, which is the
split-responsibility shape that produced S1-25 in the first place.

## S1-33: the same-slot substitution, and whether it is really a floor

iCloud can replace the *bytes* of the observed item, at the same primary key, in the gap between
the read and the update. The update then overwrites content it never examined, at a slot it did
examine.

- **ChatGPT** scores this as S1-26 not fixed: opposite-flag arrivals are handled and same-slot
  replacement remains the original record-not-observed failure.
- **Grok** calls it update-by-identity without compare-and-swap, smaller than S1-26 and a different
  thing from writing a record this call never counted.
- **Fable** calls it the irreducible remainder and states plainly that **no shape of this code can
  close it, because `SecItemUpdate` offers no compare-and-swap**: a Keychain write cannot be
  conditioned on the value that was read.

**I am not sure that last claim is true, and it is worth testing rather than accepting.**

The primary key of a generic password is the service, the account, the access group and the sync
flag. `kSecAttrGeneric` is a settable attribute that is **not** part of that key. If it can be
matched in an update query, then writing a fresh token into it on every write and requiring the
observed token in the query is a compare-and-swap: another device's write replaces the token, our
update matches nothing, and the call fails instead of overwriting. That is exactly the semantics
the residual is said to lack.

**Two honest caveats.** I have not verified that `kSecAttrGeneric` is matchable in a
`SecItemUpdate` query on iOS, and this is precisely the kind of confident-sounding platform claim
this gate has caught being wrong. And it is new machinery in a store that has produced a high and
two mediums, requiring every writer to maintain the token.

So this is recorded as **a possibility to test, not a fix to make**. If it works, Fable's floor is
not a floor. If it does not, the floor is real and named.

**Reachability, stated rather than assumed**: it needs a cross-device erase and re-create landing
inside a microsecond window during a concurrent passphrase change on this device, and
`replacePassphrase(with:)` still has no interface.

## S1-34 (low): the seam can express the case the test does not

ChatGPT's concrete point, verified here. The hosted test's `duringSave` deletes the observed
**local** record and plants a **synced** one, so the arrival it expresses is under the opposite
flag. **The same-slot substitution is the case that matters now, the seam is capable of expressing
it, and no test does.**

That is worth closing whichever way S1-33 goes: if the residual stays, a test should pin what the
code actually does in that case rather than leaving it described only in prose.

## The seam: all three back it, including the engine that scored the fix not fixed

The brief asked whether the trade was wrong and what they would have done instead.

- **ChatGPT**: a deterministic adapter-level seam is reasonable here, because the in-memory fake
  cannot model Keychain reconciliation. It confirms there is no shipping caller and the public
  initialiser always sets it to `nil`.
- **Grok**: it would have written a Keychain port so the double lived only in tests, and judges that
  more machinery for one gap. An internal `let`, `nil` on the public initialiser, not visible to the
  app target, is the smaller seam.
- **Fable**: it would not have done it differently. The property lives between the adapter's own
  Keychain calls, where no wrapper, protocol fake or injected store can interleave, so the only
  alternatives are a function table over the four `SecItem` calls, which is strictly more production
  surface, or leaving the property untestable, **which is the condition this gate has twice paid
  for**. It verified by grep that exactly one reference exists outside the store.

**The fake's atomicity divergence is not a gap in the evidence**, and Fable's reason is the one to
keep: the property under test is the real adapter's non-atomicity against the real Keychain, and a
fake taught to be artificially non-atomic would verify the fake.

**One cheap suggestion worth taking**: the "nil on every path that ships" property is grep-checkable,
and this project's CI already runs absence checks of exactly that shape.

## On the format, after four uses

Four rounds, ten answers, two "no" verdicts, and **both of them landed on the same structure**: the
mechanism is fixed and a remainder survives that the other two engines name and accept. That is a
useful disagreement rather than noise, because in both cases the remainder was real and got its own
number.

The format is also now producing corrections to itself. This round's most useful sentence may be
one I am recording against a reviewer rather than for it: an assertion that something is impossible
is a claim about a platform API, and those are checkable.

---

# The returns, as they came back

**Reproduced verbatim.** `docs/ROADMAP.md` promises each pass is published whole, and for a stretch
of this gate that promise was not kept: the analysis above was published and the returns behind it
were not. This is the repair, restored from the session transcript rather than rewritten.

**One edit, the same one made to every pass in this directory**: absolute paths from the reviewing
machine are rewritten as repository-relative. Nothing is trimmed, softened or reordered, including
the parts that turned out to be wrong.

Grok:
Commit: a72bc3d. Finding filed against b3e7e08.

Answers

┌─────────────────────┬─────┐
│                     │     │
├─────────────────────┼─────┤
│ S1-26 fixed?        │ Yes │
├─────────────────────┼─────┤
│ New high or medium? │ No  │
└─────────────────────┴─────┘

Why it is fixed

save reads once. candidates() is both the count and the target. The update is keyed to target.isSynchronizable from that snapshot, not to a second MatchLimitOne under Any.

What remains between that read and SecItemUpdate:

• A wrap arriving under the other flag is a different primary key and is not written.
• If the observed slot is empty, SecItemUpdate fails. The call throws. It does not pick a neighbour.
• The contents of the named slot can still change (last writer in that slot). That is update-by-identity without compare-and-swap, not “write a record this call never counted.”

That is smaller than S1-26, and it is the remaining window of a keyed update, not a second selection.

S1-31 does not change what save should do: the update still writes only kSecValueData.

Add when candidates() is empty: a wrap can arrive before SecItemAdd. Same-flag add collides and throws. Opposite-flag add creates a twin. That is addIfAbsent’s remaining window (form a pair), not this finding (overwrite a wrap nobody observed). It does not need the same treatment.

Throw when the observed record is gone: right. The previous behaviour would have written the stranger. replacePassphrase(with:) maps SecretStoreError to .storage. Nothing in the app calls it yet.

The seam

The trade is not wrong. A non-racy test is green on both versions; that is how this gate has already shipped a defect with a passing test. InMemoryWrappedStore.save still locks across count and replace, so it cannot carry this property. The hosted test with duringSave is the evidence that can.

What I would have done instead: a Keychain port so the double lives only in tests. That is more machinery for one gap. An internal let, nil on the public initialiser, @Sendable, not visible to the app target, is the smaller seam. duringSave?() on the shipping path is a no-op.

Failing closed when the slot has emptied is the honest outcome, not a new medium.

GPT:
Verification verdict
Question	Verdict
Is S1-26 fixed?	No
New high or medium introduced?	No


S1-26 — Not fixed
The fix pins the update to the observed sync flag, but the flag identifies a slot, not the bytes observed.
Remaining call order:
[candidates() (line 179)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:179) observes synced record W_A, flag true.
Before the update, iCloud reconciliation replaces that same true slot with another live vault’s W_B.
The query at [line 196 (line 196)](Sources/OpenFactorCore/Vault/WrappedKeyStore.swift:196) still matches because it contains only the service, account and captured flag.
SecItemUpdate overwrites unobserved W_B with the caller’s replacement wrap, propagating the loss of vault B’s recovery credential.
Thus opposite-flag arrivals are fixed, but same-slot replacement remains the original record-not-observed failure. The new seam can express this case, but its test replaces the record under the opposite flag only.
The add branch is fail-safe for this finding: a same-flag arrival makes SecItemAdd return duplicate, while an opposite-flag arrival can create a twin but cannot be overwritten. Throwing when the observed slot genuinely disappeared is also correct.
S1-31 does not change what save should do; updating only the value appropriately avoids further altering its malformed protection class, though the separate migration remains necessary.
New high or medium — No
The unresolved same-slot window is the remaining S1-26 medium, not a regression introduced by the fix. The internal duringSave seam has no shipping caller, the public initializer always sets it to nil, and a deterministic adapter-level seam is reasonable here because the in-memory fake cannot model Keychain reconciliation.
No files were changed, and no build or tests were run.

Fable:
Verification: S1-26 — commit a72bc3d (filed against b3e7e08)
Question 1: is S1-26 fixed?

Yes. The defect was two reads — a count, then a separate kSecMatchLimitOne selection — with the write aimed at whatever the second read returned. At a72bc3d, save performs one candidates() read that supplies both the count and the target: the refusal is decided from that read, and the update is pinned to the observed candidate's flag (WrappedKeyStore.swift:167 onward). There is no second selection left in the function, so there is no path on which the slot written is a slot nobody examined — which is what was filed, and it matches the filed remedy exactly.

What remains in the window between candidates() and SecItemUpdate, named precisely:

An arrival under the opposite flag is not this write's target; the update still lands on the observed slot. The result is a twin pair, which the system now tolerates non-destructively everywhere. Acceptable.
The observed record deleted makes the update match nothing; save throws .notFound. Honest, and covered below.
The irreducible remainder: same-slot content substitution. iCloud can replace the bytes of the observed item (same primary key) in the gap — for instance another device erasing and re-creating a synced vault, whose new record occupies the same synced slot — and the update then overwrites content it never examined, at the same primary key it did examine. This is a value-level TOCTOU that no shape of this code can close, because SecItemUpdate offers no compare-and-swap: you cannot condition a Keychain write on the value you read. The filed remedy implicitly accepts this floor (it pins the slot, which is all the API can pin). It needs a cross-device destroy-and-recreate landing in a microsecond window during a concurrent passphrase change on this device. My verdict is acceptable-and-named, not merely smaller: the class the finding described — a second selection choosing an uncounted record — is eliminated; what remains is the API's own atomicity limit, reachable only through an interleaving that starts with a deliberate erase elsewhere.

On the standing S1-31 question, one sentence as budgeted: save should not change — its update writes the value only, which neither repairs nor worsens a stranded flag/class pairing, and repairing it there would hand setSynchronizable's job to a second owner, which is the split-responsibility shape that produced S1-25.

Question 2: does the fix introduce a new high or medium?

No. The author's four surfaces, checked:

Throwing when the observed record has gone is right. The alternative — falling through to the add branch — would re-create a wrapped record on a device where a deliberate, authenticated erase had just propagated, resurrecting a credential someone chose to destroy; failing is strictly safer, and the failure is truthful ("what this call meant to replace is not there"). Callers: the only production caller is Vault.replacePassphrase(with:), which maps it to .storage(.notFound) and propagates; no UI calls that path yet, and no caller swallows it into a wrong state. I also note the test pins this: its exact-array assertion (== [stranger]) would go red if save ever fell through to add instead of throwing, since the add would leave two survivors.
The add branch is a different question, and low-stakes. It is reached only when an open vault's record has vanished (a legitimate re-wrap after a propagated deletion), and an arrival in its microsecond gap yields either errSecDuplicateItem (same flag — honest failure, nothing touched) or an undone-by-nobody twin (opposite flag — the tolerated, non-destructive state that unlock resolves and save thereafter refuses). Nothing is overwritten or destroyed on either path, which is the property that made the update branch a medium and does not transfer here. addIfAbsent-style rollback parity is a tidiness judgment, not a needed treatment.
The seam: the trade is right, and I would not have done it differently. The property under test lives between the adapter's own Keychain calls, where no wrapper, protocol fake, or injected store can interleave — the only alternatives are a function-table over the four SecItem calls (strictly more production surface than one optional closure) or leaving the property untestable, which is the condition this gate has twice paid for. The costs are bounded and verified: one nil-check on the write path, an internal let holding a @Sendable closure (thread-safe on the Sendable struct), an internal initialiser the app target cannot reach across the module boundary, and — checked by grep across every target — exactly one reference outside the store, in the test. One suggestion, not a finding: the "nil on every path that ships" property is grep-checkable, and this project's CI already runs absence checks of exactly that shape.
The fake's atomicity divergence does not undermine the evidence. The property is the real adapter's non-atomicity against the real Keychain; a fake taught to be artificially non-atomic would verify the fake, and no Vault-level decision branches on the gap — Vault just propagates save's errors. The hosted test is the right instrument and it is a genuine one: its premise is planted and mutated through raw SecItem calls independent of the store under test, the documented mutation (restoring the second query) makes the stranger's bytes the write target and reddens the exact-survivor assertion, and the throw-versus-add distinction is pinned by the same assertion. The standing caveat is the known one — hosted tests run only where a Keychain exists — and it is already tracked by this gate rather than introduced here.

Verdicts: S1-26 fixed; no new high or medium introduced. The one thing worth carrying forward is a name, not a fix: the same-slot value-substitution floor is now the only TOCTOU left in this store, it is imposed by the Keychain API's lack of compare-and-swap, and future rounds should not re-derive it as a finding.
