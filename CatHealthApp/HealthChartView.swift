import SwiftUI
import Charts

/// Themed line chart for a cat's health scores over time.
/// Shows last N records with:
///   - a metric picker (total / 4 sub-dimensions) so the user can see WHICH
///     axis is dragging the score, not just the composite,
///   - a green "healthy band" at 70–90 so a single dip doesn't read as alarming,
///   - a dashed 3-point moving-average overlay so single-checkup noise is
///     visibly smoothed,
///   - a trend tag (↑/↓/→) computed against the selected metric.
struct HealthChartView: View {
    let records: [HistoryRecord]      // newest first (sorted by caller)
    let theme: CatTheme
    let zh: Bool

    private let sampleCap = 20

    enum Metric: String, CaseIterable, Identifiable {
        case total, eyes, fur, posture, energy
        var id: String { rawValue }

        func label(zh: Bool) -> String {
            switch self {
            case .total:   return zh ? "总分"   : "Total"
            case .eyes:    return zh ? "眼睛"   : "Eyes"
            case .fur:     return zh ? "毛发"   : "Fur"
            case .posture: return zh ? "体态"   : "Posture"
            case .energy:  return zh ? "精神"   : "Energy"
            }
        }

        func value(in r: HistoryRecord) -> Int? {
            switch self {
            case .total:   return r.healthScore
            case .eyes:    return r.eyesScore
            case .fur:     return r.furScore
            case .posture: return r.postureScore
            case .energy:  return r.energyScore
            }
        }
    }

    @State private var metric: Metric = .total

    private var chronological: [HistoryRecord] {
        Array(records.prefix(sampleCap).reversed())
    }

    /// Records the picked metric has data for, paired with the value.
    /// Sub-score columns are nil for records logged before that schema existed,
    /// so we filter rather than impute.
    private var points: [(record: HistoryRecord, value: Int)] {
        chronological.compactMap { r in
            metric.value(in: r).map { (r, $0) }
        }
    }

    /// Centered 3-point moving average. Endpoints fall back to 2-point partial
    /// windows so the line still extends to both edges of the chart.
    private var movingAverage: [(date: Date, value: Double)] {
        guard points.count >= 3 else { return [] }
        var out: [(Date, Double)] = []
        for i in points.indices {
            let lo = max(0, i - 1), hi = min(points.count - 1, i + 1)
            let window = points[lo...hi].map { Double($0.value) }
            let avg = window.reduce(0, +) / Double(window.count)
            out.append((points[i].record.date, avg))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            metricPicker
            if points.count >= 2 {
                chart
            } else {
                emptyState
            }
        }
        .padding(14)
        .background(theme.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.light.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(zh ? "健康分数趋势" : "Health trend")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.deep)
            Spacer()
            if let trend = computeTrend() {
                Text(trend.label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(trend.color.opacity(0.15)))
                    .foregroundStyle(trend.color)
            }
        }
    }

    // MARK: - Metric picker

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Metric.allCases) { m in
                    let active = (m == metric)
                    Button {
                        metric = m
                    } label: {
                        Text(m.label(zh: zh))
                            .font(.caption.weight(active ? .semibold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                Capsule().fill(active ? theme.deep : theme.card)
                            )
                            .foregroundStyle(active ? theme.bg : theme.deep)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            // Reference band — visually anchors "healthy" so a single 65 doesn't
            // look catastrophic. Drawn first so the line/points sit on top.
            if let first = points.first?.record.date,
               let last  = points.last?.record.date {
                RectangleMark(
                    xStart: .value("start", first),
                    xEnd:   .value("end",   last),
                    yStart: .value("low",  70),
                    yEnd:   .value("high", 90)
                )
                .foregroundStyle(Color.green.opacity(0.10))
            }

            ForEach(points, id: \.record.id) { pt in
                AreaMark(
                    x: .value("date", pt.record.date),
                    y: .value("score", pt.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [theme.main.opacity(0.45), theme.main.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("date", pt.record.date),
                    y: .value("score", pt.value)
                )
                .foregroundStyle(theme.deep)
                .lineStyle(StrokeStyle(lineWidth: 2.2))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("date", pt.record.date),
                    y: .value("score", pt.value)
                )
                .foregroundStyle(scoreColor(for: pt.value))
                .symbolSize(64)
            }

            // Moving average — dashed grey line; only meaningful with 3+ points
            ForEach(Array(movingAverage.enumerated()), id: \.offset) { _, ma in
                LineMark(
                    x: .value("date",  ma.date),
                    y: .value("avg",   ma.value),
                    series: .value("series", "ma")
                )
                .foregroundStyle(theme.deep.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                .interpolationMethod(.catmullRom)
            }
        }
        .frame(height: 180)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { _ in
                AxisGridLine().foregroundStyle(theme.light.opacity(0.4))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(theme.main.opacity(0.6))
            }
        }
        .chartXAxis {
            let stride = max(1, points.count / 4)
            AxisMarks(values: .stride(by: .day, count: stride * xStrideDays)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(theme.main.opacity(0.6))
            }
        }
    }

    private var xStrideDays: Int {
        guard let first = points.first?.record.date,
              let last  = points.last?.record.date else { return 1 }
        let days = Int(last.timeIntervalSince(first) / 86_400)
        if days < 14 { return 1 }
        if days < 60 { return 3 }
        if days < 180 { return 7 }
        return 14
    }

    // MARK: - Empty

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(theme.main.opacity(0.5))
            Text(emptyText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    /// Three-way empty message:
    ///   - Total view + no records: brand-new user, encourage scanning.
    ///   - Sub-score view + no records: same as above (just clearer copy).
    ///   - Sub-score view + records exist but none have this data: explain
    ///     this is a *new* feature and the data unlocks on the next analysis.
    ///   - One data point exists for this metric: encourage one more scan.
    private var emptyText: String {
        let hasAnyRecord = !chronological.isEmpty
        let hasMetricData = !points.isEmpty
        switch (metric, hasAnyRecord, hasMetricData) {
        case (.total, false, _):
            return zh ? "多检测几次就能看到趋势" : "Scan a few more times to see the trend"
        case (.total, true, _):
            return zh ? "再来一次,就能画出趋势线了" : "One more scan and we'll have a trend"
        case (_, false, _):
            return zh ? "先做几次检测,这里就能看到分项趋势" : "Run a few scans to see per-axis trends"
        case (_, true, false):
            return zh ? "这是新加的分项指标,做一次新检测就能解锁这条线" : "This axis is new — run a fresh scan to unlock this line"
        case (_, true, true):
            return zh ? "再做一次检测就能看趋势了" : "One more scan and we'll have a trend"
        }
    }

    // MARK: - Helpers

    private func scoreColor(for score: Int) -> Color {
        ScoreBand(score: score).color
    }

    private func computeTrend() -> (label: String, color: Color)? {
        guard points.count >= 2,
              let first = points.first,
              let last  = points.last else { return nil }
        let diff = last.value - first.value
        if diff >= 5 {
            return (zh ? "↑ 上升 \(diff)" : "↑ Up \(diff)", .green)
        } else if diff <= -5 {
            return (zh ? "↓ 下降 \(abs(diff))" : "↓ Down \(abs(diff))", .red)
        } else {
            return (zh ? "→ 稳定" : "→ Stable", .orange)
        }
    }
}
