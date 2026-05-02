import SwiftUI
import SwiftData
import UIKit   // UIImpactFeedbackGenerator for tap haptics

/// Per-cat daily diary. Layout inspired by Mìyòu / Flo:
///   - Top: cat picker + month switcher
///   - Middle: 7-column calendar grid. Each day shows the date and small
///     colored dots that summarize what was logged.
///   - Bottom: today's quick summary card.
///   - Tap any day → opens `DayLogSheet` to edit that day's record.
struct DiaryView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(ThemeProvider.self) private var themeProvider
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Cat.createdAt) private var cats: [Cat]
    @Query(sort: \DailyLog.date, order: .reverse) private var allLogs: [DailyLog]
    @Query(sort: \CatEvent.scheduledAt, order: .reverse) private var allEvents: [CatEvent]
    @Query(sort: \HistoryRecord.date, order: .reverse) private var allRecords: [HistoryRecord]

    @State private var selectedCat: Cat?
    @State private var visibleMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var sheetDate: Date?
    /// Day picked in the calendar grid — drives the events list at the bottom.
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var showAddEvent = false

    private var zh: Bool { lang.isChineseSelected }
    private var theme: CatTheme {
        if let id = selectedCat?.breedId, let t = CatThemes.byId(id) { return t }
        return themeProvider.theme
    }

    /// Logs for the active cat, indexed by the day's start-of-day Date.
    private var logsByDay: [Date: DailyLog] {
        guard let cat = selectedCat else { return [:] }
        var dict: [Date: DailyLog] = [:]
        for log in allLogs where log.cat?.id == cat.id {
            dict[log.date] = log
        }
        return dict
    }

    /// Events for the active cat, grouped by start-of-day. Multiple events
    /// can land on the same day (vaccine + meds + AI check etc.).
    private var eventsByDay: [Date: [CatEvent]] {
        guard let cat = selectedCat else { return [:] }
        var dict: [Date: [CatEvent]] = [:]
        let cal = Calendar.current
        for event in allEvents where event.cat?.id == cat.id {
            let day = cal.startOfDay(for: event.scheduledAt)
            dict[day, default: []].append(event)
        }
        return dict
    }

    /// AI analysis records for the active cat, grouped by start-of-day.
    /// Auto-linked from HistoryRecord — the user never logs these manually.
    private var recordsByDay: [Date: [HistoryRecord]] {
        guard let cat = selectedCat else { return [:] }
        var dict: [Date: [HistoryRecord]] = [:]
        let cal = Calendar.current
        for r in allRecords where r.cat?.id == cat.id {
            let day = cal.startOfDay(for: r.date)
            dict[day, default: []].append(r)
        }
        return dict
    }

    private var todayLog: DailyLog? {
        logsByDay[Calendar.current.startOfDay(for: Date())]
    }

    /// Events on the currently-picked day, sorted by time.
    private var selectedDayEvents: [CatEvent] {
        (eventsByDay[selectedDay] ?? []).sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var selectedDayRecords: [HistoryRecord] {
        (recordsByDay[selectedDay] ?? []).sorted { $0.date < $1.date }
    }

    /// Most pressing upcoming-or-today event (within the next 7 days, not
    /// already completed) for the active cat. Drives the banner above the
    /// calendar — turns the diary from a "logbook" into a "what's next"
    /// dashboard.
    private var nearestUpcoming: CatEvent? {
        guard let cat = selectedCat else { return nil }
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return allEvents
            .filter {
                $0.cat?.id == cat.id
                    && $0.completedAt == nil
                    && $0.scheduledAt >= Calendar.current.startOfDay(for: now)
                    && $0.scheduledAt <= cutoff
            }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if cats.count >= 2 { catPicker }
                    if let upcoming = nearestUpcoming { upcomingBanner(upcoming) }
                    monthSwitcher
                    calendarGrid
                    selectedDayCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .navigationTitle(zh ? "猫咪日记" : "Cat Diary")
            .background(theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // "Today" jump button — bring the visible month back
                        // to the current month and pick today as the active
                        // cell (the user often roams the calendar but wants a
                        // quick way home).
                        let now = Date()
                        visibleMonth = Calendar.current.startOfMonth(for: now)
                        selectedDay = Calendar.current.startOfDay(for: now)
                    } label: {
                        Text(zh ? "今天" : "Today")
                            .foregroundStyle(theme.deep)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            sheetDate = selectedDay
                        } label: {
                            Label(zh ? "记当天日常" : "Log routine",
                                  systemImage: "square.and.pencil")
                        }
                        Button {
                            showAddEvent = true
                        } label: {
                            Label(zh ? "添加事件" : "Add event",
                                  systemImage: "calendar.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(theme.deep)
                    }
                }
            }
        }
        .onAppear {
            if selectedCat == nil {
                selectedCat = themeProvider.activeCat(from: cats)
            }
        }
        .onChange(of: themeProvider.activeCatId) { _, _ in
            selectedCat = themeProvider.activeCat(from: cats)
        }
        .sheet(item: Binding(
            get: { sheetDate.map { DateID(date: $0) } },
            set: { sheetDate = $0?.date }
        )) { id in
            DayLogSheet(
                date: id.date,
                cat: selectedCat,
                existing: logsByDay[id.date],
                theme: theme
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddEvent) {
            EventSheet(cat: selectedCat, initialDate: selectedDay, theme: theme)
        }
    }

    // MARK: - Cat picker

    private var catPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(cats) { cat in
                    let ct = CatThemes.byId(cat.breedId) ?? theme
                    let active = selectedCat?.id == cat.id
                    Button { selectedCat = cat } label: {
                        VStack(spacing: 4) {
                            CatAvatar(theme: ct,
                                      avatarData: cat.avatarData,
                                      size: 48,
                                      showRing: active)
                            Text(cat.name)
                                .font(.caption)
                                .foregroundStyle(active ? ct.deep : .secondary)
                                .fontWeight(active ? .semibold : .regular)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Upcoming banner

    /// Tap-to-jump banner. Surfaces the next thing the owner needs to do
    /// (vaccine in 3 days, today's medication, etc.) so the calendar isn't
    /// purely a logbook — the homepage answers "what now".
    private func upcomingBanner(_ event: CatEvent) -> some View {
        let color = Color(hex: event.type.tintHex)
        let when = relativeWhen(event.scheduledAt)
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                visibleMonth = Calendar.current.startOfMonth(for: event.scheduledAt)
                selectedDay = Calendar.current.startOfDay(for: event.scheduledAt)
            }
            tap(.soft)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: 38, height: 38)
                    Image(systemName: event.type.iconSymbol).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title.isEmpty ? event.type.displayName(zh: zh) : event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.deep)
                    Text(when)
                        .font(.caption)
                        .foregroundStyle(color)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Human-friendly relative time string ("今天 09:00" / "3 天后" / "1 周后").
    /// Used by the upcoming banner and the event row in the selected-day card.
    private func relativeWhen(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date)).day ?? 0
        let timeText = timeFormatter.string(from: date)
        switch days {
        case 0:        return zh ? "今天 \(timeText)" : "Today \(timeText)"
        case 1:        return zh ? "明天 \(timeText)" : "Tomorrow \(timeText)"
        case 2...6:    return zh ? "\(days) 天后"     : "in \(days) days"
        case 7:        return zh ? "1 周后"           : "in 1 week"
        case 8...13:   return zh ? "\(days) 天后"     : "in \(days) days"
        case 14...20:  return zh ? "2 周后"           : "in 2 weeks"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
            f.dateFormat = zh ? "M 月 d 日" : "MMM d"
            return f.string(from: date)
        }
    }

    /// Lightweight haptic — small and tasteful, fired on day picks and
    /// banner taps. `.soft` is the gentlest impact available; bigger
    /// styles feel jarring for a tap-heavy view like this.
    private func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred(intensity: 0.55)
    }

    // MARK: - Month switcher

    private var monthSwitcher: some View {
        HStack {
            Button {
                visibleMonth = Calendar.current.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(theme.deep)
                    .padding(8)
            }
            Spacer()
            Text(monthLabel(visibleMonth))
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.deep)
            Spacer()
            Button {
                visibleMonth = Calendar.current.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(theme.deep)
                    .padding(8)
            }
        }
    }

    private func monthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
        f.dateFormat = zh ? "yyyy 年 M 月" : "MMMM yyyy"
        return f.string(from: date)
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        VStack(spacing: 8) {
            // Weekday header
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.main.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells
            let cells = monthGrid(for: visibleMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let date = cell {
                        dayCell(date: date)
                    } else {
                        Color.clear.frame(height: 56)
                    }
                }
            }
        }
        .padding(14)
        .background(theme.card.opacity(0.4))
        .cornerRadius(18)
        // Horizontal swipe → previous / next month. Threshold ~ 40 pt is
        // generous enough that vertical scroll on the parent ScrollView
        // doesn't accidentally trigger a month change.
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy), abs(dx) > 60 else { return }
                    let delta = dx < 0 ? 1 : -1
                    withAnimation(.easeOut(duration: 0.25)) {
                        visibleMonth = Calendar.current.date(
                            byAdding: .month, value: delta, to: visibleMonth
                        ) ?? visibleMonth
                    }
                    tap(.soft)
                }
        )
    }

    private func dayCell(date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDay)
        let log = logsByDay[date]
        let events = eventsByDay[date] ?? []
        let records = recordsByDay[date] ?? []
        let hasAnything = log != nil || !events.isEmpty || !records.isEmpty
        return Button {
            // Tap selects the day; the bottom card animates to show
            // everything that landed on it. Long-press is a future
            // affordance for quick-add — left out for v1.
            tap(.soft)
            withAnimation(.easeOut(duration: 0.18)) {
                selectedDay = Calendar.current.startOfDay(for: date)
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(isToday ? .bold : .medium))
                    .foregroundStyle(
                        isSelected ? theme.bg
                        : (isToday ? theme.deep : theme.deep)
                    )
                eventIconRow(records: records, events: events, log: log)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected ? theme.deep
                        : (isToday ? theme.light.opacity(0.6)
                           : (hasAnything ? theme.light.opacity(0.3) : Color.clear))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isToday && !isSelected ? theme.deep : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, log: log,
                                              eventCount: events.count,
                                              recordCount: records.count))
    }

    /// Row of small icons summarizing the day's events. Order: AI checks
    /// first (always-relevant context), then events ordered by type
    /// importance, then routine dots from DailyLog. Capped at 3 icons —
    /// the cell is too small for more; user taps in to see the full list.
    @ViewBuilder
    private func eventIconRow(records: [HistoryRecord],
                              events: [CatEvent],
                              log: DailyLog?) -> some View {
        // Build the slot list outside the ViewBuilder; SwiftUI's @ViewBuilder
        // doesn't accept `for` loops or mutating var declarations.
        let slots = computeIconSlots(records: records, events: events)
        HStack(spacing: 3) {
            ForEach(0..<slots.count, id: \.self) { i in
                Image(systemName: slots[i].symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(slots[i].color)
            }
            // Routine dots only when there's no event icon to show.
            if slots.isEmpty, let log {
                if log.foodCount > 0  { Circle().fill(Color.orange).frame(width: 5, height: 5) }
                if log.waterCount > 0 { Circle().fill(Color.blue).frame(width: 5, height: 5) }
                if log.hasDiscomfort  { Circle().fill(Color.red).frame(width: 5, height: 5) }
            }
        }
        .frame(height: 11)
    }

    private func computeIconSlots(records: [HistoryRecord],
                                   events: [CatEvent]) -> [(symbol: String, color: Color)] {
        var slots: [(symbol: String, color: Color)] = []
        if !records.isEmpty {
            slots.append(("camera.fill", Color.gray))
        }
        let remaining = max(0, 3 - slots.count)
        for ev in events.prefix(remaining) {
            slots.append((ev.type.iconSymbol, Color(hex: ev.type.tintHex)))
        }
        return slots
    }

    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
        // f.shortWeekdaySymbols starts with Sunday in most locales
        return f.shortWeekdaySymbols ?? ["S","M","T","W","T","F","S"]
    }

    /// Returns all date cells for the visible month, padded with nil at the
    /// front so the first day-of-month aligns with its weekday column.
    private func monthGrid(for month: Date) -> [Date?] {
        let cal = Calendar.current
        guard let monthInterval = cal.dateInterval(of: .month, for: month) else { return [] }
        let start = monthInterval.start
        let firstWeekday = cal.component(.weekday, from: start) // 1 = Sunday
        let leading = firstWeekday - 1
        let dayCount = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for i in 0..<dayCount {
            cells.append(cal.date(byAdding: .day, value: i, to: start))
        }
        return cells
    }

    private func accessibilityLabel(for date: Date, log: DailyLog?,
                                     eventCount: Int, recordCount: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
        f.dateStyle = .medium
        var parts = [f.string(from: date)]
        if let log {
            if log.foodCount > 0  { parts.append(zh ? "吃了 \(log.foodCount) 次" : "ate \(log.foodCount) times") }
            if log.waterCount > 0 { parts.append(zh ? "喝水 \(log.waterCount) 次" : "drank \(log.waterCount) times") }
            if log.hasDiscomfort  { parts.append(zh ? "不舒服" : "discomfort") }
        }
        if eventCount > 0 { parts.append(zh ? "\(eventCount) 个事件" : "\(eventCount) events") }
        if recordCount > 0 { parts.append(zh ? "\(recordCount) 次 AI 检测" : "\(recordCount) AI checks") }
        if log == nil && eventCount == 0 && recordCount == 0 {
            parts.append(zh ? "无记录" : "no entry")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Selected day card (events + routine + AI records)

    private var selectedDayCard: some View {
        let log = logsByDay[selectedDay]
        let events = selectedDayEvents
        let records = selectedDayRecords
        let isToday = Calendar.current.isDateInToday(selectedDay)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(headerTitle(isToday: isToday))
                    .font(.headline)
                    .foregroundStyle(theme.deep)
                Spacer()
                Button {
                    sheetDate = selectedDay
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                        Text(log == nil ? (zh ? "记日常" : "Log routine")
                                        : (zh ? "改日常" : "Edit routine"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.deep)
                }
            }

            // Routine summary line (food / water / discomfort)
            if let log, !log.isEmpty {
                routineRow(log: log)
            }

            // Discrete events list
            if !events.isEmpty {
                Divider()
                ForEach(events) { ev in
                    eventRow(ev)
                }
            }

            // Auto-linked AI records
            if !records.isEmpty {
                Divider()
                ForEach(records) { rec in
                    recordRow(rec)
                }
            }

            if log == nil && events.isEmpty && records.isEmpty {
                emptyDayState(isToday: isToday)
            }
        }
        .padding(14)
        .background(theme.bg)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.light.opacity(0.5), lineWidth: 0.5))
    }

    private func headerTitle(isToday: Bool) -> String {
        if isToday { return zh ? "今天" : "Today" }
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
        f.dateFormat = zh ? "M 月 d 日" : "MMM d"
        return f.string(from: selectedDay)
    }

    private func routineRow(log: DailyLog) -> some View {
        HStack(spacing: 16) {
            summaryStat(icon: "fork.knife", color: .orange,
                        value: "\(log.foodCount)",
                        label: zh ? "次饭" : "meals")
            summaryStat(icon: "drop.fill", color: .blue,
                        value: "\(log.waterCount)",
                        label: zh ? "次水" : "water")
            summaryStat(icon: log.hasDiscomfort ? "exclamationmark.circle.fill" : "checkmark.circle",
                        color: log.hasDiscomfort ? .red : .green,
                        value: log.hasDiscomfort ? (zh ? "有" : "Yes") : (zh ? "无" : "No"),
                        label: zh ? "不适" : "issues")
        }
    }

    @ViewBuilder
    private func eventRow(_ ev: CatEvent) -> some View {
        eventRowBody(ev)
            .contextMenu {
                Button {
                    if ev.completedAt == nil {
                        ev.completedAt = Date()
                    } else {
                        ev.completedAt = nil
                    }
                } label: {
                    Label(ev.completedAt == nil
                          ? (zh ? "标记完成" : "Mark done")
                          : (zh ? "标记未完成" : "Mark undone"),
                          systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    Task { await NotificationService.shared.cancelAll(for: ev) }
                    modelContext.delete(ev)
                } label: {
                    Label(zh ? "删除事件" : "Delete event", systemImage: "trash")
                }
            }
    }

    private func eventRowBody(_ ev: CatEvent) -> some View {
        let t = ev.type
        let color = Color(hex: t.tintHex)
        let isCompleted = ev.completedAt != nil
        let isFuture = ev.scheduledAt > Date() && !isCompleted
        // Today-and-future events use relative wording; past events keep raw
        // time so they read like a logbook ("yesterday at 14:00" is verbose
        // for past entries, just show 14:00).
        let whenText: String = {
            if isCompleted { return timeFormatter.string(from: ev.scheduledAt) }
            return isFuture ? relativeWhen(ev.scheduledAt)
                            : timeFormatter.string(from: ev.scheduledAt)
        }()
        let titleText = ev.title.isEmpty ? t.displayName(zh: zh) : ev.title
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.gray.opacity(0.15)
                                      : color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: isCompleted ? "checkmark" : t.iconSymbol)
                    .foregroundStyle(isCompleted ? Color.secondary : color)
                    .font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(isCompleted, color: .secondary)
                        .foregroundStyle(isCompleted ? .secondary : theme.deep)
                    Spacer()
                    Text(whenText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !ev.notes.isEmpty {
                    Text(ev.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if isFuture {
                    Text(zh ? "待办" : "Upcoming")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(color.opacity(0.15)))
                } else if isCompleted {
                    Text(zh ? "已完成" : "Done")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                }
            }
        }
        .opacity(isCompleted ? 0.7 : 1.0)
    }

    /// Friendlier blank-state — replaces the bare gray text we had before.
    /// Themed avatar + a soft prompt makes the card feel inhabited even
    /// when there's nothing to show, which we hope nudges the user to
    /// keep the streak going.
    private func emptyDayState(isToday: Bool) -> some View {
        VStack(spacing: 10) {
            CatAvatar(theme: theme, size: 72, showRing: false)
                .opacity(0.85)
            Text(isToday
                 ? (zh ? "今天还是空白页 ฅ" : "Today's still a blank page ฅ")
                 : (zh ? "这天没记录什么" : "Nothing on this day"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.deep)
            Text(isToday
                 ? (zh ? "右上角 + 号加事件,或者点 \"记日常\" 打卡今天" : "Tap + to add something, or log today's routine")
                 : (zh ? "可以补一笔回忆下当天的状态" : "Add a memory for this day"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func recordRow(_ rec: HistoryRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.gray.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: "camera.fill").foregroundStyle(.gray)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(zh ? "AI 健康检测" : "AI health check")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.deep)
                Text(rec.summary ?? rec.personality)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text("\(rec.healthScore)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(ScoreBand(score: rec.healthScore).color)
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
        f.timeStyle = .short
        return f
    }

    private func summaryStat(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(theme.deep)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(theme.card.opacity(0.5))
        .cornerRadius(10)
    }
}

// Identifiable wrapper so we can drive `.sheet(item:)` from a Date.
private struct DateID: Identifiable {
    let date: Date
    var id: Date { date }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
