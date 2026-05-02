import SwiftUI
import SwiftData
import PhotosUI

/// Form for creating a new `CatEvent`. Top tabs let the user pick the event
/// type, then a type-specific form drops in below. Smart defaults populate
/// "next due" dates based on the type's `defaultNextDueDays` so the user
/// rarely needs to touch the calendar picker.
struct EventSheet: View {
    let cat: Cat?
    let initialDate: Date
    let theme: CatTheme

    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(\.modelContext) private var modelContext

    @State private var type: EventType = .vaccine
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var scheduledAt: Date

    // Vaccine
    @State private var vaccineKind: VaccineKind = .fvrcp
    @State private var lastVaccineDate: Date = Date()

    // Dewormer
    @State private var dewormerKind: DewormerKind = .both

    // Medication
    @State private var medName: String = ""
    @State private var medDose: String = ""
    @State private var medCourseDays: Int = 7
    @State private var medDailyCount: Int = 2
    @State private var medFirstTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()

    // Vet visit
    @State private var vetClinic: String = ""
    @State private var vetDoctor: String = ""
    @State private var vetComplaint: String = ""
    @State private var vetDiagnosis: String = ""
    @State private var vetCostText: String = ""
    @State private var vetReceiptItem: PhotosPickerItem?
    @State private var vetReceiptData: Data?

    private var zh: Bool { lang.isChineseSelected }

