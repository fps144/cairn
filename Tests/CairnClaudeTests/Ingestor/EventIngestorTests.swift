import XCTest
import CairnCore
import CairnStorage
@testable import CairnClaude

final class EventIngestorTests: XCTestCase {
    private var rootURL: URL!
    private var db: CairnDatabase!
    private let defaultWsId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        db = try await CairnDatabase(
            location: .inMemory, migrator: CairnStorage.makeMigrator()
        )
        try await WorkspaceDAO.upsert(
            Workspace(id: defaultWsId, name: "Default", cwd: "/tmp"), in: db
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    // MARK: - helpers

    private func makeSessionFile(_ lines: [String]) throws -> (URL, UUID) {
        let sessionId = UUID()
        let sessionDir = rootURL.appendingPathComponent("-tmp-x")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let jsonl = sessionDir.appendingPathComponent(sessionId.uuidString + ".jsonl")
        let content = lines.joined(separator: "\n") + "\n"
        FileManager.default.createFile(atPath: jsonl.path, contents: Data(content.utf8))
        return (jsonl, sessionId)
    }

    private func userLine(content: String = "hello", parentUuid: String? = "p1") -> String {
        let parent = parentUuid.map { "\"\($0)\"" } ?? "null"
        return #"{"type":"user","message":{"role":"user","content":"\#(content)"},"parentUuid":\#(parent),"timestamp":"2024-01-01T00:00:00Z","uuid":"e\#(UUID().uuidString.prefix(4))"}"#
    }

    private func assistantToolUseLine(toolUseId: String, toolName: String = "Bash") -> String {
        return #"""
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(toolUseId)","name":"\#(toolName)","input":{"command":"ls"}}],"usage":{"input_tokens":10,"output_tokens":5}},"parentUuid":"p1","timestamp":"2024-01-01T00:00:01Z","uuid":"a1"}
        """#
    }

    private func userToolResultLine(toolUseId: String, content: String = "ok", isError: Bool = false) -> String {
        let err = isError ? ",\"is_error\":true" : ""
        return #"""
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(toolUseId)","content":"\#(content)"\#(err)}]},"parentUuid":"p1","timestamp":"2024-01-01T00:00:02Z","uuid":"u1"}
        """#
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

    // MARK: - 场景

    func test_endToEnd_userMessage_persists() async throws {
        _ = try makeSessionFile([userLine(content: "hello")])

        let watcher = JSONLWatcher(database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId)
        let ingestor = EventIngestor(database: db, watcher: watcher)
        let stream = await ingestor.events()
        await ingestor.start()   // ⚠️ ingestor 先于 watcher
        try await watcher.start()
        defer { Task { await ingestor.stop(); await watcher.stop() } }

        let persisted = try await withTimeout(seconds: 5) { () -> Event? in
            for await ev in stream {
                if case .persisted(let e) = ev, e.type == .userMessage { return e }
            }
            return nil
        }
        XCTAssertNotNil(persisted)

        let inDb = try await EventDAO.fetch(sessionId: persisted!.sessionId, limit: 100, offset: 0, in: db)
        XCTAssertTrue(inDb.contains { $0.id == persisted!.id })
    }

    func test_endToEnd_toolUse_toolResult_pairs() async throws {
        _ = try makeSessionFile([
            assistantToolUseLine(toolUseId: "tu_1"),
            userToolResultLine(toolUseId: "tu_1"),
        ])

        let watcher = JSONLWatcher(database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId)
        let ingestor = EventIngestor(database: db, watcher: watcher)
        let stream = await ingestor.events()
        await ingestor.start()
        try await watcher.start()
        defer { Task { await ingestor.stop(); await watcher.stop() } }

        let pairedResult = try await withTimeout(seconds: 5) { () -> Event? in
            for await ev in stream {
                if case .persisted(let e) = ev, e.type == .toolResult, e.pairedEventId != nil {
                    return e
                }
            }
            return nil
        }
        XCTAssertNotNil(pairedResult)

        // DB 里 tool_result 的 paired_event_id 应指向 tool_use 的 id
        let allInDb = try await EventDAO.fetch(sessionId: pairedResult!.sessionId,
                                                limit: 100, offset: 0, in: db)
        let toolUse = allInDb.first { $0.type == .toolUse }
        let toolRes = allInDb.first { $0.type == .toolResult }
        XCTAssertNotNil(toolUse)
        XCTAssertNotNil(toolRes)
        XCTAssertEqual(toolRes?.pairedEventId, toolUse?.id)
    }

    func test_restore_rebuildsFromDbOnSecondStart() async throws {
        _ = try makeSessionFile([userLine()])

        // 第一轮:ingest
        do {
            let watcher = JSONLWatcher(database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId)
            let ingestor = EventIngestor(database: db, watcher: watcher)
            let stream = await ingestor.events()
            await ingestor.start()
            try await watcher.start()
            _ = try await withTimeout(seconds: 5) { () -> Bool in
                for await ev in stream {
                    if case .persisted = ev { return true }
                }
                return false
            }
            try await Task.sleep(for: .milliseconds(200))  // 等 cursor 落盘
            await ingestor.stop()
            await watcher.stop()
        }

        // 第二轮:新 ingestor,handleDiscovered 应 emit .restored
        let watcher2 = JSONLWatcher(database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId)
        let ingestor2 = EventIngestor(database: db, watcher: watcher2)
        let stream2 = await ingestor2.events()
        await ingestor2.start()
        try await watcher2.start()
        defer { Task { await ingestor2.stop(); await watcher2.stop() } }

        let restored = try await withTimeout(seconds: 5) { () -> [Event]? in
            for await ev in stream2 {
                if case .restored(_, let events) = ev { return events }
            }
            return nil
        }
        XCTAssertNotNil(restored)
        XCTAssertFalse(restored!.isEmpty, "第二轮应 restore 第一轮的 events")
    }

    func test_malformedLine_errorEvent_noRollbackOfOtherEvents() async throws {
        _ = try makeSessionFile([
            userLine(content: "good"),
            "{broken json",  // 坏行
            userLine(content: "also_good"),
        ])

        let watcher = JSONLWatcher(database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId)
        let ingestor = EventIngestor(database: db, watcher: watcher)
        let stream = await ingestor.events()
        await ingestor.start()
        try await watcher.start()
        defer { Task { await ingestor.stop(); await watcher.stop() } }

        // malformed 行 parser 返回 []+stderr warning,不应中断 batch。
        // 期望两个 good 行都 persist
        var collected: [Event] = []
        _ = try await withTimeout(seconds: 5) { () -> Bool in
            for await ev in stream {
                if case .persisted(let e) = ev {
                    collected.append(e)
                    if collected.count >= 2 { return true }
                }
            }
            return false
        }
        XCTAssertGreaterThanOrEqual(collected.count, 2)
    }

    func test_cursor_advances_on_ingest() async throws {
        let (_, sessionId) = try makeSessionFile([userLine()])

        let watcher = JSONLWatcher(database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId)
        let ingestor = EventIngestor(database: db, watcher: watcher)
        let stream = await ingestor.events()
        await ingestor.start()
        try await watcher.start()
        defer { Task { await ingestor.stop(); await watcher.stop() } }

        _ = try await withTimeout(seconds: 5) { () -> Bool in
            for await ev in stream {
                if case .persisted = ev { return true }
            }
            return false
        }
        try await Task.sleep(for: .milliseconds(200))

        let saved = try await SessionDAO.fetch(id: sessionId, in: db)
        XCTAssertNotNil(saved)
        XCTAssertGreaterThan(saved!.byteOffset, 0, "cursor byte_offset 应推进")
        XCTAssertGreaterThan(saved!.lastLineNumber, 0, "cursor lastLineNumber 应推进")
    }
}
