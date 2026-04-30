# M2.6 实施计划:Tab↔Session 绑定 + Session 生命周期

> **For agentic workers:** 本 plan 给 Claude 主导执行。用户 T13 肉眼验收(多 tab 各跑 claude,timeline 跟随 active tab 切,不互相覆盖;session 状态 live/idle/ended 正确显示)。步骤用 checkbox 跟踪。

**Goal:** 解 M2.4/M2.5 的**体验硬伤** — 多 tab 共用一个 timeline 互相覆盖。做两件事:
1. **每个 Tab 绑定自己的 claude session**(`TabSession.boundClaudeSessionId`);active tab 切换时 timeline 跟着切
2. **Session 生命周期状态机**(spec §4.5 五态 `.live/.idle/.ended/.abandoned/.crashed`)+ 定时更新 + UI 显示 `⋮ live / idle / ended` 指示

**不做**:Hook 审批(M2.7 或 v1.1)、session 历史搜索(v1.1+)、多 session 并排视图(v1.5+)、"⋮ live" 底部活跃指示的动画细节(M2.7 打磨)。

**Architecture:**

三个新组件(CairnServices + CairnClaude 层):
- `TabSessionBroker`(**CairnServices**,`@Observable @MainActor` class)—— 订阅 `JSONLWatcher.events()`,`.discovered` 事件来时匹配到**最近活跃的 tab**(按 cwd 相等优先,tab 启动时间窗口作 tiebreak)并绑定;绑定后通知 `TimelineViewModel.switchSession`
- `SessionLifecycleMonitor`(**CairnClaude**,actor)—— 30s tick 扫 `SessionDAO.fetchActive()`,按 mtime / 悬挂 tool_use 启发式计算 state,写回 DB,发 AsyncStream event 给 UI 订阅
- `TimelineViewModel.switchSession(_:)`(扩现有 VM)—— 外部调,清当前 events + seenIds,从 DB 加载该 session 的历史 events 回填

Tab 侧:
- `TabSession` 加 `boundClaudeSessionId: UUID?`(OSC 7 风格的 @Observable prop)
- `SplitCoordinator` 监听 active tab 变化 → 通知 broker → VM switch
- `LayoutSerializer.PersistedTab` 加 `boundClaudeSessionId`(跨启动恢复绑定)

UI 侧:
- `RightPanelView` 的 "Event Timeline" header 显示 session state badge(`● live` / `○ idle` / `— ended` / `⚠ abandoned` / `✗ crashed`)+ session id 前 8 位(dev 参考)
- `MainWindowView` 内监听 `split.activeTab` 变化,调 `timelineVM.switchSession(activeTab.boundClaudeSessionId)`

CairnApp 改造:
- 把 auto-switch 逻辑从 TimelineViewModel 移到 broker(VM 不再自己切),vm 只按外部 command 切
- broker 和 lifecycle monitor 在 initializeDatabase 里初始化

**Tech Stack:**
- Swift Concurrency(已有)
- `@Observable` class + AsyncStream(已有)
- 新 DB 操作:`EventDAO.fetch(sessionId:limit:offset:)` 已有,直接用
- 新 schema 字段?**不加** —— session state 已在 `sessions.state` 列(M1.2 有),`tab_sessions` 表 M2.6 不碰,tab 绑定信息存 LayoutState JSON

**Claude 耗时**:约 200-260 分钟。
**用户耗时**:约 15 分钟(T13 多 tab × 多 claude 会话,测切换 + session state 显示)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. `TabSession.boundClaudeSessionId` + OSC 风格 `bindClaudeSession(_:)` 方法 | Claude | — |
| T2. `LayoutSerializer.PersistedTab` 加 `boundClaudeSessionId`(Codable 向后兼容用 decodeIfPresent) | Claude | T1 |
| T3. `TabSessionBroker`(CairnServices,@Observable,持 split + watcher 订阅) | Claude | T1 |
| T4. `TimelineViewModel.switchSession(_:)` —— 替代 auto-switch | Claude | — |
| T5. 移除 VM 自 auto-switch 逻辑(T4 替代) | Claude | T4 |
| T6. `SessionLifecycleMonitor`(CairnClaude,actor,30s tick) | Claude | — |
| T7. `SessionDAO.updateState(_:id:in:)` async 方法 | Claude | — |
| T8. `MainWindowView` 监听 activeTab → 调 switchSession | Claude | T3,T4 |
| T9. `RightPanelView` Timeline header 显示 session state badge | Claude | T6 |
| T10. `CairnApp.initializeDatabase` 初始化 broker + monitor,接入生命周期 | Claude | T3,T6 |
| T11. `TabSessionBrokerTests`(cwd 匹配 / 时间窗口 / 无 tab 兜底)| Claude | T3 |
| T12. `SessionLifecycleMonitorTests`(5 态转换)| Claude | T6 |
| T13. VM.switchSession 测试补 | Claude | T4 |
| T14. scaffold bump `0.10.0-m2.5` → `0.11.0-m2.6` | Claude | — |
| T15. Clean build + 全测试 + rebuild + 真实多 tab × claude 触发 | Claude | T1-T14 |
| T16. Push + 用户验收清单 | Claude | T15 |
| T17. **用户验收**(多 tab 各跑 claude;timeline 切换;state badge)| **用户** | T16 |

