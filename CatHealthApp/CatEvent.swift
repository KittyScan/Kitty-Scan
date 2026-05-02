import SwiftData
import Foundation

/// Time-specific events on a cat's health calendar — anything that happens
/// at a particular moment and needs its own "did it happen yet / when's the
/// next one" tracking. Distinct from `DailyLog` which is a per-day routine
/// aggregate (food count, water count, mood).
///
/// Five v1 types:
///   • vaccine        — injection with auto-recur (12 mo for most cat shots)
///   • dewormer       — internal / external / both, recur monthly by default
///   • medication     — drug name + dose + course of N days × daily count
///   • vetVisit       — clinic visit log; receipt photo, diagnosis, cost
///   • other          — anything that doesn't fit (vomiting, behavior, etc.)
///
/// All type-specific fields live on this same record (we deliberately do
/// NOT split into per-type tables — keeps SwiftData migration simple and
/// lets the calendar query "everything on this date" without joins).
/// Fields that don't apply to a given type are just nil.
@Model
final class CatEvent {
    var id: UUID
    /// Raw value of `EventType`. Stored as String so SwiftData can index
    /// without a custom transformer.
    var typeRaw: String
    /// When this event happens / happened. For scheduled-future events
    /// (next vaccine due) this is in the future; for logged-past events
    /// (vet visit yesterday) this is in the past.
    var scheduledAt: Date
    /// Set to non-nil when the user marks the event done. Nil for
    /// auto-generated future reminders that haven't been completed.
    var completedAt: Date?

    /// Free-text title shown in lists ("Annual booster", "Amoxicillin").
    var title: String
    /// Free-text notes the owner can add.
    var notes: String

    // ----- Vaccine fields -----
    /// e.g. "FVRCP" / "Rabies" / "FeLV"; raw vaccine identifier.
    var vaccineKindRaw: String?

    // ----- Dewormer fields -----
    /// "internal" / "external" / "both"
    var dewormerKindRaw: String?

    // ----- Medication fields -----
    var medName: String?
    var medDose: String?           // free text: "5mg" / "1/2 片" / "1ml"
    var medCourseDays: Int?        // total days; auto-expand into N daily reminders
    var medDailyCount: Int?        // 1, 2, or 3 (am / am+pm / am+noon+pm)
    /// HH:MM strings, length matches medDailyCount.
    var medTimes: [String]

    // ----- Vet visit fields -----
    var vetClinic: String?
    var vetDoctor: String?
    var vetComplaint: String?
    var vetDiagnosis: String?
    /// Stored in the smallest currency unit (cents/分); presented as decimal.
    var vetCostCents: Int?
    @Attribute(.externalStorage) var vetReceiptImage: Data?

    var cat: Cat?

    init(type: EventType,
         scheduledAt: Date,
         title: String = "",
         notes: String = "",
         cat: Cat? = nil) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.scheduledAt = scheduledAt
        self.completedAt = nil
        self.title = title
        self.notes = notes
        self.medTimes = []
        self.cat = cat
    }

    var type: EventType {
        EventType(rawValue: typeRaw) ?? .other
    }
}

/// Five v1 event categories. Each carries its own default recurrence cadence
/// and rendering hint. Keep raw values stable across releases — they're
/// persisted in SwiftData.
enum EventType: String, CaseIterable, Codable, Sendable {
    case vaccine
    case dewormer
    case medication
    case vetVisit = "vet_visit"
    case other

    func displayName(zh: Bool) -> String {
        switch self {
        case .vaccine:    return zh ? "疫苗"     : "Vaccine"
        case .dewormer:   return zh ? "驱虫"     : "Dewormer"
        case .medication: return zh ? "吃药"     : "Medication"
        case .vetVisit:   return zh ? "兽医就诊" : "Vet Visit"
        case .other:      return zh ? "其他"     : "Other"
        }
    }

    /// SF Symbol identifier — these are all guaranteed to exist on iOS 17+.
    var iconSymbol: String {
        switch self {
        case .vaccine:    return "syringe.fill"
        case .dewormer:   return "ant.fill"
        case .medication: return "pills.fill"
        case .vetVisit:   return "stethoscope"
        case .other:      return "note.text"
        }
    }

    /// Tint hex (matches iOS system semantic colors loosely; no Theme dep).
    var tintHex: String {
        switch self {
        case .vaccine:    return "5856D6"   // systemPurple
        case .dewormer:   return "AF52DE"   // a nearby purple-pink
        case .medication: return "FF9500"   // systemOrange
        case .vetVisit:   return "FF3B30"   // systemRed
        case .other:      return "8E8E93"   // systemGray
        }
    }

    /// Default "next due" interval in days for auto-recurring types. Used to
    /// pre-fill the schedule picker when the user adds a new event of this
    /// type — they can override before saving.
    var defaultNextDueDays: Int? {
        switch self {
        case .vaccine:    return 365   // most cat vaccines: annual booster
        case .dewormer:   return 30    // monthly is standard
        case .medication: return nil   // explicit course, no recurrence
        case .vetVisit:   return nil   // event-driven, no recurrence
        case .other:      return nil
        }
    }
}

/// Vaccine sub-categorization — separate from EventType so we don't
/// explode the top-level enum. These match the most common shots a pet
/// owner will encounter; "其他" lets users type their own.
enum VaccineKind: String, CaseIterable, Codable, Sendable {
    case fvrcp           // 猫三联 (rhino + calici + panleukopenia)
    case rabies          // 狂犬
    case felv            // 猫白血病
    case other

    func displayName(zh: Bool) -> String {
        switch self {
        case .fvrcp:  return zh ? "猫三联"   : "FVRCP"
        case .rabies: return zh ? "狂犬"     : "Rabies"
        case .felv:   return zh ? "猫白血病" : "FeLV"
        case .other:  return zh ? "其他疫苗" : "Other"
        }
    }

    /// Default booster interval for this vaccine in days.
    /// Numbers are the AAFP feline vaccine guideline defaults — every 3 years
    /// is also acceptable for FVRCP after the kitten series, but annual is
    /// the safer-default the schedule recommends to most owners.
    var defaultIntervalDays: Int {
        switch self {
        case .fvrcp:  return 365
        case .rabies: return 365
        case .felv:   return 365
        case .other:  return 365
        }
    }
}

enum DewormerKind: String, CaseIterable, Codable, Sendable {
    case internalParasites = "internal"
    case externalParasites = "external"
    case both

    func displayName(zh: Bool) -> String {
        switch self {
        case .internalParasites: return zh ? "内驱(肠道)" : "Internal"
        case .externalParasites: return zh ? "外驱(跳蚤)" : "External"
        case .both:              return zh ? "内+外驱"   : "Both"
        }
    }
}
