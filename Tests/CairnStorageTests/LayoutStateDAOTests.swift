import XCTest
import CairnCore
@testable import CairnStorage

final class LayoutStateDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var workspaceId: UUID!
    private let ts0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/w", createdAt: ts0, lastActiveAt: ts0)
        try await WorkspaceDAO.upsert(ws, in: db)
        workspaceId = ws.id
    }

    func test_upsert_andFetch() async throws {
        let payload = #"{"tabs":[{"id":"t1","active":true}]}"#
        try await LayoutStateDAO.upsert(
            workspaceId: workspaceId,
            layoutJson: payload,
            updatedAt: Date(timeIntervalSince1970: 1),
            in: db
        )
        let result = try await LayoutStateDAO.fetch(
            workspaceId: workspaceId, in: db)!
        XCTAssertEqual(result.layoutJson, payload)
        XCTAssertEqual(result.updatedAt, Date(timeIntervalSince1970: 1))
    }

    func test_fetchMissing_returnsNil() async throws {
        let result = try await LayoutStateDAO.fetch(
            workspaceId: UUID(), in: db)
        XCTAssertNil(result)
    }
}
