import Foundation
import OpenFactorCore

/// Typing in an account by hand, for the services that print a secret instead of showing
/// a QR code.
///
/// The validation here is the point of the screen. A mistyped Base32 secret is not
/// rejected by anything downstream: it decodes to different bytes, generates plausible six
/// digit codes, and every one of them is refused by the service. Nobody finds out until a
/// login fails, by which time the enrollment page is closed. So the secret is checked on
/// every keystroke and a live code is shown before anything is saved.
@MainActor
@Observable
final class ManualSetupViewModel {

    // MARK: - What the user types

    var secretText: String = "" {
        didSet { saveFailure = nil }
    }

    var issuer: String = ""
    var name: String = ""

    var isCounterBased: Bool = false
    var algorithm: OTPAlgorithm = .default
    var digits: OTPDigits = .default
    var period: Int = 30
    var counterText: String = "0"

    /// Set when saving itself failed, which is a different thing from the form being
    /// incomplete and is shown differently.
    private(set) var saveFailure: String?

    private let store: any SecretStore

    init(store: any SecretStore) {
        self.store = store
    }

    // MARK: - Validation

    /// What is wrong with the secret as typed, or `nil` if it is usable.
    ///
    /// Empty is not an error. A field the user has not filled in yet should not be shouting
    /// at them, so an untouched form is quiet and the save button is simply unavailable.
    var secretProblem: String? {
        guard !secretText.trimmed.isEmpty else { return nil }

        do {
            let bytes = try Base32.decode(secretText)
            return bytes.isEmpty ? "That secret is empty." : nil
        } catch {
            return error.description
        }
    }

    var counterProblem: String? {
        guard isCounterBased, !counterText.trimmed.isEmpty else { return nil }
        return UInt64(counterText.trimmed) == nil ? "The counter must be a whole number." : nil
    }

    var periodProblem: String? {
        TOTPConfiguration.supportedPeriods.contains(period)
            ? nil
            : "A code cannot refresh every \(period) seconds."
    }

    /// The account the form currently describes, or `nil` if it does not describe one yet.
    ///
    /// Everything else on this screen is derived from this, so there is one definition of
    /// "valid" rather than one per button.
    var account: OTPAccount? {
        guard let secret = try? Base32.decode(secretText), !secret.isEmpty else { return nil }

        let generator: OTPGenerator
        if isCounterBased {
            guard let counter = UInt64(counterText.trimmed) else { return nil }
            generator = .hotp(counter: counter, digits: digits, algorithm: algorithm)
        } else {
            guard let configuration = try? TOTPConfiguration(
                algorithm: algorithm,
                digits: digits,
                period: period
            ) else {
                return nil
            }
            generator = .totp(configuration)
        }

        return OTPAccount(
            issuer: issuer.trimmed.nilIfBlank,
            name: name.trimmed,
            secret: secret,
            generator: generator
        )
    }

    var canSave: Bool { account != nil }

    // MARK: - Preview

    /// The code the form would produce right now, so it can be checked against what the
    /// service is showing before anything is saved.
    func previewCode(at date: Date) -> String? {
        account?.code(at: date)
    }

    func previewSecondsRemaining(at date: Date) -> TimeInterval? {
        guard !isCounterBased, account != nil else { return nil }
        return TOTP.timeRemaining(at: date, period: period)
    }

    /// The colour the account will get.
    ///
    /// Follows the issuer while nobody has expressed an opinion, so typing "GitHub" moves
    /// it without anyone asking, and stops following the moment someone picks one. A
    /// choice that silently reverted because the next keystroke changed the issuer would
    /// be worse than not offering the choice at all.
    var color: AccountColor {
        get { chosenColor ?? .suggested(forIssuer: issuer.trimmed.nilIfBlank) }
        set { chosenColor = newValue }
    }

    private var chosenColor: AccountColor?

    // MARK: - Saving

    /// Saves the account. Returns whether it worked.
    @discardableResult
    func save() -> Bool {
        guard let account else { return false }

        do {
            try store.add(account, color: color)
            saveFailure = nil
            return true
        } catch {
            saveFailure = error.description
            return false
        }
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
