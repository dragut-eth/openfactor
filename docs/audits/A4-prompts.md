# Gate A4: the prompts

The prompts used for gate A4, published here because a review is only as good as what it was
asked, and a reader who cannot see the question cannot judge the answer. If a prompt was leading,
this is where that shows.

`docs/ROADMAP.md` describes the gate. Four scopes, three engines, two rounds.

## How to run it

**One scope per conversation, and a fresh conversation every time.** Four scopes across three
engines is twelve conversations in round one. A scope carried over into the same conversation as
another is no longer a cold read of it.

**Give the engine the files each scope lists.** Attach them, or let an engine with filesystem
access read them from the repository. Do not point one at a URL, which invites it to review
whatever a search returns rather than the code in front of it.

**An engine may open anything an attached file references, and should be told so.** Scope 1 was
run without that permission and it cost a finding: the one engine that stayed inside its list
missed the most serious defect in the scope and said, correctly, that it could not assess the two
mechanisms involved because the files holding them were not attached. The other two read from disk
and found it. A list is a starting point rather than a boundary, and the scopes below now say so.

**Review a pushed commit and record which one.** Every pass is recorded with the commit it read,
because a finding against code that has since changed is worth knowing about and worth telling
apart from a finding against code that has not.

One asymmetry to record rather than hide: **the Watch key exchange has already had one cold
review**, by ChatGPT, whose findings are fixed. That engine is not cold on that scope any more.
Run it anyway, and note it when reporting, since a second look after a fix is round two's job and
this one arrives early.

## The preamble

Paste this before the scope. It is the same for every engine and every scope.

```
You are performing an independent security review of an open source two-factor authentication
app for iPhone and Apple Watch. Be adversarial. Your job is to find a real defect, not to
reassure me.

I would rather have one concrete finding than ten maybes. A confident wrong answer is worse than
an admitted gap, so where you are unsure whether something is exploitable, say so plainly rather
than either dismissing it or inflating it.

WHAT THE APP IS

Codes are generated on the device. There is no server, no account, and no network code of any
kind. Secrets live in the iOS Keychain, encrypted under a vault key held in the app's private
container. Accounts optionally sync through iCloud Keychain as ciphertext; the vault key never
syncs and is recovered on a new device with a passphrase shown once at setup. An Apple Watch can
be provisioned with the vault key over WatchConnectivity and then works independently.

There are no third-party dependencies. Cryptography is CryptoKit, except PBKDF2 which is
CommonCrypto because CryptoKit has none.

HOW TO ANSWER

For each finding: a severity, the file and the function or line, a concrete failure or exploit
with the actual byte sequence or call order where that makes it clearer, and the smallest fix
that addresses it.

Where you conclude something is sound, say what specifically prevents the attack rather than
asserting that it is fine. "The length is checked before the slice" is useful. "This looks
correct" is not.

Ignore code style, naming, comment quality, test naming, and documentation prose. They are not
what this review is for. Comments that make a false claim about behaviour ARE in scope, since a
comment nobody can trust is worse than none.
```

## Scope 1: the vault at rest

*Attach: `Sources/OpenFactorCore/Vault/Vault.swift`, `VaultRecord.swift`, `VaultKeyStore.swift`,
`WrappedVaultKey.swift`, `WrappedKeyStore.swift`, `VaultPadding.swift`,
`Sources/OpenFactorCore/KeychainSecretStore.swift`, `StoredRecords.swift`, and `docs/VAULT.md`.*

```
SCOPE: what a device holds at rest, and what an attacker who reads it learns.

The design claim is that somebody who obtains every Keychain item and every synced record learns
ciphertext, record identifiers, timestamps and approximate padded sizes, but no account name and
no secret. Attack that claim.

Specifically:

1. Is anything in plaintext that the design says is not? Consider Keychain attributes as well as
   values: labels, accounts, services, access groups, and anything else an item carries that a
   reader can enumerate without opening the value.

2. Does the padding actually hide what it is meant to hide? What can be inferred from the size
   of a stored record, and is the bucketing enough to stop counting or identifying accounts?

3. Is the metadata half genuinely separable from the secret half? The design opens only metadata
   to draw a list and opens a secret only when a code is generated. Does the code hold that line,
   and does a secret ever end up in memory, in a log, or in a copy that outlives the call?

4. The vault key wrapping: is the passphrase-derived key used correctly, are the PBKDF2
   parameters defensible, and does anything about the wrapped record leak information about the
   passphrase or make an offline guess cheaper than it should be?

5. Failure paths. What happens on a partial write, a decryption failure, or a record written by
   a newer version? Can any of them destroy data, or present an empty vault where records exist?

6. Anywhere the code does not do what docs/VAULT.md claims. Quote both.
```

