import XCTest
@testable import CairnCore

final class BudgetTests: XCTestCase {
    func test_init_defaults_allUsedZero() {
        let budget = Budget(taskId: UUID())
        XCTAssertEqual(budget.usedInputTokens, 0)
        XCTAssertEqual(budget.usedOutputTokens, 0)
        XCTAssertEqual(budget.usedCostUSD, 0.0)
        XCTAssertEqual(budget.usedWallSeconds, 0)
        XCTAssertEqual(budget.state, .normal)
        XCTAssertNil(budget.maxInputTokens)
    }

    func test_budgetState_allCases() {
        XCTAssertEqual(Set(BudgetState.allCases.map(\.rawValue)),
                       ["normal", "warning80", "exceeded", "paused"])
    }

    func test_computeState_noCaps_alwaysNormal() {
        // 无 pre-commitment → 永远 .normal(观察模式)
        let budget = Budget(
            taskId: UUID(),
            usedInputTokens: 1_000_000,
            usedOutputTokens: 500_000,
            usedCostUSD: 100.0,
            usedWallSeconds: 999999
        )
        XCTAssertEqual(budget.computeState(), .normal)
    }

    func test_computeState_costUnderWarning() {
        let budget = Budget(
            taskId: UUID(),
            maxCostUSD: 10.0,
            usedCostUSD: 5.0  // 50%
        )
        XCTAssertEqual(budget.computeState(), .normal)
    }

    func test_computeState_costAt80_triggersWarning() {
        let budget = Budget(
            taskId: UUID(),
            maxCostUSD: 10.0,
            usedCostUSD: 8.0  // exactly 80%
        )
        XCTAssertEqual(budget.computeState(), .warning80)
    }

    func test_computeState_costOver100_exceeded() {
        let budget = Budget(
            taskId: UUID(),
            maxCostUSD: 10.0,
            usedCostUSD: 10.5
        )
        XCTAssertEqual(budget.computeState(), .exceeded)
    }

    func test_computeState_anyCapExceeded_exceeded() {
        // 任何一个 cap 超过 100% 都触发 exceeded(不是任意 80% 触发 warning)
        let budget = Budget(
            taskId: UUID(),
            maxInputTokens: 1000,
            maxCostUSD: 10.0,
            usedInputTokens: 1500,  // exceeded on tokens
            usedCostUSD: 3.0  // normal on cost
        )
        XCTAssertEqual(budget.computeState(), .exceeded)
    }

    func test_computeState_pausedIsSticky() {
        // paused 不由 computeState 自动恢复;它是手动状态
        let budget = Budget(
            taskId: UUID(),
            maxCostUSD: 10.0,
            usedCostUSD: 1.0,
            state: .paused
        )
        XCTAssertEqual(budget.computeState(), .paused,
                       "paused 由用户手动设置,computeState 不应自动恢复")
    }

    func test_codable_roundTrip() throws {
        let original = Budget(
            taskId: UUID(),
            maxInputTokens: 100_000,
            maxOutputTokens: 50_000,
            maxCostUSD: 5.00,
            maxWallSeconds: 3600,
            usedInputTokens: 12_345,
            usedOutputTokens: 6_789,
            usedCostUSD: 0.68,
            usedWallSeconds: 120,
            state: .normal,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Budget.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
