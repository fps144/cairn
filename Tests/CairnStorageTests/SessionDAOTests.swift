import XCTest
import CairnCore
@testable import CairnStorage

final class SessionDAOTests: XCTestCase {
    private var db: CairnDatabase!
    private var workspaceId: UUID!
    private let ts0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        db = try await CairnDatabase(
            location: .inMemory,
            migrator: CairnStorage.makeMigrator()
        )
        let ws = Workspace(
            name: "W", cwd: "/tmp",
            createdAt: ts0, lastActiveAt: ts0
        )
        try await WorkspaceDAO.upsert(ws, in: db)
        workspaceId = ws.id
    }

    func test_upsert_insertsNewSession() async throws {
        let s = Session(workspaceId: workspaceId, jsonlPath: "/s.jsonl",
                        startedAt: ts0)
        try await SessionDAO.upsert(s, in: db)
        let fetched = try await SessionDAO.fetch(id: s.id, in: db)
        XCTAssertEqual(fetched, s)
    }

    func test_updateCursor_bumpsByteOffsetAndLine() async throws {
        let s = Session(workspaceId: workspaceId, jsonlPath: "/s.jsonl",
                        startedAt: ts0)
        try await SessionDAO.upsert(s, in: db)
        try await SessionDAO.updateCursor(
            sessionId: s.id,
            byteOffset: 12345,
            lastLineNumber: 67,
            in: db
        )
        let fetched = try await SessionDAO.fetch(id: s.id, in: db)
        XCTAssertEqual(fetched?.byteOffset, 12345)
        XCTAssertEqual(fetched?.lastLineNumber, 67)
        XCTAssertEqual(fetched?.state, .live, "updateCursor 不应改 state")
    }

    func test_fetchByWorkspace_returnsSessionsForGivenWorkspace() async throws {
        let otherWs = Workspace(
            name: "Other", cwd: "/other",
            createdAt: ts0, lastActiveAt: ts0
        )
        try await WorkspaceDAO.upsert(otherWs, in: db)

        let s1 = Session(workspaceId: workspaceId, jsonlPath: "/1.jsonl",
                         startedAt: Date(timeIntervalSince1970: 1))
        let s2 = Session(workspaceId: workspaceId, jsonlPath: "/2.jsonl",
                         startedAt: Date(timeIntervalSince1970: 2))
        let s3 = Session(workspaceId: otherWs.id, jsonlPath: "/3.jsonl",
                         startedAt: Date(timeIntervalSince1970: 3))
        for s in [s1, s2, s3] { try await SessionDAO.upsert(s, in: db) }

        let inMain = try await SessionDAO.fetchAll(workspaceId: workspaceId, in: db)
        XCTAssertEqual(Set(inMain.map(\.id)), Set([s1.id, s2.id]))
    }

    func test_fetchByState_live_idle() async throws {
        let live = Session(workspaceId: workspaceId, jsonlPath: "/live",
                           startedAt: ts0, state: .live)
        let idle = Session(workspaceId: workspaceId, jsonlPath: "/idle",
                           startedAt: ts0, state: .idle)
        let ended = Session(workspaceId: workspaceId, jsonlPath: "/ended",
                            startedAt: ts0, state: .ended)
        for s in [live, idle, ended] { try await SessionDAO.upsert(s, in: db) }

        let active = try await SessionDAO.fetchActive(in: db)
        XCTAssertEqual(Set(active.map(\.id)), Set([live.id, idle.id]),
                       "fetchActive 应命中 spec §D 的 idx_sessions_state 索引(state IN ('live','idle'))")
    }

    func test_delete_cascadesFromWorkspace() async throws {
        let s = Session(workspaceId: workspaceId, jsonlPath: "/s.jsonl",
                        startedAt: ts0)
        try await SessionDAO.upsert(s, in: db)
        // 删除 workspace → session 应 CASCADE 删除
        try await WorkspaceDAO.delete(id: workspaceId, in: db)
        let fetched = try await SessionDAO.fetch(id: s.id, in: db)
        XCTAssertNil(fetched, "spec §D workspace_id FK ON DELETE CASCADE")
    }
}
