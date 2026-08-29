import CoreImage
import Foundation
import ImageIO
import OpenFactorCore

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

    /// Every QR payload in a file's bytes, decoded at a bounded size.
    ///
    /// **This is the only place image bytes become an image**, in the app and in the share
    /// extension both, which is why the bound lives here rather than at a call site. The
    /// extension deliberately carries bytes without decoding them, so every decode in the
    /// project arrives through this function.
    static func payloads(in data: Data) -> [String] {
        guard let image = boundedImage(from: data) else { return [] }
        return payloads(in: image)
    }

    /// An image decoded at a size this app chose, or nothing.
    ///
    /// **The size is read before anything is decoded**, which is the whole point. `CIImage(data:)`
    /// took whatever the file expanded to, and a file's length on disk says nothing about that: a
    /// mostly flat 8000x8000 PNG is a few hundred kilobytes and a quarter of a gigabyte of pixels.
    /// `CGImageSourceCopyPropertiesAtIndex` answers from the header, without allocating the
    /// bitmap it is deciding about.
    ///
    /// **Then it downsamples rather than refusing.** Refusing on dimensions alone would have to
    /// reject a full frame from the phone the person is holding, and "that image is too large"
    /// is a miserable answer to somebody photographing a QR code with the camera Apple sold them.
    /// Asking ImageIO for a thumbnail bounds the work whatever the source measures, and a QR
    /// small enough to be lost at this size was never going to be detected at any size.
    private static func boundedImage(from data: Data) -> CIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0
        else { return nil }

        let properties =
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0

        // A header that will not say how big it is does not get to find out by being decoded.
        guard width > 0, height > 0 else { return nil }
        guard width * height <= ImportLimits.maximumImagePixels else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: ImportLimits.workingImageMaxDimension,
            // Orientation applied here rather than carried, so a QR in a photograph taken
            // sideways is the right way up by the time the detector sees it.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        return CIImage(cgImage: image)
    }
}
