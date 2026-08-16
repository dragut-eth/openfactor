import Foundation
import OpenFactorCore
import SwiftUI

/// Reading a file, deciding what it holds, and saving what the user accepts.
///
/// **The preview is the whole design.** Every judgement lives here, before anything is
/// written, so the user sees what will happen and agrees to it. Adding forty accounts at
/// once is not the same act as adding one, and the scan confirmation that works for a
/// single QR code does not answer it.
@Observable
@MainActor
final class ImportViewModel {

    enum Stage: Equatable {
        case choosing
        /// An OpenFactor archive, recognised but not yet opened. The bytes are held because
        /// the file was picked from a security scoped URL that is no longer accessible by
        /// the time a passphrase has been typed.
        case locked(Data, failure: String?)
        /// Deriving keys, which takes long enough on the wrong passphrase to need saying.
        case unlocking
        case reviewing(Preview)
        case finished(added: Int, skipped: Int)
        case failed(String)
    }

    /// What a file turned out to hold, after it has been read but before anything is saved.
    struct Preview: Equatable {
        let source: String
        let candidates: [Candidate]
        let refusals: [ImportRefusal]

        var importable: [Candidate] { candidates.filter { $0.disposition == .new } }
        var duplicates: [Candidate] { candidates.filter { $0.disposition == .duplicate } }
        var conflicts: [Candidate] { candidates.filter { $0.disposition == .conflict } }
    }

    /// One account from the file, and what would happen to it.
    struct Candidate: Equatable, Identifiable {
        let id = UUID()
        let imported: ImportedAccount
        let disposition: Disposition

        var label: String {
            imported.account.issuer ?? imported.account.name
        }

        enum Disposition: Equatable {
            /// Not already here.
            case new
            /// Same secret and same code generating parameters. Adding it again would
            /// produce a second card generating identical codes.
            case duplicate
            /// Same secret, different parameters. Gate A3's second review pointed out that
            /// the secret alone is not the account: the same secret with a different period
            /// or digit count is a different authenticator, so this is surfaced rather than
            /// silently collapsed.
            case conflict
        }
    }

    private(set) var stage: Stage = .choosing

    private let store: any SecretStore

    init(store: any SecretStore) {
        self.store = store
    }

    /// Shows a preview of accounts that arrived some other way than through a file.
    ///
    /// The scanner hands transfer codes here rather than growing its own review screen. The
    /// judgement about what happens to each account is the same judgement whatever carried
    /// it, and having it in one place is how the three dispositions stay consistent between
    /// a file somebody chose and a code somebody pointed a camera at.
    func present(_ result: ImportResult, source: String) {
        do {
            stage = .reviewing(try classify(result, source: source))
        } catch {
            stage = .failed("Your accounts could not be read from this device.")
        }
    }

    /// Reads a file the user picked, detecting the format from its contents.
    ///
    /// **The extension is a hint, never the decision.** A labelled text export saved as
    /// `.txt` is still one, and a file named `.json` that is not an Aegis vault must not be
    /// read as one.
    func read(_ url: URL) {
        let needsRelease = url.startAccessingSecurityScopedResource()
        defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            stage = .failed("That file could not be opened.")
            return
        }

        // Bounded before anything parses it. A file the user picked is untrusted input, and
        // an importer should not be the thing that decides how much memory to spend.
        guard data.count <= 8 * 1024 * 1024 else {
            stage = .failed("That file is too large to be an authenticator export.")
            return
        }

        // An OpenFactor archive is recognised here rather than in `preview`, because it is
        // the one format that cannot be read without asking the person for something first.
        if looksLikeOpenFactorArchive(data) {
            stage = .locked(data, failure: nil)
            return
        }

