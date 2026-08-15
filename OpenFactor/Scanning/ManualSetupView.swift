import Combine
import OpenFactorCore
import SwiftUI

/// Entering an account by hand.
///
/// The simple path is three fields, matching the reference. Everything that a QR code
/// would have carried silently lives behind Advanced, collapsed, because most services
/// use the defaults and the ones that do not will tell you exactly what to change.
struct ManualSetupView: View {

    @State private var model: ManualSetupViewModel
    @State private var now = Date()
    @State private var showsAdvanced = false
    @State private var isChoosingColour = false

    @Environment(\.dismiss) private var dismiss

    /// Whether the secret is shown in the clear. Off by default, and never remembered.
    @State private var isSecretRevealed = false
    @Environment(\.colorScheme) private var colorScheme

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let onAdded: () -> Void

    init(store: any SecretStore, onAdded: @escaping () -> Void) {
        _model = State(initialValue: ManualSetupViewModel(store: store))
        self.onAdded = onAdded
    }

    var body: some View {
        Form {
            accountSection
            advancedSection
            previewSection

            if let failure = model.saveFailure {
                Section {
                    Text(failure).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Enter details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if model.save() {
                        onAdded()
                        dismiss()
                    }
                }
                .disabled(!model.canSave)
            }
        }
        .onReceive(tick) { now = $0 }
        .sheet(isPresented: $isChoosingColour) {
            AccountColorPicker(selected: model.color) { model.color = $0 }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            LabeledContent("Secret key") {
                HStack(spacing: Tokens.Spacing.small) {
                    // Secure entry, because this is the secret itself. A plain field is
                    // readable over a shoulder and can reach the keyboard's learning,
                    // which is a copy of the secret in a place nobody audits.
                    Group {
                        if isSecretRevealed {
                            TextField("Paste or type it", text: $model.secretText)
                        } else {
                            SecureField("Paste or type it", text: $model.secretText)
                        }
                    }
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospaced())

                    // Deliberate, because a mistyped secret fails at a login rather than
                    // here, and checking it is the only defence against that.
                    Button {
                        isSecretRevealed.toggle()
                    } label: {
                        Image(systemName: isSecretRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(isSecretRevealed ? "Hide the secret" : "Show the secret")
                }
            }

            LabeledContent("Service") {
                TextField("GitHub", text: $model.issuer)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Account") {
                TextField("you@example.com", text: $model.name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .multilineTextAlignment(.trailing)
            }

            // A row opening the grid, rather than the strip the scan screen uses. In a
            // Form a disclosure row is the native idiom, and the preview card is far
            // enough down that a strip would not be next to what it changes anyway.
            Button {
                isChoosingColour = true
            } label: {
                LabeledContent("Colour") {
                    HStack(spacing: Tokens.Spacing.small) {
                        Circle()
                            .fill(Palette.gradient(for: model.color, in: colorScheme))
                            .frame(width: 22, height: 22)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Colour, \(model.color.rawValue)")
        } header: {
            Text("Account")
        } footer: {
            if let problem = model.secretProblem {
                Text(problem).foregroundStyle(.red)
            } else {
                Text("The service shows the secret key when it cannot show you a QR code.")
            }
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                Picker("Algorithm", selection: $model.algorithm) {
                    ForEach(OTPAlgorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }

                Picker("Digits", selection: $model.digits) {
                    ForEach(OTPDigits.allCases, id: \.self) { Text(String($0.rawValue)).tag($0) }
                }

                Toggle("Counter based", isOn: $model.isCounterBased)

                if model.isCounterBased {
                    LabeledContent("Counter") {
                        TextField("0", text: $model.counterText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    Stepper("Refreshes every \(model.period)s", value: $model.period, in: 5...300, step: 5)
                }
            }
        } footer: {
            if let problem = model.counterProblem ?? model.periodProblem {
                Text(problem).foregroundStyle(.red)
            } else if showsAdvanced {
                Text("Leave these alone unless the service told you otherwise. Almost none do.")
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let code = model.previewCode(at: now) {
            Section {
                AccountCard(
                    model: AccountCard.Model(
                        // The card is a preview of an account that does not exist yet, so
                        // the fields can legitimately be empty while someone is still
                        // typing. A placeholder keeps it from rendering as blank lines.
                        issuer: previewIssuer,
                        name: model.name,
                        code: code,
                        secondsRemaining: model.previewSecondsRemaining(at: now),
                        period: model.period,
                        color: model.color
                    )
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("Preview")
            } footer: {
                Text("Check this against the code the service is showing before you save.")
            }
        }
    }

    private var previewIssuer: String {
        let issuer = model.issuer.trimmingCharacters(in: .whitespaces)
        let name = model.name.trimmingCharacters(in: .whitespaces)

        if !issuer.isEmpty { return issuer }
        if !name.isEmpty { return name }
        return "New account"
    }
}

#Preview {
    NavigationStack {
        ManualSetupView(store: InMemorySecretStore(), onAdded: {})
    }
}
