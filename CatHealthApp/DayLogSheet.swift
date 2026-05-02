import SwiftUI
import SwiftData

/// Edit one day's log for one cat. Auto-saves on dismiss; if the user
/// leaves everything empty we delete the record so the calendar dot doesn't
/// linger.
struct DayLogSheet: View {
    let date: Date
    let cat: Cat?
    let existing: DailyLog?
    let theme: CatTheme

    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(\.modelContext) private var modelContext

    @State private var foodCount: Int = 0
    @State private var waterCount: Int = 0
    @State private var hasDiscomfort: Bool = false
    @State private var moodScore: Int = 3
    @State private var moodSet: Bool = false
    @State private var weightText: String = ""
    @State private var notes: String = ""

    private var zh: Bool { lang.isChineseSelected }

    var body: some View {
        NavigationStack {
            Form {
                // ---- Food / water (steppers with custom +/- buttons) ----
                Section {
                    counterRow(icon: "fork.knife", color: .orange,
                               title: zh ? "吃饭次数" : "Meals",
                               value: $foodCount, max: 12)
                    counterRow(icon: "drop.fill", color: .blue,
                               title: zh ? "喝水次数" : "Water",
                               value: $waterCount, max: 20)
                } header: {
                    Text(zh ? "今天的基本记录" : "Routine")
                }

                // ---- Mood ----
                Section {
                    HStack {
                        Text(zh ? "精神" : "Mood")
                            .foregroundStyle(theme.deep)
                        Spacer()
                        ForEach(1...5, id: \.self) { i in
                            Button {
                                moodScore = i
                                moodSet = true
                            } label: {
                                Image(systemName: i <= moodScore && moodSet ? "star.fill" : "star")
                                    .foregroundStyle(moodSet ? theme.deep : .secondary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                        if moodSet {
                            Button {
                                moodSet = false
                                moodScore = 3
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Text(zh ? "体重" : "Weight")
                            .foregroundStyle(theme.deep)
                        Spacer()
                        TextField(zh ? "可不填(克)" : "Optional (g)", text: $weightText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                }

                // ---- Discomfort + free notes ----
                Section {
                    Toggle(isOn: $hasDiscomfort) {
                        Label {
                            Text(zh ? "今天感觉不太对" : "Something off today")
                                .foregroundStyle(theme.deep)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .tint(.red)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes)
                            .frame(minHeight: 100)
                        if notes.isEmpty {
                            Text(zh
                                 ? "比如:吐了一次、便便有点稀、不爱搭理人..."
                                 : "e.g. vomited once, soft stool, hiding more than usual...")
                                .font(.body)
                                .foregroundStyle(.secondary.opacity(0.6))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
                } header: {
                    Text(zh ? "异常或备注" : "Notes")
                }

                // ---- Delete (only when editing existing) ----
                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            if let log = existing {
                                modelContext.delete(log)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text(zh ? "删除这一天的记录" : "Delete this entry")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(headerDate)
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
        }
        .onAppear { loadFromExisting() }
        .tint(theme.deep)
    }

    private var headerDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
        f.dateStyle = .full
        return f.string(from: date)
    }

    private func loadFromExisting() {
        guard let log = existing else { return }
        foodCount = log.foodCount
        waterCount = log.waterCount
        hasDiscomfort = log.hasDiscomfort
        notes = log.notes
        if let m = log.moodScore { moodScore = m; moodSet = true }
        if let w = log.weightGrams { weightText = "\(w)" }
    }

    private func save() {
        let weightVal = Int(weightText.trimmingCharacters(in: .whitespaces))

        // If this would create an empty record, just clean up and bail.
        let nothingLogged = foodCount == 0 && waterCount == 0 && !hasDiscomfort
            && notes.trimmingCharacters(in: .whitespaces).isEmpty
            && !moodSet && weightVal == nil
        if let log = existing {
            if nothingLogged {
                modelContext.delete(log)
                return
            }
            log.foodCount = foodCount
            log.waterCount = waterCount
            log.hasDiscomfort = hasDiscomfort
            log.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            log.moodScore = moodSet ? moodScore : nil
            log.weightGrams = weightVal
        } else {
            guard !nothingLogged else { return }
            let log = DailyLog(
                date: date,
                foodCount: foodCount,
                waterCount: waterCount,
                moodScore: moodSet ? moodScore : nil,
                weightGrams: weightVal,
                hasDiscomfort: hasDiscomfort,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                cat: cat
            )
            modelContext.insert(log)
        }
    }

    // MARK: - Counter helper

    private func counterRow(icon: String, color: Color, title: String,
                             value: Binding<Int>, max maxV: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title).foregroundStyle(theme.deep)
            Spacer()
            Button {
                if value.wrappedValue > 0 { value.wrappedValue -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(value.wrappedValue > 0 ? theme.deep : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)

            Text("\(value.wrappedValue)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .frame(minWidth: 32)
                .foregroundStyle(theme.deep)

            Button {
                if value.wrappedValue < maxV { value.wrappedValue += 1 }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(value.wrappedValue < maxV ? theme.deep : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }
}
