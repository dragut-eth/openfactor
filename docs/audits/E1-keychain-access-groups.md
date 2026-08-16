# E1: are Keychain access groups a boundary between apps of the same team?

**No.** Two apps signed by the same Apple Developer Team can read each other's Keychain
items, including items in an app's **default** access group, which most developers assume is
private. This was measured on Xavier's iPhone 15 Pro on 15 August 2026, and it is the finding
the whole vault design exists to answer.

## Why it was run

The project had believed, and its documentation had said, that naming a shared access group
was the thing that let the watch read the phone's accounts, and that the boundary around that
group was the developer team. The question raised was sharper: **can another app from the same
team read secrets it was never meant to see?** The answer decided whether OpenFactor's storage
needed redesigning, so it was measured rather than argued.

## Method

Two throwaway iOS apps, built from one source file, signed with the team's existing wildcard
development profile, installed with `devicectl`, results written to each app's own container
and copied back.

| | |
| --- | --- |
| Probe A | bundle `dev.openfactor.probea`. Writes a secret into **its own app-identifier group**, `HST4KH9P2X.dev.openfactor.probea` |
| Probe B | bundle `dev.openfactor.probeb`. A different app. Declares `HST4KH9P2X.dev.openfactor.probea` in its entitlements and reads |
| Control | Probe B also writes and reads its own group, so a negative result cannot be explained by a broken harness |

## Result

```
role: A
A write into own app-id group: 0
A read back own item: 0 value=SECRET-OWNED-BY-A

role: B
B read A's app-id group: 0 value=SECRET-OWNED-BY-A
VERDICT: CLAIMABLE - sibling read another app's private group
CONTROL B own group write: 0 read: 0 value=CONTROL
```

`0` is `errSecSuccess`. Probe B, a separate application, retrieved the plaintext secret that
Probe A had stored in the group Apple's own documentation calls private. The control passed,
so the harness worked and the result is not an artefact of a failed probe.

## Two objections, both checked

**"That is a development profile, distribution would be stricter."** It is not. The team's App
Store distribution profiles were inspected directly and every one grants the same wildcard:

```
dev.openfactor.app                          -> HST4KH9P2X.*
dev.openfactor.app.watchkitapp              -> HST4KH9P2X.*
dev.openfactor.app.watchkitapp.watchface    -> HST4KH9P2X.*
com.chronosgame.deux                        -> HST4KH9P2X.*
```

An unrelated app on the same team is already provisioned to claim any group under the prefix.

**"The test must be flawed, this cannot be intended."** It is intended, and Apple documents it.
The page *Sharing access to keychain items among a collection of apps* first explains that an
app ID is unique and protected by code signing, so items in the default group are private. The
next sentence says another app signed by the same team may be added **"to the app's default
keychain access group"** using the entitlement.

The uniqueness protects the *identity*: no other app can claim to **be** App One. It does not
protect the *group name*, which any sibling may list in its own entitlements.

Apple's DTS engineers state separately that the Developer portal has no Keychain Sharing
capability because there is nothing for it to do: enabling it in Xcode only edits a local
entitlements file. **There is no registration, no ownership check, and no Apple-side record of
which app may claim which keychain group.**

## What follows

The general rule, which cost three separate attempts to arrive at:

> Anything an app can read **silently**, a sibling app can be authorised to read silently.

Access groups, App Groups and default groups are all grants the account holder controls, so no
arrangement of them produces a boundary that survives the account holder. Only three things do:

1. **Something the user does.** Per-item user presence, enforced by the Secure Enclave.
2. **Something the user knows.** Encryption under a key the app cannot obtain silently.
3. **A different team.** Apple-enforced, and rejected here because it is account configuration
   rather than code: a fork cloning this repository would inherit none of it.

**The sandbox is different, and that asymmetry is the design.** No entitlement grants an app
access to another app's private container. The Keychain is built for sharing; the container is
built for isolation. `docs/VAULT.md` puts the key in the container and the ciphertext in the
Keychain, so each mechanism does the job it can actually do.

## Reproducing it

The probes were deliberately not committed: they are two apps whose only purpose is stealing
from each other, and a repository for an authenticator is the wrong place for them. The method
above is complete enough to rebuild them in twenty minutes, and both were uninstalled from the
device afterwards.
