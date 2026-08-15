import Foundation

/// Reads Step Two's export.
///
/// **A convenience importer, best effort by design, and it says so.** The file is not an
/// interchange format: it is a report Step Two writes for a human, with English labels and
/// prose paragraphs, and its authors can reword any sentence tomorrow without considering
/// it a breaking change. Nothing here is a contract with them.
///
/// That is exactly why it fails loudly and per account. A parser that guesses at a document
/// it does not control will one day guess wrong, and the wrong guess in an authenticator is
/// a code that looks right and is rejected forever.
///
/// The shape, per account, with fields separated by `U+2028` and a blank separator between
/// accounts:
///
/// ```
/// Account Name: GitHub
/// Email Address or Username: octocat@example.com
/// Secret Key: AAAA...
/// Hash Algorithm: sha1
/// Period: 30 seconds
/// Digits: 6
/// Color: Default color
/// ```
///
/// Three things about that shape break a naive reader, and all three are in the fixture.
/// The whole account list is one RTF paragraph, so splitting on newlines yields one
/// enormous line. `Period` is prose, not a number. And any non-ASCII in a label arrives as
/// an RTF escape, so a scanner that does not decode them renames the account.
public enum StepTwoImport {

    /// The labels this reader understands. English only, which is a real limitation: a
    /// localised export will produce no accounts rather than wrong ones, which is the
    /// correct way for this to fail.
    private enum Label {
        static let name = "Account Name:"
        static let account = "Email Address or Username:"
        static let secret = "Secret Key:"
        static let algorithm = "Hash Algorithm:"
        static let period = "Period:"
        static let digits = "Digits:"
        static let colour = "Color:"
    }

    /// Reads the contents of an exported file.
    ///
    /// Takes the raw text so the caller decides how the bytes were obtained. Never throws:
    /// a file that is not a Step Two export simply yields nothing, which the interface
    /// reports as "no accounts found" rather than as a failure.
    public static func read(_ contents: String) -> ImportResult {
        let text = RichTextReader.plainText(from: contents)

        var accounts: [ImportedAccount] = []
        var refusals: [ImportRefusal] = []
        var fields: [String: String] = [:]
        var position = 0

        /// Turns the fields gathered so far into an account, or a refusal naming why not.
        func finish() {
            guard !fields.isEmpty else { return }
            position += 1
            let label = fields[Label.name]

            switch build(from: fields) {
            case let .success(imported):
                accounts.append(imported)
            case let .failure(reason):
                refusals.append(ImportRefusal(position: position, label: label, reason: reason))
            }

            fields = [:]
        }

        // The separator is U+2028, and newlines appear between sections, so both split.
        for rawLine in text.split(whereSeparator: { $0 == "\u{2028}" || $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let (label, value) = labelled(line) else { continue }

            // A new account begins. Whatever came before is complete.
            if label == Label.name { finish() }

            fields[label] = value
        }

        finish()

        return ImportResult(accounts: accounts, refusals: refusals)
    }

    /// Splits a line into one of the known labels and its value, or nothing.
    ///
    /// Only known labels are recognised, so the prose paragraphs and the Settings section
    /// at the end of the document are ignored rather than parsed into nonsense.
    private static func labelled(_ line: String) -> (String, String)? {
        let known = [
            Label.name, Label.account, Label.secret,
            Label.algorithm, Label.period, Label.digits, Label.colour,
        ]

        for label in known where line.hasPrefix(label) {
            let value = line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
            return (label, value)
        }

        return nil
    }

    private static func build(
        from fields: [String: String]
    ) -> Result<ImportedAccount, ImportRefusal.Reason> {
        guard let rawSecret = fields[Label.secret], !rawSecret.isEmpty else {
            return .failure(.missingSecret)
        }

        let secret: Data
        do {
            secret = try Base32.decode(rawSecret)
        } catch {
            return .failure(.secretNotBase32)
        }

        // Absent means the default rather than a refusal only for values that cannot change
        // a code. Everything below that can change one is read strictly.
        let algorithmText = fields[Label.algorithm] ?? "sha1"
        guard let algorithm = OTPAlgorithm(rawValue: algorithmText.uppercased()) else {
            return .failure(.unsupportedAlgorithm(algorithmText))
        }

        let digitsText = fields[Label.digits] ?? "6"
        guard let digitsvalue = Int(digitsText) else { return .failure(.malformed) }
        guard let digits = OTPDigits(rawValue: digitsvalue) else {
            return .failure(.unsupportedDigits(digitsvalue))
        }

        // "30 seconds", so the number is taken from the front rather than the whole string.
        let periodText = fields[Label.period] ?? "30"
        guard let period = leadingInteger(periodText) else { return .failure(.malformed) }

        let configuration: TOTPConfiguration
        do {
            configuration = try TOTPConfiguration(
                algorithm: algorithm, digits: digits, period: period
            )
        } catch {
            return .failure(.unsupportedPeriod(period))
        }

        let account = OTPAccount(
            issuer: fields[Label.name],
            name: fields[Label.account] ?? "",
            secret: secret,
            generator: .totp(configuration)
        )

        return .success(
            ImportedAccount(account: account, color: colour(named: fields[Label.colour]))
        )
    }

    /// Reads the number at the start of a string such as "30 seconds".
    private static func leadingInteger(_ text: String) -> Int? {
        let digits = text.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Maps Step Two's colour names onto ours. Several coincide, so an import can carry a
    /// person's colours across rather than turning ten cards blue.
    ///
    /// Cosmetic, so anything unrecognised, including their "Default color", falls back
    /// rather than failing the account.
    private static func colour(named name: String?) -> AccountColor {
        guard let name, let match = AccountColor(rawValue: name.lowercased()) else {
            return .default
        }
        return match
    }
}
