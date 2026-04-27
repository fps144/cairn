import XCTest
import CairnCore
@testable import CairnStorage

final class BudgetDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var taskId: UUID!
    private let ts0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/w", createdAt: ts0, lastActiveAt: ts0)
        try await WorkspaceDAO.upsert(ws, in: db)
        let task = CairnTask(workspaceId: ws.id, title: "T", sessionIds: [],
                             createdAt: ts0, updatedAt: ts0)
        try await TaskDAO.upsert(task, in: db)
        taskId = task.id
    }

    func test_upsert_withAllCaps() async throws {
        let b = Budget(
            taskId: taskId,
            maxInputTokens: 100_000,
            maxOutputTokens: 50_000,
            maxCostUSD: 5.0,
            maxWallSeconds: 3600,
            usedInputTokens: 1000,
            usedOutputTokens: 500,
            usedCostUSD: 0.25,
            usedWallSeconds: 60,
            state: .normal,
            updatedAt: ts0
        )
        try await BudgetDAO.upsert(b, in: db)
        let fetched = try await BudgetDAO.fetch(taskId: taskId, in: db)
        XCTAssertEqual(fetched, b)
    }

    func test_upsert_withAllNilCaps() async throws {
        let b = Budget(taskId: taskId, updatedAt: ts0)
        try await BudgetDAO.upsert(b, in: db)
        let fetched = try await BudgetDAO.fetch(taskId: taskId, in: db)
        XCTAssertEqual(fetched, b)
    }

    func test_fetch_returnsNilForMissing() async throws {
        let fetched = try await BudgetDAO.fetch(taskId: UUID(), in: db)
        XCTAssertNil(fetched)
    }

    func test_state_rawValueRoundtrip() async throws {
        for state in BudgetState.allCases {
            let otherTask = CairnTask(workspaceId: try await WorkspaceDAO.fetchAll(in: db).first!.id,
                                      title: "t-\(state.rawValue)", sessionIds: [],
                                      createdAt: ts0, updatedAt: ts0)
            try await TaskDAO.upsert(otherTask, in: db)
            let b = Budget(taskId: otherTask.id, state: state, updatedAt: ts0)
            try await BudgetDAO.upsert(b, in: db)
            let fetched = try await BudgetDAO.fetch(taskId: otherTask.id, in: db)
            XCTAssertEqual(fetched?.state, state)
        }
    }

    func test_delete_cascadesFromTask() async throws {
        let b = Budget(taskId: taskId, maxCostUSD: 5.0, updatedAt: ts0)
        try await BudgetDAO.upsert(b, in: db)
        try await TaskDAO.delete(id: taskId, in: db)
        let fetched = try await BudgetDAO.fetch(taskId: taskId, in: db)
        XCTAssertNil(fetched)
    }
}
