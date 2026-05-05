import UIKit
import Foundation

/// Multi-turn agent loop for Pro analyses.
///
/// The iOS client owns the loop. Each turn is one POST to the Worker's
/// `/agent` endpoint, which forwards the messages array to Claude with
/// tool definitions attached. When Claude responds with `tool_use` blocks,
/// we resolve them locally (against SwiftData) and append `tool_result`
/// blocks to the conversation; the next turn carries the lot back. The
/// loop ends the turn Claude responds with text instead of a tool call.
///
/// Why server-stateless / client-loop:
///   • Tool data (`HistoryRecord`, `DailyLog`) lives in SwiftData on the
///     device. Round-tripping it to the Worker just to forward back is
///     pointless.
///   • Worker stays stateless per request — same auth + rate-limit
///     defenses as `/analyze`, no session storage.
///   • Cost: only the final consume-turn decrements the user's quota
///     (Worker enforces via `consume: true` flag). 1 photo = 1 Pro slot,
///     even with 4 internal turns.
///
/// Free + pack users do NOT use this path — they get the Phase 1
/// streaming single-shot. Agent mode is the Pro-tier differentiator.
@MainActor
final class AgentRunner {
    static let shared = AgentRunner()
    private init() {}

    private let endpoint = URL(string: "https://carmel-worker.8fn98bvpdb.workers.dev/agent")!
    private let consumeEndpoint = URL(string: "https://carmel-worker.8fn98bvpdb.workers.dev/consume-analysis")!

    // MARK: - Public events

    /// One event in an agent run. UI consumers care about `.stage` for the
    /// progress card; `.report` is the terminal happy-path event. The
    /// trailing `.trace` carries observability metadata for the eventual
    /// eval pipeline (Phase 3) — emitted right before `.report`.
    enum AgentEvent {
        case stage(Stage)
        case toolStarted(name: ToolName)
        case toolFinished(name: ToolName, summary: String)
        case report(HealthReport)
        case trace(AgentTrace)
    }

    enum Stage: String {
        case observing       = "observing"        // initial, before first tool
        case gatheringContext = "gathering"        // tool round in flight
        case synthesizing    = "synthesizing"     // final round
    }

    enum ToolName: String, Codable {
        case getScanHistory = "get_scan_history"
        case getDiaryEntries = "get_diary_entries"
    }

    /// Captured for every run. Future work (Phase 3 eval pipeline) reads
    /// these off the UI thread and persists them so we can analyze tool
    /// call patterns, latency tails, and prompt regressions.
    struct AgentTrace {
        var toolsCalled: [ToolName] = []
        var totalTurns: Int = 0
        var durationMs: Int = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
    }

    // MARK: - Run

