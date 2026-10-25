import UIKit
import ImageIO

/// Decodes photos at a bounded size so full-resolution camera images never
/// have to be held in memory just to show a thumbnail.
enum ImageDownsampler {

    /// Decode `data` with its longest side at most `maxPixelSize` points (scaled for the screen).
    static func image(from data: Data, maxPixelSize: CGFloat, scale: CGFloat = 1) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize * scale
        ] as [CFString: Any] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// Re-encode photo data as a JPEG no larger than `maxPixelSize`, for storage.
    static func storageJPEG(from data: Data, maxPixelSize: CGFloat = 2048, quality: CGFloat = 0.8) -> Data? {
        image(from: data, maxPixelSize: maxPixelSize)?.jpegData(compressionQuality: quality)
    }
}
