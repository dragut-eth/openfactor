import Foundation
import OpenFactorCore
import SwiftUI

/// Producing an encrypted archive: the passphrase, the file, and the file's short life.
///
/// **This is the most dangerous thing the app does on purpose.** Every secret, in one place,
/// outside the Keychain. Nothing the rest of the app relies on, the device passcode, the
/// Secure Enclave, the protection class, applies once bytes are in a file somebody can email
/// to themselves. The format was audited three times before it existed for that reason, and
/// the flow here is shaped by the same asymmetry: the app generates the passphrase, the
/// person has to say they have stored it, and the file is deleted the moment it is no longer
/// needed.
@Observable
@MainActor
final class ExportViewModel {

    enum Stage: Equatable {
        /// What the file is, before anything is generated.
        case explaining
        /// The passphrase exists and has not been used yet.
        case choosing
        /// The archive is written and waiting to be shared.
        case ready(URL)
        case failed(String)
    }

    /// Which rule produces the key. Generated is the default and stays the default.
    enum PassphraseChoice: Equatable {
        case generated
        case own
    }

    private(set) var stage: Stage = .explaining

    /// The generated passphrase, created once when the screen opens so that it is stable
    /// across redraws. A passphrase that changed while being written down would be the most
    /// avoidable data loss this app could arrange.
    private(set) var generated: String = ""

    var choice: PassphraseChoice = .generated
    var ownPassphrase: String = ""

    /// Ticked by the person, and the gate on producing the file. Deliberately not a toggle
    /// that defaults on: the format says never write an archive whose passphrase the user
    /// has not been shown and confirmed they have stored.
    var hasSavedPassphrase = false

    private(set) var accountCount = 0

    private let store: any SecretStore

    init(store: any SecretStore) {
        self.store = store
        regenerate()
    }

    func regenerate() {
        generated = BackupPassphrase.generate() ?? ""
        if generated.isEmpty {
            stage = .failed(
                """
                OpenFactor could not generate a passphrase on this device, and will not fall \
                back to anything weaker. Nothing has been exported.
                """
            )
        }
    }

    /// What is shown on screen, in groups of four. The hyphens are display only.
    var displayedPassphrase: String {
        BackupPassphrase.grouped(generated)
    }

    /// The passphrase that would actually be used, and the rule it is used under.
    var effectivePassphrase: (text: String, mode: BackupPassphrase.Mode) {
        choice == .generated ? (displayedPassphrase, .generated) : (ownPassphrase, .custom)
    }

    var ownPassphraseAssessment: PassphraseStrength.Assessment {
        PassphraseStrength.assess(ownPassphrase)
    }

    /// Whether the archive can be written yet.
    var canExport: Bool {
        guard hasSavedPassphrase else { return false }
        return choice == .generated || ownPassphraseAssessment.isAcceptable
    }

    // MARK: - The gate

    /// Asks the person to prove they are the owner, then moves to the passphrase.
    ///
    /// Gated whether or not App Lock is on, because writing every secret to a file is
    /// categorically different from reading one code and should not be two taps away on a
    /// phone that was handed over unlocked. Import is deliberately not gated: it reveals
    /// nothing.
    func authenticate() async {
        let allowed = await AppLockAvailability.authenticate(
            reason: String(localized: "Export your accounts")
        )

        guard allowed else { return }

        accountCount = (try? store.records().readable.count) ?? 0
        stage = .choosing
    }

    // MARK: - Writing

    func export() {
        let passphrase = effectivePassphrase

        do {
            let accounts = try collectAccounts()
            let archive = try BackupArchive.write(
                accounts, passphrase: passphrase.text, mode: passphrase.mode
            )
            stage = .ready(try writeTemporaryFile(archive))
        } catch let error as ExportFailure {
            stage = .failed(error.description)
        } catch let error as BackupError {
            stage = .failed(error.description)
        } catch {
            stage = .failed("OpenFactor could not write the archive.")
        }
    }

    /// Every account, with its secret, read at the moment of export and held no longer than
    /// the encryption takes.
    ///
    /// **A record that cannot be read fails the whole export.** Writing an archive missing
    /// accounts the owner believes are in it is the worst outcome available here: it is
    /// discovered at a restore, on a device that no longer has the originals. The usual
    /// cause is a locked Keychain, which is temporary and worth waiting for.
    private func collectAccounts() throws -> [ImportedAccount] {
        let records = try store.records()

        guard records.unreadable.isEmpty else { throw ExportFailure.someUnreadable }

        return try records.readable
            .sorted { $0.metadata.sortIndex < $1.metadata.sortIndex }
            .map { record in
                ImportedAccount(
                    account: OTPAccount(
                        issuer: record.metadata.issuer,
                        name: record.metadata.name,
                        secret: try store.secret(for: record.id),
                        generator: record.metadata.generator
                    ),
                    color: record.metadata.color,
                    sortIndex: record.metadata.sortIndex
                )
            }
    }

    /// The file, with the strongest protection iOS offers while it exists.
    ///
    /// The name carries a date so a person with three of them in Files can tell which is
    /// which, and nothing else: no device name, no account count, no issuer. A file name is
    /// visible in every share sheet, every backup listing and every screenshot of one.
    private func writeTemporaryFile(_ data: Data) throws -> URL {
        let stamp = Self.stampFormatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenFactor \(stamp)")
            .appendingPathExtension("openfactor")

        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Removes the archive from the app's own storage.
    ///
    /// **Called when the screen goes away, whichever way it went away.** Shared, cancelled,
    /// swiped down, or backgrounded into oblivion: the app keeps no history of exports, and
    /// a file holding every secret does not get to outlive the screen that made it because
    /// somebody dismissed it in an unexpected order.
    func discardFile() {
        guard case let .ready(url) = stage else { return }
        try? FileManager.default.removeItem(at: url)
        stage = .choosing
    }

    private enum ExportFailure: Error {
        case someUnreadable

        var description: String {
            switch self {
            case .someUnreadable:
                """
                Some accounts could not be read, so OpenFactor did not write an archive. An \
                archive missing accounts is worse than no archive, because you would find \
                out when you needed it. Unlock your device and try again.
                """
            }
        }
    }
}
