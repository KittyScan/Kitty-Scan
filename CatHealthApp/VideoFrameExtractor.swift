import UIKit
import AVFoundation

/// Extracts 3 representative keyframes from a user-supplied video and
/// composites them side-by-side into a single PNG. The composite is what
/// gets sent to Claude — vision models accept one image, not a stream, and
/// 3 frames at 0% / 50% / 100% capture the meaningful temporal info for a
/// 30-second cat video without ballooning the upload.
///
/// Why this design over uploading the whole video:
///   • Claude vision is single-frame; we'd have to rasterize anyway.
///   • A 30s 720p video is ~10–30 MB; a single 1920×640 PNG is ~500 KB.
///   • Composite keeps a single API call → same cost as a photo.
enum VideoFrameExtractor {

    enum Error: Swift.Error {
        case unreadable
        case durationUnavailable
        case frameExtractionFailed
        case compositionFailed
        case tooLong(seconds: Double)
    }

    static let maxDurationSeconds: Double = 30

    /// Extract 3 keyframes (start / middle / end) and stitch into a
    /// 3-up horizontal composite. Returns the PNG data ready for upload.
    static func extractCompositeFrame(from videoURL: URL) async throws -> UIImage {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw Error.durationUnavailable
        }
        if durationSeconds > maxDurationSeconds {
            throw Error.tooLong(seconds: durationSeconds)
        }

        // Pick three time points. For very short videos clamp slightly inside
        // the boundaries — frame 0 of some encoders is black/empty.
        let safeStart = max(0.05, 0)
        let safeEnd = max(0, durationSeconds - 0.1)
        let times: [CMTime] = [
            CMTime(seconds: safeStart, preferredTimescale: 600),
            CMTime(seconds: durationSeconds / 2, preferredTimescale: 600),
            CMTime(seconds: safeEnd, preferredTimescale: 600),
        ]

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true   // honor portrait/landscape orientation
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var frames: [UIImage] = []
        for time in times {
            do {
                let cgImage = try await generator.image(at: time).image
                frames.append(UIImage(cgImage: cgImage))
            } catch {
                // Bail rather than upload partial — one missing frame would
                // change what the AI sees and confuse the analysis.
                throw Error.frameExtractionFailed
            }
        }

        return try compositeHorizontal(frames: frames)
    }

    // MARK: - Composition

    /// 3 frames stitched horizontally with a thin separator strip between.
    /// Each frame is letterboxed into a uniform tile so the final image is
    /// a clean rectangle regardless of source aspect ratio.
    ///
    /// Tile size budget reasoning: Claude vision charges roughly
    /// `pixels / 750` tokens. We want the composite to cost about the same
    /// as a normal photo (~1568 long-side after `ClaudeService` downsamples).
    /// So: 3 tiles × 480 + separators ≈ 1456 long side, fits exactly inside
    /// the photo budget. Smaller tiles don't show enough detail per pose;
    /// larger ones double the cost vs a still photo for marginal quality.
    private static func compositeHorizontal(frames: [UIImage]) throws -> UIImage {
        guard frames.count == 3 else { throw Error.compositionFailed }

        let tileSide: CGFloat = 480
        let separator: CGFloat = 4
        let canvasWidth = tileSide * 3 + separator * 2  // 1448
        let canvasSize = CGSize(width: canvasWidth, height: tileSide)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        let composite = renderer.image { ctx in
            // Black background — separator strips bleed through this.
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            for (i, frame) in frames.enumerated() {
                let originX = (tileSide + separator) * CGFloat(i)
                let tileRect = CGRect(x: originX, y: 0, width: tileSide, height: tileSide)
                drawAspectFilled(frame, in: tileRect)
            }
        }
        return composite
    }

    /// Aspect-fill draw — same behavior as UIView's `.scaleAspectFill` content
    /// mode. Avoids letterboxing inside each tile.
    private static func drawAspectFilled(_ image: UIImage, in rect: CGRect) {
        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return }
        let scale = max(rect.width / imgW, rect.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawRect = CGRect(
            x: rect.midX - drawW / 2,
            y: rect.midY - drawH / 2,
            width: drawW, height: drawH
        )
        // Clip to the tile so over-sized aspect-fill doesn't bleed
        // into the next tile.
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: drawRect)
        context.restoreGState()
    }
}
