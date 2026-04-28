import Foundation
import CairnCore

/// Claude Code JSONL → `CairnCore.Event` 的解析器。
///
/// 纯函数,无状态;单行 in → 0-N Event out。tool_use ↔ tool_result 配对
/// 由独立的 `ToolPairingTracker` actor 处理,**不在 parser 内**。
///
/// 对应 spec §4.3 的 type 映射表 + §4.4 配对外接 + M0.1 probe 修订集。
public enum JSONLParser {
    /// 解析一行 JSONL → 0-N 个 Event。
    /// - `isFirstLine`: JSONL 文件首行不派生 compact_boundary,即使 parentUuid==nil。
    public static func parse(
        line: String,
        sessionId: UUID,
        lineNumber: Int64,
        byteOffsetInJsonl: Int64? = nil,
        isFirstLine: Bool = false
    ) -> [Event] {
        guard let entry = try? JSONLEntry.parse(line) else {
            FileHandle.standardError.write(Data(
                "[JSONLParser] malformed line #\(lineNumber): \(line.prefix(120))\n".utf8
            ))
            return []
        }
        let ts = entry.timestamp ?? Date()
        var events: [Event] = []

        switch entry.type {
        case "user":
            events = parseUser(entry, sessionId: sessionId, lineNumber: lineNumber, ts: ts)
        case "assistant":
            events = parseAssistant(entry, sessionId: sessionId, lineNumber: lineNumber, ts: ts)
        case "system", "custom-title",
             "progress", "attachment", "file-history-snapshot",
             "permission-mode", "last-prompt", "queue-operation",
             "agent-name", "tag":
            events = []  // 忽略类型:无 content 事件,但仍走下面 compact 派生
                        // —— spec §4.3 "parentUuid == null 非首行 → compact_boundary"
                        // 与 entry type 正交。
        default:
            FileHandle.standardError.write(Data(
                "[JSONLParser] unknown type '\(entry.type)' line #\(lineNumber)\n".utf8
            ))
            return []  // 未知 type 完全跳过,避免垃圾数据派生 compact
        }

        // 派生 compact_boundary
        if entry.parentUuid == nil && !isFirstLine {
            events.append(Event(
                sessionId: sessionId,
                type: .compactBoundary,
                timestamp: ts,
                lineNumber: lineNumber,
                blockIndex: events.count,
                summary: "context compacted",
                rawPayloadJson: entry.rawJson
            ))
        }

        // 统一填 byteOffset
        return events.map { e in
            var copy = e
            copy.byteOffsetInJsonl = byteOffsetInJsonl
            return copy
        }
    }

    // MARK: - user

    private static func parseUser(
        _ entry: JSONLEntry, sessionId: UUID, lineNumber: Int64, ts: Date
    ) -> [Event] {
        guard let msg = entry.message else { return [] }
        guard let content = msg["content"] else { return [] }

        // content 是 str → user_message
        if let s = content as? String {
            return [Event(
                sessionId: sessionId,
                type: .userMessage,
                timestamp: ts,
                lineNumber: lineNumber,
                blockIndex: 0,
                summary: summarize(text: s),
                rawPayloadJson: entry.rawJson
            )]
        }

        // content 是 list → tool_result × N
        guard let list = content as? [[String: Any]] else { return [] }
        var events: [Event] = []
        for (i, block) in list.enumerated() {
            guard let btype = block["type"] as? String else { continue }
            switch btype {
            case "tool_result":
                let toolUseId = block["tool_use_id"] as? String
                let resultContent = block["content"]
                let isError = (block["is_error"] as? Bool) ?? false
                let summary = summarize(toolResultContent: resultContent)
                events.append(Event(
                    sessionId: sessionId,
                    type: .toolResult,
                    toolUseId: toolUseId,
                    timestamp: ts,
                    lineNumber: lineNumber,
                    blockIndex: i,
                    summary: summary,
                    rawPayloadJson: entry.rawJson
                ))
                if isError {
                    events.append(Event(
                        sessionId: sessionId,
                        type: .error,
                        toolUseId: toolUseId,
                        timestamp: ts,
                        lineNumber: lineNumber,
                        blockIndex: events.count,
                        summary: "tool_result reported error",
                        rawPayloadJson: entry.rawJson
                    ))
                }
            default:
                continue
            }
        }
        return events
    }

    // MARK: - assistant

    private static func parseAssistant(
        _ entry: JSONLEntry, sessionId: UUID, lineNumber: Int64, ts: Date
    ) -> [Event] {
        guard let msg = entry.message,
              let list = msg["content"] as? [[String: Any]] else { return [] }
        var events: [Event] = []
        for (i, block) in list.enumerated() {
            guard let btype = block["type"] as? String else { continue }
            switch btype {
            case "text":
                let text = block["text"] as? String ?? ""
                events.append(Event(
                    sessionId: sessionId,
                    type: .assistantText,
                    timestamp: ts,
                    lineNumber: lineNumber,
                    blockIndex: i,
                    summary: summarize(text: text),
                    rawPayloadJson: entry.rawJson
                ))
            case "thinking":
                let text = block["thinking"] as? String ?? ""
                events.append(Event(
                    sessionId: sessionId,
                    type: .assistantThinking,
                    timestamp: ts,
                    lineNumber: lineNumber,
                    blockIndex: i,
                    summary: summarize(text: text),
                    rawPayloadJson: entry.rawJson
                ))
            case "tool_use":
                let toolName = block["name"] as? String ?? "unknown"
                let toolUseId = block["id"] as? String
                let inputSummary = summarize(toolUseInput: block["input"], toolName: toolName)
                events.append(Event(
                    sessionId: sessionId,
                    type: .toolUse,
                    category: ToolCategory.from(toolName: toolName),
                    toolName: toolName,
                    toolUseId: toolUseId,
                    timestamp: ts,
                    lineNumber: lineNumber,
                    blockIndex: i,
                    summary: inputSummary,
                    rawPayloadJson: entry.rawJson
                ))
                if (block["is_error"] as? Bool) == true {
                    events.append(Event(
                        sessionId: sessionId,
                        type: .error,
                        toolUseId: toolUseId,
                        timestamp: ts,
                        lineNumber: lineNumber,
                        blockIndex: events.count,
                        summary: "tool_use reported error",
                        rawPayloadJson: entry.rawJson
                    ))
                }
            default:
                continue
            }
        }

        // 附带 api_usage
        if let usage = msg["usage"] as? [String: Any] {
            let inputTok = (usage["input_tokens"] as? Int) ?? 0
            let outputTok = (usage["output_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
            let summary = "in=\(inputTok) out=\(outputTok) cache=\(cacheRead)"
            events.append(Event(
                sessionId: sessionId,
                type: .apiUsage,
                timestamp: ts,
                lineNumber: lineNumber,
                blockIndex: events.count,
                summary: summary,
                rawPayloadJson: entry.rawJson
            ))
        }

        return events
    }

    // MARK: - summarize

    static func summarize(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }

    static func summarize(toolResultContent: Any?) -> String {
        if let s = toolResultContent as? String {
            return summarize(text: s)
        }
        if let list = toolResultContent as? [[String: Any]] {
            for b in list {
                if let t = b["text"] as? String { return summarize(text: t) }
            }
        }
        return "(tool result)"
    }

    static func summarize(toolUseInput: Any?, toolName: String) -> String {
        if let dict = toolUseInput as? [String: Any] {
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                if let s = v as? String, !s.isEmpty {
                    return "\(toolName)(\(k)=\(summarize(text: s)))"
                }
            }
        }
        return "\(toolName)()"
    }
}
