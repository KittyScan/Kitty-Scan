import Foundation

enum PromptBuilder {

    // MARK: - Public API

    static func buildAnalysis(cat: Cat,
                              history: [HistoryRecord],
                              todayNote: String?,
                              recentLogs: [DailyLog] = [],
                              isEnglish: Bool = false) -> String {
        isEnglish
            ? analysisEN(cat: cat, history: history, todayNote: todayNote, recentLogs: recentLogs)
            : analysisZH(cat: cat, history: history, todayNote: todayNote, recentLogs: recentLogs)
    }

    /// Compact 7-day diary summary that gets dropped into the analysis prompt.
    /// Empty string when there's nothing useful to add — Claude doesn't need
    /// to know "no data" since the absence of this section already implies it.
    fileprivate static func diarySummary(_ logs: [DailyLog], zh: Bool) -> String {
        let recent = logs
            .sorted { $0.date > $1.date }
            .prefix(7)
        guard !recent.isEmpty else { return "" }

        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
        f.dateFormat = zh ? "M/d" : "MMM d"

        let lines: [String] = recent.map { log in
            var bits: [String] = []
            if log.foodCount > 0  { bits.append(zh ? "\(log.foodCount) 顿饭" : "\(log.foodCount) meals") }
            if log.waterCount > 0 { bits.append(zh ? "\(log.waterCount) 次水" : "\(log.waterCount)× water") }
            if let m = log.moodScore { bits.append(zh ? "精神 \(m)/5" : "mood \(m)/5") }
            if log.hasDiscomfort  { bits.append(zh ? "**异常**" : "**off**") }
            if let w = log.weightGrams { bits.append(zh ? "\(w)g" : "\(w)g") }
            let extras = log.notes.isEmpty ? "" : "(\(log.notes))"
            return "- \(f.string(from: log.date)): \(bits.joined(separator: "·"))\(extras)"
        }
        return zh
            ? "\n最近 7 天日记摘要(主人手动记录,作为分析的辅助信号):\n\(lines.joined(separator: "\n"))"
            : "\nLast 7 days from owner's diary (manual logs, supporting signal):\n\(lines.joined(separator: "\n"))"
    }

    static func buildPersonality(cat: Cat, allRecords: [HistoryRecord], isEnglish: Bool = false) -> String {
        isEnglish
            ? personalityEN(cat: cat, allRecords: allRecords)
            : personalityZH(cat: cat, allRecords: allRecords)
    }

    static func buildChat(cat: Cat, history: [HistoryRecord], lastReport: HealthReport?,
                          question: String, isEnglish: Bool = false) -> String {
        isEnglish
            ? chatEN(cat: cat, history: history, lastReport: lastReport, question: question)
            : chatZH(cat: cat, history: history, lastReport: lastReport, question: question)
    }

    // MARK: - Chinese

