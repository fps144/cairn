import XCTest
@testable import CairnCore

final class CairnCoreTests: XCTestCase {
    func test_scaffoldVersion_startsWithZero() {
        XCTAssertTrue(CairnCore.scaffoldVersion.hasPrefix("0."))
    }

    func test_scaffoldVersion_containsMilestoneTag() {
        // M3.1 起 v0.1 Beta 之后回到 milestone tag(0.1.1-m3.1 / 0.1.2-m3.2 ...)
        XCTAssertTrue(
            CairnCore.scaffoldVersion.contains("m3."),
            "Phase 3 版本字符串应含 m3.x,实际是 \(CairnCore.scaffoldVersion)"
        )
    }
}
