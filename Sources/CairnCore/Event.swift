import Foundation

/// 从 JSONL 抽出的结构化事件。spec §2.3 两维设计 + §2.6 完整字段。
///
/// - `type` 封闭 12 种,必填
/// - `category` 开放集,仅当 `type == .toolUse` 时通常非 nil(按 toolName 查表)
/// - `toolUseId` 用于 Claude Code 分配的 tool_use↔tool_result 配对,
///   `pairedEventId` 是 Cairn 在解析时填入的对端 Event.id
/// - `(sessionId, lineNumber, blockIndex)` 是主排序键(spec §2.6 索引)
/// - `rawPayloadJson` 持有原始 JSON 字符串(不解析,懒加载设计)
public struct Event: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var sessionId: UUID
    public var type: EventType
    public var category: ToolCategory?
    public var toolName: String?
    public var toolUseId: String?
    public var pairedEventId: UUID?
    public var timestamp: Date
    public var lineNumber: Int64
    public var blockIndex: Int
    public var summary: String
    public var rawPayloadJson: String?
    public var byteOffsetInJsonl: Int64?

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        type: EventType,
        category: ToolCategory? = nil,
        toolName: String? = nil,
        toolUseId: String? = nil,
        pairedEventId: UUID? = nil,
        timestamp: Date,
        lineNumber: Int64,
        blockIndex: Int = 0,
        summary: String,
        rawPayloadJson: String? = nil,
        byteOffsetInJsonl: Int64? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.type = type
        self.category = category
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.pairedEventId = pairedEventId
        self.timestamp = timestamp
        self.lineNumber = lineNumber
        self.blockIndex = blockIndex
        self.summary = summary
        self.rawPayloadJson = rawPayloadJson
        self.byteOffsetInJsonl = byteOffsetInJsonl
    }
}

// MARK: - Immutable helpers(M2.3)

extension Event {
    /// 返回新 Event,id 改为 `newId`,其他字段不变。
    /// Event.id 是 let,M2.3 EventIngestor 需要"upsert 后用 DB stable id
    /// 替换 parser 生成的随机 UUID",用这个 helper 做 immutable 变换。
    public func withId(_ newId: UUID) -> Event {
        return Event(
            id: newId, sessionId: sessionId, type: type, category: category,
            toolName: toolName, toolUseId: toolUseId, pairedEventId: pairedEventId,
            timestamp: timestamp, lineNumber: lineNumber, blockIndex: blockIndex,
            summary: summary, rawPayloadJson: rawPayloadJson,
            byteOffsetInJsonl: byteOffsetInJsonl
        )
    }

    /// 返回新 Event,pairedEventId 改为 `newPairedEventId`。
    /// ToolPairingTracker.observe 用此填入 tool_result 的配对 id。
    public func withPairedEventId(_ newPairedEventId: UUID?) -> Event {
        return Event(
            id: id, sessionId: sessionId, type: type, category: category,
            toolName: toolName, toolUseId: toolUseId, pairedEventId: newPairedEventId,
            timestamp: timestamp, lineNumber: lineNumber, blockIndex: blockIndex,
            summary: summary, rawPayloadJson: rawPayloadJson,
            byteOffsetInJsonl: byteOffsetInJsonl
        )
    }
}