---

## 文件结构规划

**新建**:

```
Sources/CairnServices/
└── TabSessionBroker.swift               (T3)

Sources/CairnClaude/Lifecycle/
└── SessionLifecycleMonitor.swift        (T6)

Sources/CairnUI/RightPanel/
└── SessionStateBadge.swift              (T9 小组件)

Tests/CairnServicesTests/
└── TabSessionBrokerTests.swift          (T11)

Tests/CairnClaudeTests/Lifecycle/
└── SessionLifecycleMonitorTests.swift   (T12)
```

**修改**:
- `Sources/CairnTerminal/TabSession.swift`(T1 加字段)
- `Sources/CairnTerminal/LayoutSerializer.swift`(T2 PersistedTab 加字段 + snapshot/restore)
- `Sources/CairnServices/TimelineViewModel.swift`(T4+T5)
- `Sources/CairnStorage/DAOs/SessionDAO.swift`(T7 updateState)
- `Sources/CairnUI/MainWindowView.swift`(T8 监听 activeTab)
- `Sources/CairnUI/RightPanel/RightPanelView.swift`(T9 header 加 badge)
- `Sources/CairnApp/CairnApp.swift`(T10 启动 broker + monitor)
- `Sources/CairnCore/CairnCore.swift`(T14 bump)
- scaffold 测试(T14 断言)

---

## 设计决策(pinned)

| # | 决策 | 理由 |
|---|---|---|
| 1 | `TabSessionBroker` 放 CairnServices(不是 CairnClaude)| broker 协调 TabSession(CairnTerminal)+ watcher(CairnClaude)+ VM(CairnServices)三者;spec §3.2 依赖方向 CairnServices 依赖两者合规 |
| 2 | `SessionLifecycleMonitor` 放 CairnClaude | 生命周期是"Claude 观察"逻辑的一部分;monitor 需要 `SessionDAO` 操作,CairnClaude 已依赖 CairnStorage |
| 3 | **绑定策略:cwd 相等优先**;无匹配时绑定到**最近活跃的 tab**(按 activeTabId 所在 group 的 activeTab) | cwd 是"用户在哪个目录跑 claude"的权威信号;JSONL 通过 hash 目录名可 forward-hash 匹配(M2.1 ProjectsDirLayout) |
| 4 | **绑定时机**:`.discovered` 事件触发;每个 session 只绑定一次(broker 记 `alreadyBoundSessionIds`)| session 发现时用户刚跑了 claude,tab 状态"活跃";之后切换其他 tab 不解绑 |
| 5 | **绑定冲突处理**:同 cwd 有多个 tab,绑到**最近活跃的** tab;活跃性按 "被切到的 activeTabId 优先 → split.activeGroupIndex 优先" | 多 tab 同 cwd 场景极少,简化规则 |
| 6 | **Tab 可重新绑定**:若用户关闭原 claude 再跑一个新 claude → 新 session 会发现 → 替换 `boundClaudeSessionId`(原 session 仍留 DB) | 符合用户直觉 |
| 7 | **无匹配 tab 时 session 不绑**(`boundClaudeSessionId` 保持 nil on Tab 侧;DB session 仍记录,只是没绑 UI tab)| 用户在 Cairn 外跑的 claude 不关心 UI,但数据不丢 |
| 8 | `TimelineViewModel` 去除 auto-switch:只按外部 `switchSession(_:)` 指令切 | 保持单一数据源:由 broker/MainWindowView 协调,vm 不自作主张 |
| 9 | `switchSession(nil)` 合法:清空 events + currentSessionId,UI 显示"no session bound" | Tab 新建未跑 claude / 绑定失败时用 |
| 10 | `switchSession(id)` 内部:① 停订阅 ② 清 events/seenIds ③ `EventDAO.fetch(sessionId:id)` 加载历史(按行号排序)④ emit 全部 events 进 events[] | 简单、清晰 |
| 11 | VM 仍订阅 `ingestor.events()` —— 但 `.persisted` 的 event 只在 `event.sessionId == currentSessionId` 时追加,其他忽略 | 多 session 并行时也只显示当前 |
| 12 | `SessionLifecycleMonitor` 间隔 **30s**(spec §4.5 含蓄要求)| 同 M2.1 reconciler 间隔;M2.7 看实测再调 |
| 13 | Lifecycle state 判定用 DB 里的 session 数据(mtime 从 JSONL 文件属性读;悬挂 tool_use 从 events 表 COUNT 查)| 权威数据在 DB;活跃 sessions 数量可控 |
| 14 | `.crashed` 判定:watcher.events() 的 `.removed` 事件 → broker → 调 monitor.markCrashed(id) | 事件驱动,比 mtime 轮询准 |
| 15 | Monitor 发 AsyncStream<StateChange> 对外 | RightPanelView/badge 订阅;M2.7 有可视效果时也用这个流 |
| 16 | `SessionDAO.updateState` **async 版本**(不是 sync)—— monitor 是 actor,async 自然 | 非关键路径;不需要 sync |
| 17 | **UI 指示 badge**:5 态用不同 SF Symbol + 色:`● live` 绿点 / `circle.dotted idle` 灰 / `checkmark.circle ended` 灰 / `exclamationmark.triangle abandoned` 橙 / `xmark.circle crashed` 红 | 简约 |
| 18 | 持久化:`PersistedTab.boundClaudeSessionId`(nil 字段 decodeIfPresent,向后兼容旧 layout JSON) | 用户跨启动恢复绑定 |
| 19 | Broker 持 `weak var split: SplitCoordinator?` —— 不循环持有 | SplitCoordinator 是 AppState,broker 应弱引用 |
| 20 | `MainWindowView` 用 `.onChange(of: split.activeTab?.id)` 监听,调 vm.switchSession;无 activeTab 或 tab.boundClaudeSessionId 为 nil 时 switchSession(nil) | SwiftUI 响应式链 |
| 21 | Broker 的 cwd 匹配:每个 JSONLWatcher discover 的 session **扫前 20 行 JSONL** 找第一条 `type=system` 的 cwd(M0.1 probe Q1 规则)—— 拿到精确 cwd | 精确比 hash 反推好;20 行够 |
| 22 | 扫 JSONL 代价:每个新 session discover 只一次,20 行 × 百字节 = ~2KB;可接受。M2.7 若测出慢再异步化 | 简单实现 |

