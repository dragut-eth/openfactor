# Architecture

How OpenFactor is put together, and why. Written for someone auditing the project who has
never seen it before.

This document grows with the code. Sections describing something not yet built are marked
*planned*, so that nothing here is quietly untrue.

## The shape of it

```
OpenFactorCore  (Swift package, no UI, no dependencies)
      ^
      |  used by
      |
   App (iOS)        Watch (watchOS)
```

The split is the most important structural decision in the project. Everything security
sensitive is in `OpenFactorCore`: encoding, code generation, URI parsing, and secret
storage. It contains no SwiftUI, no view models, and no platform UI code, so an auditor
can read the part that matters, verify it against the RFCs, and stop, without wading
through interface code. The app targets are deliberately thin.

## OpenFactorCore

*Everything but `SecretStore` exists as of PR 3. Storage arrives in PR 4.*

| Component | Responsibility |
| --- | --- |
| `Base32` | RFC 4648 decoding and encoding. Every secret arrives as Base32 text |
| `HOTP` | RFC 4226 counter based codes. SHA1, SHA256, SHA512 via CryptoKit |
| `TOTP` | RFC 6238 time based codes on top of `HOTP` |
| `OTPAuthURI` | Parsing and serializing `otpauth://` URIs |
| `SecretStore` | Reading and writing secrets, backed by the Keychain |

### Design decisions

**Time is passed in, never read.** Nothing in `TOTP` calls `Date()`. Every function takes
the moment to generate for as a parameter.

The roadmap originally called for injecting a clock protocol. A plain `Date` parameter
turned out to be strictly better: it is the same testability with no protocol, no
conformance, and no stored state, and it still leaves room for a correction for a skewed
device clock, which becomes an adjustment at the call site rather than a second
implementation of a clock. The interface layer owns the timer and therefore owns the
question of what time it is.

**The secret is not part of the configuration.** `TOTPConfiguration` holds the algorithm,
digit count, and period, all of which are stored and copied freely. The secret is a
parameter to the one function that needs it, read from the Keychain at the moment a code
is generated. No long lived object holds secret material, so no object can leak one by
being logged.

**A code is text, not a number.** `07081804` is a valid code, and an integer would lose
the leading zero. The generators return `String` throughout for that reason.

**Parsing is total.** `OTPAuthURI` either returns a fully valid account or a typed error.
It never returns a partially populated account, because a silently dropped algorithm
parameter produces codes that look right and never work. The failure would not appear at
the scan. It would appear at a login, long after the enrollment page is gone.

The `otpauth://` format has no RFC. It is a de facto standard with real disagreement
between implementations, so the parser is generous about form and strict about meaning.
Four judgement calls, each of which could reasonably have gone the other way:

- **Generous about form.** Scheme, type, parameter names, and algorithm spellings are all
  matched without regard to case, `SHA-256` and `SHA256` mean the same thing, and unknown
  parameters are ignored rather than refused. None of this changes a code.
- **Strict about meaning.** No value that changes a code is ever guessed. A counter based
  account with no counter is refused rather than started at zero, because a counter in the
  wrong place produces codes that are rejected forever and hides the cause.
- **The issuer parameter beats the label prefix** where both exist and disagree, which is
  what the format documentation asks for and what other authenticators do, so an account
  imported here is filed under the same name it would be anywhere else.
- **A bare colon is the label separator wherever one exists,** and an encoded `%3A` counts
  only when there is no bare colon at all. Writers encode colons that are part of an
  issuer or a name and leave only the separator bare, so `Company%3A%20Ltd:alice` means
  issuer `Company: Ltd`. Taking the first colon of either kind would rename the account on
  import. This was a real bug, caught by a round trip test before it shipped.

**`OTPAccount` is transient.** It is the only type that pairs a secret with its metadata,
and it exists for the moment between parsing a URI and saving it, or between loading and
generating. The stored form splits the two, see below. It deliberately conforms to neither
`Codable` nor `CustomStringConvertible`, so encoding or printing an account, and its
secret with it, is never one keystroke away.