    func runAnalysis(image: UIImage,
                     cat: Cat?,
                     recentRecords: [HistoryRecord],
                     recentLogs: [DailyLog],
                     todayNote: String?,
                     isEnglish: Bool) -> AsyncThrowingStream<AgentEvent, Error> {
        // Encode image once at Haiku's economy ceiling (768px / q0.65).
        // The agent runs against Haiku 4.5 server-side, which doesn't
        // benefit from the larger Sonnet-tier image — and the smaller
        // payload also cuts ~3× off per-turn input token cost.
        let resized = ClaudeService.downsampleForAnalysis(image, maxDimension: 768)
        let imageData = resized.jpegData(compressionQuality: 0.65)
        let base64 = imageData?.base64EncodedString()

        let systemPrompt = AgentPromptBuilder.systemPrompt(cat: cat, todayNote: todayNote, isEnglish: isEnglish)
        let token = SubscriptionManager.shared.appAccountToken.uuidString

        return AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    guard let base64 else {
                        throw ClaudeError.noImageData
                    }
                    let started = Date()
                    var trace = AgentTrace()

                    // Initial user message: photo + the analyst directive. Subsequent
                    // turns append assistant messages and user messages with
                    // tool_result blocks, but the image stays in the conversation
                    // by virtue of being in the original turn.
                    var messages: [[String: Any]] = [[
                        "role": "user",
                        "content": [
                            ["type": "image",
                             "source": ["type": "base64",
                                        "media_type": "image/jpeg",
                                        "data": base64]],
                            ["type": "text",
                             "text": AgentPromptBuilder.openingTurnPrompt(isEnglish: isEnglish)],
                        ],
                    ]]

                    await continuation.yield(.stage(.observing))

                    // Bounded loop. Hard cap of 6 turns prevents pathological
                    // ping-pong if the model gets confused. In practice we expect
                    // 3-4 turns: opener → get_scan_history → get_diary_entries →
                    // final synthesis (+ maybe one extra if the model retries).
                    let maxTurns = 6
                    var lastTextResponse: String?

                    for turn in 0..<maxTurns {
                        let isLastAllowed = (turn == maxTurns - 1)
                        // On the very last allowed turn, drop the tools so the
                        // model is forced into the synthesis path. Otherwise it
                        // could keep calling tools forever.
                        let toolsForTurn: [[String: Any]]? = isLastAllowed ? nil : Self.toolDefinitions
                        let response = try await Self.callAgent(
                            endpoint: self.endpoint,
                            accountToken: token,
                            systemPrompt: systemPrompt,
                            messages: messages,
                            tools: toolsForTurn,
                            maxTokens: 1500,
                        )
                        trace.totalTurns += 1
                        trace.inputTokens += response.usage.inputTokens
                        trace.outputTokens += response.usage.outputTokens

                        // Inspect content blocks. Anthropic returns either:
                        //   - all `text` blocks (no tools called) → terminal turn
                        //   - one or more `tool_use` blocks → resolve and continue
                        let toolUses = response.content.compactMap { $0.asToolUse }
                        let textBlocks = response.content.compactMap { $0.asText }

                        if toolUses.isEmpty {
                            // Synthesis turn — collect the text and break.
                            lastTextResponse = textBlocks.joined(separator: "\n")
                            break
                        }

                        // Append the assistant turn (so the model sees its own
                        // tool_use block on the next round) followed by a user
                        // turn carrying the tool_result blocks.
                        messages.append([
                            "role": "assistant",
                            "content": response.content.map { $0.rawDictionary },
                        ])

                        var toolResultBlocks: [[String: Any]] = []
                        for tu in toolUses {
                            let name = ToolName(rawValue: tu.name)
                            if let name {
                                await continuation.yield(.stage(.gatheringContext))
                                await continuation.yield(.toolStarted(name: name))
                                let result = await Self.resolveTool(
                                    name: name,
                                    input: tu.input,
                                    cat: cat,
                                    recentRecords: recentRecords,
                                    recentLogs: recentLogs,
                                    isEnglish: isEnglish,
                                )
                                trace.toolsCalled.append(name)
                                await continuation.yield(.toolFinished(name: name, summary: result.summary))
                                toolResultBlocks.append([
                                    "type": "tool_result",
                                    "tool_use_id": tu.id,
                                    "content": result.payload,
                                ])
                            } else {
                                // Unknown tool — feed back an error so the model
                                // can correct itself. Don't fail the whole run.
                                toolResultBlocks.append([
                                    "type": "tool_result",
                                    "tool_use_id": tu.id,
                                    "content": "error: unknown tool",
                                    "is_error": true,
                                ])
                            }
                        }
                        messages.append(["role": "user", "content": toolResultBlocks])
                    }

                    guard let finalText = lastTextResponse, !finalText.isEmpty else {
                        throw ClaudeError.invalidResponse
                    }

                    await continuation.yield(.stage(.synthesizing))

                    // Parse first — if the model gave us an unparseable response,
                    // we don't want to charge the user for it. Decrement only on
                    // a fully successful run.
                    let report = try HealthReport.from(json: finalText)

                    // Decrement quota out-of-band. /consume-analysis is a tiny
                    // KV-only endpoint (no Anthropic call) so the cost of this
                    // round-trip is negligible. If the network drops here the
                    // user keeps their analysis — acceptable edge case.
                    try? await Self.consumeOnce(endpoint: self.consumeEndpoint, accountToken: token)

                    trace.durationMs = Int(Date().timeIntervalSince(started) * 1000)
                    await continuation.yield(.trace(trace))
                    await continuation.yield(.report(report))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Tool definitions (Anthropic schema)

    /// JSON-Schema-shaped tool descriptors. Names + parameters mirror what
    /// the Worker contract expects (none — the Worker just forwards them).
    /// Kept as a static plain dictionary so we can JSON-encode without an
    /// extra Codable dance.
    static let toolDefinitions: [[String: Any]] = [
        [
            "name": ToolName.getScanHistory.rawValue,
            "description": """
            Retrieve the cat's previous scan results with key observations \
            and per-axis health scores. Call this before forming a verdict so \
            you can compare today's photo against the trend, not in isolation.
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "n": [
                        "type": "integer",
                        "description": "Number of past scans to fetch (most-recent first). Default 5.",
                        "default": 5,
                    ],
                ],
            ],
        ],
        [
            "name": ToolName.getDiaryEntries.rawValue,
            "description": """
            Retrieve owner-logged diary entries — meals, water intake, mood, \
            and any flagged unusual behavior — within the last N days. Useful \
            when something in the photo (low energy, dull coat) needs to be \
            cross-checked against routine signals.
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "days": [
                        "type": "integer",
                        "description": "Number of days back to fetch. Default 7.",
                        "default": 7,
                    ],
                ],
            ],
        ],
    ]

    // MARK: - Tool resolution

    private struct ToolResolution {
        let summary: String        // human-readable for the UI ("3 entries · 2 with low energy")
        let payload: String        // JSON string fed to Claude as tool_result content
    }

    private static func resolveTool(name: ToolName,
                                    input: [String: Any],
                                    cat: Cat?,
                                    recentRecords: [HistoryRecord],
                                    recentLogs: [DailyLog],
                                    isEnglish: Bool) async -> ToolResolution {
        switch name {
        case .getScanHistory:
            let n = (input["n"] as? Int) ?? 5
            let slice = Array(recentRecords.prefix(max(1, min(n, 10))))
            let entries: [[String: Any]] = slice.map { r in
                // HistoryRecord stores per-axis scores as flat optional Ints
                // (eyesScore, furScore, ...) rather than a nested SubScores
                // struct — see HistoryRecord.swift. Coalesce to NSNull for
                // the JSON encoder so missing scores serialise as `null`
                // instead of being dropped.
                [
                    "date": ISO8601DateFormatter().string(from: r.date),
                    "health_score": r.healthScore,
                    "summary": r.summary ?? "",
                    "eyes_score":    r.eyesScore    ?? NSNull(),
                    "fur_score":     r.furScore     ?? NSNull(),
                    "posture_score": r.postureScore ?? NSNull(),
                    "energy_score":  r.energyScore  ?? NSNull(),
                ]
            }
            let payload = jsonString([
                "count": entries.count,
                "scans": entries,
            ])
            let summary = isEnglish
                ? "\(entries.count) past scan\(entries.count == 1 ? "" : "s")"
                : "\(entries.count) 次历史记录"
            return ToolResolution(summary: summary, payload: payload)

        case .getDiaryEntries:
            let days = (input["days"] as? Int) ?? 7
            let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, min(days, 30)), to: Date()) ?? Date()
            let slice = recentLogs.filter { $0.date >= cutoff }
            let entries: [[String: Any]] = slice.map { l in
                [
                    "date": ISO8601DateFormatter().string(from: l.date),
                    "meals": l.foodCount,
                    "water": l.waterCount,
                    "mood":     l.moodScore   ?? NSNull(),
                    "weight_g": l.weightGrams ?? NSNull(),
                    "discomfort": l.hasDiscomfort,
                    "notes": l.notes,
                ]
            }
            let payload = jsonString([
                "count": entries.count,
                "days_window": days,
                "entries": entries,
            ])
            let unusual = slice.filter { $0.hasDiscomfort }.count
            let summary = isEnglish
                ? "\(entries.count) day\(entries.count == 1 ? "" : "s") logged\(unusual > 0 ? " · \(unusual) unusual" : "")"
                : "\(entries.count) 天日记\(unusual > 0 ? " · \(unusual) 天异常" : "")"
            return ToolResolution(summary: summary, payload: payload)
        }
    }

    // MARK: - HTTP

    private struct AgentResponse {
        struct ContentBlock {
            let kind: String                // "text" | "tool_use"
            let text: String?
            let toolUseId: String?
            let toolName: String?
            let toolInput: [String: Any]?
            let rawDictionary: [String: Any]   // round-trip back to Anthropic on next turn

            var asText: String? { kind == "text" ? text : nil }
            var asToolUse: ToolUse? {
                guard kind == "tool_use", let id = toolUseId, let name = toolName else { return nil }
                return ToolUse(id: id, name: name, input: toolInput ?? [:])
            }
        }
        struct ToolUse { let id: String; let name: String; let input: [String: Any] }
        struct Usage { let inputTokens: Int; let outputTokens: Int }
        let content: [ContentBlock]
        let usage: Usage
    }

    private static func callAgent(endpoint: URL,
                                  accountToken: String,
                                  systemPrompt: String,
                                  messages: [[String: Any]],
                                  tools: [[String: Any]]?,
                                  maxTokens: Int) async throws -> AgentResponse {
        // Anthropic's Messages API accepts a top-level `system` string AND a
        // messages array. The Worker's /agent endpoint passes both straight
        // through. We assemble the full body here.
        var body: [String: Any] = [
            "messages": messages,
            "max_tokens": maxTokens,
            "stream": false,
            "system": systemPrompt,
        ]
        if let tools, !tools.isEmpty { body["tools"] = tools }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceID.current,    forHTTPHeaderField: "X-Device-Id")
        req.setValue("premium",           forHTTPHeaderField: "X-Tier")
        req.setValue(accountToken,        forHTTPHeaderField: "X-Account-Token")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Self-heal on 402 — same pattern as ClaudeService.proxy /
        // analyzeImageStreaming. /agent gates on entitlement.tier === 'sub'
        // AND on quota; both can disagree with iOS local state if a past
        // /verify-receipt POST failed. Re-sync every verified StoreKit
        // transaction and retry once before propagating the error.
        var (data, response) = try await URLSession.shared.data(for: req)
        var http = response as? HTTPURLResponse
        if http?.statusCode == 402 {
            await SubscriptionManager.shared.resyncEntitlementsWithWorker()
            (data, response) = try await URLSession.shared.data(for: req)
            http = response as? HTTPURLResponse
        }
        guard let httpFinal = http else { throw ClaudeError.invalidResponse }
        if httpFinal.statusCode != 200 {
            let text = String(data: data, encoding: .utf8) ?? "unknown"
            throw ClaudeError.apiError("HTTP \(httpFinal.statusCode): \(text)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.invalidResponse
        }

        let usageDict = json["usage"] as? [String: Any] ?? [:]
        let usage = AgentResponse.Usage(
            inputTokens: (usageDict["input_tokens"] as? Int) ?? 0,
            outputTokens: (usageDict["output_tokens"] as? Int) ?? 0,
        )

        let rawContent = json["content"] as? [[String: Any]] ?? []
        let blocks: [AgentResponse.ContentBlock] = rawContent.compactMap { dict in
            let type = (dict["type"] as? String) ?? ""
            switch type {
            case "text":
                return AgentResponse.ContentBlock(
                    kind: "text",
                    text: dict["text"] as? String,
                    toolUseId: nil, toolName: nil, toolInput: nil,
                    rawDictionary: dict,
                )
            case "tool_use":
                return AgentResponse.ContentBlock(
                    kind: "tool_use",
                    text: nil,
                    toolUseId: dict["id"] as? String,
                    toolName: dict["name"] as? String,
                    toolInput: dict["input"] as? [String: Any],
                    rawDictionary: dict,
                )
            default:
                // Future content types (thinking, image, etc.) — round-trip
                // them so we don't silently lose state across turns.
                return AgentResponse.ContentBlock(
                    kind: type, text: nil,
                    toolUseId: nil, toolName: nil, toolInput: nil,
                    rawDictionary: dict,
                )
            }
        }
        return AgentResponse(content: blocks, usage: usage)
    }

    /// Tiny KV-only call to bill the user for one analysis. Best-effort —
    /// we eat network errors so a failed bookkeeping call doesn't roll back
    /// a successful agent run that the user already saw.
    private static func consumeOnce(endpoint: URL, accountToken: String) async throws {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        req.setValue(DeviceID.current, forHTTPHeaderField: "X-Device-Id")
        req.timeoutInterval = 10
        _ = try await URLSession.shared.data(for: req)
    }

    private static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }
}
