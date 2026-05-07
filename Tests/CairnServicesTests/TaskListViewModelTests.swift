import XCTest
import CairnCore
import CairnStorage
@testable import CairnServices

@MainActor
final class TaskListViewModelTests: XCTestCase {
    private let workspaceId = UUID()
    private let workspaceId2 = UUID()

    private func makeDB() async throws -> CairnDatabase {
        let db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        try await WorkspaceDAO.upsert(
            Workspace(id: workspaceId, name: "ws1", cwd: "/a"),
            in: db
        )
        try await WorkspaceDAO.upsert(
            Workspace(id: workspaceId2, name: "ws2", cwd: "/b"),
            in: db
        )
        return db
    }

    /// task_sessions FK 要求 session 存在。
    private func seedSession(_ id: UUID, workspaceId: UUID, in db: CairnDatabase) async throws {
        try await SessionDAO.upsert(
            Session(
                id: id,
                workspaceId: workspaceId,
                jsonlPath: "/tmp/\(id).jsonl"
            ),
            in: db
        )
    }

    func test_reload_loadsExistingTasks() async throws {
        let db = try await makeDB()
        let sid = UUID()
        try await seedSession(sid, workspaceId: workspaceId, in: db)
        let t = CairnTask(workspaceId: workspaceId, title: "X", sessionIds: [sid])
        try await TaskDAO.upsert(t, in: db)

        let vm = TaskListViewModel(database: db)
        await vm.reload(workspaceId: workspaceId)

        XCTAssertEqual(vm.tasks.count, 1)
        XCTAssertEqual(vm.tasks.first?.id, t.id)
        XCTAssertEqual(vm.currentWorkspaceId, workspaceId)
    }

    func test_upsert_inserts_atTop() async throws {
        let db = try await makeDB()
        let vm = TaskListViewModel(database: db)
        await vm.reload(workspaceId: workspaceId)

        // upsert 不落 DB(只动 vm.tasks 内存),不需要 seed session
        let t1 = CairnTask(workspaceId: workspaceId, title: "first", sessionIds: [UUID()])
        let t2 = CairnTask(workspaceId: workspaceId, title: "second", sessionIds: [UUID()])
        vm.upsert(t1)
        vm.upsert(t2)

        // 后插的在顶
        XCTAssertEqual(vm.tasks.first?.id, t2.id)
        XCTAssertEqual(vm.tasks.count, 2)
    }

    func test_upsert_ignoresOtherWorkspace() async throws {
        let db = try await makeDB()
        let vm = TaskListViewModel(database: db)
        await vm.reload(workspaceId: workspaceId)

        let foreign = CairnTask(workspaceId: workspaceId2, title: "x", sessionIds: [UUID()])
        vm.upsert(foreign)

        XCTAssertTrue(vm.tasks.isEmpty)
    }

    func test_highlightedTaskId_basedOnActiveSession() async throws {
        let db = try await makeDB()
        let sid = UUID()
        try await seedSession(sid, workspaceId: workspaceId, in: db)
        let t = CairnTask(workspaceId: workspaceId, title: "T", sessionIds: [sid])
        try await TaskDAO.upsert(t, in: db)

        let vm = TaskListViewModel(database: db)
        await vm.reload(workspaceId: workspaceId)

        XCTAssertEqual(vm.highlightedTaskId(forActiveSessionId: sid), t.id)
        XCTAssertNil(vm.highlightedTaskId(forActiveSessionId: nil))
        XCTAssertNil(vm.highlightedTaskId(forActiveSessionId: UUID()))
    }
}
