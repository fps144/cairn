import XCTest
import CairnCore
@testable import CairnClaude

final class ToolPairingTrackerTests: XCTestCase {
    func test_pairsUseThenResult() async throws {
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
        _ = await tracker.observe([use])
        let countAfterUse = await tracker.inflightCount()
        XCTAssertEqual(countAfterUse, 1)
        let paired = await tracker.observe([result])
        XCTAssertEqual(paired.first?.pairedEventId, use.id)
        let countAfterResult = await tracker.inflightCount()
        XCTAssertEqual(countAfterResult, 0)
    }

    func test_unpairedResultPassesThrough() async throws {
        let tracker = ToolPairingTracker()
        let orphan = Event(
            sessionId: UUID(), type: .toolResult,
            toolUseId: "tu_missing",
            timestamp: Date(), lineNumber: 1, summary: "orphan"
        )
        let out = await tracker.observe([orphan])
        XCTAssertNil(out.first?.pairedEventId)
    }

    func test_restoreFromExisting() async throws {
        let tracker = ToolPairingTracker()
        let sid = UUID()
        let use1 = Event(sessionId: sid, type: .toolUse, toolUseId: "tu_1",
                         timestamp: Date(), lineNumber: 1, summary: "")
        let use2 = Event(sessionId: sid, type: .toolUse, toolUseId: "tu_2",
                         timestamp: Date(), lineNumber: 2, summary: "")
        let res2 = Event(sessionId: sid, type: .toolResult, toolUseId: "tu_2",
                         timestamp: Date(), lineNumber: 3, summary: "")
        // use1 未配对,use2 已配对
        await tracker.restore(from: [use1, use2, res2])
        let count = await tracker.inflightCount()
        XCTAssertEqual(count, 1)
    }
}
