import XCTest
import AppKit
import SwiftTerm
@testable import CairnTerminal

@MainActor
final class LayoutSerializerTests: XCTestCase {
    private func makeFake(title: String = "t", cwd: String = "/tmp") -> TabSession {
        TabSession(
            workspaceId: UUID(), title: title, cwd: cwd, shell: "/bin/zsh",
            terminalView: LocalProcessTerminalView(frame: .zero)
        )
    }

    func test_snapshot_roundTripViaJson() throws {
        let c = SplitCoordinator()
        let g1 = TabGroup()
        g1._insertForTesting(makeFake(title: "a", cwd: "/a"))
        g1._insertForTesting(makeFake(title: "b", cwd: "/b"))
        c.replaceGroups([g1])

        let layout = LayoutSerializer.snapshot(from: c)
        XCTAssertEqual(layout.schemaVersion, 1)
        XCTAssertEqual(layout.groups.count, 1)
        XCTAssertEqual(layout.groups[0].tabs.count, 2)

        let json = try LayoutSerializer.encode(layout)
        let decoded = try LayoutSerializer.decode(json)
        XCTAssertEqual(layout, decoded)
    }

    func test_snapshot_preservesTwoGroups() {
        let c = SplitCoordinator()
        let g1 = TabGroup(); g1._insertForTesting(makeFake(title: "a"))
        let g2 = TabGroup(); g2._insertForTesting(makeFake(title: "b"))
        c.replaceGroups([g1, g2], activeIndex: 1)

        let layout = LayoutSerializer.snapshot(from: c)
        XCTAssertEqual(layout.groups.count, 2)
        XCTAssertEqual(layout.activeGroupIndex, 1)
    }

    func test_encode_containsSchemaVersion1() throws {
        let c = SplitCoordinator()
        let layout = LayoutSerializer.snapshot(from: c)
        let json = try LayoutSerializer.encode(layout)
        // CairnCore.jsonEncoder 用 .sortedKeys 无 .prettyPrinted → 紧凑格式
        XCTAssertTrue(json.contains(#""schemaVersion":1"#),
                      "encoded JSON: \(json)")
    }
}
