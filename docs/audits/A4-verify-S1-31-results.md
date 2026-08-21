# A4 verification: S1-31, answered

Reviewed commit: `e4bd414`. S1-31 was filed in `A4-verify-S1-25-results.md`.

## The answers

| Engine | S1-31 fixed? | New high or medium? |
| --- | --- | --- |
| ChatGPT | **No** | No |
| Fable | Yes | No |
| Grok | Yes | No |

**Nobody found a new high or medium.** All three verified the repair's direction and placement.
ChatGPT found a path the other two reasoned past, and it is real.

## S1-35 (medium): the repair swallows its own failure, and the toggle carries on

Found by ChatGPT. Verified here, and the consequence is the one this scope opened with.

```
if SecItemUpdate(slot as CFDictionary, changes as CFDictionary) == errSecSuccess {
    repaired += 1
}
```

A failed update is counted as not-repaired and nothing is said. Then `setSynchronizable` reaches
`if status == errSecItemNotFound { return false }` and returns **normally**, because the move query
legitimately found nothing to move. Then, in `SyncAwareKeychainStore`:

```
if shouldSync {
    try wrapped.setSynchronizable(true)
    return try store.setSynchronizable(true)
}
```

The wrapped call did not throw, so **every account is converted to iCloud** and the interface
commits the preference.

**Accounts in iCloud, wrapped key device-only, switch reading on.** That is S1-1, the finding this
whole scope opened with, reached through the repair that exists to prevent it.

**The distinction the other two engines missed is between the two callers.** Fable reasoned that a
failed update is skipped and retried at the next foreground, which is true of the reconcile and
false of the explicit toggle: the reconcile retries harmlessly, and the toggle commits a preference
and converts the accounts on the strength of a repair that did not happen. Grok reached the same
benign reading. Neither is wrong about the reconcile.

**This project already has the rule, written down one hundred lines above the code that breaks it.**
`KeychainSecretStore.setSynchronizable` carries the sentence from gate A2, F14: *the failure that
understates exposure must not be the quiet one*. And it has the precedent twice over:
`SharedInbox.write` refuses when it cannot exclude the directory from backup, and `VaultKeyStore`
refuses to write a key it cannot exclude. **I wrote the opposite in the one place where the quiet
failure converts every account.**

ChatGPT's remedy, which is the right one: require `errSecSuccess` for every attempted repair and
throw otherwise, so account conversion and the preference commitment both stop when the wrapped
record was not repaired.

**The successful-path tests cannot see this**, which is why it survived three hosted tests.

## What all three confirmed

**The direction and the placement.** The repair updates the class alone, pinned to each record's own
flag, changes no primary-key attribute, never deletes, never rewrites the wrap, and skips records
whose pair already matches.

**The twin interaction, which was the surface I was least sure of, holds.** Both Fable and Grok
walked it independently and reached the same answer: under twins the move collides and produces
`errSecDuplicateItem`, but **the repair runs before the status guard throws**, so the stranded
twin's class is corrected even on the call that then fails visibly. The toggle still fails; the
stranded class does not. Fable adds that the repair itself can never collide, because
`kSecAttrAccessible` is not part of the primary key.

**The preference-off gap is correct rather than residual.** Grok: the record's flag is true because
it was written with sync on, and the preference only flips after a successful conversion, so a
device holding one still has the preference on. Fable adds the one route that reaches a
preference-off device, app deletion and reinstall, since the Keychain outlives the app and the
preference does not, and notes the mismatch is inert there until sync is wanted again, at which
point the enable toggle repairs before anything depends on it. ChatGPT agrees no automatic loosening
is needed.

**Loosening the class is the right trade**, unanimously. Fable's reasoning: the content is
ciphertext, so the class governs sync eligibility rather than confidentiality, and it is exactly
what the flag already promised. Bringing the flag to the class instead would decide on no evidence
that a record marked for iCloud stays off it, **which is the habit this gate has now filed three
findings against**.

**The shared definition is not circular**, and Fable broke the worry properly rather than
dismissing it: the hosted tests compare the stored class against the raw `kSecAttrAccessible*`
constants rather than against `forSync`, so a wrong definition reddens two tests instead of
agreeing with itself.

## On the panel, after five verification rounds

**Three consecutive rounds have now ended two-to-one, with the same engine dissenting, and in all
three the dissent was specific and right.** Each time the mechanism was fixed and a remainder
survived that the other two named and accepted, or in this case reasoned past.

That is worth recording without turning it into a ranking. Fable and Grok each produced findings
this round that the dissent did not: the twin ordering, the reinstall route, the non-circularity of
the shared definition. **What the pattern actually argues for is keeping three**, and for reading a
lone "no" as a claim to check rather than a vote to be outvoted.

## What was done: S1-35

**The repair fails closed.** A `SecItemUpdate` that does not succeed throws, so
`setSynchronizable` throws, so `SyncAwareKeychainStore` never reaches the account conversion and
the interface never commits the preference. The comment cites the rule it broke, which was already
in the file next door.

**The seam was generalised rather than duplicated.** `duringSave` became `beforeWrite` and is
called at both gaps: the one in `save` and the one in the repair. One optional closure, two call
sites, still `nil` on every shipping path and still reachable only through the internal
initialiser. The alternative was a second hook to test three lines.

The test removes the record in the gap so the class update lands on nothing, and asserts the throw.
Mutation verified applied: restoring the swallowed status reddens it.

### An interaction I found while implementing, which is not a new finding but is worth stating

**On the disable direction the throw arrives after the accounts have already moved.**
`SyncAwareKeychainStore` converts the accounts first when turning sync off, then the wrapped key.
So a failed repair on that path now throws with every account already local while the preference,
which only flips after success, still reads on.

That is **S1-28's shape exactly**, already filed: the switch overstating protection. This change
does not create it and does not widen it beyond one more route to it, and the alternative is the
silence that made S1-35 a medium. **Recorded here so it is a known consequence rather than a
discovery.** S1-28's fix, a twin pre-flight before the accounts convert, is also the fix for this
route.

## S1-33 is waived

**Decision: recorded, not fixed.** Under the gate's rule, an item left standing is listed with its
reason.

**What it is.** iCloud can replace the bytes of the observed record, at the same primary key, in
the gap between `save` reading it and writing. Two engines called it the API's floor and one called
it the remainder of S1-26.

**Why it is not being fixed.** Reaching it needs a cross-device erase and re-create landing inside a
microsecond window during a concurrent passphrase change on this device, and **passphrase
replacement has no interface at all**: `replacePassphrase(with:)` is called by nothing but tests.

**And the available fix is not cheap.** `E12-a-compare-and-swap-token.md` measured that
`kSecAttrGeneric` can carry a compare-and-swap token, so the floor claim is false and a mechanism
exists. But it rests on two things nobody has measured: whether iCloud carries the token between
devices unchanged, and whether every writer maintains it, since a peer on an older build updates
the value and leaves the token alone. Building a version-token protocol into the store that has
produced a high and two mediums, on two unmeasured preconditions, to close a window nothing can
currently reach, is the worse bet.

**What would reopen it.** A passphrase-change screen shipping, or the two-device measurement E12
asks for coming back positive. Either changes the arithmetic and this decision should be revisited
rather than inherited.
