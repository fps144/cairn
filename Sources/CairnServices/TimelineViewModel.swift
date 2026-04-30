import Foundation
import Observation
import CairnCore
import CairnClaude
import CairnStorage

/// 右侧 Inspector 的 Event Timeline ViewModel。
///
/// 订阅 `EventIngestor.events()` AsyncStream,在 MainActor 上维护:
/// - `currentSessionId`:M2.4 简化 — 第一个到达的 `.persisted`/`.restored` 的 sessionId
///   即为 current;后续同 session 事件追加,其他 session 事件忽略
/// - `events`:当前 session 的时间序列事件列表(按 (lineNumber, blockIndex) 排序)
///
/// M2.6 Tab↔Session 绑定后,`currentSessionId` 会由外部显式 set(用户切 tab)。
@Observable
@MainActor
public final class TimelineViewModel {
    public private(set) var currentSessionId: UUID?
    /// M2.6:当前 session 的生命周期状态。外部(CairnApp)订阅
    /// `SessionLifecycleMonitor.events()` 匹配 sessionId 时调 `updateSessionState`。
    public private(set) var currentSessionState: SessionState?
    public private(set) var events: [Event] = []
    /// M2.5 T15 修订:改为 **stored property**,events 变动时一次性重算。
    /// 原 computed property 导致每次 UI 读都重算 O(N),几千 events 且
    /// ScrollView 频繁重渲时 UI 卡顿(用户反馈 "terminal 处理右侧滚动巨卡")。
    public private(set) var entries: [TimelineEntry] = []
    /// M2.5:折叠状态 —— entry.id 作为 key。
    /// 只对**可折叠** entry(toolCard / mergedTools / thinking)生效;
    /// 其他 entry 永远展开且不在这个集合里。
    /// 折叠态不持久化(重开 app 回默认折叠)。
    public private(set) var expandedIds: Set<UUID> = []

    private let ingestor: EventIngestor
    /// M2.6:switchSession 从 DB 加载历史 events 要用
    private let database: CairnDatabase
    private var task: Task<Void, Never>?
    /// 已入 events 数组的 id 集合,防御重复 emit。M2.3 DB 层 UNIQUE 约束已去重,
    /// UI 再加一层防御(seenIds 单增长,一个 session 几千 UUID 内存可接受)。
    private var seenIds: Set<UUID> = []

    public init(ingestor: EventIngestor, database: CairnDatabase) {
        self.ingestor = ingestor
        self.database = database
    }

    /// 启动订阅。**调用方必须在 ingestor.start() 之前 await 此方法**,
    /// 否则漏 `.restored` 初始事件。
    public func start() async {
        guard task == nil else { return }
        let stream = await ingestor.events()
        task = Task { @MainActor [weak self] in
            for await ev in stream {
                self?.handle(ev)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - M2.5 聚合视图 + 折叠控制

    /// 重算 entries。每次 events 变动(handle 末尾)调用。O(N)。
    private func recomputeEntries() {
        entries = TimelineAggregator.aggregate(events: events)
    }

    /// 单个 entry 的折叠 toggle。只对可折叠 entry 有意义。
    public func toggle(_ id: UUID) {
        if expandedIds.contains(id) {
            expandedIds.remove(id)
        } else {
            expandedIds.insert(id)
        }
    }

    /// ⌘⇧E:对所有可折叠 entry 生效。
    /// 若所有可折叠 entry 都已展开 → 折叠所有;否则 → 展开所有。
    public func toggleExpandAll() {
        let toggableIds: Set<UUID> = Set(entries.compactMap { entry -> UUID? in
            switch entry {
            case .toolCard, .mergedTools:
                return entry.id
            case .single(let e) where e.type == .assistantThinking:
                return e.id
            default:
                return nil
            }
        })
        if !toggableIds.isEmpty, expandedIds.isSuperset(of: toggableIds) {
            expandedIds.subtract(toggableIds)
        } else {
            expandedIds.formUnion(toggableIds)
        }
    }

    /// UI 用:判断 entry 是否展开。对不可折叠 entry 永远返回 true。
    public func isExpanded(_ entry: TimelineEntry) -> Bool {
        switch entry {
        case .toolCard, .mergedTools:
            return expandedIds.contains(entry.id)
        case .single(let e) where e.type == .assistantThinking:
            return expandedIds.contains(e.id)
        default:
            return true
        }
    }

    private func handle(_ ev: EventIngestor.IngestEvent) {
        defer { recomputeEntries() }
        switch ev {
        case .persisted(let e):
            // M2.6 修订:VM 不再 auto-switch。session 切换由外部
            // (broker / MainWindowView .task(id:))显式调 switchSession。
            // 这里只追加属于 currentSession 的事件。
            guard let cur = currentSessionId, e.sessionId == cur else { return }
            guard !seenIds.contains(e.id) else { return }
            seenIds.insert(e.id)
            events.append(e)

        case .restored:
            // M2.6:完全忽略 —— switchSession 手动从 DB 加载历史,精确且时序稳。
            break

        case .error:
            break  // stderr 已 log
        }
    }

    // MARK: - M2.6 session 切换 API

    /// 外部命令切换当前显示的 session。
    /// - nil:清空 events,UI 显示空态(Tab 未绑定 claude session)
    /// - 非 nil:加载该 session 的历史 events(按 lineNumber/blockIndex 排序)
    public func switchSession(_ sessionId: UUID?) async {
        currentSessionId = sessionId
        currentSessionState = nil  // 新 session state 由 monitor 下 tick 提供
        events = []
        seenIds = []
        recomputeEntries()

        guard let sid = sessionId else { return }

        do {
            let historical = try await EventDAO.fetch(
                sessionId: sid, limit: 10_000, offset: 0, in: database
            )
            for e in historical {
                if !seenIds.contains(e.id) {
                    seenIds.insert(e.id)
                    events.append(e)
                }
            }
            recomputeEntries()
        } catch {
            FileHandle.standardError.write(Data(
                "[TimelineViewModel] switchSession load failed: \(error)\n".utf8
            ))
        }
    }

    /// 外部(CairnApp)订阅 SessionLifecycleMonitor.events() 时
    /// match currentSessionId 后调此方法更新 UI badge。
    public func updateSessionState(_ state: SessionState?) {
        currentSessionState = state
    }
}

// MARK: - Testing

extension TimelineViewModel {
    /// 测试 hook:`@testable import CairnServices` 下可见。直接 inject IngestEvent,
    /// 绕过 ingestor.events() 订阅,纯测 VM state machine。
    internal func handleForTesting(_ ev: EventIngestor.IngestEvent) {
        handle(ev)
    }
}
