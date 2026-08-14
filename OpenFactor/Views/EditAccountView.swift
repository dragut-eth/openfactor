import OpenFactorCore
import SwiftUI

/// Renaming an account.
///
/// Only the two fields a person chose. The algorithm, digits, period, and counter came
/// from the service and changing them here would not change what the service expects, it
/// would just stop the codes matching. Those are set once, at enrolment.
struct EditAccountView: View {
    let record: AccountRecord
    let onSave: (_ issuer: String?, _ name: String) -> Void

    @State private var issuer: String
    @State private var name: String

    @Environment(\.dismiss) private var dismiss

    init(record: AccountRecord, onSave: @escaping (_ issuer: String?, _ name: String) -> Void) {
        self.record = record
        self.onSave = onSave
        _issuer = State(initialValue: record.metadata.issuer ?? "")
        _name = State(initialValue: record.metadata.name)
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
            }
            .navigationTitle("Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(issuer, name)
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: Tokens.Spacing.medium)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Tokens.Spacing.medium) {
                    ForEach(AccountColor.allCases, id: \.self) { color in
                        Button {
                            onPick(color)
                            dismiss()
                        } label: {
                            swatch(color)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.rawValue.capitalized)
                        .accessibilityAddTraits(color == selected ? [.isSelected] : [])
                    }
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
        onSave: { _, _ in }
    )
}

#Preview("Colour") {
    AccountColorPicker(selected: .indigo, onPick: { _ in })
}
