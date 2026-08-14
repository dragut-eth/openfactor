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

    @Environment(\.dismiss) private var dismiss

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
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            LabeledContent("Secret key") {
                TextField("Paste or type it", text: $model.secretText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospaced())
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
                        color: model.suggestedColor
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
