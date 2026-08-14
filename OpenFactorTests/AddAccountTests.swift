import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import OpenFactorCore
import Testing

@testable import OpenFactor

/// Builds a real QR code image, so the decoder can be tested against the thing it will
/// actually meet rather than against a fixture someone drew once.
private func qrImage(encoding text: String) -> CIImage {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"

    // Scaled up, because the detector needs more than the handful of pixels the generator
    // produces at its native size.
    return filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
}

@Suite("QR decoding")
struct QRDecoderTests {

    /// The whole import path in one assertion: a QR code goes in, an account comes out,
    /// with no camera anywhere.
    @Test("A generated QR code decodes back to the account it encodes")
    func roundTripsAnAccount() throws {
        let uri = "otpauth://totp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=8"

        let payloads = QRDecoder.payloads(in: qrImage(encoding: uri))
        #expect(payloads == [uri])

        let account = try OTPAuthURI.account(from: try #require(payloads.first))
        #expect(account.issuer == "GitHub")
        #expect(account.name == "octocat")
        #expect(account.generator.digits == .eight)
    }

    @Test("An image with no QR code yields nothing")
    func findsNothingInAPlainImage() {
        let blank = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(QRDecoder.payloads(in: blank).isEmpty)
    }

    @Test("Data that is not an image yields nothing rather than crashing")
    func survivesGarbageData() {
        #expect(QRDecoder.payloads(in: Data([0x00, 0x01, 0x02])).isEmpty)
        #expect(QRDecoder.payloads(in: Data()).isEmpty)
    }

    /// Codes carrying something other than a setup URI decode fine and are rejected later,
    /// by the parser, with its own message.
    @Test("A QR code holding anything else still decodes")
    func decodesNonOTPPayloads() {
        #expect(QRDecoder.payloads(in: qrImage(encoding: "https://example.com")) == ["https://example.com"])
    }
}

@MainActor
@Suite("Adding an account")
struct AddAccountViewModelTests {

    private static let validURI =
        "otpauth://totp/GitHub:octocat?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=GitHub"

    // MARK: - Scanning

    /// A scan must not save anything. A QR code is unreadable to a human, so the
    /// confirmation step is the only chance to see what was in it.
    @Test("Scanning moves to confirmation without saving")
    func scanningDoesNotSave() throws {
        let store = InMemorySecretStore()
        let model = AddAccountViewModel(store: store)

        model.handleScan(Self.validURI)

        guard case let .confirming(account) = model.stage else {
            Issue.record("Expected to be confirming, was \(model.stage)")
            return
        }

        #expect(account.issuer == "GitHub")
        #expect(try store.records().readable.isEmpty, "Nothing may be saved before confirmation")
    }

    @Test("Confirming saves the account")
    func confirmingSaves() throws {
        let store = InMemorySecretStore()
        let model = AddAccountViewModel(store: store)

        model.handleScan(Self.validURI)
        model.confirm()

        let saved = try store.records().readable
        #expect(saved.count == 1)
        #expect(saved.first?.metadata.issuer == "GitHub")
        #expect(model.stage == .added)
    }

    /// The preview is the point of the confirmation step: it is checked against what the
    /// service is showing while the enrollment page is still open.
    @Test("The confirmation shows the code the account really produces")
    func previewMatchesTheRFCVector() {
        let model = AddAccountViewModel(store: InMemorySecretStore())
        model.handleScan(
            "otpauth://totp/RFC:6238?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8"
        )

        #expect(model.previewCode(at: Date(timeIntervalSince1970: 59)) == "94287082")
        #expect(model.previewSecondsRemaining(at: Date(timeIntervalSince1970: 59)) == 1)
    }

    @Test("The colour starts as the one suggested by the issuer")
    func suggestsAColourFromTheIssuer() {
        let model = AddAccountViewModel(store: InMemorySecretStore())
        model.handleScan(Self.validURI)

        #expect(model.color == AccountColor.suggested(forIssuer: "GitHub"))
    }

    /// The suggestion is a starting point, not the only option, and what the user picks on
    /// the confirmation screen is what gets stored.
    @Test("A chosen colour is the one saved")
    func savesTheChosenColour() throws {
        let store = InMemorySecretStore()
        let model = AddAccountViewModel(store: store)

        model.handleScan(Self.validURI)
        model.color = .pink
        model.confirm()

        #expect(try store.records().readable.first?.metadata.color == .pink)
    }

    // MARK: - Rejection

    /// The parser's errors are already specific, so they are shown rather than replaced
    /// with something vaguer.
    @Test(
        "A code that is not a setup code is refused with a reason",
        arguments: [
            "https://example.com",
            "otpauth://totp/A",
            "otpauth://steam/A?secret=JBSWY3DPEHPK3PXP",
            "",
        ]
    )
    func refusesBadPayloads(payload: String) {
        let model = AddAccountViewModel(store: InMemorySecretStore())
        model.handleScan(payload)

        #expect(model.stage == .scanning)
        #expect(model.problem != nil)
    }

    @Test("Confirming with nothing scanned does nothing")
    func confirmingNothingDoesNothing() throws {
        let store = InMemorySecretStore()
        let model = AddAccountViewModel(store: store)

        model.confirm()

        #expect(model.stage == .scanning)
        #expect(try store.records().readable.isEmpty)
    }

    /// A capture session reports the same code many times a second while it stays in
    /// frame. The scanner stops after the first, and this is the second line of defence.
    @Test("A repeated scan does not replace the pending account")
    func ignoresRepeatedScansWhileConfirming() {
        let model = AddAccountViewModel(store: InMemorySecretStore())

        model.handleScan(Self.validURI)
        model.handleScan("otpauth://totp/Other:someone?secret=JBSWY3DPEHPK3PXP&issuer=Other")

        guard case let .confirming(account) = model.stage else {
            Issue.record("Expected to still be confirming")
            return
        }

        #expect(account.issuer == "GitHub")
    }

    @Test("Scanning again clears the problem and goes back to looking")
    func scanAgainResets() {
        let model = AddAccountViewModel(store: InMemorySecretStore())

        model.handleScan("nonsense")
        #expect(model.problem != nil)

        model.scanAgain()
        #expect(model.problem == nil)
        #expect(model.stage == .scanning)
    }

    // MARK: - Images

    @Test("Importing a picture of a code works end to end")
    func importsFromAnImage() throws {
        let model = AddAccountViewModel(store: InMemorySecretStore())
        let context = CIContext()
        let image = qrImage(encoding: Self.validURI)
        let data = try #require(context.pngRepresentation(
            of: image,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ))

        model.handleImage(data)

        guard case let .confirming(account) = model.stage else {
            Issue.record("Expected to be confirming, was \(model.stage). Problem: \(model.problem ?? "none")")
            return
        }

        #expect(account.issuer == "GitHub")
    }

    @Test("An image with no code says so")
    func reportsAnImageWithNoCode() {
        let model = AddAccountViewModel(store: InMemorySecretStore())
        model.handleImage(Data([0x00, 0x01]))

        #expect(model.stage == .scanning)
        #expect(model.problem?.contains("No QR code") == true)
    }
}
