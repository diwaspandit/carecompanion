import CareCore
import SwiftUI

/// Lets the senior share Apple Health with their family from their own iPhone.
struct HealthPermissionsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var permission: HealthPermissionStatus = .notDetermined
    @State private var isWorking = false
    @State private var errorMessage: String?
    #if DEBUG
    @State private var sampleResult: String?
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(CareTheme.coral)
                            .accessibilityHidden(true)
                        Text("Share Apple Health")
                            .font(.system(size: 30, weight: .black))
                        Text("Your family sees a daily total for each of these, so they know how your days are going.")
                            .font(.system(size: 17))
                            .foregroundStyle(CareTheme.mutedText)
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 14) {
                        HealthDataTypeRow(icon: "figure.walk", title: "Steps", description: "How active you were each day")
                        HealthDataTypeRow(icon: "bed.double.fill", title: "Sleep", description: "Hours asleep each night")
                        HealthDataTypeRow(icon: "heart.fill", title: "Resting heart rate", description: "Your daily resting heart rate")
                    }

                    Text("Individual Health samples stay on this iPhone. CareCompanion never writes to Apple Health. To stop sharing, open the Health app › Sharing › Apps › CareCompanion.")
                        .font(.system(size: 14))
                        .foregroundStyle(CareTheme.mutedText)
                        .padding(16)
                        .background(CareTheme.bluePale, in: RoundedRectangle(cornerRadius: 16))

                    FormErrorText(message: errorMessage ?? state.healthSyncStatus.lastError)

                    if permission == .restricted {
                        Text("Apple Health isn't available on this device.")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CareTheme.coralDark)
                    } else if permission != .authorized {
                        PrimaryActionButton(title: "Allow Apple Health access", isLoading: isWorking) {
                            Task { await requestAccess() }
                        }
                        .accessibilityIdentifier("health.allow")
                    } else {
                        syncSection
                    }

                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(CareTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { permission = await state.checkHealthPermissionStatus() }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let synced = state.snapshot.health.filter { $0.seniorID == state.linkedSenior?.id && $0.source == "healthkit" }
            Label(synced.isEmpty ? "Access allowed. No Health data found for the past week yet." : "Sharing \(synced.count) days with your family",
                  systemImage: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CareTheme.sageDark)
                .accessibilityIdentifier("health.status")
            if let date = state.healthSyncStatus.lastSyncDate {
                Text("Last shared \(date.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 14))
                    .foregroundStyle(CareTheme.secondaryText)
            }
            PrimaryActionButton(title: state.healthSyncStatus.healthData == .syncing ? "Sharing…" : "Share now",
                                isLoading: state.healthSyncStatus.healthData == .syncing) {
                Task { await state.syncHealthData() }
            }
            .accessibilityIdentifier("health.syncNow")
            Button("Health permissions in Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(CareTheme.sageDark)
        }
    }

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 8)
            Text("Developer (debug builds only)").font(.system(size: 13, weight: .bold)).foregroundStyle(CareTheme.secondaryText)
            Button("Write a sample week into Apple Health") {
                Task {
                    guard let provider = state.healthProvider as? HealthKitHealthDataProvider else { return }
                    sampleResult = await provider.writeSimulatorSampleWeek()
                    permission = await state.checkHealthPermissionStatus()
                    await state.setupAutomaticHealthSync()
                    await state.syncHealthData()
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .accessibilityIdentifier("health.writeSample")
            if let sampleResult {
                Text(sampleResult).font(.system(size: 12, design: .monospaced)).foregroundStyle(CareTheme.mutedText)
            }
        }
    }
    #endif

    private func requestAccess() async {
        isWorking = true
        errorMessage = nil
        do {
            try await state.requestHealthPermissions()
            permission = await state.checkHealthPermissionStatus()
            await state.setupAutomaticHealthSync()
            await state.syncHealthData()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}

struct HealthDataTypeRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(CareTheme.blue)
                .frame(width: 44, height: 44)
                .background(CareTheme.bluePale, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(description).font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
