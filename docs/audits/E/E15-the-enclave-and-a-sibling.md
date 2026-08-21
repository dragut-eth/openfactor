# E15: can a same team sibling use another app's Secure Enclave key?

**Yes. It finds the key, uses it, and reads the plaintext.** A second app, different bundle
identifier, same developer team, declared the first app's access group in its entitlements,
located its Secure Enclave key, and decrypted a message sealed to that key. **Adding a user
presence requirement changed nothing except that the phone asked for a passcode first.**

**Measured on Xavier's iPhone 15 Pro, iOS 27.0, 21 August 2026.**

## Why it was run

**A decision was about to be taken on reasoning alone.** Gate A4's closing round produced one
finding all three reviewers reached independently: the vault key is a `.complete` protected file
the process can read whenever the device is unlocked. The remedy they named, and that
`docs/MASVS.md` costed under MASVS-CRYPTO-2, was to wrap it under a Secure Enclave key with a
`.userPresence` access control.

**The objection to that was structural and unmeasured.** An Enclave key has to persist as a
Keychain item, and `E1-keychain-access-groups.md` measured that the Keychain is not a boundary
between apps of one team. Whether finding such an item is enough to *use* it was the open step,
and this project has been wrong four times by treating that kind of step as obvious.

## Method

Two throwaway apps, built and installed with `devicectl`, deleted afterwards. The shape is E1's,
deliberately, because this is E1's question pointed at different hardware.

| | |
| --- | --- |
| **Writer** | bundle `dev.openfactor.e15.writer`. Creates a Secure Enclave P-256 key in **its own default access group**, tagged `dev.openfactor.e15.key`, and seals a known string to it with ECIES. Leaves the ciphertext in a shared App Group |
| **Reader** | bundle `dev.openfactor.e15.reader`. A different app. **Declares `HST4KH9P2X.dev.openfactor.e15.writer` in its entitlements**, finds the key by tag, and tries to decrypt |
| **Control** | Reader also creates, finds and uses **its own** Enclave key first, so a negative result cannot be blamed on a broken query |

**The first attempt was wrong and its result was discarded.** Reader did not declare the writer's
access group, so it searched only its own and reported "not found". That measured nothing except
that two apps have different default groups. **It also had no control**, so the negative was
worthless in both directions. E1 carried a control and declared the victim's group; this did not,
until it did.

## Result

```
control: OK. This app can create, find and use its own Enclave key.

named victim group: status 0
any entitled group: status 0
FOUND the key reference.
Read 123 sealed bytes.
OPENED IT: E15-PROOF-ONLY-OPENFACTOR-SHOULD-READ-THIS
```

**Identical with `.userPresence` on the key**, except that iOS asked for the device passcode
before the decryption completed. **The sibling still got the plaintext.**

## What this means

**The Enclave protects the key material and does not protect the key.** The private half never
left the hardware, exactly as documented. It did not need to: the sibling asked the Enclave to
perform the operation, and the Enclave did, because the Keychain considered the caller entitled.
**Non-extractable is not the same as exclusive.**

**A user presence requirement is a prompt, not a boundary.** It converts a silent theft into one
the person is asked to approve, in a dialog raised by the attacking app. Somebody used to
authenticating for this developer's apps will approve it. **That is an argument for who you install
from, not a control the platform enforces.**

## What it decided

**The Secure Enclave wrap was examined and declined**, and this is the measurement behind that.
Wrapping the vault key under an Enclave key would move its protection **from the app container,
which `E4-container-isolation.md` measured as a real boundary, onto the Keychain, which E1 and now
E15 both measure as no boundary at all against this team.** It would have made the app weaker
against the attacker it actually names, in exchange for hardening one case it has declared out of
scope.

**`docs/VAULT.md`'s invariant now has two measurements under it** rather than one: the vault key is
never written to the Keychain, and an Enclave-backed item is a Keychain item.

## What this does not establish

**One device, one OS version, one team, once.** The same caveat every measurement here carries.

**Only the access control flags tested.** `.privateKeyUsage` alone and `.privateKeyUsage` with
`.userPresence`. **`.applicationPassword` was not tried**, and it is the one flag that might change
the answer, because it binds use of the key to a secret the app supplies. It is also circular for
this design: that secret would need storing, and the place to store it is the problem being solved.

**Nothing about a different team.** A sibling of another developer cannot declare this team's
access group, and that was not the question.

**Nothing about extraction.** The key material genuinely cannot leave the phone. A container imaged
while unlocked and analysed elsewhere is still a case an Enclave wrap would defend, which is why it
was a real trade rather than an obviously bad idea.

## Reproducing it

**Two apps, one team, an afternoon.** The writer creates an Enclave key in its own default group
and seals a known string; the reader declares that group in its entitlements and tries to open it.
**Carry the control**, because a negative without one says nothing at all. That mistake was made
here first and is recorded above rather than tidied away.

**The apps are not in this repository.** They were throwaway, they held nothing, and they were
deleted. Everything needed to write them again is in this file.
