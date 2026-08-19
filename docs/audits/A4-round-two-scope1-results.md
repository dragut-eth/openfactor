# A4 round two, scope 1: what three engines found in the fixes

Round two of scope 1 read `46f65a3`. The account it responded to is `A4-round-two-scope1.md`, and
all three engines returned.

**Two engines walked out the same high finding independently, and all three found the same
medium.** That is a higher agreement rate than round one of this scope produced, where no finding
at all was reported by all three.

| Engine | Verdict |
| --- | --- |
| ChatGPT 5.6 Sol | One high, three medium, two low. "Creation remains destructively racy" |
| Grok 4.6 | Two of eleven incomplete, five surviving false claims |
| Fable 5 | Nine of eleven hold, one plausible medium, and a coverage claim it could not verify |

## The high finding, found twice

`create(with:)` asked `state()` whether a record existed, then ran `WrappedVaultKey.wrap` at
600,000 PBKDF2 iterations, then called `save`, which replaces whatever it finds. **A wrapped
record arriving from iCloud during the derivation was overwritten by a wrap of a brand new vault
key**, and every account already sealed under the old one became unopenable by anybody, including
somebody holding the correct passphrase.

Grok put the cost of the gap precisely: hundreds of milliseconds, during which `VaultGateModel`
also holds `isWorking`, so `refresh()` returns early and the gate cannot see the arrival either.

**The test written for that fix could not see it**, because `InMemoryWrappedStore`'s record never
changed between the check and the write. Both engines said so. That is the sharpest thing either
found: the fix had a test, the test passed, and neither fact meant what it appeared to.

Creation now uses `addIfAbsent`, a write that refuses to replace anything. The fake gained a
`duringWrite` hook that does what iCloud does at the worst moment, and the test built on it fails
against the old shape.

## The medium all three found

`refresh()` guarded the passphrase screen with `state == .absent` and nothing else, so a transient
read failure returning `.unavailable` replaced the screen and discarded the only copy of a
passphrase somebody was in the middle of writing down. Nothing is lost from the vault, because
nothing has been written; the person is left holding a string that opens nothing.

The rule is stated the other way round now, which is also how the documentation states it: leave
the screen only on evidence that the displayed passphrase must be abandoned, meaning a record or a
key. **Fable also pointed out the fix had no test at all**, and that the round two account claimed
otherwise, which is a claim-versus-reality defect in its own right. There are three tests now, in
the app target, where that fix lives.

## What each engine found alone

**ChatGPT: the label limit counts characters, not bytes.** A grapheme cluster carries any number of
combining marks, so `"a"` plus fifty thousand combining acute accents is one `Character` and a
hundred kilobytes, and passed the sixty four character bound untouched. Measured before fixing:
one character, 100,001 bytes. There is a byte ceiling now, set at four kilobytes from measuring
the most expensive graphemes people actually type. The first value tried was 1,024, which is below
what sixty four family emoji occupy, and the existing grapheme test caught it immediately.

**Fable: `save` writes the wrong protection class onto a synced record.** The update carried this
store's construction-time `whenUnlockedThisDeviceOnly` onto a record that `setSynchronizable(true)`
had moved to iCloud and to `whenUnlocked`. Either securityd refuses it, or the record sits
device-only while flagged as syncing, which is the silent withholding this store exists to
prevent. Filed as plausible rather than confirmed, because settling it needs a device. Only the
value changes now.

**Grok: creation always wrote `synchronizable: false`.** The app built its vault with the default
store, so the toggle path was fixed and the create path was not. Erase from the locked screen with
sync on, create again, and the wrap is local while every new account syncs, which is the original
total-loss shape reached by a different tap. The wrap now takes the current preference.

**Fable, the same fact from the other side:** a device that enabled sync before this all began is
sitting in the loss shape now and nothing prompts its owner to toggle anything. There is an
idempotent reconcile at launch, following the precedent this scope already set when reading a key
began repairing how it was stored.

## Everything else

The one-shot `replacePassphrase()` is no longer public. A PBKDF2 failure no longer reports as a
wrong passphrase, which was the same category error as finding 9 in miniature. The iteration-count
route into `recordNotUnderstood` has its own test, which Grok noticed it lacked.
`creatingRefusesWhileUnreadable` expects a specific error rather than any error, which Fable
noticed would pass for the wrong reason.

Five documentation claims that survived the last pass are gone: listing has returned the item's
data since the metadata moved into it, so the `kSecReturnData` sentence was false in two places;
nothing is cleared on a conversion that does not exist; and the vault has four states, which the
page, the header and two comments still called three.

**Review commit for round three: `71d3ee6`.**
