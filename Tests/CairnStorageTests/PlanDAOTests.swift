import XCTest
import CairnCore
@testable import CairnStorage

final class PlanDAOTests: XCTestCase {
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

    func test_upsert_withEmptySteps() async throws {
        let plan = Plan(taskId: taskId, source: .manual, steps: [],
                        updatedAt: ts0)
        try await PlanDAO.upsert(plan, in: db)
        let fetched = try await PlanDAO.fetch(id: plan.id, in: db)
        XCTAssertEqual(fetched, plan)
    }

    func test_upsert_withMultiStepsAllFields() async throws {
        let plan = Plan(
            id: UUID(),
            taskId: taskId,
            source: .todoWrite,
            steps: [
                PlanStep(content: "S1", status: .completed, priority: .high),
                PlanStep(content: "S2", status: .inProgress, priority: .medium),
                PlanStep(content: "S3", status: .pending, priority: .low),
            ],
            markdownRaw: "# My Plan\n- [x] S1\n",
            updatedAt: ts0
        )
        try await PlanDAO.upsert(plan, in: db)
        let fetched = try await PlanDAO.fetch(id: plan.id, in: db)
        XCTAssertEqual(fetched, plan)
    }

    func test_fetchByTask_latestFirst() async throws {
        let old = Plan(taskId: taskId, source: .planMd,
                       updatedAt: Date(timeIntervalSince1970: 1))
        let newer = Plan(taskId: taskId, source: .manual,
                         updatedAt: Date(timeIntervalSince1970: 2))
        try await PlanDAO.upsert(old, in: db)
        try await PlanDAO.upsert(newer, in: db)
        let plans = try await PlanDAO.fetchByTask(taskId: taskId, in: db)
        XCTAssertEqual(plans.map(\.id), [newer.id, old.id])
    }

    func test_delete() async throws {
        let plan = Plan(taskId: taskId, source: .manual, updatedAt: ts0)
        try await PlanDAO.upsert(plan, in: db)
        try await PlanDAO.delete(id: plan.id, in: db)
        let fetched = try await PlanDAO.fetch(id: plan.id, in: db)
        XCTAssertNil(fetched)
    }

    func test_cascadeFromTask() async throws {
        let plan = Plan(taskId: taskId, source: .manual, updatedAt: ts0)
        try await PlanDAO.upsert(plan, in: db)
        try await TaskDAO.delete(id: taskId, in: db)
        let fetched = try await PlanDAO.fetch(id: plan.id, in: db)
        XCTAssertNil(fetched)
    }
}
