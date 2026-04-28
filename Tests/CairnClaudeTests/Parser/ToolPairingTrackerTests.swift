import XCTest
import CairnCore
@testable import CairnClaude

final class ToolPairingTrackerTests: XCTestCase {
    func test_pairsUseThenResult() {
        let tracker = ToolPairingTracker()
        let sid = UUID()
        let use = Event(
            sessionId: sid, type: .toolUse,
            toolName: "Bash", toolUseId: "tu_1",
            timestamp: Date(), lineNumber: 1, summary: "Bash"
        )
        let result = Event(
            sessionId: sid, type: .toolResult,
            toolUseId: "tu_1",
            timestamp: Date(), lineNumber: 2, summary: "ok"
        )
        _ = tracker.observe([use])
        XCTAssertEqual(tracker.inflightCount(), 1)
        let paired = tracker.observe([result])
        XCTAssertEqual(paired.first?.pairedEventId, use.id)
        XCTAssertEqual(tracker.inflightCount(), 0)
    }

    func test_unpairedResultPassesThrough() {
        let tracker = ToolPairingTracker()
        let orphan = Event(
            sessionId: UUID(), type: .toolResult,
            toolUseId: "tu_missing",
            timestamp: Date(), lineNumber: 1, summary: "orphan"
        )
        let out = tracker.observe([orphan])
        XCTAssertNil(out.first?.pairedEventId)
    }

    func test_restoreFromExisting_onlyCountsPairedResults() {
        let tracker = ToolPairingTracker()
        let sid = UUID()
        let use1 = Event(sessionId: sid, type: .toolUse, toolUseId: "tu_1",
                         timestamp: Date(), lineNumber: 1, summary: "")
        let use2 = Event(sessionId: sid, type: .toolUse, toolUseId: "tu_2",
                         timestamp: Date(), lineNumber: 2, summary: "")
        let res2Paired = Event(sessionId: sid, type: .toolResult,
                               toolUseId: "tu_2",
                               pairedEventId: use2.id,  // ← paired
                               timestamp: Date(), lineNumber: 3, summary: "")
        // use1 未配对,use2 已配对(paired_event_id 非空)
        tracker.restore(from: [use1, use2, res2Paired])
        XCTAssertEqual(tracker.inflightCount(), 1, "只 use1 重进 inflight")
    }

    /// M2.3 新增回归:crash 后 DB 里孤儿 tool_result(paired=null)
    /// 不应让 tool_use 漏进 inflight。
    func test_restoreFromExisting_orphanResult_keepsUseInInflight() {
        let tracker = ToolPairingTracker()
        let sid = UUID()
        let use = Event(sessionId: sid, type: .toolUse, toolUseId: "tu_1",
                        timestamp: Date(), lineNumber: 1, summary: "")
        // 孤儿 tool_result:已入库但 paired_event_id 是 nil(M2.3 pre-fix 会漏)
        let orphanResult = Event(sessionId: sid, type: .toolResult,
                                 toolUseId: "tu_1",
                                 pairedEventId: nil,
                                 timestamp: Date(), lineNumber: 2, summary: "")
        tracker.restore(from: [use, orphanResult])
        XCTAssertEqual(tracker.inflightCount(), 1,
                       "orphan tool_result 不应阻止 tool_use 进 inflight")
    }
}
