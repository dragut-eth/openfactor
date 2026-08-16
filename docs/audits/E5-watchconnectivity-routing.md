# E5: can a sibling app reach another app's watch over WatchConnectivity?

**Not by simply having a session.** A second app signed by the same team activated
`WCSession` successfully and found it inert: no counterpart, no reachability, and a send that
failed by name. Measured on Xavier's iPhone 15 Pro, 16 August 2026.

This is item 2 of the vault design's prove list. It was demoted from load bearing to defence in
depth when the provisioning exchange gained a six digit authentication string, so this measures
something the design no longer depends on. That is the right order: the claim was made
independent of the answer first, and the answer collected second.

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

**It is not scheduled, because the design no longer turns on it.** The six digit string means an
injected request cannot be approved by a person comparing two screens, whatever the routing
does. If that string is ever removed, this probe becomes load bearing again and must be run
first.
