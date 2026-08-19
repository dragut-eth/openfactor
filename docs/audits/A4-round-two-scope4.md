# A4 round two, scope 4: what changed and why

Round one found eleven items at the app's boundaries. All eleven are fixed. **Review commit
`8471c33`.** Round one read `74fe841`.

## The eleven

**1. App Lock and the snapshot cover protected one window scene.** `UIApplicationSupportsMultipleScenes`
was `true` by Xcode's default and is now declared `false`, which is what the lock always assumed.

**2. The inbox was never swept at launch.** All three engines found it. The only sweep sat inside
the collection path, which does nothing until the scene is active, the lock is open, the vault is
open, and no arrival is pending, so an image shared to a locked phone that was never unlocked again
stayed in a shared container. Both `SharedInbox` and `SECURITY.md` said otherwise. A launch sweep
now runs under none of those conditions and removes what is older than five minutes, which cannot
eat the item somebody just shared.

**3. Inbox items were eligible for device backup.** An item lives for seconds, and a backup taken
in those seconds carries a QR image of every secret into iCloud, where nothing sweeps it. The
directory is excluded before anything is written into it.

**4. `take()` was unbounded.** The size is asked of the file system first now, and an oversized
item is removed rather than left for the next attempt.

**5. The migration URL crash**, shared with scope 3.

**6. Confirm and manual previews never masked codes** while the screen was being recorded.

**7. `onOpenURL` destroyed a pending arrival.** A link opened while a shared image waited to be
confirmed threw that image away with no sign anything had happened.

**8. Freshness trusted an attacker-writable mtime**, so an item could claim it arrived in the
future and sort ahead of everything.

**9. `APP_LOCK.md`'s transition table was wrong**, which is worse than a comment being wrong: it is
normative, and a reader following it would have broken working code.

**10. The extension's bound was applied after materialization.** It asks for a file representation
and reads the size off disk now.

**11. `localOnly` was pinned by no test.** One boolean decides whether a backup passphrase may
leave the device, and making the two call sites consistent is the tidy-looking change that would
hand somebody's recovery credential to Universal Clipboard.

## Where to look hardest

**The launch sweep is time based, which the old one was not.** Five minutes is a judgment. Too
short eats a share somebody is slow to confirm; too long is the exposure this finding was about.

**It also runs unconditionally at launch**, including while the app is locked, which is the point.
Check that it cannot touch anything else in the container.

**The mtime clamp only stops an item claiming the future.** An item claiming to be older than it is
sweeps sooner, which is the safe direction, and is worth confirming rather than assuming.

**The first-arrival-wins rule is new** and silently drops the second. That is deliberate and it is
the kind of deliberate that hides a lost link.
