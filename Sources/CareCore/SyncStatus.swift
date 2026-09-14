import Foundation

/// Represents the synchronization status of various services
public enum SyncState: String, Codable, Sendable {
    case idle
    case syncing
    case synced
    case failed
    case offline
}

/// Tracks sync status for different service components
public struct SyncStatus: Equatable, Codable, Sendable {
    public var careData: SyncState
    public var healthData: SyncState
    public var subscription: SyncState
    public var lastSyncDate: Date?
    public var lastError: String?

    public init(
        careData: SyncState = .idle,
        healthData: SyncState = .idle,
        subscription: SyncState = .idle,
        lastSyncDate: Date? = nil,
        lastError: String? = nil
    ) {
        self.careData = careData
        self.healthData = healthData
        self.subscription = subscription
        self.lastSyncDate = lastSyncDate
        self.lastError = lastError
    }

    public var isAnySyncing: Bool {
        [careData, healthData, subscription].contains(.syncing)
    }

    public var hasAnyFailed: Bool {
        [careData, healthData, subscription].contains(.failed)
    }

    public var allSynced: Bool {
        [careData, healthData, subscription].allSatisfy { $0 == .synced || $0 == .idle }
    }
}