## Scope 2: the Watch key exchange

*Files: `Sources/OpenFactorCore/Vault/WatchProvisioning.swift`, `WatchProvisioningFlow.swift`,
`VaultKeyStore.swift`, `Vault.swift`; `OpenFactor/Vault/WatchKeyProvider.swift`;
`OpenFactor/OpenFactorApp.swift`, which is where the approval alert is wired and therefore where
the question "can approval happen without a human tap" is actually answered;
`OpenFactorWatch Watch App/WatchVaultModel.swift`, `WatchVaultGateView.swift`,
`OpenFactorWatchApp.swift`; `Tests/OpenFactorCoreTests/WatchProvisioningTests.swift` and
`WatchProvisioningFlowTests.swift`; the Watch sections of `docs/VAULT.md` and `SECURITY.md`.*

*Open anything these reference. The key this exchange delivers is installed by `VaultKeyStore`
and read by the rest of the vault, and a question about what the watch ends up holding cannot be
answered without following it there.*

```
SCOPE: handing a symmetric vault key from an iPhone to a paired Apple Watch, over
WatchConnectivity. Two interactive messages:

  watch -> phone:  "OFW1" || nonce(16) || w_pub(65)                 = 85 bytes
  phone -> watch:  "OFW1" || nonce(16) || p_pub(65) || sealed(60)   = 145 bytes

  transcript = "OFW1" || nonce || w_pub || p_pub                    = 150 bytes
  kek        = HKDF-SHA256(ECDH(P-256), salt: empty,
                           info: "openfactor.vault.watch.v1" || transcript)
  sealed     = AES-GCM(vault key) under kek, with transcript as additional data

DECIDED AND NOT UNDER REVIEW: there is deliberately no short authentication string for the
person to compare between the two screens. An attempt at one was found impossible in this shape,
because the watch cannot derive such a string until the message that already carries the key. A
single confirmation tap on the phone replaces it, which means WatchConnectivity's routing
exclusivity is load bearing and is not a guarantee Apple documents. Assume that trade. Everything
downstream of it is fair game.

Attack:

1. The cryptography as written. Is the transcript binding complete, or can an attacker vary
   something in either message without changing the derived key? Is the nonce checked before
   anything is derived? Can a response from one exchange be replayed into another? Is the HKDF
   info construction unambiguous? Can the AES-GCM nonce repeat under the same derived key?

2. Parsing bytes the other device sent. Exact length enforcement, slice arithmetic, public key
   validation, and whether any malformed input can trap or crash. A message that crashes the
   phone is a real defect.

3. The state machine across the phone and the watch. Can the phone seal the key to a public key
   it never showed its owner? Can a second request substitute a key for the one just approved?
   Can approval happen without a human tap? Can the watch install a key from a message it has
   not fully verified, or from an attempt it abandoned?

4. What the tests do not cover. Name specific missing negative tests that would catch a real
   regression.
```

## Scope 3: everything that parses bytes somebody else wrote

*Files: `Sources/OpenFactorCore/Backup/` (all seven), `Sources/OpenFactorCore/Import/` (all six),
`OTPAuthURI.swift`, `OTPAuthURISerialization.swift`, `OTPAuthURIError.swift`, `Base32.swift`,
`Base32Error.swift`, `AccountLabel.swift`, `OTPAccount.swift`, `AccountMetadata.swift`,
`OTPGenerator.swift`, `SecretStore.swift`; `OpenFactor/Import/ImportViewModel.swift` and
`OpenFactor/Export/ExportViewModel.swift`, which hold the size bounds, the routing between
parsers, and everything about what an import does to accounts that already exist; and
`docs/BACKUP_FORMAT.md`.*

*Open anything these reference. Question 4 asks what an importer can do to existing data, which
cannot be answered from a parser alone: it needs the store the import writes through.*

