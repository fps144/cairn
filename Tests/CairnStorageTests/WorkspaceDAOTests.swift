import XCTest
import CairnCore
@testable import CairnStorage

final class WorkspaceDAOTests: XCTestCase {
    private var db: CairnDatabase!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
    }

    // 所有 Date 字段用 Date(timeIntervalSince1970: 整数秒)构造:
    // ISO-8601 round-trip 最高到毫秒精度,Date 原生含微秒,
    // 默认 `Date()` 会在 ms-precision 下丢失微秒,导致 round-trip 不完全相等。
    // 用整数秒规避此问题。

    func test_upsert_insertsNewRow() async throws {
        let ws = Workspace(
            name: "Cairn", cwd: "/Users/sorain/cairn",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastActiveAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await WorkspaceDAO.upsert(ws, in: db)
        let fetched = try await WorkspaceDAO.fetch(id: ws.id, in: db)
        XCTAssertEqual(fetched, ws)
    }

    func test_upsert_updatesExistingRow() async throws {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let v1 = Workspace(
            id: id, name: "v1", cwd: "/tmp/v1",
            createdAt: created, lastActiveAt: created
        )
        try await WorkspaceDAO.upsert(v1, in: db)
        let v2 = Workspace(
            id: id, name: "v2", cwd: "/tmp/v2",
            createdAt: created,
            lastActiveAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        try await WorkspaceDAO.upsert(v2, in: db)
        let fetched = try await WorkspaceDAO.fetch(id: id, in: db)
        XCTAssertEqual(fetched, v2)
    }

    func test_fetch_returnsNilForMissing() async throws {
        let fetched = try await WorkspaceDAO.fetch(id: UUID(), in: db)
        XCTAssertNil(fetched)
    }

    func test_fetchAll_ordersByLastActiveDesc() async throws {
        let older = Workspace(
            name: "Old", cwd: "/a",
            lastActiveAt: Date(timeIntervalSince1970: 1_000_000_000)
        )
        let newer = Workspace(
            name: "New", cwd: "/b",
            lastActiveAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        try await WorkspaceDAO.upsert(older, in: db)
        try await WorkspaceDAO.upsert(newer, in: db)
        let all = try await WorkspaceDAO.fetchAll(in: db)
        XCTAssertEqual(all.map(\.name), ["New", "Old"])
    }

    func test_delete_removesRow() async throws {
        let ws = Workspace(
            name: "X", cwd: "/x",
            createdAt: Date(timeIntervalSince1970: 1),
            lastActiveAt: Date(timeIntervalSince1970: 1)
        )
        try await WorkspaceDAO.upsert(ws, in: db)
        try await WorkspaceDAO.delete(id: ws.id, in: db)
        let fetched = try await WorkspaceDAO.fetch(id: ws.id, in: db)
        XCTAssertNil(fetched)
    }

    func test_uniqueCwd_constraint() async throws {
        // spec §D: workspaces.cwd UNIQUE
        let a = Workspace(
            name: "A", cwd: "/shared",
            createdAt: Date(timeIntervalSince1970: 1),
            lastActiveAt: Date(timeIntervalSince1970: 1)
        )
        let b = Workspace(
            name: "B", cwd: "/shared",
            createdAt: Date(timeIntervalSince1970: 1),
            lastActiveAt: Date(timeIntervalSince1970: 1)
        )
        try await WorkspaceDAO.upsert(a, in: db)
        do {
            try await WorkspaceDAO.upsert(b, in: db)
            XCTFail("应该抛 UNIQUE 约束错")
        } catch {
            // GRDB 把 SQLite error 封装为 DatabaseError;任何 Error 都算验证通过
        }
    }
}
