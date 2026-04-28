import XCTest
import CairnCore
@testable import CairnClaude

final class SessionRegistryTests: XCTestCase {
    func test_registerAndLookup() async throws {
        let reg = SessionRegistry()
        let sid = UUID()
        let session = Session(
            id: sid,
            workspaceId: UUID(),
            jsonlPath: "/tmp/a.jsonl",
            startedAt: Date(),
            byteOffset: 0,
            lastLineNumber: 0,
            state: .live
        )
        await reg.register(session)
        let found = await reg.lookup(path: "/tmp/a.jsonl")
        XCTAssertEqual(found?.id, sid)
    }

    func test_advanceUpdatesCursor() async throws {
        let reg = SessionRegistry()
        let sid = UUID()
        await reg.register(Session(
            id: sid, workspaceId: UUID(), jsonlPath: "/tmp/b.jsonl",
            startedAt: Date(), byteOffset: 0, lastLineNumber: 0, state: .live
        ))
        await reg.advance(sessionId: sid, newOffset: 100, linesRead: 5)
        let s = await reg.get(sessionId: sid)
        XCTAssertEqual(s?.byteOffset, 100)
        XCTAssertEqual(s?.lastLineNumber, 5)
    }

    func test_unregisterRemovesBothIndices() async throws {
        let reg = SessionRegistry()
        let sid = UUID()
        await reg.register(Session(
            id: sid, workspaceId: UUID(), jsonlPath: "/tmp/c.jsonl",
            startedAt: Date(), byteOffset: 0, lastLineNumber: 0, state: .live
        ))
        await reg.unregister(sessionId: sid)
        let byId = await reg.get(sessionId: sid)
        let byPath = await reg.lookup(path: "/tmp/c.jsonl")
        XCTAssertNil(byId)
        XCTAssertNil(byPath)
    }
}
