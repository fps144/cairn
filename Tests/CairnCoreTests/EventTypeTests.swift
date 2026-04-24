import XCTest
@testable import CairnCore

final class EventTypeTests: XCTestCase {
    func test_allCases_hasTwelveMembers() {
        XCTAssertEqual(EventType.allCases.count, 12,
                       "spec §2.3:type 封闭 12 种(v1 活跃 10 + v1.1 预留 2)")
    }

    func test_rawValues_matchSpec() {
        XCTAssertEqual(Set(EventType.allCases.map(\.rawValue)), Set([
            "user_message",
            "assistant_text",
            "assistant_thinking",
            "tool_use",
            "tool_result",
            "api_usage",
            "compact_boundary",
            "error",
            "plan_updated",
            "session_boundary",
            "approval_requested",
            "approval_decided",
        ]))
    }

    func test_codable_roundTrip() throws {
        for caseValue in EventType.allCases {
            let data = try JSONEncoder().encode(caseValue)
            let decoded = try JSONDecoder().decode(EventType.self, from: data)
            XCTAssertEqual(caseValue, decoded)
        }
    }

    func test_v1Reserved_vs_v11Active() {
        // v1.1 预留:approval_requested, approval_decided
        let v11Reserved: Set<EventType> = [.approvalRequested, .approvalDecided]
        XCTAssertEqual(v11Reserved.count, 2)
        let v1Active = Set(EventType.allCases).subtracting(v11Reserved)
        XCTAssertEqual(v1Active.count, 10)
    }
}
