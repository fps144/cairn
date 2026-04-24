import XCTest
@testable import CairnCore

final class CairnTaskTests: XCTestCase {
    func test_init_v1_hasSingleSession() {
        let sessionId = UUID()
        let task = CairnTask(
            workspaceId: UUID(),
            title: "Refactor auth",
            sessionIds: [sessionId]
        )
        XCTAssertEqual(task.sessionIds.count, 1,
                       "spec §2.2 说 v1 UI 默认 Task has one Session(1:1)")
        XCTAssertEqual(task.sessionIds.first, sessionId)
        XCTAssertEqual(task.status, .active)
        XCTAssertNil(task.intent)
        XCTAssertNil(task.completedAt)
    }

    func test_taskStatus_allCases() {
        XCTAssertEqual(Set(TaskStatus.allCases.map(\.rawValue)),
                       ["active", "completed", "abandoned", "archived"])
    }

    func test_codable_roundTrip_completed() throws {
        let original = CairnTask(
            id: UUID(),
            workspaceId: UUID(),
            title: "Implement M1.1",
            intent: "Fill CairnCore with real data types",
            status: .completed,
            sessionIds: [UUID(), UUID()],  // 测试 >1 session 也能序列化
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_010_000),
            completedAt: Date(timeIntervalSince1970: 1_700_010_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CairnTask.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
