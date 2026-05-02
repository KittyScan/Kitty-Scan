import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \HistoryRecord.date, order: .reverse) var records: [HistoryRecord]
    @Query(sort: \Cat.createdAt) var cats: [Cat]
    @Environment(\.modelContext) var modelContext
    @Environment(LanguageManager.self) var lang
    @Environment(ThemeProvider.self) var themeProvider

    @State private var filterCatId: UUID? = nil

    private var zh: Bool { lang.isChineseSelected }

    private var filteredRecords: [HistoryRecord] {
        guard let id = filterCatId else { return records }
        return records.filter { $0.cat?.id == id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if cats.count >= 2 { filterBar }
                Group {
                    if filteredRecords.isEmpty {
                        if records.isEmpty { emptyState } else { filteredEmpty }
                    } else {
                        List {
                            // Always show the chart card when there's ≥1 record.
                            // HealthChartView has its own "not enough data" empty
                            // state for the 1-record case — no external guard needed.
                            Section {
                                HealthChartView(
                                    records: filteredRecords,
                                    theme: chartTheme,
                                    zh: zh
                                )
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }

                            ForEach(filteredRecords) { record in
                                NavigationLink(destination: HistoryDetailView(record: record)) {
                                    HistoryRowView(record: record, lang: lang, theme: themeForRecord(record))
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                            .onDelete(perform: delete)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle(lang.loc("history.title"))
        }
    }

    private var chartTheme: CatTheme {
        // When a specific cat is filtered, use its theme; else the active cat's.
        if let id = filterCatId, let c = cats.first(where: { $0.id == id }) {
            return CatThemes.byId(c.breedId) ?? themeProvider.theme
        }
        return themeProvider.theme
    }

    // Per-row theme: use each record's cat's breed, fall back to current
    private func themeForRecord(_ r: HistoryRecord) -> CatTheme {
        CatThemes.byId(r.cat?.breedId) ?? themeProvider.theme
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(title: zh ? "全部" : "All",
                           active: filterCatId == nil,
                           theme: themeProvider.theme) {
                    withAnimation(.spring(response: 0.4)) { filterCatId = nil }
                }
                ForEach(cats) { c in
                    let ct = CatThemes.byId(c.breedId) ?? themeProvider.theme
                    FilterPill(title: c.name,
                               active: filterCatId == c.id,
                               theme: ct) {
                        withAnimation(.spring(response: 0.4)) { filterCatId = c.id }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        let theme = themeProvider.theme
        return VStack(spacing: 16) {
            Spacer()
            CatAvatar(theme: theme, size: 90, showRing: true).opacity(0.9)
            Text(lang.loc("history.empty.title"))
                .font(.title3).fontWeight(.semibold)
                .foregroundStyle(theme.deep)
            Text(lang.loc("history.empty.sub"))
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }

    private var filteredEmpty: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("🔎").font(.system(size: 40)).opacity(0.7)
            Text(zh ? "这只猫还没有记录喵" : "No records for this cat yet")
                .font(.subheadline).foregroundColor(.secondary)
            Button {
                withAnimation { filterCatId = nil }
            } label: {
                Text(zh ? "看看全部 →" : "See all →")
                    .font(.caption)
                    .foregroundColor(themeProvider.theme.deep)
            }
            Spacer()
        }
    }

    private func delete(at offsets: IndexSet) {
        let list = filteredRecords
        for i in offsets { modelContext.delete(list[i]) }
    }
}

private struct FilterPill: View {
    let title: String
    let active: Bool
    let theme: CatTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? theme.bg : theme.deep)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? theme.deep : theme.card)
                )
                .overlay(
                    Capsule().strokeBorder(active ? Color.clear : theme.light.opacity(0.6),
                                           lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryRowView: View {
    let record: HistoryRecord
    let lang: LanguageManager
    let theme: CatTheme

    private var scoreColor: Color {
        ScoreBand(score: record.healthScore).color
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = record.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    CatAvatar(theme: theme, size: 60, showRing: false)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.breed).font(.headline)
                HStack(spacing: 6) {
                    if let catName = record.cat?.name {
                        Text(catName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.deep)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(theme.light.opacity(0.6)))
                    }
                    Text(record.date, style: .date).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()

            ZStack {
                Circle().fill(scoreColor.opacity(0.15)).frame(width: 48, height: 48)
                VStack(spacing: 0) {
                    Text("\(record.healthScore)")
                        .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(scoreColor)
                    Text(lang.loc("history.score")).font(.system(size: 7)).foregroundColor(scoreColor.opacity(0.8))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
