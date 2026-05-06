import XCTest
@testable import CairnCore

final class CairnCoreTests: XCTestCase {
    func test_scaffoldVersion_startsWithZero() {
        XCTAssertTrue(CairnCore.scaffoldVersion.hasPrefix("0."))
    }

    func test_scaffoldVersion_containsMilestoneTag() {
        // M2.7 起改 semver(0.1.0-beta);不再含 milestone tag
        XCTAssertTrue(
            CairnCore.scaffoldVersion.contains("beta"),
            "v0.1 Beta 版本字符串应含 beta,实际是 \(CairnCore.scaffoldVersion)"
        )
    }
}
