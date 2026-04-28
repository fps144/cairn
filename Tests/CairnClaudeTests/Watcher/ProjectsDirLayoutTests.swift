import XCTest
@testable import CairnClaude

final class ProjectsDirLayoutTests: XCTestCase {
    func test_hashReplacesSlashesUnderscoresDotsWithDashes() {
        XCTAssertEqual(
            ProjectsDirLayout.hash(cwd: "/Users/sorain"),
            "-Users-sorain"
        )
        XCTAssertEqual(
            ProjectsDirLayout.hash(cwd: "/Users/sorain/.vext/workspaces/01KN/mvp"),
            "-Users-sorain--vext-workspaces-01KN-mvp"
        )
        XCTAssertEqual(
            ProjectsDirLayout.hash(cwd: "/tmp/with_under_scores"),
            "-tmp-with-under-scores"
        )
    }

    func test_hashIsIdempotent() {
        // 正向幂等:hash 后只含 `-`,再次 hash 不变(`-` 不在替换集里)。
        // 逆向则歧义(`-` 不能判断原字符是 `/` `_` `.` 还是 `-` 本身)。
        let once = ProjectsDirLayout.hash(cwd: "/a/b.c")
        let twice = ProjectsDirLayout.hash(cwd: once)
        XCTAssertEqual(once, "-a-b-c")
        XCTAssertEqual(once, twice)
    }

    func test_hashIsForwardOnly_reverseHasAmbiguity() {
        // 三个完全不同的 cwd hash 到同一字符串 —— 逆向不可能。
        XCTAssertEqual(ProjectsDirLayout.hash(cwd: "/a/b"),
                       ProjectsDirLayout.hash(cwd: "/a_b"))
        XCTAssertEqual(ProjectsDirLayout.hash(cwd: "/a.b"),
                       ProjectsDirLayout.hash(cwd: "/a-b"))
    }
}
