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
