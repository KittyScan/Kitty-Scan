import SwiftUI
import SwiftData
import UIKit

enum OnboardingStep {
    case welcome, breed, profile
}

@Observable
final class OnboardingFlow {
    var step: OnboardingStep = .welcome
    /// New cats start on the neutral default theme. The colored breed picker
    /// is skipped entirely at signup — colored themes unlock only after the
    /// user buys a pack or Pro (gated in SettingsView's ThemePickerSheet).
    var breedId: String = "default"
    var catName: String = ""
    var sex: String = "male"
    var birth: String = ""
    var neuter: Bool = false
    var avatarImage: UIImage? = nil

    var theme: CatTheme { CatThemes.byId(breedId) ?? CatThemes.defaultTheme }
}

// =========================================================
// Root onboarding container
// =========================================================
struct OnboardingView: View {
    @Environment(LanguageManager.self) var lang
    @Environment(\.modelContext) private var modelContext
    @State private var flow: OnboardingFlow

    var skipWelcome: Bool
    var onFinish: (Cat) -> Void

    init(skipWelcome: Bool = false, onFinish: @escaping (Cat) -> Void) {
        self.skipWelcome = skipWelcome
        self.onFinish = onFinish
        let f = OnboardingFlow()
        if skipWelcome { f.step = .breed }
        self._flow = State(initialValue: f)
    }

    private var zh: Bool { lang.isChineseSelected }

    var body: some View {
        ZStack {
            flow.theme.bg.ignoresSafeArea()

            Group {
                switch flow.step {
                case .welcome:
                    WelcomeStep(flow: flow, zh: zh)
                case .breed:
                    BreedPickerStep(flow: flow, zh: zh)
                case .profile:
                    ProfileCreateStep(flow: flow, zh: zh, onDone: saveCat)
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: flow.step)
    }

    private func saveCat() {
        let th = flow.theme
        let name = flow.catName.trimmingCharacters(in: .whitespaces).isEmpty
            ? th.def(zh: zh) : flow.catName
        let data = flow.avatarImage?.jpegData(compressionQuality: 0.85)
        let cat = Cat(
            name: name,
            breed: th.name(zh: zh),
            breedId: th.id,
            sex: flow.sex,
            age: flow.birth.isEmpty ? nil : flow.birth,
            neuter: flow.neuter,
            avatarData: data
        )
        modelContext.insert(cat)
        try? modelContext.save()
        onFinish(cat)
    }
}

// =========================================================
// Step 1 · Welcome
// =========================================================
private struct WelcomeStep: View {
    @Bindable var flow: OnboardingFlow
    let zh: Bool

    var body: some View {
        let th = flow.theme
        VStack(spacing: 0) {
            Spacer()

            CatAvatar(theme: th, size: 120)
                .padding(.bottom, 24)

            Text(zh ? "喵呜~ 你来啦 ♡" : "Meow~ you're here ♡")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(th.deep)

            Text(zh
                 ? "我是你的小猫健康管家喵\n一起把每天都变成回忆叭 ฅ"
                 : "I'm your cat's tiny health butler~\nLet's turn every day into a memory ฅ")
                .font(.system(size: 14))
                .foregroundStyle(th.main)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 10)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                // Skip the breed/theme picker — colored themes are a paid
                // feature, so new users go straight to profile creation on
                // the neutral default palette.
                flow.step = .profile
            } label: {
                Text(zh ? "开始撸猫日记 →" : "Start the purr journal →")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(th.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 20).fill(th.deep))
                    .shadow(color: th.deep.opacity(0.25), radius: 10, y: 5)
            }
            .padding(.horizontal, 32)

            Text(zh ? "老铲屎官? 登录" : "Already a cat parent? Log in")
                .font(.caption)
                .foregroundStyle(th.main.opacity(0.7))
                .padding(.top, 14)
                .padding(.bottom, 40)
        }
    }
}

