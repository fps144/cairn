import XCTest
@testable import CairnClaude

final class VnodeWatcherTests: XCTestCase {
    private var tmpURL: URL!

    override func setUp() async throws {
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vnode-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: tmpURL.path, contents: Data())
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL)
    }

    func test_writeTriggersEvent() async throws {
        let watcher = try VnodeWatcher(fileURL: tmpURL)
        let stream = watcher.events()
        let task = Task { () -> VnodeWatcher.VnodeEvent? in
            for await ev in stream { return ev }
            return nil
        }

        try await Task.sleep(for: .milliseconds(100))

        let fh = try FileHandle(forWritingTo: tmpURL)
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("hello\n".utf8))
        try fh.close()

        let got = try await withTimeout(seconds: 2) {
            await task.value
        }
        guard let got = got else { XCTFail("no vnode event"); return }
        XCTAssertTrue(got == .write || got == .extend, "got \(got)")
        watcher.stop()
    }

    func test_deleteTriggersEvent() async throws {
        let watcher = try VnodeWatcher(fileURL: tmpURL)
        let stream = watcher.events()
        let task = Task { () -> [VnodeWatcher.VnodeEvent] in
            var collected: [VnodeWatcher.VnodeEvent] = []
            for await ev in stream {
                collected.append(ev)
                if collected.count >= 1 { break }
            }
            return collected
        }

        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.removeItem(at: tmpURL)

        let got = try await withTimeout(seconds: 2) { await task.value }
        XCTAssertTrue(got.contains(.delete) || got.contains(.rename))
        watcher.stop()
    }

    private func withTimeout<T: Sendable>(
        seconds: Double, _ body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
