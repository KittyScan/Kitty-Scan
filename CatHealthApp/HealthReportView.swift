import SwiftUI
import UIKit

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String  // "user" | "assistant"
    let text: String
}

struct HealthReportView: View {
    let report: HealthReport
    var cat: Cat? = nil
    var recentRecords: [HistoryRecord] = []
    @Environment(LanguageManager.self) var lang
    @Environment(SubscriptionManager.self) var subs
    @Environment(ThemeProvider.self) private var themeProvider
    private var theme: CatTheme { themeProvider.theme }
    @State private var expanded: Set<String> = ["warnings"]
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var chatMessages: [ChatMessage] = []
    @State private var chatInput = ""
    @FocusState private var chatFocused: Bool
    @State private var isChatting = false
    @State private var showNearbyVets = false
    @State private var chatPaywallReason: SubscriptionManager.GateResult.BlockReason?
    @State private var showMethodology = false

    /// Per-report 👍/👎. Tracked locally so the footer can switch to a
    /// "thanks ♡" confirmation after submission. Routed through the same
    /// /feedback Worker endpoint as the bug-report flow with category
    /// "rating" — server-side that's just another row in the KV ledger
    /// (prefix `fb:`) for later aggregation.
    @State private var ratingSubmitted: Int? = nil   // -1 / +1, nil = unrated
    @State private var showRatingReason = false      // 👎 reason picker

    var body: some View {
        if isNoCatDetected {
            noCatView
                .padding(.horizontal)
                .padding(.bottom, 20)
        } else {
            reportBody
        }
    }

    private var isNoCatDetected: Bool {
        report.breed.lowercased().contains("no-cat-detected")
            || report.breed.lowercased().contains("no cat")
            || (report.healthScore == 0 && report.breed.contains("—"))
    }