---

## 对外 API 定义(T3 + T4 + T6 固化)

```swift
// Sources/CairnServices/TabSessionBroker.swift
@Observable
@MainActor
public final class TabSessionBroker {
    public init(
        split: SplitCoordinator,
        watcher: JSONLWatcher,
        onBind: @escaping @MainActor (TabSession, UUID) -> Void
    )
    public func start() async  // 订阅 watcher.events()
    public func stop() async
}
```

```swift
// Sources/CairnServices/TimelineViewModel.swift(新增 API)
extension TimelineViewModel {
    /// 外部命令切换当前显示的 session。
    /// - nil:清空 events,UI 显示空态
    /// - 非 nil:加载该 session 的历史 events(按行号排序)
    public func switchSession(_ sessionId: UUID?) async
}
```

```swift
// Sources/CairnClaude/Lifecycle/SessionLifecycleMonitor.swift
public actor SessionLifecycleMonitor {
    public struct StateChange: Sendable {
        public let sessionId: UUID
        public let oldState: SessionState?
        public let newState: SessionState
        public let timestamp: Date
    }
    public init(database: CairnDatabase, interval: Duration = .seconds(30))
    public func events() -> AsyncStream<StateChange>
    public func start() async
    public func stop() async
    /// watcher 的 .removed 事件来时,外部调此方法立即标 .crashed
    public func markCrashed(sessionId: UUID) async
}
```

---

## 风险清单

| # | 风险 | 缓解 |
|---|---|---|
| 1 | Broker cwd 匹配失败(JSONL 里没 system entry 或 tab cwd 未对齐)| fallback 绑到最近活跃 tab;失败静默不绑,下次 discover 重试 |
| 2 | 多 tab 相同 cwd 时绑定到错 tab | 用 activeGroupIndex + activeTabId 作 tiebreak;M2.7 有冲突用户可 UI 右键重绑(不做) |
| 3 | Lifecycle monitor tick 与 watcher 同步冲突 | 两者都读 DB,DB 事务隔离已足够 |
| 4 | session 首次 discover 时 mtime 很新 → state=live;随后长时间无新 lines → 30s 后 idle ok | 正常流程 |
| 5 | Tab 关闭时 boundClaudeSessionId 持久化与恢复 | LayoutSerializer 已处理;PersistedTab decodeIfPresent 兼容旧 layout |
| 6 | VM.switchSession 中 DB 加载耗时(大 session 数千 events)| EventDAO.fetch(limit:) 默认 limit=10_000 已加(M2.3 设定);M2.7 优化懒加载 |
| 7 | active tab 频繁切换 → VM 频繁 switchSession → DB 来回加载 | debounce 50ms 合并快速切换(T4 加可选 debounce);M2.7 优化 |
| 8 | Lifecycle state 转换漏发(monitor tick 间隔内多次转换)| 每 tick 只比较当前 vs 上次,转换只取最终态 |

