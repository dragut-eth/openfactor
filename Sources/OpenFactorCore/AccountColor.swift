import Foundation

/// Which colour an account's card is drawn in.
///
/// These are names, not colours. The core has no idea what red looks like, and it should
/// not: the actual values live with the design tokens in the app, one set for light mode
/// and one for dark, so a palette change never touches stored data. What is stored is
/// this name, which stays meaningful whatever the palette does next.
public enum AccountColor: String, Sendable, Equatable, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink
    case gray

    /// Used when an account arrives without a colour, mostly on import.
    public static let `default` = AccountColor.blue

    /// A palette name this version does not know is read as the default, not as an error.
    ///
    /// Deliberately different from how the generator settings decode, and the difference
    /// is the point. An unknown algorithm changes the codes, so it must fail loudly. An
    /// unknown colour changes nothing but a tint, and refusing it would mean a record
    /// written by a newer version with a bigger palette could not be read by this one,
    /// which in `KeychainSecretStore.records()` blocks the entire list over a paint
    /// colour. Found at gate A1.
    public init(fallingBack name: String) {
        self = AccountColor(rawValue: name) ?? .default
    }

    /// A colour derived from the issuer, so a freshly added account is not the same blue
    /// as the last one and the list stays scannable.
    ///
    /// Deliberately not random. The same issuer lands on the same colour on every device
    /// and after every reinstall, which makes the list feel stable rather than shuffled.
    public static func suggested(forIssuer issuer: String?) -> AccountColor {
        guard let issuer = issuer?.lowercased(), !issuer.isEmpty else {
            return .default
        }

        // A small deterministic sum. Nothing here is security relevant, it only needs to
        // spread common issuers across the palette and give the same answer every time.
        let total = issuer.unicodeScalars.reduce(into: UInt32(0)) { sum, scalar in
            sum = sum &* 31 &+ scalar.value
        }

        return allCases[Int(total % UInt32(allCases.count))]
    }
}

extension AccountColor: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(fallingBack: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
