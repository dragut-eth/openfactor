# E5: can a sibling app reach another app's watch over WatchConnectivity?

**Not by simply having a session.** A second app signed by the same team activated
`WCSession` successfully and found it inert: no counterpart, no reachability, and a send that
failed by name. Measured on Xavier's iPhone 15 Pro, 16 August 2026.

This is item 2 of the vault design's prove list. It was demoted from load bearing to defence in
depth when the provisioning exchange gained a six digit authentication string. That is the right
order: the claim was made independent of the answer first, and the answer collected second.

**The demotion has since been reversed, and this document went on describing itself as
irrelevant.** The six digit comparison was removed, because the Watch cannot derive the string
until the message that already carries the key, so it could not do what it claimed.
`SECURITY.md` records the removal and states the consequence plainly: routing exclusivity is
load bearing again. **This measurement is therefore load bearing again too**, which is the
opposite of what the paragraph above said for as long as it stood. The scheduling note at the
end of this file named that exact condition and nobody checked it when the condition arrived.

## Method

One iOS app, `dev.openfactor.probewc`, same team, wildcard development profile, **no embedded
watch app of its own**. It activated `WCSession`, reported everything the session would tell it,
and attempted `sendMessage` while a real paired watch was present and carrying OpenFactor.

## Result

```
bundle: dev.openfactor.probewc
has embedded watch app: false
WCSession.isSupported: true
activation callback: state=2 error=none
activationState: 2 (2 == activated)
isPaired: true
isWatchAppInstalled: false
isReachable: false
watchDirectoryURL: nil
sendMessage failed: domain=WCErrorDomain code=7006
  Watch app is not installed.
```

**The session activates and is useless.** `WCSession` is scoped to the app's *own* counterpart,
not to the device's watch. The sibling sees a watch exists and has no route to anybody else's
watch app: no directory, no reachability, and `WCErrorDomain` 7006 rather than a delivery.

So the "a session is a device wide channel" hypothesis is dead. Routing is per companion pair.

**One thing it does leak.** `isPaired` is `true`, so any app of any team learns that this person
owns an Apple Watch. Not a channel, and not a secret, but worth knowing it is readable.

## What this does not settle

The attack the design actually worries about is not a sibling *iOS* app with no watch. It is a
**rogue watch app** that declares `WKCompanionAppBundleIdentifier` pointing at OpenFactor, and
therefore claims to be OpenFactor's counterpart. This probe says nothing about whether iOS would
install such a thing, whether two watch apps may claim one companion, or whether its messages
would reach the OpenFactor phone app.

Answering that needs a second iOS app with an embedded watch app built and signed by hand,
installed onto the watch. It is a day's work rather than an hour's, and the account holder
constraint makes the result predictable in one direction: a same-team attacker can register
`dev.openfactor.app.anything`, so a bundle prefix rule would not stop them.

**This was not scheduled, on the grounds that the design no longer turned on it.** The six digit
string meant an injected request could not be approved by a person comparing two screens,
whatever the routing did. The note then set its own reopening condition: if that string is ever
removed, this probe becomes load bearing again and must be run first.

**That condition fired and nothing acted on it.** The string was removed, and this file kept its
original framing through every round that followed. The gap it leaves is narrow and specific: a
sibling phone app reaching a watch was measured and found inert, in the direction recorded above.
**A watch app claiming to be this app's counterpart was not measured in either direction.**
`SECURITY.md` discloses that and argues such an app would have to ship inside OpenFactor's own
bundle, which is a malicious build and separately out of scope. That argument is reasoning
offered where this folder's standard is measurement, and it is labelled as reasoning rather than
promoted. Whether to run the probe or to accept the assumption in writing is an open decision,
not a closed one.
