import Foundation

/// The two gates in front of erasing every account, as a value a test can reach.
///
/// **They used to live entirely in a SwiftUI view**, which is the shape this project keeps
/// extracting: `WatchProvisioningFlow`, `AppLockPresentation` and `ProvisioningDesk` were all
/// moved out of app targets for the same reason. A reviewer scoring `docs/MASVS.md` named this
/// one specifically: MASVS-AUTH-3 claims sensitive operations carry additional authentication,
/// and the test it cited proved that deletion deletes, not that anything guarded it.
///
/// **The ordering is the security property, not the two checks on their own.** Authentication
/// happens before a single record is read, because an unlocked phone in the wrong hands is
/// exactly what this defends against and App Lock may be off. A failed identity check must leave
/// every account where it was.
///
/// **The typed word is checked here as well as by the button.** The view disables its button
/// until the word matches, which means the confirmation was enforced by a view and by nothing
/// else. A rule enforced only by the thing that displays it is a rule with no test behind it.
public enum EraseGate {

    /// The word that has to be typed. **Deliberately not "delete"**, which muscle memory
    /// supplies without reading, and deliberately not localised into something ambiguous.
    public static let confirmation = "ERASE"

    /// Whether what somebody typed is the confirmation.
    ///
    /// Trimmed and upper-cased, because a keyboard that capitalises and a person who taps space
    /// are not trying to cancel.
    public static func isConfirmed(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == confirmation
    }

    /// What happened, in the terms the screen has to report.
    public enum Outcome: Equatable, Sendable {
        /// Every account removed, and how many.
        case erased(Int)
        /// The word was not typed. Nothing was read and nothing was authenticated.
        case notConfirmed
        /// Identity was not confirmed. Nothing was removed.
        case notAuthenticated
        /// The store refused part way. Some accounts may already be gone.
        case failed(SecretStoreError)
    }

    /// Runs both gates, then erases.
    ///
    /// **`authenticate` is a parameter rather than a call**, so a test can decide what identity
    /// confirmation returns. That is the only way the refusal path is reachable at all: nothing
    /// in a test bundle can make a real Face ID prompt fail.
    ///
    /// **Unreadable records are erased too.** Leaving them would be the worst outcome available
    /// here: an erase that reports success and leaves secrets on the device.
    public static func erase(
        typed: String,
        from store: any SecretStore,
        authenticate: () async -> Bool
    ) async -> Outcome {
        guard isConfirmed(typed) else { return .notConfirmed }
        guard await authenticate() else { return .notAuthenticated }

        do {
            let records = try store.records()
            let ids = records.readable.map(\.id) + records.unreadable
            for id in ids {
                try store.delete(id: id)
            }
            return .erased(ids.count)
        } catch {
            return .failed(error)
        }
    }
}