**Secrets and metadata are separated by the query, not by the file.** Drawing the account
list never loads secret material. How that is achieved changed during PR 4, and the new
answer is stronger than the planned one, so it is worth stating precisely.

The plan was two stores: secrets in the Keychain, metadata somewhere ordinary. Two
problems with that. Two records can get out of step, leaving a secret nobody can name or a
name with no secret behind it, and more importantly the metadata is not secret but it is
sensitive: the issuer and account name say which services someone uses and under which
email address. In a plist or a database file that sits in the clear on the device and in
every unencrypted backup.

So each account is a single Keychain item. The secret is in `kSecValueData`, the metadata
is JSON in `kSecAttrGeneric`, and both are encrypted at rest. The separation comes from
the queries instead: listing accounts asks for attributes and explicitly sets
`kSecReturnData` to false, so it decrypts no secrets at all, and only `secret(for:)` asks
for data, for one account, at the moment a code is generated. There is deliberately no
call that returns every account with its secret.

**No hand rolled cryptography.** HMAC and the hash functions come from CryptoKit. The only
cryptographic code written here is the RFC 4226 dynamic truncation, which is arithmetic on
the HMAC output and is covered by the published vectors.

**The metadata schema must evolve without stranding old readers.** Metadata is JSON in the
Keychain, and a record written by a newer version will one day be read by an older one, on
a second device that has not updated. Two rules, set at gate A1. New fields must be
optional with a default, so an old reader can ignore them. And values that change code
generation, the algorithm, digits, period, and counter, are never given fallbacks: an
unknown algorithm fails the record loudly, because guessing produces plausible codes that
are rejected everywhere. Cosmetic values get fallbacks instead, which is why an unknown
colour name decodes as the default rather than making an account, or the whole list,
unreadable.

**Decoding is lenient about formatting and strict about content.** `Base32` accepts
lowercase, spaces, and hyphens, because that is how services actually print secrets and
how they land on the pasteboard. It rejects everything else with a specific error rather
than skipping the character, since skipping would decode a different secret than the user
believes they entered. The one deliberate exception is the handful of leftover bits at the
end of a secret whose length is not a multiple of 8 characters, which are discarded rather
than rejected. RFC 4648 section 3.5 permits rejecting them, but a 26 character secret
carries two such bits and real services set them, so rejecting would refuse secrets that
work everywhere else. The reasoning is repeated at the code.

## App targets

*Planned, arriving in PR 5 onward.* SwiftUI, with view models over `SecretStore` and the
generators. Screens and behavior are specified in [UI_SPEC.md](UI_SPEC.md).

**One timer for the whole list,** never one per row. Every visible code recomputes on a
single shared tick.

## Storage and sync

*Storage exists as of PR 4. Sync exists as of PR 13.*

