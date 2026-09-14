import SwiftUI
import CareCore

/// Full medication CRUD with add, edit, delete, and adherence tracking
struct MedicationManagementView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddMedication = false
    @State private var editingMedication: Medication?

    private var medications: [Medication] {
        state.snapshot.medications.filter { $0.seniorID == state.selectedSeniorID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if medications.isEmpty {
                        ContentUnavailableView(
                            "No Medications",
                            systemImage: "capsule",
                            description: Text("Add medications to track daily adherence")
                        )
                    } else {
                        ForEach(medications) { medication in
                            MedicationRowView(medication: medication, onEdit: {
                                editingMedication = medication
                            })
                        }
                    }
                }

                Section {
                    Button {
                        showingAddMedication = true
                    } label: {
                        Label("Add Medication", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddMedication) {
                AddMedicationView()
            }
            .sheet(item: $editingMedication) { medication in
                EditMedicationView(medication: medication)
            }
        }
    }
}

private struct MedicationRowView: View {
    @Environment(AppState.self) private var state
    let medication: Medication
    let onEdit: () -> Void
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack {
            Button {
                Task { await state.toggleMedication(id: medication.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: medication.taken ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(medication.taken ? CareTheme.sage : CareTheme.secondaryText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(medication.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CareTheme.ink)
                        Text(medication.scheduledTime)
                            .font(.system(size: 14))
                            .foregroundStyle(CareTheme.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(CareTheme.secondaryText)
            }
        }
        .confirmationDialog("Delete Medication", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await state.deleteMedication(id: medication.id) }
            }
        } message: {
            Text("Are you sure you want to delete \(medication.name)?")
        }
    }
}

private struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var scheduledTime = "8:00 AM"

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication Details") {
                    TextField("Name", text: $name)
                    TextField("Scheduled Time", text: $scheduledTime)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button("Add Medication") {
                        Task {
                            await state.addMedication(name: name, scheduledTime: scheduledTime)
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || scheduledTime.isEmpty)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct EditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    let medication: Medication
    @State private var name = ""
    @State private var scheduledTime = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication Details") {
                    TextField("Name", text: $name)
                    TextField("Scheduled Time", text: $scheduledTime)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button("Save Changes") {
                        Task {
                            await state.updateMedication(id: medication.id, name: name, scheduledTime: scheduledTime)
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || scheduledTime.isEmpty)
                }
            }
            .navigationTitle("Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                name = medication.name
                scheduledTime = medication.scheduledTime
            }
        }
    }
}
