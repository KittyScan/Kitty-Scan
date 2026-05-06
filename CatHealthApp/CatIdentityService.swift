import Foundation
import UIKit
import Vision

/// Decides whether a freshly taken photo is the same cat as the active profile,
/// using Apple's Vision framework. The whole comparison runs on-device — no
/// extra network calls, no extra cost.
///
/// We use `VNGenerateImageFeaturePrintRequest` (Apple's general-purpose image
/// embedding) and pick the *minimum* distance between the new photo and any
/// reference photo of the active cat (avatar + recent records). Min distance is
/// the right reduction here: if the new photo matches *any* prior photo of this
/// cat, that's strong evidence it's the same cat — even if pose/lighting drift
/// across other references.
///
/// Thresholds were picked empirically:
///   - < 1.2  same cat  (different angles of one cat usually fall here)
///   - > 2.0  different cat  (a different cat almost always crosses this)
///   - in between → `.uncertain` (don't pester the user; saving silently under
///     the active cat is the safe default).
///
/// Distances depend on Vision's revision; if Apple bumps the model these may
/// need re-tuning. We pin to revision 1 to keep the thresholds stable across
/// iOS versions.
@MainActor
final class CatIdentityService {
    static let shared = CatIdentityService()

    // Empirical L2 distances for VNGenerateImageFeaturePrintRequest revision 1:
    //   same cat, varied angles/lighting: typically 0.5–1.2
    //   different cat, same breed:        typically 1.4–2.2
    //   different cat, different breed:   typically 1.8–4.0+
    //
    // Calibration history:
    //   v1: 1.0 / 1.5 — too strict. Same-cat-different-angle photos at 1.1-1.4
    //       fell into 'uncertain'; angle-shift to 1.5+ falsely fired the
    //       'different cat' alert. Real users were getting prompted on their
    //       own cat constantly.
    //   v2 (current): 1.2 / 1.8 — covers the same-cat 0.5-1.2 range entirely
    //       and pushes the 'different cat' floor above the same-cat upper
    //       bound, eliminating the cross-band false positive. Uncertain band
    //       (1.2-1.8) silently saves under active profile (safer default).
    private static let sameCatMaxDistance:      Float = 1.2
    private static let differentCatMinDistance: Float = 1.8

    enum Decision {
        case sameCat
        case differentCat
        case uncertain
    }

    struct Verdict {
        let decision: Decision
        let minDistance: Float?
        let referenceCount: Int
    }

    /// Compare `newImage` against the active cat's avatar + last N record photos.
    /// Returns `.uncertain` when there aren't enough references to be confident.
    func compare(newImage: UIImage, against cat: Cat, recentLimit: Int = 5) async -> Verdict {
        let references: [Data] = {
            var data: [Data] = []
            if let avatar = cat.avatarData { data.append(avatar) }
            let recordImages = cat.records
                .sorted { $0.date > $1.date }
                .prefix(recentLimit)
                .compactMap { $0.imageData }
            data.append(contentsOf: recordImages)
            return data
        }()

        // Need at least one reference photo to even attempt a comparison.
        guard !references.isEmpty else {
            return Verdict(decision: .uncertain, minDistance: nil, referenceCount: 0)
        }

        let referenceImages = references.compactMap { UIImage(data: $0) }
        return await Task.detached(priority: .userInitiated) { [newImage] in
            await Self.computeVerdict(newImage: newImage, references: referenceImages)
        }.value
    }

    private static func computeVerdict(newImage: UIImage, references: [UIImage]) async -> Verdict {
        guard let newPrint = featurePrint(from: newImage) else {
            return Verdict(decision: .uncertain, minDistance: nil, referenceCount: references.count)
        }

        var minDistance: Float = .greatestFiniteMagnitude
        var compared = 0
        for ref in references {
            guard let refPrint = featurePrint(from: ref) else { continue }
            var distance: Float = 0
            do {
                try newPrint.computeDistance(&distance, to: refPrint)
                compared += 1
                if distance < minDistance { minDistance = distance }
            } catch {
                continue
            }
        }

        guard compared > 0 else {
            return Verdict(decision: .uncertain, minDistance: nil, referenceCount: references.count)
        }

        let decision: Decision = {
            if minDistance < sameCatMaxDistance      { return .sameCat }
            if minDistance > differentCatMinDistance { return .differentCat }
            return .uncertain
        }()

        return Verdict(decision: decision, minDistance: minDistance, referenceCount: compared)
    }

    private static func featurePrint(from image: UIImage) -> VNFeaturePrintObservation? {
        guard let cg = image.cgImage ?? CIImage(image: image).flatMap({
            CIContext().createCGImage($0, from: $0.extent)
        }) else { return nil }

        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image), options: [:])
        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    private static func cgOrientation(_ image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
