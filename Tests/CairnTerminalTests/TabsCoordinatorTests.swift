import XCTest
import AppKit
import SwiftTerm
@testable import CairnTerminal

@MainActor
final class TabsCoordinatorTests: XCTestCase {
    /// 不启动真实 PTY 进程的 TabSession(测试用)。
    /// 不调 startProcess,terminate 走 optional chain 的 process?,
    /// 安全 no-op(参见 TabSession.terminate 的注释)。
    private func makeFakeSession(workspaceId: UUID = UUID()) -> TabSession {
        let view = LocalProcessTerminalView(frame: .zero)
        return TabSession(
            workspaceId: workspaceId,
            title: "test",
            cwd: "/tmp",
            shell: "/bin/zsh",
            terminalView: view
        )
    }

    func test_openTab_viaInsertHelper_appendsAndActivates() {
        let c = TabsCoordinator()
        let s = makeFakeSession()
        c._insertForTesting(s)
        XCTAssertEqual(c.tabs.count, 1)
        XCTAssertEqual(c.activeTabId, s.id)
        XCTAssertEqual(c.activeTab?.id, s.id)
    }

    func test_activateNextTab_cycles() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        let b = makeFakeSession(); c._insertForTesting(b)
        let d = makeFakeSession(); c._insertForTesting(d)
        // 当前 active 是 d(最后 insert 的),next 应 wrap 到 a
        c.activateNextTab()
        XCTAssertEqual(c.activeTabId, a.id)
        c.activateNextTab()
        XCTAssertEqual(c.activeTabId, b.id)
    }

    func test_activatePreviousTab_cycles() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        let b = makeFakeSession(); c._insertForTesting(b)
        let d = makeFakeSession(); c._insertForTesting(d)
        c.activateTab(id: a.id)
        c.activatePreviousTab()
        // 从 a 往前 wrap 到最后一个(d)
        XCTAssertEqual(c.activeTabId, d.id)
    }

    func test_closeTab_activatesPredecessor() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        let b = makeFakeSession(); c._insertForTesting(b)
        let d = makeFakeSession(); c._insertForTesting(d)
        c.activateTab(id: b.id)  // 当前 b
        c.closeTab(id: b.id)
        XCTAssertEqual(c.tabs.count, 2)
        // b 关掉,active 切到前驱 a
        XCTAssertEqual(c.activeTabId, a.id)
    }

    func test_closeTab_lastTab_activeIdNil() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        c.closeTab(id: a.id)
        XCTAssertTrue(c.tabs.isEmpty)
        XCTAssertNil(c.activeTabId)
    }

    func test_activateTab_ignoresUnknownId() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        let fakeId = UUID()
        c.activateTab(id: fakeId)
        // 未改变
        XCTAssertEqual(c.activeTabId, a.id)
    }

    func test_activateNextTab_fromEmpty_isNoop() {
        let c = TabsCoordinator()
        c.activateNextTab()  // 不 crash
        XCTAssertNil(c.activeTabId)
    }
}
