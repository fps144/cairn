import XCTest
@testable import CairnCore

final class JSONRoundTripTests: XCTestCase {
    /// 验证 CairnCore 共享的 encoder/decoder 对所有实体 round-trip 保真。
    /// spec §7.2:ISO-8601 字符串。
    func test_sharedEncoder_outputsISO8601DateStrings() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14T22:13:20Z
        let ws = Workspace(name: "W", cwd: "/", createdAt: date, lastActiveAt: date)
        let data = try CairnCore.jsonEncoder.encode(ws)
        let jsonStr = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(
            jsonStr.contains("2023-11-14T22:13:20Z"),
            "共享 encoder 应产出 ISO-8601 日期字符串,实际: \(jsonStr)"
        )
    }

    func test_allEntities_roundTripViaSharedCoder() throws {
        // Workspace
        try assertRoundTrip(
            Workspace(name: "w", cwd: "/tmp",
                      createdAt: .init(timeIntervalSince1970: 1),
                      lastActiveAt: .init(timeIntervalSince1970: 2))
        )
        // Tab
        try assertRoundTrip(
            Tab(workspaceId: UUID(), title: "t")
        )
        // Session
        try assertRoundTrip(
            Session(workspaceId: UUID(), jsonlPath: "/x",
                    startedAt: .init(timeIntervalSince1970: 1))
        )
        // CairnTask
        try assertRoundTrip(
            CairnTask(workspaceId: UUID(), title: "task",
                      createdAt: .init(timeIntervalSince1970: 1),
                      updatedAt: .init(timeIntervalSince1970: 2))
        )
        // Event
        try assertRoundTrip(
            Event(sessionId: UUID(), type: .toolUse,
                  category: .shell, toolName: "Bash",
                  timestamp: .init(timeIntervalSince1970: 1),
                  lineNumber: 1, summary: "bash")
        )
        // Budget
        try assertRoundTrip(
            Budget(taskId: UUID(),
                   updatedAt: .init(timeIntervalSince1970: 1))
        )
        // Plan
        try assertRoundTrip(
            Plan(taskId: UUID(), source: .manual,
                 updatedAt: .init(timeIntervalSince1970: 1))
        )
    }

    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let data = try CairnCore.jsonEncoder.encode(value)
        let decoded = try CairnCore.jsonDecoder.decode(T.self, from: data)
        XCTAssertEqual(value, decoded, "round-trip 失败: \(T.self)",
                       file: file, line: line)
    }
}
