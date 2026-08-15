import Foundation
import SwiftUI

/// How the account list is ordered.
///
/// Manual is the default and the only one that lets a card be dragged. The other two are
/// derived from the account itself, so there is nothing to drag them into: reordering a
/// list that sorts itself would either be ignored or would silently switch the setting.
enum AccountSortOrder: String, CaseIterable, Identifiable {
    case manual
    case issuer
    case name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manually"
        case .issuer: "By service"
        case .name: "By account"
        }
    }
}

/// Which colour scheme the app uses, regardless of the system.
///
/// Present because a scheme override is one of the few settings people genuinely change,
/// and because the palette was built for both schemes from the start, so honouring it
/// costs nothing.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means follow the system, which is what SwiftUI expects.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Where preferences are stored, and the deliberate line between these and secrets.
///
/// These live in `UserDefaults`, which is an ordinary unencrypted file in the app
/// container. That is fine for exactly what is here and nothing more: a sort order and a
/// colour scheme reveal nothing about the accounts, or that there are any. Anything that
/// would say which services someone uses belongs in the Keychain with the secrets, which
/// is why the account metadata is there and not here.
enum PreferenceKey {
    static let sortOrder = "sortOrder"
    static let appearance = "appearance"

    /// Whether accounts are offered to iCloud Keychain.
    ///
    /// A preference rather than something derived from the Keychain, because with no
    /// accounts stored there is nothing to derive it from, and the answer still has to be
    /// remembered so the next account added inherits it.
    static let syncEnabled = "syncEnabled"
}
