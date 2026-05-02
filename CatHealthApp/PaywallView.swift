import SwiftUI
import StoreKit

/// Sheet shown when the user hits a quota wall (free analyses exhausted,
/// pack empty, sub quota out, or chat tapped without a sub). Shows the three
/// purchase options + a restore button.
struct PaywallView: View {
    let reason: SubscriptionManager.GateResult.BlockReason

    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(ThemeProvider.self) private var themeProvider
    @State private var subs = SubscriptionManager.shared
    @State private var purchasing: SubscriptionManager.ProductID?
    @State private var purchaseError: String?

    private var zh: Bool { lang.isChineseSelected }
    private var theme: CatTheme { themeProvider.theme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    headline
                    reasonCard
                    productList
                    restoreButton
                    if let err = purchaseError {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    legaleseFooter
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 24)
            }
            .background(Theme.background)
            .navigationTitle(zh ? "解锁 KittyScan Pro" : "Unlock KittyScan Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(zh ? "关闭" : "Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headline: some View {
        VStack(spacing: 8) {
            // Launch-promo banner — sits above the icon so it's the first
            // thing users see when the paywall opens. Decorative gradient
            // pill with a sparkle icon, theme-tinted so it blends in.
            promoBanner
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.deep)
            Text(zh ? "继续看护它的健康" : "Keep their health on track")
                .font(.title2.weight(.bold))
            Text(zh
                 ? "AI 分析 + 趋势追踪 + 视频问诊,选一个适合的方案"
                 : "AI analysis, trend tracking, video, and chat — pick what fits.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    /// "Launch celebration — limited promo" pill. Pulled out as its own view
    /// so it's easy to A/B different copies or swap to a deal-of-the-week
    /// banner later.
    private var promoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
            Text(zh ? "上线庆典 · 限时优惠最高 30% off"
                    : "Launch promo · up to 30% off")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(theme.bg)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [theme.deep, theme.main],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        )
    }

    /// Two-line price block: strikethrough MSRP + actual sale price.
    /// Visually communicates "we marked this down for launch" without
    /// touching the actual Apple-managed price (which is whatever
    /// `product.displayPrice` resolves to at App Store Connect).
    @ViewBuilder
    private func priceBlock(id: SubscriptionManager.ProductID, product: Product?) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(id.displayMSRP)
                .font(.caption)
                .foregroundColor(.secondary)
                .strikethrough(true, color: Color.red.opacity(0.85))
            Text(price(for: product))
                .font(.body.weight(.bold))
                .foregroundStyle(theme.deep)
        }
    }

    private var reasonCard: some View {
        let (title, body) = reasonCopy()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(Theme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.footnote).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.disclaimerBg)
        .cornerRadius(12)
    }

    private func reasonCopy() -> (String, String) {
        switch reason {
        case .freeExhausted:
            return zh
                ? ("喵～ 3 次免费体验都被用光啦 ฅ",
                   "我们觉得你家小猫值得最贴心的看护呀～挑一个方案,继续陪它一起好不好?(´ω`)")
                : ("Oh no — your 3 free analyses are gone ฅ",
                   "Pick a plan to keep watching out for your little furball ♡")
        case .packEmpty:
            return zh
                ? ("次卡里的额度被吃光了喵 (>ω<)",
                   "再续一包,或者干脆来个 Pro 月订,聊天也一起解锁～")
                : ("Pack credits all gone (>ω<)",
                   "Top up another pack, or grab Pro to unlock chat too!")
        case .subAnalyzeQuotaExhausted:
            return zh
                ? ("本月 50 次都用完啦 ฅ",
                   "下次续费会自动重置喵～如果这个月还想继续,买个次卡补一下也不亏!")
                : ("Out of this month's 50 analyses ฅ",
                   "Resets at next renewal. Need more right now? A pack tops you up.")
        case .subChatQuotaExhausted:
            return zh
                ? ("聊天追问的 30 次配额用完了 (=^・ω・^=)",
                   "下次续费就重置咯～(我也想多陪你聊呀但 token 真的有点贵 喵 ฅ)")
                : ("Out of this month's 30 chats (=^・ω・^=)",
                   "Resets at next renewal!")
        case .chatRequiresSubscription:
            return zh
                ? ("聊天功能是 Pro 专属哦~",
                   "订阅 Pro 后,你可以跟我无限次聊天,我会用专业知识帮你看顾它喵 ♡")
                : ("Chat is a Pro perk ♡",
                   "Subscribe to Pro to chat with me about your cat anytime!")
        case .themeLocked:
            return zh
                ? ("这只小猫主题要解锁才能用喵 ฅ",
                   "买一份次卡或订 Pro,22 款配色全部一次性解开,给主子换最配的颜色叭~ (=^・ω・^=)")
                : ("This kitty theme is locked ฅ",
                   "Grab any pack or Pro to unlock all 22 palettes — pick the one that fits your kitty best ♡")
        }
    }

    // MARK: - Products

    private var productList: some View {
        VStack(spacing: 10) {
            productRow(.monthly, badge: zh ? "推荐" : "Best value")
            productRow(.pack30,  badge: nil)
            productRow(.pack10,  badge: nil)
        }
    }

    @ViewBuilder
    private func productRow(_ id: SubscriptionManager.ProductID, badge: String?) -> some View {
        let product = subs.products.first { $0.id == id.rawValue }
        let busy = (purchasing == id) || (subs.purchaseInFlight == id)

        Button {
            Task {
                purchaseError = nil
                purchasing = id
                let ok = await subs.purchase(id)
                purchasing = nil
                if ok { dismiss() }
                else if subs.purchaseInFlight == nil {
                    purchaseError = zh ? "购买未完成,请稍后再试" : "Purchase didn't complete. Please try again."
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon(for: id))
                    .font(.title2)
                    .foregroundStyle(theme.deep)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title(for: id, product: product))
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(theme.deep))
                                .foregroundColor(theme.bg)
                        }
                    }
                    Text(subtitle(for: id))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Group {
                    if busy {
                        ProgressView()
                    } else {
                        priceBlock(id: id, product: product)
                    }
                }
                .frame(minWidth: 80, alignment: .trailing)
            }
            .padding(14)
            .background(Theme.cardPrimary)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.light.opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(busy || product == nil)
    }

    private func icon(for id: SubscriptionManager.ProductID) -> String {
        switch id {
        case .monthly: return "crown.fill"
        case .pack30:  return "tray.full.fill"
        case .pack10:  return "tray.fill"
        }
    }

    private func title(for id: SubscriptionManager.ProductID, product: Product?) -> String {
        if let product { return product.displayName }
        switch id {
        case .monthly: return zh ? "Pro 月订" : "Pro Monthly"
        case .pack30:  return zh ? "30 次分析包" : "30-Pack"
        case .pack10:  return zh ? "10 次分析包" : "10-Pack"
        }
    }

    private func subtitle(for id: SubscriptionManager.ProductID) -> String {
        switch id {
        case .monthly:
            return zh
                ? "每月 50 次分析 + 30 次聊天追问,自动续费"
                : "50 analyses + 30 chats per month. Auto-renews."
        case .pack30:
            return zh ? "30 次分析,长期有效,不含聊天" : "30 analyses, never expires. No chat."
        case .pack10:
            return zh ? "10 次分析,长期有效,不含聊天" : "10 analyses, never expires. No chat."
        }
    }

    private func price(for product: Product?) -> String {
        product?.displayPrice ?? "—"
    }

    // MARK: - Restore + legalese

    private var restoreButton: some View {
        Button {
            Task {
                purchaseError = nil
                await subs.restore()
            }
        } label: {
            Text(zh ? "恢复购买" : "Restore Purchases")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.info)
        }
        .padding(.top, 4)
    }

    private var legaleseFooter: some View {
        VStack(spacing: 8) {
            Text(zh
                 ? "Pro 月订 $6.99/月,在到期前 24 小时内自动续费,除非提前取消。可在 Apple ID 设置中管理或取消。"
                 : "Pro Monthly auto-renews at $6.99/month unless canceled at least 24 hours before the end of the current period. Manage or cancel in your Apple ID settings.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link(zh ? "隐私政策" : "Privacy Policy",
                     destination: URL(string: "https://melodious-yeot-3f33ae.netlify.app/privacy.html")!)
                Text("·").foregroundColor(.secondary)
                Link(zh ? "使用条款" : "Terms of Use",
                     destination: URL(string: "https://melodious-yeot-3f33ae.netlify.app/terms.html")!)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.info)
        }
        .padding(.top, 12)
    }
}
