import Foundation
import CairnCore

/// 维护 tool_use ↔ tool_result 的 in-memory 配对关系。
/// 重启后 DB 重建由 M2.3 EventIngestor 调用 `restore(from:)` 完成。
///
/// **⚠️ id 稳定性约束**:observe 里 inflight 存的是**传入 event 的 id**。
/// 如果 caller 先做 DB upsert 把 Event.id 替换成 stable 值再调 observe,
/// 配对后的 pairedEventId 才能指向 DB 里真实存在的 row。M2.3 EventIngestor
/// **必须**按此顺序调度,否则 tool_result.paired_event_id 指向不存在的 id。
/// M2.2 范围只保证"同一 parser 流里 tool_use→tool_result id 一致"。
public actor ToolPairingTracker {
    private var inflight: [String: UUID] = [:]  // toolUseId → tool_use Event.id

    public init() {}

    /// 处理一批 Event:tool_use 入 inflight;tool_result 出 inflight + 填 pairedEventId。
    /// 返回修正后的 Event 数组(tool_result 的 pairedEventId 已填)。
    public func observe(_ events: [Event]) -> [Event] {
        return events.map { event in
            switch event.type {
            case .toolUse:
                if let tid = event.toolUseId {
                    inflight[tid] = event.id
                }
                return event
            case .toolResult:
                guard let tid = event.toolUseId,
                      let useId = inflight.removeValue(forKey: tid) else {
                    return event
                }
                var paired = event
                paired.pairedEventId = useId
                return paired
            default:
                return event
            }
        }
    }

    /// 重建 inflight:从已 persisted 的 Event 列表找出未配对的 tool_use。
    /// 规则:tool_use 若对应 tool_use_id 没有一条 tool_result → 仍 inflight。
    public func restore(from existing: [Event]) {
        inflight.removeAll()
        var useEvents: [String: UUID] = [:]
        var resultUseIds: Set<String> = []
        for e in existing {
            guard let tid = e.toolUseId else { continue }
            switch e.type {
            case .toolUse: useEvents[tid] = e.id
            case .toolResult: resultUseIds.insert(tid)
            default: break
            }
        }
        for (tid, useId) in useEvents where !resultUseIds.contains(tid) {
            inflight[tid] = useId
        }
    }

    public func inflightCount() -> Int { inflight.count }
}
