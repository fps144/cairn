import Foundation

/// 工具分类的**开放集**。spec §2.3:仅当 `Event.type == .toolUse` 时使用,
/// 按 `toolName` 查表映射。
///
/// Swift 没有"开放 enum",所以用 `struct RawRepresentable`:
/// - 12 个静态常量对应 spec §2.3 已命名的类别
/// - `from(toolName:)` 按 spec §2.3 的映射表 + M0.1 probe 扩展解析
/// - 未知 toolName 兜底到 `.other`
/// - 允许外部用 `ToolCategory(rawValue: "custom")` 构造新类别
public struct ToolCategory: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - 静态常量(spec §2.3 的 12 种已命名类别)

extension ToolCategory {
    public static let shell = ToolCategory(rawValue: "shell")
    public static let fileRead = ToolCategory(rawValue: "file_read")
    public static let fileWrite = ToolCategory(rawValue: "file_write")
    public static let fileSearch = ToolCategory(rawValue: "file_search")
    public static let webFetch = ToolCategory(rawValue: "web_fetch")
    public static let mcpCall = ToolCategory(rawValue: "mcp_call")
    public static let subagent = ToolCategory(rawValue: "subagent")
    public static let todo = ToolCategory(rawValue: "todo")
    public static let planMgmt = ToolCategory(rawValue: "plan_mgmt")
    public static let askUser = ToolCategory(rawValue: "ask_user")
    public static let ide = ToolCategory(rawValue: "ide")
    public static let other = ToolCategory(rawValue: "other")
}

// MARK: - toolName → category 查表

extension ToolCategory {
    /// 按 Claude Code toolName 映射到 category。
    ///
    /// spec §2.3 静态表 + M0.1 probe 实测扩展(Task* / Skill / ListMcpResourcesTool)。
    /// 未知 toolName 兜底到 `.other`。
    public static func from(toolName: String) -> ToolCategory {
        // IDE 特化(mcp__ide__* 是 mcpCall 的子分类,优先级高)
        if toolName.hasPrefix("mcp__ide__") {
            return .ide
        }
        // MCP 通用前缀
        if toolName.hasPrefix("mcp__") {
            return .mcpCall
        }
        // MCP 资源列举工具(不走 mcp__ 前缀)
        if toolName == "ListMcpResourcesTool" || toolName == "ReadMcpResourceTool" {
            return .mcpCall
        }
        // 精确名称查表
        switch toolName {
        case "Bash":
            return .shell
        case "Read", "NotebookRead":
            return .fileRead
        case "Write", "Edit", "NotebookEdit":
            return .fileWrite
        case "Glob", "Grep":
            return .fileSearch
        case "WebFetch", "WebSearch":
            return .webFetch
        case "Agent", "Task":
            return .subagent
        case "TodoWrite":
            return .todo
        case "EnterPlanMode", "ExitPlanMode":
            return .planMgmt
        case "AskUserQuestion":
            return .askUser
        default:
            break
        }
        // M0.1 probe 发现的 Task* 系列(TaskCreate/Update/List/Get/Output/Stop 等)
        // 都是任务管理工具,归 todo
        if toolName.hasPrefix("Task") && toolName != "Task" {
            return .todo
        }
        return .other
    }
}
