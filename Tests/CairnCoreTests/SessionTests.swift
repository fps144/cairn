import XCTest
@testable import CairnCore

final class SessionTests: XCTestCase {
    func test_init_defaults() {
        let session = Session(
            workspaceId: UUID(),
            jsonlPath: "/Users/sorain/.claude/projects/-hash/abc.jsonl",
            startedAt: Date()
        )
        XCTAssertEqual(session.byteOffset, 0)
        XCTAssertEqual(session.lastLineNumber, 0)
        XCTAssertNil(session.endedAt)
        XCTAssertNil(session.modelUsed)
        XCTAssertFalse(session.isImported)
        XCTAssertEqual(session.state, .live)
    }

    func test_sessionState_allCases() {
        XCTAssertEqual(Set(SessionState.allCases.map(\.rawValue)),
                       ["live", "idle", "ended", "abandoned", "crashed"])
    }

    func test_codable_roundTrip() throws {
        let original = Session(
            id: UUID(),
            workspaceId: UUID(),
            jsonlPath: "/tmp/s.jsonl",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600),
            byteOffset: 12_345,
            lastLineNumber: 67,
            modelUsed: "claude-opus-4-7",
            isImported: false,
            state: .ended
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Session.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
