# E12: whether the Keychain can do compare and swap

**Date:** 2026-08-20. **Measured on:** iPhone 17 Pro simulator, iOS 26.x, through the hosted test
target, which uses the real Keychain rather than a fake.

## What was being answered

The S1-26 verification round left one window: iCloud can replace the *bytes* of the observed
wrapped record, at the same primary key, in the gap between `save` reading it and `save` writing.

One return called this irreducible, in these terms: **no shape of this code can close it, because
`SecItemUpdate` offers no compare-and-swap, and a Keychain write cannot be conditioned on the value
that was read.** Two of the three treated it as a floor.

**That is a claim about a platform API, so it is measurable rather than arguable.** This project's
E series exists for exactly that.

## The idea under test

The primary key of a `kSecClassGenericPassword` item is the service, the account, the access group
and the sync flag. **`kSecAttrGeneric` is settable and is not part of that key.** So if it can be
matched in an update query, and changed by the same update, it is a version token and the update is
a compare and swap.

## The procedure

For a device-only item and a synchronizable one, identically:

1. Add an item with `kSecAttrGeneric` set to token A and a value of "first".
2. Read the attributes back and check the token is there.
3. `SecItemUpdate` with a query carrying token A, changing the value to "second" **and** the token
   to token B in the same call.
4. `SecItemUpdate` again with a query carrying token A, which is now stale, changing the value to
   "third".
5. Read the value.

## The result

**Identical for both flags, and unambiguous.**

| Step | Device only | Synchronizable |
| --- | --- | --- |
| Add | `errSecSuccess` | `errSecSuccess` |
| Token read back | token A | token A |
| Update matching the right token | `errSecSuccess` | `errSecSuccess` |
| Value after it | second | second |
| Update matching a stale token | **`errSecItemNotFound`** | **`errSecItemNotFound`** |
| Value after that | second, unchanged | second, unchanged |

**`kSecAttrGeneric` is matchable in an update query, is changeable by that same update, and a write
carrying a stale token matches nothing and changes nothing.** That is a compare and swap.

**So the claim is wrong: the primitive exists.** Recorded as a correction to the round rather than
as a criticism of it; every one of these returns has been right more often than not, and this one
was checkable, which is the point.

## What this does not establish

**It does not say the token survives iCloud.** Whether securityd carries `kSecAttrGeneric` across
devices unchanged, normalises it, or drops it, cannot be measured in a simulator. If iCloud does not
carry it, a token written here is not the token a peer's write replaces, and the mechanism gives
either constant failure or a false sense of safety. **That is the question to settle on two devices
before anything is built on this**, and it is the same shape as E8, which measured propagation
rather than assuming it.

**It does not make the mechanism safe by itself.** A compare and swap only holds if **every writer
maintains the token**. A peer running an older build updates the value while leaving the token
alone, so this reader's stale token still matches and the write lands anyway. The guarantee is
therefore against races with builds that participate, not against all races, and a version that
introduced it would have to treat an absent token as "no guarantee available" rather than as
permission.

**It was measured on a simulator.** Every load-bearing measurement in this project has been repeated
on hardware, and this one has not.

## Where this leaves S1-33

It moves it from "an accepted floor" to **"an open question with a candidate mechanism and two
unmeasured preconditions"**. Nothing has been built on it, and nothing should be until the
propagation question is answered on two devices.

The experiment itself is kept as `OpenFactorTests/GenericAttributeExperiment.swift`, as assertions
rather than as a printout, so the platform behaviour it records is re-measured on every run and a
future iOS that changes it is noticed here rather than in the field.