        do {
            stage = .reviewing(try preview(from: data))
        } catch let error as AegisImport.FileError {
            stage = .failed(error.description)
        } catch {
            stage = .failed("OpenFactor could not find any accounts in that file.")
        }
    }

    private func preview(from data: Data) throws -> Preview {
        // Aegis first, because a JSON vault is unambiguous: it either decodes or it does
        // not. The labelled reader accepts anything and finds nothing in most of it, so
        // trying it first would swallow a malformed vault.
        if looksLikeJSON(data) {
            let result = try AegisImport.read(data)
            return try classify(result, source: "Aegis vault")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportFailure.unreadable
        }

        let result = LabelledTextImport.read(text)
        guard !result.isEmpty else { throw ImportFailure.unreadable }
        return try classify(result, source: "Text export")
    }

    /// Whether this is one of ours, decided by the field the format says to look at first.
    ///
    /// Only the `format` string, and only whether it is present with the right value. Every
    /// other judgement about the file belongs to the reader, which refuses far more
    /// carefully than a sniff can and does it before deriving any key.
    private func looksLikeOpenFactorArchive(_ data: Data) -> Bool {
        guard
            looksLikeJSON(data),
            let root = try? JSONSerialization.jsonObject(with: data),
            let object = root as? [String: Any]
        else {
            return false
        }
        return object["format"] as? String == BackupArchive.format
    }

    /// Opens an archive with the passphrase somebody typed.
    ///
    /// **Off the main actor**, because this is up to four PBKDF2 derivations at 600,000
    /// iterations and the wrong passphrase is the path that pays for all four. Left on the
    /// main actor it would freeze the interface for around a second, on the screen where a
    /// worried person is most likely to tap again and assume it is broken.
    func unlock(with passphrase: String) async {
        guard case let .locked(data, _) = stage else { return }
        stage = .unlocking

        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try BackupArchive.read(data, passphrase: passphrase) }
        }.value

        switch outcome {
        case let .success(result):
            do {
                stage = .reviewing(try classify(result, source: "OpenFactor backup"))
            } catch {
                stage = .failed("Your accounts could not be read from this device.")
            }
        case let .failure(error):
            let message = (error as? BackupError)?.description ?? BackupError.couldNotOpen.description
            stage = .locked(data, failure: message)
        }
    }

    /// Both formats can begin with `{`, which is how the first version of this got it
    /// wrong: RTF opens with `{\rtf` and every labelled text export was sniffed as a broken
    /// Aegis vault. The signature is checked before the brace.
    private func looksLikeJSON(_ data: Data) -> Bool {
        let head = data.prefix(512)
        if head.starts(with: Array("{\\rtf".utf8)) { return false }

        guard let first = head.first(where: { !$0.isASCIIWhitespace }) else { return false }
        return first == UInt8(ascii: "{")
    }

    /// Works out what would happen to each account, against what is already stored.
    private func classify(_ result: ImportResult, source: String) throws -> Preview {
        let existing = try store.records().readable

        // Matched on the secret, since a re-enrolment produces a genuinely different one
        // and a renamed account does not. Comparing secrets means holding them here for
        // the length of the comparison, which import already does by nature.
        var bySecret: [Data: [AccountRecord]] = [:]
        for record in existing {
            guard let secret = try? store.secret(for: record.id) else { continue }
            bySecret[secret, default: []].append(record)
        }

        let candidates = result.accounts.map { imported in
            Candidate(
                imported: imported,
                disposition: disposition(for: imported, against: bySecret[imported.account.secret])
            )
        }

        return Preview(source: source, candidates: candidates, refusals: result.refusals)
    }

    private func disposition(
        for imported: ImportedAccount,
        against matches: [AccountRecord]?
    ) -> Candidate.Disposition {
        guard let matches, !matches.isEmpty else { return .new }

        // Same secret and the same code generating parameters is the same authenticator.
        // Same secret with different parameters generates different codes, so it is a
        // conflict for the user to resolve rather than a duplicate to swallow.
        return matches.contains { $0.metadata.generator == imported.account.generator }
            ? .duplicate
            : .conflict
    }

    /// Saves the accounts the user accepted. Nothing before this point has written anything.
    func confirm(_ preview: Preview, includingConflicts: Bool) {
        var added = 0

        let toSave = preview.importable + (includingConflicts ? preview.conflicts : [])

        for candidate in toSave {
            do {
                try store.add(candidate.imported.account, color: candidate.imported.color)
                added += 1
            } catch {
                // Keep going. One failure should not strand the rest, and the count at the
                // end tells the truth about what happened.
                continue
            }
        }

        stage = .finished(
            added: added,
            skipped: preview.candidates.count - added
        )
    }

    private enum ImportFailure: Error {
        case unreadable
    }
}

extension UInt8 {
    fileprivate var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}