```
SCOPE: hostile input. Every byte here came from a file, a QR code, a URL, or another app, and
none of it is trusted. This is the largest attack surface in the project.

The parsers are: an encrypted backup format defined in docs/BACKUP_FORMAT.md, a Google
Authenticator transfer payload (protobuf), an Aegis export, a labelled-text importer, a rich-text
reader, and an otpauth:// URI parser.

Attack:

1. Memory and control flow. Can any input cause a crash, a trap, an unbounded allocation, or a
   loop that does not terminate? Slice arithmetic, integer conversion, length prefixes that
   exceed the buffer, and deeply nested or repeated protobuf fields are the obvious places.

2. The backup format's cryptography. Are the PBKDF2 parameters, the salt, the IV or nonce
   handling, and the authentication defensible? Is the ciphertext authenticated before anything
   derived from it is used? Can a modified archive produce a partially applied import?

3. Confusion between formats. The app decides which parser to use from the bytes. Can input be
   crafted that is valid for two, or that is routed to the wrong one, and does anything follow
   from that?

4. What an importer can do to existing data. Can a hostile file overwrite, duplicate, or destroy
   accounts already stored? Is an import atomic, and if it fails halfway, what remains?

5. Do the bounds actually bound? Sizes are capped in several places. Find one that is checked
   after the expensive operation rather than before, or one that can be bypassed by a different
   entry point.

6. Anywhere the code does not do what docs/BACKUP_FORMAT.md claims, in a way that would break
   an independent implementation written only from that document.
```

## Scope 4: the app's boundaries

*Files: `OpenFactorShare/ShareViewController.swift` and `OpenFactorShare/OpenFactorShare.entitlements`,
since the extension's security claim is what it cannot reach;
`Sources/OpenFactorCore/Inbox/SharedInbox.swift`; `OpenFactor/Import/InboxOpener.swift`;
`OpenFactor/Lock/` (all four); `OpenFactor/CodeClipboard.swift`;
`OpenFactor/Design/ScreenCapture.swift`; `OpenFactor/OpenFactorApp.swift`, where the lock, the
cover, the arrival and the capture flag are wired together and where their ordering lives;
`OpenFactor/AccountListView.swift` and `OpenFactor/Scanning/AddAccountSession.swift`, which hold
the arrival rule and the state that survives a lock; `OpenFactor/Vault/VaultGateModel.swift`,
which sits between the lock and the list; `OpenFactorTests/AppLockPresentationTests.swift` and
`AppLockEngineTests.swift`; `docs/APP_LOCK.md`, which is the normative design for the lock and
states what it does not cover; and `SECURITY.md`.*

*Open anything these reference.*

```
SCOPE: everywhere this app touches the rest of the system. A share extension writing to an app
group container, URL schemes any app on the device can send, the lock that stands in front of the
interface, the clipboard, and the screen itself.

Attack:

1. The shared inbox. A share extension writes an image there and the app takes it. Can an item
   outlive what it should? Can two processes race? What does an attacker with access to that
   container learn, and what does the naming reveal? Is deletion guaranteed on every path,
   including failure and cancellation?

2. URL schemes. The app accepts otpauth:// and otpauth-migration:// from any app on the device.
   What can be done with that beyond the obvious, and is the bound on payload size enforced
   before anything expensive?

3. App Lock. It is a gate in front of the interface, not encryption, and it is not claimed to
   stop somebody who can run code as this app. Within that: can any sequence of scene events
   leave the interface visible when it should be locked, or leave the app switcher snapshot
   showing content? The decisions are in AppLockPresentation, which is a pure value type, and
   docs/APP_LOCK.md is normative for them. That document also records one limitation already
   measured and accepted, a second iOS snapshot cache the cover cannot reach; do not spend the
   pass rediscovering it, but do say if it is described wrongly.

4. The clipboard. Codes are allowed to travel between the owner's devices; passphrases are
   copied device-local. Both carry an expiry. Is that distinction actually enforced at every call
   site, and can either kind end up on the wrong path?

5. Screen capture. Codes are masked and passphrases withheld while iOS reports the screen is
   captured. Can that state be wrong, missed, or arrive too late to matter?

6. Anywhere SECURITY.md claims something these files do not do. Claims in that document carry a
   basis label: measured, tested, or reasoned. The reasoned ones are the ones nothing verifies,
   and are the best place to look.
```

