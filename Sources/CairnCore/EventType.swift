import Foundation

/// Event 类型的**封闭集**。spec §2.3:12 种(v1 活跃 10,v1.1 预留 2)。
///
/// 两维设计中的"第一维"(type)。第二维 `ToolCategory` 是开放集,
/// 仅当 `type == .toolUse` 时使用,定义见 `ToolCategory.swift`。
public enum EventType: String, Codable, CaseIterable, Sendable {
    case userMessage = "user_message"
    case assistantText = "assistant_text"
    case assistantThinking = "assistant_thinking"
    case toolUse = "tool_use"
    case toolResult = "tool_result"
    case apiUsage = "api_usage"
    case compactBoundary = "compact_boundary"
    case error
    case planUpdated = "plan_updated"
    case sessionBoundary = "session_boundary"
    // v1.1 预留:
    case approvalRequested = "approval_requested"
    case approvalDecided = "approval_decided"
}
