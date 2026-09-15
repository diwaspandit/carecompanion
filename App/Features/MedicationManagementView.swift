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
                        Button { editing = medication } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(medication.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(CareTheme.ink)
                                    Text([medication.dosage, medication.scheduledTime].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: medication.taken ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(medication.taken ? CareTheme.sage : CareTheme.secondaryText)
                                    .accessibilityLabel(medication.taken ? "Taken today" : "Not taken today")
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { medications[$0].id }
                        Task { for id in ids { await state.deleteMedication(id: id) } }
                    }
                } footer: {
                    Text("Changes appear on every family member's phone.")
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

private struct MedicationFormView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let medication: Medication?

    @State private var name = ""
    @State private var dosage = ""
    @State private var time = MedicationTime.date(from: "8:00 AM")
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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityIdentifier("medication.form.save")
                }
            }
            .onAppear {
                guard let medication else { return }
                name = medication.name
                dosage = medication.dosage
                time = MedicationTime.date(from: medication.scheduledTime)
            }
        }
    }

    private func save() {
        let scheduled = MedicationTime.string(from: time)
        Task {
            isSaving = true
            let saved = if let medication {
                await state.updateMedication(id: medication.id, name: name, dosage: dosage, scheduledTime: scheduled)
            } else {
                await state.addMedication(name: name, dosage: dosage, scheduledTime: scheduled)
            }
            isSaving = false
            if saved { dismiss() }
        }
    }
}
