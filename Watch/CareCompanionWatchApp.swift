import SwiftUI
import WatchKit

@main
struct CareCompanionWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchPushDelegate.self) private var pushDelegate
    @State private var session = WatchSession()

    init() {
        MedicationReminderCenter.shared.prepare()
        activateWatchPhoneLink()
        Task { @MainActor in WatchHealthRelay.shared.start() }
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(session)
        }
    }
}

final class WatchPushDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        activateWatchPhoneLink()
        Task { @MainActor in WatchHealthRelay.shared.start() }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        Task { @MainActor in
            for task in backgroundTasks {
                if let refresh = task as? WKApplicationRefreshBackgroundTask {
                    await WatchHealthRelay.shared.publish()
                    WatchHealthRelay.scheduleBackgroundRefresh()
                    refresh.setTaskCompletedWithSnapshot(false)
                } else {
                    task.setTaskCompletedWithSnapshot(false)
                }
            }
        }
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        PushRegistration.store(deviceToken)
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {}
}
