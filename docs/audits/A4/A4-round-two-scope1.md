# A4 round two, scope 1: what changed and why

Round one found eleven items in the vault at rest. All eleven are fixed. This is the "what
changed" block the round two prompt in `docs/audits/A4/A4-prompts.md` calls for.

**Review commit `a7f9121`.** Round one read `74fe841`.

Round two asks three questions and only three: does each change address the finding it claims to,
did any change introduce something new, and does any comment or document now claim something the
code stopped doing.

## Read this first

**The suite that covered this scope never ran.** `VaultTests` is gated on `KeychainAvailability`,
the package's test binary is unsigned, so `SecItemAdd` returns `errSecMissingEntitlement`, and the
whole `Vault lifecycle` suite is skipped on the machine the tests run on. This was found while
proving the fixes below: each was reverted in turn to watch the suite go red, and it stayed green
every time.

So the vault's decisions were argued for in comments and verified by nobody, including the two
that destroy accounts when they are wrong. `WrappedRecordStore` is a protocol now, `Vault` takes
one, and the decisions are checked against an in-memory store in `VaultDecisionTests`, which
touches no Keychain and cannot be skipped. Every fix was then reverted a second time, and the new
suite caught each one.

**This is the same disease scope 2's round three named**, in a different file: the decisions were
sitting where the tests could not reach. Weigh the fixes below knowing that until this commit
nothing in this scope was covered by a test that runs.

## The eleven, and what was done

**1. The wrapped key never synced.** `WrappedKeyStore` defaulted to `synchronizable: false` and
nothing ever wrote the flag, so enabling sync moved the accounts and not the means of reading
them. Fixed with 3, since fixing either alone is worse than fixing neither.

**2. The watch wrote the vault key without `.complete` protection**, having borrowed an
`#if os(iOS)` helper. `VaultKeyStore` has its own `writingOptions` now.

**3. `save` twinned on a differing sync flag.** `kSecAttrSynchronizable` is part of a Keychain
item's primary key, so a differing flag produces a twin rather than a duplicate error. `save`
looks before it adds.

**4. `install` wrote the key before excluding it from backup.** Rewritten twice more since, under
scope 2's rounds two and three, and now written inside a directory excluded before any key
material exists.

**5. Errors collapsed to `absent`.** `exists` was `(try? load()) != nil`, so a read failure and an
empty store gave the same answer, and that answer's remedy is to create a vault over whatever is
really there. `Vault.State` has `unavailable`, `state()` distinguishes them, and the app has a
screen whose only action is to look again.

**6. `create(with:)` had no existence check.** It refuses when a record is already present, and
refuses when the store cannot be read at all, on the grounds that the point is not to find a
record but to decline to overwrite what it cannot see.

**7. `refresh()` ignored an arriving wrap.** The early return covered every state, so a record
arriving while a generated passphrase was displayed changed nothing and the next tap tried to
create over it. It now moves away when a record has actually arrived, and leaves the screen alone
otherwise, so a scene becoming active cannot clear a passphrase somebody is copying down.

**8. `replacePassphrase` saved before showing.** Split into `prepareReplacementPassphrase()` and
`replacePassphrase(with:)`, the shape `create(with:)` already had. The one-shot is kept for tests
and carries the same warning.

**9. A future-version record read as a wrong passphrase.** `notAWrappedKey` and
`iterationsOutOfRange` are decided before any derivation runs, so no passphrase could have opened
that record. They are `recordNotUnderstood` now, and the app says updating is the thing to try.

**10. The document mismatches.** The service constant and the UUID case were wrong on a page that
declares itself normative, in the direction that breaks a second implementation. The metadata
encoder now sorts its keys, which the page had always claimed. The "converted" sentence that sat
directly above a section titled "why there is no converter" is gone.

**11. Padding's residual size class.** The page said why padding exists and never what remains
after it. It now says: a coarse class of one, two or three buckets, no characters of any field.

## Where to look hardest

**`VaultDecisionTests` is new and everything rests on it.** If its fake store is wrong, or its
assertions are weaker than they read, this scope is back where it was: unverified. It is the first
place to attack.

**Item 6 changes what creation does on a device that already has a vault**, which is the path
every existing install takes on upgrade. A wrong refusal here is a phone that cannot set itself
up.

**Item 7 changes a guard that exists to protect a passphrase somebody is writing down.** It is
now conditional. A wrong condition either clears the screen under somebody's pen, or restores the
defect it was fixing.

**Item 5 adds a fourth state to a type whose whole documented purpose is telling three apart.**
The page says confusing `absent` and `locked` is the failure that cannot be recovered from.
