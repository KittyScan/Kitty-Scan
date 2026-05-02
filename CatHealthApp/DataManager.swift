import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Pragmatic wrapper for crossing actor boundaries with non-Sendable types
/// (SwiftData @Model classes like Cat / HistoryRecord). Only safe when the
/// receiving task does READ-ONLY access of immutable properties — which is
/// exactly what `CatPDF.render` does. Don't use this to mutate.
struct UncheckedSendableBox<Wrapped>: @unchecked Sendable {
    let value: Wrapped
    init(_ value: Wrapped) { self.value = value }
}

/// Persistent location for export artifacts. We use the app's Documents
/// directory (not `temporaryDirectory`) so files survive across launches —
/// the user can revisit them via Settings → Recent exports without having
/// to re-run the export. Files in Documents are also user-visible via the
/// Files app (under "On My iPhone → KittyScan").
///
/// Old temp-directory files used to vanish silently when iOS cleaned up;
/// moving everything here was the fix for "I exported it and now it's gone".
enum ExportStorage {
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// All previously-exported files, newest first. Reads file modification
    /// dates rather than persisting an index — simple, robust, and stays in
    /// sync if files are deleted via the Files app.
    static func listAll() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
    }
}

/// Progress states emitted by `exportAll` to drive the loading UI.
enum ExportStep: Hashable {
    case collecting
    case json
    case card(index: Int, total: Int, catName: String)
    case pdf(index: Int, total: Int, catName: String)
    case finalizing
    case done
}

/// What the user picked in ExportConfigSheet. Feeds into `exportAll`.
struct ExportConfig: Hashable {
    /// Empty set = all cats.
    var catIds: Set<UUID> = []
    var dateRange: DateRange = .allTime
    /// Kept off — JSON dump is dev-facing and confusing for typical users.
    /// We removed the UI toggle; the export pipeline still understands the
    /// flag so we can flip it back on in a future "developer mode" if needed.
    var includeJSON: Bool = false
    var includeCards: Bool = true
    var includePDFs: Bool = true

    enum DateRange: Hashable, CaseIterable {
        case allTime, last30Days, last90Days, lastYear

        func contains(_ date: Date) -> Bool {
            let now = Date()
            switch self {
            case .allTime:    return true
            case .last30Days: return now.timeIntervalSince(date) <= 30  * 86_400
            case .last90Days: return now.timeIntervalSince(date) <= 90  * 86_400
            case .lastYear:   return now.timeIntervalSince(date) <= 365 * 86_400
            }
        }

        func labelZh() -> String {
            switch self {
            case .allTime:    return "全部"
            case .last30Days: return "30 天"
            case .last90Days: return "90 天"
            case .lastYear:   return "1 年"
            }
        }
        func labelEn() -> String {
            switch self {
            case .allTime:    return "All"
            case .last30Days: return "30 days"
            case .last90Days: return "90 days"
            case .lastYear:   return "1 year"
            }
        }
    }

    /// Returns cats filtered by selection.
    func selectedCats(from cats: [Cat]) -> [Cat] {
        if catIds.isEmpty { return cats }
        return cats.filter { catIds.contains($0.id) }
    }

    /// Returns a record filter predicate.
    func matches(_ record: HistoryRecord) -> Bool {
        dateRange.contains(record.date)
    }
}

/// A produced file with enough metadata to render a nice row in the success UI.
struct ExportedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let kind: Kind
    let displayName: String
    let sizeBytes: Int
    let subtitle: String

    enum Kind: Hashable { case json, png, pdf }
}

/// Utilities for exporting + wiping user data (compliance: data portability + account deletion).
enum DataManager {

    // MARK: - Export DTOs
    private struct ExportBundle: Codable {
        let appVersion: String
        let exportedAt: Date
        let userEmail: String?
        let cats: [CatExport]
    }

    private struct CatExport: Codable {
        let id: String
        let name: String
        let breed: String?
        let breedId: String?
        let sex: String?
        let age: String?
        let neuter: Bool
        let knownIssues: [String]
        let personalitySummary: String?
        let vaccineDate: Date?
        let dewormingDate: Date?
        let createdAt: Date
        let records: [RecordExport]
    }

