import XCTest
@testable import CairnCore

final class CairnCoreTests: XCTestCase {
    func test_scaffoldVersion_startsWithZero() {
        XCTAssertTrue(CairnCore.scaffoldVersion.hasPrefix("0."))
    }

    func test_scaffoldVersion_containsMilestoneTag() {
        XCTAssertTrue(
            CairnCore.scaffoldVersion.contains("m2.1"),
            "版本字符串应包含当前 milestone 标识,实际是 \(CairnCore.scaffoldVersion)"
        )
    }
}
