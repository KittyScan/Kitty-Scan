import SwiftUI
import UIKit

/// In-app feedback / bug-report sheet. Posts to the worker `/feedback`
/// endpoint, which writes to KV (so we can read it server-side without
/// exposing the dev's email in the app binary).
///
/// What we send: the user's free-text message + app version + iOS version
/// + their `Account Token` (for de-anonymization the dev can see — useful
/// for "this user reported X, let me check their entitlement"). We
/// deliberately do NOT send their email or any personal info.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(ThemeProvider.self) private var themeProvider
    @State private var subs = SubscriptionManager.shared

    @State private var text: String = ""
    @State private var category: Category = .general
    @State private var sending = false
    @State private var sendResult: SendResult?
    @State private var showProfanityWarning = false
    @FocusState private var textFocused: Bool

    private var zh: Bool { lang.isChineseSelected }
    private var theme: CatTheme { themeProvider.theme }

    private static let endpoint = URL(string: "https://carmel-worker.8fn98bvpdb.workers.dev/feedback")!
    private static let maxChars = 2000
    /// Lowered to 2. Five excluded short Chinese feedback like
    /// "卡了" / "崩了" / "好的" that are perfectly valid signals. The
    /// validation is just a spam filter, not a quality bar — anything
    /// shorter than 2 chars is almost certainly a mis-tap.
    private static let minChars = 2

    enum Category: String, CaseIterable, Identifiable {
        case bug, feature, billing, general
        var id: String { rawValue }
        func label(zh: Bool) -> String {
            switch self {
            case .bug:      return zh ? "Bug 报告" : "Bug"
            case .feature:  return zh ? "功能建议" : "Feature idea"
            case .billing:  return zh ? "订阅 / 付费" : "Billing"
            case .general:  return zh ? "其他反馈" : "Other"
            }
        }
    }

    enum SendResult: Identifiable {
        case ok
        case failure(String)
        var id: String {
            switch self {
            case .ok: return "ok"
            case .failure(let s): return "fail:\(s)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        Picker(zh ? "类型" : "Category", selection: $category) {
                            ForEach(Category.allCases) { c in
                                Text(c.label(zh: zh)).tag(c)
                            }
                        }
                    }

                    Section {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $text)
                                .frame(minHeight: 160)
                                .font(.body)
                                .focused($textFocused)
                            if text.isEmpty {
                                Text(zh
                                     ? "尽量描述清楚:你做了什么操作?预期发生什么?实际发生什么?"
                                     : "Describe what you did, what you expected, and what actually happened.")
                                    .font(.body)
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    } header: {
                        Text(zh ? "你的反馈" : "Your feedback")
                    } footer: {
                        HStack {
                            // Hint: tells the user when they're below minChars,
                            // so they understand WHY Send is grey instead of
                            // tapping helplessly.
                            if !canSubmit && !text.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(zh ? "再写几个字就能发了喵" : "A few more words to enable Send")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            Text("\(text.count) / \(Self.maxChars)")
                                .font(.caption)
                                .foregroundColor(text.count > Self.maxChars ? Theme.danger : .secondary)
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .animation(.easeInOut(duration: 0.18), value: textFocused)


                // Visible "hide keyboard" affordance — only shows when the
                // editor is focused. Many users don't realize the small
                // "完成" in the keyboard accessory toolbar is tappable, so
                // this gives an obvious in-canvas alternative right above
                // the action bar. Disappears when keyboard is down so it
                // doesn't add noise.
                if textFocused {
                    Button {
                        textFocused = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                            Text(zh ? "收起键盘" : "Hide keyboard")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.deep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(theme.card.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Fixed bottom action bar — always tappable regardless of
                // keyboard state. Replaces the (sometimes unresponsive)
                // toolbar Cancel/Send buttons; toolbar Cancel kept as a
                // backup but the big visible buttons are the primary path.
                bottomActionBar
            }
            .navigationTitle(zh ? "提交问题" : "Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Backup Cancel — most users will use the bottom one.
                ToolbarItem(placement: .cancellationAction) {
                    Button(zh ? "关闭" : "Close") { dismiss() }
                }
                // Keyboard "Done" — gives the user an explicit way to drop
                // the keyboard so the bottom action bar (and the rest of the
                // form) becomes reachable. Beefier styling than the default
                // text-only "Done" so it doesn't get lost in the toolbar.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        textFocused = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down.circle.fill")
                            Text(zh ? "收起键盘" : "Hide keyboard")
                        }
                        .font(.body.weight(.semibold))
                    }
                }
            }
            .overlay {
                if sending {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView(zh ? "发送中..." : "Sending...")
                            .padding(20)
                            .background(Theme.cardPrimary)
                            .cornerRadius(12)
                    }
                }
            }
            .alert(zh ? "话有点重哦~" : "Strong language detected",
                   isPresented: $showProfanityWarning) {
                Button(zh ? "改一改" : "Edit") {
                    showProfanityWarning = false
                    textFocused = true
                }
                Button(zh ? "继续发送" : "Send anyway", role: .destructive) {
                    showProfanityWarning = false
                    Task {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        await actuallySend(trimmed: trimmed)
                    }
                }
            } message: {
                Text(zh
                     ? "你的反馈里有几个不太友好的词,我们的小伙伴看到会有点难过 (；ω；)\n要不换个温柔点的说法?"
                     : "Your feedback has a few rough words — our team would prefer something nicer (；ω；)\nWant to revise it?")
            }
            .alert(item: $sendResult) { result in
                switch result {
                case .ok:
                    return Alert(
                        title: Text(zh ? "已收到 ❤️" : "Thanks ❤️"),
                        message: Text(zh
                                      ? "你的反馈已经送到。我们会一条条看,有重要更新会在下次发版的更新说明里告诉你。"
                                      : "Your feedback has been sent. We read every one and reply via release notes."),
                        dismissButton: .default(Text(zh ? "好的" : "OK")) {
                            dismiss()
                        }
                    )
                case .failure(let msg):
                    return Alert(
                        title: Text(zh ? "发送失败" : "Couldn't send"),
                        message: Text(msg),
                        dismissButton: .default(Text(zh ? "我知道了" : "OK"))
                    )
                }
            }
        }
    }

    private var canSubmit: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= Self.minChars && trimmed.count <= Self.maxChars
    }

    /// Always-visible bottom action bar. Two large buttons; both are
    /// guaranteed-tappable because they live below the form, outside the
    /// scroll/keyboard interaction area where the original toolbar buttons
    /// would sometimes get swallowed.
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text(zh ? "取消" : "Cancel")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.deep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.card.opacity(0.7))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 6) {
                    if sending {
                        ProgressView().tint(theme.bg)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(zh ? "发送" : "Send")
                        .font(.body.weight(.bold))
                }
                .foregroundStyle(canSubmit ? theme.bg : theme.bg.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSubmit ? theme.deep : theme.deep.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || sending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func send() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minChars, trimmed.count <= Self.maxChars else { return }

        // Profanity nudge — gentle "watch the language" pop-up. User can
        // still force-send, we just want to encourage civility before the
        // message lands in our inbox. Run on the trimmed text so leading
        // whitespace can't hide a slur.
        if ProfanityFilter.containsProfanity(trimmed) {
            showProfanityWarning = true
            return
        }

        await actuallySend(trimmed: trimmed)
    }

    /// Performs the network POST. Split out from `send()` so the profanity
    /// alert's "Send anyway" handler can call this directly without
    /// re-running the warning check.
    private func actuallySend(trimmed: String) async {
        sending = true
        defer { sending = false }

        let payload: [String: Any] = [
            "category":   category.rawValue,
            "text":       trimmed,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            "appBuild":   Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            "iosVersion": UIDevice.current.systemVersion,
            "language":   lang.currentLanguage,
        ]

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(subs.appAccountToken.uuidString, forHTTPHeaderField: "X-Account-Token")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                sendResult = .ok
            } else {
                // Pull the worker's `error` field out of the JSON response
                // and translate to a friendly message — opaque "Server error
                // (400)" tells the user nothing actionable.
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                let workerErr = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                sendResult = .failure(friendlyError(code: code, workerError: workerErr))
            }
        } catch {
            sendResult = .failure(zh
                ? "网络好像出问题了,等下再来一次?"
                : "Network hiccup — try again in a moment?")
        }
    }

    /// Map worker error codes to user-facing strings. Each known case has a
    /// short hint about what to do next; unknown codes fall through to a
    /// generic message that still mentions the status code for our own
    /// debugging via screenshots.
    private func friendlyError(code: Int, workerError: String?) -> String {
        switch (code, workerError) {
        case (400, "too_short"):
            return zh ? "内容太短了,再多写几个字喵" : "Too short — add a few more words"
        case (413, "too_long"):
            return zh ? "内容太长了,精简一下再来" : "Too long — trim a bit"
        case (400, "invalid_category"):
            return zh ? "类目选错了,重选一下吧" : "Pick a category and try again"
        case (429, _):
            return zh
                ? "今天发太多次啦 (>ω<) 明天再来吧~"
                : "Too many today (>ω<) Try again tomorrow"
        case (400, _):
            return zh ? "请求格式不对,可能是 App 版本要更新" : "Bad request — try updating the app"
        case (500..<600, _):
            return zh ? "服务器累趴下了,稍等再来" : "Server's having a moment, try again later"
        default:
            return zh ? "发送失败 (\(code)) 试试再来一次" : "Send failed (\(code)) — try again"
        }
    }
}
