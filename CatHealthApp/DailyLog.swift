import SwiftData
import Foundation

/// One row per cat per day. Tracking the routine stuff (food, water, mood,
/// any discomfort) gives the AI analysis much better context — a 65 score
/// makes more sense when paired with "didn't eat lunch yesterday" than with
/// no signal at all.
///
/// Date is stored at midnight (start-of-day) so equality + lookup-by-day is
/// trivial. We never use the time component.
@Model
final class DailyLog {
    var id: UUID
    /// Always start-of-day (00:00) in the local timezone at write time.
    var date: Date

    /// Number of meals the cat had. Caps at 10 in the UI but stored uncapped.
    var foodCount: Int
    /// Number of times the cat drank water (or count of refills observed).
    var waterCount: Int

    /// Logged 1–5; 3 is "normal", below 3 lethargic, above 3 hyper.
    /// Optional because the user shouldn't be forced to score every day.
    var moodScore: Int?

    /// Free-form weight in grams. Optional — most users won't weigh daily.
    var weightGrams: Int?

    /// Quick-tap toggle for "something seemed off today".
    var hasDiscomfort: Bool

    /// Free-text note from the user. The most important field for AI context.
    var notes: String

    var cat: Cat?

    init(date: Date,
         foodCount: Int = 0,
         waterCount: Int = 0,
         moodScore: Int? = nil,
         weightGrams: Int? = nil,
         hasDiscomfort: Bool = false,
         notes: String = "",
         cat: Cat? = nil) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.foodCount = foodCount
        self.waterCount = waterCount
        self.moodScore = moodScore
        self.weightGrams = weightGrams
        self.hasDiscomfort = hasDiscomfort
        self.notes = notes
        self.cat = cat
    }

    /// Whether anything was actually logged. Used to decide when to delete
    /// an empty record on save (so we don't pollute the calendar with
    /// invisible "0 / 0 / no note" rows).
    var isEmpty: Bool {
        foodCount == 0 && waterCount == 0 && moodScore == nil
            && weightGrams == nil && !hasDiscomfort && notes.isEmpty
    }
}
