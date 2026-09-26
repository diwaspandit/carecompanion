import CareCore
import SwiftUI

/// Add or edit a visit for the selected senior.
struct AppointmentFormView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let appointment: Appointment?

    @State private var title = ""
    @State private var clinician = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var location = ""
    @State private var notes = ""
    @State private var repeatRule = VisitRepeat.once
    @State private var hasEnd = false
    @State private var endsOn = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var isSaving = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Visit") {
                    TextField("What is it? e.g. Heart check-up", text: $title)
                        .accessibilityIdentifier("appointment.form.title")
                    TextField("Doctor or clinician", text: $clinician)
                    DatePicker("Date and time", selection: $date)
                    TextField("Location", text: $location)
                }
                Section("Repeat") {
                    Picker("Repeats", selection: $repeatRule) {
                        ForEach(VisitRepeat.allCases, id: \.self) { rule in
                            Text(rule.label).tag(rule)
                        }
                    }
                    .accessibilityIdentifier("appointment.form.repeat")
                    if repeatRule != .once {
                        Toggle("Set an end date", isOn: $hasEnd)
                        if hasEnd {
                            DatePicker("Last day", selection: $endsOn, in: date..., displayedComponents: .date)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Things to bring or ask", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                if let appointment {
                    Section {
                        Button("Delete appointment", role: .destructive) { confirmDelete = true }
                    }
                    .confirmationDialog("Delete \(appointment.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            Task {
                                await state.deleteAppointment(id: appointment.id)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(appointment == nil ? "New appointment" : "Edit appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityIdentifier("appointment.form.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let appointment else { return }
        title = appointment.title
        clinician = appointment.clinician
        date = appointment.date
        location = appointment.location
        notes = appointment.notes
        repeatRule = appointment.repeatRule
        if let stored = appointment.endsOn {
            hasEnd = true
            endsOn = CareSchedule.pickerDate(fromStored: stored, timeZone: state.selectedTimeZone)
        }
    }

    private func save() {
        let edited = Appointment(id: appointment?.id ?? "", seniorID: appointment?.seniorID ?? state.selectedSeniorID,
                                 title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                 clinician: clinician.trimmingCharacters(in: .whitespacesAndNewlines), date: date,
                                 location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                                 notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                 repeatRule: repeatRule,
                                 endsOn: repeatRule == .once || !hasEnd
                                    ? nil
                                    : CareSchedule.storedDay(from: endsOn, timeZone: state.selectedTimeZone),
                                 outcome: appointment?.outcome, loggedAt: appointment?.loggedAt)
        Task {
            isSaving = true
            if await state.saveAppointment(edited) { dismiss() }
            isSaving = false
        }
    }
}

/// Upcoming and past visits for the selected senior, with add/edit.
struct AppointmentListSection: View {
    @Environment(AppState.self) private var state
    var large = false
    @State private var editing: Appointment?
    @State private var adding = false

    private var upcoming: [(Appointment, Date)] {
        state.appointments.compactMap { visit in
            guard let next = CareSchedule.nextOccurrence(of: visit, after: Date(), timeZone: state.selectedTimeZone) else { return nil }
            return (visit, next)
        }.sorted { $0.1 < $1.1 }
    }
    private var past: [Appointment] {
        state.appointments.filter { CareSchedule.nextOccurrence(of: $0, after: Date(), timeZone: state.selectedTimeZone) == nil }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Upcoming")
                    .font(.system(size: large ? 25 : 17, weight: .black))
                    .foregroundStyle(large ? CareTheme.ink : CareTheme.secondaryText)
                Spacer()
                Button {
                    adding = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(CareTheme.action, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("appointments.add")
            }
            if upcoming.isEmpty {
                EmptyStateCard(icon: "calendar", title: "No upcoming visits",
                               message: "Add doctor visits so everyone knows what's coming up.")
            }
            ForEach(upcoming, id: \.0.id) { appointment, when in
                VStack(alignment: .leading, spacing: 8) {
                    Button { editing = appointment } label: {
                        AppointmentRowView(appointment: appointment, timeZone: state.selectedTimeZone, displayDate: when)
                    }
                    .buttonStyle(.plain)
                    visitLog(appointment)
                }
            }
            if !past.isEmpty {
                Text("Earlier")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(CareTheme.secondaryText)
                    .padding(.top, 6)
                ForEach(past) { appointment in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { editing = appointment } label: {
                            AppointmentRowView(appointment: appointment, timeZone: state.selectedTimeZone)
                                .opacity(0.7)
                        }
                        .buttonStyle(.plain)
                        visitLog(appointment)
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { AppointmentFormView(appointment: nil) }
        .sheet(item: $editing) { AppointmentFormView(appointment: $0) }
    }

    @ViewBuilder
    private func visitLog(_ appointment: Appointment) -> some View {
        if let occurrence = CareSchedule.occurrenceNeedingLog(appointment, now: Date(), timeZone: state.selectedTimeZone) {
            HStack(spacing: 10) {
                Button("Went") { Task { await state.logVisit(id: appointment.id, outcome: .went, occurrence: occurrence) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(CareTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(CareTheme.grayPill, in: Capsule())
                    .accessibilityIdentifier("appointment.went.\(appointment.id)")
                Button("Missed") { Task { await state.logVisit(id: appointment.id, outcome: .missed, occurrence: occurrence) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(CareTheme.danger)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(CareTheme.grayPill, in: Capsule())
                    .accessibilityIdentifier("appointment.missed.\(appointment.id)")
            }
        }
    }
}
