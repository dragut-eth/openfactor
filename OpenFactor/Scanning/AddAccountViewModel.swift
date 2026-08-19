import Foundation
import OpenFactorCore

/// Turning something scanned into a saved account.
///
/// All the judgement in the add flow lives here rather than in the scanner, so it can be
/// tested without a camera. The camera's only job is to hand over a string.
///
/// **A scan does not save anything.** It moves to a confirmation step showing the issuer,
/// the account name, and a live code. One extra tap, for two reasons: a QR is unreadable
/// to a human, so this is the first and only chance to see what was actually in it, and
/// the code preview can be checked against what the service is showing while the
/// enrollment page is still open. After that page is gone, a wrongly imported account is
/// discovered at a login, which is the worst possible moment.
@MainActor
@Observable
final class AddAccountViewModel {

    enum Stage: Equatable {
        /// Looking for a code.
        case scanning

        /// Found one, showing what it contains.
        case confirming(OTPAccount)

        /// Found a transfer from another authenticator, which is not one account and is
        /// not this screen's job. It is handed to the import preview, which was built for
        /// exactly this: forty accounts arriving at once is a different act from adding
        /// one, and a confirmation screen showing a single issuer cannot answer it.
        case transferring(GoogleAuthenticatorImport.Batch)

        /// Saved. The sheet closes on this.
        case added
    }

    private(set) var stage: Stage = .scanning

    /// What went wrong with the last attempt, in words the user can act on.
    private(set) var problem: String?

    /// The colour the account will get.
    ///
    /// Seeded from the issuer when a code is read, then the user's to change on the
    /// confirmation screen before anything is saved.
    var color: AccountColor = .default

    private let store: any SecretStore

    init(store: any SecretStore) {
        self.store = store
    }

    // MARK: - Reading codes

    /// Handles one payload from the camera or a photo.
    func handleScan(_ payload: String) {
        guard case .scanning = stage else { return }

        // Asked first, and it is a scheme comparison rather than a guess. `otpauth://` is
        // one account and `otpauth-migration://` is a transfer: two schemes, no overlap.
        // Every other importer in this app has to sniff contents because a file extension
        // lies; here the payload names its own format.
        if GoogleAuthenticatorImport.looksLikeMigration(payload) {
            do {
                stage = .transferring(try GoogleAuthenticatorImport.read(payload))
                problem = nil
            } catch {
                // Says what the code *is* and what to do about it. This screen used to
                // answer a transfer code with "not a setup code", which was true and
                // useless at the exact moment somebody was trying to move in.
                problem = error.description
            }
            return
        }

        do {
            let account = try OTPAuthURI.account(from: payload)
            color = .suggested(forIssuer: account.issuer)
            problem = nil
            stage = .confirming(account)
        } catch {
            // The parser's errors already say precisely what is wrong, so they are shown
            // rather than replaced with something vaguer.
            problem = error.description
        }
    }

    /// Returns to the camera after a transfer preview was closed without importing.
    ///
    /// Without this the screen stays in a stage it can never leave: `handleScan` refuses
    /// anything but `.scanning`, so the viewfinder would be live and deaf.
    func resumeScanning() {
        if case .transferring = stage { stage = .scanning }
    }

    /// Handles an imported image, which may hold no codes, one, or several.
    func handleImage(_ data: Data) {
        guard case .scanning = stage else { return }

        // **The one entry point that had no bound at all.** A review found the picker path going
        // straight into `CIImage(data:)`, while the document picker, the URL scheme and the share
        // extension were all bounded. It is a QR detector rather than the vault, which is why it
        // was rated below the others and still filed: an unbounded path is an unbounded path.
        //
        // The honest limit of this fix: the system's transfer has already produced the bytes by
        // the time they arrive here, so this bounds what OpenFactor decodes rather than what
        // Photos hands over. `CIImage` on a hostile image is the expensive part, and that is on
        // this side of the line.
        guard ImportLimits.isWithinBound(data.count, isOpenFactorArchive: false) else {
            problem = "That image is too large to read."
            return
        }

        let payloads = QRDecoder.payloads(in: data)

        guard !payloads.isEmpty else {
            problem = "No QR code was found in that image."
            return
        }

        // More than one code in a screenshot is ambiguous, and guessing which account the
        // user meant is not a guess worth making with something they will rely on to log
        // in. Ask for a picture of the one they want.
        guard payloads.count == 1 else {
            problem = "That image has \(payloads.count) QR codes in it. Crop it to the one you want."
            return
        }

        handleScan(payloads[0])
    }

    // MARK: - Confirming

    /// The code the pending account produces right now, so it can be checked against what
    /// the service is showing before anything is saved.
    func previewCode(at date: Date) -> String? {
        guard case let .confirming(account) = stage else { return nil }
        return account.code(at: date)
    }

    func previewSecondsRemaining(at date: Date) -> TimeInterval? {
        guard case let .confirming(account) = stage,
            case let .totp(configuration) = account.generator
        else {
            return nil
        }

        return TOTP.timeRemaining(at: date, period: configuration.period)
    }

    /// Saves the pending account.
    func confirm() {
        guard case let .confirming(account) = stage else { return }

        do {
            try store.add(account, color: color)
            problem = nil
            stage = .added
        } catch {
            problem = error.description
        }
    }

    /// Goes back to looking, after a wrong code or a change of mind.
    func scanAgain() {
        stage = .scanning
        problem = nil
    }

    func dismissProblem() {
        problem = nil
    }
}
