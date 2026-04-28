import XCTest
@testable import CairnClaude

final class FSEventsWatcherTests: XCTestCase {
    private var rootURL: URL!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func test_detectsNewJsonlFile() async throws {
        let watcher = try FSEventsWatcher(rootURL: rootURL)
        let stream = watcher.events()
        try watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(500))

        let sessionDir = rootURL.appendingPathComponent("-Users-alice-proj")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent("some-session.jsonl")
        // 用 createFile + append 模拟 Claude Code 的 O_CREAT|O_APPEND 写法,
        // 触发 FSEvents 的 Created flag。atomically:true 会走 tmp + rename,
        // 事件变成 Renamed,测试命中不了 .created 分支。
        FileManager.default.createFile(atPath: jsonl.path, contents: Data("hello\n".utf8))

        let event = try await withTimeout(seconds: 5) { () -> FSEventsWatcher.FSEvent? in
            for await ev in stream {
                if case .created(let url) = ev, url.lastPathComponent.hasSuffix(".jsonl") {
                    return ev
                }
            }
            return nil
        }
        XCTAssertNotNil(event)
        if case .created(let url) = event {
            XCTAssertEqual(url.lastPathComponent, "some-session.jsonl")
        }
    }

    func test_filtersOutNonJsonl() async throws {
        let watcher = try FSEventsWatcher(rootURL: rootURL)
        let stream = watcher.events()
        try watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(500))

        let other = rootURL.appendingPathComponent("ignore.txt")
        FileManager.default.createFile(atPath: other.path, contents: Data("x".utf8))

        // 1 秒窗口内 collect 所有事件(for-await 永远不会自己 return,
        // 需显式用 Task + cancel 终止,而不是给 timeout body 套 for-await
        // —— 后者的 body 会一直等导致 timeout 抛 CancellationError 把 test 挂掉)。
        let collect = Task { () -> [FSEventsWatcher.FSEvent] in
            var acc: [FSEventsWatcher.FSEvent] = []
            for await ev in stream {
                acc.append(ev)
                if acc.count > 20 { break }
            }
            return acc
        }
        try await Task.sleep(for: .seconds(1))
        collect.cancel()
        let events = await collect.value
        let jsonlEvents = events.filter {
            if case .created(let url) = $0 { return url.lastPathComponent.hasSuffix(".jsonl") }
            return false
        }
        XCTAssertTrue(jsonlEvents.isEmpty, "expected no .jsonl events, got \(jsonlEvents)")
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
