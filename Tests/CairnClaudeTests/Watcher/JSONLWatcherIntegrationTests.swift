import XCTest
import CairnCore
import CairnStorage
@testable import CairnClaude

final class JSONLWatcherIntegrationTests: XCTestCase {
    private var rootURL: URL!
    private var db: CairnDatabase!
    private let defaultWsId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        db = try await CairnDatabase(
            location: .inMemory, migrator: CairnStorage.makeMigrator()
        )
        try await WorkspaceDAO.upsert(
            Workspace(id: defaultWsId, name: "Default", cwd: NSHomeDirectory()),
            in: db
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func test_discoversExistingSessionOnStart() async throws {
        let sessionDir = rootURL.appendingPathComponent("-Users-alice")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent("s1.jsonl")
        try "{\"type\":\"user\"}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        let watcher = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let stream = await watcher.events()
        try await watcher.start()
        defer { Task { await watcher.stop() } }

        let first = try await withTimeout(seconds: 3) { () -> JSONLWatcher.WatcherEvent? in
            for await ev in stream {
                if case .discovered = ev { return ev }
            }
            return nil
        }
        guard case .discovered(let session) = first else {
            return XCTFail("no discovery")
        }
        // macOS tmp 路径比较要用 resolved symlinks —— enumerator 可能返回
        // /private/var/... 而测试的 jsonl.path 是 /var/...
        let resolvedExpected = URL(fileURLWithPath: jsonl.path)
            .resolvingSymlinksInPath().path
        let resolvedActual = URL(fileURLWithPath: session.jsonlPath)
            .resolvingSymlinksInPath().path
        XCTAssertEqual(resolvedActual, resolvedExpected)
    }

    func test_yieldsNewLinesOnAppend() async throws {
        let sessionDir = rootURL.appendingPathComponent("-Users-bob")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent("s2.jsonl")
        try "{\"type\":\"user\"}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        let watcher = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let stream = await watcher.events()
        try await watcher.start()
        defer { Task { await watcher.stop() } }

        _ = try await withTimeout(seconds: 3) { () -> Bool in
            for await ev in stream {
                if case .discovered = ev { return true }
            }
            return false
        }

        try await Task.sleep(for: .milliseconds(100))

        let fh = try FileHandle(forWritingTo: jsonl)
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("{\"type\":\"assistant\"}\n".utf8))
        try fh.close()

        // discover 时 byteOffset=0,首次 ingest 会把**已有全部内容**都读一遍
        // (包括 append 前的 {"type":"user"})—— 这是 watcher 预期行为:
        // discover 不等于"视已有内容为已读",给下游 parser 完整上下文。
        // 断言点:新 append 的 assistant 行必须在 lines 里出现。
        let lines = try await withTimeout(seconds: 5) { () -> [String]? in
            for await ev in stream {
                if case .lines(_, let ls, _) = ev, ls.contains(#"{"type":"assistant"}"#) {
                    return ls
                }
            }
            return nil
        }
        XCTAssertNotNil(lines)
        XCTAssertTrue(lines!.contains(#"{"type":"assistant"}"#))
    }

    func test_persistsCursorToDb() async throws {
        let sessionDir = rootURL.appendingPathComponent("-Users-carol")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent("s3.jsonl")
        try "{\"type\":\"user\"}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        let watcher = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let stream = await watcher.events()
        try await watcher.start()
        defer { Task { await watcher.stop() } }

        let task = Task { () -> UUID? in
            for await ev in stream {
                if case .lines(let sid, _, _) = ev { return sid }
            }
            return nil
        }

        try await Task.sleep(for: .milliseconds(300))
        let fh = try FileHandle(forWritingTo: jsonl)
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("{\"type\":\"assistant\"}\n".utf8))
        try fh.close()

        let sid = try await withTimeout(seconds: 5) { await task.value }
        XCTAssertNotNil(sid)

        // 等 async updateCursor 落盘
        try await Task.sleep(for: .milliseconds(200))

        let saved = try await SessionDAO.fetch(id: sid!, in: db)
        XCTAssertNotNil(saved)
        XCTAssertGreaterThan(saved!.byteOffset, 0)
        XCTAssertGreaterThan(saved!.lastLineNumber, 0)
    }

    /// 回归测试:**必须**证明 discover 不会把已有 byte_offset 覆盖为 0。
    /// 首次 watcher 读完几行 → stop → 再起新 watcher,discover 同一文件,
    /// 应复用 byte_offset,不重复发已读过的行。
    func test_reusesCursorOnRediscover() async throws {
        let sessionDir = rootURL.appendingPathComponent("-Users-reuse")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent(UUID().uuidString + ".jsonl")
        try "{\"a\":1}\n{\"b\":2}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        let sessionId = UUID(uuidString: jsonl.deletingPathExtension().lastPathComponent)!

        // 第一轮:read 两行 → stop
        do {
            let w1 = JSONLWatcher(
                database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
            )
            let stream = await w1.events()
            try await w1.start()
            let collect = Task { () -> [String] in
                var acc: [String] = []
                for await ev in stream {
                    if case .lines(_, let ls, _) = ev { acc.append(contentsOf: ls) }
                    if acc.count >= 2 { break }
                }
                return acc
            }
            try await Task.sleep(for: .milliseconds(300))
            let fh = try FileHandle(forWritingTo: jsonl)
            try fh.seekToEnd()
            try fh.write(contentsOf: Data("{\"c\":3}\n".utf8))
            try fh.close()
            let got = try await withTimeout(seconds: 5) { await collect.value }
            XCTAssertTrue(got.contains(#"{"a":1}"#) && got.contains(#"{"b":2}"#))
            // 等 pending async updateCursor 落盘,否则 stop 后 DB byte_offset 可能还是旧值
            try await Task.sleep(for: .milliseconds(300))
            await w1.stop()
        }

        let saved = try await SessionDAO.fetch(id: sessionId, in: db)
        XCTAssertNotNil(saved)
        let offsetAfterFirstRun = saved!.byteOffset
        XCTAssertGreaterThan(offsetAfterFirstRun, 0)

        // 第二轮:新 watcher 实例,不应重发已读过的行,不应把 byte_offset 重置
        let w2 = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let stream2 = await w2.events()
        try await w2.start()
        defer { Task { await w2.stop() } }

        let collect2 = Task { () -> [String] in
            var acc: [String] = []
            for await ev in stream2 {
                if case .lines(_, let ls, _) = ev { acc.append(contentsOf: ls) }
                if acc.count > 10 { break }
            }
            return acc
        }
        try await Task.sleep(for: .seconds(1))
        collect2.cancel()
        let extra = await collect2.value
        XCTAssertTrue(extra.isEmpty, "should not re-yield already-read lines, got \(extra)")

        let saved2 = try await SessionDAO.fetch(id: sessionId, in: db)
        XCTAssertEqual(saved2?.byteOffset, offsetAfterFirstRun)
    }

    /// 同 path 得同 UUID;不同 path 得不同 UUID。跨启动的 cursor 复用
     /// 依赖此性质(subagents 子目录文件名 `agent-xxx` 不是 UUID 格式)。
    func test_stableUUID_deterministic() {
        let u1 = JSONLWatcher.stableUUID(from: "/tmp/a/b.jsonl")
        let u2 = JSONLWatcher.stableUUID(from: "/tmp/a/b.jsonl")
        let u3 = JSONLWatcher.stableUUID(from: "/tmp/a/c.jsonl")
        XCTAssertEqual(u1, u2)
        XCTAssertNotEqual(u1, u3)
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