    private static func analysisZH(cat: Cat, history: [HistoryRecord], todayNote: String?, recentLogs: [DailyLog]) -> String {
        let checkNum    = history.count + 1
        let issues      = cat.knownIssues.isEmpty ? "" : "，主人说它\(cat.knownIssues.joined(separator: "、"))"
        let breedLine   = [cat.age, cat.breed].compactMap { $0 }.joined(separator: "的")
        let neuterStr   = cat.neuter ? "已绝育" : "未绝育"
        let personality = cat.personalitySummary.map { "\n关于\(cat.name)的性格：\n\($0)\n" } ?? ""
        let historyLines = history.prefix(3).map {
            "- \(timeAgoZH($0.date))（\($0.healthScore)分）：\($0.summary ?? "综合状态评估")"
        }.joined(separator: "\n")
        let note = todayNote?.trimmingCharacters(in: .whitespaces).isEmpty == false ? todayNote! : "没有特别备注"
        let diary = diarySummary(recentLogs, zh: true)

        return """
        这是\(cat.name)的第\(checkNum)次检测。
        \(cat.name)是只\(breedLine)，\(neuterStr)\(issues)。
        \(personality)
        历史记录（仅供趋势对比,不要让历史分数影响本次独立评分）：
        \(historyLines.isEmpty ? "（首次检测，暂无历史记录）" : historyLines)
        \(diary)

        主人今天说：\(note)

        请结合以上背景分析这张照片。
        在分析中必须：
        - 和上次检测对比，明确说明变好/变差/持平
        - 如果某个问题连续出现2次以上，语气要加重，说"这已经是第X次了"
        - 如果上次提到的问题现在好转了，要明确表扬

        【结构化评分 · 必须严格遵守】
        不要给一个整体分数 —— 必须对 4 个维度各自独立打 0-100 分。
        代码会根据权重算出最终总分,你不要自己算。

        四个维度:
        • eyes(眼睛): 清澈度、是否有眼屎/红肿/眯眼、眼神是否有神
        • fur(毛发): 顺滑度、光泽、是否打结/过油/脱毛/脏
        • posture(体态): 姿势是否自然、胖瘦、是否蜷缩/僵硬
        • energy(精神): 神情是否精神、警觉,还是呆滞/萎靡

        每项打分 rubric:
        • 95-100:完美 — 这个维度挑不出任何毛病
        • 85-94: 很好,只有一个小瑕疵
        • 70-84: OK 但有可见问题
        • 55-69: 明显问题
        • 40-54: 严重问题
        • 0-39:  危险

        【禁令】
        - 不要默认全打 85
        - 不要让 4 个维度分数趋同(除非确实都一样好/一样差)
        - 不要因为历史分数 85 就这次也 85 —— 独立判断
        - 四个维度分数必须和对应文字描述一致:
          * "眼睛明亮有神" → eyes ≥ 88
          * "毛发有些粗糙" → fur 必须 < 80
          * "神情萎靡" → energy 必须 < 65

        summary 里一句话说明**最弱那个维度的主要扣分点**。

        【安全规则】
        1. 如果照片里没有猫或猫脸太模糊/太远/被遮挡：
           - breed 必须返回 "no-cat-detected"
           - healthScore 返回 0
           - summary 写：照片里好像没看清小猫咪喵,换张更清楚的再来?
           - 其他字段用"—"占位,不要瞎编
        2. 某个状态如果无法从照片判断：在对应字段明确写"无法从照片判断"，
           不要为了把表填满而猜测。
        3. 如果你对健康问题拿不准：宁可在 suggestions 里写"建议带去兽医面诊"
           也不要给出可能误导的诊断。
        4. 如发现以下任一严重症状,必须在 warnings 对应条目开头加 [URGENT] 标记：
           呼吸困难/张嘴喘气、大量出血、抽搐/肢体僵直、瞳孔异常或无对光反应、
           严重脱水(皮肤回弹慢)、无法站立、失去意识、持续呕吐、黄疸。
           例如: "[URGENT] 小猫看起来呼吸急促,建议立即就医"

        用温柔朋友的语气，不要用"建议您"，
        直接叫它\(cat.name)，说话像认识它很久的人。

        只返回一个合法的 JSON 对象,不要其他文字,不要 markdown 围栏。
        字段和类型必须和下面这个示例一致(里面的数字/文字是示例,你自己填):
        {
          "breed": "橘色虎斑",
          "furColor": "橘色带白色下巴",
          "personality": "好奇活泼,爱观察主人",
          "subScores": {
            "eyes": 88,
            "fur": 72,
            "posture": 85,
            "energy": 90
          },
          "eyesCondition": "眼睛清澈有神",
          "furCondition": "局部有一点打结",
          "postureCondition": "姿态自然",
          "suggestions": ["多梳毛", "增加饮水", "每天玩耍"],
          "warnings": [],
          "parentBreeds": ["普通虎斑"],
          "lifestyleTag": "food",
          "lifestyleDetail": "食量稳定,注意别过胖",
          "summary": "毛发略打结,其它状态良好"
        }

        重要: subScores 必须是 4 个 0-100 的整数。**不要**输出
        "<0-100 整数>" 这种占位符 —— 直接给具体数字。
        """
    }

    private static func personalityZH(cat: Cat, allRecords: [HistoryRecord]) -> String {
        let lines = allRecords.map {
            "\(timeAgoZH($0.date))（\($0.healthScore)分）：\($0.summary ?? "")"
        }.joined(separator: "\n")
        return """
        基于对\(cat.name)的\(allRecords.count)次检测，生成一段100-150字的性格与健康观察摘要。

        检测历史：
        \(lines)

        要求：用第三人称，轻松口语化，包含性格特点、体态趋势、健康亮点和反复出现的问题。
        格式以"\(cat.name)性格观察（基于\(allRecords.count)次检测）："开头。
        只返回摘要文本，不要其他内容。
        """
    }

