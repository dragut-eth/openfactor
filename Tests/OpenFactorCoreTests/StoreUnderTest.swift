import Foundation
import Security

@testable import OpenFactorCore

/// Whether this process can use the data protection Keychain at all.
///
/// It usually cannot. Reaching the modern Keychain requires an entitlement, entitlements
/// come from code signing, and a `swift test` bundle is not signed, so `SecItemAdd`
/// returns `errSecMissingEntitlement`, which is -34018.
///
/// The legacy file based Keychain on macOS does accept writes from an unsigned process,
/// and is not a substitute: it ignores `kSecAttrAccessible` and does not return it, so
/// asserting the protection class against it would assert nothing while looking thorough.
/// That is worse than not testing it, because it reads as a passing test.
///
/// **This file compiles into two targets, and the probe is what tells them apart.** The package
/// suite runs unsigned and cannot reach the Keychain; the hosted suite runs inside a host
/// application in a simulator and always can. So the same source selects the in memory store in
/// one and both stores in the other, which is the behaviour that is wanted.
///
/// **It was briefly removed on a mistaken reading and that cost real coverage.** A finding claimed
/// two suites executed nowhere, and the check behind it looked at `swift test` skipping them and
/// at the CI job's `-only-testing` flag, and never checked target membership. The Xcode project
/// synchronises this directory into the hosted test target as well, so those suites had been
/// running there all along. Removing the probe here narrowed `testable` to the in memory store and
/// silently dropped fifteen Keychain executions from the hosted run. Measured, not reasoned:
/// thirty case executions before, fifteen after.
///
/// The lesson is the one this project keeps relearning in a new costume: a claim about a build
/// system is checkable, and reasoning about one is not the same as running it.
enum KeychainAvailability {

    static let isUsable: Bool = {
        let service = "app.openfactor.availability.probe"
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: UUID().uuidString,
            kSecValueData as String: Data("probe".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)

        if status == errSecSuccess {
            SecItemDelete(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecUseDataProtectionKeychain as String: true,
                ] as CFDictionary
            )
            return true
        }

        return false
    }()
}

/// The stores the behaviour suite runs against.
enum StoreUnderTest: String, CaseIterable, Sendable, CustomStringConvertible {
    case inMemory
    case keychain

    /// Both where the Keychain is reachable, otherwise only the in memory one.
    static var testable: [StoreUnderTest] {
        KeychainAvailability.isUsable ? allCases : [.inMemory]
    }

    var description: String { rawValue }

    /// A fresh, empty store. The Keychain one gets its own service name so that a test
    /// can never see another test's accounts, or the real app's.
    func make() -> any SecretStore {
        switch self {
        case .inMemory:
            InMemorySecretStore()
        case .keychain:
            // Unlocked, because a store will not create a vault by itself: the design requires
            // a passphrase to have been shown first, so `.vaultLocked` is the correct answer to
            // a fresh store and the wrong starting point for a suite about something else.
            (try? UnlockedVault.store())
                ?? KeychainSecretStore(service: "app.openfactor.tests.\(UUID().uuidString)")
        }
    }
}

extension SecretStore {
    /// Removes everything this store wrote. A no op for the in memory store, which goes
    /// away on its own.
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
