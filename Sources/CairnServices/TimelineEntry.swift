import Foundation
import CairnCore

/// Timeline 聚合后的一条 entry。M2.4 是"一个 Event 一行"的扁平模型,
/// M2.5 引入聚合:tool_use + tool_result 合并为一张卡片、连续同 category
/// tool 合并为一行、compact_boundary 独立渲染。
public enum TimelineEntry: Equatable, Identifiable {
    case single(Event)
    /// tool_use + 可选 tool_result 的配对卡片。in-flight 时 result == nil。
    case toolCard(toolUse: Event, toolResult: Event?)
    /// 连续同 category 的 tool_use 合并(N ≥ 2)。
    case mergedTools(category: ToolCategory, events: [Event])
    /// compact_boundary 独立渲染为 divider
    case compactBoundary(Event)

    public var id: UUID {
        switch self {
        case .single(let e):
            return e.id
        case .toolCard(let use, _):
            return use.id
        case .mergedTools(_, let events):
            // aggregator 保证 events.count >= 2,非空;用 events[0].id。
            // **不要** `?? UUID()` fallback —— UUID() 每次调用新值,
            // ForEach(id:\.id) 会误判 entry 变化每帧重建,严重性能问题。
            return events[0].id
        case .compactBoundary(let e):
            return e.id
        }
    }
}
