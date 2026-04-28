import XCTest
@testable import CairnClaude

final class ReconcilerTests: XCTestCase {
    func test_firesCallbackAtInterval() async throws {
        let counter = AsyncCounter()
        let reconciler = Reconciler(interval: .milliseconds(50)) {
            await counter.inc()
        }
        await reconciler.start()
        try await Task.sleep(for: .milliseconds(180))
        await reconciler.stop()
        let n = await counter.value
        XCTAssertGreaterThanOrEqual(n, 2)
        XCTAssertLessThanOrEqual(n, 5)
    }

    func test_stopHaltsCallbacks() async throws {
        let counter = AsyncCounter()
        let reconciler = Reconciler(interval: .milliseconds(50)) {
            await counter.inc()
        }
        await reconciler.start()
        try await Task.sleep(for: .milliseconds(80))
        await reconciler.stop()
        let n1 = await counter.value
        try await Task.sleep(for: .milliseconds(200))
        let n2 = await counter.value
        XCTAssertEqual(n1, n2)
    }
}

private actor AsyncCounter {
    private(set) var value = 0
    func inc() { value += 1 }
}
