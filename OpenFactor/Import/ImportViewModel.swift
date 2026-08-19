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

        // **One open and one bounded read**, rather than a size lookup followed by a separate
        // load. The lookup version was already an improvement on measuring after the allocation,
        // and a review took it apart again: whoever supplied the file can change it between the
        // two calls, so the bound describes a file that no longer exists. Two other engines read
        // the same lines and passed them, on the reasoning that only the shared container faces a
        // hostile writer, and that disagreement is recorded rather than settled. `BoundedFile`
        // removes the need to settle it.
        let data: Data
        do {
            data = try BoundedFile.read(url, limit: ImportLimits.largestAcceptableBytes)
        } catch .tooLarge {
            stage = .failed("That file is too large to be an authenticator export.")
            return
        } catch {
            // **Not "too large".** The refusal used to reuse that sentence for a file it could not
            // measure, which claims something it did not know. A review pointed out that this
            // project's own rule about untrustworthy messages argues against it.
            stage = .failed("That file could not be opened.")
            return
        }

        read(data)
    }

    /// The same path for bytes that arrived without a file, which is what the share extension's
    /// inbox produces.
    ///
    /// Split out rather than duplicated, because everything below is the part that matters: the
    /// bound, the archive check, and the parser. A second entry point that skipped any of them
    /// would be a second, weaker importer.
    func read(_ data: Data) {
        // **One cheap bound before anything expensive**, which is the largest ceiling any format
        // has. Reordering this method so the format decides the bound put a full `Data` copy and
        // a complete `JSONSerialization` parse in front of the memory check, which is the exact
        // pattern the reorder existed to remove: a bound after the expensive operation. A review
        // found it in the commit that was fixing it.
        guard data.count <= ImportLimits.largestAcceptableBytes else {
            stage = .failed("That file is too large to be an authenticator export.")
            return
        }

        // **The format decides the bound, so the format is recognised first.** This used to
        // refuse everything over eight mebibytes before looking, and `BACKUP_FORMAT.md` permits
        // eight mebibytes of *decoded ciphertext*, which is about 11.2 million base64 characters
        // plus a wrapper. So a conforming version 1 archive was refused, before the passphrase
        // screen, in a way its owner could not tell apart from the file being rubbish. Gate A3
        // found that same mistake inside `BackupArchive.read`; this was it one layer up, where no
        // test was looking.
        //
        // An archive is now held to the frozen ceiling and nothing else. `BackupArchive.read`
        // enforces the format's own three checks in order from there.
        let isArchive = looksLikeOpenFactorArchive(data)

        guard ImportLimits.isWithinBound(data.count, isOpenFactorArchive: isArchive) else {
            stage = .failed("That file is too large to be an authenticator export.")
            return
        }

        // An OpenFactor archive is recognised here rather than in `preview`, because it is
        // the one format that cannot be read without asking the person for something first.
        if isArchive {
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
        let body = JSONSniff.body(of: data)
        if !body.isEmpty {
            sourceWasEncrypted = false
            let result = try AegisImport.read(body)
            return try classify(result, source: "Aegis vault")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportFailure.unreadable
        }

        sourceWasEncrypted = false
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
            case let body = JSONSniff.body(of: data), !body.isEmpty,
            let root = try? JSONSerialization.jsonObject(with: body),
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
                sourceWasEncrypted = true
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
    /// Whether these bytes are meant to be JSON. The decision is `JSONSniff`'s, in the core,
    /// where a test can reach it: it was private to this file and had two defects that a reviewer
    /// had to find by reading.
    private func looksLikeJSON(_ data: Data) -> Bool {
        !JSONSniff.body(of: data).isEmpty
    }

    /// Whether the file these accounts came from was an encrypted OpenFactor archive.
    ///
    /// **Only so the last screen can stop telling people something false.** It advised deleting
    /// the file because it "contains your secret keys in the clear", which is true of an Aegis
    /// vault and a labelled text export and exactly wrong about an encrypted backup: that file is
    /// the person's recovery copy, and this app was telling them to throw it away. A review found
    /// it.
    private(set) var sourceWasEncrypted = false

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

        // **Accounts already seen in this same file count too.** A review found that each
        // imported account was compared only against what was stored, so a file listing the same
        // account twice added it twice, and the preview said "will be added" for both. Duplicate
        // detection that only looks outward is not duplicate detection.
        var seenInThisFile: [Data: [OTPGenerator]] = [:]
        var candidates: [Candidate] = []

        for imported in result.accounts {
            let stored = (bySecret[imported.account.secret] ?? []).map(\.metadata.generator)
            let earlier = seenInThisFile[imported.account.secret] ?? []

            candidates.append(
                Candidate(
                    imported: imported,
                    disposition: disposition(for: imported, against: stored + earlier)))

            seenInThisFile[imported.account.secret, default: []]
                .append(imported.account.generator)
        }

        return Preview(source: source, candidates: candidates, refusals: result.refusals)
    }

    /// - Parameter matches: the generators of everything carrying this secret already, whether
    ///   stored on the device or listed earlier in the same file.
    private func disposition(
        for imported: ImportedAccount,
        against matches: [OTPGenerator]
    ) -> Candidate.Disposition {
        guard !matches.isEmpty else { return .new }

        // Same secret and the same code generating parameters is the same authenticator.
        // Same secret with different parameters generates different codes, so it is a
        // conflict for the user to resolve rather than a duplicate to swallow.
        return matches.contains(imported.account.generator) ? .duplicate : .conflict
    }

    /// Saves the accounts the user accepted. Nothing before this point has written anything.
    func confirm(_ preview: Preview, includingConflicts: Bool) {
        var added = 0

        // **In the order the file asked for.** Every reader carries a `sortIndex`, and `add`
        // assigns its own append-at-end position, so the file's order was read and discarded.
        // Order survived a round trip only because the writer happens to emit in order. Sorting
        // here is the whole fix: the accounts are appended in the order somebody arranged them,
        // which is what restoring a backup is supposed to give back.
        let toSave = (preview.importable + (includingConflicts ? preview.conflicts : []))
            .sorted { $0.imported.sortIndex < $1.imported.sortIndex }

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