    init(cat: Cat?, initialDate: Date, theme: CatTheme) {
        self.cat = cat
        self.initialDate = initialDate
        self.theme = theme
        // Default scheduled time = picked day at 09:00
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: initialDate)
        comps.hour = 9
        _scheduledAt = State(initialValue: cal.date(from: comps) ?? initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Type picker (segmented-ish chip row)
                Section {
                    typePicker
                } header: {
                    Text(zh ? "事件类型" : "Event Type")
                }

                // Common: title + scheduled date + notes
                Section {
                    TextField(titlePlaceholder, text: $title)
                    DatePicker(zh ? "时间" : "When",
                               selection: $scheduledAt,
                               displayedComponents: scheduledComponents)
                } header: {
                    Text(zh ? "基础信息" : "Basics")
                }

                // Type-specific fields
                switch type {
                case .vaccine:    vaccineFields
                case .dewormer:   dewormerFields
                case .medication: medicationFields
                case .vetVisit:   vetVisitFields
                case .other:      EmptyView()
                }

                // Free-text notes (always)
                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes).frame(minHeight: 90)
                        if notes.isEmpty {
                            Text(zh ? "可填:剂量、副作用、医生说的话..."
                                    : "Optional: dose, side effects, what the vet said...")
                                .font(.body)
                                .foregroundStyle(.secondary.opacity(0.6))
                                .padding(.top, 8).padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
                } header: {
                    Text(zh ? "备注" : "Notes")
                }
            }
            .navigationTitle(zh ? "新事件" : "New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(zh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(zh ? "保存" : "Save") { save(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .tint(theme.deep)
        }
        .onChange(of: type) { _, newType in
            applyDefaultsForType(newType)
        }
        .onChange(of: lastVaccineDate) { _, _ in
            // Whenever the user changes the "last shot" date, recompute the
            // "next due" suggestion based on the vaccine kind's interval.
            if type == .vaccine {
                let interval = vaccineKind.defaultIntervalDays
                if let next = Calendar.current.date(byAdding: .day, value: interval, to: lastVaccineDate) {
                    scheduledAt = next
                }
            }
        }
        .onChange(of: vaccineReceiptPhotoChanged) { _, _ in
            // PhotosPicker async load
            if let item = vetReceiptItem {
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run { vetReceiptData = data }
                    }
                }
            }
        }
    }

    private var vaccineReceiptPhotoChanged: PhotosPickerItem? {
        // SwiftUI requires a stable type for onChange; use the binding directly.
        vetReceiptItem
    }

    // MARK: - Type picker

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EventType.allCases, id: \.self) { t in
                    typeChip(t)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    /// Pulled into its own builder because inline ternaries in nested
    /// SwiftUI modifiers blow Swift's type-check time budget (Xcode reports
    /// "unable to type-check in reasonable time" once you stack 4+).
    private func typeChip(_ t: EventType) -> some View {
        let active = (t == type)
        let bgColor: Color = active ? Color(hex: t.tintHex) : theme.card
        let fgColor: Color = active ? Color.white : theme.deep
        let weight: Font.Weight = active ? .semibold : .regular
        return Button {
            type = t
        } label: {
            HStack(spacing: 6) {
                Image(systemName: t.iconSymbol).font(.subheadline)
                Text(t.displayName(zh: zh)).font(.subheadline.weight(weight))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(bgColor))
            .foregroundStyle(fgColor)
        }
        .buttonStyle(.plain)
    }

    private var titlePlaceholder: String {
        switch type {
        case .vaccine:    return zh ? "标题(可选,例:春季加强针)"   : "Title (e.g. Spring booster)"
        case .dewormer:   return zh ? "标题(可选)"                 : "Title (optional)"
        case .medication: return zh ? "处方名(必填)"               : "Prescription title"
        case .vetVisit:   return zh ? "就诊主题(可选)"             : "Visit reason (optional)"
        case .other:      return zh ? "标题"                       : "Title"
        }
    }

    private var scheduledComponents: DatePickerComponents {
        switch type {
        case .medication: return [.date, .hourAndMinute]
        case .vaccine, .dewormer, .other: return [.date]
        case .vetVisit:   return [.date, .hourAndMinute]
        }
    }

    // MARK: - Vaccine fields

    private var vaccineFields: some View {
        Section {
            Picker(zh ? "疫苗类型" : "Vaccine type", selection: $vaccineKind) {
                ForEach(VaccineKind.allCases, id: \.self) { k in
                    Text(k.displayName(zh: zh)).tag(k)
                }
            }
            DatePicker(zh ? "上次接种" : "Last given",
                       selection: $lastVaccineDate,
                       displayedComponents: [.date])
        } header: {
            Text(zh ? "疫苗信息" : "Vaccine details")
        } footer: {
            Text(zh
                 ? "下次到期已根据疫苗类型自动算好(\(vaccineKind.defaultIntervalDays / 30) 个月后),可在上方时间里手动调。"
                 : "Next-due auto-calculated (\(vaccineKind.defaultIntervalDays / 30) months later); adjust above if needed.")
        }
    }

    // MARK: - Dewormer fields

    private var dewormerFields: some View {
        Section {
            Picker(zh ? "驱虫类型" : "Dewormer type", selection: $dewormerKind) {
                ForEach(DewormerKind.allCases, id: \.self) { k in
                    Text(k.displayName(zh: zh)).tag(k)
                }
            }
        } header: {
            Text(zh ? "驱虫" : "Dewormer")
        } footer: {
            Text(zh ? "建议每月一次。" : "Monthly cadence recommended.")
        }
    }

    // MARK: - Medication fields

    private var medicationFields: some View {
        Section {
            TextField(zh ? "药名(例:阿莫西林)" : "Drug name", text: $medName)
            TextField(zh ? "剂量(例:5mg)" : "Dose", text: $medDose)
            Stepper(value: $medCourseDays, in: 1...30) {
                Text(zh ? "疗程:\(medCourseDays) 天" : "Course: \(medCourseDays) days")
            }
            Picker(zh ? "每日次数" : "Times per day", selection: $medDailyCount) {
                Text(zh ? "1 次/天" : "Once").tag(1)
                Text(zh ? "2 次/天" : "Twice").tag(2)
                Text(zh ? "3 次/天" : "Three times").tag(3)
            }
            DatePicker(zh ? "首次时间" : "First dose time",
                       selection: $medFirstTime,
                       displayedComponents: [.hourAndMinute])
        } header: {
            Text(zh ? "用药信息" : "Medication")
        } footer: {
            Text(zh
                 ? "我们会在每天 \(timeString(medFirstTime)) 提醒你,持续 \(medCourseDays) 天。\(medDailyCount > 1 ? "其他给药时间会自动间隔分配。" : "")"
                 : "We'll remind you at \(timeString(medFirstTime)) daily for \(medCourseDays) days.\(medDailyCount > 1 ? " Additional doses spaced automatically." : "")")
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
        f.timeStyle = .short
        return f.string(from: d)
    }

    // MARK: - Vet visit fields

    private var vetVisitFields: some View {
        Section {
            TextField(zh ? "医院名称" : "Clinic", text: $vetClinic)
            TextField(zh ? "医生姓名(可选)" : "Doctor (optional)", text: $vetDoctor)
            TextField(zh ? "主诉(为什么去)" : "Complaint", text: $vetComplaint)
            TextField(zh ? "诊断结果" : "Diagnosis", text: $vetDiagnosis)
            HStack {
                Text(zh ? "费用" : "Cost")
                Spacer()
                TextField(zh ? "可不填" : "optional", text: $vetCostText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }
            PhotosPicker(selection: $vetReceiptItem, matching: .images) {
                HStack {
                    Image(systemName: "photo")
                    Text(vetReceiptData == nil
                         ? (zh ? "上传处方/收据照片" : "Add prescription photo")
                         : (zh ? "已选好照片(点击换)" : "Photo selected (tap to change)"))
                }
                .foregroundStyle(theme.deep)
            }
        } header: {
            Text(zh ? "就诊信息" : "Visit details")
        }
    }

    // MARK: - Defaults

    /// When user taps a different type, reset state pertinent only to other
    /// types and pre-populate sensible defaults for the new one. We do NOT
    /// clear `notes` / `title` — those carry over so a quick type-change
    /// doesn't lose what the user already typed.
    private func applyDefaultsForType(_ newType: EventType) {
        switch newType {
        case .vaccine:
            // Default "next due" = today + 12 months
            if let next = Calendar.current.date(byAdding: .day,
                                                value: vaccineKind.defaultIntervalDays,
                                                to: Date()) {
                scheduledAt = next
            }
        case .dewormer:
            if let next = Calendar.current.date(byAdding: .day, value: 30, to: Date()) {
                scheduledAt = next
            }
        case .medication:
            scheduledAt = medFirstTime
        case .vetVisit, .other:
            // Keep whatever date the user originally tapped; it's typically
            // "today" or the day they're logging retroactively.
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: initialDate)
            comps.hour = 9
            scheduledAt = cal.date(from: comps) ?? initialDate
        }
    }

    // MARK: - Save

    private func save() {
        let event = CatEvent(
            type: type,
            scheduledAt: scheduledAt,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            cat: cat
        )

        switch type {
        case .vaccine:
            event.vaccineKindRaw = vaccineKind.rawValue
            if event.title.isEmpty {
                event.title = vaccineKind.displayName(zh: zh)
            }
        case .dewormer:
            event.dewormerKindRaw = dewormerKind.rawValue
            if event.title.isEmpty {
                event.title = dewormerKind.displayName(zh: zh)
            }
        case .medication:
            event.medName = medName.isEmpty ? nil : medName
            event.medDose = medDose.isEmpty ? nil : medDose
            event.medCourseDays = medCourseDays
            event.medDailyCount = medDailyCount
            event.medTimes = expandedDoseTimes()
            if event.title.isEmpty { event.title = medName.isEmpty
                ? EventType.medication.displayName(zh: zh)
                : medName
            }
        case .vetVisit:
            event.vetClinic = vetClinic.isEmpty ? nil : vetClinic
            event.vetDoctor = vetDoctor.isEmpty ? nil : vetDoctor
            event.vetComplaint = vetComplaint.isEmpty ? nil : vetComplaint
            event.vetDiagnosis = vetDiagnosis.isEmpty ? nil : vetDiagnosis
            event.vetReceiptImage = vetReceiptData
            if let cost = parseCost(vetCostText) { event.vetCostCents = cost }
            if event.title.isEmpty {
                event.title = vetClinic.isEmpty
                    ? EventType.vetVisit.displayName(zh: zh)
                    : vetClinic
            }
        case .other:
            if event.title.isEmpty { event.title = EventType.other.displayName(zh: zh) }
        }

        modelContext.insert(event)

        // Fire-and-forget: ask permission if needed (lazy, only on first
        // event save) and schedule the type-appropriate notifications.
        // Doesn't block the UI — if the user denies, `reschedule` no-ops.
        Task {
            _ = await NotificationService.shared.requestPermissionIfNeeded()
            await NotificationService.shared.reschedule(for: event)
        }
    }

    /// Convert "first dose at 08:00, 2/day" → ["08:00", "20:00"].
    /// Even spacing across the 12-hour wake window simplifies UX without
    /// medical-rule complexity (every-Nh dosing is far less common at home).
    private func expandedDoseTimes() -> [String] {
        guard medDailyCount >= 1 else { return [] }
        let cal = Calendar.current
        var comps = cal.dateComponents([.hour, .minute], from: medFirstTime)
        let firstHour = comps.hour ?? 8
        let firstMin = comps.minute ?? 0
        let totalSpan = 12   // distribute doses across a 12-hour daytime window
        let step = medDailyCount > 1 ? totalSpan / (medDailyCount - 1) : 0
        var out: [String] = []
        for i in 0..<medDailyCount {
            let hour = (firstHour + step * i) % 24
            out.append(String(format: "%02d:%02d", hour, firstMin))
            _ = comps
        }
        return out
    }

    /// Cost field accepts plain decimal entry like "238.50". Stored in cents
    /// to avoid Double precision drift on the ledger.
    private func parseCost(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard let val = Double(trimmed) else { return nil }
        return Int((val * 100).rounded())
    }
}
