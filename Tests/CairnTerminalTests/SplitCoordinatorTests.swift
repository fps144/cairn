import XCTest
import AppKit
import SwiftTerm
@testable import CairnTerminal

@MainActor
final class SplitCoordinatorTests: XCTestCase {
    private func makeFake() -> TabSession {
        TabSession(
            workspaceId: UUID(), title: "t", cwd: "/tmp", shell: "/bin/zsh",
            terminalView: LocalProcessTerminalView(frame: .zero)
        )
    }

    func test_init_singleGroup() {
        let c = SplitCoordinator()
        XCTAssertEqual(c.groups.count, 1)
        XCTAssertEqual(c.activeGroupIndex, 0)
    }

    func test_collapseEmptyGroups_removesEmptyExceptLast() {
        let c = SplitCoordinator()
        let g1 = TabGroup(); g1._insertForTesting(makeFake())
        let g2 = TabGroup()  // 空
        c.replaceGroups([g1, g2])
        c.collapseEmptyGroups()
        XCTAssertEqual(c.groups.count, 1)
        XCTAssertFalse(c.groups[0].tabs.isEmpty)
    }

    func test_collapseEmptyGroups_allEmpty_keepsOne() {
        let c = SplitCoordinator()
        c.replaceGroups([TabGroup(), TabGroup()])
        c.collapseEmptyGroups()
        // 全空时 collapse 成 1 空组(不变式:至少 1 组)
        XCTAssertEqual(c.groups.count, 1)
    }

    func test_handleTabTerminated_removesFromCorrectGroup() {
        let c = SplitCoordinator()
        let g1 = TabGroup(); let a = makeFake(); g1._insertForTesting(a)
        let g2 = TabGroup(); let b = makeFake(); g2._insertForTesting(b)
        c.replaceGroups([g1, g2])
        c.handleTabTerminated(tabId: a.id)
        // a 不在了,g1 collapse,总 groups 变 1(只剩 g2)
        XCTAssertEqual(c.groups.count, 1)
        XCTAssertTrue(c.groups[0].tabs.contains(where: { $0.id == b.id }))
    }
}
