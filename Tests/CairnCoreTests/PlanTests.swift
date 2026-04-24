import XCTest
@testable import CairnCore

final class PlanTests: XCTestCase {
    func test_planSource_allCases() {
        XCTAssertEqual(Set(PlanSource.allCases.map(\.rawValue)),
                       ["todo_write", "plan_md", "manual"])
    }

    func test_planStepStatus_allCases() {
        XCTAssertEqual(Set(PlanStepStatus.allCases.map(\.rawValue)),
                       ["pending", "in_progress", "completed"])
    }

    func test_planStepPriority_allCases() {
        XCTAssertEqual(Set(PlanStepPriority.allCases.map(\.rawValue)),
                       ["low", "medium", "high"])
    }

    func test_planStep_init_defaults() {
        let step = PlanStep(content: "Research auth libraries")
        XCTAssertEqual(step.status, .pending)
        XCTAssertEqual(step.priority, .medium)
    }

    func test_plan_codable_roundTrip() throws {
        let original = Plan(
            id: UUID(),
            taskId: UUID(),
            source: .todoWrite,
            steps: [
                PlanStep(content: "Step 1", status: .completed, priority: .high),
                PlanStep(content: "Step 2", status: .inProgress, priority: .medium),
                PlanStep(content: "Step 3", status: .pending, priority: .low),
            ],
            markdownRaw: "# My Plan\n- [x] Step 1\n- [ ] Step 2\n",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Plan.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_plan_stepsOrderPreserved() {
        let s1 = PlanStep(content: "First")
        let s2 = PlanStep(content: "Second")
        let plan = Plan(taskId: UUID(), source: .manual, steps: [s1, s2])
        XCTAssertEqual(plan.steps.map(\.content), ["First", "Second"])
    }
}
