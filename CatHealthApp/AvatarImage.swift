import Foundation
import ImageIO
import UIKit

/// Memory-safe image decoder.
///
/// `UIImage(data:)` decompresses the full image into RAM (a 10MB JPEG → ~40MB RGBA).
/// When rendering many CatFace avatars during an export, that destroys memory and
/// the OS kills the app. ImageIO lets us decode a downsampled thumbnail directly,
/// using only the bytes needed for the target display size.
enum AvatarImage {

    /// Load a downsampled UIImage. `maxPixelSize` clamps the longest edge;
    /// pass target display size × 2 (retina) for crisp-but-small output.
    static func decode(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 64),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
