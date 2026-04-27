import XCTest
import CairnCore
@testable import CairnStorage

final class EventDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var sessionId: UUID!
    private let ts0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(name: "W", cwd: "/w",
                           createdAt: ts0, lastActiveAt: ts0)
        try await WorkspaceDAO.upsert(ws, in: db)
        let s = Session(workspaceId: ws.id, jsonlPath: "/s", startedAt: ts0)
        try await SessionDAO.upsert(s, in: db)
        sessionId = s.id
    }

    func test_upsert_andFetch_fullFields() async throws {
        let event = Event(
            id: UUID(),
            sessionId: sessionId,
            type: .toolUse,
            category: .shell,
            toolName: "Bash",
            toolUseId: "toolu_01",
            pairedEventId: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            lineNumber: 42,
            blockIndex: 0,
            summary: "ls -la",
            rawPayloadJson: #"{"type":"tool_use"}"#,
            byteOffsetInJsonl: 12345
        )
        try await EventDAO.upsert(event, in: db)
        let fetched = try await EventDAO.fetch(id: event.id, in: db)
        XCTAssertEqual(fetched, event)
    }

    func test_upsertBatch_allInOneTransaction() async throws {
        let events = (1...100).map { i in
            Event(sessionId: sessionId, type: .assistantText,
                  timestamp: Date(timeIntervalSince1970: Double(i)),
                  lineNumber: Int64(i), summary: "msg \(i)")
        }
        try await EventDAO.upsertBatch(events, in: db)
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
        }
        XCTAssertEqual(count, 100)
    }

    func test_fetchBySession_pagination() async throws {
        let events = (1...50).map { i in
            Event(sessionId: sessionId, type: .assistantText,
                  timestamp: Date(timeIntervalSince1970: Double(i)),
                  lineNumber: Int64(i), summary: "msg \(i)")
        }
        try await EventDAO.upsertBatch(events, in: db)

        let page1 = try await EventDAO.fetch(
            sessionId: sessionId, limit: 20, offset: 0, in: db)
        let page2 = try await EventDAO.fetch(
            sessionId: sessionId, limit: 20, offset: 20, in: db)

        XCTAssertEqual(page1.count, 20)
        XCTAssertEqual(page2.count, 20)
        XCTAssertEqual(page1.first?.lineNumber, 1,
                       "应按 (line_number, block_index) 升序")
        XCTAssertEqual(page1.last?.lineNumber, 20)
        XCTAssertEqual(page2.first?.lineNumber, 21)
    }

    func test_fetchByToolUseId_forPairing() async throws {
        let use = Event(sessionId: sessionId, type: .toolUse,
                        toolName: "Read", toolUseId: "t1",
                        timestamp: ts0, lineNumber: 1, summary: "read")
        let result = Event(sessionId: sessionId, type: .toolResult,
                           toolUseId: "t1",
                           timestamp: ts0, lineNumber: 2, summary: "result")
        try await EventDAO.upsert(use, in: db)
        try await EventDAO.upsert(result, in: db)

        let matches = try await EventDAO.fetchByToolUseId("t1", in: db)
        XCTAssertEqual(Set(matches.map(\.id)), Set([use.id, result.id]))
    }

    func test_fetchByType() async throws {
        let err = Event(sessionId: sessionId, type: .error,
                        timestamp: ts0, lineNumber: 1, summary: "err")
        let txt = Event(sessionId: sessionId, type: .assistantText,
                        timestamp: ts0, lineNumber: 2, summary: "ok")
        try await EventDAO.upsert(err, in: db)
        try await EventDAO.upsert(txt, in: db)

        let errors = try await EventDAO.fetchByType(
            .error, sessionId: sessionId, in: db)
        XCTAssertEqual(errors.map(\.id), [err.id])
    }

    func test_delete_cascadesFromSession() async throws {
        let event = Event(sessionId: sessionId, type: .userMessage,
                          timestamp: ts0, lineNumber: 1, summary: "hi")
        try await EventDAO.upsert(event, in: db)
        try await SessionDAO.delete(id: sessionId, in: db)

        let fetched = try await EventDAO.fetch(id: event.id, in: db)
        XCTAssertNil(fetched, "session CASCADE 应带走 events")
    }
}
