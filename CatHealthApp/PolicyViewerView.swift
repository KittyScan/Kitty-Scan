import SwiftUI

struct PolicyViewerView: View {
    let doc: PolicyDoc
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var themeProvider
    @Environment(LanguageManager.self) private var lang

    private var theme: CatTheme { themeProvider.theme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(doc.title)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(theme.deep)
                        Text(lang.isChineseSelected
                             ? "生效日期:\(doc.effectiveDate)"
                             : "Effective date: \(doc.effectiveDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Sections
                    ForEach(doc.sections, id: \.number) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(section.number). \(section.heading)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(theme.deep)

                            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                                block.view(theme: theme)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.isChineseSelected ? "关闭" : "Close") { dismiss() }
                }
            }
        }
    }
}

private extension PolicyDoc.Block {
    @ViewBuilder
    func view(theme: CatTheme) -> some View {
        switch self {
        case .paragraph(let s):
            Text(attributed(s))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(let list):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(list, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(theme.main)
                        Text(attributed(line))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 4)

        case .callout(let s):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
                Text(attributed(s))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.orange.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)

        case .link(let label, let url):
            if let u = URL(string: url) {
                Link(destination: u) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                        Text(label)
                            .font(.callout)
                            .underline()
                    }
                    .foregroundStyle(theme.deep)
                }
                .padding(.leading, 4)
            }
        }
    }

    /// Parse inline Markdown (bold / italics) safely, fall back to plain text.
    private func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(s)
    }
}
