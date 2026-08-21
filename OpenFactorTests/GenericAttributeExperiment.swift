import Foundation
import Security
import Testing

@testable import OpenFactorCore

/// Whether `kSecAttrGeneric` can carry a compare-and-swap token on a generic password.
///
/// A verification round claimed that the last window in `WrappedKeyStore.save` cannot be closed by
/// any shape of the code, because `SecItemUpdate` offers no compare-and-swap: a write cannot be
/// conditioned on the value that was read. That is a claim about a platform API, so it is
/// measurable rather than arguable.
///
/// The primary key of a generic password is the service, the account, the access group and the
/// sync flag. `kSecAttrGeneric` is settable and is not part of it. If it can be *matched* in an
/// update query, and *changed* by the same update, then it is a version token and the update is a
/// compare-and-swap.
@Suite("Experiment: a compare and swap token")
struct GenericAttributeExperiment {

    private func service() -> String { "app.openfactor.tests.cas.\(UUID().uuidString)" }

    private func base(_ service: String, synchronizable: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "wrapped",
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: synchronizable,
        ]
    }

    private func cleanUp(_ service: String) {
        var query = base(service, synchronizable: false)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }

    private func value(of service: String, synchronizable: Bool) -> Data? {
        var query = base(service, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    /// The whole property, in one pass: a token can be stored, matched, replaced by the same
    /// update, and a write carrying a stale token lands nowhere.
    private func compareAndSwapHolds(synchronizable: Bool) {
        let service = service()
        defer { cleanUp(service) }

        let tokenA = Data("token-A".utf8)
        let tokenB = Data("token-B".utf8)

        var attributes = base(service, synchronizable: synchronizable)
        attributes[kSecAttrAccessible as String] =
            SecretAccessibility.forSync(synchronizable).attribute
        attributes[kSecAttrGeneric as String] = tokenA
        attributes[kSecValueData as String] = Data("first".utf8)
        #expect(SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess)

        var read = base(service, synchronizable: synchronizable)
        read[kSecReturnAttributes as String] = true
        var readBack: CFTypeRef?
        _ = SecItemCopyMatching(read as CFDictionary, &readBack)
        #expect(
            (readBack as? [String: Any])?[kSecAttrGeneric as String] as? Data == tokenA,
            "the token is stored and can be read back")

        // Match on the token this reader saw, and move it on in the same write.
        var swap = base(service, synchronizable: synchronizable)
        swap[kSecAttrGeneric as String] = tokenA
        let changes: [String: Any] = [
            kSecValueData as String: Data("second".utf8),
            kSecAttrGeneric as String: tokenB,
        ]
        #expect(
            SecItemUpdate(swap as CFDictionary, changes as CFDictionary) == errSecSuccess,
            "an update can both match on the token and replace it")
        #expect(value(of: service, synchronizable: synchronizable) == Data("second".utf8))

        // And the case the idea rests on: somebody else moved the token on, so this reader's
        // write must not land.
        var stale = base(service, synchronizable: synchronizable)
        stale[kSecAttrGeneric as String] = tokenA
        let staleChanges: [String: Any] = [kSecValueData as String: Data("third".utf8)]
        #expect(
            SecItemUpdate(stale as CFDictionary, staleChanges as CFDictionary)
                == errSecItemNotFound,
            "a write carrying a stale token matches nothing")
        #expect(
            value(of: service, synchronizable: synchronizable) == Data("second".utf8),
            "and changes nothing")
    }

    @Test("A device-only item can carry a compare and swap token")
    func deviceOnly() { compareAndSwapHolds(synchronizable: false) }

    @Test("A synchronizable item can carry one too")
    func synchronizable() { compareAndSwapHolds(synchronizable: true) }
}
