import Combine
import OpenFactorCore
import PhotosUI
import SwiftUI

/// The add flow: point the camera at a code, or import a picture of one, then confirm.
struct AddAccountView: View {

    @State private var model: AddAccountViewModel
    @State private var cameraStatus = CameraAccess.status
    @State private var photoItem: PhotosPickerItem?

    @Environment(\.dismiss) private var dismiss

    private let store: any SecretStore
    let onAdded: () -> Void

    init(store: any SecretStore, onAdded: @escaping () -> Void) {
        self.store = store
        _model = State(initialValue: AddAccountViewModel(store: store))
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            content
                // No title. Cancel on one side and Enter manually on the other leave no
                // room for one, and it truncated to "Add acc...". The two buttons already
                // say what the screen is.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }

                    // The reference puts this here too. It is the way out for services
                    // that print a secret instead of showing a code, and the way out when
                    // the camera is unavailable.
                    // Trailing rather than `.confirmationAction`, which renders bold and
                    // made this read as the primary action next to a regular weight
                    // Cancel. Scanning is the primary action; this is the way out of it.
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Enter manually") {
                            ManualSetupView(store: store) {
                                onAdded()
                                dismiss()
                            }
                        }
                    }
                }
                .task {
                    if cameraStatus == .notAsked {
                        _ = await CameraAccess.request()
                        cameraStatus = CameraAccess.status
                    }
                }
                .onChange(of: model.stage) { _, stage in
                    if stage == .added {
                        onAdded()
                        dismiss()
                    }
                }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            model.handleImage(data)
                        } else {
                            model.handleImage(Data())
                        }
                        photoItem = nil
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .scanning:
            scanner
        case let .confirming(account):
            ConfirmAccountView(
                account: account,
                color: model.suggestedColor,
                model: model
            )
        case .added:
            ProgressView()
        }
    }

    // MARK: - Scanning

    private var scanner: some View {
        VStack(spacing: 0) {
            ZStack {
                if cameraStatus == .allowed {
                    CameraScannerView { model.handleScan($0) }
                        .ignoresSafeArea(edges: .horizontal)
                    ScanningFrame()
                } else {
                    CameraUnavailableView(status: cameraStatus)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)

            footer
        }
        .alert(
            "That code could not be used",
            isPresented: Binding(
                get: { model.problem != nil },
                set: { if !$0 { model.dismissProblem() } }
            ),
            actions: {
                Button("Try again") { model.scanAgain() }
            },
            message: {
                Text(model.problem ?? "")
            }
        )
    }

    private var footer: some View {
        VStack(spacing: Tokens.Spacing.medium) {
            Text("Point the camera at the QR code the service is showing you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Import a picture of a code", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
        }
        .padding(Tokens.Spacing.large)
        .frame(maxWidth: .infinity)
        .background(Tokens.Surface.background)
    }
}

/// A frame over the camera, so it is obvious the app is looking rather than frozen. The
/// reference shows a bare camera feed, which gives no feedback at all.
private struct ScanningFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
            .stroke(.white.opacity(0.85), lineWidth: 3)
            .frame(width: 230, height: 230)
            .shadow(radius: 8)
            .accessibilityHidden(true)
    }
}

/// Camera denied, or no camera at all. Both need a way forward rather than a dead end.
private struct CameraUnavailableView: View {
    let status: CameraAccess.Status

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera.fill")
        } description: {
            Text(explanation)
        } actions: {
            if status == .denied, let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(settings) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
    }

    private var title: String {
        status == .denied ? "Camera access is off" : "No camera available"
    }

    private var explanation: String {
        status == .denied
            ? "OpenFactor needs the camera to scan a setup code. You can turn it on in Settings, or import a picture of the code instead."
            : "This device has no camera the app can use. You can import a picture of the code instead."
    }
}

// MARK: - Confirming

/// What was in the code, and the code it produces right now.
private struct ConfirmAccountView: View {
    let account: OTPAccount
    let color: AccountColor
    let model: AddAccountViewModel

    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Spacing.large) {
                Text("Check this against what the service is showing, then add it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                AccountCard(
                    model: AccountCard.Model(
                        issuer: account.issuer ?? account.name,
                        name: account.name,
                        code: model.previewCode(at: now) ?? "------",
                        secondsRemaining: model.previewSecondsRemaining(at: now),
                        period: period,
                        color: color
                    )
                )

                VStack(spacing: Tokens.Spacing.small) {
                    Button {
                        model.confirm()
                    } label: {
                        Text("Add account").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Scan a different code") { model.scanAgain() }
                }
            }
            .padding(Tokens.Spacing.large)
        }
        .background(Tokens.Surface.background)
        .onReceive(tick) { now = $0 }
    }

    private var period: Int {
        if case let .totp(configuration) = account.generator { configuration.period } else { 0 }
    }
}

#Preview("Confirming") {
    AddAccountView(store: InMemorySecretStore(), onAdded: {})
}
