import Foundation
import CairnCore

/// 把扁平的 `[Event]` 聚合成 `[TimelineEntry]`。纯函数无状态。
///
/// 规则(spec §6.4):
/// - `tool_use` + 同 `toolUseId` 的 `tool_result` 配对合并为 `.toolCard`
/// - 连续 N ≥ 2 个**同 category 的未配对** `tool_use` 合并为 `.mergedTools`
/// - `compact_boundary` 独立 `.compactBoundary`
/// - 其他事件独立 `.single`
///
/// 输入顺序 = 输出顺序(保持 (lineNumber, blockIndex) 时序)。
/// 每个 event 出现在**一个** entry 里,不丢不重。
public enum TimelineAggregator {
    public static func aggregate(events: [Event]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []

        // 预构建 toolUseId → tool_result 索引,便于配对(O(N))
        var resultByUseId: [String: Event] = [:]
        for e in events where e.type == .toolResult {
            if let tid = e.toolUseId {
                resultByUseId[tid] = e
            }
        }
        // 被 .toolCard 消耗的 tool_result id 集合,避免重复独立渲染
        var consumedResultIds: Set<UUID> = []

        var i = 0
        while i < events.count {
            let e = events[i]

            // 已被配对使用的 tool_result 跳过
            if e.type == .toolResult && consumedResultIds.contains(e.id) {
                i += 1
                continue
            }

            switch e.type {
            case .compactBoundary:
                entries.append(.compactBoundary(e))
                i += 1

            case .toolUse:
                // 尝试配对
                if let tid = e.toolUseId, let result = resultByUseId[tid] {
                    entries.append(.toolCard(toolUse: e, toolResult: result))
                    consumedResultIds.insert(result.id)
                    i += 1
                } else {
                    // 未配对:尝试与后续同 category 的未配对 tool_use 合并
                    guard let currentCat = e.category else {
                        entries.append(.toolCard(toolUse: e, toolResult: nil))
                        i += 1
                        continue
                    }
                    var runGroup: [Event] = [e]
                    var j = i + 1
                    while j < events.count {
                        let next = events[j]
                        guard next.type == .toolUse,
                              next.category == currentCat,
                              let tid = next.toolUseId,
                              resultByUseId[tid] == nil
                        else { break }
                        runGroup.append(next)
                        j += 1
                    }
                    if runGroup.count >= 2 {
                        entries.append(.mergedTools(category: currentCat, events: runGroup))
                    } else {
                        entries.append(.toolCard(toolUse: e, toolResult: nil))
                    }
                    i = j
                }

            default:
                entries.append(.single(e))
                i += 1
            }
        }
        return entries
    }
}
