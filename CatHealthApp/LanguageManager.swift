import Foundation
import Observation

@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    var currentLanguage: String {
        didSet { UserDefaults.standard.set(currentLanguage, forKey: "appLanguage") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage")
        let system = Locale.current.language.languageCode?.identifier ?? "en"
        let resolved = saved ?? system
        // Validate the resolved code against the curated list — falls back
        // to English if the user's system locale isn't in the supported set.
        // Without this guard a user on Hindi (no .lproj) would get an
        // unmapped code that breaks `aiInstructionLanguage` and the picker.
        if let match = SupportedLanguage.byCode(resolved) {
            self.currentLanguage = match.code
        } else {
            self.currentLanguage = "en"
        }
    }

    var bundle: Bundle {
        // Try the exact code first, then the language part (e.g. "es-MX" → "es"),
        // then fall back to English. This lets us ship Spanish strings later
        // without breaking users who already picked a region variant.
        let candidates = [currentLanguage,
                          String(currentLanguage.prefix(while: { $0 != "-" })),
                          "en"]
        for code in candidates {
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
               let b = Bundle(path: path) {
                return b
            }
        }
        return .main
    }

    func loc(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// True only for actual Chinese variants (zh-Hans, zh-Hant). Used by the
    /// many inline `lang.isChineseSelected ? "中" : "EN"` ternaries scattered
    /// through the views. Anything other than Chinese falls into the English
    /// branch, which is the right v1 behavior — we have full Chinese + English
    /// strings, and other locales fall back to English UI while Claude
    /// responds in the user's chosen language (see `aiInstructionLanguage`).
    var isChineseSelected: Bool { currentLanguage.hasPrefix("zh") }

    /// What we send to Claude as "respond in this language". Claude
    /// understands locale names ("Spanish", "Japanese") much more reliably
    /// than codes, so we map codes → English names here.
    var aiInstructionLanguage: String {
        SupportedLanguage.byCode(currentLanguage)?.englishName ?? "English"
    }
}

/// Curated list of 30 major languages by speaker count + iOS-supported
/// regional variants. Each entry has the BCP-47 code we store, the native
/// display name (shown in the picker), and the English name we send to
/// Claude as "respond in {englishName}".
struct SupportedLanguage: Identifiable, Hashable {
    let code: String           // BCP-47 — e.g. "zh-Hans", "es", "ja"
    let nativeName: String     // shown in the picker, in its own script
    let englishName: String    // sent to Claude, e.g. "Chinese", "Spanish"
    var id: String { code }

    static let all: [SupportedLanguage] = [
        // East Asia
        .init(code: "zh-Hans", nativeName: "简体中文",   englishName: "Simplified Chinese"),
        .init(code: "zh-Hant", nativeName: "繁體中文",   englishName: "Traditional Chinese"),
        .init(code: "ja",      nativeName: "日本語",     englishName: "Japanese"),
        .init(code: "ko",      nativeName: "한국어",      englishName: "Korean"),
        // West-Europe / Anglo
        .init(code: "en",      nativeName: "English",    englishName: "English"),
        .init(code: "es",      nativeName: "Español",    englishName: "Spanish"),
        .init(code: "fr",      nativeName: "Français",   englishName: "French"),
        .init(code: "de",      nativeName: "Deutsch",    englishName: "German"),
        .init(code: "it",      nativeName: "Italiano",   englishName: "Italian"),
        .init(code: "pt-BR",   nativeName: "Português (Brasil)", englishName: "Brazilian Portuguese"),
        .init(code: "pt-PT",   nativeName: "Português",  englishName: "European Portuguese"),
        .init(code: "nl",      nativeName: "Nederlands", englishName: "Dutch"),
        .init(code: "el",      nativeName: "Ελληνικά",   englishName: "Greek"),
        // Nordic
        .init(code: "sv",      nativeName: "Svenska",    englishName: "Swedish"),
        .init(code: "nb",      nativeName: "Norsk",      englishName: "Norwegian"),
        .init(code: "da",      nativeName: "Dansk",      englishName: "Danish"),
        .init(code: "fi",      nativeName: "Suomi",      englishName: "Finnish"),
        // East Europe / Slavic
        .init(code: "ru",      nativeName: "Русский",    englishName: "Russian"),
        .init(code: "uk",      nativeName: "Українська", englishName: "Ukrainian"),
        .init(code: "pl",      nativeName: "Polski",     englishName: "Polish"),
        .init(code: "cs",      nativeName: "Čeština",    englishName: "Czech"),
        .init(code: "hu",      nativeName: "Magyar",     englishName: "Hungarian"),
        .init(code: "ro",      nativeName: "Română",     englishName: "Romanian"),
        .init(code: "tr",      nativeName: "Türkçe",     englishName: "Turkish"),
        // Middle East / S. Asia
        .init(code: "ar",      nativeName: "العربية",     englishName: "Arabic"),
        .init(code: "he",      nativeName: "עברית",       englishName: "Hebrew"),
        .init(code: "hi",      nativeName: "हिन्दी",        englishName: "Hindi"),
        // SE Asia
        .init(code: "id",      nativeName: "Indonesia",   englishName: "Indonesian"),
        .init(code: "th",      nativeName: "ไทย",          englishName: "Thai"),
        .init(code: "vi",      nativeName: "Tiếng Việt",  englishName: "Vietnamese"),
    ]

    static func byCode(_ code: String) -> SupportedLanguage? {
        // Exact match first; fall back to language-only prefix (es-MX → es)
        if let exact = all.first(where: { $0.code == code }) { return exact }
        let prefix = code.prefix(while: { $0 != "-" })
        return all.first { $0.code == String(prefix) }
    }
}
