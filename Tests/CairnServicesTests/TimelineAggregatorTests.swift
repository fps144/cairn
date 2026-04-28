import XCTest
import CairnCore
@testable import CairnServices

final class TimelineAggregatorTests: XCTestCase {
    private func makeEvent(
        type: EventType, category: ToolCategory? = nil,
        toolUseId: String? = nil, lineNumber: Int64 = 1,
        blockIndex: Int = 0
    ) -> Event {
        Event(
            sessionId: UUID(), type: type, category: category,
            toolName: category.map { _ in "T" }, toolUseId: toolUseId,
            timestamp: Date(), lineNumber: lineNumber, blockIndex: blockIndex,
            summary: "s"
        )
    }

    func test_empty() {
        XCTAssertTrue(TimelineAggregator.aggregate(events: []).isEmpty)
    }

    func test_singleUserMessage() {
        let e = makeEvent(type: .userMessage)
        let entries = TimelineAggregator.aggregate(events: [e])
        XCTAssertEqual(entries.count, 1)
        if case .single(let got) = entries[0] {
            XCTAssertEqual(got.id, e.id)
        } else {
            XCTFail("expected .single")
        }
    }

    func test_toolUseAndResult_pair() {
        let use = makeEvent(type: .toolUse, category: .shell,
                            toolUseId: "tu_1", lineNumber: 1)
        let result = makeEvent(type: .toolResult, toolUseId: "tu_1",
                               lineNumber: 2)
        let entries = TimelineAggregator.aggregate(events: [use, result])
        XCTAssertEqual(entries.count, 1)
        if case .toolCard(let u, let r) = entries[0] {
            XCTAssertEqual(u.id, use.id)
            XCTAssertEqual(r?.id, result.id)
        } else {
            XCTFail("expected .toolCard")
        }
    }

    func test_toolUseWithoutResult_inflight() {
        let use = makeEvent(type: .toolUse, category: .shell,
                            toolUseId: "tu_1")
        let entries = TimelineAggregator.aggregate(events: [use])
        XCTAssertEqual(entries.count, 1)
        if case .toolCard(_, let r) = entries[0] {
            XCTAssertNil(r, "in-flight tool_use 的 result 应为 nil")
        } else {
            XCTFail("expected .toolCard(in-flight)")
        }
    }

    func test_threeUnpairedSameCategory_merge() {
        let events = (1...3).map { i in
            makeEvent(type: .toolUse, category: .fileRead,
                      toolUseId: "tu_\(i)", lineNumber: Int64(i))
        }
        let entries = TimelineAggregator.aggregate(events: events)
        XCTAssertEqual(entries.count, 1)
        if case .mergedTools(let cat, let es) = entries[0] {
            XCTAssertEqual(cat, .fileRead)
            XCTAssertEqual(es.count, 3)
        } else {
            XCTFail("expected .mergedTools")
        }
    }

    func test_twoDifferentCategories_noMerge() {
        let read = makeEvent(type: .toolUse, category: .fileRead,
                             toolUseId: "tu_1", lineNumber: 1)
        let write = makeEvent(type: .toolUse, category: .fileWrite,
                              toolUseId: "tu_2", lineNumber: 2)
        let entries = TimelineAggregator.aggregate(events: [read, write])
        XCTAssertEqual(entries.count, 2)
        if case .toolCard = entries[0] {} else { XCTFail() }
        if case .toolCard = entries[1] {} else { XCTFail() }
    }

    func test_compactBoundary() {
        let cb = makeEvent(type: .compactBoundary)
        let entries = TimelineAggregator.aggregate(events: [cb])
        if case .compactBoundary(let e) = entries[0] {
            XCTAssertEqual(e.id, cb.id)
        } else {
            XCTFail("expected .compactBoundary")
        }
    }

    func test_mixedSequence_preservesOrder() {
        let u = makeEvent(type: .userMessage, lineNumber: 1)
        let think = makeEvent(type: .assistantThinking, lineNumber: 2)
        let use = makeEvent(type: .toolUse, category: .shell,
                            toolUseId: "tu_1", lineNumber: 3)
        let result = makeEvent(type: .toolResult, toolUseId: "tu_1",
                               lineNumber: 4)
        let text = makeEvent(type: .assistantText, lineNumber: 5)
        let entries = TimelineAggregator.aggregate(
            events: [u, think, use, result, text]
        )
        // user, thinking, toolCard, text:4 entries
        XCTAssertEqual(entries.count, 4)
        if case .single(let e0) = entries[0] {
            XCTAssertEqual(e0.type, .userMessage)
        } else { XCTFail() }
        if case .single(let e1) = entries[1] {
            XCTAssertEqual(e1.type, .assistantThinking)
        } else { XCTFail() }
        if case .toolCard(let u, _) = entries[2] {
            XCTAssertEqual(u.id, use.id)
        } else { XCTFail() }
        if case .single(let e3) = entries[3] {
            XCTAssertEqual(e3.type, .assistantText)
        } else { XCTFail() }
    }

    func test_pairedToolResult_notRepeated() {
        let use = makeEvent(type: .toolUse, category: .shell,
                            toolUseId: "tu_1", lineNumber: 1)
        let result = makeEvent(type: .toolResult, toolUseId: "tu_1",
                               lineNumber: 2)
        let entries = TimelineAggregator.aggregate(events: [use, result])
        XCTAssertEqual(entries.count, 1,
                       "result 已被 toolCard 吃掉,不应独立再出现")
    }
}
