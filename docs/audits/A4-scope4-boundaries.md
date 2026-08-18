# A4, scope 4: the app's boundaries

Gate A4 round one, the scope covering the share extension, the shared inbox, URL schemes, App
Lock, the clipboard, and screen capture. The prompt is `docs/audits/A4-prompts.md`, preamble plus
Scope 4, unchanged.

**Commit under review: `74fe841`.** No source has changed since; only `docs/audits/` has.

**This scope's file list was the most enlarged after scope 1's lesson**, gaining `docs/APP_LOCK.md`,
the share extension's entitlements, and the file that wires the lock, the cover, the arrival and
the capture flag together. Whether that helped is visible in what came back.

**One edit is made to every pass published here.** Absolute paths from the reviewing machine are
rewritten as repository-relative. Nothing else is trimmed, softened, or reordered.

| Engine | Status |
| --- | --- |
| ChatGPT 5.6 Sol | Returned, below. Triaged |
| Fable 5 | Returned, below. Triaged |
| Grok 4.6 | Returned, below. Triaged |

---

## ChatGPT 5.6 Sol

*Read-only pass over commit `74fe841`. Reproduced as returned.*

> ### High — App Lock and the snapshot cover protect only one window scene
>
> `OpenFactor/Lock/PrivacyShield.swift:31`, `apply`, `showLock`, `setCovered`, `foregroundScene`;
> `OpenFactor/OpenFactorApp.swift:74`.
>
> The iPad target supports multiple scenes, but `PrivacyShield` has one process-global `cover` and
> one process-global `lock`. Both are attached to `UIApplication.shared.connectedScenes.first`,
> which is neither necessarily the scene generating the event nor necessarily foregrounded.
>
> Concrete sequence:
>
> 1. Open windows A and B on iPad.
> 2. A resigns active. The cover is created on whichever scene happens to be first.
> 3. B later resigns active. Because `cover` already exists, `setCovered(true)` merely unhides that
>    same window in its original scene.
> 4. B has no cover, so its app-switcher snapshot can contain account names and live codes.
> 5. Warm App Lock has the same defect: its sole lock window can cover A while B remains visibly
>    unlocked.
>
> This contradicts `docs/APP_LOCK.md` R1/R2 and `SECURITY.md`'s claim that the app-switcher card
> never contains a code. **The pure presentation tests cannot catch it because they model one phase
> and no `UIWindowScene` identity.**
>
> Smallest fix: disable multiple-scene support. If multiple windows are intentional, maintain a
> lock/cover pair keyed by `UISceneSession.persistentIdentifier`, feed scene-specific lifecycle
> events, and discard windows when their scene disconnects.
>
> ### Medium — Inbox leftovers are not swept at launch when the app is locked
>
> `OpenFactor/OpenFactorApp.swift:152` (`collectWhatArrived`), `OpenFactor/Import/InboxOpener.swift:43`
> (`collect`), `Sources/OpenFactorCore/Inbox/SharedInbox.swift:29`.
>
> `SharedInbox` says the directory is swept "at every launch," and `SECURITY.md` says leftovers are
> swept when OpenFactor launches. The only sweep is the `defer` inside `InboxOpener.collect`, but
> `collectWhatArrived` refuses to call it until the scene is active, App Lock is open, the vault is
> open, and no arrival is pending.
>
> Concrete sequence: the extension writes a transfer image containing all OTP secrets; OpenFactor
> launches with App Lock enabled; `collectWhatArrived` returns because `lock.isLocked` is true; the
> user cancels Face ID and closes the app. Repeating the launch does not sweep the file; even after
> ten minutes, freshness is never evaluated without a successful unlock and open vault.
>
> While the device itself is unlocked, complete file protection does not stop a sibling app
> authorized for the app group from reading this file. **The accepted "brief temporary exposure"
> can therefore become indefinite.**
>
> Smallest fix: separate collection from presentation. Take the fresh item into the already
> app-owned `arrival` state, and sweep the remainder, during launch even while locked; gate only
> the sheet's presentation on App Lock and vault state.
>
> ### Medium — External files are fully loaded before the 8 MB limit is checked
>
> [As recorded in scope 3.] The check prevents expensive parsing, but does not bound the more
> fundamental allocation and I/O. Smallest fix: open the file and read at most `8 MiB + 1` bytes,
> rejecting it when the extra byte exists. A preliminary file-size attribute can be an
> optimization, but the actual read must remain bounded because providers and files can change
> between the check and read.
>
> ### Medium — The inbox consumer does not enforce the extension's size limit
>
> `Sources/OpenFactorCore/Inbox/SharedInbox.swift:172` (`take`),
> `OpenFactorShare/ShareViewController.swift:64`.
>
> The 8 MB limit exists only in the share extension. The app-group container is explicitly not
> trusted as a boundary, yet `take` loads any UUID-named file in full. An authorized sibling app
> can write a very large body with a current or future modification date; `pending()` accepts it as
> newest, and `take()` attempts to materialize it before any image or QR validation. Resource
> exhaustion can kill the app; if termination prevents the deferred cleanup, the poison item
> remains for the next attempt.
>
> Smallest fix: enforce the 8 MB limit inside `take` with a bounded read and delete oversized
> entries. The producer-side limit should remain defense in depth.
>
> ### Low — The extension's size check occurs after the attachment is materialized
>
> `OpenFactorShare/ShareViewController.swift:59` (`run`), `:100` (`firstImage`).
> `loadDataRepresentation` returns a complete `Data` value before `run` checks `data.count`. A
> provider backed by a very large image can therefore exhaust the extension's memory before the
> advertised 8 MB bound runs. **The comment claiming this prevents the extension from deciding "how
> much memory to spend" is false.**
>
> ### Low — Any incoming URL can discard an already pending arrival
>
> `OpenFactor/OpenFactorApp.swift:170` (`onOpenURL`), `:212` (`collectWhatArrived`).
>
> Inbox collection guards `arrival == nil`; direct URLs do not. Any app can invoke the registered
> scheme and unconditionally replace `arrival`.
>
> Concrete sequence: a shared transfer image is destructively taken from the app-group inbox into
> `arrival`; before it is reviewed, another app opens `otpauth://totp/...`; `onOpenURL` replaces
> `arrival`; the image bytes are released and their original inbox file is already gone.
>
> Nothing is silently saved, but a hostile URL can destroy a pending import and contradicts the
> normative rule that an arrival presents only when "nothing else is pending."
>
> ### Boundaries that held
>
> * The share extension entitlement contains the app group but not the app's shared Keychain access
>   group, preventing it from reading or modifying stored OpenFactor accounts.
> * URL-delivered codes are scheme-allowlisted and their UTF-8 length is checked before
>   base64/protobuf or `otpauth` parsing.
> * Clipboard call sites preserve the intended distinction: codes use a validity-based expiry and
>   may travel; both passphrase call sites use the device-local path with a two-minute expiry.
> * In the single-scene state model, event ordering around Face ID is handled defensively: a
>   backgrounded late unlock shows the cover, repeated success is inert, and the lock window is
>   shown before the cover is hidden.

