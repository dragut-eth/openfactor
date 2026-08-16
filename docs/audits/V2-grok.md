# V2, second external review: Grok on `docs/VAULT.md`

Verdict: the central design holds, and it holds because of measurements rather than prose. The
page is not finished, and the reasons are the ones it lists about itself plus several it does
not.

This review is the operational and integration counterpart to ChatGPT's protocol and format
one. Its best findings are about properties the document **never mentions**, which is a harder
class to catch than a claim stated wrongly.

**Two of its claims are about code rather than the page, so they were verified here rather than
accepted.** Both are correct.

## Accepted, and these are the two that matter

**G1. The vault silently gives up "listing never loads a secret". Accepted, blocking.**

Verified in `KeychainSecretStore.swift`: every listing path sets `kSecReturnData` to **false**
(four separate call sites), and `kSecReturnData: true` appears exactly once, in `secret(for:)`.
The file's own header states the property: *listing accounts never decrypts a single secret,
and only `secret(for:)` asks for data, for one account, at the moment a code is generated.*

An opaque item ends that. Metadata moves inside the ciphertext, so drawing the list has to
decrypt **every account**, which means every secret is in process memory to render a screen that
needs none of them. Against a sibling app this changes nothing, since it holds ciphertext
either way. Against a process dump, a crash report, or anything reading a foreground app's
memory, it is a real reduction, and the V1 note that "the `SecretStore` contract is unchanged"
was true for callers and false for this.

The document does not mention it, which is worse than getting it wrong. It has to either
preserve the property, by keeping enough outside the ciphertext to draw a list, or state
plainly that it is being traded away and why. **Keeping it is likely to cost some of the
metadata privacy this design exists for**, so it is a genuine trade rather than an oversight to
patch.

**G2. "The only item ever written twice" is simply wrong. Accepted, major.**

Verified: `update()` names only `kSecAttrGeneric`, with an explicit comment that no path through
it can overwrite a secret. Today a rename, a colour change, a reorder or an HOTP increment
rewrites metadata and never touches the value.

Under the vault, metadata lives inside the sealed value, so **every one of those becomes a
rewrite of the ciphertext**. HOTP is the sharp case: the counter advances on every code, so a
counter-based account rewrites its sealed blob each time it is used, with a fresh nonce, and
syncs it.

Two consequences the document owes: the two-writer rewrap risk it flags for one item now applies
to every account item, and the sync churn is materially higher than today.

## Accepted

**G3. Conversion can satisfy the paragraph and break the invariant.** Current items carry issuer
and name as JSON in `kSecAttrGeneric`. The migration section says to convert accounts and the
invariants forbid clear metadata, but nothing says **wipe the old attribute**. An implementer
who encrypts the value and leaves `kSecAttrGeneric` in place has followed the instructions and
defeated the design. Must be explicit.

**G4. "Closed against another app on the same team" is closed *after* provisioning, not during.**
If WatchConnectivity routing is not exclusive, a sibling requests the key, the person taps
Provision, and the phone seals the real vault key to the attacker's public key. The tap is then
the only control, and it is the confused-deputy shape. The page is honest that this is unproven;
the claim's wording is not conditioned on it.

**G5. App Group containers are not in the invariants, and PR 16c is about to add one.** The bans
cover iCloud Drive and ubiquitous containers, and "private container" is correct read strictly.
The share extension's inbox is an App Group container, which E1's logic already classifies as a
grant rather than a boundary. The key must never go there, and that sentence is missing.

**G6. V1's M8 never made it into the page.** The third watch empty state, provisioned with
ciphertext arriving but no vault key, is recorded in `V1.md` and absent from `VAULT.md`. Its
existing second branch tells the wearer to check sync, and this project has measured turning
sync off emptying a watch in fourteen minutes.

**G7. "Escrow stops being load bearing" is half true.** Correct for confidentiality: a
compromised iCloud Keychain yields blobs. False for availability: with sync on and every device
lost, escrow is precisely how the ciphertext and wrapped key come back so the passphrase has
something to unwrap. The sentence needs splitting.

**G8. `SECURITY.md` describes the world before this page.** Accurate today, wrong the day this
ships. Not a defect in the design; an obligation attached to it.

**G9. Encodings unspecified**, including the GCM nonce and tag, which the wrapped-key structure
never names. Same finding as ChatGPT's C3 and C4, reached independently, which raises rather
than lowers its weight.

## What both external reviews agree on

The central move is right: ciphertext in the Keychain, key in the container. Neither found a
flaw in it, and both reached the same summary independently, that the Keychain has become
storage and transport rather than the confidentiality boundary. Both refuse to freeze the
document. Both land on the same unspecified encodings.

They do not overlap anywhere else, which is the argument for having run two.

## Disposition

Still nothing edited into `VAULT.md`. Fable has not reported. When the revision happens it now
carries, at minimum: the complete ECDH transcript with a nonce and bound public keys, exact
record encodings with test vectors, the wipe-the-old-attribute rule, the App Group ban, the
third watch empty state, the split escrow sentence, and an honest decision about whether
listing still avoids loading secrets.

That last one is the only finding in either review that is a **design** question rather than a
gap to fill, because preserving it may cost some of the metadata privacy this whole redesign
exists to buy.
