import OpenFactorCore
import SwiftUI

/// Everything about an account a person chose: its two labels and its colour.
///
/// Only those. The algorithm, digits, period, and counter came from the service and
/// changing them here would not change what the service expects, it would just stop the
/// codes matching. Those are set once, at enrolment.
///
/// The colour lives here rather than only behind its own menu entry because "details" and
/// "colour" were two destinations for one idea, which was fine while the only way in was a
/// menu listing both, and stopped being fine when tapping a card in edit mode had to choose
/// one of them. "Change colour" in the context menu is now a shortcut into a screen that
/// holds everything, rather than the only way to reach the colour at all.
struct EditAccountView: View {
    let record: AccountRecord
    let onSave: (_ issuer: String?, _ name: String, _ color: AccountColor) -> Void

    @State private var issuer: String
    @State private var name: String
    @State private var color: AccountColor

    @Environment(\.dismiss) private var dismiss

    init(
        record: AccountRecord,
        onSave: @escaping (_ issuer: String?, _ name: String, _ color: AccountColor) -> Void
    ) {
        self.record = record
        self.onSave = onSave
        _issuer = State(initialValue: record.metadata.issuer ?? "")
        _name = State(initialValue: record.metadata.name)
        _color = State(initialValue: record.metadata.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Service") {
                        TextField("GitHub", text: $issuer)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Account") {
                        TextField("you@example.com", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("These are just labels. Changing them does not affect the codes.")
                }

                Section("Colour") {
                    AccountColorGrid(selected: color) { color = $0 }
                }
            }
            .navigationTitle("Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(issuer, name, color)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Choosing a card colour, as a grid rather than the reference's nested list. Ten swatches
/// fit on one screen, so there is no reason to make anyone scroll a list of colour names.
struct AccountColorPicker: View {
    let selected: AccountColor
    let onPick: (AccountColor) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                AccountColorGrid(selected: selected) { color in
                    onPick(color)
                    dismiss()
                }
                .padding(Tokens.Spacing.large)
            }
            .background(Tokens.Surface.background)
            .navigationTitle("Colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The swatches on their own, with no screen around them.
///
/// Extracted so the edit screen can hold the colour inline while the shortcut from the
/// context menu still presents it as its own sheet. One grid, two frames around it, rather
/// than two grids that could drift apart.
struct AccountColorGrid: View {
    let selected: AccountColor
    let onPick: (AccountColor) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: Tokens.Spacing.medium)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Tokens.Spacing.medium) {
            ForEach(AccountColor.allCases, id: \.self) { color in
                Button {
                    onPick(color)
                } label: {
                    swatch(color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.rawValue.capitalized)
                .accessibilityAddTraits(color == selected ? [.isSelected] : [])
            }
        }
    }

    private func swatch(_ color: AccountColor) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Palette.gradient(for: color, in: colorScheme))
            .frame(height: 76)
            .overlay {
                if color == selected {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Tokens.OnCard.primary)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(color == selected ? 0.5 : 0), lineWidth: 2)
            }
    }
}

/// The palette as a single row, for the scan confirmation.
///
/// A strip rather than a separate screen because the card it recolours is directly above
/// it: the point is watching the choice land, and a picker that covers the card would hide
/// the thing being chosen for. The manual form uses the grid instead, where a disclosure
/// row is the native idiom and a strip would look foreign.
struct AccountColorStrip: View {
    @Binding var selection: AccountColor

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tokens.Spacing.small + 2) {
                ForEach(AccountColor.allCases, id: \.self) { color in
                    Button {
                        withAnimation(.snappy) { selection = color }
                    } label: {
                        Circle()
                            .fill(Palette.gradient(for: color, in: colorScheme))
                            .frame(width: 38, height: 38)
                            .overlay {
                                if color == selection {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(Tokens.OnCard.primary)
                                }
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Color.primary.opacity(color == selection ? 0.55 : 0),
                                        lineWidth: 2
                                    )
                                    .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.rawValue.capitalized)
                    .accessibilityAddTraits(color == selection ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Card colour")
    }
}

#Preview("Strip") {
    @Previewable @State var colour = AccountColor.indigo
    return AccountColorStrip(selection: $colour).padding()
}

#Preview("Edit") {
    EditAccountView(
        record: AccountRecord(
            id: UUID(),
            metadata: AccountMetadata(
                issuer: "GitHub",
                name: "octocat",
                generator: .totp(.standard),
                color: .blue,
                sortIndex: 0
            )
        ),
        onSave: { _, _, _ in }
    )
}

#Preview("Colour") {
    AccountColorPicker(selected: .indigo, onPick: { _ in })
}
