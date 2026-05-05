import UIKit
import Foundation

/// Calls the Carmel Worker proxy (which holds the real Anthropic API key).
/// iOS client sends: image_base64 (optional) + prompt + X-Device-Id header.
/// Worker enforces per-device rate limit and forwards to Anthropic.
final class ClaudeService {
    static let shared = ClaudeService()
    private init() {}

    // Swap to https://api.carmel.app/analyze once the custom domain is bound.
    private let endpoint = URL(string: "https://carmel-worker.8fn98bvpdb.workers.dev/analyze")!

    // MARK: - Core proxy call

    private func proxy(imageBase64: String?, prompt: String,
                       maxTokens: Int = 1500,
                       tier: Tier = .economy) async throws -> String {
        // First attempt. On HTTP 402 (server says quota exhausted) we
        // assume iOS-Worker entitlement state has drifted — re-sync every
        // verified StoreKit transaction and retry exactly once. Without
        // this, a real user whose original /verify-receipt POST quietly
        // failed (network blip, Apple API delay) would see "you paid but
        // can't use the app" until they reinstalled.
        do {
            return try await executeProxyOnce(imageBase64: imageBase64, prompt: prompt,
                                              maxTokens: maxTokens, tier: tier)
        } catch ClaudeError.apiError(let msg) where msg.contains("HTTP 402") {
            await SubscriptionManager.shared.resyncEntitlementsWithWorker()
            return try await executeProxyOnce(imageBase64: imageBase64, prompt: prompt,
                                              maxTokens: maxTokens, tier: tier)
        }
    }