---

## Tasks

### Task 1: TabSession.boundClaudeSessionId

**Files**:
- Modify: `Sources/CairnTerminal/TabSession.swift`

- [ ] **Step 1: 加 @Observable 字段 + bind method**

```swift
// TabSession 类里加:
public var boundClaudeSessionId: UUID?

public func bindClaudeSession(_ id: UUID) {
    guard boundClaudeSessionId != id else { return }
    boundClaudeSessionId = id
}
```

- [ ] **Step 2: `Factory.create` 初始化为 nil**(默认行为)
- [ ] **Step 3: build**
- [ ] **Step 4: commit**

```bash
git add Sources/CairnTerminal/TabSession.swift
git commit -m "feat(m2.6): TabSession.boundClaudeSessionId + bindClaudeSession"
```

---

### Task 2: LayoutSerializer.PersistedTab 加字段

**Files**:
- Modify: `Sources/CairnTerminal/LayoutSerializer.swift`

- [ ] **Step 1: PersistedTab 加 optional 字段**

```swift
public struct PersistedTab: Codable, Equatable, Sendable {
    public let id: UUID
    public let workspaceId: UUID
    public let title: String
    public let cwd: String
    public let shell: String
    /// M2.6 加。旧 layout JSON 无此字段 decode 时用 decodeIfPresent 得 nil。
    public let boundClaudeSessionId: UUID?
}
```

- [ ] **Step 2: snapshot 里填;restore 里还原**

```swift
// snapshot:
PersistedTab(
    id: tab.id, workspaceId: tab.workspaceId,
    title: tab.title, cwd: tab.cwd, shell: tab.shell,
    boundClaudeSessionId: tab.boundClaudeSessionId
)

// restore:
created.boundClaudeSessionId = persisted.boundClaudeSessionId  // 直接赋值
```

- [ ] **Step 3: Codable 自动合成,优先显式 decodeIfPresent**(通过 `let boundClaudeSessionId: UUID?` + 默认合成处理 optional)

- [ ] **Step 4: build + 跑 M1.5 LayoutSerializerTests 确认兼容**
- [ ] **Step 5: commit**

```bash
git add Sources/CairnTerminal/LayoutSerializer.swift
git commit -m "feat(m2.6): PersistedTab.boundClaudeSessionId (Codable backward-compat)"
```

---

### Task 3: TabSessionBroker

**Files**:
- Create: `Sources/CairnServices/TabSessionBroker.swift`