### Triage

**The high-severity finding is confirmed, and it is the first finding in this gate that exposes a
secret rather than losing one.**

The shipped `Info.plist` was read rather than the project file:

```
UIApplicationSceneManifest => { UIApplicationSupportsMultipleScenes => true }
UIDeviceFamily => [1, 2]
```

Multiple scenes are enabled, on iPhone and iPad, and `PrivacyShield` holds exactly one `cover` and
one `lock`, each created once against `connectedScenes.first` and thereafter only hidden and
unhidden. A second iPad window therefore has no cover in the app switcher and no lock over it.

That breaks two claims this project makes in its own words. `SECURITY.md`: "The app switcher card
never contains a code. Measured, repeatedly." And `docs/APP_LOCK.md` R2: "The app switcher
photograph never contains a code, an account name, or any interface."

**The observation about the tests is the part worth keeping.** `AppLockPresentation` was extracted
into a pure value type precisely so the lock's decisions could be tested, and that was the right
move: it caught a real leak before it shipped. But it models *when* to lock, and this defect is
about *what surface* gets locked. The tests are sound and complete for what they cover, and their
existence made the untested dimension harder to see, not easier.

**The sweep finding is confirmed.** The only call to `SharedInbox.sweep()` in the repository is the
`defer` inside `InboxOpener.collect`, and `collectWhatArrived` returns early unless the scene is
active, the lock is open, the vault is open, and no arrival is pending. So with App Lock enabled
and Face ID cancelled, a transfer image containing every secret its owner has stays in the app
group container indefinitely.

Both `SharedInbox`'s own header and `SECURITY.md` state that the directory is swept at every
launch. Neither is true. **The entire argument for the inbox being acceptable rests on the item
living for seconds**, and that argument is written in the file whose behaviour contradicts it.

