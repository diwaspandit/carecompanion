import Foundation

/// Permission status for health data access
public enum HealthPermissionStatus: String, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
    case restricted
}

/// Protocol for health data providers (HealthKit, demo data, etc.)
public protocol HealthDataProvider: Sendable {
    /// Get current permission status for health data
    func permissionStatus() async -> HealthPermissionStatus

    /// Request permission to read health data
    func requestPermission() async throws

    /// Get health snapshots for a senior
    func snapshots(seniorID: String, endingAt date: Date) async throws -> [HealthSnapshot]

    /// Start background sync if permissions are granted
    func startBackgroundSync() async throws

    /// Stop background sync
    func stopBackgroundSync() async
}

/// Demo implementation that provides deterministic health data
public struct DemoHealthDataProvider: HealthDataProvider {
    public init() {}

    public func permissionStatus() async -> HealthPermissionStatus {
        // Demo mode simulates authorized status
        .authorized
    }

    public func requestPermission() async throws {
        // Demo mode doesn't need real permissions
    }

    public func snapshots(seniorID: String, endingAt date: Date) async throws -> [HealthSnapshot] {
        let steps = [2840, 3120, 2680, 3400, 2950, 3200, 3050]
        let sleep = [380, 410, 395, 420, 405, 390, 415]
        let heartRate = [72, 71, 73, 70, 72, 71, 72]

        return (0..<7).map { day in
            HealthSnapshot(
                id: "health-\(seniorID)-\(day)",
                seniorID: seniorID,
                date: date.addingTimeInterval(Double(-day) * 86400),
                steps: steps[day],
                sleepMinutes: sleep[day],
                restingHeartRate: heartRate[day],
                source: "Demo data"
            )
        }
    }

    public func startBackgroundSync() async throws {
        // Demo mode doesn't sync real data
    }

    public func stopBackgroundSync() async {
        // Demo mode doesn't have sync to stop
    }

    /// Synchronous version for backward compatibility
    public func snapshotsSync(seniorID: String, endingAt date: Date) -> [HealthSnapshot] {
        let steps = [2840, 3120, 2680, 3400, 2950, 3200, 3050]
        let sleep = [380, 410, 395, 420, 405, 390, 415]
        let heartRate = [72, 71, 73, 70, 72, 71, 72]

        return (0..<7).map { day in
            HealthSnapshot(
                id: "health-\(seniorID)-\(day)",
                seniorID: seniorID,
                date: date.addingTimeInterval(Double(-day) * 86400),
                steps: steps[day],
                sleepMinutes: sleep[day],
                restingHeartRate: heartRate[day],
                source: "Demo data"
            )
        }
    }
}