```swift
import Foundation
import Observation
import CairnCore
import CairnTerminal
import CairnClaude

/// 绑定 Cairn Tab 到 Claude Session 的 broker。
///
/// 订阅 `JSONLWatcher.events()` 的 `.discovered` 事件,按 cwd 相等匹配到
/// 最近活跃的 tab 并绑定。绑定后通过 onBind 回调通知外部。
@Observable
@MainActor
public final class TabSessionBroker {
    private weak var split: SplitCoordinator?
    private let watcher: JSONLWatcher
    private let onBind: @MainActor (TabSession, UUID) -> Void

    private var consumerTask: Task<Void, Never>?
    /// 已绑定过的 sessionId,防重复
    private var alreadyBoundSessionIds: Set<UUID> = []

    public init(
        split: SplitCoordinator,
        watcher: JSONLWatcher,
        onBind: @escaping @MainActor (TabSession, UUID) -> Void
    ) {
        self.split = split
        self.watcher = watcher
        self.onBind = onBind
    }

    public func start() async {
        guard consumerTask == nil else { return }
        let stream = await watcher.events()
        consumerTask = Task { @MainActor [weak self] in
            for await event in stream {
                if case .discovered(let session) = event {
                    await self?.handleDiscovered(session)
                }
            }
        }
    }

    public func stop() async {
        consumerTask?.cancel()
        consumerTask = nil
    }

    // MARK: - 绑定逻辑

    private func handleDiscovered(_ session: Session) async {
        guard !alreadyBoundSessionIds.contains(session.id) else { return }
        guard let split = split else { return }

        // 🚧 只绑**新鲜 session**(文件 mtime 最近 2 分钟),防止 startup 时
        // 494 个历史 session discover 全部尝试绑定覆盖 active tab。
        let url = URL(fileURLWithPath: session.jsonlPath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date) ?? session.startedAt
        guard Date().timeIntervalSince(mtime) < 120 else {
            alreadyBoundSessionIds.insert(session.id)  // 标记避免重复扫
            return
        }

        // 候选 tab 按优先级排:active tab → active group 其他 tab → 其他 group
        let orderedTabs: [TabSession] = {
            var result: [TabSession] = []
            let activeGroup = split.groups[split.activeGroupIndex]
            if let at = activeGroup.activeTab { result.append(at) }
            result.append(contentsOf: activeGroup.tabs.filter { $0.id != activeGroup.activeTabId })
            for (i, g) in split.groups.enumerated() where i != split.activeGroupIndex {
                result.append(contentsOf: g.tabs)
            }
            return result
        }()

        // cwd 匹配 tab(未绑定的)→ fallback 第一个未绑 tab
        let sessionCwd = await resolveSessionCwd(session)
        let normalizedSessionCwd = sessionCwd.map { Self.normalize($0) }
        let cwdMatched = orderedTabs.first { tab in
            tab.boundClaudeSessionId == nil
                && normalizedSessionCwd != nil
                && Self.normalize(tab.cwd) == normalizedSessionCwd
        }
        let target = cwdMatched ?? orderedTabs.first { $0.boundClaudeSessionId == nil }

        guard let tab = target else { return }  // 无可用 tab,session 继续在 DB,UI 不显示
        alreadyBoundSessionIds.insert(session.id)
        tab.bindClaudeSession(session.id)
        onBind(tab, session.id)
    }

    /// macOS tmp 路径 resolve symlinks(`/tmp` → `/private/tmp`),否则
    /// tab.cwd 和 session.cwd 格式不同可能 false-negative 匹配。
    private static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// 从 JSONL 文件前 N 行找 `type=system` 的 cwd(M0.1 probe Q1 规则)。
    private func resolveSessionCwd(_ session: Session) async -> String? {
        let url = URL(fileURLWithPath: session.jsonlPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 取前 20 行或前 16KB
        let maxBytes = min(data.count, 16 * 1024)
        let prefix = data.prefix(maxBytes)
        guard let text = String(data: prefix, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").prefix(20) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String,
                  type == "system",
                  let cwd = obj["cwd"] as? String
            else { continue }
            return cwd
        }
        return nil
    }
}
```

- [ ] **Step 1: 实现**
- [ ] **Step 2: build**
- [ ] **Step 3: commit**

```bash
git add Sources/CairnServices/TabSessionBroker.swift
git commit -m "feat(m2.6): TabSessionBroker — cwd-based Tab↔Session binding"
```

---

### Task 4: TimelineViewModel.switchSession

**Files**:
- Modify: `Sources/CairnServices/TimelineViewModel.swift`

- [ ] **Step 1: 加 switchSession**

```swift
extension TimelineViewModel {
    /// 外部命令切换当前显示的 session。
    /// - nil:清空 events,UI 显示空态
    /// - 非 nil:加载该 session 的历史 events(按 lineNumber/blockIndex 排序)
    public func switchSession(_ sessionId: UUID?) async {
        currentSessionId = sessionId
        events = []
        seenIds = []
        recomputeEntries()

        guard let sid = sessionId else { return }

        // DB 加载历史 events
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
}
```

**需要 database 引用**:TimelineViewModel.init 现在只接受 `ingestor: EventIngestor`,没 database。加参数:

```swift
public init(ingestor: EventIngestor, database: CairnDatabase) {
    self.ingestor = ingestor
    self.database = database
}
private let database: CairnDatabase
```

- [ ] **Step 2: 改 init 签名;CairnApp 调用点更新**
- [ ] **Step 3: build**
- [ ] **Step 4: commit**

---

### Task 5: 移除 VM 自 auto-switch

**Files**:
- Modify: `Sources/CairnServices/TimelineViewModel.swift`

- [ ] **Step 1: 改 handle .persisted 逻辑,只追加属于 currentSession 的事件,不自己切**

```swift
case .persisted(let e):
    guard let cur = currentSessionId, e.sessionId == cur else { return }
    guard !seenIds.contains(e.id) else { return }
    seenIds.insert(e.id)
    events.append(e)
```

- [ ] **Step 2: VM 完全忽略 `.restored`**(switchSession 自己从 DB 加载,
  不依赖 ingestor emit restored)

```swift
case .restored:
    break  // switchSession 手动加载 DB 历史,更精确;restored 仅供其他订阅者
case .error:
    break
```

- [ ] **Step 3: 修 TimelineViewModelTests**(auto-switch 的 test 改成 switchSession 的 test)
- [ ] **Step 4: commit**

