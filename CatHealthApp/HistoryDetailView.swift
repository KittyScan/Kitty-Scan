import SwiftUI

struct HistoryDetailView: View {
    let record: HistoryRecord
    @Environment(LanguageManager.self) var lang

    /// Currently displayed report — starts as the original, gets swapped
    /// in-place if the user accepts a translation.
    @State private var displayReport: HealthReport?
    @State private var showTranslateAlert = false
    @State private var isTranslating = false
    @State private var translateError: String?

    private var zh: Bool { lang.isChineseSelected }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let data = record.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding()
                }
                if let displayReport {
                    HealthReportView(
                        report: displayReport,
                        cat: record.cat,
                        recentRecords: record.cat.map { Array($0.records.sorted { $0.date > $1.date }.prefix(5)) } ?? []
                    )
                }
            }
        }
        .navigationTitle(displayReport?.breed ?? record.breed)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isTranslating {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(zh ? "正在翻译喵... ฅ" : "Translating ฅ...")
                            .font(.subheadline)
                    }
                    .padding(20)
                    .background(Theme.cardPrimary)
                    .cornerRadius(14)
                }
            }
        }
        .onAppear { resolveDisplayReport() }
        .onChange(of: lang.currentLanguage) { _, _ in resolveDisplayReport() }
        .alert(zh ? "喵~ 主人换语言了 (=^・ω・^=)"
                  : "Meow~ language switched (=^・ω・^=)",
               isPresented: $showTranslateAlert) {
            Button(zh ? "翻译喵 ✿" : "Translate ✿") {
                Task { await translate() }
            }
            Button(zh ? "先用原文 ฅ" : "Keep original ฅ", role: .cancel) { }
        } message: {
            Text(translateAlertBody)
        }
        .alert(zh ? "翻译失败喵 (>﹏<)" : "Translation failed (>﹏<)",
               isPresented: Binding(
                get: { translateError != nil },
                set: { if !$0 { translateError = nil } }
               )) {
            Button("OK") { translateError = nil }
        } message: {
            Text(translateError ?? "")
        }
    }

    /// Decide which version of the report to display based on current
    /// language, and trigger the translate alert when applicable.
    private func resolveDisplayReport() {
        let currentLang = lang.currentLanguage
        let original = record.effectiveOriginalLanguage

        // Same language as when generated → just show original.
        if matchesLanguage(original, currentLang) {
            displayReport = record.toReport()
            return
        }

        // Cached translation available → use it directly, no alert.
        if let cached = record.translatedReport(in: currentLang) {
            displayReport = cached
            return
        }

        // Mismatch + no cache → show original now, ask user about translating.
        displayReport = record.toReport()
        // Only ask once per appearance — user can re-enter the screen to be
        // asked again. Avoids re-triggering on every onChange tick.
        if !showTranslateAlert { showTranslateAlert = true }
    }

    /// "zh-Hans" and "zh-Hant" both count as Chinese for translation
    /// purposes — re-translating from one Chinese variant to another is
    /// noise. Same for any "xx-YY" / "xx" prefix pairing.
    private func matchesLanguage(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let prefixA = a.split(separator: "-").first.map(String.init) ?? a
        let prefixB = b.split(separator: "-").first.map(String.init) ?? b
        return prefixA == prefixB
    }

    private var translateAlertBody: String {
        let target = lang.aiInstructionLanguage  // e.g. "Spanish"
        if zh {
            return "这份报告是用别的语言写的,要我帮你翻译成\(target == "English" ? "中文" : target)吗?"
        } else {
            return "This report was generated in a different language. Translate it into \(target)?"
        }
    }

    private func translate() async {
        guard let original = displayReport else { return }
        isTranslating = true
        defer { isTranslating = false }

        let target = lang.aiInstructionLanguage  // e.g. "Spanish", "Chinese"
        let langCode = lang.currentLanguage

        do {
            let tf = try await ClaudeService.shared
                .translateReport(original, toLanguageName: target)
            await MainActor.run {
                record.cacheTranslation(tf, for: langCode)
                if let translated = record.translatedReport(in: langCode) {
                    displayReport = translated
                }
            }
        } catch {
            translateError = error.localizedDescription
        }
    }
}
