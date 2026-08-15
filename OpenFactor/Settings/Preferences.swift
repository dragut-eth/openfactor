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

    /// Which app icon the user chose. See ``AppIconPreference``.
    static let appIcon = "appIcon"

    /// Whether the interface is behind Face ID, Touch ID, or the passcode. Off by default:
    /// everything in this app is opted into, not imposed.
    static let appLockEnabled = "appLockEnabled"

    /// How long the app can be away before returning locks it, in seconds. Zero means any
    /// time away at all.
    static let appLockGraceSeconds = "appLockGraceSeconds"
}


/// Which app icon is on the home screen.
///
/// iOS already offers a global icon appearance control, in the home screen's Customize
/// panel, and this duplicates part of it deliberately: that one applies to every app at
/// once, and someone who wants their authenticator to look a particular way should not have
/// to make every other icon match.
///
/// The dark icon is the primary, so it is what the App Store shows and what an untouched
/// install gets. The other two are alternates.
enum AppIconPreference: String, CaseIterable, Identifiable {

    /// The primary icon, dark in every appearance.
    case dark

    /// Light in every appearance.
    case light

    /// Follows the system: light artwork in light appearance, dark in dark.
    case automatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .automatic: "Automatic"
        }
    }

    /// The asset catalog name, or `nil` for the primary icon.
    ///
    /// `nil` is not "no icon": it is how `setAlternateIconName` is told to go back to the
    /// one built into the app.
    var alternateIconName: String? {
        switch self {
        case .dark: nil
        case .light: "AppIconLight"
        case .automatic: "AppIconAuto"
        }
    }
}

/// How long the app may be in the background before coming back locked.
///
/// Three values rather than a slider, because the differences that matter are categorical:
/// hand the phone over and it is locked, pocket it between codes and it is not.
enum AppLockGrace: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        }
    }
}
