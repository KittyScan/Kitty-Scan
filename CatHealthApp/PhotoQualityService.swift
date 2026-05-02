import Foundation
import UIKit
import Vision
import CoreImage

/// Pre-flight check on a photo before we spend an Anthropic API call on it.
///
/// Two cheap on-device signals:
///   1. Vision's animal-recognition request — if there's no cat (or only weak
///      confidence), the analysis report would just say "no cat detected"
///      anyway, so we surface that *now* and save the round-trip.
///   2. Average luminance — extremely dark or extremely bright photos can't
///      be analyzed reliably (blown-out fur, invisible eye detail).
///
/// Both run in well under 100ms on-device. We deliberately *don't* fail-closed:
/// callers receive a verdict and decide whether to block, warn, or proceed.
@MainActor
final class PhotoQualityService {
    static let shared = PhotoQualityService()

    enum Issue {
        case noCatDetected
        case tooDark      // average luminance < 0.20
        case tooBright    // average luminance > 0.92
        case tooBlurry    // Laplacian variance < blurThreshold
    }

    /// Variance threshold below which we treat a photo as blurry. Empirically:
    /// crisp phone photos sit around 200–2000+; clearly out-of-focus ones
    /// drop under 50. We pick 60 as a generous cutoff so we don't pester
    /// users about photos that are merely "soft" rather than truly blurry.
    private let blurThreshold: Double = 60

    func check(image: UIImage) async -> Issue? {
        // Run brightness first — synchronous and very fast.
        if let l = luminance(of: image) {
            if l < 0.20 { return .tooDark }
            if l > 0.92 { return .tooBright }
        }

        // Blur check — runs on a downsampled grayscale buffer in Swift, so
        // we keep it on a background priority. ~5–15ms on a 128×128 buffer.
        if let v = laplacianVariance(of: image), v < blurThreshold {
            return .tooBlurry
        }

        // Vision animal recognition — async, ~50–80ms.
        return await Task.detached(priority: .userInitiated) {
            await Self.detectCat(in: image)
        }.value
    }

    /// Sharpness proxy via Laplacian-of-grayscale variance. Lower = blurrier.
    /// Downsampled to 128×128 for speed; resolution loss doesn't hurt blur
    /// detection because real out-of-focus blur dominates at every scale.
    private func laplacianVariance(of image: UIImage, side: Int = 128) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let w = side, h = side
        var pixels = [UInt8](repeating: 0, count: w * h)
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Apply Laplacian kernel to interior pixels and accumulate variance.
        // Single pass: keep running sum + sum-of-squares to get variance
        // without storing the full convolution buffer.
        var sum = 0.0
        var sumSq = 0.0
        var count = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c  = Int(pixels[y * w + x])
                let up = Int(pixels[(y - 1) * w + x])
                let dn = Int(pixels[(y + 1) * w + x])
                let lf = Int(pixels[y * w + (x - 1)])
                let rt = Int(pixels[y * w + (x + 1)])
                let l = Double(4 * c - up - dn - lf - rt)
                sum += l
                sumSq += l * l
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let mean = sum / Double(count)
        return sumSq / Double(count) - mean * mean
    }

    private static func detectCat(in image: UIImage) async -> Issue? {
        guard let cg = image.cgImage else { return nil }

        let request = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Vision failure is *not* a quality issue — let the call go through.
            return nil
        }

        guard let observations = request.results else { return .noCatDetected }
        let catFound = observations.contains { obs in
            obs.labels.contains { $0.identifier.lowercased().contains("cat") && $0.confidence > 0.3 }
        }
        return catFound ? nil : .noCatDetected
    }

    /// Average luminance in 0...1, computed from a downsampled CIImage.
    /// Uses the CIAreaAverage filter — Core Image runs this on the GPU.
    private func luminance(of image: UIImage) -> Double? {
        guard let ci = CIImage(image: image) else { return nil }
        let extent = ci.extent
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ])
        guard let out = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        ctx.render(out, toBitmap: &bitmap,
                   rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8,
                   colorSpace: nil)
        // Rec. 709 luminance from sRGB 0–255 channels.
        let r = Double(bitmap[0]) / 255
        let g = Double(bitmap[1]) / 255
        let b = Double(bitmap[2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