Secrets are Keychain items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` by default.
Turning on sync flips them to synchronizable, which puts them in iCloud Keychain, end to
end encrypted with keys Apple does not hold.

**Sync requires weakening the protection class.** A synchronizable item cannot be
`ThisDeviceOnly`, by definition, so turning sync on moves those items to
`kSecAttrAccessibleWhenUnlocked`. `SecretAccessibility` names both classes and documents
the trade at the point of use, so the weakening is a visible decision rather than a
side effect of setting a flag.

**Switching sync converts items in place and never reads a secret.**
`setSynchronizable(_:)` lists accounts with `kSecReturnData` explicitly false, then calls
`SecItemUpdate` on each one to change the two attributes. Read, delete, re-add would have
been the obvious shape and is wrong three times over: it decrypts every secret, it holds
them all in memory at once, and a crash between the delete and the add loses an account
outright.

**Which items still need converting is a question for the Keychain, not a flag this code
reads.** The listing query pins `kSecAttrSynchronizable` to the state being converted away
from, so it returns exactly the unconverted items and there is nothing to parse. The first
version listed everything and read each item's flag out of the returned attributes,
defaulting to "local" when the read failed. That made the two failures asymmetric: turning
sync on failed loudly, because the update then matched nothing, while turning sync off
skipped the item in silence and left it in iCloud Keychain with the interface saying device
only. In a security tool the quiet failure must not be the one that understates exposure.
Gate A2, F14.

This also makes the idempotency structural rather than conditional: a second run simply
finds fewer items, and finds none once the work is done.

**`syncState()` exists so the interface can describe where secrets are by looking.** It
returns the identifiers of the synced and local accounts, reading attributes and no data.
The delete confirmation uses it to say whether a deletion reaches other devices, and the
settings screen uses it to describe storage rather than reading back the switch the user
chose. The two genuinely disagree: a conversion killed part way leaves a mixture, and an
account synced from another device arrives whatever this device's switch says. Gate A2,
F9 and F12.

**Every query matches both synced and unsynced items,** via
`kSecAttrSynchronizableAny`. Without it, turning sync on would make every existing account
appear to vanish, since the default for an unspecified `kSecAttrSynchronizable` in a query
is false rather than either.

**Only the interface knows whether sync is on.** `KeychainSecretStore` takes the setting at
construction and applies it to new items; it does not read `UserDefaults`, because a
security core that reaches for global mutable state is one an auditor has to chase.

The connection between the preference and the store is `SyncAwareKeychainStore`, in the app
target, which builds a `KeychainSecretStore` per call from the current preference. Per call
rather than per launch, because an account added after the switch moves has to be written
the way the switch says. The first attempt kept one store and rebuilt the view tree when
the preference changed, which worked and also dismissed the settings sheet out from under
the switch the user had just touched. Reading the preference at the call site removes the
stale copy instead of papering over it.

**Sync is a separate protocol.** `SynchronizableSecretStore` refines `SecretStore` rather
than adding a method to it. Only a Keychain backed store can sync, and giving
`InMemorySecretStore` a method that pretends to would put a switch in the settings screen
that does nothing. Code that offers sync asks for the narrower protocol, and a store that
cannot provide it does not get asked.

**The protection class is verified by test** as of PR 5, in the app hosted test target.
It cannot be checked from a `swift test` bundle: reaching the data protection Keychain
needs an entitlement, entitlements come from code signing, and that bundle is unsigned.
The macOS legacy Keychain accepts writes from an unsigned process and ignores
`kSecAttrAccessible` entirely, which makes it worse than useless as a stand in, since
asserting against it would pass while proving nothing.

**One state this has not been shown to repair.** Within a device, re-running the conversion
finishes a half done one, and that is now tested. Across two devices, gate A2 raised a case
the argument does not obviously cover: turn sync off on device A, its items become local,
device B's copies stay synced and may re-arrive on A. A would then hold a local item and a
synced item with the same service and UUID, which the Keychain permits because the sync flag
is part of the primary key, and turning sync on again would update the local twin toward a
primary key that already exists. Whether that happens is unknown, and settling it needs two
devices. Written down rather than assumed away. Gate A2, F13.

**Merging is iCloud Keychain's, and this app does not second guess it.** An item is
identified by its service and its account attribute, which here is the account's UUID, and
that determines what merges and what does not. Three cases, described as they actually
behave rather than as anyone would like them to:

- **The same service enrolled separately on two devices** produces two UUIDs and therefore
  two accounts, both shown. They are genuinely two enrollments with two different secrets,
  so collapsing them would be wrong, and the interface has no basis for guessing that a
  `GitHub` from one device is the same thing as a `GitHub` from another.
- **The same account renamed on two devices** is one item written twice, and the later
  write wins. Not a merge, a replacement, and nothing is lost but a name.
- **An account deleted on one device** is deleted on the others. That is what sync means,
  and it is why deleting asks for confirmation.

Sort positions collide the same way, since each device assigns the next index it can see,
so the list sort has to be stable rather than assume positions are unique. Building a
conflict resolution layer on top of this was considered and rejected: it would mean a
second source of truth about which accounts exist, and the failure mode of getting that
wrong is losing a second factor. Gate A2 should confirm this description against the
behaviour rather than take it on trust.

The watch reads the same synchronizable Keychain items rather than receiving secrets over
WatchConnectivity. A bespoke transfer channel is another place for secret material to
leak, and iCloud Keychain already solves the problem correctly.

## Open decisions

Recorded here so they are not silently defaulted.

### A shared Keychain access group for the watch

**Decided: yes, and it landed in PR 13 rather than PR 14.**

The watch is read only, shows a list and a code, and must work with the phone off or absent.
That rules out asking the phone for a code on demand, and it rules out handing secrets over
WatchConnectivity, which would mean building a second transport for secret material. What
is left is the mechanism Apple provides: both targets declare the same
`keychain-access-groups` entitlement, items are written to that explicit group, and iCloud
Keychain carries them between devices.

Three consequences, and the first is why this cannot wait for PR 14:

- **A Keychain item lives in the group it was written to.** Every secret stored before the
  shared group was declared is in the app's bundle group. Introducing a shared group later
  means migrating them, and a migration that goes wrong looks like "my accounts vanished".

  **PR 13 declared the group and shipped no migration, and that was a bug.** The reasoning
  was that the only user had said their data need not be preserved, which was a wrong
  reading: it meant do not work around my data, not do not write the feature. The symptom
  appeared the first time the watch app ran. The phone showed six accounts and the watch
  showed one, with no error anywhere, because a query naming no access group searches every
  group the app can reach and the phone can reach both. Only the watch, which shares just
  the one group, could see the difference.

  `migrateToDefaultAccessGroup()` is the correction. It moves each item with
  `SecItemUpdate`, which can change `kSecAttrAccessGroup` in place, so no secret is
  decrypted and no crash can lose an account. That the API permits this is proved by test
  rather than assumed. The target group is discovered by writing a valueless probe and
  reading back where it landed, because no public API answers the question and hardcoding
  the name would put the team identifier in the source and give the group two homes that
  could disagree. It runs at every launch, is idempotent, and costs one query once there is
  nothing left to move.
- **The watch will require iCloud sync to be on.** A shared access group shares between apps
  on one device; getting anything to a second device is iCloud Keychain's job. The watch
  cannot work with sync off, and the interface has to say so rather than ship a watch app
  that silently shows nothing.
- **The watch becomes a device holding your secrets.** That belongs in the threat model
  next to the sync entry, not left implicit.

**Verified on 2026-08-14, on a real Apple Watch Ultra paired to a real iPhone.** The watch
app read an account that was created on the phone, and named its issuer. Nothing was
transferred between the two devices by this app: the phone wrote to the shared access
group, iCloud Keychain carried the item, and the watch read it from the same group.

This was the load bearing assumption of the entire watch design and it had been open since
PR 5. It was proved before any of the watch interface was written, by a target whose only
screen reads the Keychain and reports what it found, precisely so that a wrong answer would
be legible rather than showing up later as an empty list with several possible causes.

Gate A2 had already improved the odds without settling it, by finding Apple's statement
that watchOS 7 and later synchronizes keychain items. That was the half most likely to be
false. The access group half is now observed rather than reasoned.

### The Xcode project file

**Decided in PR 5: checked in, not generated,** which is the opposite of the lean recorded
here beforehand. Requiring a `brew install` before anyone can open the project is a real
cost for a project whose pitch is that it has no dependencies, and a generated project is
only as trustworthy as its generator. The auditability that costs is bought back by
`docs/PROJECT.md`, which says in words what the project contains, and by a CI job that
asserts the load bearing settings still match it. Full reasoning in that file.

### Export format

**Decided in PR 16.** An encrypted archive with a passphrase derived through a strong KDF.
The format will be documented in `docs/BACKUP_FORMAT.md` so an archive can be decrypted
without this app, which is a requirement rather than a nicety: a backup you can only open
with the software that wrote it is not really a backup.
