import Foundation

/// Everything about an account except its secret.
///
/// This is what the list is drawn from. Loading it never touches secret material, which
/// is the point: the codes on screen are generated one at a time, and the secret for an
/// account is read only in the instant its code is computed.
///
/// **Not secret is not the same as not sensitive.** The issuer and the account name say
/// which services someone uses and under which email address, which is exactly the sort
/// of thing worth protecting even though it cannot generate a code. So this is stored in
/// the Keychain too, encrypted at rest, rather than in a plist or a database file. See
/// ``KeychainSecretStore``.
public struct AccountMetadata: Sendable, Equatable, Codable {

    /// Who issued the account, for example `GitHub`.
    public var issuer: String?

    /// Which account at that issuer, usually an email address or a username.
    public var name: String

    /// How this account's codes are produced. Stored because it is fixed at enrollment
    /// and cannot be recovered from the secret.
    public var generator: OTPGenerator

    /// Which palette entry the card is drawn in.
    public var color: AccountColor

    /// Position in the list. The list is sorted manually by default, per `UI_SPEC.md`.
    public var sortIndex: Int

    public init(
        issuer: String?,
        name: String,
        generator: OTPGenerator,
        color: AccountColor,
        sortIndex: Int
    ) {
        self.issuer = issuer
        self.name = name
        self.generator = generator
        self.color = color
        self.sortIndex = sortIndex
    }

    /// What the list shows as the headline for this account.
    ///
    /// Falls back to the account name when there is no issuer, and to a placeholder when
    /// there is neither, since a URI can legitimately carry no label at all.
    public var displayIssuer: String {
        if let issuer, !issuer.isEmpty { return issuer }
        if !name.isEmpty { return name }
        return "Unnamed account"
    }
}

/// A stored account: its identifier and everything but the secret.
///
/// The identifier is generated when the account is saved and never changes, so renaming
/// an account or moving it in the list cannot orphan its secret.
public struct AccountRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var metadata: AccountMetadata

    public init(id: UUID, metadata: AccountMetadata) {
        self.id = id
        self.metadata = metadata
    }
}
