# A4 round two, scope 3: what changed and why

Round one found eleven items in the code that reads bytes somebody else wrote. All eleven are
fixed. **Review commit `8471c33`.** Round one read `74fe841`.

## The eleven

**1. Enrollment accepted what the backup format forbids.** `AccountLimits` now holds the minimum
secret length and the maximum counter, and all four enrollment paths read them, as does the writer.

**2. A migration payload crashed the app.** `Int(clamping:)` turned a hostile batch field into
`Int.max` and the next `+ 1` trapped. Fields above a stated maximum are refused rather than
clamped.

**3, 4, 5, 9. The import bounds, fixed as one family**, because they are one mistake made in four
places. The bound ran after `Data(contentsOf:)`, so a four hundred megabyte attachment was a four
hundred megabyte allocation, which on a phone is a termination rather than a message; the size is
asked of the file system first now. The same eight mebibyte number quietly retired the format's
frozen ceiling, so conforming version 1 archives were refused before the passphrase screen, in a
way their owner could not tell apart from rubbish; the format decides the bound now, and an archive
is held to the ceiling and nothing else. The writer could emit an archive the reader must refuse.
The picker path had no bound at all, and the share extension materialised the whole attachment
before measuring it.

**6. Duplicates within one file bypassed detection.** Each imported account was compared only
against what was stored, so a file listing the same account twice added it twice while the preview
said "will be added" for both.

**7. The JSON sniff was defeatable**, and it was stricter than the reader it guards, which is the
wrong direction for a recovery file. A byte order mark sent an archive to the labelled-text reader,
and the RTF guard ran before the whitespace skip. The decision is `JSONSniff` in the core now.

**8. The refusal reason lied for a short secret**, reporting invalid characters for a secret that
decodes perfectly.

**10. "Secret keys in the clear" was false for an encrypted archive.** The done screen told
everybody to delete the file they had just imported, including the backup that gets their accounts
back.

**11. `sortIndex` was read from every format and discarded**, so order survived a round trip only
because the writer happens to emit in order.

## Where to look hardest

**`ImportLimits` is new and three findings now rest on it.** If its rule is wrong, four entry
points are wrong together, which is the cost of consolidating them.

**The bound before the copy is a file system question**, so it is only as good as `fileSizeKey` on
whatever the URL points at. A URL whose size cannot be read is allowed through to the second bound.

**`JSONSniff` returns bytes rather than a verdict**, because `JSONSerialization` refuses a leading
mark too. Anything that recognises a file and then parses the unmodified bytes has the bug back.

**Duplicate detection now has two sources**, the store and the accounts seen earlier in the same
file. The second was added this round.
