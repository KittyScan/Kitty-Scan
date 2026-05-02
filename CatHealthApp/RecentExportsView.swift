import SwiftUI
import UIKit
import QuickLook

/// Browses past exports persisted under `Documents/Exports/`. Tapping a row
/// opens the file in-app via Quick Look (no jumping to Files / Books / Photos).
/// Long-press / swipe gives delete + share.
///
/// This view exists because temp-directory exports used to vanish silently
/// after the success screen; users had no in-app way back to their files.
/// Documents-directory persistence + this list closes the loop.
struct RecentExportsView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(ThemeProvider.self) private var themeProvider
    @State private var files: [URL] = []
    @State private var previewURL: URL?
    @State private var shareURL: URL?

    private var zh: Bool { lang.isChineseSelected }
    private var theme: CatTheme { themeProvider.theme }

    var body: some View {
        Group {
            if files.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(files, id: \.self) { url in
                        Button { previewURL = url } label: {
                            row(for: url)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(url: url)
                            } label: { Label(zh ? "删除" : "Delete", systemImage: "trash") }
                            Button {
                                shareURL = url
                            } label: { Label(zh ? "分享" : "Share", systemImage: "square.and.arrow.up") }
                            .tint(theme.deep)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(zh ? "历史导出" : "Recent Exports")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .fullScreenCover(item: Binding(
            get: { previewURL.map { ExportPreviewItem(url: $0) } },
            set: { previewURL = $0?.url }
        )) { item in
            QuickLookPreview(url: item.url)
        }
        .sheet(item: Binding(
            get: { shareURL.map { ExportPreviewItem(url: $0) } },
            set: { shareURL = $0?.url }
        )) { item in
            ShareSheet(items: [item.url])
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundStyle(theme.deep.opacity(0.5))
            Text(zh ? "还没有导出过文件" : "No exports yet")
                .font(.headline)
                .foregroundStyle(theme.deep)
            Text(zh
                 ? "在设置 → 导出我的数据,生成 PDF / PNG 后会出现在这里。"
                 : "Run an export from Settings → Export my data; results appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    // MARK: - Row

    private func row(for url: URL) -> some View {
        let kind = inferKind(url)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int) ?? 0
        let date = (attrs?[.modificationDate] as? Date) ?? .distantPast

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(kind.color.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: kind.icon)
                    .foregroundStyle(kind.color)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(formatDate(date)) · \(formatSize(size))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.tertiaryLabel)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func reload() {
        files = ExportStorage.listAll()
    }

    private func delete(url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    private func inferKind(_ url: URL) -> (icon: String, color: Color) {
        switch url.pathExtension.lowercased() {
        case "pdf":  return ("doc.text.fill",  Color.red)
        case "png", "jpg", "jpeg": return ("photo.fill", Color.orange)
        case "json": return ("curlybraces",    Color.gray)
        default:     return ("doc.fill",       Color.gray)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatSize(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}

private struct ExportPreviewItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private extension Color {
    static var tertiaryLabel: Color { Color(UIColor.tertiaryLabel) }
}

/// Wraps UIActivityViewController for swipe-action share. Reusing the
/// existing `URLActivitySheet` would also work but this lets us keep the
/// view standalone-self-contained.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
