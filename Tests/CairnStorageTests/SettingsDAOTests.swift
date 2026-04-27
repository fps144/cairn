import XCTest
import CairnCore
@testable import CairnStorage

final class SettingsDAOTests: XCTestCase {
    private var db: CairnDatabase!

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
    }

    func test_setAndGet() async throws {
        try await SettingsDAO.set(
            key: "terminal.font", valueJson: #""SF Mono""#, in: db)
        let val = try await SettingsDAO.get(key: "terminal.font", in: db)
        XCTAssertEqual(val, #""SF Mono""#)
    }

    func test_getMissing_returnsNil() async throws {
        let val = try await SettingsDAO.get(key: "nope", in: db)
        XCTAssertNil(val)
    }

    func test_setOverrides() async throws {
        try await SettingsDAO.set(key: "k", valueJson: "1", in: db)
        try await SettingsDAO.set(key: "k", valueJson: "2", in: db)
        let val = try await SettingsDAO.get(key: "k", in: db)
        XCTAssertEqual(val, "2")
    }
}
