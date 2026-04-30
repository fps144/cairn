import XCTest
import CairnCore
import CairnClaude
import CairnStorage
@testable import CairnServices

@MainActor
final class TimelineViewModelTests: XCTestCase {
    private let defaultWsId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func makeVM() async throws -> TimelineViewModel {
        let db = try await CairnDatabase(
            location: .inMemory, migrator: CairnStorage.makeMigrator()
        )
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tvm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try await WorkspaceDAO.upsert(
            Workspace(id: defaultWsId, name: "W", cwd: "/tmp"), in: db
        )
        let watcher = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let ingestor = EventIngestor(database: db, watcher: watcher)
        return TimelineViewModel(ingestor: ingestor, database: db)
    }

    // MARK: - M2.6:不再 auto-switch

    func test_persistedWithoutCurrentSession_filtered() async throws {
        let vm = try await makeVM()
        let e = Event(sessionId: UUID(), type: .userMessage,
                      timestamp: Date(), lineNumber: 1, summary: "hi")
        vm.handleForTesting(.persisted(e))
        XCTAssertNil(vm.currentSessionId, "VM 不 auto-switch,current 保持 nil")
        XCTAssertEqual(vm.events.count, 0, "无 current 时事件被 filter")
    }

    func test_switchSession_setsCurrentAndClearsEvents() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        await vm.switchSession(sid)
        XCTAssertEqual(vm.currentSessionId, sid)
        XCTAssertEqual(vm.events.count, 0, "新 session 无历史 DB events")
    }

    func test_afterSwitch_persistedSameSession_appends() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        await vm.switchSession(sid)
        for i in 1...5 {
            let e = Event(sessionId: sid, type: .userMessage,
                          timestamp: Date(), lineNumber: Int64(i), summary: "msg \(i)")
            vm.handleForTesting(.persisted(e))
        }
        XCTAssertEqual(vm.events.count, 5)
        XCTAssertEqual(vm.events.map(\.lineNumber), [1,2,3,4,5])
    }

    func test_persistedOtherSession_filtered() async throws {
        let vm = try await makeVM()
        let sid1 = UUID()
        let sid2 = UUID()
        await vm.switchSession(sid1)
        // sid2 的事件应被 filter
        vm.handleForTesting(.persisted(Event(
            sessionId: sid2, type: .userMessage,
            timestamp: Date(), lineNumber: 1, summary: "other"
        )))
        XCTAssertEqual(vm.events.count, 0)
    }

    func test_switchSession_nilClearsAll() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        await vm.switchSession(sid)
        vm.handleForTesting(.persisted(Event(
            sessionId: sid, type: .userMessage,
            timestamp: Date(), lineNumber: 1, summary: "a"
        )))
        XCTAssertEqual(vm.events.count, 1)

        await vm.switchSession(nil)
        XCTAssertNil(vm.currentSessionId)
        XCTAssertEqual(vm.events.count, 0)
    }

    func test_duplicateId_filtered() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        await vm.switchSession(sid)
        let e = Event(sessionId: sid, type: .userMessage,
                      timestamp: Date(), lineNumber: 1, summary: "dup")
        vm.handleForTesting(.persisted(e))
        vm.handleForTesting(.persisted(e))  // 同 id 再次
        XCTAssertEqual(vm.events.count, 1)
    }

    // MARK: - M2.6:lifecycle state

    func test_updateSessionState() async throws {
        let vm = try await makeVM()
        XCTAssertNil(vm.currentSessionState)
        vm.updateSessionState(.live)
        XCTAssertEqual(vm.currentSessionState, .live)
        vm.updateSessionState(.idle)
        XCTAssertEqual(vm.currentSessionState, .idle)
    }

    // MARK: - M2.5:toggle 测试(依然 work)

    func test_toggle_flipsExpandedState() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        await vm.switchSession(sid)
        let use = Event(
            sessionId: sid, type: .toolUse, category: .shell,
            toolName: "Bash", toolUseId: "tu_1",
            timestamp: Date(), lineNumber: 1, summary: "Bash"
        )
        vm.handleForTesting(.persisted(use))
        let entry = vm.entries[0]
        XCTAssertFalse(vm.isExpanded(entry))
        vm.toggle(entry.id)
        XCTAssertTrue(vm.isExpanded(entry))
        vm.toggle(entry.id)
        XCTAssertFalse(vm.isExpanded(entry))
    }

    func test_isExpanded_defaultRules() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        await vm.switchSession(sid)
        // userMessage 默认展开(非可折叠)
        let user = Event(sessionId: sid, type: .userMessage,
                         timestamp: Date(), lineNumber: 1, summary: "hi")
        vm.handleForTesting(.persisted(user))
        let userEntry = vm.entries.last!
        XCTAssertTrue(vm.isExpanded(userEntry))

        // thinking 默认折叠
        let think = Event(sessionId: sid, type: .assistantThinking,
                          timestamp: Date(), lineNumber: 2, summary: "real thinking")
        vm.handleForTesting(.persisted(think))
        let thinkEntry = vm.entries.last!
        XCTAssertFalse(vm.isExpanded(thinkEntry))

        // toolCard 默认折叠
        let use = Event(sessionId: sid, type: .toolUse, category: .shell,
                        toolName: "Bash", toolUseId: "tu_1",
                        timestamp: Date(), lineNumber: 3, summary: "Bash")
        vm.handleForTesting(.persisted(use))
        let toolEntry = vm.entries.last!
        XCTAssertFalse(vm.isExpanded(toolEntry))
    }

    func test_toggleExpandAll_expandsAllCollapsibles_thenCollapsesAll() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        await vm.switchSession(sid)
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

        vm.toggleExpandAll()
        XCTAssertTrue(vm.isExpanded(vm.entries[0]))
        XCTAssertTrue(vm.isExpanded(vm.entries[1]))

        vm.toggleExpandAll()
        XCTAssertFalse(vm.isExpanded(vm.entries[0]))
        XCTAssertFalse(vm.isExpanded(vm.entries[1]))
    }
}
