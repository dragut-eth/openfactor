import OpenFactorCore
import SwiftUI

extension View {

    /// Stops a service or account field at the bound `AccountLabel` enforces.
    ///
    /// **The storage bound is the real one and this is not a second opinion about it**, which
    /// is why the number lives in the core and this reads it. Both screens that type a label
    /// use this, so the two cannot drift apart, and neither can drift from what is stored.
    ///
    /// The reason to bound the field at all, when the core already clamps on save, is that
    /// silent truncation at save time is a small lie: somebody would watch sixty-five
    /// characters go in and find sixty-four came out, with nothing having said so. Stopping
    /// the field is the ordinary iOS behavior and says it at the moment it happens.
    ///
    /// It cuts on change rather than filtering keystrokes, because a paste is the case worth
    /// handling and a paste is not a keystroke.
    func boundedLabel(_ text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            let clamped = AccountLabel.clamped(new)
            if clamped != new { text.wrappedValue = clamped }
        }
    }
}