## Round two

After round one's findings are triaged and fixed, the same engine runs the same scope again in a
**fresh** conversation, with this appended to the preamble.

```
This code was reviewed previously and changed as a result. Below is what changed and why.

Your job is not to re-review everything from scratch, though you may. It is to answer three
questions:

1. Does each change actually address the finding it claims to? A fix that moves a check without
   changing what is checked, or that handles the reported case while leaving the class open, is a
   finding.

2. Did any change introduce something new? Fixes made under time pressure are a common source of
   defects, and a fix to a state machine is a common source of a different race.

3. Is anything now claimed in a comment or document that the code does not do? Changes tend to
   leave documentation behind.

Be as willing to say "this fix is incomplete" as you were to report the original. Accepting a fix
because it is a plausible response to your own finding is the specific failure this round exists
to catch.

WHAT CHANGED:
[per-finding: the finding, what was changed, and the commit]
```

## Round three, and when to stop

Round two of scope 2 changed eight things, so the fixes for those eight have not been reviewed by
anybody. A round runs again whenever the previous round's fixes were substantial enough that
shipping them unreviewed would be the same bet the gate exists to refuse.

The prompt is round two's, with three differences: the account of what changed is cumulative, the
engine is told what the previous round concluded so it can disagree with it, and it is asked
explicitly whether the code is converging or merely churning.

**An engine that missed the previous round is told so and given both accounts**, since for it this
is a first look at everything since the original commit rather than a second look at a fix.

```
This code has now been reviewed twice and changed after each round. Below is what changed, and
what the last round concluded.

Your job is to answer four questions:

1. Does each change actually address the finding it claims to? A fix that moves a check without
   changing what is checked, or that handles the reported case while leaving the class open, is a
   finding.

2. Did any change introduce something new? These changes were made to a state machine and a
   file-writing path that have now been modified on three separate occasions. Each previous round
   found that the last round's fixes had introduced defects of their own.

3. Is anything now claimed in a comment or document that the code does not do?

4. Is this converging? Say plainly whether the changes are reducing the defect surface or moving
   it around. If the same area has been rewritten three times and is still wrong, that is the
   most useful thing you can tell us, and it will not be argued with.

Where a previous reviewer's conclusion is recorded below, you are not bound by it. Two reviewers
cleared a construction last round and it was removed anyway on the maintainer's own reasoning;
that reasoning is written down and may be wrong. Saying so is in scope.

Be as willing to say "this fix is incomplete" as you were to report the original. Accepting a fix
because it is a plausible response to a finding is the specific failure this round exists to
catch.

WHAT CHANGED:
[cumulative: each finding, what was changed, which round it came from, and the commit]
```

## The closing opinion

Asked once per engine, after round two, **in a fresh conversation**, pointing the engine at its
own published passes rather than continuing one of them.

Continuing a pass was the first plan and it was wrong. An engine's last conversation holds one
scope out of four, so its opinion would rest on a quarter of what it looked at, and which quarter
would depend on the order the scopes happened to be run in. Reading its own recorded passes gives
it everything it found, and has the property a published opinion ought to have: anybody can
reproduce it from this repository, rather than taking on trust a conversation only one person
saw.

```
In docs/audits/ of this repository are the passes you wrote while reviewing this app, across four
scopes and two rounds. Read your own passes, and the triage notes recorded beneath them, which
say which of your findings were accepted, which were rejected, and why.

Then write a short opinion of ten to fifteen sentences, for somebody deciding whether to trust
this app with their two-factor codes.

Write it for a security-conscious friend rather than for the developer. Say what you would warn
them about, and what you would not trust this app with. If there is something you could not
assess from what you were shown, say that, and say why it matters. If any of your findings were
rejected and you still think you were right, say that too.

Do not summarise the project's own claims back to me; assume the reader can read the README. I am
publishing this whole, including anything unflattering, so write what you actually think rather
than what would be encouraging.
```

**A session is worth keeping only until its pass has been triaged**, in case a finding needs one
clarifying question put to the engine that wrote it. After that the conversation is disposable:
round two starts fresh, and so does this.

**A bland opinion is a fact about the method worth publishing, not a reason to ask again.**
Nothing here is re-asked until it improves, and nothing is trimmed to read better.