    private static func chatZH(cat: Cat, history: [HistoryRecord], lastReport: HealthReport?, question: String) -> String {
        let historyLines = history.prefix(3).map {
            "\(timeAgoZH($0.date))（\($0.healthScore)分）：\($0.summary ?? "")"
        }.joined(separator: "\n")
        let score   = lastReport.map { "\($0.healthScore)" } ?? "?"
        let eyes    = lastReport?.eyesCondition ?? "未知"
        let fur     = lastReport?.furCondition ?? "未知"
        let posture = lastReport?.postureCondition ?? "未知"

        return """
        你是认识\(cat.name)很久的朋友，刚帮它做完了一次健康检测。

        \(cat.name)的档案：\([cat.age, cat.breed].compactMap { $0 }.joined(separator: "的"))，\(cat.neuter ? "已绝育" : "未绝育")
        \(cat.knownIssues.isEmpty ? "" : "已知问题：\(cat.knownIssues.joined(separator: "、"))")
        \(cat.personalitySummary.map { "性格：\($0)" } ?? "")

        本次检测（\(score)分）：眼睛：\(eyes)  毛发：\(fur)  体态：\(posture)

        近期历史：
        \(historyLines.isEmpty ? "暂无" : historyLines)

        主人现在问：\(question)

        用温柔朋友的语气回答，不超过200字，结合\(cat.name)的具体情况给具体建议，直接叫它\(cat.name)。
        """
    }

    // MARK: - English

    private static func analysisEN(cat: Cat, history: [HistoryRecord], todayNote: String?, recentLogs: [DailyLog]) -> String {
        let checkNum    = history.count + 1
        let issues      = cat.knownIssues.isEmpty ? "" : ". Owner notes: \(cat.knownIssues.joined(separator: ", "))"
        let breedLine   = [cat.age, cat.breed].compactMap { $0 }.joined(separator: " ")
        let neuterStr   = cat.neuter ? "neutered" : "intact"
        let personality = cat.personalitySummary.map { "\nPersonality profile for \(cat.name):\n\($0)\n" } ?? ""
        let historyLines = history.prefix(3).map {
            "- \(timeAgoEN($0.date)) (score: \($0.healthScore)): \($0.summary ?? "general health assessment")"
        }.joined(separator: "\n")
        let note = todayNote?.trimmingCharacters(in: .whitespaces).isEmpty == false ? todayNote! : "No special notes today"
        let diary = diarySummary(recentLogs, zh: false)

        return """
        This is check #\(checkNum) for \(cat.name).
        \(cat.name) is a \(breedLine) cat, \(neuterStr)\(issues).
        \(personality)
        Check history (for trend comparison only — do NOT anchor this check's score to past scores):
        \(historyLines.isEmpty ? "(First check — no history yet)" : historyLines)
        \(diary)

        Owner's note today: \(note)

        Please analyze this photo using the context above.
        In your analysis you must:
        - Compare with the last check and explicitly state: improved / worsened / stable
        - If an issue has appeared 2+ times in a row, emphasize it: "This is now the Nth time we've seen this"
        - If a previously flagged issue has improved, explicitly praise the progress

        [STRUCTURED SCORING — STRICT]
        Do NOT give a single overall score — you must grade FOUR dimensions
        independently on 0-100. Code will compute the composite from weights;
        don't compute it yourself.

        The four dimensions:
        • eyes:    clarity, discharge/redness/squinting, spark of alertness
        • fur:     smoothness, shine, mats/greasy/patchy/dirty
        • posture: natural vs hunched/stiff, body condition (over/underweight)
        • energy:  alert vs listless, demeanor in the photo

        Per-dimension rubric:
        • 95-100: this dimension shows no flaw
        • 85-94:  very good with ONE tiny imperfection
        • 70-84:  OK but a visible issue
        • 55-69:  clear problem
        • 40-54:  serious problem
        • 0-39:   dangerous

        [FORBIDDEN]
        - Do NOT default all four to 85.
        - Do NOT let the four scores cluster (unless the cat genuinely is uniformly good/bad).
        - Do NOT anchor on the cat's past scores — grade this check fresh.
        - Each dimension score must match its textual description:
          * "Bright, alert eyes" → eyes ≥ 88
          * "Slightly coarse fur" → fur must be < 80
          * "Listless look"      → energy must be < 65

        In `summary`, one sentence about the weakest dimension's main deduction.

        [SAFETY RULES]
        1. If there is no cat in the photo, or the cat's face is too blurry / too far / occluded:
           - Set breed to "no-cat-detected"
           - Set healthScore to 0
           - Set summary to: "I can't see a clear cat in this photo — mind taking another?"
           - Fill other fields with "—"; do NOT fabricate.
        2. If you cannot judge a specific condition from the photo, write
           "Cannot tell from photo" in that field. Never guess to fill the blank.
        3. When uncertain about a health issue, prefer suggesting a vet visit
           over giving a diagnosis that could mislead.
        4. If any of the following severe symptoms are visible, prefix the
           relevant warning with [URGENT]:
           labored/open-mouth breathing, heavy bleeding, seizure/stiffness,
           abnormal or non-responsive pupils, severe dehydration (slow skin
           tent), inability to stand, unconsciousness, persistent vomiting,
           jaundice.
           Example: "[URGENT] Breathing looks rapid — see a vet immediately."

        Use a warm, friendly tone as if you've known \(cat.name) for years. Call them by name. Avoid formal phrasing like "I recommend you".

        Return one valid JSON object only — no prose, no markdown fences.
        Fields + types must match this example (values are placeholders, fill yours):
        {
          "breed": "Orange Tabby",
          "furColor": "Orange with white chest",
          "personality": "Curious and playful, often watches the owner",
          "subScores": {
            "eyes": 88,
            "fur": 72,
            "posture": 85,
            "energy": 90
          },
          "eyesCondition": "Clear and alert eyes",
          "furCondition": "Minor matting on one side",
          "postureCondition": "Natural, relaxed",
          "suggestions": ["Brush more often", "Encourage hydration", "15 min wand play"],
          "warnings": [],
          "parentBreeds": ["Domestic shorthair"],
          "lifestyleTag": "food",
          "lifestyleDetail": "Appetite stable, watch weight",
          "summary": "Slight fur matting; otherwise good."
        }

        Important: subScores must be four integers 0-100. **Never** output
        placeholder syntax like "<integer 0-100>" — emit actual numbers.
        """
    }

