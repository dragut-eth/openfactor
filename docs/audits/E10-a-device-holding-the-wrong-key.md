# E10: a device holding the wrong key notices, asks, and recovers

**2026-08-19.** The two phones from E8 and E9, on one Apple Account.

`VaultGateModel` carries a comment describing a scenario nobody had produced: two iPhones on one
Apple Account, the second replaces the vault, and the first keeps its old key while every record
that syncs is sealed under the new one. Before this, that phone drew the list and showed every
account as unreadable, blaming a legacy item or a newer version of the app, neither of which was
true, and never offered the passphrase that would have fixed it. The rule written to answer it is
`StoredRecords.suggestsAWrongKey`.

**It had never been produced on hardware.** E9's manufacture produced it as a side effect: phone two
destroyed the shared vault and created a new one, so phone one was left holding a key for a vault
that no longer existed while a record sealed under a different key arrived from iCloud.

## What was observed

**First, and this is the part worth recording, the list showed `------` for the accounts.** Phone
one was already foregrounded when the records changed underneath it. The rows had been read while
they were still readable, so they kept drawing, and each attempt to generate a code failed against
a record that was gone or no longer its own. For that window the app said the accounts were broken
when the truth was that this device no longer held their key.

**Force-quitting and relaunching landed on "Enter your vault passphrase".** The wrong-key rule fired
as designed: the key is present, it opens nothing, so the honest screen is the one that asks for the
passphrase rather than the one that lists unreadable rows.

**Entering the other phone's passphrase unlocked it**, and phone one showed the account created on
phone two.

## What this settles

**The wrong-key path works end to end on hardware**, in the direction that matters: a device notices
its key is wrong, says the true thing, and is repaired by the passphrase alone with no reinstall and
no erase.

Taken with E8 and E9, all three legs of recovery have now been exercised on real devices rather than
reasoned about: a replacement phone recovering, a phone in the loss shape repairing itself, and a
phone holding the wrong key being corrected.

## The observation worth filing

**The wrong-key check runs when the app comes forward or the gate re-reads, not continuously.** An
app already open when its records change underneath keeps drawing rows whose codes cannot be
generated, showing `------` rather than the screen that explains what happened.

Reaching it needs another device to replace the vault while this one is open and looking, which is
rare. But "your codes appear broken" is a frightening thing to show somebody when the true
statement is "this iPhone does not have the key to these accounts", and the app already knows how
to say the second one.
