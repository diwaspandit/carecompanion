import XCTest
@testable import CareCore

final class TransientRetryTests: XCTestCase {
    func testDroppedConnectionIsRetriedOnce() async throws {
        var attempts = 0
        let value = try await TransientRetry.run(retryDelay: .zero) { () async throws -> String in
            attempts += 1
            if attempts == 1 { throw URLError(.networkConnectionLost) }
            return "saved"
        }
        XCTAssertEqual(value, "saved")
        XCTAssertEqual(attempts, 2)
    }

    func testNonTransientErrorsAreNotRetried() async {
        var attempts = 0
        do {
            _ = try await TransientRetry.run(retryDelay: .zero) { () async throws -> Int in
                attempts += 1
                throw CareServiceError.unauthorized
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(error as? CareServiceError, .unauthorized)
        }
        XCTAssertEqual(attempts, 1)
    }

    func testGivesUpAfterSecondTransientFailure() async {
        var attempts = 0
        do {
            _ = try await TransientRetry.run(retryDelay: .zero) { () async throws -> Int in
                attempts += 1
                throw URLError(.timedOut)
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(attempts, 2)
    }

    func testOfflineIsNotTreatedAsTransient() {
        XCTAssertFalse(TransientRetry.isTransient(URLError(.notConnectedToInternet)))
        XCTAssertTrue(TransientRetry.isTransient(URLError(.networkConnectionLost)))
    }
}
