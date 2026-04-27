import XCTest
import AppKit
import SwiftTerm
@testable import CairnTerminal

@MainActor
final class TabGroupTests: XCTestCase {
    private func makeFake() -> TabSession {
        TabSession(
            workspaceId: UUID(), title: "t", cwd: "/tmp", shell: "/bin/zsh",
            terminalView: LocalProcessTerminalView(frame: .zero)
        )
    }

    func test_init_hasEmptyTabs() {
        let g = TabGroup()
        XCTAssertTrue(g.tabs.isEmpty)
        XCTAssertNil(g.activeTabId)
    }

    func test_appendRestored_activatesFirst() {
        let g = TabGroup()
        let a = makeFake(); g.appendRestoredTab(a)
        XCTAssertEqual(g.activeTabId, a.id)
        let b = makeFake(); g.appendRestoredTab(b)
        // active 不变(appendRestored 只在 nil 时设置)
        XCTAssertEqual(g.activeTabId, a.id)
    }

    func test_closeTab_returnsTrueWhenEmpty() {
        let g = TabGroup()
        let a = makeFake(); g._insertForTesting(a)
        let wasEmpty = g.closeTab(id: a.id)
        XCTAssertTrue(wasEmpty)
        XCTAssertTrue(g.tabs.isEmpty)
    }

    func test_closeTab_returnsFalseWhenNotEmpty() {
        let g = TabGroup()
        g._insertForTesting(makeFake())
        let b = makeFake(); g._insertForTesting(b)
        let wasEmpty = g.closeTab(id: b.id)
        XCTAssertFalse(wasEmpty)
        XCTAssertEqual(g.tabs.count, 1)
    }

    func test_activateNextTab_cycles() {
        let g = TabGroup()
        let a = makeFake(); g._insertForTesting(a)
        let b = makeFake(); g._insertForTesting(b)
        g.activateNextTab()
        XCTAssertEqual(g.activeTabId, a.id)  // wrap 回前
    }
}
