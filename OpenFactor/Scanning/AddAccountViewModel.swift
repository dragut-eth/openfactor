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

        /// Saved. The sheet closes on this.
        case added
    }

    private(set) var stage: Stage = .scanning

    /// What went wrong with the last attempt, in words the user can act on.
    private(set) var problem: String?

    /// The colour the account will get, suggested from the issuer and changeable later.
    private(set) var suggestedColor: AccountColor = .default

    private let store: any SecretStore

    init(store: any SecretStore) {
        self.store = store
    }

    // MARK: - Reading codes

    /// Handles one payload from the camera or a photo.
    func handleScan(_ payload: String) {
        guard case .scanning = stage else { return }

        do {
            let account = try OTPAuthURI.account(from: payload)
            suggestedColor = .suggested(forIssuer: account.issuer)
            problem = nil
            stage = .confirming(account)
        } catch {
            // The parser's errors already say precisely what is wrong, so they are shown
            // rather than replaced with something vaguer.
            problem = error.description
        }
    }

    /// Handles an imported image, which may hold no codes, one, or several.
    func handleImage(_ data: Data) {
        guard case .scanning = stage else { return }

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
            try store.add(account, color: suggestedColor)
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
