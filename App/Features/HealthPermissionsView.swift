import SwiftUI
import CareCore

struct HealthPermissionsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var permissionStatus: HealthPermissionStatus = .notDetermined
    @State private var isRequesting = false
    @State private var errorMessage: String?
    @State private var seedResults: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red.gradient)

                        Text("Health Data Access")
                            .font(.system(size: 32, weight: .bold))

                        Text("CareCompanion can sync health data from Apple Health to help family members understand daily activity patterns.")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // What we access
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What We Access")
                            .font(.system(size: 22, weight: .semibold))

                        HealthDataTypeRow(
                            icon: "figure.walk",
                            title: "Steps",
                            description: "Daily step count to monitor activity levels"
                        )

                        HealthDataTypeRow(
                            icon: "bed.double.fill",
                            title: "Sleep",
                            description: "Sleep duration to track rest patterns"
                        )

                        HealthDataTypeRow(
                            icon: "heart.fill",
                            title: "Resting Heart Rate",
                            description: "Heart rate measurements for wellness monitoring"
                        )
                    }

                    // Privacy notice
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.blue)
                            Text("Your Privacy")
                                .font(.system(size: 20, weight: .semibold))
                        }

                        Text("• Health data stays on your device and is only shared with authorized family members\n• You control which data types to share\n• You can revoke access anytime in Settings")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                    // Current status
                    if permissionStatus != .notDetermined {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Status")
                                .font(.system(size: 17, weight: .semibold))

                            HStack {
                                statusIcon
                                Text(statusText)
                                    .font(.system(size: 15))
                                Spacer()
                            }
                            .padding(12)
                            .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                            .padding(12)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Action button
                    if permissionStatus == .notDetermined || permissionStatus == .denied {
                        Button {
                            Task {
                                await requestPermission()
                            }
                        } label: {
                            HStack {
                                if isRequesting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(permissionStatus == .notDetermined ? "Allow Health Access" : "Open Settings")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                        }
                        .disabled(isRequesting)
                    }

                    if permissionStatus == .authorized {
                        syncVerificationSection
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await checkPermissionStatus()
        }
    }

    private var healthKitRecords: [HealthSnapshot] {
        state.snapshot.health.filter { $0.seniorID == state.selectedSeniorID && $0.source == "healthkit" }
    }

    private var syncVerificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync Verification")
                .font(.system(size: 17, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Senior: \(state.selectedSenior?.name ?? "—") (\(state.selectedSeniorID))")
                Text("Sync state: \(state.healthSyncStatus.healthData.rawValue)")
                if let date = state.healthSyncStatus.lastSyncDate {
                    Text("Last sync: \(date.formatted(date: .abbreviated, time: .standard))")
                }
                if let error = state.healthSyncStatus.lastError {
                    Text("Last error: \(error)").foregroundStyle(.red)
                }
                Text("Apple Health days synced: \(healthKitRecords.count)")
                if let latest = healthKitRecords.first {
                    Text("Latest (\(latest.date.formatted(date: .abbreviated, time: .omitted))): \(latest.steps) steps · \(latest.sleepMinutes) min sleep · \(latest.restingHeartRate) bpm")
                } else {
                    Text("No Apple Health samples found yet — dashboard is showing demo data.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("health.syncVerification")

            Button {
                Task { await state.syncHealthData() }
            } label: {
                Text(state.healthSyncStatus.healthData == .syncing ? "Syncing…" : "Sync Now")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .disabled(state.healthSyncStatus.healthData == .syncing)
            .accessibilityIdentifier("health.syncNow")

            #if DEBUG
            if let healthKit = state.healthProvider as? HealthKitHealthDataProvider {
                Button {
                    Task {
                        seedResults = await healthKit.seedSampleData()
                        await state.syncHealthData()
                    }
                } label: {
                    Text("Add Sample Health Data (Debug)")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.orange)
                }
                .accessibilityIdentifier("health.seedSampleData")

                if !seedResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(seedResults, id: \.self) { line in
                            Text(line).foregroundStyle(line.hasPrefix("Saved") ? Color.primary : Color.red)
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
            }
            #endif
        }
    }

    private var statusIcon: some View {
        Group {
            switch permissionStatus {
            case .authorized:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .restricted:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .notDetermined:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.gray)
            }
        }
        .font(.system(size: 20))
    }

    private var statusText: String {
        switch permissionStatus {
        case .authorized:
            return "Health data access granted"
        case .denied:
            return "Access denied. Open Settings to enable."
        case .restricted:
            return "Health data is restricted on this device"
        case .notDetermined:
            return "Permission not requested yet"
        }
    }

    private func checkPermissionStatus() async {
        if let healthProvider = state.healthProvider {
            permissionStatus = await healthProvider.permissionStatus()
        }
    }

    private func requestPermission() async {
        guard let healthProvider = state.healthProvider else { return }

        isRequesting = true
        errorMessage = nil

        do {
            if permissionStatus == .denied {
                // Open Settings if already denied
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
            } else {
                // Request permission
                try await healthProvider.requestPermission()
                await checkPermissionStatus()

                // If authorized, set up automatic sync and perform initial sync
                if permissionStatus == .authorized {
                    await state.setupAutomaticHealthSync()
                    await state.syncHealthData()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isRequesting = false
    }
}

struct HealthDataTypeRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    HealthPermissionsView()
        .environment(AppState(repository: DemoCareRepository()))
}
