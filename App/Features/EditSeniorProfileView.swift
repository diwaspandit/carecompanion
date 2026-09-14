import SwiftUI
import CareCore

/// Edit senior profile details
struct EditSeniorProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state

    @State private var name = ""
    @State private var age = 65
    @State private var city = ""
    @State private var timeZone = "UTC"

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    TextField("Name", text: $name)
                    Stepper("Age: \(age)", value: $age, in: 1...130)
                    TextField("City", text: $city)
                }

                Section("Location") {
                    Picker("Time Zone", selection: $timeZone) {
                        Text("Asia/Kathmandu").tag("Asia/Kathmandu")
                        Text("America/Chicago").tag("America/Chicago")
                        Text("America/New_York").tag("America/New_York")
                        Text("America/Los_Angeles").tag("America/Los_Angeles")
                        Text("Europe/London").tag("Europe/London")
                        Text("UTC").tag("UTC")
                    }
                }

                Section {
                    Button("Save Changes") {
                        Task {
                            await state.updateSeniorProfile(
                                name: name,
                                age: age,
                                city: city,
                                timeZone: timeZone
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || city.isEmpty)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let senior = state.selectedSenior {
                    name = senior.name
                    age = senior.age
                    city = senior.city
                    timeZone = senior.timeZoneIdentifier
                }
            }
        }
    }
}

/// Emergency contacts management
struct EmergencyContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddContact = false

    // Demo contacts (in production, these would come from the repository)
    struct EmergencyContact: Identifiable {
        let id = UUID()
        var name: String
        var relation: String
        var phone: String
    }

    @State private var contacts: [EmergencyContact] = [
        EmergencyContact(name: "Diwas Sharma", relation: "Son", phone: "+1 512 555 0142"),
        EmergencyContact(name: "Sunita Sharma", relation: "Daughter", phone: "+977 98 4100 2233")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(contacts) { contact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.name)
                            .font(.system(size: 17, weight: .semibold))
                        Text(contact.relation)
                            .font(.system(size: 14))
                            .foregroundStyle(CareTheme.secondaryText)
                        Text(contact.phone)
                            .font(.system(size: 14))
                            .foregroundStyle(CareTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    contacts.remove(atOffsets: indexSet)
                }
            }
            .navigationTitle("Emergency Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddContact = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddEmergencyContactView { contact in
                    contacts.append(contact)
                }
            }
        }
    }
}

private struct AddEmergencyContactView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (EmergencyContactsView.EmergencyContact) -> Void

    @State private var name = ""
    @State private var relation = ""
    @State private var phone = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact Details") {
                    TextField("Name", text: $name)
                    TextField("Relation", text: $relation)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section {
                    Button("Add Contact") {
                        onAdd(EmergencyContactsView.EmergencyContact(
                            name: name,
                            relation: relation,
                            phone: phone
                        ))
                        dismiss()
                    }
                    .disabled(name.isEmpty || relation.isEmpty || phone.isEmpty)
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
