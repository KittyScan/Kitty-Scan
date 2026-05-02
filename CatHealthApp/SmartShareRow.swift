import SwiftUI
import UIKit
import Photos
import MessageUI

/// Small-red-book-inspired quick-action row. Unlike a generic share sheet,
/// each button here performs a **genuinely different action** using native iOS APIs:
///
///   📥 保存相册 — saves all PNG cards to Photos (no share sheet)
///   📧 邮件     — MFMailComposeViewController with all files as attachments
///   📋 复制     — UIPasteboard with the first PNG image
///   ⋯  更多    — full UIActivityViewController
///
/// Theme-aware: icon tints + backgrounds come from the active CatTheme.
struct SmartShareRow: View {
    let files: [ExportedFile]
    let theme: CatTheme
    let zh: Bool
    let onToast: (String) -> Void

    @State private var showMail = false
    @State private var showActivity = false
    @State private var mailError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(zh ? "快速分享" : "Quick share")
                .font(.system(size: 11))
                .foregroundStyle(theme.main.opacity(0.7))
                .padding(.leading, 4)

            HStack(spacing: 10) {
                action(
                    icon: "square.and.arrow.down.fill",
                    label: zh ? "保存相册" : "Save",
                    sub: "\(pngCount)\(zh ? "张" : "")",
                    bg: theme.accent.opacity(0.25), fg: theme.accent,
                    disabled: pngCount == 0,
                    handler: saveAllPNGs
                )
                action(
                    icon: "envelope.fill",
                    label: zh ? "邮件" : "Email",
                    sub: "\(files.count)\(zh ? "个" : "")",
                    bg: Color(red: 0.9, green: 0.95, blue: 0.98),
                    fg: Color(red: 0.09, green: 0.37, blue: 0.64),
                    disabled: !MFMailComposeViewController.canSendMail(),
                    handler: { showMail = true }
                )
                action(
                    icon: "doc.on.doc.fill",
                    label: zh ? "复制" : "Copy",
                    sub: zh ? "图片" : "image",
                    bg: theme.light.opacity(0.5), fg: theme.deep,
                    disabled: pngCount == 0,
                    handler: copyFirstPNG
                )
                action(
                    icon: "ellipsis",
                    label: zh ? "更多" : "More",
                    sub: zh ? "全部" : "all",
                    bg: theme.card, fg: theme.deep,
                    disabled: false,
                    handler: { showActivity = true }
                )
            }
        }
        .sheet(isPresented: $showMail) {
            MailComposeView(
                files: files,
                subject: zh ? "KittyScan 健康报告" : "KittyScan Health Report",
                body: zh
                     ? "KittyScan 生成的 \(files.count) 个文件在附件里。"
                     : "\(files.count) files from KittyScan attached.",
                onComplete: { success in
                    if success { onToast(zh ? "邮件已发送 ✉️" : "Email sent ✉️") }
                }
            )
        }
        .sheet(isPresented: $showActivity) {
            ActivitySheetURLs(urls: files.map(\.url))
        }
        .alert(zh ? "相册权限" : "Photos permission",
               isPresented: Binding(get: { mailError != nil },
                                    set: { if !$0 { mailError = nil } })) {
            Button("OK", role: .cancel) { mailError = nil }
        } message: {
            Text(mailError ?? "")
        }
    }

    // MARK: - Action button
    @ViewBuilder
    private func action(icon: String,
                        label: String,
                        sub: String,
                        bg: Color,
                        fg: Color,
                        disabled: Bool,
                        handler: @escaping () -> Void) -> some View {
        Button(action: handler) {
            VStack(spacing: 5) {
                Circle()
                    .fill(disabled ? theme.card.opacity(0.5) : bg)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(disabled ? theme.main.opacity(0.4) : fg)
                    )
                VStack(spacing: 1) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(disabled ? theme.main.opacity(0.4) : theme.deep)
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.main.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    // MARK: - Computed
    private var pngCount: Int { files.filter { $0.kind == .png }.count }

    // MARK: - Handlers
    private func saveAllPNGs() {
        let imageURLs = files.filter { $0.kind == .png }.map(\.url)
        guard !imageURLs.isEmpty else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    onToast(zh ? "请先允许访问相册 📷" : "Please allow photo access 📷")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                for url in imageURLs {
                    if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        PHAssetChangeRequest.creationRequestForAsset(from: img)
                    }
                }
            }, completionHandler: { ok, _ in
                DispatchQueue.main.async {
                    if ok {
                        let n = imageURLs.count
                        onToast(zh ? "已保存 \(n) 张 🖼" : "Saved \(n) image(s) 🖼")
                    } else {
                        onToast(zh ? "保存失败 · 再试一次?" : "Save failed — try again?")
                    }
                }
            })
        }
    }

    private func copyFirstPNG() {
        guard let pngURL = files.first(where: { $0.kind == .png })?.url,
              let data = try? Data(contentsOf: pngURL),
              let img = UIImage(data: data) else { return }
        UIPasteboard.general.image = img
        onToast(zh ? "图片已复制 📋" : "Image copied 📋")
    }
}

// =========================================================
// Mail compose wrapper
// =========================================================
private struct MailComposeView: UIViewControllerRepresentable {
    let files: [ExportedFile]
    let subject: String
    let body: String
    let onComplete: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        for f in files {
            if let data = try? Data(contentsOf: f.url) {
                let mime: String = {
                    switch f.kind {
                    case .json: return "application/json"
                    case .png:  return "image/png"
                    case .pdf:  return "application/pdf"
                    }
                }()
                vc.addAttachmentData(data, mimeType: mime, fileName: f.displayName)
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        init(_ parent: MailComposeView) { self.parent = parent }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            parent.onComplete(result == .sent)
            parent.dismiss()
        }
    }
}

// =========================================================
// Multi-file activity sheet (for "更多")
// =========================================================
private struct ActivitySheetURLs: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
