import SwiftUI
import SwiftData

/// Pre-export configuration sheet. Shown when user taps "Export my data".
/// On confirm, calls back with the chosen `ExportConfig` so the caller
/// can launch `ExportFlowView`.
struct ExportConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(ThemeProvider.self) private var themeProvider
    @Query(sort: \Cat.createdAt) private var cats: [Cat]

    @State private var config = ExportConfig()
    @State private var submitted = false
    let onConfirm: (ExportConfig) -> Void
    /// When provided, the Cancel toolbar button calls this instead of `dismiss()`.
    /// Useful when embedded inside another fullScreenCover so cancel closes
    /// the whole flow instead of just this subview.
    var onCancel: (() -> Void)? = nil

    private var zh: Bool { lang.isChineseSelected }
    private var theme: CatTheme { themeProvider.theme }

    private var selectedCount: Int {
        config.catIds.isEmpty ? cats.count : config.catIds.count
    }

    private var estimatedFileCount: Int {
        var n = 0
        if config.includeCards { n += selectedCount }
        if config.includePDFs { n += selectedCount }
        return n
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    // --- Cats ---
                    sectionHeader(zh ? "选择猫咪" : "Cats",
                                  badge: "\(selectedCount) / \(cats.count)")

                    VStack(spacing: 8) {
                        if cats.count > 1 {
                            Button {
                                if config.catIds.isEmpty {
                                    // Currently "all" selected -> deselect all explicitly
                                    config.catIds = [cats.first?.id].compactMap { $0 }.reduce(into: Set<UUID>()) { $0.insert($1) }
                                } else {
                                    config.catIds = []
                                }
                            } label: {
                                HStack {
                                    Text(zh ? "全选" : "Select all")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(theme.deep)
                                    Spacer()
                                    Image(systemName: config.catIds.isEmpty ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(config.catIds.isEmpty ? theme.deep : theme.main.opacity(0.5))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(config.catIds.isEmpty ? theme.card : theme.bg))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(theme.light.opacity(0.6), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(cats) { cat in
                            catPickerRow(cat: cat)
                        }
                    }

                    // --- Date range ---
                    sectionHeader(zh ? "时间范围" : "Date range")
                    dateRangeSegmented

                    // --- File types ---
                    sectionHeader(zh ? "包含文件" : "Include")

                    VStack(spacing: 8) {
                        toggleRow(
                            icon: "photo",
                            title: zh ? "PNG 档案卡" : "PNG profile cards",
                            subtitle: zh ? "每只猫 1 张 1080×1350 海报" : "1 poster per cat",
                            count: config.includeCards ? selectedCount : nil,
                            on: $config.includeCards
                        )
                        toggleRow(
                            icon: "doc.text",
                            title: zh ? "PDF 健康档案" : "PDF health report",
                            subtitle: zh ? "每只猫一份完整病历" : "Full per-cat dossier",
                            count: config.includePDFs ? selectedCount : nil,
                            on: $config.includePDFs
                        )
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }

            // Bottom summary + CTA
            VStack(spacing: 10) {
                HStack {
                    Text(zh ? "预计生成" : "Will produce")
                        .font(.caption).foregroundStyle(theme.main.opacity(0.8))
                    Spacer()
                    Text("\(estimatedFileCount) \(zh ? "个文件" : "files")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.deep)
                }

                Button {
                    // Guard against double-tap.
                    guard !submitted else { return }
                    submitted = true
                    onConfirm(config)
                    // Don't dismiss here — caller transitions the flow state.
                } label: {
                    Text(zh ? "开始导出 →" : "Start export →")
                        .font(.headline)
                        .foregroundStyle(theme.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canExport ? theme.deep : theme.deep.opacity(0.35))
                        )
                        .shadow(color: canExport ? theme.deep.opacity(0.25) : .clear,
                                radius: 8, y: 3)
                }
                .disabled(!canExport)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .padding(.top, 10)
            .background(theme.bg.shadow(color: .black.opacity(0.04), radius: 6, y: -2))

            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(zh ? "导出档案" : "Export archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(zh ? "取消" : "Cancel") {
                        if let onCancel { onCancel() } else { dismiss() }
                    }
                }
            }
        }
    }

    private var canExport: Bool {
        // Empty catIds means "all cats selected" by convention.
        // So as long as there are cats and at least one file type is on, we can export.
        !cats.isEmpty && (config.includeCards || config.includePDFs)
    }

    // MARK: - Components

    private func sectionHeader(_ title: String, badge: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.deep)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(theme.main)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(theme.card))
            }
        }
        .padding(.top, 6)
    }

    private func catPickerRow(cat: Cat) -> some View {
        let ct = CatThemes.byId(cat.breedId) ?? theme
        let isChecked = config.catIds.isEmpty ? true : config.catIds.contains(cat.id)

        return Button {
            // First tap on any individual cat while in "all" mode -> switch to explicit selection
            if config.catIds.isEmpty {
                config.catIds = Set(cats.map { $0.id })
            }
            if config.catIds.contains(cat.id) {
                config.catIds.remove(cat.id)
            } else {
                config.catIds.insert(cat.id)
            }
            // If back to every cat selected, simplify to "empty = all" representation
            if config.catIds == Set(cats.map { $0.id }) { config.catIds = [] }
        } label: {
            HStack(spacing: 12) {
                CatAvatar(theme: ct, avatarData: cat.avatarData, size: 42, showRing: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.deep)
                    HStack(spacing: 4) {
                        if let breed = cat.breed {
                            Text(breed).font(.caption).foregroundStyle(theme.main.opacity(0.75))
                        }
                        Text("·").font(.caption).foregroundStyle(theme.main.opacity(0.4))
                        Text("\(cat.records.count) \(zh ? "条记录" : "records")")
                            .font(.caption).foregroundStyle(theme.main.opacity(0.75))
                    }
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isChecked ? theme.deep : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(isChecked ? theme.deep : theme.main.opacity(0.4),
                                          lineWidth: 1.5))
                        .frame(width: 22, height: 22)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.bg)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(isChecked ? theme.card.opacity(0.6) : theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.light.opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var dateRangeSegmented: some View {
        HStack(spacing: 6) {
            ForEach(ExportConfig.DateRange.allCases, id: \.self) { option in
                let selected = config.dateRange == option
                Button {
                    config.dateRange = option
                } label: {
                    Text(zh ? option.labelZh() : option.labelEn())
                        .font(.footnote.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? theme.bg : theme.deep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selected ? theme.deep : theme.card)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleRow(icon: String,
                           title: String,
                           subtitle: String,
                           count: Int?,
                           on: Binding<Bool>) -> some View {
        Button {
            on.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(on.wrappedValue ? theme.deep : theme.main.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(on.wrappedValue ? theme.light.opacity(0.5) : theme.card))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.deep)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(theme.main.opacity(0.7))
                }

                Spacer()

                if let count, on.wrappedValue {
                    Text("×\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.deep)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(theme.light.opacity(0.5)))
                }

                Toggle("", isOn: on)
                    .labelsHidden()
                    .tint(theme.deep)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.light.opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
