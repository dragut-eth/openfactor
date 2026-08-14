import AVFoundation
import SwiftUI

/// The live camera, wrapped for SwiftUI.
///
/// `AVFoundation` decodes QR codes in the capture pipeline itself, so nothing here ever
/// holds a frame, writes one anywhere, or looks at pixels. The only thing that leaves this
/// view is the string a code contained.
///
/// The session runs on its own queue because starting one blocks, and blocking the main
/// thread is what makes a scanner feel broken before it has even seen anything.
struct CameraScannerView: UIViewControllerRepresentable {

    /// Called on the main actor with each payload, which for QR is whatever text the code
    /// carried. The view stops scanning after the first one it reports.
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onScan = onScan
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.openfactor.scanner")
    private var preview: AVCaptureVideoPreviewLayer?

    /// A capture session reports the same code many times a second while it stays in
    /// frame. Without this, one QR in view adds the account over and over.
    private var hasReported = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasReported = false
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    private func configureSession() {
        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            // No usable camera, which is the ordinary case in the simulator. The
            // surrounding view offers the photo and manual paths regardless, so this is
            // not a failure worth surfacing on its own.
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }

        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)

        // Only QR. Setting this after adding the output is required: the list of available
        // types is empty until then, and asking for a type that is not available traps.
        output.metadataObjectTypes = output.availableMetadataObjectTypes.filter { $0 == .qr }

        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        self.preview = preview
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput objects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasReported,
            let object = objects.first as? AVMetadataMachineReadableCodeObject,
            object.type == .qr,
            let payload = object.stringValue
        else {
            return
        }

        hasReported = true
        onScan?(payload)
    }
}

/// Whether the app may use the camera, and asking if it has not been decided.
enum CameraAccess {

    enum Status {
        case allowed
        case notAsked
        case denied
    }

    static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