**The unbounded `take` is confirmed.** `FileManager.default.contents(atPath:)` materializes the
whole file, and the only size limit in the system lives in the extension, which the threat model
explicitly does not trust as a boundary. This is the app-group-is-a-grant-not-a-boundary argument
applied where it had not been.

**Both size-check-after-load findings are confirmed**, one already recorded in scope 3 and the
extension's own now too, along with the false comment above it.

**The arrival-replacement finding is confirmed.** `onOpenURL` assigns `arrival` with no guard,
while `collectWhatArrived` will not collect unless `arrival == nil`. A hostile URL can therefore
destroy a pending transfer image whose inbox file was already deleted by the taking. It also
contradicts the arrival rule as written in `docs/APP_LOCK.md`.

**Nothing was rejected.**

### A correction to something said earlier in this gate

After scope 3, this gate's summary was that no engine had found a way to get a secret out, and
that every serious finding was about losing accounts rather than leaking them.

**That is no longer true.** The multi-scene defect puts live codes and account names in an iPad's
app switcher, which is exactly the surface the cover exists to protect and exactly what two
documents promise it does. It is narrower than it sounds, needing a second window on an iPad, and
it is still not an attacker reading storage. But it is a confidentiality failure, and the earlier
summary should not stand unqualified.

---

## Fable 5

*Read-only pass over commit `74fe841`. Reproduced as returned, abridged in the sections
enumerating what held.*

> **F1 — Medium. The launch sweep does not exist. An inbox item can outlive everything the design
> says bounds it, and it is eligible for device backups while it sits there.**
>
> `sweep()` has exactly one caller in the entire codebase: the `defer` inside
> `InboxOpener.collect()`, which is reached only through `collectWhatArrived()` and its four
> guards. There is no unconditional sweep anywhere.
>
> Two consequences, one of them beyond the accepted sibling-app exposure:
>
> 1. **The item is included in device backups.** App group containers are backed up by local and
>    iCloud backup; `.completeFileProtection` does not exclude a file from backup, and nothing sets
>    `isExcludedFromBackup` on the inbox directory or its files. A backup taken during the window
>    carries the plaintext transfer QR into exactly the kind of persistent, cloud-reachable store
>    the extension exists to keep it out of. **An unswept inbox item in an iCloud backup is the
>    same exposure with a different folder name.**
> 2. Two published claims are false. `SharedInbox.swift:31` says the directory is "swept at every
>    launch. The sweep is what covers the case the delete cannot: the app never opened, or was
>    killed between the extension writing and the app reading." That is precisely the case it does
>    not cover. `SECURITY.md:489` repeats it.
>
> **Note the trap in the obvious fix**: an unconditional `sweep()` at launch would destroy a fresh,
> legitimately shared image before the vault gate opens, which is presumably why the sweep ended up
> folded into `collect()`. Smallest fix that avoids the trap: an **age-bounded sweep**, deleting
> only items older than `SharedInbox.freshness`, run unconditionally at every launch and every
> scene activation, before and independent of the gate. Separately, set `isExcludedFromBackup` on
> the inbox directory.
>
> **F2 — Low. The claimed app-side size bound on a shared image does not exist.** The extension's
> check carries the comment "Bounded here as well as in the app." There is no app-side bound:
> `take()` loads the entire file via `FileManager.contents` with no size check.
> `SECURITY.md:469` says "an imported file and a shared image both cap at 8MB"; for the shared
> image the cap exists only inside the extension process. An authorized sibling can write a
> UUID-named multi-gigabyte file, which the app loads wholesale and hands to the image decoder.
>
> **F3 — Low. `onOpenURL` overwrites a pending arrival**, permanently destroying a shared image
> that was already destructively taken from the inbox. [As recorded in the ChatGPT pass.]
>
> **F4 — Low. Freshness and ordering trust an attacker-writable modification date.** `pending()`
> sorts by `.modificationDate` and `collect()` judges freshness by it. A future-dated file is
> always fresh, since `timeIntervalSinceNow` is positive, and always sorts newest, so it wins
> `take()` on every collection and shadows every genuine share until something deletes it. One-line
> fix: clamp `arrived` to `min(mtime, now)`.
>
> **On App Lock: I walked the presentation core against every sequence I could construct and could
> not find a scene-event ordering that leaves the interface visible or the snapshot dirty.**
> `settling` is set only when `phase == .inactive`; every departure clears it before the cover
> decision is read; a second unlock outcome is dead on arrival; `coverVisible` excludes
> `.launching`. Every state mutation that can change an output is followed by
> `PrivacyShield.apply`. Show-before-hide is real in both directions. The double-auto-prompt
> defense is sound because an `await` of a same-main-actor method does not suspend before the
> callee's first genuine suspension point, so the second task always observes the mark. Missing
> negative tests: none against the document's own required list.
>
> **On the clipboard, the distinction is enforced structurally, which is the strong version.**
> Three call sites, one private `write`, a `localOnly` flag a caller must choose. Neither kind can
> inherit the other's rule by accident. One pedantry: for HOTP the expiry is `now + 30s`, and an
> HOTP code does not stop working then, so the comment "callers pass the moment the code itself
> stops working" is not quite true for counter accounts. The behavior is stricter than the claim,
> which is the right direction to be wrong in.
>
> **A note on where the document rotted.** The two false claims are both about the inbox lifecycle,
> which suggests the sweep behavior changed after the prose was written and the prose was not
> re-derived from the code: **the exact rot mode the document's own basis-label system warns about,
> in the one section that carries no basis label at all.**