    /// Single-shot of the proxy call. `proxy` wraps this with the 402
    /// self-heal so callers don't have to know about retry semantics.
    private func executeProxyOnce(imageBase64: String?, prompt: String,
                                  maxTokens: Int, tier: Tier) async throws -> String {
        var body: [String: Any] = [
            "prompt": prompt,
            "max_tokens": maxTokens,
        ]
        if let imageBase64 {
            body["image_base64"] = imageBase64
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceID.current,      forHTTPHeaderField: "X-Device-Id")
        // Worker reads this and picks Haiku 4.5 (economy) vs Sonnet 4.6
        // (premium). Default economy keeps cost minimal even if the iOS
        // call site forgot to specify a tier.
        req.setValue(tier.headerValue,      forHTTPHeaderField: "X-Tier")
        // Worker's entitlement ledger is keyed on this UUID — same across
        // devices for one Apple ID, so subscriptions follow the user.
        // `appAccountToken` is a sync accessor (UserDefaults read), so no
        // await is needed even though SubscriptionManager itself is @MainActor.
        let token = SubscriptionManager.shared.appAccountToken.uuidString
        req.setValue(token, forHTTPHeaderField: "X-Account-Token")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        if http.statusCode != 200 {
            // Try to surface the Worker's structured error body for nicer UI mapping.
            let bodyText = String(data: data, encoding: .utf8) ?? "unknown"
            if http.statusCode == 429,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reason = json["reason"] as? String {
                throw ClaudeError.apiError("HTTP 429 rate_limited \(reason)")
            }
            throw ClaudeError.apiError("HTTP \(http.statusCode): \(bodyText)")
        }

        // Worker forwards Anthropic's response verbatim. We pick out the text.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw ClaudeError.invalidResponse
        }
        return text
    }

    // MARK: - Streaming primitives

    /// One event in a streaming analyze response. Two phases:
    ///   1. Claude's pre-JSON observation streams as `.observation(delta)` chunks
    ///      (typewriter UX in CameraView).
    ///   2. The moment we detect the opening `{` of the JSON object, we emit
    ///      `.observationDone` once. The caller can transition the UI from
    ///      "AI thinking" to "Generating report…".
    ///   3. Once the upstream stream completes, the buffered text is parsed
    ///      via `HealthReport.from(json:)` and emitted as `.report`.
    enum AnalyzeStreamEvent {
        case observation(String)
        case observationDone
        case report(HealthReport)
    }

    /// Streaming variant of `analyzeImage`. Hands back an AsyncThrowingStream
    /// the caller drives with `for try await`. Sub-second TTFT in practice
    /// (Worker round-trip + Anthropic SSE first byte).
    @MainActor
    func analyzeImageStreaming(_ image: UIImage,
                               cat: Cat? = nil,
                               recentRecords: [HistoryRecord] = [],
                               recentLogs: [DailyLog] = [],
                               todayNote: String? = nil,
                               tier: Tier = .economy,
                               isEnglish: Bool = false) -> AsyncThrowingStream<AnalyzeStreamEvent, Error> {
        // Build the same payload as the buffered path so the report shape
        // is byte-identical between the two — easier to A/B + fallback.
        let resized = Self.downsampleForAnalysis(image, maxDimension: tier.maxImageDimension)
        let base64 = resized.jpegData(compressionQuality: tier.jpegQuality)?.base64EncodedString()

        let basePrompt: String
        if let cat {
            basePrompt = PromptBuilder.buildAnalysis(cat: cat, history: recentRecords,
                                                     todayNote: todayNote,
                                                     recentLogs: recentLogs,
                                                     isEnglish: isEnglish)
        } else {
            basePrompt = isEnglish ? defaultPromptEN : defaultPromptZH
        }
        let prompt = applyLanguageOverride(to: basePrompt)
        let token = SubscriptionManager.shared.appAccountToken.uuidString

        return AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    guard let base64 else {
                        throw ClaudeError.noImageData
                    }

                    let body: [String: Any] = [
                        "prompt": prompt,
                        "max_tokens": 1500,
                        "stream": true,
                        "image_base64": base64,
                    ]

                    var req = URLRequest(url: self.endpoint)
                    req.httpMethod = "POST"
                    req.setValue("application/json",       forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream",      forHTTPHeaderField: "Accept")
                    req.setValue(DeviceID.current,         forHTTPHeaderField: "X-Device-Id")
                    req.setValue(tier.headerValue,         forHTTPHeaderField: "X-Tier")
                    req.setValue(token, forHTTPHeaderField: "X-Account-Token")
                    req.timeoutInterval = 90
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    // First attempt. On HTTP 402 we re-sync StoreKit
                    // entitlements with the Worker and retry exactly once —
                    // catches the case where /verify-receipt failed at
                    // purchase time and left the user "paid client-side,
                    // unknown server-side". Identical pattern to
                    // ClaudeService.proxy's retry wrapper.
                    var (bytes, response) = try await URLSession.shared.bytes(for: req)
                    var http = response as? HTTPURLResponse
                    if http?.statusCode == 402 {
                        await SubscriptionManager.shared.resyncEntitlementsWithWorker()
                        (bytes, response) = try await URLSession.shared.bytes(for: req)
                        http = response as? HTTPURLResponse
                    }
                    guard let httpFinal = http else {
                        throw ClaudeError.invalidResponse
                    }
                    if httpFinal.statusCode != 200 {
                        // Mirror the buffered path's structured 429 surfacing.
                        throw ClaudeError.apiError("HTTP \(httpFinal.statusCode)")
                    }

                    // Accumulators. `fullBuffer` holds every text delta in
                    // arrival order — fed to HealthReport.from(json:) at end.
                    // `observationDoneEmitted` flips the moment we see `{`,
                    // so we stop forwarding observation deltas to the UI.
                    var fullBuffer = ""
                    var observationDoneEmitted = false

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload.isEmpty || payload == "[DONE]" { continue }

                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        // Anthropic SSE: only `content_block_delta` events with
                        // type `text_delta` carry visible model text. Everything
                        // else (message_start, ping, message_delta) is bookkeeping.
                        if let type = event["type"] as? String, type == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           let kind = delta["type"] as? String, kind == "text_delta",
                           let text = delta["text"] as? String, !text.isEmpty {

                            fullBuffer += text

                            if !observationDoneEmitted {
                                if let braceIdx = text.firstIndex(of: "{") {
                                    // Mixed chunk: trailing observation prose
                                    // followed by the JSON's opening brace.
                                    // Emit just the prose part, then the marker.
                                    let head = String(text[..<braceIdx])
                                    if !head.isEmpty {
                                        continuation.yield(.observation(head))
                                    }
                                    continuation.yield(.observationDone)
                                    observationDoneEmitted = true
                                } else {
                                    continuation.yield(.observation(text))
                                }
                            }
                        }
                    }

                    // Stream finished — parse the full buffer as JSON. The
                    // extractor is tolerant of leading observation prose.
                    let report = try HealthReport.from(json: fullBuffer)
                    if !observationDoneEmitted {
                        // Defensive: if the model never emitted a `{` we still
                        // want the UI to leave the streaming state cleanly.
                        continuation.yield(.observationDone)
                    }
                    continuation.yield(.report(report))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Analysis with cat context

    /// Tier of the underlying Claude model picked for this analysis.
    /// Cheaper tier → smaller image + Haiku model. Pro users get the
    /// premium tier in exchange for their subscription, so they stay on
    /// Sonnet for finer detail (subtle eye discharge, fur quality, etc.).
    enum Tier {
        case economy   // Haiku 4.5  · 768px max · JPEG 0.65 → ~$0.003/call
        case premium   // Sonnet 4.6 · 1568px max · JPEG 0.75 → ~$0.018/call

        var maxImageDimension: CGFloat { self == .premium ? 1568 : 768 }
        var jpegQuality: CGFloat       { self == .premium ? 0.75  : 0.65 }
        var headerValue: String        { self == .premium ? "premium" : "economy" }
    }

    func analyzeImage(_ image: UIImage,
                      cat: Cat? = nil,
                      recentRecords: [HistoryRecord] = [],
                      recentLogs: [DailyLog] = [],
                      todayNote: String? = nil,
                      tier: Tier = .economy,
                      isEnglish: Bool = false) async throws -> HealthReport {
        // CRITICAL token-budget guard. Image is downsampled to the tier's
        // ceiling first, so an iPhone Pro 12MP shot doesn't get billed at
        // ~$0.05 — economy tier brings that to ~$0.003.
        let resized = Self.downsampleForAnalysis(image, maxDimension: tier.maxImageDimension)
        guard let imageData = resized.jpegData(compressionQuality: tier.jpegQuality) else {
            throw ClaudeError.noImageData
        }
        let base64 = imageData.base64EncodedString()

        let basePrompt: String
        if let cat {
            basePrompt = PromptBuilder.buildAnalysis(cat: cat, history: recentRecords,
                                                  todayNote: todayNote,
                                                  recentLogs: recentLogs,
                                                  isEnglish: isEnglish)
        } else {
            // No-cat path (used by the "different cat detected" loop, and any
            // analysis without an active profile). Must respect the user's
            // chosen language — never auto-fall-back to English.
            basePrompt = isEnglish ? defaultPromptEN : defaultPromptZH
        }
        // Layer the user's picker language on top of the prompt template.
        // For zh/en the template is already correct so the override is a
        // no-op; for the other 28 supported languages we keep the English
        // structural prompt but tell Claude to write its free-form fields
        // (personality, suggestions, etc.) in the chosen language.
        let prompt = applyLanguageOverride(to: basePrompt)

        let raw = try await proxy(imageBase64: base64, prompt: prompt,
                                   maxTokens: 1500, tier: tier)
        return try HealthReport.from(json: raw)
    }

    // MARK: - Follow-up chat (text-only)

    func chat(cat: Cat,
              history: [HistoryRecord],
              lastReport: HealthReport?,
              question: String,
              isEnglish: Bool = false) async throws -> String {
        let basePrompt = PromptBuilder.buildChat(cat: cat, history: history, lastReport: lastReport, question: question, isEnglish: isEnglish)
        let prompt = await applyLanguageOverride(to: basePrompt)
        // Chat always uses Haiku — the conversation is short-form Q&A and
        // doesn't need Sonnet's vision-reasoning depth. ~10× cheaper.
        return try await proxy(imageBase64: nil, prompt: prompt,
                                maxTokens: 600, tier: .economy)
    }

    // MARK: - Report translation (text-only, Haiku)

    /// Translate the free-form text fields of a HealthReport into the target
    /// language. Returns just the translated fields — caller layers them
    /// over the numeric/enum fields of the original record.
    ///
    /// Cheap by design: Haiku 4.5 + ~600 token cap. Roughly $0.001 per call.
    func translateReport(_ report: HealthReport,
                         toLanguageName targetLanguage: String) async throws -> TranslatedFields {
        // Encode the source fields as compact JSON so Haiku has a clear
        // schema to map keys against. Numeric/enum fields are left out —
        // we only ship what actually needs translating.
        let source: [String: Any] = [
            "breed": report.breed,
            "furColor": report.furColor,
            "personality": report.personality,
            "eyesCondition": report.eyesCondition,
            "furCondition": report.furCondition,
            "postureCondition": report.postureCondition,
            "suggestions": report.suggestions,
            "warnings": report.warnings,
            "lifestyleDetail": report.lifestyleDetail,
            "summary": report.summary ?? "",
        ]
        let sourceJSON = (try? JSONSerialization.data(withJSONObject: source))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let prompt = """
        Translate every string value in the JSON below into \(targetLanguage). \
        Keep all keys exactly as they are in English. Keep array structure for \
        `suggestions` and `warnings`. Don't add or remove keys. Don't add \
        commentary. Return ONLY the translated JSON object.

        Source:
        \(sourceJSON)
        """

        let raw = try await proxy(imageBase64: nil, prompt: prompt,
                                   maxTokens: 800, tier: .economy)

        // Reuse HealthReport's tolerant JSON extractor — strips ```json fences
        // and trims any preamble text Haiku might prepend.
        guard let cleaned = Self.extractJSON(from: raw),
              let data = cleaned.data(using: .utf8),
              let tf = try? JSONDecoder().decode(TranslatedFields.self, from: data) else {
            throw ClaudeError.invalidResponse
        }
        return tf
    }

    /// Public mirror of HealthReport's private JSON extractor — keeps the
    /// translate path tolerant of Haiku occasionally wrapping its output.
    private static func extractJSON(from raw: String) -> String? {
        let stripped = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let start = stripped.firstIndex(of: "{"),
              let end = stripped.lastIndex(of: "}"),
              start < end else { return nil }
        return String(stripped[start...end])
    }

    // MARK: - Personality summary (text-only, stores in cat)

    @MainActor
    func refreshPersonality(cat: Cat, records: [HistoryRecord], isEnglish: Bool = false) async {
        guard records.count >= 3 else { return }
        let prompt = PromptBuilder.buildPersonality(cat: cat, allRecords: records, isEnglish: isEnglish)
        do {
            let summary = try await proxy(imageBase64: nil, prompt: prompt, maxTokens: 400)
            cat.personalitySummary = summary
            // Stamp the count so callers can throttle future refreshes —
            // see `Cat.personalityRefreshedAtCount` for the throttling rule.
            cat.personalityRefreshedAtCount = records.count
        } catch {
            print("[ClaudeService] personality update failed:", error.localizedDescription)
        }
    }

    /// Token-budget cap. Resizes any incoming image so its long side ≤
    /// `maxDimension` (default 1568, Claude vision's effective ceiling).
    /// Preserves aspect ratio. Scale pinned to 1 so we render at exactly
    /// the target pixel count — no surprise 3× retina blow-up.
    static func downsampleForAnalysis(_ image: UIImage, maxDimension: CGFloat = 1568) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longSide = max(w, h)
        // Already small — return as-is, don't waste CPU re-rendering.
        if longSide <= maxDimension { return image }
        let scale = maxDimension / longSide
        let target = CGSize(width: floor(w * scale), height: floor(h * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Append a language instruction when the user's picker is set to
    /// anything other than zh-Hans / zh-Hant / en. The two "primary"
    /// languages already have hand-tuned prompt templates, so we don't
    /// need to override them. For everything else, we keep the English
    /// structural prompt and ask Claude to write all free-form fields in
    /// the chosen language. Claude handles this reliably across the 30
    /// supported languages.
    @MainActor
    private func applyLanguageOverride(to prompt: String) -> String {
        let lang = LanguageManager.shared
        let code = lang.currentLanguage
        if code.hasPrefix("zh") || code == "en" { return prompt }
        let target = lang.aiInstructionLanguage  // e.g. "Spanish"
        return prompt + "\n\nIMPORTANT: All free-form text fields (personality, eyesCondition, furCondition, postureCondition, suggestions, lifestyleDetail, summary, warnings) must be written in \(target). Keep JSON keys and enum values like lifestyleTag in English."
    }

    // MARK: - Default prompts (no cat context)

    private let defaultPromptZH = """
    请仔细分析这张猫咪照片,然后按以下格式输出:
    1) 先用 1-2 句中文平实地说说你看到了什么(纯文字,无 markdown,无 JSON);
    2) 空一行;
    3) 输出严格 JSON 格式的健康报告。

    所有字符串字段(personality / eyesCondition / furCondition / postureCondition /
    suggestions / lifestyleDetail / summary)必须使用中文。

    {
      "breed": "猫的品种",
      "furColor": "毛色描述",
      "personality": "推测的性格(1-2 句中文)",
      "healthScore": <0-100 整数>,
      "subScores": {
        "eyes": <0-100 整数>,
        "fur": <0-100 整数>,
        "posture": <0-100 整数>,
        "energy": <0-100 整数>
      },
      "eyesCondition": "眼睛状况(2 句中文)",
      "furCondition": "毛发状况(2 句中文)",
      "postureCondition": "体态/精神状况(2 句中文)",
      "suggestions": ["中文建议1", "中文建议2", "中文建议3"],
      "warnings": [],
      "parentBreeds": [],
      "lifestyleTag": "water|food|exercise",
      "lifestyleDetail": "一句中文生活建议",
      "summary": "50 字以内的中文总结"
    }

    JSON 后面不要再有任何文字。
    """

    private let defaultPromptEN = """
    Please analyze this cat photo carefully, then output in this format:
    1) 1-2 plain sentences saying what you observe (plain prose, no markdown,
       no JSON characters);
    2) one blank line;
    3) a strict JSON health report.

    All string fields (personality / eyesCondition / furCondition / postureCondition /
    suggestions / lifestyleDetail / summary) must be in English.

    {
      "breed": "Cat breed",
      "furColor": "Fur color description",
      "personality": "Inferred personality (1-2 sentences)",
      "healthScore": <integer 0-100>,
      "subScores": {
        "eyes": <integer 0-100>,
        "fur": <integer 0-100>,
        "posture": <integer 0-100>,
        "energy": <integer 0-100>
      },
      "eyesCondition": "Eyes condition (2 sentences)",
      "furCondition": "Fur condition (2 sentences)",
      "postureCondition": "Posture/energy condition (2 sentences)",
      "suggestions": ["tip1", "tip2", "tip3"],
      "warnings": [],
      "parentBreeds": [],
      "lifestyleTag": "water|food|exercise",
      "lifestyleDetail": "one sentence",
      "summary": "50-character summary of this check"
    }

    Nothing after the JSON.
    """
}
