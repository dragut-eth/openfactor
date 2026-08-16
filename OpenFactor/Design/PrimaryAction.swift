import SwiftUI

/// The app's one prominent button, defined once.
///
/// It exists on the two screens that ask for a single thing and nothing else: the empty account
/// list's "Add an account", and the vault setup's "Create my vault". Those are the same moment in
/// the same app and they looked different, because the second one was written later and matched
/// nothing.
///
/// **Padding rather than a fixed width, and that distinction is the whole of this type.** It was
/// a 260pt frame, which sizes the button to the frame and not to the words: a long label filled
/// it and looked right, a short one sat marooned in the middle of a capsule with ninety points of
/// air on either side. Padding gives every label the same margin, so two buttons match each other
/// without both having to match some third number neither of them chose.
///
/// The prominent button style adds roughly twenty points of its own on each side, so the constant
/// here is the remainder rather than the gap you end up seeing.
struct PrimaryActionLabel: View {

    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .padding(.horizontal, Tokens.Spacing.medium)
            .padding(.vertical, 4)
    }
}

extension View {

    /// Applied to the `Button`, while `PrimaryActionLabel` handles its inside. Both halves are
    /// needed: the style cannot set the label's width, and the label cannot set the shape.
    func primaryActionStyle() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
    }
}
