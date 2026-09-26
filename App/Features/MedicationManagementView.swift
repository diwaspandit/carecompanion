import CareCore
import SwiftUI

/// Add, edit and remove the selected senior's medicines.
struct MedicationManagementView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false
    @State private var editing: Medication?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let medications = MedicationTime.sorted(state.medications)
                    if medications.isEmpty {
                        ContentUnavailableView("No medicines", systemImage: "pills",
                                               description: Text("Add each medicine with its dose and time."))
                    }
                    ForEach(medications) { medication in
                        HStack {
                            Button { editing = medication } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(medication.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(CareTheme.ink)
                                        Text([medication.dosage, medication.scheduledTime, CareSchedule.medicationScheduleText(medication)]
                                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: medication.taken ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(medication.taken ? CareTheme.sage : CareTheme.secondaryText)
                                        .accessibilityLabel(medication.taken ? "Taken today" : "Not taken today")
                                }
                            }
                            .buttonStyle(.plain)
                            if state.role == .family {
                                MedicationRemindButton(medication: medication)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { medications[$0].id }
                        Task { for id in ids { await state.deleteMedication(id: id) } }
                    }
                } footer: {
                    Text("Added medicines show up on the senior's phone and for every family member.")
                }
                Section {
                    Button { showingAdd = true } label: {
                        Label("Add medicine", systemImage: "plus")
                    }
                    .accessibilityIdentifier("medications.add")
                }
            }
            .navigationTitle("Medicines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAdd) { MedicationFormView(medication: nil) }
            .sheet(item: $editing) { MedicationFormView(medication: $0) }
        }
    }
}

struct MedicationFormView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let medication: Medication?

    @State private var name = ""
    @State private var dosage = ""
    @State private var time = MedicationTime.date(from: "8:00 AM")
    @State private var everyDay = true
    @State private var weekdays: Set<Int> = []
    @State private var hasEnd = false
    @State private var endsOn = Date()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Medicine") {
                    TextField("Name, e.g. Amlodipine", text: $name)
                        .accessibilityIdentifier("medication.form.name")
                    TextField("Dose, e.g. 5 mg, 1 tablet", text: $dosage)
                        .accessibilityIdentifier("medication.form.dosage")
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
                Section("Repeat") {
                    Toggle("Every day", isOn: $everyDay)
                        .onChange(of: everyDay) { _, isOn in
                            if !isOn, weekdays.isEmpty {
                                var calendar = Calendar(identifier: .gregorian)
                                calendar.timeZone = state.selectedTimeZone
                                weekdays = [calendar.component(.weekday, from: Date())]
                            }
                        }
                    if !everyDay {
                        weekdayPicker
                    }
                    Toggle("Set an end date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Last day", selection: $endsOn, displayedComponents: .date)
                    }
                }
                if let medication {
                    Section {
                        Button("Delete medicine", role: .destructive) {
                            Task {
                                await state.deleteMedication(id: medication.id)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(medication == nil ? "Add medicine" : "Edit medicine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving || (!everyDay && weekdays.isEmpty))
                        .accessibilityIdentifier("medication.form.save")
                }
            }
            .onAppear {
                guard let medication else { return }
                name = medication.name
                dosage = medication.dosage
                time = MedicationTime.date(from: medication.scheduledTime)
                everyDay = medication.weekdays.isEmpty
                weekdays = Set(medication.weekdays)
                if let stored = medication.endsOn {
                    hasEnd = true
                    endsOn = CareSchedule.pickerDate(fromStored: stored, timeZone: state.selectedTimeZone)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        let symbols = CareSchedule.weekdaySymbols
        return HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = weekdays.contains(day)
                Button(symbols[day - 1]) {
                    if on { weekdays.remove(day) } else { weekdays.insert(day) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(on ? .white : CareTheme.ink)
                .background(on ? CareTheme.sage : CareTheme.grayPill, in: Capsule())
                .accessibilityLabel(symbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func save() {
        let scheduled = MedicationTime.string(from: time)
        let days = everyDay ? [] : weekdays.sorted()
        let end = hasEnd ? CareSchedule.storedDay(from: endsOn, timeZone: state.selectedTimeZone) : nil
        Task {
            isSaving = true
            let saved = if let medication {
                await state.updateMedication(id: medication.id, name: name, dosage: dosage, scheduledTime: scheduled,
                                             weekdays: days, endsOn: end)
            } else {
                await state.addMedication(name: name, dosage: dosage, scheduledTime: scheduled, weekdays: days, endsOn: end)
            }
            isSaving = false
            if saved { dismiss() }
        }
    }
}