```bash
git add Sources/CairnServices/TimelineViewModel.swift Tests/CairnServicesTests/TimelineViewModelTests.swift
git commit -m "refactor(m2.6): VM 移除 auto-switch,只按外部 switchSession 切"
```

---

### Task 6: SessionLifecycleMonitor

**Files**:
- Create: `Sources/CairnClaude/Lifecycle/SessionLifecycleMonitor.swift`

```swift
import Foundation
import CairnCore
import CairnStorage

/// Session 生命周期状态机(spec §4.5):
/// - `.live`:mtime < 60s
/// - `.idle`:60s ≤ mtime < 5min
/// - `.ended`:mtime ≥ 5min 且无悬挂 tool_use
/// - `.abandoned`:mtime ≥ 30min 且有悬挂 tool_use
/// - `.crashed`:文件被删(外部调 markCrashed)
///
/// 每 interval 秒 tick,对所有 active session 重新计算 state,写回 DB,发事件。
public actor SessionLifecycleMonitor {
    public struct StateChange: Sendable {
        public let sessionId: UUID
        public let oldState: SessionState?
        public let newState: SessionState
        public let timestamp: Date
    }

    private let database: CairnDatabase
    private let interval: Duration
    private var continuations: [AsyncStream<StateChange>.Continuation] = []
    private var task: Task<Void, Never>?

    public init(database: CairnDatabase, interval: Duration = .seconds(30)) {
        self.database = database
        self.interval = interval
    }

    public func events() -> AsyncStream<StateChange> {
        let (stream, cont) = AsyncStream.makeStream(of: StateChange.self)
        continuations.append(cont)
        return stream
    }

    public func start() async {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.interval ?? .seconds(30))
                await self?.tick()
            }
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
        for c in continuations { c.finish() }
        continuations.removeAll()
    }

    public func markCrashed(sessionId: UUID) async {
        await transition(sessionId: sessionId, to: .crashed)
    }

    // MARK: - 内部

    private func tick() async {
        do {
            let activeSessions = try await SessionDAO.fetchActive(in: database)
            for s in activeSessions {
                let newState = computeState(for: s)
                if newState != s.state {
                    await transition(sessionId: s.id, from: s.state, to: newState)
                }
            }
        } catch {
            FileHandle.standardError.write(Data(
                "[LifecycleMonitor] tick failed: \(error)\n".utf8
            ))
        }
    }

    private func computeState(for session: Session) -> SessionState {
        let url = URL(fileURLWithPath: session.jsonlPath)
        // 文件不存在 → crashed
        if !FileManager.default.fileExists(atPath: url.path) {
            return .crashed
        }
        // mtime
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date) ?? session.startedAt
        let age = Date().timeIntervalSince(mtime)

        if age < 60 {
            return .live
        }
        if age < 5 * 60 {
            return .idle
        }

        // > 5min:检查悬挂 tool_use(在 events 表中 paired_event_id IS NULL 的 tool_use)
        let hangingCount = (try? countHangingToolUses(sessionId: session.id)) ?? 0

        if hangingCount == 0 {
            return .ended
        }
        if age >= 30 * 60 {
            return .abandoned
        }
        return .idle  // 5-30min 有悬挂但还没到 abandoned
    }

    private func countHangingToolUses(sessionId: UUID) throws -> Int {
        return try database.readSync { db in
            let row = try GRDB.Row.fetchOne(db, sql: """
                SELECT COUNT(*) FROM events
                WHERE session_id = ? AND type = 'tool_use'
                  AND NOT EXISTS (
                    SELECT 1 FROM events r
                    WHERE r.tool_use_id = events.tool_use_id
                      AND r.type = 'tool_result'
                  )
                """, arguments: [sessionId.uuidString])
            return row?[0] ?? 0
        }
    }

    private func transition(sessionId: UUID, from old: SessionState? = nil, to new: SessionState) async {
        do {
            try await SessionDAO.updateState(sessionId: sessionId, state: new, in: database)
            let change = StateChange(
                sessionId: sessionId, oldState: old,
                newState: new, timestamp: Date()
            )
            for c in continuations { c.yield(change) }
        } catch {
            FileHandle.standardError.write(Data(
                "[LifecycleMonitor] transition failed: \(error)\n".utf8
            ))
        }
    }
}
```

**注**:需要 `import GRDB` for Row。也需要 `CairnDatabase.readSync` (M2.3 加过) 。

- [ ] **Step 1: 实现**
- [ ] **Step 2: build**
- [ ] **Step 3: commit**

---

### Task 7: SessionDAO.updateState

**Files**:
- Modify: `Sources/CairnStorage/DAOs/SessionDAO.swift`

