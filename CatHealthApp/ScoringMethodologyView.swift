import SwiftUI

/// "How is the score calculated?" sheet. Surfaces the 4-dimension scoring,
/// weights, band thresholds, and the model we run — so users (and any vet
/// they show this to) can judge whether the number is meaningful.
///
/// Design intent: read like a well-edited science blog post, not a legal
/// disclaimer. Build trust by being specific (we list the model, the
/// weights, the bands) without overpromising (we keep "not a substitute
/// for a real vet" front and center).
struct ScoringMethodologyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(ThemeProvider.self) private var themeProvider

    private var zh: Bool { lang.isChineseSelected }
    private var theme: CatTheme { themeProvider.theme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headline
                    section1_what
                    section2_dimensions
                    section3_formula
                    section4_bands
                    section5_history
                    section6_limits
                    footerDisclaimer
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(zh ? "评分是怎么算的" : "How the score works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(zh ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "stethoscope.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(theme.deep)
            Text(zh ? "我们怎么给一张照片打分?" : "How we score a single photo")
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.deep)
            Text(zh
                 ? "和大多数 \"AI 评分 App\" 不一样:我们不是问 AI 一句 \"这只猫健康吗\" 然后直接拿一个数字。下面是每一步在做什么。"
                 : "Unlike most \"AI score apps\" we don't just ask the model \"is this cat healthy\" and use the number it spits out. Here's what actually happens.")
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var section1_what: some View {
        section(
            number: 1,
            title: zh ? "看的是什么" : "What we look at",
            body: zh
                ? "每张猫咪照片送到 Anthropic 的 Claude(目前是 Sonnet 4.6 视觉模型)。我们让模型分别就**眼睛、毛发、体态、精神**四个维度独立打分,每项 0-100,带具体描述。"
                : "Each photo goes to Anthropic's Claude (currently Sonnet 4.6 vision). The model scores four independent dimensions: **eyes, fur, posture, and energy** — each 0–100, each with a textual description."
        )
    }

    private var section2_dimensions: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(number: 2, title: zh ? "四维权重" : "Four-dimension weights")
            Text(zh
                 ? "权重是按家猫健康判读的可见度排的——眼睛和精神是最强的健康信号,毛发体态变化更慢。"
                 : "Weights reflect how *visible* each signal tends to be in a typical photo — eyes and energy carry the loudest health signal; fur and posture shift slowly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                weightRow(emoji: "👀", label: zh ? "眼睛" : "Eyes",   weight: "30%",
                          why: zh ? "分泌物 / 清亮度" : "discharge / clarity")
                weightRow(emoji: "🐾", label: zh ? "精神" : "Energy", weight: "30%",
                          why: zh ? "整体状态 / 警觉度" : "alertness / liveliness")
                weightRow(emoji: "✨", label: zh ? "毛发" : "Fur",     weight: "20%",
                          why: zh ? "光泽 / 皮屑" : "gloss / flakes")
                weightRow(emoji: "🪑", label: zh ? "体态" : "Posture", weight: "20%",
                          why: zh ? "对称 / 紧绷度" : "symmetry / tension")
            }
        }
    }

    private var section3_formula: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(number: 3, title: zh ? "总分公式" : "Composite formula")
            Text(zh
                 ? "总分 = 眼睛 × 0.30 + 精神 × 0.30 + 毛发 × 0.20 + 体态 × 0.20"
                 : "Total = Eyes × 0.30 + Energy × 0.30 + Fur × 0.20 + Posture × 0.20")
                .font(.body.monospaced())
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card.opacity(0.4))
                .cornerRadius(10)
            Text(zh
                 ? "权重不会因为某次评分高低而漂移——它是写死的常数。如果我们以后调整,会在版本说明里告诉你。"
                 : "Weights are constants — they never drift based on individual scores. If we ever change them, the release notes will say so.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var section4_bands: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(number: 4, title: zh ? "分数段含义" : "What the bands mean")
            VStack(spacing: 8) {
                bandRow(range: "90–100", label: zh ? "优秀" : "Excellent",
                        color: ScoreBand.excellent.color,
                        desc: zh ? "看起来非常好" : "Looking great")
                bandRow(range: "70–89",  label: zh ? "良好" : "Good",
                        color: ScoreBand.good.color,
                        desc: zh ? "正常范围" : "Within normal range")
                bandRow(range: "40–69",  label: zh ? "一般" : "Fair",
                        color: ScoreBand.fair.color,
                        desc: zh ? "有需要观察的地方" : "Worth keeping an eye on")
                bandRow(range: "0–39",   label: zh ? "需关注" : "Attention",
                        color: ScoreBand.critical.color,
                        desc: zh ? "建议尽快咨询兽医" : "See a vet soon")
            }
        }
    }

    private var section5_history: some View {
        section(
            number: 5,
            title: zh ? "历史记录怎么影响" : "How history factors in",
            body: zh
                ? "每次分析时,你猫的最近 5 次检测结果和最近 7 天日记会作为**对比上下文**喂给模型——但**不会让历史分数影响本次的独立评分**。模型被明确要求:每次只看眼前这张照片来打分,但叙述里要指出 \"和上次比变好/变差/持平\"。这样得分诚实,趋势分析有用。"
                : "When analyzing, your cat's last 5 reports and last 7 days of diary entries are sent as **comparison context** — but the model is explicitly instructed: score this photo on its own merits, never anchor to past numbers. The narrative compares; the score doesn't drift."
        )
    }

    private var section6_limits: some View {
        section(
            number: 6,
            title: zh ? "我们不能做什么" : "What we can't do",
            body: zh
                ? "AI 看不出血液指标、寄生虫感染、内脏问题,也不能替代触诊和听诊。**我们的评分是一个粗筛,不是诊断**。任何分数低于 40 或带 [URGENT] 警告的报告,请认真考虑去看真人兽医。"
                : "AI can't see bloodwork, parasites, internal organ issues, and can't replace palpation or auscultation. **Our score is a screening signal, not a diagnosis.** Any report under 40 or marked [URGENT] should be taken to a real veterinarian."
        )
    }

    private var footerDisclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.bottom, 4)
            Text(zh ? "我们承诺" : "Our promise")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.deep)
            Text(zh
                 ? "·  不替你的兽医做决定;你的兽医永远说了算。\n·  不靠你的猫数据训练模型(Anthropic 的 Zero Data Retention)。\n·  评分公式和权重对所有用户一样,不会按订阅档位区别对待。"
                 : "·  We won't replace your vet — your vet has final say.\n·  We don't train models on your data (Anthropic Zero Data Retention).\n·  Same scoring formula for everyone — no \"premium tier\" math.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Components

    private func section(number: Int, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(number: number, title: title)
            Text(.init(body))                        // markdown bold support
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeader(number: Int, title: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(theme.bg)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.deep))
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.deep)
        }
    }

    private func weightRow(emoji: String, label: String, weight: String, why: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(theme.deep)
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(weight).font(.body.weight(.bold).monospacedDigit()).foregroundStyle(theme.deep)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.cardPrimary)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.light.opacity(0.4), lineWidth: 0.5))
    }

    private func bandRow(range: String, label: String, color: Color, desc: String) -> some View {
        HStack(spacing: 12) {
            Capsule().fill(color).frame(width: 6, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label).font(.subheadline.weight(.bold)).foregroundStyle(color)
                    Text(range).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(color.opacity(0.06))
        .cornerRadius(10)
    }
}
