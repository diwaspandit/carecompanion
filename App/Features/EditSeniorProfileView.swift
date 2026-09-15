import CareCore
import SwiftUI

/// Edit the selected senior's details.
struct EditSeniorProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state

    @State private var name = ""
    @State private var age = 70
    @State private var city = ""
    @State private var timeZone = TimeZone.current.identifier
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SeniorDetailsFields(name: $name, age: $age, city: $city, timeZone: $timeZone)
                    Text("Check-ins and medicines reset at midnight in this time zone.")
                        .font(.system(size: 13))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                .padding(20)
            }
            .background(CareTheme.background)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            let saved = await state.updateSeniorProfile(name: name, age: age, city: city, timeZone: timeZone)
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                guard let senior = state.selectedSenior else { return }
                name = senior.name
                age = senior.age
                city = senior.city
                timeZone = senior.timeZoneIdentifier
            }
        }
    }
}

/// Add or edit an emergency contact for the selected senior.
struct EmergencyContactFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    let contact: EmergencyContact?

    @State private var name = ""
    @State private var relation = ""
    @State private var phone = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .accessibilityIdentifier("contact.form.name")
                    TextField("Relation, e.g. Daughter, Doctor", text: $relation)
                    TextField("Phone number", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .accessibilityIdentifier("contact.form.phone")
                } header: {
                    Text("Contact")
                } footer: {
                    Text("Shown on the SOS screen so help is one tap away.")
                }
                if let contact {
                    Section {
                        Button("Delete contact", role: .destructive) {
                            Task {
                                await state.deleteEmergencyContact(id: contact.id)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(contact == nil ? "Add contact" : "Edit contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            let saved = await state.saveEmergencyContact(name: name, relation: relation, phone: phone,
                                                                         id: contact?.id ?? "")
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || PhoneLinks.call(phone) == nil || isSaving)
                    .accessibilityIdentifier("contact.form.save")
                }
            }
            .onAppear {
                guard let contact else { return }
                name = contact.name
                relation = contact.relation
                phone = contact.phone
            }
        }
    }
}