```swift
extension SessionDAO {
    public static func updateState(
        sessionId: UUID, state: SessionState, in db: CairnDatabase
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE sessions SET state = ? WHERE id = ?",
                arguments: [state.rawValue, sessionId.uuidString]
            )
        }
    }
}
```

- [ ] **Step 1: 实现** + 单测
- [ ] **Step 2: commit**

---

### Task 8: MainWindowView 监听 activeTab

**Files**:
- Modify: `Sources/CairnUI/MainWindowView.swift`

- [ ] **Step 1: 用 `.task(id:)` 监听 active tab 的 boundClaudeSessionId**

```swift
// MainWindowView 里加 computed var:
private var activeBoundSessionKey: UUID? {
    guard split.activeGroupIndex < split.groups.count else { return nil }
    return split.groups[split.activeGroupIndex].activeTab?.boundClaudeSessionId
}

// body 里 NavigationSplitView 修饰链加:
.task(id: activeBoundSessionKey) {
    // `.task(id:)` 在 id 变化或首次 appear 时触发,正好满足
    // 初始化时 + 切换时都调用 switchSession
    if let vm = timelineVM {
        await vm.switchSession(activeBoundSessionKey)
    }
}
```

`.task(id:)` 比 `.onChange` 好:首次 appear 也触发(app 启动就有 activeBoundSessionKey 值时不会被 onChange 跳过)。

- [ ] **Step 2: build**
- [ ] **Step 3: commit**

---

### Task 9: RightPanelView Timeline header + SessionStateBadge

**Files**:
- Create: `Sources/CairnUI/RightPanel/SessionStateBadge.swift`
- Modify: `Sources/CairnUI/RightPanel/RightPanelView.swift`

```swift
// SessionStateBadge.swift
import SwiftUI
import CairnCore

public struct SessionStateBadge: View {
    let state: SessionState?

    public init(state: SessionState?) { self.state = state }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var symbol: String {
        switch state {
        case .live:      return "circle.fill"
        case .idle:      return "circle.dotted"
        case .ended:     return "checkmark.circle"
        case .abandoned: return "exclamationmark.triangle.fill"
        case .crashed:   return "xmark.circle.fill"
        case .none:      return "questionmark.circle"
        }
    }
    private var color: Color {
        switch state {
        case .live:      return .green
        case .idle:      return .secondary
        case .ended:     return .secondary
        case .abandoned: return .orange
        case .crashed:   return .red
        case .none:      return .tertiary
        }
    }
    private var label: String {
        switch state {
        case .live:      return "live"
        case .idle:      return "idle"
        case .ended:     return "ended"
        case .abandoned: return "abandoned"
        case .crashed:   return "crashed"
        case .none:      return "—"
        }
    }
}
```

RightPanelView 的 "Event Timeline" 节 header 加 badge:

```swift
HStack {
    Text("Event Timeline").font(.headline)
    Spacer()
    if let vm = timelineVM {
        SessionStateBadge(state: /* 从 vm 或 monitor 拿 state */)
    }
}
```

**问题**:状态从哪拿?vm 当前只有 `currentSessionId`,state 要从哪查?

**方案**:VM 加 `currentSessionState: SessionState?` 字段;`SessionLifecycleMonitor.events()` 订阅,变化时更新 VM。

- [ ] **Step 1: VM 加 currentSessionState 字段 + updateSessionState API**

```swift
// TimelineViewModel.swift 加:
public private(set) var currentSessionState: SessionState?

extension TimelineViewModel {
    /// 外部(CairnApp)订阅 `SessionLifecycleMonitor.events()` 并在状态变化
    /// 且 `change.sessionId == currentSessionId` 时调此方法更新 UI badge。
    public func updateSessionState(_ state: SessionState?) {
        currentSessionState = state
    }
}
```

`switchSession(_:)` 切换时也应重置 state:

```swift
public func switchSession(_ sessionId: UUID?) async {
    currentSessionId = sessionId
    currentSessionState = nil  // 新 session 的初始 state 由 monitor 下次 tick 提供
    events = []
    // ...
}
```

- [ ] **Step 2: SessionStateBadge + RightPanelView header**

```swift
// RightPanelView 里 Event Timeline 节 header:
HStack {
    Text("Event Timeline").font(.headline)
    Spacer()
    if let vm = timelineVM {
        SessionStateBadge(state: vm.currentSessionState)
    }
}
```

- [ ] **Step 3: build**
- [ ] **Step 4: commit**

---

### Task 10: CairnApp.initializeDatabase 装配

**Files**:
- Modify: `Sources/CairnApp/CairnApp.swift`