// =========================================================
// Step 2 · Breed picker (22 themes)
// =========================================================
private struct BreedPickerStep: View {
    @Bindable var flow: OnboardingFlow
    let zh: Bool

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let th = flow.theme
        VStack(spacing: 0) {
            // Header
            ZStack {
                Text(zh ? "③ 你家小主子是什么品种呀 ✿" : "③ What breed is your kitty? ✿")
                    .font(.system(size: 12))
                    .foregroundStyle(th.main)
                HStack {
                    Button {
                        flow.step = .welcome
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(th.deep)
                            .padding(.horizontal, 8)
                    }
                    Spacer()
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 14)

            ProgressBar(current: 1, total: 3, color: th.deep, trackColor: th.card)
                .padding(.top, 12)
                .padding(.horizontal, 40)

            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text(zh ? "挑一个小猫 · 主题会跟着变哦" : "Pick a kitty · the theme follows")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(th.deep)
                        Text(zh ? "22 款专属配色,每只都独一无二" : "22 palettes, each one of a kind")
                            .font(.system(size: 11))
                            .foregroundStyle(th.main.opacity(0.7))
                    }
                    .padding(.top, 20)

                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(CatThemes.all) { t in
                            BreedCard(theme: t, selected: t.id == flow.breedId, zh: zh) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    flow.breedId = t.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)

                    Button {
                        flow.step = .profile
                    } label: {
                        Text(zh ? "就选 ta ♡" : "It's this one ♡")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(th.bg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 20).fill(th.deep))
                            .shadow(color: th.deep.opacity(0.2), radius: 10, y: 5)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

private struct BreedCard: View {
    let theme: CatTheme
    let selected: Bool
    let zh: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                CatAvatar(theme: theme, size: 50, showRing: false)
                    .padding(.top, 4)
                Text(theme.name(zh: zh))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.deep)
                    .lineLimit(1)
                Text(theme.mood(zh: zh))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.main.opacity(0.75))
                    .lineLimit(1)
                HStack(spacing: 2) {
                    ForEach(Array(theme.swatches.enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(selected ? theme.card : theme.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(selected ? theme.deep : theme.light.opacity(0.5),
                                  lineWidth: selected ? 1.8 : 0.8)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.bg)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(theme.deep))
                        .offset(x: -6, y: 6)
                }
            }
            .shadow(color: selected ? theme.deep.opacity(0.1) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// =========================================================
// Step 3 · Profile form
// =========================================================
private struct ProfileCreateStep: View {
    @Bindable var flow: OnboardingFlow
    let zh: Bool
    let onDone: () -> Void

    @FocusState private var focusedField: Field?
    enum Field { case name, birth }

    @State private var showPhotoSheet = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false

    var body: some View {
        let th = flow.theme
        VStack(spacing: 0) {
            ZStack {
                Text(zh ? "④ 创建专属档案" : "④ Create a profile")
                    .font(.system(size: 12))
                    .foregroundStyle(th.main)
                HStack {
                    Button {
                        flow.step = .breed
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(th.deep)
                            .padding(.horizontal, 8)
                    }
                    Spacer()
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 14)

            ProgressBar(current: 2, total: 3, color: th.deep, trackColor: th.card)
                .padding(.top, 12)
                .padding(.horizontal, 40)

            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Button { showPhotoSheet = true } label: {
                            ZStack(alignment: .bottomTrailing) {
                                CatAvatar(theme: th,
                                          avatarData: flow.avatarImage?.jpegData(compressionQuality: 0.85),
                                          size: 100,
                                          showRing: true)
                                Circle()
                                    .fill(th.light)
                                    .frame(width: 32, height: 32)
                                    .overlay(Text("📷").font(.system(size: 16)))
                                    .overlay(Circle().strokeBorder(th.bg, lineWidth: 2))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .buttonStyle(.plain)

                        Text(zh ? "认识一下你的小猫咪 ✿" : "Let's get to know your kitty ✿")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(th.deep)
                        Text(zh ? "点头像上传照片 / 不传就用手绘风" : "Tap to upload / or keep the hand-drawn one")
                            .font(.system(size: 11))
                            .foregroundStyle(th.main.opacity(0.75))
                    }
                    .padding(.top, 20)

                    if flow.avatarImage == nil {
                        PhotoTipsCard(theme: th, zh: zh)
                            .padding(.horizontal, 20)
                    }

                    VStack(spacing: 14) {
                        LabeledField(label: zh ? "ฅ 小名" : "ฅ Name", theme: th) {
                            TextField(
                                text: $flow.catName,
                                prompt: Text(th.def(zh: zh) + (zh ? " / 咪咪 / 豆豆..." : " / Luna / Bean...")).foregroundStyle(th.main.opacity(0.4))
                            ) { EmptyView() }
                                .foregroundStyle(th.deep)
                                .focused($focusedField, equals: .name)
                        }

                        LabeledField(label: zh ? "🐈 品种" : "🐈 Breed", theme: th) {
                            HStack {
                                Text(th.name(zh: zh))
                                    .foregroundStyle(th.deep)
                                Spacer()
                                Text(zh ? "更换 ›" : "Change ›")
                                    .font(.system(size: 11))
                                    .foregroundStyle(th.main.opacity(0.7))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { flow.step = .breed }
                        }

                        HStack(spacing: 10) {
                            LabeledField(label: zh ? "🎂 生日" : "🎂 Birthday", theme: th) {
                                TextField(
                                    text: $flow.birth,
                                    prompt: Text("2023.09").foregroundStyle(th.main.opacity(0.4))
                                ) { EmptyView() }
                                    .foregroundStyle(th.deep)
                                    .focused($focusedField, equals: .birth)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(zh ? "性别" : "Sex")
                                    .font(.system(size: 12))
                                    .foregroundStyle(th.main.opacity(0.75))
                                    .padding(.leading, 8)
                                HStack(spacing: 6) {
                                    SexPill(title: zh ? "♂ 男猫" : "♂ Boy",
                                            active: flow.sex == "male", theme: th) {
                                        flow.sex = "male"
                                    }
                                    SexPill(title: zh ? "♀ 女猫" : "♀ Girl",
                                            active: flow.sex == "female", theme: th) {
                                        flow.sex = "female"
                                    }
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Text("✂️").font(.system(size: 16))
                            Text(zh ? "已经做绝育了吗?" : "Already neutered?")
                                .font(.system(size: 13))
                                .foregroundStyle(th.main)
                            Spacer()
                            Toggle("", isOn: $flow.neuter)
                                .labelsHidden()
                                .tint(th.accent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(th.card))
                    }
                    .padding(.horizontal, 20)

                    Button(action: onDone) {
                        Text(zh ? "打个招呼 ♡" : "Say hi ♡")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(th.bg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 20).fill(th.deep))
                            .shadow(color: th.deep.opacity(0.2), radius: 10, y: 5)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Inline blue hide-keyboard button — same pattern as the chat / AddCatSheet:
        // floats above the keyboard while a TextField is focused, sits in the
        // safe-area inset so it doesn't fight the ScrollView layout.
        .safeAreaInset(edge: .bottom) {
            if focusedField != nil {
                Button { focusedField = nil } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down.circle.fill")
                        Text(zh ? "收起键盘" : "Hide keyboard")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.info))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .confirmationDialog(zh ? "选头像" : "Pick avatar",
                            isPresented: $showPhotoSheet,
                            titleVisibility: .visible) {
            Button(zh ? "📸 拍一张" : "📸 Take photo") { showCamera = true }
            Button(zh ? "🖼 从相册选" : "🖼 From library") { showPhotoLibrary = true }
            if flow.avatarImage != nil {
                Button(zh ? "移除照片" : "Remove photo", role: .destructive) {
                    flow.avatarImage = nil
                }
            }
            Button(zh ? "取消" : "Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: $flow.avatarImage, sourceType: .camera, allowsCrop: true)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePicker(image: $flow.avatarImage, sourceType: .photoLibrary, allowsCrop: true)
                .ignoresSafeArea()
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    let theme: CatTheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.main.opacity(0.75))
                .padding(.leading, 8)
            content
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.light.opacity(0.6), lineWidth: 0.5))
        }
    }
}

private struct PhotoTipsCard: View {
    let theme: CatTheme
    let zh: Bool

    private var tips: [(String, String)] {
        if zh {
            return [
                ("☀️", "自然光最好 · 别开闪光灯"),
                ("📐", "脸部正面居中 · 占画面 2/3"),
                ("🙀", "拍到眼睛更有灵气喵"),
            ]
        } else {
            return [
                ("☀️", "Daylight looks best · no flash"),
                ("📐", "Center the face · fill 2/3 frame"),
                ("🙀", "Catch the eyes for extra sparkle"),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("💡").font(.system(size: 14))
                Text(zh ? "拍照小贴士" : "Photo tips")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.deep)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .top, spacing: 6) {
                        Text(tip.0).font(.system(size: 12))
                        Text(tip.1)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.main)
                            .lineLimit(2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.card.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.light.opacity(0.4), lineWidth: 0.5)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct SexPill: View {
    let title: String
    let active: Bool
    let theme: CatTheme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? theme.deep : theme.main.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(active ? theme.light : theme.bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(active ? theme.deep : theme.light.opacity(0.6),
                                      lineWidth: active ? 1.5 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// =========================================================
// Shared mini components
// =========================================================
private struct ProgressBar: View {
    let current: Int
    let total: Int
    let color: Color
    let trackColor: Color
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < current ? color : trackColor)
                    .frame(height: 4)
            }
        }
    }
}
