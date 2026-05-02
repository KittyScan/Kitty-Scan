import SwiftUI

/// Blocking first-launch consent view. Shown until both privacy policy and ToS
/// have been acknowledged. Acceptance is persisted under the current Policies.version,
/// so bumping the version forces users to re-consent.
struct ConsentGate: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(ThemeProvider.self) private var themeProvider

    let onAccept: () -> Void

    @State private var agreedPrivacy = false
    @State private var agreedToS = false
    @State private var showPrivacy = false
    @State private var showToS = false

    private var zh: Bool { lang.isChineseSelected }
    private var theme: CatTheme { themeProvider.theme }
    private var canProceed: Bool { agreedPrivacy && agreedToS }

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.bg, theme.card],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                CatAvatar(theme: theme, size: 110, showRing: true)
                    .padding(.bottom, 22)

                Text(zh ? "欢迎来到 KittyScan 喵 ♡" : "Welcome to KittyScan ♡")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.deep)

                Text(zh
                     ? "开始前,花 30 秒过一下这两个小文档"
                     : "Before we start, a 30-second read")
                    .font(.subheadline)
                    .foregroundStyle(theme.main)
                    .padding(.top, 6)

                Spacer()

                VStack(spacing: 10) {
                    ConsentRow(
                        title: zh ? "隐私政策" : "Privacy Policy",
                        subtitle: zh ? "我们怎么处理你的数据" : "How we handle your data",
                        checked: agreedPrivacy,
                        theme: theme,
                        onToggle: { agreedPrivacy.toggle() },
                        onView: { showPrivacy = true }
                    )
                    ConsentRow(
                        title: zh ? "服务协议" : "Terms of Service",
                        subtitle: zh ? "使用规则 + AI 免责" : "Rules + AI disclaimer",
                        checked: agreedToS,
                        theme: theme,
                        onToggle: { agreedToS.toggle() },
                        onView: { showToS = true }
                    )
                }
                .padding(.horizontal, 24)

                Button {
                    Consent.recordAcceptance()
                    onAccept()
                } label: {
                    Text(zh ? "同意并继续 →" : "Accept & Continue →")
                        .font(.headline)
                        .foregroundStyle(canProceed ? theme.bg : theme.bg.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(canProceed ? theme.deep : theme.deep.opacity(0.3))
                        )
                        .shadow(color: canProceed ? theme.deep.opacity(0.25) : .clear,
                                radius: 10, y: 4)
                }
                .disabled(!canProceed)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 10)

                Text(zh
                     ? "不同意也完全 ok · 只是就没法用啦 ฅ"
                     : "Declining is fine — you just can't use the app ฅ")
                    .font(.caption2)
                    .foregroundStyle(theme.main.opacity(0.7))
                    .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showPrivacy) {
            PolicyViewerView(doc: Policies.privacy(zh: zh))
        }
        .sheet(isPresented: $showToS) {
            PolicyViewerView(doc: Policies.terms(zh: zh))
        }
    }
}

private struct ConsentRow: View {
    let title: String
    let subtitle: String
    let checked: Bool
    let theme: CatTheme
    let onToggle: () -> Void
    let onView: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Tap target for TOGGLE: checkbox + title text. Wrapping them in
            // a single Button makes both hit areas trigger the same action,
            // so tapping the title is the same as tapping the box (~80% of
            // the row width works for the toggle, which is the primary action
            // here).
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(checked ? theme.deep : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(checked ? theme.deep : theme.main.opacity(0.5),
                                                  lineWidth: 1.5)
                            )
                            .frame(width: 24, height: 24)
                        if checked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.bg)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.deep)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.main.opacity(0.8))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Separate tap target for VIEW: just the chevron, with extra
            // padding so it's a 44pt-min hit area but visually still small.
            Button(action: onView) {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.main)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("View"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.light.opacity(0.5), lineWidth: 0.5)
        )
    }
}
