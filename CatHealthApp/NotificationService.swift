import Foundation
import UserNotifications
import Observation

/// Local notification orchestration for diary events.
///
/// Architecture:
///   • Each `CatEvent` owns a deterministic set of notification identifiers
///     so we can find and cancel them when the event is edited or deleted
///     (no need to persist Apple's request ID separately).
///   • All scheduling is *additive* + idempotent: re-scheduling for an
///     event first removes its old notifications, then re-creates them.
///   • Permission is requested lazily — first time the user creates an
///     event that would trigger a reminder, we ask. Setting toggle in
///     SettingsView lets them flip it later.
///
/// Identifier scheme: "evt-<eventID>-<purpose>-<sequence>"
///   purpose:  vacc | dewormer | dose | weighIn
///   sequence: 0..N (e.g. 4 vaccine reminders at 14d/7d/3d/1d, indices 0-3)
@MainActor
@Observable
final class NotificationService {
    static let shared = NotificationService()

    /// Cached after the user grants/denies. Re-querying via getNotificationSettings
    /// is async and we want fast access when scheduling.
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - Permission

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Request permission. Returns whether we ended up with permission
    /// (handles the "user denied" branch — caller shouldn't try to schedule).
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()
        if isGranted(authorizationStatus) { return true }
        if authorizationStatus == .denied { return false }
        // .notDetermined or anything else — try to ask. iOS will silently
        // ignore if the user has globally disabled notifications.
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            print("[Notif] auth request failed:", error.localizedDescription)
            return false
        }
    }

    /// Cross-platform "is the app allowed to fire local notifications?".
    /// `.ephemeral` only exists on iOS; the explicit case match avoids
    /// macOS build breakage and keeps the call sites readable.
    private func isGranted(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional: return true
        default:
            #if os(iOS)
            if status == .ephemeral { return true }
            #endif
            return false
        }
    }

    // MARK: - Schedule for a CatEvent

    /// Schedule (or re-schedule) all notifications attached to this event.
    /// Idempotent: cancels existing notifications for the event first.
    func reschedule(for event: CatEvent) async {
        await cancelAll(for: event)
        guard isGranted(authorizationStatus) else { return }

        switch event.type {
        case .vaccine:
            await scheduleVaccineReminders(for: event)
        case .dewormer:
            await scheduleDewormerReminder(for: event)
        case .medication:
            await scheduleMedicationReminders(for: event)
        case .vetVisit, .other:
            // Single reminder at the scheduled moment, only if future.
            if event.scheduledAt > Date() {
                let name = catName(event)
                let title = zh
                    ? "📅 \(name) 的小事:\(event.title)"
                    : "\(name)'s thing today: \(event.title)"
                let body = event.notes.isEmpty
                    ? (zh ? "记得提前出门哦 🚗" : "Don't forget — head out a bit early 🚗")
                    : event.notes
                await scheduleSingle(
                    id: notifID(event: event, purpose: "appt", seq: 0),
                    title: title,
                    body: body,
                    fireAt: event.scheduledAt
                )
            }
        }
    }

    /// Cancel everything scheduled for an event. Call from `onDelete`.
    func cancelAll(for event: CatEvent) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let prefix = notifIDPrefix(eventID: event.id)
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Per-type scheduling

    /// Vaccine: 4 reminders before the due date — 14 / 7 / 3 / 1 days out.
    private func scheduleVaccineReminders(for event: CatEvent) async {
        let dueDate = event.scheduledAt
        let leadDays = [14, 7, 3, 1]
        let name = catName(event)
        for (i, days) in leadDays.enumerated() {
            guard let fire = Calendar.current.date(byAdding: .day, value: -days, to: dueDate),
                  fire > Date() else { continue }
            await scheduleSingle(
                id: notifID(event: event, purpose: "vacc", seq: i),
                title: vaccineTitle(name: name, daysAhead: days),
                body: vaccineBody(eventTitle: event.title, dueDate: dueDate, daysAhead: days),
                fireAt: fire
            )
        }
    }

    /// Dewormer: one reminder on the due date itself in the morning.
    private func scheduleDewormerReminder(for event: CatEvent) async {
        let dueDate = event.scheduledAt
        guard dueDate > Date() else { return }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: dueDate)
        comps.hour = 9
        guard let fire = cal.date(from: comps) else { return }
        let name = catName(event)
        await scheduleSingle(
            id: notifID(event: event, purpose: "dewormer", seq: 0),
            title: zh ? "🐛 该给 \(name) 驱虫啦" : "Dewormer day for \(name) 🐛",
            body: zh
                ? "9 点了,小药片走起 ฅ"
                : "9 AM — tiny tablet time ฅ",
            fireAt: fire
        )
    }

    /// Medication: one reminder per dose × course days.
    /// E.g. 2 doses × 7 days = 14 notifications. Capped at 60 reminders per
    /// event so we don't blow past iOS's per-app pending-notification limit
    /// (~64).
    private func scheduleMedicationReminders(for event: CatEvent) async {
        guard let courseDays = event.medCourseDays,
              let dailyCount = event.medDailyCount,
              !event.medTimes.isEmpty else { return }
        let name = catName(event)
        let medInfo = [event.medName, event.medDose].compactMap { $0 }.joined(separator: " · ")
        let body = medInfo.isEmpty
            ? (zh ? "把它哄过来,药片塞进去 🐾" : "Bring them over, tap to mark done 🐾")
            : medInfo
        var seq = 0
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: event.scheduledAt)
        outer: for dayOffset in 0..<courseDays {
            guard let dayBase = cal.date(byAdding: .day, value: dayOffset, to: startDay) else { continue }
            // Slight title rotation across days so the user doesn't tune it
            // out — same content, just three friendly variants.
            for timeStr in event.medTimes.prefix(dailyCount) {
                guard let fire = combine(day: dayBase, time: timeStr),
                      fire > Date() else { continue }
                let title = medicationTitle(name: name, seq: seq)
                await scheduleSingle(
                    id: notifID(event: event, purpose: "dose", seq: seq),
                    title: title,
                    body: body,
                    fireAt: fire
                )
                seq += 1
                if seq >= 60 { break outer }   // iOS cap safety
            }
        }
    }

    private func medicationTitle(name: String, seq: Int) -> String {
        if zh {
            switch seq % 3 {
            case 0:  return "💊 \(name) 等你的小药片~"
            case 1:  return "💊 \(name) 张嘴喵~"
            default: return "💊 该给 \(name) 喂药啦"
            }
        } else {
            switch seq % 3 {
            case 0:  return "💊 \(name)'s pill time~"
            case 1:  return "💊 Open up, \(name)~"
            default: return "💊 \(name) needs a dose"
            }
        }
    }

    // MARK: - Weekly weigh-in (cat-scoped, not event-scoped)

    /// Recurring Monday-9am ping to log weight. Cat-scoped so each cat has
    /// its own reminder. Idempotent — call again safely; existing ID is
    /// replaced by iOS itself when re-added.
    func scheduleWeeklyWeighIn(for cat: Cat) async {
        guard authorizationStatus == .authorized else { return }
        let id = "weekly-weighin-\(cat.id.uuidString)"
        var trigger = DateComponents()
        trigger.weekday = 2   // Monday
        trigger.hour = 9
        trigger.minute = 0
        let content = UNMutableNotificationContent()
        if zh {
            content.title = "📏 \(cat.name) 周一称重日~"
            content.body = "看看这周有没有偷偷长肉喵 ฅ"
        } else {
            content.title = "📏 \(cat.name)'s Monday weigh-in"
            content.body = "Curious if anyone got chunkier this week ฅ"
        }
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true)
        )
        try? await UNUserNotificationCenter.current().add(req)
    }

    func cancelWeeklyWeighIn(for cat: Cat) {
        let id = "weekly-weighin-\(cat.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - Internals

    private func scheduleSingle(id: String, title: String, body: String, fireAt: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(req)
        } catch {
            print("[Notif] add failed for \(id):", error.localizedDescription)
        }
    }

    private func combine(day: Date, time: String) -> Date? {
        // time = "HH:MM"
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        c.hour = parts[0]; c.minute = parts[1]
        return Calendar.current.date(from: c)
    }

    private func notifIDPrefix(eventID: UUID) -> String {
        "evt-\(eventID.uuidString)-"
    }

    private func notifID(event: CatEvent, purpose: String, seq: Int) -> String {
        "\(notifIDPrefix(eventID: event.id))\(purpose)-\(seq)"
    }

    /// Bilingual cute title for vaccine reminders. The "voice" gets warmer
    /// as the date approaches — 2 weeks out is a heads-up, day-before is a
    /// snuggle.
    private func vaccineTitle(name: String, daysAhead: Int) -> String {
        if zh {
            switch daysAhead {
            case 14: return "🩹 别忘了 \(name) 的疫苗"
            case 7:  return "🩹 \(name) 下周要打针啦"
            case 3:  return "🩹 还有 3 天哦"
            default: return "🩹 明天就是打针日啦"
            }
        } else {
            switch daysAhead {
            case 14: return "🩹 \(name)'s vaccine in 2 weeks"
            case 7:  return "🩹 \(name)'s shot next week"
            case 3:  return "🩹 \(name)'s shot in 3 days"
            default: return "🩹 Big day tomorrow!"
            }
        }
    }

    private func vaccineBody(eventTitle: String, dueDate: Date, daysAhead: Int) -> String {
        if zh {
            switch daysAhead {
            case 14: return "下下周该打了,提前安排时间 🐾"
            case 7:  return "再过 7 天,在 \(prettyDateZH(dueDate)),空出半天哦~"
            case 3:  return "记得提前预约兽医 ฅ"
            default: return "今晚多抱抱它,明天就要小针针了 ฅ"
            }
        } else {
            switch daysAhead {
            case 14: return "Block out the calendar 🐾"
            case 7:  return "On \(prettyDateEN(dueDate)) — book it in~"
            case 3:  return "Time to call the vet ฅ"
            default: return "Snuggle extra hard tonight ฅ"
            }
        }
    }

    private func prettyDateZH(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans")
        f.dateFormat = "M 月 d 日"
        return f.string(from: date)
    }

    private func prettyDateEN(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// Read the language flag fresh every call. Cheaper than wiring in a
    /// `@Environment` and lets test code flip the locale at runtime.
    private var zh: Bool { LanguageManager.shared.isChineseSelected }

    /// Cat name with a friendly fallback when the relationship hasn't loaded
    /// (e.g. the cat was just created and isn't yet associated). Empty
    /// strings would render notifications like "💊  needs a dose"
    /// which feels broken — better to fall back to a warm placeholder.
    private func catName(_ event: CatEvent) -> String {
        if let n = event.cat?.name, !n.isEmpty { return n }
        return zh ? "猫咪" : "Kitty"
    }
}
