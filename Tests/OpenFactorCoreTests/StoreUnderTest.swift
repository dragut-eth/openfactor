import Foundation
import Security

@testable import OpenFactorCore

/// The stores the behaviour suite runs against.
///
/// ## Why this is only the in memory one here
///
/// Reaching the data protection Keychain requires an entitlement, entitlements come from code
/// signing, and a `swift test` bundle is not signed, so `SecItemAdd` returns
/// `errSecMissingEntitlement`. The legacy file based Keychain on macOS does accept writes from an
/// unsigned process and is not a substitute: it ignores `kSecAttrAccessible` and does not return
/// it, so asserting a protection class against it would assert nothing while looking thorough,
/// which is worse than not testing it.
///
/// **This used to decide at run time, and that is what made it dangerous.** It probed the Keychain
/// and returned both cases where one was reachable and only the in memory one where it was not. On
/// the machine that runs this suite it was always the second, so the Keychain half of every case
/// below silently did not run while the suite reported success. Two whole suites sat behind the
/// same probe and executed in no job at all; they live in the hosted target now, where a simulator
/// always has a real Keychain.
///
/// **What is left is stated rather than probed.** This list is the in memory store, always, and the
/// Keychain half of `SecretStoreTests` is not covered anywhere. That is recorded as the remaining
/// half of S1-37 rather than hidden behind a condition that reads as thoroughness.
enum StoreUnderTest: String, CaseIterable, Sendable, CustomStringConvertible {
    case inMemory

    static var testable: [StoreUnderTest] { allCases }

    var description: String { rawValue }

    /// A fresh, empty store.
    func make() -> any SecretStore {
        switch self {
        case .inMemory:
            InMemorySecretStore()
        }
    }
}

extension SecretStore {
    /// Removes everything this store wrote. A no op for the in memory store, which goes away on
    /// its own.
    func cleanUp() {
        guard let keychain = self as? KeychainSecretStore else { return }

        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychain.service,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ] as CFDictionary
        )
    }
}
