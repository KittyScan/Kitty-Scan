import SwiftUI
import SwiftData
import UIKit
import PhotosUI

struct CameraView: View {
    @Environment(LanguageManager.self) var lang
    @Environment(ThemeProvider.self) var themeProvider
    @Environment(SubscriptionManager.self) var subs
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Cat.createdAt) private var cats: [Cat]

    private var theme: CatTheme { themeProvider.theme }

    @State private var selectedCat: Cat?
    @State private var showAddCat = false
    @State private var selectedImage: UIImage?
    @State private var showImageSourceSheet = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var todayNote = ""
    @FocusState private var todayNoteFocused: Bool
    @State private var isAnalyzing = false

    // Long-press on a cat surfaces a context menu with "Delete" — uses the
    // iOS-native long-press path (works inside ScrollView), no wiggle mode.
    @State private var pendingDeleteCat: Cat?
    @State private var report: HealthReport?
    @State private var errorMessage: String?

    // "Different cat detected" loop. When the visual identity check says the
    // photo is *not* the active cat, we hold off on persisting and ask the
    // user what to do. `pendingReport`/`pendingImage` carry the analysis that
    // hasn't been saved yet; `mismatchVerdict` is shown for transparency.
    // `mismatchOriginalCat` remembers which profile the photo *would* have
    // been saved under — we visually deselect `selectedCat` so the user sees
    // immediately that the photo isn't being attributed to their cat, but we
    // still need the original reference for the "save anyway" alert path.
    @State private var pendingReport: HealthReport?
    @State private var pendingImage: UIImage?
    @State private var mismatchVerdict: CatIdentityService.Verdict?
    @State private var mismatchOriginalCat: Cat?
    @State private var showMismatchAlert = false
    @State private var showPrefilledAddCat = false
    /// True when the displayed `report` was generated *without* the active
    /// cat's context (because the identity check flagged a different cat).
    /// This drives the on-screen view to omit the active cat's name, theme,
    /// and chat — the report should read as a fresh/standalone analysis until
    /// the user confirms what to do with it.
    @State private var reportIsForeignCat = false

    // Photo-quality pre-flight: when the on-device check flags a problem
    // (no cat / too dark / too bright), we warn the user before spending an
    // API call. They can override and continue if they think the algorithm
    // is wrong.
    @State private var qualityIssue: PhotoQualityService.Issue?
    @State private var showQualityAlert = false

    // Paywall: presented when the user hits a quota wall before analyze runs.
    @State private var paywallReason: SubscriptionManager.GateResult.BlockReason?

    // Video import flow — gated to pack/Pro users (free can't analyze video).
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var videoExtractionError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroHeader
                    catSelector
                    imageSection
                    todayNoteSection
                    actionButtons
                    if let errorMessage { errorBanner(errorMessage) }
                    if let report {
                        let displayCat: Cat? = reportIsForeignCat ? nil : selectedCat
                        HealthReportView(
                            report: report,
                            cat: displayCat,
                            recentRecords: displayCat.map { Array($0.records.sorted { $0.date > $1.date }.prefix(5)) } ?? []
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        todayNoteFocused = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down.circle.fill")
                            Text(lang.isChineseSelected ? "收起键盘" : "Hide keyboard")
                        }
                        .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .confirmationDialog(lang.loc("camera.source.title"),
                            isPresented: $showImageSourceSheet,
                            titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(lang.loc("camera.source.camera")) { showCamera = true }
            }
            Button(lang.loc("camera.source.library")) { showPhotoLibrary = true }
            Button(lang.loc("camera.source.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: $selectedImage, sourceType: .camera, allowsCrop: true).ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePicker(image: $selectedImage, sourceType: .photoLibrary, allowsCrop: true).ignoresSafeArea()
        }
        .sheet(isPresented: $showAddCat) { AddCatSheet(onSave: { cat in selectedCat = cat }) }
        .sheet(isPresented: $showPrefilledAddCat) {
            AddCatSheet(
                prefillBreed: pendingReport?.breed,
                prefillAvatar: pendingImage,
                onSave: { newCat in
                    // Persist the held-back report under the new cat, then make
                    // it the active profile so the user lands in the right place.
                    if let r = pendingReport, let img = pendingImage {
                        let record = HistoryRecord(
                            from: r, image: img,
                            todayNote: todayNote.isEmpty ? nil : todayNote,
                            cat: newCat
                        )
                        record.originalLanguage = lang.currentLanguage
                        modelContext.insert(record)
                    }
                    themeProvider.setActive(cat: newCat)
                    selectedCat = newCat
                    pendingReport = nil
                    pendingImage = nil
                    mismatchVerdict = nil
                    mismatchOriginalCat = nil
                    // The on-screen report now belongs to the new cat — drop
                    // the "foreign" flag so chat etc. attach to the new profile.
                    reportIsForeignCat = false
                }
            )
        }
        .alert(
            lang.isChineseSelected ? "这好像不是同一只猫?" : "Is this a different cat?",
            isPresented: $showMismatchAlert,
            presenting: mismatchVerdict
        ) { _ in
            Button(lang.isChineseSelected ? "建立新档案" : "Create new profile") {
                showPrefilledAddCat = true
            }
            Button(lang.isChineseSelected ? "就是 \(mismatchOriginalCat?.name ?? "TA"),保存" : "Same cat, save it") {
                let original = mismatchOriginalCat
                persistPending(under: original)
                // User overrode the verdict — restore the selector state we
                // proactively cleared, and re-attach the on-screen report to
                // their cat (so chat etc. work).
                selectedCat = original
                mismatchOriginalCat = nil
                reportIsForeignCat = false
            }
            Button(lang.isChineseSelected ? "取消" : "Cancel", role: .cancel) {
                // Leave the selector deselected — the user explicitly walked
                // away from attributing this photo. They can re-pick a cat
                // manually, or just go take a new photo.
                pendingReport = nil
                pendingImage = nil
                mismatchVerdict = nil
                mismatchOriginalCat = nil
            }
        } message: { _ in
            let zh = lang.isChineseSelected
            let breed = pendingReport?.breed ?? ""
            let active = mismatchOriginalCat?.name ?? ""
            Text(zh
                 ? "图片看上去和「\(active)」之前的照片差别比较大,识别到的品种是「\(breed)」。要不要建一个新档案?"
                 : "This photo doesn't look like \(active)'s previous photos. Detected breed: \(breed). Create a new profile?")
        }
        .onChange(of: selectedImage) {
            report = nil; errorMessage = nil
            pendingReport = nil; pendingImage = nil
            mismatchVerdict = nil; mismatchOriginalCat = nil
            reportIsForeignCat = false
            qualityIssue = nil
        }
        .onChange(of: videoPickerItem) { _, new in
            guard let new else { return }
            Task { await handleVideoPicked(new) }
        }
        .alert(lang.isChineseSelected ? "视频问题" : "Video issue",
               isPresented: Binding(
                get: { videoExtractionError != nil },
                set: { if !$0 { videoExtractionError = nil } }
               )) {
            Button(lang.isChineseSelected ? "好的" : "OK") {
                videoExtractionError = nil
                videoPickerItem = nil
            }
        } message: {
            Text(videoExtractionError ?? "")
        }
        .sheet(item: $paywallReason) { reason in
            PaywallView(reason: reason)
        }
        .alert(
            qualityAlertTitle,
            isPresented: $showQualityAlert,
            presenting: qualityIssue
        ) { _ in
            Button(lang.isChineseSelected ? "重新选张照片" : "Pick another photo") {
                showImageSourceSheet = true
                qualityIssue = nil
            }
            Button(lang.isChineseSelected ? "还是分析" : "Analyze anyway") {
                qualityIssue = nil
                Task { await analyze(skipQualityCheck: true) }
            }
            Button(lang.isChineseSelected ? "取消" : "Cancel", role: .cancel) {
                qualityIssue = nil
            }
        } message: { issue in
            Text(qualityAlertMessage(for: issue))
        }
        .alert(
            lang.isChineseSelected
                ? "确定要删除「\(pendingDeleteCat?.name ?? "")」吗?"
                : "Delete \(pendingDeleteCat?.name ?? "")?",
            isPresented: Binding(
                get: { pendingDeleteCat != nil },
                set: { if !$0 { pendingDeleteCat = nil } }
            ),
            presenting: pendingDeleteCat
        ) { cat in
            Button(lang.isChineseSelected ? "删除" : "Delete", role: .destructive) {
                deleteCat(cat)
            }
            Button(lang.isChineseSelected ? "取消" : "Cancel", role: .cancel) {
                pendingDeleteCat = nil
            }
        } message: { _ in
            Text(lang.isChineseSelected
                 ? "所有健康记录、日记、提醒都会一起删掉,无法恢复喵 (>﹏<)"
                 : "All health records, diary entries, and reminders will be deleted. This can't be undone.")
        }
        .onAppear {
            if selectedCat == nil {
                selectedCat = themeProvider.activeCat(from: cats)
            }
        }
        .onChange(of: themeProvider.activeCatId) { _, _ in
            selectedCat = themeProvider.activeCat(from: cats)
        }
        // Sync the OTHER direction: when the user taps a cat in the selector
        // (or the mismatch loop assigns a new cat), promote it to the global
        // active cat so the gradient header / theme follow along. Keyed on
        // `id` because SwiftData @Model classes don't compare by value.
        // Skip when `selectedCat` goes nil (foreign-cat loop intentionally
        // deselects mid-flow — we don't want to clobber the theme then).
        .onChange(of: selectedCat?.id) { _, _ in
            if let cat = selectedCat {
                themeProvider.setActive(cat: cat)
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [theme.deep, theme.main],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea(edges: .top).frame(height: 140)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🐾 KittyScan")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(lang.loc("camera.app.subtitle"))
                        .font(.subheadline).foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                if let cat = selectedCat ?? cats.first {
                    CatAvatar(theme: theme,
                              avatarData: cat.avatarData,
                              size: 60,
                              showRing: false)
                        .opacity(0.9)
                } else {
                    Text("🐾").font(.system(size: 50)).opacity(0.6)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }

    // MARK: - Cat Selector

    private var catSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.loc("camera.subject")).font(.caption).foregroundColor(.secondary).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Add cat button
                    Button { showAddCat = true } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(theme.card).frame(width: 52, height: 52)
                                Image(systemName: "plus").font(.title3).foregroundColor(theme.deep)
                            }
                            Text(lang.loc("camera.add.cat")).font(.caption2).foregroundColor(theme.deep)
                        }
                    }

                    ForEach(cats) { cat in
                        catChip(cat)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func catChip(_ cat: Cat) -> some View {
        let catTheme = CatThemes.byId(cat.breedId) ?? theme
        let isSelected = selectedCat?.id == cat.id

        Button { selectedCat = cat } label: {
            VStack(spacing: 4) {
                ZStack {
                    CatAvatar(theme: catTheme,
                              avatarData: cat.avatarData,
                              size: 52,
                              showRing: false)
                    if isSelected {
                        Circle().strokeBorder(theme.deep, lineWidth: 2.5)
                            .frame(width: 52, height: 52)
                    }
                }
                Text(cat.name)
                    .font(.caption2)
                    .foregroundColor(isSelected ? theme.deep : .secondary)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        // Long-press → native iOS context menu with Delete. Works reliably
        // inside the horizontal ScrollView (handled by UIKit, not by a
        // SwiftUI gesture that competes with scroll panning).
        .contextMenu {
            Button(role: .destructive) {
                pendingDeleteCat = cat
            } label: {
                Label(lang.isChineseSelected ? "删除「\(cat.name)」" : "Delete \(cat.name)",
                      systemImage: "trash")
            }
        }
    }

    // MARK: - Image Section

    private var imageSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.cardSecondary)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(8)
                    .onTapGesture { showImageSourceSheet = true }
            } else {
                VStack(spacing: 12) {
                    CatAvatar(theme: theme, size: 72, showRing: false)
                    Text(lang.loc("camera.placeholder.title"))
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

                    // Photo-quality hints
                    VStack(alignment: .leading, spacing: 4) {
                        tipRow("☀️", lang.isChineseSelected ? "光线充足,避免逆光"  : "Bright light, no backlight")
                        tipRow("📐", lang.isChineseSelected ? "猫脸居中,占画面 2/3" : "Center face, fill 2/3 of frame")
                        tipRow("🔍", lang.isChineseSelected ? "对焦清晰,别动" : "In focus, hold still")
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(theme.card.opacity(0.5))
                    .cornerRadius(12)
                    .padding(.top, 6)
                }
                .padding(.vertical, 30).padding(.horizontal, 20)
            }
        }
        .padding(.horizontal)
    }

    private func tipRow(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(emoji).font(.caption)
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Today's Note

    private var todayNoteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lang.loc("camera.today.label")).font(.caption).foregroundColor(.secondary)
            TextField(lang.loc("camera.today.placeholder"), text: $todayNote, axis: .vertical)
                .font(.subheadline)
                .focused($todayNoteFocused)
                .padding(12)
                .background(Theme.cardSecondary)
                .cornerRadius(14)
                .lineLimit(2...4)
        }
        .padding(.horizontal)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if selectedImage != nil {
                Button { Task { await analyze() } } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isAnalyzing
                                  ? LinearGradient(colors: [theme.deep.opacity(0.5), theme.main.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [theme.deep, theme.main], startPoint: .leading, endPoint: .trailing))
                        if isAnalyzing {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text(analyzeButtonLabel).foregroundColor(.white).fontWeight(.semibold)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "pawprint.fill").foregroundColor(.white)
                                Text(lang.loc("camera.analyze")).fontWeight(.bold).foregroundColor(.white)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                }
                .disabled(isAnalyzing)
                .shadow(color: theme.deep.opacity(0.3), radius: 8, x: 0, y: 4)
            }

            Button { showImageSourceSheet = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedImage == nil ? "photo.on.rectangle.angled" : "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                    Text(selectedImage == nil ? lang.loc("camera.select") : lang.loc("camera.reselect"))
                        .font(.subheadline)
                }
                .foregroundColor(selectedImage == nil ? Theme.info : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, selectedImage == nil ? 14 : 8)
                .background(selectedImage == nil ? Theme.info.opacity(0.08) : Color.clear)
                .cornerRadius(12)
            }

            // Video analysis — pack/Pro only. Free users tapping this hit
            // the paywall before any video gets imported, so we don't waste
            // their time picking a clip they can't analyze.
            videoButton
            quotaIndicator
        }
        .padding(.horizontal)
    }

    /// Video import button. Tap behavior depends on tier:
    ///   • Free   → paywall (no video at all)
    ///   • Pack   → opens PhotosPicker for ≤ 30s video; we extract 3 keyframes
    ///   • Pro    → same as pack
    /// We deliberately gate BEFORE the picker opens so a free user picking a
    /// clip and then being told "you can't" feels worse than a blocked tap.
    @ViewBuilder
    private var videoButton: some View {
        let zh = lang.isChineseSelected
        let isLocked = subs.tier == .free
        let label = HStack(spacing: 6) {
            Image(systemName: isLocked ? "lock.fill" : "video.fill")
                .font(.subheadline)
            Text(zh ? "用视频分析(更准)" : "Analyze a video (better)")
                .font(.subheadline)
            if isLocked {
                Text(zh ? "Pro" : "Pro")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(theme.deep))
                    .foregroundStyle(theme.bg)
            }
        }
        .foregroundColor(isLocked ? Color.secondary : theme.deep)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(theme.card.opacity(isLocked ? 0.4 : 0.6))
        .cornerRadius(12)

        if isLocked {
            Button { paywallReason = .freeExhausted } label: { label }
                .buttonStyle(.plain)
        } else {
            PhotosPicker(selection: $videoPickerItem,
                         matching: .videos,
                         preferredItemEncoding: .compatible) { label }
        }
    }

    /// Run when the user picks a video. Loads its bytes, writes a temp file,
    /// extracts a 3-frame composite, and feeds the composite into the same
    /// analyze() pipeline as a normal photo.
    private func handleVideoPicked(_ item: PhotosPickerItem) async {
        let zh = lang.isChineseSelected
        do {
            // PhotosPicker can hand us URL or Data; on iOS 17+ Data is the
            // reliable cross-app form. Write to temp so AVAsset can read.
            guard let data = try await item.loadTransferable(type: Data.self) else {
                videoExtractionError = zh ? "无法读取视频" : "Couldn't read the video"
                return
            }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).mov")
            try data.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let composite = try await VideoFrameExtractor.extractCompositeFrame(from: tmp)
            // Feed the composite into the existing photo analyze pipeline —
            // identity check, quota gate, Claude call, persistence: all reused.
            selectedImage = composite
        } catch VideoFrameExtractor.Error.tooLong(let secs) {
            videoExtractionError = zh
                ? "视频太长(\(Int(secs)) 秒),最多 30 秒"
                : "Video too long (\(Int(secs))s); max 30s"
        } catch {
            videoExtractionError = zh
                ? "视频处理失败: \(error.localizedDescription)"
                : "Video processing failed: \(error.localizedDescription)"
        }
    }

    /// Tiny footer showing how many analyses remain. Tappable → paywall, so the
    /// upsell is one tap away from anywhere on the camera screen. Shown only
    /// when remaining is finite — subscribers see it during the period; we hide
    /// it once their reset comes back.
    @ViewBuilder
    private var quotaIndicator: some View {
        let zh = lang.isChineseSelected
        switch subs.tier {
        case .free:
            let left = max(0, SubscriptionManager.freeLifetimeAnalyses - subs.freeUsed)
            Button {
                paywallReason = left > 0 ? .freeExhausted : .freeExhausted
            } label: {
                Text(zh ? "免费体验剩 \(left) 次 · 升级 Pro" : "\(left) free analyses left · Upgrade")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .packCredits(let n):
            Button { paywallReason = .packEmpty } label: {
                Text(zh ? "次卡剩 \(n) 次 · 看方案" : "\(n) pack credits left · View plans")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .subscriber:
            let left = max(0, SubscriptionManager.subMonthlyAnalyses - subs.subAnalyzesUsed)
            Text(zh ? "本月 Pro 还剩 \(left) 次分析" : "Pro · \(left) analyses left this month")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var analyzeButtonLabel: String {
        selectedCat.map { lang.loc("camera.analyzing") + " \($0.name)…" } ?? lang.loc("camera.analyzing")
    }

    private func errorBanner(_ message: String) -> some View {
        let friendly = friendlyErrorMessage(message)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lang.isChineseSelected ? "分析失败了喵" : "Analysis failed")
                        .font(.subheadline.weight(.semibold))
                    Text(friendly)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button {
                    Task { await analyze() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text(lang.isChineseSelected ? "重试" : "Retry")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(theme.deep)
                    .cornerRadius(10)
                }
                Button {
                    errorMessage = nil
                } label: {
                    Text(lang.isChineseSelected ? "关闭" : "Dismiss")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private var qualityAlertTitle: String {
        let zh = lang.isChineseSelected
        return zh ? "这张照片可能不太适合分析" : "This photo may not analyze well"
    }

    private func qualityAlertMessage(for issue: PhotoQualityService.Issue) -> String {
        let zh = lang.isChineseSelected
        switch issue {
        case .noCatDetected:
            return zh
                ? "没有看到清楚的猫咪。是不是猫脸没对准,或者距离太远?换一张面部清楚的照片效果会好很多。"
                : "I don't see a clear cat. Maybe the face isn't centered, or it's too far away. A close-up of the face works much better."
        case .tooDark:
            return zh
                ? "照片有点暗,毛色和眼睛细节看不清。打开灯或者去窗边再拍一张?"
                : "The photo is dark — fur and eye details are hard to read. Try better lighting or near a window."
        case .tooBright:
            return zh
                ? "照片过曝了,细节都被白光盖住。避开直射光源再拍一张吧。"
                : "The photo is overexposed — details are washed out. Try moving away from direct light."
        case .tooBlurry:
            return zh
                ? "照片有点糊喵 (>﹏<) — 毛发纹理和眼睛细节看不清,分析效果会打折哦。\n小贴士:对焦后稳一秒再按快门,或者把猫放近一点再拍 ฅ"
                : "The photo looks a bit blurry (>﹏<) — fur texture and eye details are hard to read.\nTip: hold steady for a beat after focusing, or move closer to your kitty ฅ"
        }
    }

    private func friendlyErrorMessage(_ raw: String) -> String {
        let low = raw.lowercased()
        let zh = lang.isChineseSelected
        if low.contains("timed out") || low.contains("timeout") {
            return zh ? "请求超时了 · 检查一下网络再试一次?" : "Request timed out. Check your network and try again."
        }
        if low.contains("offline") || low.contains("network") || low.contains("internet") {
            return zh ? "网络好像断了,连上 WiFi 或数据再试" : "Looks like no network. Connect to WiFi/cellular and retry."
        }
        if low.contains("429") || low.contains("rate") {
            return zh ? "有点快啦 · 等一会儿再来" : "Too many requests. Slow down and try again in a bit."
        }
        if low.contains("401") || low.contains("403") {
            return zh ? "服务器拒绝访问了 · 请联系开发者" : "Server rejected the request. Please contact support."
        }
        if low.contains("500") || low.contains("502") || low.contains("503") {
            return zh ? "服务端暂时有问题,稍等一下" : "Server is having issues. Please try again shortly."
        }
        return raw
    }

    // MARK: - Cat Deletion

    private func deleteCat(_ cat: Cat) {
        // If the deleted cat was the active selection, clear it so the
        // header / theme / report fall back to whatever's left.
        if selectedCat?.id == cat.id { selectedCat = nil }
        if themeProvider.activeCatId == cat.id.uuidString { themeProvider.activeCatId = nil }

        modelContext.delete(cat)
        try? modelContext.save()

        pendingDeleteCat = nil
    }

    // MARK: - Analysis

    private func analyze(skipQualityCheck: Bool = false) async {
        guard let image = selectedImage else { return }

        // Quota gate — runs *before* anything else so we never start a
        // server call (or even a Vision pre-flight) for a user who can't pay
        // for it. Paywall sheet handles upsell.
        if case .blocked(let reason) = subs.canAnalyze() {
            paywallReason = reason
            return
        }

        isAnalyzing = true; errorMessage = nil; report = nil
        reportIsForeignCat = false
        defer { isAnalyzing = false }

        // Photo-quality pre-flight — skipped on the user-confirmed retry path
        // so they can override our detector if it's wrong. Runs entirely
        // on-device, so a bad photo never costs an Anthropic call.
        if !skipQualityCheck {
            if let issue = await PhotoQualityService.shared.check(image: image) {
                qualityIssue = issue
                showQualityAlert = true
                return
            }
        }

        do {
            let activeCat = selectedCat

            // Identity check FIRST — it's a fast on-device Vision pass (~50ms)
            // and decides what context to feed Claude. Doing it after the
            // Claude call would mean the report is already contaminated by the
            // wrong cat's name/breed/history before we can correct course.
            var verdict: CatIdentityService.Verdict?
            if let activeCat {
                verdict = await CatIdentityService.shared.compare(newImage: image, against: activeCat)
            }
            let isForeign = (verdict?.decision == .differentCat)

            // Strip cat context for foreign-cat photos so Claude generates a
            // clean, standalone report instead of personalizing to the wrong cat.
            let contextCat: Cat? = isForeign ? nil : activeCat
            let recentRecords = contextCat.map {
                Array($0.records.sorted { $0.date > $1.date }.prefix(5))
            } ?? []
            // Last 7 days of diary entries — feeds into the prompt so the AI
            // can pair the photo with "what's the routine been like" signals
            // (e.g. didn't eat much + lethargic eyes → more likely real concern).
            let recentLogs: [DailyLog] = contextCat.map {
                let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                return $0.dailyLogs
                    .filter { $0.date >= cutoff }
                    .sorted { $0.date > $1.date }
            } ?? []

            // Pro users get Sonnet 4.6 + 1568px (premium tier); free + pack
            // users get Haiku 4.5 + 768px (economy tier). Cost difference is
            // ~6× so this is the single biggest lever on unit economics.
            // Subscribers paid for accuracy; free/pack users get usable
            // analyses at a fraction of the cost.
            let tier: ClaudeService.Tier = subs.isSubscribed ? .premium : .economy
            let result = try await ClaudeService.shared.analyzeImage(
                image,
                cat: contextCat,
                recentRecords: recentRecords,
                recentLogs: recentLogs,
                todayNote: todayNote.isEmpty ? nil : todayNote,
                tier: tier,
                isEnglish: !lang.isChineseSelected
            )
            report = result
            reportIsForeignCat = isForeign

            // Decrement quota now (right after the paid call succeeded) so we
            // count it whether the report is saved under the active cat, the
            // friend's-cat path, or discarded entirely. The cost was incurred
            // either way.
            subs.consumeAnalyze()

            if isForeign {
                pendingReport = result
                pendingImage = image
                mismatchVerdict = verdict
                mismatchOriginalCat = activeCat
                // Auto-deselect: the user shouldn't have to manually clear
                // their cat from the selector when we already know this isn't
                // them. The cat selector renders nothing as highlighted, which
                // makes the "this photo isn't your cat" state visible at a
                // glance — separate from the modal alert.
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCat = nil
                }
                showMismatchAlert = true
                return
            }

            persistRecord(report: result, image: image, cat: activeCat)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persist a HealthReport as a HistoryRecord under the given cat. Kept as a
    /// helper so both the normal path and the "save anyway" alert path go
    /// through the same write + personality-refresh logic.
    private func persistRecord(report: HealthReport, image: UIImage, cat: Cat?) {
        let record = HistoryRecord(
            from: report, image: image,
            todayNote: todayNote.isEmpty ? nil : todayNote,
            cat: cat
        )
        // Stamp the language the report was generated in so the translation
        // alert in HistoryDetailView knows which way to translate later.
        record.originalLanguage = lang.currentLanguage
        modelContext.insert(record)
        if let cat, shouldRefreshPersonality(for: cat) {
            let isEnglish = !lang.isChineseSelected
            Task {
                await ClaudeService.shared.refreshPersonality(cat: cat, records: Array(cat.records), isEnglish: isEnglish)
            }
        }
    }

    /// Throttle rule for `refreshPersonality`. We only spend an API call when
    /// either:
    ///   - this is the first time we'd ever generate a summary (record 3+), or
    ///   - at least 5 new records have piled up since the last refresh.
    /// At ~$0.01/call and one analysis per cat per day, this drops personality
    /// regeneration from ~30/month to ~6/month — same content quality, ~80%
    /// cheaper.
    private func shouldRefreshPersonality(for cat: Cat) -> Bool {
        let count = cat.records.count
        guard count >= 3 else { return false }
        guard let last = cat.personalityRefreshedAtCount else {
            // Never generated — first qualifying analysis triggers it.
            return true
        }
        return count >= last + 5
    }

    private func persistPending(under cat: Cat?) {
        guard let r = pendingReport, let img = pendingImage else { return }
        persistRecord(report: r, image: img, cat: cat)
        pendingReport = nil
        pendingImage = nil
        mismatchVerdict = nil
    }
}

// MARK: - Add Cat Sheet

private struct AddCatSheet: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(LanguageManager.self) var lang

    /// Optional prefill from the "different cat detected" loop.
    /// When the user accepts the prompt to create a profile for a freshly
    /// photographed cat, we pass the AI-detected breed and the photo so they
    /// don't have to retype/repick.
    var prefillBreed: String? = nil
    var prefillAvatar: UIImage? = nil
    var onSave: (Cat) -> Void

    @State private var name = ""
    @State private var breed = ""
    @State private var neuter = false
    @State private var issueInput = ""
    @State private var knownIssues: [String] = []
    @State private var selectedAgeKey = "cat.age.1to3"
    @State private var didApplyPrefill = false

    private var agePicker: [(key: String, value: String)] {
        [
            ("cat.age.0to1", "0-1"),
            ("cat.age.1to3", "1-3"),
            ("cat.age.3to7", "3-7"),
            ("cat.age.7plus", "7+"),
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                if let avatar = prefillAvatar {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: avatar)
                                .resizable().scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                Section(lang.loc("cat.add.basic")) {
                    TextField(lang.loc("cat.name.placeholder"), text: $name)
                    TextField(lang.loc("cat.breed.placeholder"), text: $breed)
                    Picker(lang.loc("cat.age.picker"), selection: $selectedAgeKey) {
                        ForEach(agePicker, id: \.key) { item in
                            Text(lang.loc(item.key)).tag(item.key)
                        }
                    }
                    Toggle(lang.loc("cat.neuter"), isOn: $neuter)
                }
                Section(lang.loc("cat.issues.section")) {
                    ForEach(knownIssues, id: \.self) { issue in
                        Text(issue)
                    }
                    .onDelete { knownIssues.remove(atOffsets: $0) }
                    HStack {
                        TextField(lang.loc("cat.issues.placeholder"), text: $issueInput)
                        Button(lang.loc("cat.issues.add")) {
                            let t = issueInput.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty { knownIssues.append(t); issueInput = "" }
                        }
                        .disabled(issueInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(lang.loc("cat.add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.loc("cat.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.loc("cat.save")) {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let ageLabel = lang.loc(selectedAgeKey)
                        let cat = Cat(name: name.trimmingCharacters(in: .whitespaces),
                                      breed: breed.isEmpty ? nil : breed,
                                      age: ageLabel, neuter: neuter,
                                      avatarData: prefillAvatar?.jpegData(compressionQuality: 0.7))
                        cat.knownIssues = knownIssues
                        modelContext.insert(cat)
                        onSave(cat)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !didApplyPrefill else { return }
                didApplyPrefill = true
                if let b = prefillBreed, breed.isEmpty { breed = b }
            }
        }
    }
}
