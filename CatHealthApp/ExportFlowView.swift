import SwiftUI
import UIKit
import SwiftData

/// Full-screen export flow following the pet_export_loading_and_success mockup.
/// Theme-aware: every color (ring, check, confetti, file icons) follows the active cat's theme.
struct ExportFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(ThemeProvider.self) private var themeProvider
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Cat.createdAt) private var cats: [Cat]

    @State private var phase: Phase = .config
    @State private var runningConfig = ExportConfig()
    @State private var completedFiles: [ExportedFile] = []
    @State private var exportError: String?
    @State private var previewURL: URL?
    @State private var showPreview = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var hasStarted = false

    private var theme: CatTheme { themeProvider.theme }
    private var zh: Bool { lang.isChineseSelected }

    enum Phase: Equatable {
        case config
        case loading(step: ExportStep)
        case success
        case failed
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            Group {
                switch phase {
                case .config:
                    configBody
                case .loading(let step):
                    loadingBody(step: step)
                case .success:
                    successBody
                case .failed:
                    failedBody
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.88), value: phase)
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                URLActivitySheet(url: url)
            }
        }
        .fullScreenCover(isPresented: $showPreview) {
            if let url = previewURL {
                QuickLookPreview(url: url)
            }
        }
        .overlay(alignment: .top) { toastOverlay }
    }

    // MARK: - Config

    private var configBody: some View {
        ExportConfigSheet(
            onConfirm: { config in
                runningConfig = config
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    phase = .loading(step: .collecting)
                }
                Task { await runExport() }
            },
            onCancel: { dismiss() }
        )
    }

    // MARK: - Loading

    private func loadingBody(step: ExportStep) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            // Progress ring + center CatAvatar + %
            progressRing(progress: progressFraction(for: step))
                .padding(.bottom, 28)

            Text(zh ? "正在生成档案" : "Generating archive")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.deep)

            Text(stepSubtitle(for: step))
                .font(.system(size: 13))
                .foregroundStyle(theme.main.opacity(0.8))
                .padding(.top, 4)

            // Step list
            VStack(spacing: 10) {
                let p = progressFraction(for: step)
                stepRow(done: p >= 0.2, active: step == .collecting,
                        label: zh ? "收集基本信息" : "Collecting info")
                stepRow(done: p >= 0.35, active: step == .json,
                        label: zh ? "打包档案 JSON" : "Packaging JSON")
                stepRow(done: p >= 0.65, active: isCardStep(step),
                        label: cardStepLabel(for: step))
                stepRow(done: p >= 0.92, active: isPdfStep(step),
                        label: pdfStepLabel(for: step))
                stepRow(done: p >= 1.0, active: step == .finalizing,
                        label: zh ? "整理文件" : "Finalizing")
            }
            .frame(maxWidth: 260)
            .padding(.top, 28)

            Spacer()

            // Cancel
            Button { cancel() } label: {
                Text(zh ? "取消" : "Cancel")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.main)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.light.opacity(0.7), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }

    // Big themed progress ring with CatAvatar + % in the middle.
    // Has a subtle "breathing" pulse while loading — feels alive.
    @State private var ringPulse: CGFloat = 1.0
    private func progressRing(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(theme.card, lineWidth: 6)
                .frame(width: 140, height: 140)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(theme.deep, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)

            VStack(spacing: 6) {
                // IMPORTANT: SimpleCatAvatar (plain Circle + Image) —
                // previously used CatAvatar → CatFace → Canvas, which
                // rebuilt Metal pipelines on every progress update,
                // blocked main thread, and got the app killed mid-export.
                SimpleCatAvatar(theme: theme,
                                name: activeCatName,
                                avatarData: activeCatAvatar,
                                size: 56)
                    .scaleEffect(ringPulse)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.deep)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                ringPulse = 1.06
            }
        }
    }

    private func stepRow(done: Bool, active: Bool, label: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if done {
                    Circle().fill(Color(red: 0.11, green: 0.62, blue: 0.46))
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else if active {
                    Circle().strokeBorder(theme.deep, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    Circle().trim(from: 0, to: 0.3)
                        .stroke(theme.deep, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(spinAngle))
                } else {
                    Circle().strokeBorder(theme.light.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                }
            }
            .frame(width: 22)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(done ? theme.main.opacity(0.7) : (active ? theme.deep : theme.main.opacity(0.4)))

            Spacer()
        }
    }

    @State private var spinAngle: Double = 0
    private func startSpin() {
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
            spinAngle = 360
        }
    }

    // MARK: - Success

    @State private var successAppeared = false

    private var successBody: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 50)

            // Check + themed confetti (with staggered entrance)
            ZStack {
                // Confetti animates outward from center + fade-in, staggered
                ForEach(Array(confettiPositions.enumerated()), id: \.offset) { i, dot in
                    RoundedRectangle(cornerRadius: dot.radius)
                        .fill(dot.color)
                        .frame(width: dot.size, height: dot.size)
                        .rotationEffect(.degrees(dot.rotation))
                        .offset(x: successAppeared ? dot.x : 0,
                                y: successAppeared ? dot.y : 0)
                        .opacity(successAppeared ? 1 : 0)
                        .scaleEffect(successAppeared ? 1 : 0.2)
                        .animation(
                            .spring(response: 0.6, dampingFraction: 0.65)
                            .delay(0.25 + Double(i) * 0.05),
                            value: successAppeared
                        )
                }
                Circle()
                    .fill(theme.light.opacity(0.5))
                    .frame(width: 96, height: 96)
                    .scaleEffect(successAppeared ? 1.0 : 0.7)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.05),
                               value: successAppeared)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(theme.deep)
                    .scaleEffect(successAppeared ? 1.0 : 0.3)
                    .opacity(successAppeared ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.15),
                               value: successAppeared)
            }
            .padding(.bottom, 18)
            .onAppear {
                successAppeared = true
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }

            Text(zh ? "导出完成" : "Export complete")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.deep)
            Text(zh
                 ? "为 \(cats.count) 只猫生成了 \(completedFiles.count) 个文件"
                 : "Generated \(completedFiles.count) files for \(cats.count) cat(s)")
                .font(.system(size: 12))
                .foregroundStyle(theme.main.opacity(0.8))
                .padding(.top, 4)
                .padding(.bottom, 22)

            // File list
            VStack(spacing: 0) {
                ForEach(Array(completedFiles.enumerated()), id: \.element.id) { idx, file in
                    fileRow(file: file)
                    if idx < completedFiles.count - 1 {
                        Divider().background(theme.light.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.card.opacity(0.5))
            )
            .padding(.horizontal, 20)

            SmartShareRow(files: completedFiles, theme: theme, zh: zh, onToast: showToast)
                .padding(.horizontal, 20)
                .padding(.top, 22)

            // "Where do my files live?" hint — addresses the user-reported
            // surprise that saving to Files makes future taps open Books /
            // Photos / Quick Look (iOS default for that file type) instead of
            // Carmel. They can always come back via Settings → 历史导出 to
            // preview in-app.
            Text(zh
                 ? "保存的文件可在 设置 → 历史导出 里随时再次预览"
                 : "Saved files stay in Settings → Recent Exports for in-app preview")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 14)

            Spacer()

            // Buttons
            VStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Text(zh ? "完成" : "Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 18).fill(theme.deep))
                        .shadow(color: theme.deep.opacity(0.25), radius: 10, y: 4)
                }

                Button {
                    reexport()
                } label: {
                    Text(zh ? "重新导出" : "Re-export")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.main)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    private func fileRow(file: ExportedFile) -> some View {
        Button {
            previewURL = file.url
            showPreview = true
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBg(for: file.kind))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: iconName(for: file.kind))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(iconFg(for: file.kind))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.deep)
                        .lineLimit(1)
                    Text("\(formatBytes(file.sizeBytes)) · \(file.subtitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.main.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.main.opacity(0.4))
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // Toast from SmartShareRow results
    @State private var toastMessage: String?
    @State private var toastVisible = false
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            toastVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.3)) { toastVisible = false }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if toastVisible, let msg = toastMessage {
            Text(msg)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(theme.deep))
                .shadow(color: theme.deep.opacity(0.3), radius: 8, y: 3)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Failed

    private var failedBody: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundColor(.orange)
            Text(zh ? "导出失败" : "Export failed").font(.headline)
            Text(exportError ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button { reexport() } label: {
                Text(zh ? "重试" : "Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.bg)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 16).fill(theme.deep))
            }
            .padding(.horizontal, 30)
            Button(zh ? "取消" : "Cancel") { dismiss() }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    // MARK: - Driver

    /// Drives the full export. Since the flow owns a single view instance across
    /// config → loading → success phases, the Task runs freely without being
    /// cancelled by phantom presentation lifecycle events.
    private func runExport() async {
        guard !hasStarted else {
            print("[Export] runExport() skipped — already started")
            return
        }
        hasStarted = true
        startSpin()

        do {
            let files = try await DataManager.exportAll(
                cats: cats,
                config: runningConfig,
                userEmail: nil,
                zh: zh,
                onStep: { step in
                    phase = .loading(step: step)
                }
            )
            print("[Export] all files produced, switching to .success")
            completedFiles = files
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                phase = .success
            }
            print("[Export] phase now .success")
        } catch is CancellationError {
            print("[Export] task cancelled — view dismissed")
        } catch {
            print("[Export] failed: \(error.localizedDescription)")
            exportError = error.localizedDescription
            phase = .failed
        }
    }

    private func cancel() {
        // User pressed Cancel — just dismiss, .task will cancel automatically
        dismiss()
    }

    private func reexport() {
        completedFiles.removeAll()
        exportError = nil
        hasStarted = false
        phase = .loading(step: .collecting)
        Task { await runExport() }
    }

    private func shareAllFiles() {
        // Present share sheet for the JSON (or first file). For multi-file share,
        // iOS share sheet accepts array of URLs — we use first for simplicity here.
        if let first = completedFiles.first {
            shareURL = first.url
            showShare = true
        }
    }

    // MARK: - Helpers

    private var activeCatAvatar: Data? {
        themeProvider.activeCat(from: cats)?.avatarData
    }

    private var activeCatName: String {
        themeProvider.activeCat(from: cats)?.name ?? "C"
    }

    private func progressFraction(for step: ExportStep) -> Double {
        switch step {
        case .collecting:                          return 0.12
        case .json:                                return 0.28
        case .card(let i, let t, _):
            let per = 0.25 / Double(max(t, 1))
            return 0.35 + per * Double(i)
        case .pdf(let i, let t, _):
            let per = 0.25 / Double(max(t, 1))
            return 0.65 + per * Double(i)
        case .finalizing:                          return 0.95
        case .done:                                return 1.0
        }
    }

    private func isCardStep(_ step: ExportStep) -> Bool {
        if case .card = step { return true }
        return false
    }
    private func isPdfStep(_ step: ExportStep) -> Bool {
        if case .pdf = step { return true }
        return false
    }

    private func cardStepLabel(for step: ExportStep) -> String {
        if case .card(let i, let t, let name) = step {
            return zh ? "渲染 \(name) 的档案卡 (\(i)/\(t))"
                      : "Rendering \(name)'s card (\(i)/\(t))"
        }
        return zh ? "渲染档案卡" : "Rendering cards"
    }
    private func pdfStepLabel(for step: ExportStep) -> String {
        if case .pdf(let i, let t, let name) = step {
            return zh ? "生成 \(name) 的 PDF (\(i)/\(t))"
                      : "Building \(name)'s PDF (\(i)/\(t))"
        }
        return zh ? "生成健康档案 PDF" : "Building PDFs"
    }

    private func stepSubtitle(for step: ExportStep) -> String {
        switch step {
        case .collecting:
            return zh ? "清点猫咪档案..." : "Taking inventory..."
        case .json:
            return zh ? "打包数据文件..." : "Packing data..."
        case .card(let i, let t, let name):
            return zh ? "生成 \(name) 的档案卡 (\(i)/\(t))"
                      : "Rendering \(name)'s card (\(i)/\(t))"
        case .pdf(let i, let t, let name):
            return zh ? "排版 \(name) 的 PDF (\(i)/\(t))"
                      : "Laying out \(name)'s PDF (\(i)/\(t))"
        case .finalizing:
            return zh ? "整理文件..." : "Finalizing..."
        case .done:
            return zh ? "搞定!" : "All done!"
        }
    }

    // Confetti pulled from current theme for per-cat personality
    private var confettiPositions: [Confetti] {
        [
            Confetti(color: theme.accent, size: 7, radius: 1, rotation: 25,  x: -55, y: -45),
            Confetti(color: theme.main,   size: 6, radius: 3, rotation: 0,   x:  55, y: -30),
            Confetti(color: theme.deep,   size: 6, radius: 3, rotation: 0,   x: -60, y:  40),
            Confetti(color: theme.nose,   size: 8, radius: 1, rotation: -15, x:  58, y:  48),
            Confetti(color: theme.eye,    size: 5, radius: 3, rotation: 0,   x:  18, y: -60),
            Confetti(color: theme.light,  size: 6, radius: 2, rotation: 10,  x: -35, y:  60),
        ]
    }
    private struct Confetti {
        let color: Color
        let size: CGFloat
        let radius: CGFloat
        let rotation: Double
        let x: CGFloat
        let y: CGFloat
    }

    private func iconName(for kind: ExportedFile.Kind) -> String {
        switch kind {
        case .json: return "curlybraces"
        case .png:  return "photo"
        case .pdf:  return "doc.text"
        }
    }
    private func iconBg(for kind: ExportedFile.Kind) -> Color {
        switch kind {
        case .json: return theme.card
        case .png:  return theme.light.opacity(0.5)
        case .pdf:  return Color(red: 0.88, green: 0.96, blue: 0.93)
        }
    }
    private func iconFg(for kind: ExportedFile.Kind) -> Color {
        switch kind {
        case .json: return theme.deep
        case .png:  return theme.deep
        case .pdf:  return Color(red: 0.06, green: 0.43, blue: 0.34)
        }
    }

    private func formatBytes(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f MB", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.0f KB", Double(n) / 1_000) }
        return "\(n) B"
    }
}