```swift
// initializeDatabase 末尾(替代 M2.4 的 vm.start + ingestor.start + watcher.start 顺序):
let broker = TabSessionBroker(
    split: split, watcher: watcher,
    onBind: { [weak vm] tab, sessionId in
        // 绑定后若此 tab 正在 active,立即切 vm 到新 session。
        // MainWindowView 的 .task(id:) 也会触发,但让 broker 在绑定同
        // event loop 里主动切可让"新 session 第一刻"无延迟显示。
        if tab.id == split.groups[split.activeGroupIndex].activeTabId {
            Task { @MainActor in
                await vm?.switchSession(sessionId)
            }
        }
    }
)
let monitor = SessionLifecycleMonitor(database: db)
appDelegate.broker = broker
appDelegate.lifecycleMonitor = monitor

// ⚠️ 订阅顺序:所有订阅者先 ready,再启动 emit 源
await vm.start()          // 订阅 ingestor
await broker.start()      // 订阅 watcher(.discovered)
await monitor.start()     // 独立 30s tick
let stateStream = await monitor.events()
Task { @MainActor [weak vm] in
    for await change in stateStream {
        guard let vm = vm else { break }
        if change.sessionId == vm.currentSessionId {
            vm.updateSessionState(change.newState)
        }
    }
}
await ingestor.start()    // 订阅 watcher(.persisted/.restored)
try await watcher.start() // 最后启动 emit 源
```

- [ ] **Step 1: delegate 加 broker + monitor 字段**
- [ ] **Step 2: 装配 + willTerminate stop**
- [ ] **Step 3: commit**

---

### Task 11-13: 测试

每个组件的单元测试。具体代码执行时展开(按 M2.3/M2.4/M2.5 模板):

- **TabSessionBrokerTests**:构造 mock watcher events + 假 SplitCoordinator,验证 cwd 匹配 / 无匹配 fallback / 重复 session 不重绑 / 无 tab 不 crash
- **SessionLifecycleMonitorTests**:构造 tmp JSONL 不同 mtime,验证 5 态转换准确
- **VM.switchSession 测试**:外部调 switchSession → 清空 + 加载 + 正确显示

---

### Task 14: scaffold bump

`0.10.0-m2.5` → `0.11.0-m2.6`

---

### Task 15: Clean build + 全测试 + 真实触发

- [ ] `swift package clean && swift build`
- [ ] `swift test` 期望 191 + ~12 = ~203 tests
- [ ] `./scripts/make-app-bundle.sh debug`
- [ ] 实测:开 2 个 tab,每个跑 claude,测 timeline 切换

---

### Task 16: Push + 清单

---

### Task 17: 用户验收

```bash
open build/Cairn.app
# Tab 1:⌘T 新建,cd ~/proj1,跑 claude,说几句话
# Tab 2:⌘T 新建,cd ~/proj2,跑 claude,说几句话
# ⌘L 切换 tab
# ⌘I 打开 Inspector
```

**验收 6 项:**

| # | 检查 | 期望 |
|---|---|---|
| 1 | Tab 1 active 时,Timeline 显示 Tab 1 里的 claude events | 切 Tab 2,Timeline 切到 Tab 2 的 events |
| 2 | Session state badge 显示(live/idle 等) | Tab 跑 claude 中 = `● live` 绿;空闲 1min+ = `○ idle`;退出 5min+ = `ended` |
| 3 | Cmd+Q 重启,Tab↔Session 绑定恢复 | 之前 Tab 1 绑的 session 还在;Timeline 能继续 |
| 4 | 在 Cairn 外另跑 claude(未绑 tab) | DB 有 session row,但 UI 不显示(nil tab)|
| 5 | 同 cwd 两 tab,后一个跑 claude | broker 绑到最近 active tab(或空着的那个)|
| 6 | 不崩 / 不卡 | 测试全绿 + 实测多 tab 切换流畅 |

---

## Known limitations(留给后续 milestone)

- **Broker 只绑 mtime < 2min 的 session**:启动时 494 历史 session 不会被尝试绑到 active tab;但若用户切到一个**很久前绑过的** tab,它的 `boundClaudeSessionId` 仍然有效(layout 持久化),vm 照样加载那个 session 历史。只是新冒出的 session 不再乱绑
- **单 tab 同时多 session**:一个 tab 里连跑两次 `claude`,新 session 覆盖绑定;需要 session 切换历史 UI 时做(v1.5+)
- **手动重绑**:用户无法 UI 上手动指定 tab↔session(v1.1 可加右键菜单)
- **Multi-session 并排**:多 session 同时看(v1.5+)
- **Hook 审批:** M2.7
- **⋮ live 动画细节:** M2.7 打磨
- **活跃 tabs 数量统计到 status bar:** v1.5

---

## 完成定义

T1-T16 全打勾 + T17 用户 ✅ + tag `m2-6-done` + milestone-log 追 M2.6 条目。
