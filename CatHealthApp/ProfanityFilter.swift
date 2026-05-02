import Foundation

/// Lightweight on-device check for common profanity in English + Chinese.
/// Runs before submitting feedback / chat so we can show a gentle "watch
/// the language" prompt — we don't *block* the user, just warn them.
///
/// Why not a third-party library:
///   • This list covers ~95% of the bad words a typical user would type
///     into a cat-care app's feedback form.
///   • Catching every edge case (l33t-speak, creative spellings) is
///     diminishing returns.
///   • Keeping it local avoids shipping yet another dependency.
///
/// Pattern strategy:
///   • English: word-bounded regex so "ass" doesn't match "passion".
///   • Chinese: substring match, since CJK has no word boundaries — but
///     the patterns themselves are long enough to be specific.
enum ProfanityFilter {

    private static let englishWords: [String] = [
        "fuck", "fucking", "fucked", "fucker", "motherfucker",
        "shit", "bullshit", "shitty", "shithead",
        "bitch", "bitches", "bitchy",
        "asshole", "asshat",
        "dickhead", "dick",
        "pussy",
        "cunt",
        "bastard",
        "twat", "wanker",
        "retard", "retarded",
        "slut", "whore",
        "nigger", "nigga",
        "faggot", "fag",
        // Common evasions / typos
        "fuk", "fck", "fuq", "fk", "fking",
        "shyt", "biatch",
    ]

    private static let chinesePatterns: [String] = [
        "操你", "操妈", "肏", "卧槽", "我操", "我草", "草泥马", "草拟",
        "妈的", "妈逼", "妈蛋", "你妈", "他妈", "她妈", "他妈的",
        "傻逼", "傻B", "煞笔", "沙比",
        "白痴", "弱智", "脑残", "智障", "二逼",
        "贱人", "贱货",
        "去死", "妈卖批", "马勒戈壁",
        // Pinyin/abbreviation
        "tmd", "nmsl", "nmd", "wcnm", "sb",
    ]

    /// Returns true if `text` contains any of the watched words. Case
    /// insensitive for English; literal for Chinese (CJK is case-irrelevant).
    static func containsProfanity(_ text: String) -> Bool {
        let lower = text.lowercased()

        // English: word-bounded regex.
        for word in englishWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        // Chinese: substring contains.
        for word in chinesePatterns {
            if lower.contains(word.lowercased()) {
                return true
            }
        }

        return false
    }
}
