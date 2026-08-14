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
/// So the tests that need a real Keychain are written, and skipped where they cannot run.
/// They run against a host application target, which arrives in PR 5. Until then the
/// protection class on stored secrets is **unverified by test**, and that is recorded in
/// `handoff.md` and in the checklist for gate A1 rather than left to be discovered.
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
            KeychainSecretStore(service: "app.openfactor.tests.\(UUID().uuidString)")
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
