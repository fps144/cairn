import XCTest
import CairnCore
import CairnClaude
import CairnStorage
@testable import CairnServices

@MainActor
final class TimelineViewModelTests: XCTestCase {
    private func makeVM() async throws -> TimelineViewModel {
        let db = try await CairnDatabase(
            location: .inMemory, migrator: CairnStorage.makeMigrator()
        )
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tvm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let defaultWsId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        try await WorkspaceDAO.upsert(
            Workspace(id: defaultWsId, name: "W", cwd: "/tmp"), in: db
        )
        let watcher = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let ingestor = EventIngestor(database: db, watcher: watcher)
        return TimelineViewModel(ingestor: ingestor)
    }

    func test_firstPersisted_setsCurrentSession() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        let e = Event(sessionId: sid, type: .userMessage,
                      timestamp: Date(), lineNumber: 1, summary: "hi")
        vm.handleForTesting(.persisted(e))
        XCTAssertEqual(vm.currentSessionId, sid)
        XCTAssertEqual(vm.events.count, 1)
    }

    func test_subsequentSameSession_appends() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        for i in 1...5 {
            let e = Event(sessionId: sid, type: .userMessage,
                          timestamp: Date(), lineNumber: Int64(i), summary: "msg \(i)")
            vm.handleForTesting(.persisted(e))
        }
        XCTAssertEqual(vm.events.count, 5)
        XCTAssertEqual(vm.events.map(\.lineNumber), [1,2,3,4,5])
    }

    func test_newSession_autoSwitches() async throws {
        // M2.4 T12 修订:新 session 的 .persisted 到达时 auto-switch,
        // 清空旧 events,用户新开 claude 对话能立刻在 timeline 看到。
        let vm = try await makeVM()
        let sid1 = UUID(), sid2 = UUID()
        vm.handleForTesting(.persisted(Event(
            sessionId: sid1, type: .userMessage,
            timestamp: Date(), lineNumber: 1, summary: "s1"
        )))
        XCTAssertEqual(vm.currentSessionId, sid1)
        vm.handleForTesting(.persisted(Event(
            sessionId: sid2, type: .userMessage,
            timestamp: Date(), lineNumber: 1, summary: "s2-new"
        )))
        XCTAssertEqual(vm.currentSessionId, sid2, "新 session 应 auto-switch")
        XCTAssertEqual(vm.events.count, 1)
        XCTAssertEqual(vm.events[0].summary, "s2-new")
    }

    func test_duplicateId_filtered() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        let e = Event(sessionId: sid, type: .userMessage,
                      timestamp: Date(), lineNumber: 1, summary: "dup")
        vm.handleForTesting(.persisted(e))
        vm.handleForTesting(.persisted(e))
        XCTAssertEqual(vm.events.count, 1)
    }

    func test_restored_prependsHistory_whenSessionMatches() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        // 先 live event 设定 current session
        let live = Event(id: UUID(), sessionId: sid, type: .userMessage,
                         timestamp: Date(), lineNumber: 10, summary: "live")
        vm.handleForTesting(.persisted(live))

        // restored 带历史 1-5 行
        let history = (1...5).map { i in
            Event(id: UUID(), sessionId: sid, type: .userMessage,
                  timestamp: Date(), lineNumber: Int64(i), summary: "h\(i)")
        }
        vm.handleForTesting(.restored(sessionId: sid, events: history))
        XCTAssertEqual(vm.events.count, 6)
        XCTAssertEqual(vm.events.first?.summary, "h1")  // prepend 后 h1 在最前
        XCTAssertEqual(vm.events.last?.summary, "live")
    }
}
