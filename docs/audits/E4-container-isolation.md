# E4: is another app's private container reachable by a sibling?

**No.** The sandbox denies it at the system call level, on a device where the attacking app
knew the victim's exact path, was signed by the same team, and the device was unlocked.
Measured on Xavier's iPhone 15 Pro, 16 August 2026.

This is the assumption `docs/VAULT.md` rests on, and it was listed as unproven because the
belief had the same shape as the one gate E1 destroyed. It is now measured.

## Method

Two apps, same team, same wildcard development profile, same harness as E1.

Probe A wrote a file called `vault.key` into its own `Application Support`, with the strongest
file protection class, then **published its absolute path into the shared Keychain group** that
E1 proved a sibling can claim. That is the realistic attack chain rather than a contrived one:
the Keychain hole gives the attacker the path, so the container is attacked from a position of
full knowledge.

Probe B read the path out of the Keychain and tried Foundation, `FileManager`, a raw POSIX
`open`, and directory enumeration. It also wrote and read a file in its own container, so a
failure could not be blamed on a broken harness.

## Result

```
A wrote: /var/mobile/Containers/Data/Application/9A2FBA4D-…/Library/Application Support/vault.key
A can read own file: VAULT-KEY-OWNED-BY-A
A published path to shared keychain: 0

B learned victim path from keychain: /var/mobile/Containers/Data/Application/9A2FBA4D-…/vault.key
B String(contentsOfFile:): nil
B FileManager.contents: nil
B FileManager.isReadableFile: false
B POSIX open failed, errno 1 (Operation not permitted)
B enumerate /var/mobile/Containers/Data/Application: denied
CONTROL B own file: CONTROL-B
```

**`errno 1`, `EPERM`, from a raw `open(2)` is the load bearing line.** Foundation returning
`nil` could have been politeness; the kernel refusing the file descriptor could not. The
sandbox denied it, not a library.

Enumeration was denied too, so an attacker who did not already know the path could not go
looking for it. The control passed, so the harness worked.

## What this proves, and what it does not

**Proves:** an app of the same team cannot read another app's private container, even holding
its exact path. The container is a real boundary where the Keychain access group is not. The
asymmetry the vault design is built on is measured, from both sides now.

**Does not prove:** anything about a jailbroken device, a compromised operating system, or a
malicious update to the app that owns the container. Those remain where `docs/VAULT.md` puts
them, in the section on what it does not defend against.

**Does not prove durability.** This was about *access*. Whether the container survives an
"Offload App", a Quick Start migration, or a restore is a separate question, and it stays on
the list of things to settle.

## Reproducing it

Not committed, for the same reason as E1: these are two apps whose only purpose is stealing
from each other. The method above rebuilds them in twenty minutes, and both were uninstalled
from the device afterwards.
