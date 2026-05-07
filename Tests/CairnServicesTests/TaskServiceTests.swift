import XCTest
import CairnCore
import CairnStorage
@testable import CairnServices

final class TaskServiceTests: XCTestCase {
    private let workspaceId = UUID()

    private func makeDB() async throws -> CairnDatabase {
        let db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(id: workspaceId, name: "test", cwd: "/tmp/ws")
        try await WorkspaceDAO.upsert(ws, in: db)
        return db
    }

    /// task_sessions FK 要求 session 存在。spec §D 的 schema 是真实约束。
    private func seedSession(_ id: UUID, in db: CairnDatabase) async throws {
        let s = Session(
            id: id,
            workspaceId: workspaceId,
            jsonlPath: "/tmp/\(id).jsonl"
        )
        try await SessionDAO.upsert(s, in: db)
    }

    // MARK: - makeTitle 派生(纯函数,4 tests)

    func test_makeTitle_withCwd_lastComponent() {
        let title = TaskService.makeTitle(
            cwd: "/Users/x/projects/cairn",
            now: Date(timeIntervalSince1970: 1714492800)
        )
        XCTAssertTrue(title.hasPrefix("cairn @ "), "实际:\(title)")
    }

    func test_makeTitle_withNilCwd_fallbackUntitled() {
        let title = TaskService.makeTitle(cwd: nil, now: Date())
        XCTAssertTrue(title.hasPrefix("Untitled @ "), "实际:\(title)")
    }

    func test_makeTitle_withEmptyCwd_fallbackUntitled() {
        let title = TaskService.makeTitle(cwd: "", now: Date())
        XCTAssertTrue(title.hasPrefix("Untitled @ "), "实际:\(title)")
    }

    func test_makeTitle_truncatesAt60Chars() {
        let long = "/" + String(repeating: "a", count: 80)
        let title = TaskService.makeTitle(cwd: long, now: Date())
        XCTAssertLessThanOrEqual(title.count, 60)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    // MARK: - findOrCreate(异步 + DAO,3 tests)

    func test_findOrCreate_newSession_createsTask() async throws {
        let db = try await makeDB()
        let sessionId = UUID()
        try await seedSession(sessionId, in: db)
        let task = try await TaskService.findOrCreate(
            sessionId: sessionId,
            workspaceId: workspaceId,
            cwd: "/Users/x/cairn",
            in: db
        )
        XCTAssertEqual(task.workspaceId, workspaceId)
        XCTAssertEqual(task.sessionIds, [sessionId])
        XCTAssertEqual(task.status, .active)
        XCTAssertTrue(task.title.hasPrefix("cairn @ "))
    }

    func test_findOrCreate_existingSession_returnsSame() async throws {
        let db = try await makeDB()
        let sessionId = UUID()
        try await seedSession(sessionId, in: db)
        let first = try await TaskService.findOrCreate(
            sessionId: sessionId, workspaceId: workspaceId, cwd: "/a", in: db
        )
        // 第二次给不同 cwd:不应"重新派生"title,只返回已存在的 task
        let second = try await TaskService.findOrCreate(
            sessionId: sessionId, workspaceId: workspaceId, cwd: "/b", in: db
        )
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.title, second.title)
    }

    func test_findOrCreate_persistsAndRoundtrips() async throws {
        let db = try await makeDB()
        let sessionId = UUID()
        try await seedSession(sessionId, in: db)
        let created = try await TaskService.findOrCreate(
            sessionId: sessionId, workspaceId: workspaceId, cwd: "/x", in: db
        )
        let fetched = try await TaskDAO.fetchTaskBySessionId(sessionId, in: db)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, created.id)
        XCTAssertEqual(fetched?.sessionIds, [sessionId])
    }
}
