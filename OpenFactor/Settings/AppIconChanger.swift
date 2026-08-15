import SwiftUI
import UIKit

/// Changes the home screen icon.
///
/// Small enough to be a free function, but it is worth naming the one thing that is not
/// obvious: iOS shows an alert of its own every time the icon changes, and there is no
/// supported way to suppress it. Apps that hide it swizzle a private method. This one does
/// not, because a security tool that reaches for private API to avoid a dialog has its
/// priorities in the wrong order, and because the alert is honest: something did change on
/// the user's home screen.
///
/// It also means the change must not be attempted when nothing would change, or the user
/// gets an alert for opening a settings screen.
enum AppIconChanger {

    /// Applies the preference, doing nothing if the icon is already the one asked for.
    ///
    /// Failures are swallowed on purpose. The only realistic causes are a device that does
    /// not support alternate icons and a name that is not in the catalog, and neither is
    /// something the user can act on. The setting stays where they put it and the icon does
    /// not change, which is visible without being told.
    @MainActor
    static func apply(_ preference: AppIconPreference) {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else { return }

        let wanted = preference.alternateIconName
        guard application.alternateIconName != wanted else { return }

        application.setAlternateIconName(wanted)
    }
}
