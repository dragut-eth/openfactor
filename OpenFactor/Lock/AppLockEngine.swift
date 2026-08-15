import Foundation

/// Decides whether the app is locked. Nothing else.
///
/// This is the part of App Lock that has to be correct, so it is a value type with no
/// clock, no Keychain, no LocalAuthentication, and no UIKit: every decision is arithmetic
/// on a date passed in, which is the same rule `TOTP` follows and for the same reason. The
/// tests can walk it through any sequence of launches, backgrounds, and returns without
/// touching a simulator, and the pieces that cannot be unit tested, Face ID and the shield
/// window, stay too thin to hide a bug.
///
/// **What the lock is, honestly.** A gate in front of the interface, not encryption. The
/// secrets are protected by the device Keychain whether the lock is on or off, and the
/// scenario the lock defends is exactly one: someone holding the phone while it is
/// unlocked. `SECURITY.md` words this carefully and the code should not imply more.
struct AppLockEngine: Equatable {

    /// Whether the interface is currently behind the lock.
    private(set) var isLocked: Bool

    /// When the app last left the foreground, if it has not yet returned.
    private var backgroundedAt: Date?

    /// A cold launch starts locked when the lock is enabled, because the time spent
    /// terminated is time the phone was out of the user's hands for all this engine knows.
    init(enabled: Bool) {
        isLocked = enabled
    }

    /// The app left the foreground. The moment is recorded; the decision happens on
    /// return, because the grace period cannot be judged until its end.
    ///
    /// The earliest moment wins if the system reports background more than once, since the
    /// user has been away since the first one.
    mutating func appDidBackground(at date: Date) {
        if backgroundedAt == nil {
            backgroundedAt = date
        }
    }

    /// The app is returning. Locks when the lock is enabled and the time away reached the
    /// grace period.
    ///
    /// A negative elapsed time means the clock moved backwards while the app was away.
    /// That is indistinguishable from tampering, so it locks rather than reasons about it:
    /// the cost of being wrong is one unlock prompt.
    mutating func appWillForeground(at date: Date, enabled: Bool, gracePeriod: TimeInterval) {
        defer { backgroundedAt = nil }

        guard enabled, let backgroundedAt else { return }

        let elapsed = date.timeIntervalSince(backgroundedAt)
        if elapsed < 0 || elapsed >= gracePeriod {
            isLocked = true
        }
    }

    /// The person proved they are the owner. Only `AppLockController` calls this, and only
    /// after `LocalAuthentication` succeeded.
    mutating func unlock() {
        isLocked = false
    }
}
