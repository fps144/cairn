import XCTest
import CairnCore
@testable import CairnStorage

final class ApprovalDAOTests: XCTestCase {
    private var db: CairnDatabase!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
    }

    func test_upsert_andFetch_minimalFields() async throws {
        let id = UUID()
        try await ApprovalDAO.upsert(
            id: id,
            sessionId: nil,
            toolName: "Bash",
            toolInputJson: #"{"command":"ls"}"#,
            decision: "approved",
            decidedBy: "user",
            decidedAt: Date(timeIntervalSince1970: 1_700_000_000),
            reason: "routine",
            in: db
        )
        let record = try await ApprovalDAO.fetch(id: id, in: db)
        XCTAssertEqual(record?.toolName, "Bash")
        XCTAssertEqual(record?.decision, "approved")
    }
}