---

## Grok 4.6

*Read-only pass over commit `74fe841`. Reproduced as returned, abridged where it repeats findings
already recorded above.*

> **Finding 1 — High. A shared transfer QR can sit in the App Group indefinitely.** [Same defect,
> reached independently.] Freshness is not a deletion deadline. It is a presentation filter inside
> a function that may never run. Four false claims, adding one the other passes did not name: the
> `OpenFactor.entitlements` comment says the item is "held for seconds", and nothing enforces that.
>
> I did not measure an iCloud or Finder backup of this file. I do record that `VaultKeyStore` sets
> `isExcludedFromBackup = true` on the vault key and this write does not. I am sure of the missing
> flag. I am not sure of inclusion.
>
> **Finding 2 — High (availability). Any app on the device can crash OpenFactor with one
> `otpauth-migration://` URL. No confirm tap. The 8 KB bound does not help.**
>
> `Int(clamping: UInt64.max)` is `Int.max`. `Batch` stores that as `index`. `handleScan` sets
> `.transferring(batch)`. The add sheet's body then builds `ImportView`, which evaluates
> `batch.position` → `Int.max + 1` → trap.
>
> **If App Lock is a warm window, `AccountListView` is still in the tree under the lock. The sheet
> is built under it. The process dies while "locked."** If the lock is cold, or the vault is not
> open, the URL is held on `arrival` and the trap waits for the first moment the list exists.
>
> Smallest fix: refuse a `batch_index` that is not in `0...Int.max-1` at the varint, or compute
> `position` with a checked add. **Do not clamp a value you later increment.**
>
> **Finding 3 — Low. Codes are masked on the account list while the screen is captured. They are
> not masked on the two other screens that draw a live code:** `ConfirmAccountView` and
> `ManualSetupView`'s preview section. `SECURITY.md` says "codes become bullets" while captured;
> that is true of the list and false of confirm-add and manual-entry preview. Someone AirPlaying a
> meeting who scans or opens an `otpauth://` URL broadcasts the live digits. **The capture flag is
> not wrong here; it is simply never read.**
>
> **One spec error that is not a code bug.** The transition table in `docs/APP_LOCK.md` says
> `didBecomeActive` sets `coldLock = false`. The code leaves `coldLock` untouched, and the tests
> require a never-unlocked cold lock to stay the root across a background and return. Implementing
> the table would recreate the orientation latch the page exists to prevent. The page says it is
> normative. **The table is the part that is wrong.**
>
> **On multiple scenes:** I cannot assess `PrivacyShield.foregroundScene` taking `.first` on a Set.
> The main target is iPhone and iPad, multiple scenes are not declared, and with one scene `.first`
> is that scene. If a second `UIWindowScene` ever exists, the lock and cover can attach to the
> wrong one. That is a maybe. I am not promoting it.
>
> **Also:** `SECURITY.md`'s claim that the extension "passes a URL carrying only an identifier" is
> false and leftover; `write`'s UUID is discarded and the app polls. Safer than the claim, but the
> claim is wrong. And the tests pin that a code lands and that an expired one does not; **they do
> not pin `localOnly`.** The distinction is in the code, not in the suite.

### Triage of the Fable 5 and Grok 4.6 passes

