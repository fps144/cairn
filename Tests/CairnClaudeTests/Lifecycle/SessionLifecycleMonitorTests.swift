import XCTest
import CairnCore
@testable import CairnClaude

/// 测纯函数版 `computeStatePure` 的 5 态判定(spec §4.5)。
/// instance method `computeState(for:)` 调用此函数,行为一致。
final class SessionLifecycleMonitorTests: XCTestCase {
    func test_live_recentMtime() {
        XCTAssertEqual(
            SessionLifecycleMonitor.computeStatePure(
                mtimeAge: 30, fileExists: true, hangingToolUses: 0
            ),
            .live
        )
    }

    func test_idle_within5Min() {
        XCTAssertEqual(
            SessionLifecycleMonitor.computeStatePure(
                mtimeAge: 120, fileExists: true, hangingToolUses: 0
            ),
            .idle
        )
    }

    func test_ended_over5MinNoHanging() {
        XCTAssertEqual(
            SessionLifecycleMonitor.computeStatePure(
                mtimeAge: 600, fileExists: true, hangingToolUses: 0
            ),
            .ended
        )
    }

    func test_idle_5To30MinWithHanging() {
        // 5-30 min 区间含悬挂 tool_use → 仍 .idle(未到 abandoned)
        XCTAssertEqual(
            SessionLifecycleMonitor.computeStatePure(
                mtimeAge: 600, fileExists: true, hangingToolUses: 2
            ),
            .idle
        )
    }

    func test_abandoned_over30MinWithHanging() {
        XCTAssertEqual(
            SessionLifecycleMonitor.computeStatePure(
                mtimeAge: 1800, fileExists: true, hangingToolUses: 1
            ),
            .abandoned
        )
    }

    func test_crashed_fileMissing() {
        // 文件不存在 → .crashed,不管 mtime 或 hanging
        XCTAssertEqual(
            SessionLifecycleMonitor.computeStatePure(
                mtimeAge: 30, fileExists: false, hangingToolUses: 0
            ),
            .crashed
        )
        XCTAssertEqual(
            SessionLifecycleMonitor.computeStatePure(
                mtimeAge: 9999, fileExists: false, hangingToolUses: 5
            ),
            .crashed
        )
    }
}
