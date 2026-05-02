import SwiftData
import Foundation
import UIKit

@Model
final class HistoryRecord {
    var id: UUID
    var breed: String
    var furColor: String
    var personality: String
    var healthScore: Int
    var eyesCondition: String
    var furCondition: String
    var postureCondition: String
    var suggestions: [String]
    var warnings: [String]
    var parentBreeds: [String]
    var lifestyleTag: String
    var lifestyleDetail: String
    var date: Date
    var imageData: Data?
    var todayNote: String?
    var summary: String?
    var cat: Cat?

    // Per-dimension scores (added so the trend chart can break down by axis).
    // Optional because records created before this column existed will be nil
    // — chart code skips nil points instead of imputing fake data.
    var eyesScore:    Int?
    var furScore:     Int?
    var postureScore: Int?
    var energyScore:  Int?

    /// Language code (e.g. "zh-Hans", "en", "es") this report was generated in.
    /// Nil for records created before this column existed — those fall back to
    /// a CJK heuristic on first read so we know which way to translate.
    var originalLanguage: String?

    /// Cached translations, keyed by language code.
    /// Stored as JSON `[String: TranslatedFields]` to avoid a SwiftData
    /// schema migration every time we add a language. Read via
    /// `translatedFields(for:)`, write via `cacheTranslation(_:for:)`.
    var translationsData: Data?

    init(from report: HealthReport, image: UIImage?, todayNote: String? = nil, cat: Cat? = nil) {
        self.id = report.id
        self.breed = report.breed
        self.furColor = report.furColor
        self.personality = report.personality
        self.healthScore = report.healthScore
        self.eyesCondition = report.eyesCondition
        self.furCondition = report.furCondition
        self.postureCondition = report.postureCondition
        self.suggestions = report.suggestions
        self.warnings = report.warnings
        self.parentBreeds = report.parentBreeds
        self.lifestyleTag = report.lifestyleTag
        self.lifestyleDetail = report.lifestyleDetail
        self.date = report.date
        self.imageData = image?.jpegData(compressionQuality: 0.5)
        self.todayNote = todayNote
        self.summary   = report.summary
        self.cat       = cat
        self.eyesScore    = report.subScores?.eyes
        self.furScore     = report.subScores?.fur
        self.postureScore = report.subScores?.posture
        self.energyScore  = report.subScores?.energy
    }

    func toReport() -> HealthReport {
        let sub: SubScores? = {
            guard let e = eyesScore, let f = furScore,
                  let p = postureScore, let n = energyScore else { return nil }
            return SubScores(eyes: e, fur: f, posture: p, energy: n)
        }()
        return HealthReport(
            breed: breed, furColor: furColor, personality: personality,
            healthScore: healthScore, subScores: sub,
            eyesCondition: eyesCondition,
            furCondition: furCondition, postureCondition: postureCondition,
            suggestions: suggestions, warnings: warnings,
            parentBreeds: parentBreeds, lifestyleTag: lifestyleTag,
            lifestyleDetail: lifestyleDetail,
            summary: summary
        )
    }

    // MARK: - Translation

    /// Returns the report rendered in the target language code, or `nil` if
    /// no translation is cached for that language. Original-language reads
    /// always succeed via `toReport()`.
    func translatedReport(in langCode: String) -> HealthReport? {
        if effectiveOriginalLanguage == langCode { return toReport() }
        guard let tf = translatedFields(for: langCode) else { return nil }
        let sub: SubScores? = {
            guard let e = eyesScore, let f = furScore,
                  let p = postureScore, let n = energyScore else { return nil }
            return SubScores(eyes: e, fur: f, posture: p, energy: n)
        }()
        return HealthReport(
            breed: tf.breed, furColor: tf.furColor, personality: tf.personality,
            healthScore: healthScore, subScores: sub,
            eyesCondition: tf.eyesCondition,
            furCondition: tf.furCondition, postureCondition: tf.postureCondition,
            suggestions: tf.suggestions, warnings: tf.warnings,
            parentBreeds: parentBreeds, lifestyleTag: lifestyleTag,
            lifestyleDetail: tf.lifestyleDetail,
            summary: tf.summary
        )
    }

    func cacheTranslation(_ tf: TranslatedFields, for langCode: String) {
        var map = decodedTranslations()
        map[langCode] = tf
        translationsData = try? JSONEncoder().encode(map)
    }

    /// Resolves the original language. For legacy nil records we sniff the
    /// first text fields for any CJK character and assume zh-Hans, else en.
    /// This isn't perfect (a Chinese user generating an EN report would get
    /// mis-tagged) but it's only a fallback for pre-feature records.
    var effectiveOriginalLanguage: String {
        if let originalLanguage { return originalLanguage }
        let sample = breed + personality + summary.orEmpty
        return sample.containsCJK ? "zh-Hans" : "en"
    }

    private func translatedFields(for langCode: String) -> TranslatedFields? {
        decodedTranslations()[langCode]
    }

    private func decodedTranslations() -> [String: TranslatedFields] {
        guard let translationsData else { return [:] }
        return (try? JSONDecoder().decode([String: TranslatedFields].self, from: translationsData)) ?? [:]
    }
}

/// Free-form text fields of a HealthReport. Numeric fields (scores) and
/// enum fields (lifestyleTag) don't need translation, so they're not in here.
struct TranslatedFields: Codable {
    let breed: String
    let furColor: String
    let personality: String
    let eyesCondition: String
    let furCondition: String
    let postureCondition: String
    let suggestions: [String]
    let warnings: [String]
    let lifestyleDetail: String
    let summary: String?
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

private extension String {
    var containsCJK: Bool {
        unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
    }
}
