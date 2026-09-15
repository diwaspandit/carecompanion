import Foundation

/// Retries a request once when a pooled connection drops before any response arrives, for example an
/// idle HTTP/3 connection that timed out while the app was in the background. Only use it for
/// requests that are safe to send twice.
public enum TransientRetry {
    public static func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [.networkConnectionLost, .timedOut, .cannotConnectToHost, .secureConnectionFailed].contains(urlError.code)
    }

    /// Runs on the caller's actor so the work closure never crosses isolation.
    public static func run<T>(isolation: isolated (any Actor)? = #isolation, retryDelay: Duration = .milliseconds(400),
                              _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error where isTransient(error) {
            try await Task.sleep(for: retryDelay)
            return try await work()
        }
    }
}
