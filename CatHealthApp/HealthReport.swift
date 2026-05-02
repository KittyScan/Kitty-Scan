import Foundation
import SwiftUI
import UIKit

/// Single source of truth for health-score segmentation.
/// Every color, label, and emergency trigger in the app resolves through this.
///
/// Band boundaries are deliberately aligned with the emergency-vet threshold
/// (<40) so the red score-ring color and the red "see a vet NOW" CTA always
/// appear together — never one without the other.
enum ScoreBand {
    case excellent  // 90-100
    case good       // 70-89
    case fair       // 40-69
    case critical   // 0-39

    init(score: Int) {
        switch score {
        case 90...100: self = .excellent
        case 70..<90:  self = .good
        case 40..<70:  self = .fair
        default:       self = .critical
        }
    }

    var color: Color {
        switch self {
        case .excellent: return Theme.success
        case .good:      return Theme.primary
        case .fair:      return Theme.warning
        case .critical:  return Theme.danger
        }
    }

    var uiColor: UIColor {
        switch self {
        case .excellent: return .systemGreen
        case .good:      return UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
        case .fair:      return .systemOrange
        case .critical:  return .systemRed
        }
    }

    /// Localization key for the score label shown next to the number.
    var labelKey: String {
        switch self {
        case .excellent: return "report.score.excellent"
        case .good:      return "report.score.good"
        case .fair:      return "report.score.fair"
        case .critical:  return "report.score.attention"
        }
    }

    /// Whether this band warrants the emergency "see a vet NOW" CTA.
    /// (AI-flagged [URGENT] keywords trigger it independently.)
    var isCritical: Bool { self == .critical }
}

extension HealthReport {
    var scoreBand: ScoreBand { .init(score: healthScore) }
}

/// Per-dimension scores. The AI is asked to grade each independently on 0-100.
/// The final `healthScore` is a weighted average of these four.
///
/// Weights were set by domain judgment (cat health signals):
///   eyes   30% — strongest visible signal (discharge, clarity)
///   energy 30% — demeanor/liveliness tracks overall wellbeing
///   fur    20% — visible but slow-changing
///   posture 20% — informative but hard to judge from a static photo
///
/// These are fixed constants. If later we gather user feedback ("this score is
/// too high / too low") we can fit better weights offline (linear regression
/// over the feedback data) and ship new constants — no in-app training needed.
struct SubScores: Codable, Hashable {
    let eyes: Int
    let fur: Int
    let posture: Int
    let energy: Int

    static let weights: (eyes: Double, fur: Double, posture: Double, energy: Double)
        = (0.30, 0.20, 0.20, 0.30)

    /// Weighted composite, clamped to 0-100.
    var composite: Int {
        let w = Self.weights
        let raw = Double(eyes) * w.eyes
                + Double(fur) * w.fur
                + Double(posture) * w.posture
                + Double(energy) * w.energy
        return max(0, min(100, Int(raw.rounded())))
    }

    /// Fallback when AI returns only a legacy single score.
    static func uniform(_ score: Int) -> SubScores {
        SubScores(eyes: score, fur: score, posture: score, energy: score)
    }
}

struct HealthReport: Codable, Identifiable {
    let id: UUID
    let breed: String
    let furColor: String
    let personality: String
    let healthScore: Int
    let subScores: SubScores?
    let eyesCondition: String
    let furCondition: String
    let postureCondition: String
    let suggestions: [String]
    let warnings: [String]
    let parentBreeds: [String]
    let lifestyleTag: String      // "water" | "food" | "exercise"
    let lifestyleDetail: String
    let summary: String?
    let date: Date

    init(breed: String, furColor: String, personality: String, healthScore: Int,
         subScores: SubScores? = nil,
         eyesCondition: String, furCondition: String, postureCondition: String,
         suggestions: [String], warnings: [String],
         parentBreeds: [String], lifestyleTag: String, lifestyleDetail: String,
         summary: String? = nil) {
        self.id = UUID()
        self.breed = breed
        self.furColor = furColor
        self.personality = personality
        self.healthScore = healthScore
        self.subScores = subScores
        self.eyesCondition = eyesCondition
        self.furCondition = furCondition
        self.postureCondition = postureCondition
        self.suggestions = suggestions
        self.warnings = warnings
        self.parentBreeds = parentBreeds
        self.lifestyleTag = lifestyleTag
        self.lifestyleDetail = lifestyleDetail
        self.summary = summary
        self.date = Date()
    }
}

private struct DecodableReport: Decodable {
    let breed: String
    let furColor: String
    let personality: String
    let healthScore: Int?           // optional — we compute from subScores when present
    let subScores: SubScores?
    let eyesCondition: String
    let furCondition: String
    let postureCondition: String
    let suggestions: [String]
    let warnings: [String]
    let parentBreeds: [String]
    let lifestyleTag: String
    let lifestyleDetail: String
    let summary: String?
}

extension HealthReport {
    /// Extracts the JSON object from a potentially noisy AI response:
    /// strips markdown fences, trims prose before/after, grabs the first `{`
    /// through the last `}`. Tolerant of models that occasionally wrap the
    /// JSON in preamble or explanation text.
    private static func extractJSON(from raw: String) -> String? {
        let stripped = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let start = stripped.firstIndex(of: "{"),
              let end = stripped.lastIndex(of: "}"),
              start < end else { return nil }
        return String(stripped[start...end])
    }

    static func from(json: String) throws -> HealthReport {
        guard let cleaned = extractJSON(from: json) else {
            print("[HealthReport] no JSON object found in response:")
            print(json)
            throw ClaudeError.invalidResponse
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw ClaudeError.invalidResponse
        }
        let d: DecodableReport
        do {
            d = try JSONDecoder().decode(DecodableReport.self, from: data)
        } catch {
            // Log the exact response + which field tripped it, so we can
            // diagnose model drift without shipping extra telemetry.
            print("[HealthReport] decode failed:")
            print("Raw response:\n\(json)")
            print("Cleaned JSON:\n\(cleaned)")
            print("DecodingError: \(error)")
            throw ClaudeError.invalidResponse
        }

        // Prefer the computed composite when subScores are provided; otherwise
        // fall back to the legacy single score. This keeps old responses working
        // during prompt migration + handles cases where the model skips subScores.
        let finalScore: Int
        if let sub = d.subScores {
            finalScore = sub.composite
        } else if let legacy = d.healthScore {
            finalScore = max(0, min(100, legacy))
        } else {
            finalScore = 0
        }

        return HealthReport(
            breed: d.breed,
            furColor: d.furColor,
            personality: d.personality,
            healthScore: finalScore,
            subScores: d.subScores,
            eyesCondition: d.eyesCondition,
            furCondition: d.furCondition,
            postureCondition: d.postureCondition,
            suggestions: d.suggestions,
            warnings: d.warnings,
            parentBreeds: d.parentBreeds,
            lifestyleTag: d.lifestyleTag,
            lifestyleDetail: d.lifestyleDetail,
            summary: d.summary
        )
    }
}

enum ClaudeError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case noImageData

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无法解析 AI 返回的数据"
        case .apiError(let msg): return "API 错误：\(msg)"
        case .noImageData: return "图片数据无效"
        }
    }
}
