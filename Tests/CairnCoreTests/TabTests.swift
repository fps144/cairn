import XCTest
@testable import CairnCore

final class TabTests: XCTestCase {
    func test_init_preservesAllFields() {
        let id = UUID()
        let workspaceId = UUID()
        let tab = Tab(
            id: id,
            workspaceId: workspaceId,
            title: "~/myproj (zsh)",
            ptyPid: 12345,
            state: .active
        )
        XCTAssertEqual(tab.id, id)
        XCTAssertEqual(tab.workspaceId, workspaceId)
        XCTAssertEqual(tab.title, "~/myproj (zsh)")
        XCTAssertEqual(tab.ptyPid, 12345)
        XCTAssertEqual(tab.state, .active)
    }

    func test_tabState_rawValues() {
        XCTAssertEqual(TabState.active.rawValue, "active")
        XCTAssertEqual(TabState.closed.rawValue, "closed")
        XCTAssertEqual(TabState.allCases.count, 2)
    }

    func test_codable_roundTrip_withNilPtyPid() throws {
        let original = Tab(
            id: UUID(),
            workspaceId: UUID(),
            title: "Closed tab",
            ptyPid: nil,
            state: .closed
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
