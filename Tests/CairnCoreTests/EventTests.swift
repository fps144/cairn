import XCTest
@testable import CairnCore

final class EventTests: XCTestCase {
    func test_init_userMessage_hasNoToolFields() {
        let event = Event(
            sessionId: UUID(),
            type: .userMessage,
            timestamp: Date(),
            lineNumber: 1,
            summary: "Hello Claude"
        )
        XCTAssertNil(event.category)
        XCTAssertNil(event.toolName)
        XCTAssertNil(event.toolUseId)
        XCTAssertEqual(event.blockIndex, 0)
    }

    func test_init_toolUse_hasCategoryAndToolName() {
        let event = Event(
            sessionId: UUID(),
            type: .toolUse,
            category: .fileRead,
            toolName: "Read",
            toolUseId: "toolu_01",
            timestamp: Date(),
            lineNumber: 42,
            summary: "Read README.md"
        )
        XCTAssertEqual(event.category, .fileRead)
        XCTAssertEqual(event.toolName, "Read")
        XCTAssertEqual(event.toolUseId, "toolu_01")
    }

    func test_codable_roundTrip_withRawPayload() throws {
        let original = Event(
            id: UUID(),
            sessionId: UUID(),
            type: .toolResult,
            category: nil,
            toolName: nil,
            toolUseId: "toolu_01",
            pairedEventId: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            lineNumber: 43,
            blockIndex: 0,
            summary: "File read OK (1234 bytes)",
            rawPayloadJson: #"{"type":"tool_result","content":"..."}"#,
            byteOffsetInJsonl: 98_765
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Event.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_defaults_minimalEvent() {
        let event = Event(
            sessionId: UUID(),
            type: .assistantText,
            timestamp: Date(),
            lineNumber: 5,
            summary: "response"
        )
        XCTAssertEqual(event.blockIndex, 0,
                       "blockIndex 默认 0 — spec §2.6 为单 block 行的默认位置")
        XCTAssertNil(event.rawPayloadJson)
        XCTAssertNil(event.byteOffsetInJsonl)
        XCTAssertNil(event.pairedEventId)
    }
}