    private static func personalityEN(cat: Cat, allRecords: [HistoryRecord]) -> String {
        let lines = allRecords.map {
            "\(timeAgoEN($0.date)) (score: \($0.healthScore)): \($0.summary ?? "")"
        }.joined(separator: "\n")
        return """
        Based on \(allRecords.count) health checks for \(cat.name), write a 100-150 word personality and health observation summary.

        Check history:
        \(lines)

        Requirements: third person, casual and friendly tone, include personality traits, body condition trend, health highlights, and recurring issues.
        Start with "\(cat.name)'s Profile (based on \(allRecords.count) checks):".
        Return only the summary text, nothing else.
        """
    }

    private static func chatEN(cat: Cat, history: [HistoryRecord], lastReport: HealthReport?, question: String) -> String {
        let historyLines = history.prefix(3).map {
            "\(timeAgoEN($0.date)) (score: \($0.healthScore)): \($0.summary ?? "")"
        }.joined(separator: "\n")
        let score   = lastReport.map { "\($0.healthScore)" } ?? "?"
        let eyes    = lastReport?.eyesCondition ?? "unknown"
        let fur     = lastReport?.furCondition ?? "unknown"
        let posture = lastReport?.postureCondition ?? "unknown"

        return """
        You're a good friend who has known \(cat.name) for years and just finished a health check for them.

        \(cat.name)'s profile: \([cat.age, cat.breed].compactMap { $0 }.joined(separator: " ")), \(cat.neuter ? "neutered" : "intact")
        \(cat.knownIssues.isEmpty ? "" : "Known issues: \(cat.knownIssues.joined(separator: ", "))")
        \(cat.personalitySummary.map { "Personality: \($0)" } ?? "")

        This check (\(score)/100): Eyes: \(eyes)  Fur: \(fur)  Posture: \(posture)

        Recent history:
        \(historyLines.isEmpty ? "No history yet" : historyLines)

        Owner asks: \(question)

        Answer in a warm, friendly tone under 150 words. Give specific advice based on \(cat.name)'s situation — not generic answers. Call them by name.
        """
    }

    // MARK: - Helpers

    private static func timeAgoZH(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days < 7  { return "\(days)天前" }
        if days < 30 { return "\(days / 7)周前" }
        return "\(days / 30)个月前"
    }

    private static func timeAgoEN(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days < 7  { return "\(days)d ago" }
        if days < 30 { return "\(days / 7)w ago" }
        return "\(days / 30)mo ago"
    }
}
