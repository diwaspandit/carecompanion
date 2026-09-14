import SwiftUI
import CareCore

/// App settings: sign out, demo reset, privacy controls, about
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(LiveModeController.self) private var live
    @Environment(\.dismiss) private var dismiss
    @State private var showingResetConfirmation = false
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                // Account Section (if signed in)
                if live.isSignedIn {
                    Section("Account") {
                        if let email = live.signedInEmail {
                            LabeledContent("Email", value: email)
                        }

                        if live.hasAccount, let account = state.snapshot.account.name as String? {
                            LabeledContent("Family", value: account)
                        }

                        if live.isLive, let repo = live.repository {
                            LabeledContent("Invite Code", value: repo.inviteCode)
                                .textSelection(.enabled)
                        }

                        Button(role: .destructive) {
                            showingSignOutConfirmation = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                // Demo Section
                Section("Demo") {
                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset Demo", systemImage: "arrow.counterclockwise")
                    }
                }

                // Privacy Section
                Section("Privacy") {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy & Data", systemImage: "hand.raised")
                    }
                }

                // About Section
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "1")
                    Link(destination: URL(string: "https://carecompanion.example.com")!) {
                        Label("Website", systemImage: "globe")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset Demo", isPresented: $showingResetConfirmation) {
                Button("Reset", role: .destructive) {
                    Task { await state.resetDemo() }
                }
            } message: {
                Text("This will reset all demo data to the initial state.")
            }
            .confirmationDialog("Sign Out", isPresented: $showingSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    Task { await live.signOut() }
                }
            } message: {
                Text("You'll need to sign in again to access your care data.")
            }
        }
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text("CareCompanion processes health and care data locally on your device. Data is synced securely to your family account when you're signed in.")
                    .font(.system(size: 15))
                    .foregroundStyle(CareTheme.secondaryText)
            }

            Section("Data Collection") {
                LabeledContent("Health Data", value: "With Permission")
                LabeledContent("Location", value: "Never")
                LabeledContent("Analytics", value: "None")
            }

            Section("Your Rights") {
                Button("Delete My Data") {
                    // Placeholder for data deletion
                }
                Button("Export My Data") {
                    // Placeholder for data export
                }
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
