import XCTest
@testable import CairnCore

final class WorkspaceTests: XCTestCase {
    func test_init_preservesAllFields() {
        let id = UUID()
        let now = Date()
        let ws = Workspace(
            id: id,
            name: "MyProject",
            cwd: "/Users/sorain/myproj",
            createdAt: now,
            lastActiveAt: now,
            archivedAt: nil
        )
        XCTAssertEqual(ws.id, id)
        XCTAssertEqual(ws.name, "MyProject")
        XCTAssertEqual(ws.cwd, "/Users/sorain/myproj")
        XCTAssertEqual(ws.createdAt, now)
        XCTAssertEqual(ws.lastActiveAt, now)
        XCTAssertNil(ws.archivedAt)
    }

    func test_codable_roundTrip() throws {
        let original = Workspace(
            id: UUID(),
            name: "Cairn",
            cwd: "/tmp",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastActiveAt: Date(timeIntervalSince1970: 1_700_001_000),
            archivedAt: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workspace.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func test_equatable_byAllFields() {
        let id = UUID()
        let a = Workspace(id: id, name: "A", cwd: "/a",
                          createdAt: Date(), lastActiveAt: Date(), archivedAt: nil)
        let b = Workspace(id: id, name: "B", cwd: "/b",
                          createdAt: Date(), lastActiveAt: Date(), archivedAt: nil)
        // 按设计决策 #6,Equatable 是 Swift synthesized 的"所有字段比较"。
        // 同 id 但 name/cwd 不同 → 不相等。这保证 round-trip 测试能真实验证
        // 字段完整性(若改成 by-id 比较,round-trip 会在字段丢失时伪通过)。
        XCTAssertNotEqual(a, b)
    }
}
