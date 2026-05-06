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
    //       'different cat' alert. Users got prompted on their own cat constantly.
    //   v2: 1.2 / 1.8 — better but still false-positives on real-world photos.
    //       Strong angle/lighting shifts (close-up vs full-body, sun vs indoor)
    //       routinely hit 1.8-2.4 on the SAME cat. The Vision feature print
    //       isn't fine-tuned for cats, so same-cat-different-pose can sit on
    //       top of different-cat-same-breed.
    //   v3 (current): 1.2 / 2.5 — only fire the 'different cat' alert when
    //       distance is BIG enough to be unambiguous. False-negative cost
    //       (a friend's cat saves under the wrong profile) is rare AND
    //       user-recoverable via long-press → delete; false-positive cost
    //       (own cat flagged daily) is common AND annoying. We tilt toward
    //       silence. Uncertain band (1.2-2.5) saves silently under the
    //       active profile.
    private static let sameCatMaxDistance:      Float = 1.2
    private static let differentCatMinDistance: Float = 2.5

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
        let perCatFloor = Self.learnedToleranceFloor(for: cat)
        return await Task.detached(priority: .userInitiated) { [newImage] in
            await Self.computeVerdict(newImage: newImage, references: referenceImages, perCatFloor: perCatFloor)
        }.value
    }

    private static func computeVerdict(newImage: UIImage, references: [UIImage], perCatFloor: Float) async -> Verdict {
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

        // The 'different cat' floor is the MAX of the global default and any
        // per-cat learned floor. If the user has overridden the alert ("same
        // cat, save anyway") in the past at distance D, perCatFloor ≥ D + 0.1
        // so the same shot won't false-positive again. Per-cat floor never
        // shrinks the alert band — only widens it.
        let effectiveDifferentFloor = max(differentCatMinDistance, perCatFloor)

        let decision: Decision = {
            if minDistance < sameCatMaxDistance       { return .sameCat }
            if minDistance > effectiveDifferentFloor  { return .differentCat }
            return .uncertain
        }()

        return Verdict(decision: decision, minDistance: minDistance, referenceCount: compared)
    }

    // MARK: - Per-cat learned tolerance
    //
    // When the user dismisses a 'different cat' alert by choosing 'same cat,
    // save anyway', that's the strongest possible signal that the threshold
    // was wrong for THIS cat. We store the highest such distance per-cat in
    // UserDefaults, and `compare()` reads it back as the floor on subsequent
    // comparisons. Net effect: each cat naturally trains to its own tolerance
    // (e.g. fluffy cats with extreme pose variation end up with a higher
    // floor than uniformly-coated cats).

    private static func toleranceKey(for cat: Cat) -> String {
        "identity.tolerance.\(cat.id.uuidString)"
    }

    /// Read the learned per-cat tolerance floor. Returns 0 (no boost) when
    /// the user has never overridden an alert for this cat.
    static func learnedToleranceFloor(for cat: Cat) -> Float {
        let raw = UserDefaults.standard.float(forKey: toleranceKey(for: cat))
        return raw  // UserDefaults.float returns 0.0 when key absent — exactly what we want.
    }

    /// Called from CameraView when the user clicks 'same cat, save anyway'
    /// on the mismatch alert. Records the observed distance + small margin
    /// as the new per-cat floor (only if it would widen the band).
    static func recordOverrideAsSameCat(cat: Cat, observedDistance: Float) {
        let prior = learnedToleranceFloor(for: cat)
        let candidate = observedDistance + 0.1
        if candidate > prior {
            UserDefaults.standard.set(candidate, forKey: toleranceKey(for: cat))
        }
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
