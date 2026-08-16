# V2, third external review: Fable on `docs/VAULT.md`

Three findings, one blocking. Its best one is the only **semantic** error found in the whole
round: a sentence that is true, and leads a reader to a false conclusion.

## Accepted, blocking

**F1. The provisioning tap authorises timing, not identity.**

The sharpest sentence in the round. The person taps Provision, but nothing lets them verify
*whose* public key arrived. The tap gates **when** the exchange happens, not **who** it happens
with, and from the user's side an injected request looks identical to their own watch.

That matters because the only other defence is item 2 of the prove list, WatchConnectivity
routing exclusivity, which is exactly the shape of belief E1 destroyed.

**And the argument for the fix is better than the fix.** A short authentication string derived
from the exchange, shown on both screens for the person to compare, **demotes routing
exclusivity from load bearing to defence in depth**, which is the move this document makes
everywhere else. It stops the security property depending on how a probe turns out.

This changes the disposition recorded for ChatGPT's C2, which was accepted only *conditionally*,
pending the routing probe. Fable's framing is right and mine was wrong: the point of adding it
is precisely that we stop needing the probe's answer to hold the claim.

**F2. A passphrase change is not revocation, and the document reads as though it might be.**

The best finding of the round, and neither other reviewer saw it.

`VAULT.md` presents rewrapping as a feature: changing the passphrase rewraps 32 bytes rather
than re-encrypting every account. Operationally true. But **rewrapping does not rotate the vault
key**, and the wrapped item is a Keychain item, so the in-scope adversary can capture it. Anyone
holding an old wrapped item and the old passphrase can unwrap the vault key **forever**, and
changing the passphrase does nothing about it. A sibling can also replay the old wrapped item,
which the replay paragraph covers for accounts and not for this.

So a user told "change your passphrase" after a suspected compromise has been given a remedy
that is not one. The document must say that responding to compromise requires **vault key
rotation**, meaning a new key, every account re-encrypted, and a new passphrase, and either
define that path or state plainly that version 1 does not have it.

## Accepted

**F3. "The strongest file protection class" must be a named class.** In a page normative down to
AAD strings, this is the one place two different implementations could both claim compliance.
The choice has consequences that need stating: `.complete` means unreadable whenever the device
is locked, which forecloses background work and interacts with watchOS wrist-lock semantics,
while `.completeUntilFirstUserAuthentication` is a materially weaker and different promise.

**F4, minor.** The salt and iteration count sit outside the seal, as they must, but are not in
the AAD. Denial-only given the clamp, and binding them costs nothing.

**F5, minor.** The watch's P-256 private key could live in the Secure Enclave rather than the
container. Hygiene rather than a hole, since it is used once and discarded.

## What it did not catch

Recorded because coverage is the point of running three. Fable did not find the incomplete ECDH
transcript, and in fact its own finding assumes a complete exchange by referring to the ECDH
output. It also did not find any of Grok's integration findings.

## Why three reviews rather than one

They divided almost perfectly, and none of the three would have been sufficient:

| | Found |
| --- | --- |
| **ChatGPT** | protocol and format precision: the ECDH was half a protocol, the record formats were not normative |
| **Grok** | integration with code that exists: listing stops avoiding secrets, "written twice" was false, conversion can leave cleartext behind |
| **Fable** | semantic errors: the tap proves timing not identity, rewrapping is not revocation |

Their only overlaps are the central architecture, which all three approve, and the unspecified
encodings, which two reached independently.