    private var noCatView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 46))
                .foregroundColor(Theme.warning)
                .padding(.top, 10)

            Text(lang.isChineseSelected ? "没看清小猫咪喵 ฅ" : "Couldn't spot a cat ฅ")
                .font(.title3.weight(.semibold))

            Text(lang.isChineseSelected
                 ? "照片里好像没有清楚的猫咪。\n试试光线好一点、对准脸部的那种照片~"
                 : "I can't see a clear cat in this photo.\nTry one with better light and the face in focus.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                tipLine("☀️", lang.isChineseSelected ? "光线充足,避免逆光"  : "Bright, no backlight")
                tipLine("🐱", lang.isChineseSelected ? "猫脸居中,占画面 2/3" : "Center the face, fill 2/3")
                tipLine("🔍", lang.isChineseSelected ? "对焦清晰,别太远"    : "Sharp focus, not too far")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.disclaimerBg)
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Theme.cardSecondary)
        .cornerRadius(18)
    }

    private func tipLine(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(emoji).font(.callout)
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }

    private var reportBody: some View {
        VStack(spacing: 12) {
            // Share button row
            HStack {
                Spacer()
                Button {
                    renderAndShare()
                } label: {
                    Label(lang.loc("report.share"), systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundColor(Theme.info)
                }
            }

            disclaimerBanner
            if hasEmergencyKeywords { emergencyVetCard }
            scoreCard
            if let sub = report.subScores { subScoresCard(sub) }
            accordion(id: "basic",      icon: "info.circle.fill",   title: lang.loc("report.basic.title"),      color: Theme.info)    { basicContent }
            if !report.parentBreeds.isEmpty {
                accordion(id: "ancestry", icon: "person.2.fill",     title: lang.loc("report.ancestry.title"),   color: .pink)         { ancestryContent }
            }
            accordion(id: "body",       icon: "stethoscope",         title: lang.loc("report.body.title"),       color: Theme.info)    { bodyContent }
            accordion(id: "lifestyle",  icon: lifestyleSymbol,       title: lang.loc("report.lifestyle.title"),  color: lifestyleColor){ lifestyleContent }
            if !report.suggestions.isEmpty {
                accordion(id: "tips",   icon: "checkmark.seal.fill", title: lang.loc("report.suggestions.title"),color: Theme.success) { tipsContent }
            }
            if !report.warnings.isEmpty { warningsCard }
            if cat != nil { chatSection }
            ratingFooter
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .sheet(isPresented: $showRatingReason) {
            ratingReasonSheet
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                ActivitySheet(items: [img])
            }
        }
        .sheet(item: $chatPaywallReason) { reason in
            PaywallView(reason: reason)
        }
    }

    // MARK: - Disclaimer
    private var disclaimerBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "stethoscope.circle.fill")
                .foregroundColor(Theme.warning)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.isChineseSelected ? "AI 仅供参考" : "AI is for reference only")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.amberText)
                Text(lang.loc("report.disclaimer"))
                    .font(.footnote)
                    .foregroundColor(Theme.amberText.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.disclaimerBg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.warning.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Emergency vet CTA
    //
    // We only show the red "see a vet NOW" card when the situation is
    // unambiguously severe. Previously any mention of "dehydration",
    // "pupil", "breathing difficulty" etc. triggered it, which produced
    // false alarms on moderate scores (60-70). Now we require either:
    //   1. Health score < 40 (truly concerning), or
    //   2. AI explicitly prefixed a warning with "[URGENT]"
    //      (our PromptBuilder instructs the model to do this only for
    //       labored breathing, heavy bleeding, seizures, unconsciousness,
    //       severe dehydration, jaundice — the real emergencies).
    //
    // Regular warnings still render in the warnings card below; this
    // only controls the prominent red emergency CTA at the top.
    private static let emergencyKeywords: [String] = [
        "[urgent]",          // our PromptBuilder marker
        "立即就医",
        "紧急就医",
        "immediate vet",
        "emergency vet",
    ]

    private var hasEmergencyKeywords: Bool {
        if report.scoreBand.isCritical { return true }

        let haystack = report.warnings.joined(separator: " ").lowercased()
        return Self.emergencyKeywords.contains { haystack.contains($0) }
    }

    private var emergencyVetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cross.circle.fill")
                    .foregroundColor(.white)
                    .font(.title2)
                Text(lang.isChineseSelected ? "建议立即联系兽医" : "Contact a vet immediately")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            Text(lang.isChineseSelected
                 ? "检测到可能存在紧急症状,AI 无法替代面诊。请尽快带猫咪去附近宠物医院。"
                 : "Possible emergency symptoms detected. AI can't replace a real exam — please visit a vet ASAP.")
                .font(.body)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showNearbyVets = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                    Text(lang.isChineseSelected ? "查找附近兽医" : "Find nearby vets")
                }
                .font(.body.weight(.semibold))
                .foregroundColor(Theme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            LinearGradient(colors: [Theme.danger, Color(red: 0.85, green: 0.2, blue: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(14)
        .shadow(color: Theme.danger.opacity(0.35), radius: 10, x: 0, y: 4)
        .sheet(isPresented: $showNearbyVets) {
            NearbyVetsView()
        }
    }

    // MARK: - Score Card (two-column)
    private var scoreCard: some View {
        scoreCardContent
            .overlay(alignment: .topTrailing) {
                // ⓘ — opens the scoring methodology sheet. Top-right of the
                // card so it doesn't interfere with the ring/sub-scores but
                // is always within thumb reach. Uses contentShape + padding
                // for a 44pt hit target without visual bulk.
                Button { showMethodology = true } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lang.isChineseSelected
                                    ? "评分是怎么算的"
                                    : "How the score works")
            }
            .sheet(isPresented: $showMethodology) {
                ScoringMethodologyView()
            }
    }

    private var scoreCardContent: some View {
        HStack(spacing: 0) {
            // Left: ring + score
            ZStack {
                Circle().stroke(scoreColor.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(report.healthScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.2), value: report.healthScore)
                VStack(spacing: 2) {
                    Text("\(report.healthScore)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    Text(scoreLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 110, height: 110)
            .padding(.leading, 20)
            // VoiceOver reads: "健康分数 78 分,良好" — collapses the ring's
            // many child views into a single, scannable announcement.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lang.isChineseSelected
                                ? "健康分数 \(report.healthScore) 分,\(scoreLabel)"
                                : "Health score \(report.healthScore), \(scoreLabel)")

            Divider().padding(.vertical, 16).padding(.horizontal, 16)

            // Right: 3 mini indicators
            VStack(alignment: .leading, spacing: 12) {
                miniRow(icon: "eye.fill",      label: lang.loc("report.body.eyes"),    value: report.eyesCondition)
                miniRow(icon: "sparkles",       label: lang.loc("report.body.fur"),     value: report.furCondition)
                miniRow(icon: "figure.stand",  label: lang.loc("report.body.posture"), value: report.postureCondition)
            }
            .padding(.trailing, 20)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .background(Theme.cardPrimary)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 5)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.08), lineWidth: 1))
    }

    private func miniRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.subheadline).foregroundColor(Theme.info).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.footnote).foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label):\(value)")
    }

    // MARK: - Accordion
    @ViewBuilder
    private func accordion<Content: View>(
        id: String, icon: String, title: String, color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let open = expanded.contains(id)
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if open { expanded.remove(id) } else { expanded.insert(id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundColor(color).frame(width: 20)
                    Text(title).font(.headline).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(lang.isChineseSelected
                               ? (open ? "已展开,双击收起" : "双击展开详情")
                               : (open ? "Expanded, double tap to collapse" : "Double tap to expand"))

            if open {
                Divider().padding(.horizontal, 16)
                content()
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.cardSecondary)
        .cornerRadius(16)
        .clipped()
    }

    // MARK: - Section contents
    private var basicContent: some View {
        VStack(spacing: 12) {
            infoRow("pawprint.fill",    Theme.primary, lang.loc("report.basic.breed"),       report.breed)
            infoRow("paintpalette.fill",Theme.primary, lang.loc("report.basic.color"),       report.furColor)
            infoRow("heart.fill",       Theme.primary, lang.loc("report.basic.personality"), report.personality)
        }
    }

    private var ancestryContent: some View {
        HStack(spacing: 10) {
            ForEach(report.parentBreeds, id: \.self) { breed in
                Label(breed, systemImage: "pawprint")
                    .font(.subheadline).fontWeight(.medium)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.pink.opacity(0.12)).cornerRadius(20)
            }
            Spacer()
        }
    }

    private var bodyContent: some View {
        VStack(spacing: 12) {
            infoRow("eye.fill",     Theme.info, lang.loc("report.body.eyes"),    report.eyesCondition)
            infoRow("sparkles",     Theme.info, lang.loc("report.body.fur"),     report.furCondition)
            infoRow("figure.stand", Theme.info, lang.loc("report.body.posture"), report.postureCondition)
        }
    }

    private var lifestyleContent: some View {
        let i = lifestyleDetails
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: i.icon).font(.title2).foregroundColor(i.color).frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(i.label).font(.headline).foregroundColor(i.color)
                Text(report.lifestyleDetail).font(.body).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tipsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(report.suggestions.enumerated()), id: \.offset) { idx, text in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.footnote.weight(.bold)).foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.success).clipShape(Circle())
                    Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Warnings (always visible, orange left border)
    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.warning)
                Text(lang.loc("report.warnings.title")).font(.headline)
                Spacer()
            }
            .padding(16)
            Divider().padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(report.warnings, id: \.self) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(Theme.danger).frame(width: 22)
                        Text(item)
                            .font(.body.weight(.bold))
                            .foregroundColor(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.warningBg)
        .cornerRadius(16)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.warning)
                .frame(width: 4)
                .padding(.vertical, 1)
        }
        .clipped()
    }

    // MARK: - Helpers
    private func infoRow(_ icon: String, _ color: Color, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundColor(color).frame(width: 22)
            Text(label).font(.body).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Text(value).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scoreColor: Color { report.scoreBand.color }

    private var scoreLabel: String {
        lang.loc(report.scoreBand.labelKey)
    }

    // MARK: - Sub-scores breakdown
    private func subScoresCard(_ sub: SubScores) -> some View {
        let zh = lang.isChineseSelected
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(zh ? "评分构成" : "Score breakdown")
                    .font(.headline)
                Spacer()
                Text(zh ? "加权平均 → \(sub.composite)" : "Weighted → \(sub.composite)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            subScoreBar(label: zh ? "眼睛" : "Eyes",    value: sub.eyes,   weight: "30%")
            subScoreBar(label: zh ? "毛发" : "Fur",     value: sub.fur,    weight: "20%")
            subScoreBar(label: zh ? "体态" : "Posture", value: sub.posture,weight: "20%")
            subScoreBar(label: zh ? "精神" : "Energy",  value: sub.energy, weight: "30%")
        }
        .padding(14)
        .background(Theme.cardPrimary)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))
    }

    private func subScoreBar(label: String, value: Int, weight: String) -> some View {
        let color = ScoreBand(score: value).color
        return HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .frame(width: 60, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(value) / 100)
                        .animation(.easeOut(duration: 0.9), value: value)
                }
            }
            .frame(height: 10)
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 36, alignment: .trailing)
            Text(weight)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lang.isChineseSelected
                            ? "\(label) \(value) 分,占总分 \(weight)"
                            : "\(label) \(value), weight \(weight)")
    }

    private var lifestyleSymbol: String {
        switch report.lifestyleTag {
        case "water": return "drop.fill"
        case "food":  return "fork.knife"
        case "exercise": return "figure.run"
        default: return "star.fill"
        }
    }

    private var lifestyleColor: Color {
        switch report.lifestyleTag {
        case "water":    return .blue
        case "exercise": return Theme.success
        default:         return Theme.primary
        }
    }

    private var lifestyleDetails: (icon: String, label: String, color: Color) {
        switch report.lifestyleTag {
        case "water":    return ("drop.fill",   lang.loc("report.lifestyle.water"),    .blue)
        case "food":     return ("fork.knife",  lang.loc("report.lifestyle.food"),     Theme.primary)
        case "exercise": return ("figure.run",  lang.loc("report.lifestyle.exercise"), Theme.success)
        default:         return ("star.fill",   lang.loc("report.lifestyle.default"),  Theme.info)
        }
    }

    // MARK: - Chat Section

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill").foregroundColor(Theme.info)
                Text(lang.loc("report.chat.title")).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14)

            if !chatMessages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(chatMessages) { msg in
                        HStack(alignment: .top, spacing: 0) {
                            if msg.role == "user" { Spacer(minLength: 60) }
                            Text(msg.text)
                                .font(.body)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(msg.role == "user" ? Theme.primary : Theme.cardSecondary)
                                .foregroundColor(msg.role == "user" ? .white : .primary)
                                .cornerRadius(16)
                            if msg.role == "assistant" { Spacer(minLength: 60) }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Hide-keyboard button — only visible while the chat input is
            // focused. Single source of truth (the keyboard accessory toolbar
            // version was previously unreliable inside this nested ScrollView).
            if chatFocused {
                Button {
                    chatFocused = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down.circle.fill")
                        Text(lang.isChineseSelected ? "收起键盘" : "Hide keyboard")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.deep)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .transition(.opacity)
            }

            HStack(spacing: 10) {
                let placeholder = cat.map { String(format: lang.loc("report.chat.placeholder"), $0.name) }
                    ?? lang.loc("report.chat.followup")
                TextField(placeholder, text: $chatInput, axis: .vertical)
                    .font(.body)
                    .focused($chatFocused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.cardSecondary)
                    .cornerRadius(14)
                    .lineLimit(1...3)
                    .disabled(isChatting)

                Button {
                    Task { await sendChat() }
                } label: {
                    if isChatting {
                        ProgressView().tint(Theme.info)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2).foregroundColor(chatInput.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.info.opacity(0.3) : Theme.info)
                    }
                }
                .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty || isChatting)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(Theme.cardPrimary)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.18), value: chatFocused)
    }

    private func sendChat() async {
        guard let cat, !chatInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Chat is subscription-gated. If the user can't chat right now, surface
        // the paywall instead of silently failing or burning their analyze quota.
        if case .blocked(let reason) = subs.canChat() {
            chatPaywallReason = reason
            return
        }

        let question = chatInput.trimmingCharacters(in: .whitespaces)
        chatInput = ""
        // Auto-dismiss the keyboard once the message is in flight; the user
        // wants to read the answer, not keep typing.
        chatFocused = false
        chatMessages.append(ChatMessage(role: "user", text: question))
        isChatting = true
        defer { isChatting = false }
        do {
            let answer = try await ClaudeService.shared.chat(
                cat: cat,
                history: recentRecords,
                lastReport: report,
                question: question,
                isEnglish: !lang.isChineseSelected
            )
            subs.consumeChat()
            chatMessages.append(ChatMessage(role: "assistant", text: answer))
        } catch {
            chatMessages.append(ChatMessage(role: "assistant", text: lang.loc("report.chat.error")))
        }
    }

    // MARK: - Share
    @MainActor
    private func renderAndShare() {
        // Pin to light so the exported PNG always has a light background,
        // regardless of the user's current system appearance.
        let card = ShareCardView(report: report, cat: cat)
            .environment(lang)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let img = renderer.uiImage {
            shareImage = img
            showShareSheet = true
        } else {
            showShareSheet = true
        }
    }

    // MARK: - Rating footer

    /// Bottom-of-report 👍 / 👎. Switches to a "thanks ♡" pill the moment
    /// the user picks one — we don't want to badger them on subsequent
    /// scrolls of the same report. State is per-view, so opening another
    /// past report from History lets that one be rated independently.
    private var ratingFooter: some View {
        let zh = lang.isChineseSelected
        return Group {
            if let r = ratingSubmitted {
                HStack(spacing: 6) {
                    Text(r > 0 ? "♡" : "ฅ").font(.system(size: 14))
                    Text(zh ? "感谢喵～收到了" : "Thanks meow ♡")
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(theme.deep.opacity(0.75))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            } else {
                VStack(spacing: 10) {
                    Text(zh ? "这次报告有用吗?" : "Was this report helpful?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 14) {
                        Button {
                            ratingSubmitted = 1
                            Task { await submitRating(score: 1, reason: nil) }
                        } label: {
                            ratingPill(emoji: "😺", label: zh ? "有用" : "Helpful", tint: theme.accent)
                        }
                        .buttonStyle(.plain)

                        Button {
                            // Don't lock state until they pick a reason — lets
                            // them dismiss the sheet to back out of the 👎.
                            showRatingReason = true
                        } label: {
                            ratingPill(emoji: "🙀", label: zh ? "差点" : "Off", tint: theme.main)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: ratingSubmitted)
    }

    private func ratingPill(emoji: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(emoji).font(.system(size: 16))
            Text(label).font(.subheadline.weight(.medium))
        }
        .foregroundColor(theme.deep)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(tint.opacity(0.18))
                .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.8))
        )
    }

    /// 👎 reason picker. Four common reasons + free-skip. Tapping any
    /// option sets `ratingSubmitted = -1` and submits; tapping outside
    /// (sheet dismiss) cancels — the user stays unrated.
    private var ratingReasonSheet: some View {
        let zh = lang.isChineseSelected
        let reasons: [(zh: String, en: String, key: String)] = [
            ("不太准确",     "Not accurate",        "inaccurate"),
            ("太啰嗦",       "Too verbose",         "verbose"),
            ("漏了关键信息", "Missed key info",     "missing_info"),
            ("不太能看懂",   "Hard to understand",  "unclear"),
        ]
        return VStack(alignment: .leading, spacing: 14) {
            Text(zh ? "怎么不太对呢喵?" : "What was off?")
                .font(.title3.weight(.bold))
                .foregroundColor(theme.deep)
                .padding(.top, 8)
            Text(zh ? "选个原因,帮我们让报告更好喵～"
                    : "Pick a reason — helps us make reports better meow ♡")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(reasons, id: \.key) { r in
                    Button {
                        ratingSubmitted = -1
                        showRatingReason = false
                        Task { await submitRating(score: -1, reason: r.key) }
                    } label: {
                        HStack {
                            Text(zh ? r.zh : r.en)
                                .foregroundColor(theme.deep)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(theme.main.opacity(0.5))
                                .font(.caption)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    ratingSubmitted = -1
                    showRatingReason = false
                    Task { await submitRating(score: -1, reason: "skipped") }
                } label: {
                    Text(zh ? "其它,不想说 ฅ" : "Other / skip ฅ")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// POST to the existing /feedback endpoint with category=rating. The
    /// Worker just stores it under the `fb:` KV prefix — same place as
    /// bug reports — so we can aggregate later in the eval pipeline.
    private func submitRating(score: Int, reason: String?) async {
        guard let url = URL(string: "https://carmel-worker.8fn98bvpdb.workers.dev/feedback")
        else { return }
        let infoBundle = Bundle.main.infoDictionary
        let appVersion = infoBundle?["CFBundleShortVersionString"] as? String
        let appBuild = infoBundle?["CFBundleVersion"] as? String

        let text: String = {
            // Min 2 chars enforced server-side. Always ≥ 2 here.
            let glyph = score > 0 ? "👍" : "👎"
            if let reason, !reason.isEmpty { return "\(glyph) \(reason)" }
            return glyph
        }()

        let payload: [String: Any] = [
            "category": "rating",
            "text": text,
            "appVersion": appVersion ?? "",
            "appBuild": appBuild ?? "",
            "iosVersion": UIDevice.current.systemVersion,
            "language": lang.currentLanguage,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SubscriptionManager.shared.appAccountToken.uuidString,
                     forHTTPHeaderField: "X-Account-Token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: - Share Card (rendered to image)
private struct ShareCardView: View {
    let report: HealthReport
    var cat: Cat?
    @Environment(LanguageManager.self) var lang

    private var scoreColor: Color { report.scoreBand.color }

    var body: some View {
        VStack(spacing: 0) {
            // Header gradient
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color(red:1,green:0.60,blue:0.20), Color(red:1,green:0.80,blue:0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🐱 KittyScan")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        if let cat {
                            Text(cat.name)
                                .font(.subheadline).foregroundColor(.white.opacity(0.9))
                        }
                    }
                    Spacer()
                    // Score ring
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.3), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(report.healthScore) / 100)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text("\(report.healthScore)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text(lang.loc(scoreLabel))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .frame(width: 72, height: 72)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .frame(height: 110)

            // Body
            VStack(alignment: .leading, spacing: 14) {
                // Key metrics row
                HStack(spacing: 0) {
                    metricCell(icon: "eye.fill",      label: lang.loc("report.body.eyes"),    value: report.eyesCondition)
                    Divider().frame(height: 40)
                    metricCell(icon: "sparkles",       label: lang.loc("report.body.fur"),     value: report.furCondition)
                    Divider().frame(height: 40)
                    metricCell(icon: "figure.stand",  label: lang.loc("report.body.posture"), value: report.postureCondition)
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                // Breed + personality
                if !report.breed.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "pawprint.fill").foregroundColor(Theme.primary).frame(width: 16)
                        Text(report.breed).font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Text(report.furColor).font(.subheadline).foregroundColor(.secondary)
                    }
                }

                // Top suggestions
                if !report.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lang.loc("report.suggestions.title"))
                            .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                        ForEach(Array(report.suggestions.prefix(3).enumerated()), id: \.offset) { idx, tip in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Theme.success).clipShape(Circle())
                                Text(tip).font(.caption).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // Warnings
                if !report.warnings.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.warning).font(.caption)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(report.warnings, id: \.self) { w in
                                Text(w)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(Theme.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(10)
                    .background(Theme.disclaimerBg)
                    .cornerRadius(10)
                }
            }
            .padding(16)
            .background(Theme.background)

            // Footer
            HStack {
                Spacer()
                Text("🐾 KittyScan — AI Cat Care")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))
        }
        .frame(width: 360)
        .background(Theme.background)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
        .padding(20)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var scoreLabel: String { report.scoreBand.labelKey }

    private func metricCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundColor(Theme.info)
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

// MARK: - Activity Sheet
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
