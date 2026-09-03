# E16: two writing iPhones, and when a list shows what arrived

**Date:** 2026-09-02, 19:48 to 20:25. **Measured on:** an iPhone 15 Pro on iOS 27 and an iPhone XS
on iOS 18.7.9, one Apple Account, iCloud Keychain on, plus an Apple Watch Ultra reading the same
records. OpenFactor 1.0 (8) on all three. Throwaway records only, an encrypted backup taken first.

## What was being answered

**The gap A2 opened and never closed.** A2 was written expecting two iPhones and got a watch, which
is read only, so every step needing a second *writing* device went unrun. Gate A4 circled the same
case. Audits X1 and X2 both list multi-device iCloud conflict and deletion propagation under claims
they could not verify. Three consecutive reviews have named it.

The questions were: do two devices adding different accounts merge, does the same record edited on
both resolve or corrupt, does anything tell the person a conflict happened, and how long does any
of it take.

## Method

Three throwaway records created on the 15 Pro and allowed to reach the XS. Both phones then put in
airplane mode, so they could diverge without talking. Each renamed the same record differently and
added a record the other had never seen. Airplane mode off on both at **19:48**.

| Device | While offline |
| --- | --- |
| 15 Pro | `TEST-ONE` renamed to `ONE-FROM-15PRO`; added `ONLY-ON-15PRO` |
| XS | `TEST-ONE` renamed to `ONE-FROM-XS`; added `ONLY-ON-XS` |

## What the conflicts did

**Additions merged.** Both new records reached every device. Nothing was dropped.

**The same record edited on both resolved last writer wins, at the item level.**
`ONE-FROM-15PRO` won on all three devices. The XS's rename was gone, and its owner watched it
disappear from the device that made it.

**Nothing anywhere said a conflict had happened.** No prompt, no marker, no second copy. This was
the expected answer and it is now measured rather than assumed. A person who renames an account on
two devices in the same window loses one rename and is never told.

## What the run actually found, which is not about conflicts

**19:48** reconnected. Neither phone changed.

**19:51** both apps backgrounded and reopened. Neither phone changed.

**19:55** the watch showed the merged set. Both phones still showed their own pre-reconnect view.
A read-only device was ahead of both writing devices.

**19:58** the 15 Pro force quit and relaunched. It converged instantly. The XS, left running,
did not.

**The list is read when its view is created, and at no other time.** `AccountListView` loads in
`onAppear` and after a sheet closes. Its one second timer calls `tick`, which recomputes six digits
and does not re-read the store. `onAppear` does not fire again when an app is backgrounded and
returned, because the view never left the hierarchy.

## The three devices were one rule in three configurations

This took three wrong theories to reach, and the correction is the useful part.

**The XS, later, showed a deletion within a minute with no force quit**, which appeared to
contradict everything above until the reason came out: App Lock is enabled on it, and it asked for
Face ID. **App Lock swaps the root view out and back**, so releasing it creates `AccountListView`
fresh and `onAppear` fires. A background and return with no lock does not.

**The watch was not refreshing better. It was being relaunched more.** Watch apps are evicted
aggressively, so opening one is nearly always a cold launch. That is the whole of why it looked
ahead.

Except that the watch then updated **while its list was on screen and untouched**, which the phone
never does, and that has a cause worth copying:

    watch   .task(id: scenePhase) { load() }
    phone   .onAppear { model.load(at: Date()) }

**The watch keys its load on the scene phase.** A watch screen dims and wakes constantly, so the
task re-runs and the whole list is re-read. The phone loads once and then only recomputes digits.

**So what a person sees depends on their own settings.** With App Lock on, every return through the
lock refreshes and nothing looks wrong. With App Lock off, or returning inside its grace window, a
phone can sit stale indefinitely. Both phones were in the second state for ten minutes tonight.

## Timings, and one number this project should stop quoting

| Event | Time | Elapsed |
| --- | --- | --- |
| Airplane mode off, both phones | 19:48 | |
| Watch holds the merged set | ~19:55 | ~7 min |
| Deleted five records on the 15 Pro | 20:20 | |
| Gone on the XS | 20:21 | ~1 min |
| Gone on the watch | 20:25 | ~5 min |

**A2 measured a withdrawal at fourteen minutes and called it the slowest operation it saw.**
Tonight a deletion reached a second phone in about one minute and a watch in about five. Two
devices, an order of magnitude apart from the recorded figure and from each other.

**Neither number is representative on its own, which is the point.** Propagation is not a constant
and this project should stop quoting fourteen minutes as though it were one. What can be said is
that a deletion reached two devices in single digit minutes on one evening, and took fourteen on
another, and nothing in the app influences either.

## What this closes and what it does not

**Closed:** two writing devices merge additions, resolve same-record edits last writer wins, and
report nothing. The oldest open measurement in the project, named by A2, A4, X1 and X2.

**Not closed, and deliberately not attempted:** the delete-versus-edit race, where one device
removes a record while the other edits it. It needs a third offline window and the evening had
gone on long enough. It is the one case where a resurrected record is plausible.

**Not measured:** whether anything is lost when both devices write the *same* field within the
sync window rather than while offline. The airplane mode method forces a clean divergence, which is
the strong case, not the subtle one.

## What follows from it

**The refresh behaviour is a missing feature rather than a defect**, and the maintainer's framing
was better than the reviewer's. Nothing claims live refresh. The app's own sync copy says where
accounts are, not that they appear anywhere. And iCloud Keychain has no change notification, so an
app cannot be told an item arrived: re-reading on some trigger is the only mechanism available.

**The trigger the watch uses is the one the phone is missing**, and it is already in this
repository, on hardware the maintainer owns, in a file written by the same person. That is the
third time in one audit round that one surface held the answer while another did not: `VERIFYING.md`
had the accurate Keychain sentence while three places overstated it, `ManualSetupView` had the
masked field with a reveal while both passphrase screens were plain, and now this.

**The caution against doing it quickly.** Scene phase on iPhone is entangled with App Lock, the
cover window and the Face ID gap, which is the machinery where three separately reasoned fixes were
each wrong before a device trace settled it, and where a flush on the wrong side introduced a second
leak. The pattern is proven; the place it has to go is not forgiving.

## What was changed, and validated on the same hardware

`AccountListView` now reloads when the scene becomes active. **`.active` only, rather than the
watch's whole scene phase**, for the reason above: `.inactive` is the Face ID window and the cover
window, and this change had no business being anywhere near them.

**Not gated on the sync preference**, deliberately. Records synced before it was turned off still
change, which is the mixed state the settings screen already has copy for, and a refresh that is
unreliable in the hardest state to reason about is worse than one that costs a Keychain read.

**Two things made this smaller than it looked.** `load` was already written to be called on a live
list: it matches existing rows by identifier so a reload does not blank every code, which somebody
had anticipated long before tonight. And drag to reorder sits behind an explicit edit mode, so
nothing in the list competes with a refresh.

**Validated on the 15 Pro against the XS**, with a record added on one phone and then deleted from
it, returning to the other inside the App Lock grace window so no lock screen intervened. That is
the exact path that showed a stale list all evening. It now shows the truth, including removing a
record from the screen while it is being watched, which is new behaviour for this app and was
looked at once before being accepted.

**The record crossed between the two phones in under a minute**, both appearing and disappearing.
That is the third sub-minute propagation of the evening and it is now the pattern rather than the
outlier. A2's fourteen minutes stands as something that happened, not as a figure to plan around.

**What is still not done:** pull to refresh. It is a genuine feature rather than a fix and belongs
to a decision of its own. With this reload in place the only case it covers is a change arriving
while somebody sits looking at the screen.
