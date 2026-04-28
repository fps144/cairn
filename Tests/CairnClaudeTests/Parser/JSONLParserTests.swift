import XCTest
import CairnCore
@testable import CairnClaude

final class JSONLParserTests: XCTestCase {
    private let sid = UUID()

    private func loadFixture(_ name: String) throws -> [String] {
        // SPM `.copy("Parser/fixtures")` 实际把**末段目录** `fixtures/` 扁平 copy
        // 到 bundle 根,不保留 `Parser/` 前缀。subdirectory 写 "fixtures"。
        let url = Bundle.module.url(
            forResource: name, withExtension: "jsonl",
            subdirectory: "fixtures"
        )!
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func parseFirst(_ fixture: String, lineNumber: Int64 = 1, isFirstLine: Bool = true) throws -> [Event] {
        let lines = try loadFixture(fixture)
        return JSONLParser.parse(
            line: lines[0], sessionId: sid,
            lineNumber: lineNumber, isFirstLine: isFirstLine
        )
    }

    // MARK: - user

    func test_userText_mapsToUserMessage() throws {
        let events = try parseFirst("user-text")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .userMessage)
        XCTAssertFalse(events[0].summary.isEmpty)
    }

    func test_userToolResult_mapsToToolResult() throws {
        let events = try parseFirst("user-tool-result")
        XCTAssertTrue(events.contains { $0.type == .toolResult })
        XCTAssertNotNil(events.first { $0.type == .toolResult }?.toolUseId)
    }

    // MARK: - assistant

    func test_assistantText() throws {
        let events = try parseFirst("assistant-text")
        // 严格 count:text(block 0)+ api_usage(派生) = 2
        XCTAssertEqual(events.count, 2, "got types \(events.map(\.type))")
        XCTAssertEqual(events[0].type, .assistantText)
        XCTAssertEqual(events[0].blockIndex, 0)
        XCTAssertEqual(events[1].type, .apiUsage)
        XCTAssertEqual(events[1].blockIndex, 1)
    }

    func test_assistantThinking() throws {
        let events = try parseFirst("assistant-thinking")
        XCTAssertTrue(events.contains { $0.type == .assistantThinking })
    }

    func test_assistantToolUse() throws {
        let events = try parseFirst("assistant-tool-use")
        let tu = events.first { $0.type == .toolUse }
        XCTAssertNotNil(tu)
        XCTAssertNotNil(tu?.toolName)
        XCTAssertNotNil(tu?.toolUseId)
    }

    func test_assistantMixed_multipleBlocks() throws {
        let events = try parseFirst("assistant-mixed")
        // mixed fixture: thinking + text + tool_use,共 3 个 content block + api_usage
        let types = events.map(\.type)
        XCTAssertTrue(types.contains(.assistantThinking))
        XCTAssertTrue(types.contains(.assistantText))
        XCTAssertTrue(types.contains(.toolUse))
        XCTAssertTrue(types.contains(.apiUsage))
        // blockIndex 单调递增
        for i in 1..<events.count {
            XCTAssertGreaterThanOrEqual(events[i].blockIndex, events[i-1].blockIndex)
        }
    }

    // MARK: - 忽略类型

    func test_systemEntry_returnsEmpty() throws {
        let events = try parseFirst("system-with-cwd")
        XCTAssertTrue(events.isEmpty)
    }

    func test_ignoredTypes_allReturnEmpty() throws {
        let lines = try loadFixture("ignored-types")
        for line in lines {
            let events = JSONLParser.parse(
                line: line, sessionId: sid,
                lineNumber: 1, isFirstLine: true
            )
            XCTAssertTrue(events.isEmpty, "expected empty for ignored type, got \(events)")
        }
    }

    // MARK: - 派生事件

    func test_compactBoundary_derivesOnNullParent() throws {
        let events = try parseFirst("compact-boundary", lineNumber: 5, isFirstLine: false)
        // user entry 的 user_message + compact_boundary 派生
        XCTAssertTrue(events.contains { $0.type == .compactBoundary })
    }

    func test_compactBoundary_skippedOnFirstLine() throws {
        let events = try parseFirst("compact-boundary", lineNumber: 1, isFirstLine: true)
        XCTAssertFalse(events.contains { $0.type == .compactBoundary })
    }

    func test_errorFlag_derivesErrorEvent() throws {
        let events = try parseFirst("error-flag")
        XCTAssertTrue(events.contains { $0.type == .error })
    }

    // MARK: - 容错

    func test_malformedJson_returnsEmptyWithoutCrash() {
        let events = JSONLParser.parse(
            line: "{broken json",
            sessionId: sid, lineNumber: 1, isFirstLine: true
        )
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - 性能 smoke

    /// 1000 行混合 fixture,单线程 parse 应 < 300ms。
    /// spec §8.5 M2.3 有 "1000 行 < 500ms" 要求,parser 层定更严目标留余量。
    func test_parse1000Lines_underThreeHundredMs() throws {
        let fixtures = ["user-text", "assistant-text", "assistant-tool-use",
                        "user-tool-result", "system-with-cwd"]
        var lines: [String] = []
        for name in fixtures {
            let fx = try loadFixture(name)
            for _ in 0..<(1000 / fixtures.count) {
                lines.append(contentsOf: fx)
            }
        }
        while lines.count > 1000 { lines.removeLast() }
        XCTAssertEqual(lines.count, 1000)

        let start = DispatchTime.now()
        var total = 0
        for (i, line) in lines.enumerated() {
            total += JSONLParser.parse(
                line: line, sessionId: sid,
                lineNumber: Int64(i + 1), isFirstLine: i == 0
            ).count
        }
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsedNs) / 1_000_000
        XCTAssertLessThan(elapsedMs, 300, "1000 行 parse \(elapsedMs)ms,超过 300ms 上限")
        XCTAssertGreaterThan(total, 0)
    }

    // MARK: - 本地 smoke(T11)

    /// 本机真 session JSONL 整份 parse 不崩 + 事件数合理。
    /// 硬编码本机路径;其他机器 / CI skip。
    func test_localRealSession_parses() throws {
        let path = "\(NSHomeDirectory())/.claude/projects/-Users-sorain-xiaomi-projects-AICoding-cairn/2626ca25-0515-4e42-9521-902aff636617.jsonl"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("real session file not present on this machine")
        }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.split(separator: "\n").map(String.init)
        var totalEvents = 0
        var byType: [EventType: Int] = [:]
        for (i, line) in lines.enumerated() {
            let events = JSONLParser.parse(
                line: line, sessionId: sid,
                lineNumber: Int64(i + 1), isFirstLine: i == 0
            )
            totalEvents += events.count
            for e in events {
                byType[e.type, default: 0] += 1
            }
        }
        print("[M2.2 smoke] \(lines.count) lines → \(totalEvents) events")
        print("[M2.2 smoke] by type:")
        for (t, n) in byType.sorted(by: { $0.value > $1.value }) {
            print("  \(t.rawValue): \(n)")
        }
        XCTAssertGreaterThan(totalEvents, 0)
        // 至少有 user_message
        XCTAssertNotNil(byType[.userMessage])
    }
}
