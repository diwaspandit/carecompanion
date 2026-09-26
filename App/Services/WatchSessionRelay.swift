import CareCore
import Foundation
import WatchConnectivity

/// Sends the iPhone's signed-in session to the paired watch. The watch asks, and the phone also
/// publishes whenever the account changes. A restarted watch has an empty login, so the phone
/// keeps offering the current one instead of waiting for a new sign-in.
final class WatchSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {
    private weak var controller: SessionController?
    private var republish: Task<Void, Never>?

    func start(controller: SessionController) {
        self.controller = controller
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        republish?.cancel()
        republish = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.publish()
            }
        }
    }

    func publish() {
        let controller = controller
        Task { @MainActor in
            guard let controller else { return }
            var payload = (await controller.watchHandoff()).dictionary
            // The system drops an application context that matches the previous one. A restarted
            // watch no longer has that context, so each send needs its own marker.
            payload["sentAt"] = UUID().uuidString
            payload["appearance"] = UserDefaults.standard.string(forKey: CareAppearance.storageKey) ?? "system"
            guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Self.flushPendingWatchMessages()
        publish()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { publish() }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        publish()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    /// Sends a message alert to the watch now, or holds it until the phone link is ready.
    static func sendToWatch(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        if WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(payload)
            return
        }
        pendingLock.lock()
        pendingWatchMessages.append(payload)
        pendingLock.unlock()
    }

    static func flushPendingWatchMessages() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        pendingLock.lock()
        let queued = pendingWatchMessages
        pendingWatchMessages = []
        pendingLock.unlock()
        for payload in queued {
            WCSession.default.transferUserInfo(payload)
        }
    }

    private static let pendingLock = NSLock()
    nonisolated(unsafe) private static var pendingWatchMessages: [[String: Any]] = []

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["kind"] as? String == WatchHealthReport.messageKind {
            ingest(message)
            replyHandler(["ok": "1"])
            return
        }
        if message["kind"] as? String == PhoneOpen.messagesKind {
            replyHandler(["ok": "1"])
            let controller = controller
            Task { @MainActor in
                controller?.showMessagesFromWatch()
            }
            return
        }
        let controller = controller
        let reply = Reply(replyHandler)
        Task { @MainActor in
            var payload = (await controller?.watchHandoff() ?? WatchAuthHandoff(status: .signedOut)).dictionary
            payload["sentAt"] = UUID().uuidString
            payload["appearance"] = UserDefaults.standard.string(forKey: CareAppearance.storageKey) ?? "system"
            reply.send(payload)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo["kind"] as? String == "moodClear" {
            let controller = controller
            Task { @MainActor in
                await MedicationReminderCenter.shared.dismissMoodPromptLocally()
                guard let state = controller?.appState else { return }
                await state.refresh()
                await MedicationReminderCenter.shared.sync(from: state)
            }
            return
        }
        if userInfo["kind"] as? String == PhoneOpen.messagesKind {
            let controller = controller
            Task { @MainActor in
                controller?.showMessagesFromWatch()
            }
            return
        }
        ingest(userInfo)
    }

    private func ingest(_ message: [String: Any]) {
        guard let report = WatchHealthReport(userInfo: message) else { return }
        let controller = controller
        Task { @MainActor in
            await controller?.receiveWatchHealth(report)
        }
    }
}

/// Lets the Watch Connectivity reply cross into a main-actor task.
private final class Reply: @unchecked Sendable {
    private let reply: ([String: Any]) -> Void

    init(_ reply: @escaping ([String: Any]) -> Void) {
        self.reply = reply
    }

    func send(_ payload: [String: String]) {
        reply(payload)
    }
}
