import XCTest
import CairnCore
@testable import CairnStorage

final class TaskDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var workspaceId: UUID!
    private var sessionId1: UUID!
    private var sessionId2: UUID!
    private let ts0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/w",
                           createdAt: ts0, lastActiveAt: ts0)
        try await WorkspaceDAO.upsert(ws, in: db)
        workspaceId = ws.id

        let s1 = Session(workspaceId: ws.id, jsonlPath: "/1", startedAt: ts0)
        let s2 = Session(workspaceId: ws.id, jsonlPath: "/2", startedAt: ts0)
        try await SessionDAO.upsert(s1, in: db)
        try await SessionDAO.upsert(s2, in: db)
        sessionId1 = s1.id
        sessionId2 = s2.id
    }

    func test_upsert_singleSession_1to1() async throws {
        let task = CairnTask(workspaceId: workspaceId, title: "T",
                             sessionIds: [sessionId1],
                             createdAt: ts0, updatedAt: ts0)
        try await TaskDAO.upsert(task, in: db)
        let fetched = try await TaskDAO.fetch(id: task.id, in: db)
        XCTAssertEqual(fetched, task)
    }

    func test_upsert_multiSession_replacesJoinRows() async throws {
        let id = UUID()
        let v1 = CairnTask(id: id, workspaceId: workspaceId, title: "T",
                           sessionIds: [sessionId1],
                           createdAt: ts0, updatedAt: ts0)
        try await TaskDAO.upsert(v1, in: db)

        let v2 = CairnTask(id: id, workspaceId: workspaceId, title: "T",
                           sessionIds: [sessionId1, sessionId2],
                           createdAt: ts0, updatedAt: ts0)
        try await TaskDAO.upsert(v2, in: db)

        let fetched = try await TaskDAO.fetch(id: id, in: db)
        XCTAssertEqual(Set(fetched?.sessionIds ?? []), Set([sessionId1, sessionId2]))
    }

    func test_upsert_emptySessionIds_ok() async throws {
        let task = CairnTask(workspaceId: workspaceId, title: "Empty",
                             sessionIds: [],
                             createdAt: ts0, updatedAt: ts0)
        try await TaskDAO.upsert(task, in: db)
        let fetched = try await TaskDAO.fetch(id: task.id, in: db)
        XCTAssertEqual(fetched?.sessionIds, [])
    }

    func test_fetchByWorkspace_andStatus() async throws {
        let active = CairnTask(workspaceId: workspaceId, title: "A",
                               status: .active, sessionIds: [],
                               createdAt: ts0, updatedAt: ts0)
        let done = CairnTask(workspaceId: workspaceId, title: "B",
                             status: .completed, sessionIds: [],
                             createdAt: ts0, updatedAt: ts0)
        try await TaskDAO.upsert(active, in: db)
        try await TaskDAO.upsert(done, in: db)

        let activeOnly = try await TaskDAO.fetchAll(
            workspaceId: workspaceId, status: .active, in: db)
        XCTAssertEqual(activeOnly.map(\.id), [active.id])
    }

    func test_delete_cascadesTaskSessions() async throws {
        let task = CairnTask(workspaceId: workspaceId, title: "T",
                             sessionIds: [sessionId1, sessionId2],
                             createdAt: ts0, updatedAt: ts0)
        try await TaskDAO.upsert(task, in: db)
        try await TaskDAO.delete(id: task.id, in: db)

        // 确认 task_sessions 行已清理
        let joinCount = try await db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task_sessions WHERE task_id = ?",
                arguments: [task.id.uuidString]
            ) ?? -1
        }
        XCTAssertEqual(joinCount, 0)
    }

    func test_codable_and_row_roundTrip_fullTask() async throws {
        // sessionIds 语义是"集合",DAO roundtrip 按字典序返回,
        // 本测试也按字典序构造,保证 Equatable 精确匹配。
        let sorted = [sessionId1!, sessionId2!].sorted { $0.uuidString < $1.uuidString }
        let task = CairnTask(
            id: UUID(),
            workspaceId: workspaceId,
            title: "完整字段",
            intent: "所有字段都有值",
            status: .completed,
            sessionIds: sorted,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_003_600),
            completedAt: Date(timeIntervalSince1970: 1_700_003_600)
        )
        try await TaskDAO.upsert(task, in: db)
        let fetched = try await TaskDAO.fetch(id: task.id, in: db)
        XCTAssertEqual(fetched, task)
    }
}
