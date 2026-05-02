import SwiftData
import UIKit

@Model
final class Cat {
    var id: UUID
    var name: String
    var breed: String?
    var breedId: String?
    var sex: String?
    var age: String?
    var neuter: Bool
    var knownIssues: [String]
    var personalitySummary: String?
    /// Snapshot of `records.count` at the moment we last regenerated the
    /// personality summary. Used to throttle: we only refresh once enough
    /// new records have accumulated to actually shift the summary, instead
    /// of burning an API call after every single analysis.
    var personalityRefreshedAtCount: Int?
    var vaccineDate: Date?
    var dewormingDate: Date?
    @Attribute(.externalStorage) var avatarData: Data?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \HistoryRecord.cat)
    var records: [HistoryRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \DailyLog.cat)
    var dailyLogs: [DailyLog] = []

    @Relationship(deleteRule: .cascade, inverse: \CatEvent.cat)
    var events: [CatEvent] = []

    init(name: String,
         breed: String? = nil,
         breedId: String? = nil,
         sex: String? = nil,
         age: String? = nil,
         neuter: Bool = false,
         avatarData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.breed = breed
        self.breedId = breedId
        self.sex = sex
        self.age = age
        self.neuter = neuter
        self.knownIssues = []
        self.avatarData = avatarData
        self.createdAt = Date()
    }

    var avatarImage: UIImage? {
        guard let data = avatarData else { return nil }
        return UIImage(data: data)
    }
}
