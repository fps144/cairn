import Foundation

/// Cairn 领域核心模块。零外部依赖,纯值语义。
///
/// 本模块包含 7 个核心实体(Workspace / Tab / Session / CairnTask / Event / Budget / Plan),
/// 5 个状态机 enum(TabState / SessionState / TaskStatus / BudgetState / PlanStepStatus),
/// 以及 EventType(封闭 12 种)、ToolCategory(开放集)。
///
/// 所有类型 public + Codable + Equatable/Hashable/Sendable(全部 Swift synthesized,
/// 按所有字段比较/hash)。日期序列化统一 ISO-8601,见 `ISO8601Coding.swift`。
public enum CairnCore {
    /// 模块版本标识。每个 milestone 完成时 bump。
    public static let scaffoldVersion = "0.7.0-m2.2"
}
