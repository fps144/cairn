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

    // MARK: - M2.5 toggle 测试

    func test_toggle_flipsExpandedState() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        let use = Event(
            sessionId: sid, type: .toolUse, category: .shell,
            toolName: "Bash", toolUseId: "tu_1",
            timestamp: Date(), lineNumber: 1, summary: "Bash"
        )
        vm.handleForTesting(.persisted(use))
        let entry = vm.entries[0]
        // toolCard 默认折叠
        XCTAssertFalse(vm.isExpanded(entry))
        vm.toggle(entry.id)
        XCTAssertTrue(vm.isExpanded(entry))
        vm.toggle(entry.id)
        XCTAssertFalse(vm.isExpanded(entry))
    }

    func test_isExpanded_defaultRules() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        // userMessage 默认展开(非可折叠)
        let user = Event(sessionId: sid, type: .userMessage,
                         timestamp: Date(), lineNumber: 1, summary: "hi")
        vm.handleForTesting(.persisted(user))
        let userEntry = vm.entries.last!
        XCTAssertTrue(vm.isExpanded(userEntry), "userMessage 默认展开")

        // thinking 默认折叠
        let think = Event(sessionId: sid, type: .assistantThinking,
                          timestamp: Date(), lineNumber: 2, summary: "thinking...")
        vm.handleForTesting(.persisted(think))
        let thinkEntry = vm.entries.last!
        XCTAssertFalse(vm.isExpanded(thinkEntry), "thinking 默认折叠")

        // toolCard 默认折叠
        let use = Event(sessionId: sid, type: .toolUse, category: .shell,
                        toolName: "Bash", toolUseId: "tu_1",
                        timestamp: Date(), lineNumber: 3, summary: "Bash")
        vm.handleForTesting(.persisted(use))
        let toolEntry = vm.entries.last!
        XCTAssertFalse(vm.isExpanded(toolEntry), "toolCard 默认折叠")
    }

    func test_toggleExpandAll_expandsAllCollapsibles_thenCollapsesAll() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        let think = Event(sessionId: sid, type: .assistantThinking,
                          timestamp: Date(), lineNumber: 1, summary: "t")
        let use = Event(sessionId: sid, type: .toolUse, category: .shell,
                        toolName: "Bash", toolUseId: "tu_1",
                        timestamp: Date(), lineNumber: 2, summary: "B")
        vm.handleForTesting(.persisted(think))
        vm.handleForTesting(.persisted(use))

        // 默认全折叠
        XCTAssertFalse(vm.isExpanded(vm.entries[0]))
        XCTAssertFalse(vm.isExpanded(vm.entries[1]))

        // 第一次 toggleExpandAll → 全展开
        vm.toggleExpandAll()
        XCTAssertTrue(vm.isExpanded(vm.entries[0]))
        XCTAssertTrue(vm.isExpanded(vm.entries[1]))

        // 第二次 → 全折叠
        vm.toggleExpandAll()
        XCTAssertFalse(vm.isExpanded(vm.entries[0]))
        XCTAssertFalse(vm.isExpanded(vm.entries[1]))
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
