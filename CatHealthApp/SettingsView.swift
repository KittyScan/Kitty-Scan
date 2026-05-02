import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(AuthManager.self) var auth
    @Environment(LanguageManager.self) var lang
    @Environment(ThemeProvider.self) var themeProvider
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Cat.createdAt) private var cats: [Cat]
    @Query(sort: \HistoryRecord.date, order: .reverse) private var allRecords: [HistoryRecord]

    @State private var showThemePicker = false
    @State private var showCatEdit = false
    @State private var showAddCat = false
    @State private var showDeleteConfirm1 = false
    @State private var showDeleteConfirm2 = false
    @State private var deleteTypedText = ""
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showExportShare = false
    @State private var showExport = false
    @State private var showPrivacyPolicy = false
    @State private var showToS = false
    @State private var showFeedback = false

    private var zh: Bool { lang.isChineseSelected }
    private var theme: CatTheme { themeProvider.theme }
    private var activeCat: Cat? { themeProvider.activeCat(from: cats) }

    var body: some View {
        NavigationStack {
            List {
                // Multi-cat switcher (only shown if 2+ cats)
                if cats.count >= 2 {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(cats) { c in
                                    let ct = CatThemes.byId(c.breedId) ?? theme
                                    let active = activeCat?.id == c.id
                                    Button {
                                        themeProvider.setActive(cat: c)
                                    } label: {
                                        VStack(spacing: 4) {
                                            ZStack {
                                                CatAvatar(theme: ct,
                                                          avatarData: c.avatarData,
                                                          size: 52,
                                                          showRing: false)
                                                if active {
                                                    Circle()
                                                        .strokeBorder(ct.deep, lineWidth: 2.5)
                                                        .frame(width: 52, height: 52)
                                                }
                                            }
                                            Text(c.name)
                                                .font(.caption2)
                                                .foregroundStyle(active ? ct.deep : .secondary)
                                                .fontWeight(active ? .semibold : .regular)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button {
                                    showAddCat = true
                                } label: {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Circle().fill(theme.card).frame(width: 52, height: 52)
                                            Image(systemName: "plus").foregroundStyle(theme.deep).font(.title3)
                                        }
                                        Text(zh ? "添加" : "Add")
                                            .font(.caption2)
                                            .foregroundStyle(theme.deep)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    } header: {
                        Text(zh ? "切换猫咪" : "Switch cat")
                    }
                }

                // My cat
                if let cat = activeCat {
                    Section {
                        HStack(spacing: 14) {
                            CatAvatar(theme: theme,
                                      avatarData: cat.avatarData,
                                      size: 60,
                                      showRing: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cat.name).font(.headline).foregroundStyle(theme.deep)
                                if let breed = cat.breed {
                                    Text(breed).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(theme.mood(zh: zh))
                                    .font(.caption2)
                                    .foregroundStyle(theme.main)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)

                        Button {
                            showThemePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "paintpalette.fill")
                                    .foregroundStyle(theme.deep)
                                Text(zh ? "切换主题" : "Switch theme")
                                    .foregroundStyle(.primary)
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(Array(theme.swatches.enumerated()), id: \.offset) { _, c in
                                        Circle().fill(c).frame(width: 10, height: 10)
                                    }
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Button {
                            showCatEdit = true
                        } label: {
                            HStack {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(theme.deep)
                                Text(zh ? "编辑档案" : "Edit profile")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        if cats.count < 2 {
                            Button {
                                showAddCat = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(theme.deep)
                                    Text(zh ? "再加一只猫 ฅ" : "Add another cat ฅ")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: {
                        Text(zh ? "我的猫咪" : "My Cat")
                    }
                }

                Section {
                    Picker(selection: Bindable(lang).currentLanguage) {
                        ForEach(SupportedLanguage.all) { l in
                            Text(l.nativeName).tag(l.code)
                        }
                    } label: {
                        Label {
                            Text(lang.loc("settings.language.section"))
                        } icon: {
                            Image(systemName: "globe")
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text(lang.loc("settings.language.section"))
                } footer: {
                    Text(zh
                         ? "目前 App 界面只有中文和英文,但 AI 分析和聊天会按你选的语言回复。"
                         : "App UI is in Chinese and English for now, but AI analysis and chat reply in whatever language you pick.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section(lang.loc("settings.account.section")) {
                    if let user = auth.user, auth.isLoggedIn {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(LinearGradient(colors: [theme.light, theme.accent],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 44, height: 44)
                                .overlay(Text(String(user.name.prefix(1)))
                                    .font(.headline).foregroundColor(.white))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name).font(.headline)
                                Text(user.email).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button(role: .destructive) {
                            auth.signOut()
                        } label: {
                            Label(lang.loc("settings.signout"),
                                  systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button {
                            Task { await auth.signInWithGoogle() }
                        } label: {
                            HStack {
                                ZStack {
                                    Circle().fill(.white).frame(width: 24, height: 24).shadow(radius: 1)
                                    Text("G").font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                                }
                                Text(lang.loc("auth.google"))
                            }
                        }
                    }
                }

                // Notifications
                Section {
                    NotificationStatusRow()
                } header: {
                    Text(zh ? "提醒" : "Notifications")
                } footer: {
                    Text(zh
                         ? "用于疫苗到期、每日吃药、每周称重打卡。可在系统 \"设置 → 通知\" 里随时关闭。"
                         : "For vaccine due-dates, daily medication times, and weekly weigh-ins. Toggle anytime in Settings → Notifications.")
                }

                // Data & privacy
                Section {
                    Button {
                        showPrivacyPolicy = true
                    } label: {
                        Label {
                            Text(zh ? "隐私政策" : "Privacy Policy")
                        } icon: {
                            Image(systemName: "lock.shield")
                        }
                    }

                    Button {
                        showToS = true
                    } label: {
                        Label {
                            Text(zh ? "服务协议" : "Terms of Service")
                        } icon: {
                            Image(systemName: "doc.text")
                        }
                    }

                    Button {
                        showExport = true
                    } label: {
                        Label {
                            Text(zh ? "导出我的数据" : "Export my data")
                        } icon: {
                            Image(systemName: "square.and.arrow.up.on.square")
                        }
                    }

                    NavigationLink {
                        RecentExportsView()
                    } label: {
                        Label {
                            Text(zh ? "历史导出" : "Recent exports")
                        } icon: {
                            Image(systemName: "tray.full")
                        }
                    }

                    Button {
                        showFeedback = true
                    } label: {
                        Label {
                            Text(zh ? "提交问题 / 反馈" : "Send Feedback")
                        } icon: {
                            Image(systemName: "envelope")
                        }
                    }
                } header: {
                    Text(zh ? "数据与隐私" : "Data & Privacy")
                }

                // Delete account at the very bottom — destructive actions
                // belong away from everyday controls, with a clear footer
                // warning so the user understands the blast radius.
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm1 = true
                    } label: {
                        Label {
                            Text(zh ? "删除账号" : "Delete account")
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                } footer: {
                    Text(zh
                         ? "删除账号会清空所有本地数据:猫咪档案、历史记录、登录信息。此操作不可逆。"
                         : "Deleting your account wipes all local data: cat profiles, history records, and login info. This cannot be undone.")
                }
            }
            .navigationTitle(lang.loc("settings.title"))
        }
        // Delete step 1: confirm dialog
        .alert(zh ? "删除账号?" : "Delete account?",
               isPresented: $showDeleteConfirm1) {
            Button(zh ? "取消" : "Cancel", role: .cancel) { }
            Button(zh ? "继续" : "Continue", role: .destructive) {
                deleteTypedText = ""
                showDeleteConfirm2 = true
            }
        } message: {
            Text(zh
                 ? "所有猫咪档案、分析历史、登录信息都会被永久删除。继续?"
                 : "All cat profiles, history, and login info will be permanently deleted. Continue?")
        }
        // Delete step 2: typed confirmation
        .sheet(isPresented: $showDeleteConfirm2) {
            DeleteConfirmSheet(
                zh: zh,
                theme: theme,
                typed: $deleteTypedText,
                onConfirm: {
                    DataManager.wipeAll(modelContext: modelContext, cats: cats, records: allRecords)
                    themeProvider.activeCatId = nil
                    themeProvider.breedId = nil
                    auth.signOut()
                    showDeleteConfirm2 = false
                },
                onCancel: { showDeleteConfirm2 = false }
            )
        }
        // Export share sheet (legacy, kept for fallback)
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                URLActivitySheet(url: url)
            }
        }
        // Unified export flow: config → loading → success, all in one
        // fullScreenCover to avoid sheet→cover transition races that were
        // cancelling the export mid-flight.
        .fullScreenCover(isPresented: $showExport) {
            ExportFlowView()
                .environment(lang)
                .environment(themeProvider)
        }
        // Privacy + ToS viewers
        .sheet(isPresented: $showPrivacyPolicy) {
            PolicyViewerView(doc: Policies.privacy(zh: zh))
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
        .sheet(isPresented: $showToS) {
            PolicyViewerView(doc: Policies.terms(zh: zh))
        }
        .alert(zh ? "导出失败" : "Export failed",
               isPresented: Binding(get: { exportError != nil },
                                    set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .sheet(isPresented: $showThemePicker) {
            ThemePickerSheet(
                currentBreedId: activeCat?.breedId,
                zh: zh,
                onSelect: { newId in
                    guard let cat = activeCat, let newTheme = CatThemes.byId(newId) else { return }
                    cat.breedId = newId
                    cat.breed = newTheme.name(zh: zh)
                    try? modelContext.save()
                    themeProvider.breedId = newId
                    showThemePicker = false
                }
            )
        }
        .sheet(isPresented: $showCatEdit) {
            if let cat = activeCat {
                CatEditSheet(cat: cat, theme: theme, zh: zh) {
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $showAddCat) {
            OnboardingView(skipWelcome: true) { cat in
                themeProvider.setActive(cat: cat)
                showAddCat = false
            }
        }
    }

    private func exportData() {
        do {
            let url = try DataManager.exportJSON(cats: cats, userEmail: auth.user?.email)
            exportURL = url
            showExportShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// =========================================================
// Delete confirmation sheet — requires typing DELETE/删除
// =========================================================
private struct DeleteConfirmSheet: View {
    let zh: Bool
    let theme: CatTheme
    @Binding var typed: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var requiredWord: String { zh ? "删除" : "DELETE" }
    private var canConfirm: Bool {
        typed.trimmingCharacters(in: .whitespaces).uppercased() == requiredWord.uppercased()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.danger)
                    .padding(.top, 20)

                Text(zh ? "最后一步确认" : "Final confirmation")
                    .font(.title3.weight(.semibold))

                Text(zh
                     ? "请输入 \"\(requiredWord)\" 来确认删除。\n这个操作无法撤销。"
                     : "Type \"\(requiredWord)\" to confirm.\nThis cannot be undone.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                TextField(requiredWord, text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(canConfirm ? Theme.danger : Color.secondary.opacity(0.3),
                                          lineWidth: canConfirm ? 1.5 : 0.5)
                    )

                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    Text(zh ? "永久删除" : "Delete forever")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canConfirm ? Theme.danger : Theme.danger.opacity(0.3))
                        .cornerRadius(14)
                }
                .disabled(!canConfirm)
                .buttonStyle(.plain)

                Button(zh ? "取消" : "Cancel") { onCancel() }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                Spacer()
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// =========================================================
// Theme picker sheet — 22 cards grid
// =========================================================
private struct ThemePickerSheet: View {
    let currentBreedId: String?
    let zh: Bool
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subs
    @State private var paywallReason: SubscriptionManager.GateResult.BlockReason?

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    /// Theme ID free users can use without buying anything. Stays in sync
    /// with SubscriptionManager's "first only" rule.
    private var freeAllowedID: String { CatThemes.all.first?.id ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !subs.hasPremiumAccess {
                    upgradeBanner
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                }
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(CatThemes.all) { t in
                        let locked = !subs.hasPremiumAccess && t.id != freeAllowedID
                        SettingsBreedCard(
                            theme: t,
                            selected: t.id == currentBreedId,
                            locked: locked,
                            zh: zh
                        ) {
                            if locked {
                                paywallReason = .themeLocked
                            } else {
                                onSelect(t.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .navigationTitle(zh ? "挑一只给 ta ♡" : "Pick one ♡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(zh ? "取消" : "Cancel") { dismiss() }
                }
            }
            .sheet(item: $paywallReason) { reason in
                PaywallView(reason: reason)
            }
        }
    }

    /// Persistent upsell card pinned at the top — communicates the unlock
    /// once instead of relying solely on the lock icons (which can read as
    /// "broken" rather than "locked behind purchase").
    private var upgradeBanner: some View {
        Button { paywallReason = .themeLocked } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.open.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.orange))
                VStack(alignment: .leading, spacing: 2) {
                    Text(zh ? "解锁 22 款主题" : "Unlock 22 themes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(zh
                         ? "购买任意次卡或 Pro 后可选所有主题"
                         : "Pick any pack or Pro to use all themes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(UIColor.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsBreedCard: View {
    let theme: CatTheme
    let selected: Bool
    let locked: Bool
    let zh: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                CatAvatar(theme: theme, size: 52, showRing: false)
                    .padding(.top, 6)
                    .opacity(locked ? 0.4 : 1)
                Text(theme.name(zh: zh))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.deep)
                    .lineLimit(1)
                    .opacity(locked ? 0.5 : 1)
                Text(theme.mood(zh: zh))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.main.opacity(0.75))
                    .lineLimit(1)
                    .opacity(locked ? 0.5 : 1)
                HStack(spacing: 2) {
                    ForEach(Array(theme.swatches.enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 6)
                .opacity(locked ? 0.5 : 1)
            }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(selected ? theme.card : theme.bg))
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
                } else if locked {
                    // Lock badge — visible but unobtrusive. Pairs with the
                    // upgrade banner at top + the dimmed card content to
                    // make the gating obvious without screaming.
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.orange))
                        .offset(x: -6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// =========================================================
// Edit cat name / avatar / neuter
// =========================================================
private struct CatEditSheet: View {
    @Bindable var cat: Cat
    let theme: CatTheme
    let zh: Bool
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showPhotoSheet = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var tempImage: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Button { showPhotoSheet = true } label: {
                            ZStack(alignment: .bottomTrailing) {
                                CatAvatar(theme: theme,
                                          avatarData: cat.avatarData,
                                          size: 100,
                                          showRing: true)
                                Circle()
                                    .fill(theme.light)
                                    .frame(width: 32, height: 32)
                                    .overlay(Text("📷").font(.system(size: 16)))
                                    .overlay(Circle().strokeBorder(theme.bg, lineWidth: 2))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .buttonStyle(.plain)
                        Text(zh ? "点头像换照片" : "Tap avatar to change")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                }

                Section(zh ? "基本信息" : "Basic info") {
                    LabeledContent(zh ? "名字" : "Name") {
                        TextField(zh ? "名字" : "Name", text: $cat.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(zh ? "性别" : "Sex") {
                        Picker("", selection: Binding(
                            get: { cat.sex ?? "male" },
                            set: { cat.sex = $0 }
                        )) {
                            Text(zh ? "♂ 男猫" : "♂ Boy").tag("male")
                            Text(zh ? "♀ 女猫" : "♀ Girl").tag("female")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    LabeledContent(zh ? "生日" : "Birthday") {
                        TextField("2023.09", text: Binding(
                            get: { cat.age ?? "" },
                            set: { cat.age = $0.isEmpty ? nil : $0 }
                        ))
                        .multilineTextAlignment(.trailing)
                    }
                    Toggle(zh ? "已绝育" : "Neutered", isOn: $cat.neuter)
                }
            }
            .navigationTitle(zh ? "编辑档案" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(zh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(zh ? "保存" : "Save") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .confirmationDialog(zh ? "头像来源" : "Avatar source",
                            isPresented: $showPhotoSheet,
                            titleVisibility: .visible) {
            Button(zh ? "📸 拍一张" : "📸 Take photo") { showCamera = true }
            Button(zh ? "🖼 从相册选" : "🖼 From library") { showLibrary = true }
            if cat.avatarData != nil {
                Button(zh ? "移除照片" : "Remove", role: .destructive) {
                    cat.avatarData = nil
                }
            }
            Button(zh ? "取消" : "Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: $tempImage, sourceType: .camera, allowsCrop: true)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            ImagePicker(image: $tempImage, sourceType: .photoLibrary, allowsCrop: true)
                .ignoresSafeArea()
        }
        .onChange(of: tempImage) { _, img in
            if let img, let data = img.jpegData(compressionQuality: 0.85) {
                cat.avatarData = data
            }
        }
    }
}


/// Compact row that shows current notification permission status and lets
/// the user request it (or jump to Settings to flip it back on).
private struct NotificationStatusRow: View {
    @Environment(LanguageManager.self) private var lang
    @State private var notif = NotificationService.shared

    private var zh: Bool { lang.isChineseSelected }

    var body: some View {
        HStack {
            Image(systemName: "bell.badge")
                .foregroundStyle(statusColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(zh ? "本地提醒" : "Local notifications")
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            actionButton
        }
        .task { await notif.refreshAuthorizationStatus() }
    }

    private var statusColor: Color {
        switch notif.authorizationStatus {
        case .authorized, .provisional: return .green
        case .denied: return .red
        default: return .secondary
        }
    }

    private var statusText: String {
        switch notif.authorizationStatus {
        case .authorized:    return zh ? "已开启" : "Enabled"
        case .provisional:   return zh ? "试用中" : "Provisional"
        case .denied:        return zh ? "已关闭(系统设置里改)" : "Disabled (change in Settings)"
        case .notDetermined: return zh ? "尚未授权" : "Not yet asked"
        default:             return zh ? "未知状态" : "Unknown"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch notif.authorizationStatus {
        case .notDetermined:
            Button(zh ? "开启" : "Enable") {
                Task { _ = await notif.requestPermissionIfNeeded() }
            }
            .buttonStyle(.bordered)
        case .denied:
            Button(zh ? "去设置" : "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }
}
