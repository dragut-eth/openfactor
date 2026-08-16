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
        /// Which kind of file, before anything is generated.
        case explaining
        /// The passphrase exists and has not been used yet.
        case choosing
        /// The plaintext path, which has one thing to say and needs it acknowledged.
        case warning
        /// The file is written and waiting to be shared.
        case ready(URL)
        case failed(String)
    }

    /// The two ways out of the app.
    ///
    /// One is a backup and one is a door. They are separate paths rather than a switch on
    /// the same screen, because the plaintext one has a warning that has to be read and an
    /// acknowledgement of its own, and burying that under a segmented control would make the
    /// dangerous choice the cheaper tap.
    enum Kind: Equatable {
        case archive
        case plainAegis
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

    var choice: PassphraseChoice = .generated {
        didSet { if choice != oldValue { hasSavedPassphrase = false } }
    }

    var ownPassphrase: String = "" {
        didSet { if ownPassphrase != oldValue { hasSavedPassphrase = false } }
    }

    /// Ticked by the person, and the gate on producing the file. Deliberately not a toggle
    /// that defaults on: the format says never write an archive whose passphrase the user
    /// has not been shown and confirmed they have stored.
    ///
    /// **It is cleared whenever the passphrase it refers to changes**, and that was a
    /// blocking finding of the security review rather than caution. Tick the box, then tap
    /// "Generate a different one", and the archive was sealed with a passphrase that had
    /// never been on screen while the box was ticked. The one written down opens nothing,
    /// and nobody finds out until a restore. The same held for editing a custom passphrase
    /// after ticking, and for switching between the two.
    var hasSavedPassphrase = false

    private(set) var accountCount = 0

    private(set) var kind: Kind = .archive

    /// Ticked on the plaintext path. The same gate the passphrase has, for the same reason:
    /// the person has to have read the one sentence that matters before a file exists.
    var understandsPlaintext = false

    private let store: any SecretStore

    init(store: any SecretStore) {
        self.store = store
        regenerate()
    }

    func regenerate() {
        // The acknowledgement referred to the old one.
        hasSavedPassphrase = false
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
    func authenticate(for kind: Kind) async {
        let allowed = await AppLockAvailability.authenticate(
            reason: String(localized: "Export your accounts")
        )

        guard allowed else { return }

        self.kind = kind
        accountCount = (try? store.records().readable.count) ?? 0
        stage = kind == .archive ? .choosing : .warning
    }

    // MARK: - Writing

    /// Writes the plaintext vault.
    ///
    /// Gated behind the same authentication as the encrypted archive, and behind an
    /// acknowledgement of its own. It is the more dangerous of the two files by a wide
    /// margin: there is no passphrase between it and whoever ends up holding it.
    func exportPlain() {
        guard understandsPlaintext else { return }

        do {
            let accounts = try collectAccounts()
            let vault = try AegisExport.write(accounts)
            stage = .ready(try writeTemporaryFile(vault, extension: "json", label: "plaintext"))
        } catch let error as ExportFailure {
            stage = .failed(error.description)
        } catch {
            stage = .failed("OpenFactor could not write the file.")
        }
    }

    func export() {
        let passphrase = effectivePassphrase

        do {
            let accounts = try collectAccounts()
            let archive = try BackupArchive.write(
                accounts, passphrase: passphrase.text, mode: passphrase.mode
            )
            stage = .ready(try writeTemporaryFile(archive, extension: "openfactor", label: nil))
        } catch let error as ExportFailure {
            stage = .failed(error.description)
        } catch let error as BackupError {
            stage = .failed(error.description)
        } catch {
            stage = .failed("OpenFactor could not write the backup.")
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

    /// Where exports live while they exist: one directory, so that removing it removes
    /// every one of them without having to know their names.
    private static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    /// Removes anything a previous run left behind.
    ///
    /// **Called at launch, because `onDisappear` cannot cover a process that is not there
    /// any more.** The review found the gap: force quit from the app switcher, or an out of
    /// memory kill, while the Ready screen is showing, and the file survives with nothing in
    /// the app ever revisiting it. For the plaintext vault that is every secret in the clear,
    /// sitting in the container until the app is deleted. The promise was that the file does
    /// not outlive the screen, and this is the half of it the screen cannot keep.
    static func discardOrphanedFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The file, with the strongest protection iOS offers while it exists.
    ///
    /// The name carries a date so a person with three of them in Files can tell which is
    /// which, and nothing else: no device name, no account count, no issuer. A file name is
    /// visible in every share sheet, every backup listing and every screenshot of one.
    private func writeTemporaryFile(
        _ data: Data,
        extension pathExtension: String,
        label: String?
    ) throws -> URL {
        let stamp = Self.stampFormatter.string(from: Date())
        let name = label.map { "OpenFactor \($0) \(stamp)" } ?? "OpenFactor \(stamp)"

        try FileManager.default.createDirectory(
            at: Self.directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        let url = Self.directory
            .appendingPathComponent(name)
            .appendingPathExtension(pathExtension)

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
        stage = kind == .archive ? .choosing : .warning
    }

    private enum ExportFailure: Error {
        case someUnreadable

        var description: String {
            switch self {
            case .someUnreadable:
                """
                Some accounts could not be read, so OpenFactor did not write a backup. A \
                backup missing accounts is worse than no backup, because you would find \
                out when you needed it. Unlock your device and try again.
                """
            }
        }
    }
}