**The sweep finding is confirmed three times over, and Fable's backup angle is the part nobody
else had.** Verified: there is no `isExcludedFromBackup` and no `URLResourceValues` anywhere under
`Sources/OpenFactorCore/Inbox/` or `OpenFactorShare/`, while `VaultKeyStore.swift:123` sets exactly
that flag on the vault key. So a transfer QR that fails to be swept is eligible for the device
backup, and the share extension exists precisely to keep that image out of a persistent,
cloud-reachable store. The mechanism the extension was built to avoid is reproduced inside the
mechanism itself.

**Fable's proposed fix is the right one and it names the trap in the obvious fix.** An
unconditional sweep at launch would delete a share the owner is about to unlock into. An
age-bounded sweep, deleting only items past the freshness window, is safe on every path because
`collect()` refuses to present such items anyway.

**Grok's Finding 2 confirms scope 3's crash from the other side and sharpens its reachability.**
The trap is not in the parser and not in the confirm screen; it is in `ImportView.init` reading
`batch.position` while the sheet is being built. And the observation that matters: with a warm
App Lock the account list is still in the tree beneath the lock window, so **the process can die
while the app is displaying its lock screen.**

**Finding 3 confirmed, and it is a gap in the capture work written on 2026-08-18.** Only
`AccountListView`, `VaultSetupView` and `ExportView` read `isScreenCaptured`. `ConfirmAccountView`
and `ManualSetupView`'s preview both draw a live code and never read it. The environment value is
already injected at the root, so the fix is one ternary in each place. `SECURITY.md`'s "codes
become bullets" is therefore true of one screen out of three.

**The `docs/APP_LOCK.md` table error is confirmed and is the most dangerous documentation defect
found in this gate.** The table at line 133 says `didBecomeActive` sets `coldLock = false`. The
code deliberately does not, the comment above it explains why in both directions, and
`coldLockStaysColdWithoutAnUnlock` pins the behaviour. The page opens by declaring that where the
code and the page disagree, **the page is correct and the code is a defect**. Anybody who trusted
that instruction would "fix" the code to match, break a tested guarantee, and reintroduce the
orientation latch the page was written to prevent.

**`localOnly` is not pinned by any test**, which is confirmed and belongs with the two verified
holes from scope 2: the clipboard distinction that this project treats as load bearing is asserted
by code and by prose, and by nothing that runs.

**One engine was factually wrong, and it is worth recording precisely.** Grok considered the
multi-scene question, concluded "multiple scenes are not declared", and honestly filed it as a
maybe it would not promote. The shipped `Info.plist` says otherwise:
`UIApplicationSceneManifest → UIApplicationSupportsMultipleScenes => true`, with
`UIDeviceFamily => [1, 2]`. Grok reasoned from `TARGETED_DEVICE_FAMILY` in the project file;
ChatGPT reached the right answer; the artifact settles it.

**That is the closest thing to a false negative this gate has produced**, and its shape is
instructive: the engine asked exactly the right question, looked in a plausible place for the
answer, and got a wrong one. Its instinct to flag the uncertainty rather than assert either way is
what a reader should want, and it still would have left the defect in the code had it been the
only engine run.

## Scope 4 complete

| Finding | ChatGPT | Fable 5 | Grok 4.6 |
| --- | --- | --- | --- |
| Multi-scene: one cover, one lock, wrong scene | **Found** | Missed | Considered, wrongly dismissed |
| Inbox is never swept at launch | Found | Found | Found |
| Inbox items are eligible for device backup | Missed | **Found** | Noted the missing flag, unsure |
| `take()` is unbounded | Found | Found | Found |
| Migration URL crashes the app | Missed here, found in scope 3 | Missed | **Found** |
| Confirm and manual previews never mask codes | Missed | Missed | **Found** |
| `onOpenURL` destroys a pending arrival | Found | Found | Missed |
| Freshness trusts an attacker-writable mtime | Missed | **Found** | Missed |
| `APP_LOCK.md`'s transition table is wrong | Missed | Missed | **Found** |
| Extension bound applied after materialization | Found | Found | Missed |
| `localOnly` is pinned by no test | Missed | Missed | **Found** |

**One finding in eleven was reported by all three.** Five were found by exactly one engine, and
four of those five are the ones this triage rates highest after the sweep: the multi-scene defect,
the backup eligibility, the unmasked previews, and the normative table that instructs a reader to
break working code.

### Not yet acted on

**Nothing has been changed.** Round one is complete across all four scopes. Fixes begin now.
