import CoreImage
import Foundation

/// Reads QR codes out of a still image.
///
/// The camera path does not come through here: `AVFoundation` decodes its own frames.
/// This is for the photo import path, which exists because a service enrolling you on the
/// phone you are holding often shows the QR on that same screen, leaving no second device
/// to point a camera at. Screenshot, import, done.
///
/// Nothing here touches the network or the photo library. It is handed one image that the
/// user picked and returns whatever text is encoded in it.
enum QRDecoder {

    /// Every QR payload found in an image, in no particular order.
    ///
    /// Returns all of them rather than the first, because a screenshot of an enrollment
    /// page can easily contain more than one code, and picking one at random would be a
    /// coin toss over which account gets added.
    static func payloads(in image: CIImage) -> [String] {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )

        let features = detector?.features(in: image) ?? []

        return features
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .filter { !$0.isEmpty }
    }

    static func payloads(in data: Data) -> [String] {
        guard let image = CIImage(data: data) else { return [] }
        return payloads(in: image)
    }
}
