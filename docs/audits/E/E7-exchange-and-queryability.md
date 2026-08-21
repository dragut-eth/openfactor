# E7: the watch exchange, and what an opaque item costs the store

Items 4 and 5 of the vault prove list. Both settled. Item 6 could not be run and the reason is
recorded at the end rather than glossed.

## Item 4: the exchange fits, and the binding works

The protocol in `docs/VAULT.md` was implemented on both sides and run, rather than reasoned
about. Sizes are measured, not estimated.

```
request  (watch -> phone):  85 bytes
response (phone -> watch): 145 bytes
WCSession interactive limit: 65536 bytes

both sides derived the same key: true
watch recovered the vault key:   true
authentication string matches:   true   (110408)
```

**Four hundred times the headroom.** Message size was raised as something that might constrain
the design; it does not come close to mattering. A P-256 public key in x963 form is 65 bytes,
the sealed 32 byte vault key is 60 with its nonce and tag, and everything else is a version and
a nonce.

**Agreement alone would prove nothing**, so the run includes the negative controls:

```
a substituted phone key still opens it: false   (must be false)
the SAS changes when the transcript changes: true   (must be true)
```

The first is what proves the transcript binding is real rather than decorative: swap the phone's
public key and the derived key no longer opens the payload. The second is what makes the six
digit string worth showing, since a string that did not move with the transcript would be
theatre.

**What this does not cover:** it was run on macOS CryptoKit, which is the same implementation
watchOS carries, but a watch was not involved. The remaining watch-specific question is whether
a watch app can hold the private key in its own container, and E4 already measured that
containers behave as expected for the platform.

## Item 5: an opaque item costs no queryability

Settled by reading the store rather than probing it, because the question is what the code asks
the Keychain for, and that is visible.

`KeychainSecretStore` selects items by exactly three things:

| Selector | Today | Under the vault |
| --- | --- | --- |
| `kSecAttrService` | already a constant, "so the app's items can be found" | unchanged |
| `kSecAttrAccount` | the account's UUID | unchanged |
| `kSecAttrSynchronizable` | true, false, or any | unchanged |

**Nothing else is ever used to select.** Sorting happens in Swift, on already loaded metadata,
not in the query. `kSecAttrLabel` is already pinned to the constant `"OpenFactor"` and was
deliberately never set to the account name, which is the same decision this design makes for the
same reason.

So the opaque layout changes what a returned item *contains*, and nothing about how items are
*found*. The one attribute that disappears is `kSecAttrGeneric`, which held the metadata JSON
and was never a selector.

**One precision the invariants owe.** "No Keychain item carries metadata in the clear, in any
attribute" should read *account* metadata. The service constant and the label identify the app,
not the person's accounts, and both are already deliberate.

## Item 6 could not be run

Rewrapping under two writers needs a second device signed into the same iCloud account with the
same access group, and only the iPhone and the Apple Watch are paired for development. The
watch cannot serve, because under this design it is a reader.

The Vision Pro could, and it would need developer mode enabled and pairing set up first. Each
observation then costs the measured iCloud Keychain latency, which this project has seen run to
half an hour.

It is worth being clear about what it would and would not tell us. Keychain writes are last
writer wins, and the design has no merge to get wrong. What the probe would establish is whether
a same-identifier record written from two devices produces the twin behaviour gate A2 flagged as
theoretical, which is now more relevant rather than less: after the audit, **every account item
is rewritten** on a rename, a reorder or an HOTP counter, not just the wrapped key.

Unblocked by the Vision Pro being paired for development, and cheap to run afterwards.
