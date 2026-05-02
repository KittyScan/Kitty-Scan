import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Lightweight portrait pre-processor for share-card avatars.
///
/// Goal: take a user's phone photo and make it *pop* on a poster — not turn
/// it into something else. We do exactly one Core Image pass (`CIColorControls`)
/// to bump saturation a touch and lift contrast, then return. Real photo,
/// real cat, just a hair more vivid. ~25–40 ms on a 1024² source.
///
/// We deliberately do NOT do: pencil sketch, posterize, oil-paint, comic.
/// Those all looked off-brand on real cat photos in testing — and added
/// 200+ ms of latency for a worse result.
enum CatPortraitFilter {

    /// Square center-crop, downsample, and a subtle vibrance pass.
    /// Output side defaults to 1024 px — plenty for a 500 pt circle on the
    /// poster, light enough to render in well under 50 ms.
    static func polish(_ source: UIImage, outputSide: CGFloat = 1024) -> UIImage {
        let cropped = centerSquare(source) ?? source
        let resized = resize(cropped, side: outputSide)
        return enhance(resized)
    }

    /// Single-filter color tweak: saturation +12 %, contrast +5 %, brightness +2 %.
    /// All small numbers — the photo still looks like the original, just
    /// shows up better against printed/screen backgrounds.
    private static func enhance(_ source: UIImage) -> UIImage {
        guard let ci = CIImage(image: source) else { return source }
        let tweaked = ci.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.12,
            kCIInputContrastKey:   1.05,
            kCIInputBrightnessKey: 0.02,
        ])
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(tweaked, from: tweaked.extent) else { return source }
        return UIImage(cgImage: cg, scale: source.scale, orientation: source.imageOrientation)
    }

    // MARK: - geometry helpers

    private static func centerSquare(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let side = min(w, h)
        let crop = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
        guard let out = cg.cropping(to: crop) else { return nil }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func resize(_ image: UIImage, side: CGFloat) -> UIImage {
        let target = CGSize(width: side, height: side)
        // Pin to scale 1 so we render at exactly `side` pixels, not
        // `side × screenScale`. The card is authored in fixed pixel coords,
        // not retina logical points — matching scale 1 here is what avoids
        // the 9× pixel blow-up that hung the export.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