    private struct RecordExport: Codable {
        let id: String
        let date: Date
        let breed: String
        let furColor: String
        let healthScore: Int
        let eyesCondition: String
        let furCondition: String
        let postureCondition: String
        let suggestions: [String]
        let warnings: [String]
        let lifestyleTag: String
        let lifestyleDetail: String
        let summary: String?
        let todayNote: String?
        // Photos NOT included — user already has local copies; export stays small & shareable.
    }

    // MARK: - Export to JSON file
    @MainActor
    static func exportJSON(cats: [Cat],
                           userEmail: String?,
                           recordFilter: (HistoryRecord) -> Bool = { _ in true }) throws -> URL {
        let bundle = ExportBundle(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            exportedAt: Date(),
            userEmail: userEmail,
            cats: cats.map { c in
                CatExport(
                    id: c.id.uuidString,
                    name: c.name,
                    breed: c.breed,
                    breedId: c.breedId,
                    sex: c.sex,
                    age: c.age,
                    neuter: c.neuter,
                    knownIssues: c.knownIssues,
                    personalitySummary: c.personalitySummary,
                    vaccineDate: c.vaccineDate,
                    dewormingDate: c.dewormingDate,
                    createdAt: c.createdAt,
                    records: c.records
                        .filter(recordFilter)
                        .sorted { $0.date > $1.date }
                        .map { r in
                            RecordExport(
                                id: r.id.uuidString,
                                date: r.date,
                                breed: r.breed,
                                furColor: r.furColor,
                                healthScore: r.healthScore,
                                eyesCondition: r.eyesCondition,
                                furCondition: r.furCondition,
                                postureCondition: r.postureCondition,
                                suggestions: r.suggestions,
                                warnings: r.warnings,
                                lifestyleTag: r.lifestyleTag,
                                lifestyleDetail: r.lifestyleDetail,
                                summary: r.summary,
                                todayNote: r.todayNote
                            )
                        }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(bundle)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        let date = fmt.string(from: Date())
        let filename = "cathealth-export-\(date).json"
        let url = ExportStorage.directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Full export (JSON + themed PNG card per cat)

    /// Async export that produces:
    ///   1× carmel-export-<date>.json     (all cats + history)
    ///   N× <CatName>_card.png            (one themed 1080×1350 poster per cat)
    /// Reports progress via `onStep` so the UI can animate a step list.
    @MainActor
    static func exportAll(cats: [Cat],
                          config: ExportConfig,
                          userEmail: String?,
                          zh: Bool,
                          onStep: (ExportStep) -> Void) async throws -> [ExportedFile] {

        var produced: [ExportedFile] = []
        let selected = config.selectedCats(from: cats)
        let filter: (HistoryRecord) -> Bool = config.matches

        print("[Export] START · \(selected.count) cats · JSON=\(config.includeJSON) cards=\(config.includeCards) pdfs=\(config.includePDFs)")

        // Step 1 — collect (no artificial pacing delay)
        onStep(.collecting)

        // Step 2 — JSON
        if config.includeJSON {
            onStep(.json)
            let jsonURL = try exportJSON(cats: selected, userEmail: userEmail, recordFilter: filter)
            let jsonSize = (try? FileManager.default.attributesOfItem(atPath: jsonURL.path)[.size] as? Int) ?? 0
            produced.append(ExportedFile(
                url: jsonURL, kind: .json, displayName: jsonURL.lastPathComponent,
                sizeBytes: jsonSize,
                subtitle: zh ? "\(selected.count) 只猫 · 完整数据" : "\(selected.count) cat(s) · full data"
            ))
        }

        let dateFmt = DateFormatter(); dateFmt.locale = .current; dateFmt.dateStyle = .medium
        let dateStr = dateFmt.string(from: Date())

        // Step 3 — PNG cards in PARALLEL.
        // CardInput is fully Sendable (snapshotted on main), so multiple
        // detached tasks can render concurrently without touching SwiftData
        // from background. Speedup ~ N× for N cats.
        if config.includeCards {
            onStep(.card(index: 1, total: selected.count, catName: selected.first?.name ?? ""))
            // Build all inputs on main first (cheap, just property reads).
            let cardInputs: [(idx: Int, name: String, input: CardInput)] = selected.enumerated().map { idx, cat in
                let theme = CatThemes.byId(cat.breedId) ?? CatThemes.defaultTheme
                let filteredRecords = cat.records.filter(filter).sorted { $0.date > $1.date }
                let latestScore = filteredRecords.first?.healthScore
                let days = max(1, Int(Date().timeIntervalSince(cat.createdAt) / 86_400))
                let input = CardInput.snapshot(
                    cat: cat, records: filteredRecords, theme: theme,
                    recordCount: filteredRecords.count, latestScore: latestScore,
                    sinceCreatedDays: days, exportDateText: dateStr, zh: zh
                )
                return (idx, cat.name, input)
            }
            // Render concurrently. Each completed PNG bumps the progress UI.
            let cardResults = await withTaskGroup(of: (Int, String, Data?).self) { group -> [(Int, String, Data?)] in
                for entry in cardInputs {
                    group.addTask(priority: .userInitiated) {
                        let data = autoreleasepool { CatCardView.renderPNG(input: entry.input) }
                        return (entry.idx, entry.name, data)
                    }
                }
                var out: [(Int, String, Data?)] = []
                var doneCount = 0
                for await result in group {
                    out.append(result)
                    doneCount += 1
                    onStep(.card(index: doneCount, total: cardInputs.count, catName: result.1))
                }
                return out.sorted { $0.0 < $1.0 }
            }
            for (_, name, cardData) in cardResults {
                guard let cardData else { continue }
                let filename = "\(sanitize(name))_card.png"
                let url = ExportStorage.directory.appendingPathComponent(filename)
                try cardData.write(to: url, options: .atomic)
                produced.append(ExportedFile(
                    url: url, kind: .png, displayName: filename,
                    sizeBytes: cardData.count, subtitle: "1080 × 1920"
                ))
            }
        }

        // Step 4 — PDF archives, SEQUENTIALLY off-main.
        // PDF rendering is memory-intensive (multi-page CG context with
        // embedded photos). Running 5 PDFs concurrently caused memory
        // pressure + slow renders due to thrashing. Serial off-main is
        // faster overall and gives the user accurate per-cat progress.
        if config.includePDFs {
            for (idx, cat) in selected.enumerated() {
                onStep(.pdf(index: idx + 1, total: selected.count, catName: cat.name))
                let theme = CatThemes.byId(cat.breedId) ?? CatThemes.defaultTheme
                let filteredRecords = cat.records.filter(filter).sorted { $0.date > $1.date }
                let recordCount = filteredRecords.count
                let catBox = UncheckedSendableBox(cat)
                let recordsBox = UncheckedSendableBox(filteredRecords)
                let pdfData: Data? = await Task.detached(priority: .userInitiated) {
                    autoreleasepool {
                        CatPDF.render(cat: catBox.value,
                                      records: recordsBox.value,
                                      theme: theme, zh: zh)
                    }
                }.value
                guard let pdfData else { continue }
                let filename = "\(sanitize(cat.name))_health.pdf"
                let url = ExportStorage.directory.appendingPathComponent(filename)
                try pdfData.write(to: url, options: .atomic)
                // Patient summary + methodology = 2 pages, always.
                let pageCount = 2
                _ = recordCount
                produced.append(ExportedFile(
                    url: url, kind: .pdf, displayName: filename,
                    sizeBytes: pdfData.count,
                    subtitle: zh ? "\(pageCount) 页" : "\(pageCount) pages"
                ))
            }
        }

        onStep(.finalizing)
        onStep(.done)
        print("[Export] DONE · \(produced.count) files")
        return produced
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_"))
            .union(CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}")) // CJK
        let scalars = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let joined = String(scalars)
        return joined.isEmpty ? "cat" : joined
    }

    // MARK: - Wipe everything
    @MainActor
    static func wipeAll(modelContext: ModelContext, cats: [Cat], records: [HistoryRecord]) {
        for r in records { modelContext.delete(r) }
        for c in cats { modelContext.delete(c) }
        try? modelContext.save()

        // Wipe all user-related UserDefaults keys this app owns
        let keysToWipe = [
            "authUser",       // AuthManager cached user
            "appLanguage",    // LanguageManager
            "activeCatId",    // ThemeProvider
        ]
        for key in keysToWipe {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// Share sheet wrapper for URLs (export file).
struct URLActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
