# M2.4 实施计划:EventBus + Timeline View 基础

> **For agentic workers:** 本 plan 给 Claude 主导执行。用户 T12 做最终肉眼验收(跑真实 Claude session 看 Inspector Timeline 实时刷)。步骤用 checkbox 跟踪。

**Goal:** 把 M2.3 `EventIngestor` 落盘 + AsyncStream 发出的 `IngestEvent` 流,**显示到 UI 右侧 Inspector 的 Event Timeline 面板**。用户一边跑 Claude Code 一边在 Cairn 里看到行式 event 流实时刷新。**不做**:工具卡片合并(M2.5)、Tab↔Session 绑定(M2.6)、工具折叠交互(M2.5)。

**Architecture:**
- `EventBus` **不新增抽象** — 直接用 `EventIngestor.events() -> AsyncStream<IngestEvent>`,M2.3 已经是 fanout 多订阅。spec §8.5 的 "AsyncStream EventBus" 这就是。
- `TimelineViewModel`(CairnServices,@Observable @MainActor class):持有 `currentSessionId: UUID?` + `events: [Event]`,订阅 ingestor.events() 在 MainActor 上更新。session 选择策略(M2.4 简化):**第一个到达的 `.persisted` 事件的 sessionId 即为 current**,后续自动切到最新活跃 session。M2.6 Tab↔Session 绑定后此逻辑让位给正式映射。
- `TimelineView`(CairnUI):`@Bindable vm` → `LazyVStack` + `EventRowView`,空态给引导文案。
- `EventRowView`(CairnUI):单行渲染 — emoji icon + category color + summary 一行,监听 spec §6.4 颜色/图标表。合并 / 折叠留 M2.5。
- `CairnApp`:把 M2.3 dev-only harness 的 Ingestor **正式化** — 不再依赖 `CAIRN_DEV_WATCH=1`,每次启动都起 watcher + ingestor + timeline,RightPanelView 接入 vm。

**Tech Stack:**
- `@Observable` + `@Bindable`(Swift Observation,M1.4 已用)
- `LazyVStack` + `ScrollView`(spec §6.9 要求:>500 events 必须 lazy)
- `ScrollViewReader` + `.onChange(of: vm.events.count)` 自动滚到底
- 依赖链:CairnUI ← CairnServices ← CairnClaude(M2.3 已 OK)

**Claude 耗时**:约 150-210 分钟。
**用户耗时**:约 10 分钟(T12:打开 app,另开终端跑 claude,看 Inspector 面板是否刷)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. Category icon/color 映射表(CairnUI 扩展 ToolCategory / EventType) | Claude | — |
| T2. `TimelineViewModel`(CairnServices,@Observable + 订阅 ingestor.events()) | Claude | T1 |
| T3. `EventRowView`(CairnUI,单行:icon + summary + 时间戳) | Claude | T1 |
| T4. `TimelineView`(CairnUI,LazyVStack + 空态 + 自动滚底) | Claude | T3 |
| T5. `RightPanelView` 接入 vm,替换"Event Timeline"空态 | Claude | T2,T4 |
| T6. `CairnApp` 正式化 Ingestor(非 dev env,每次启动);SplitCoordinator + vm + db + ingestor 生命周期 | Claude | T2 |
| T7. `TimelineViewModelTests`:送假 IngestEvent 流,验证 events 数组增长 + session 切换 | Claude | T2 |
| T8. `EventRowViewTests` / TimelineView Preview(手动检查渲染) | Claude | T3,T4 |
| T9. scaffold bump `0.8.0-m2.3` → `0.9.0-m2.4` | Claude | — |
| T10. Clean build + 全测试 + rebuild .app + 真实 Claude 触发 + Inspector 肉眼 | Claude | T1-T9 |
| T11. Push + 验收清单 | Claude | T10 |
| T12. **用户验收**(开 app → 跑 claude → 看 Inspector 实时刷) | **用户** | T11 |

---

## 文件结构规划

**新建**:

```
Sources/CairnUI/RightPanel/
├── TimelineView.swift           (T4)
├── EventRowView.swift           (T3)
└── EventStyleMap.swift          (T1 icon/color 表)

Sources/CairnServices/
└── TimelineViewModel.swift      (T2)

Tests/CairnServicesTests/
└── TimelineViewModelTests.swift (T7)

Tests/CairnUITests/
└── EventRowViewTests.swift      (T8,渲染不崩)
```

**修改**:
- `Sources/CairnUI/RightPanel/RightPanelView.swift`(T5 接入 vm)
- `Sources/CairnUI/MainWindowView.swift`(T5/T6 透传 vm)
- `Sources/CairnApp/CairnApp.swift`(T6 正式化 Ingestor + vm 生命周期)
- `Sources/CairnCore/CairnCore.swift`(T9 bump)
- `Tests/CairnCoreTests/CairnCoreTests.swift`(T9 断言)
- `Tests/CairnStorageTests/CairnStorageTests.swift`(T9 断言)

---

## 设计决策(pinned)

| # | 决策 | 理由 |
|---|---|---|
| 1 | **不引入 EventBus 中间层** — 直接用 `EventIngestor.events()` | M2.3 已 fanout;加一层只增代码无功能 |
| 2 | `TimelineViewModel` 放 CairnServices,**@Observable @MainActor class** | 跨 UI/Services 边界,Observation 原生;MainActor 保证 events 数组只在主线程改,UI 无竞态 |
| 3 | **session 选择:auto-current**(第一个 `.persisted` 事件的 sessionId 即为 current;后续同 session 追加,新 session 到达时 **不自动切换**—— 避免 UI 乱跳) | M2.4 不做 Tab↔Session 绑定;最小能 work 的行为 |
| 4 | `.restored(sid, events)` 事件:**仅当 sid == currentSessionId 才 prepend 到 events 前** | 跨启动加载历史 |
| 5 | `events: [Event]` 作为单数组存 MainActor state,追加 O(1) | Swift Array 追加分摊 O(1);几千 event 可接受;M2.7 如需优化看 virtualization |
| 6 | Timeline 用 `LazyVStack`(spec §6.9 > 500 events 必须 lazy) | 性能;ScrollView + LazyVStack 原生组合 |
| 7 | **自动滚到底**:监听 `events.count` 变化,`ScrollViewReader.scrollTo(last, anchor: .bottom)` | "边跑 Claude 边看刷新" 的核心体验 |
| 8 | EventRowView **一行式**:icon + summary + 右侧时间戳;不折叠、不合并 | M2.4 是"基础",卡片合并 + 折叠是 M2.5 |
| 9 | icon/color 表独立 `EventStyleMap.swift`,spec §6.4 映射集中一处 | 日后改视觉或主题集中改一个文件 |
| 10 | Dark/Light 兼容:colors 用 `Color.accentColor` + semantic 系统色(`.red`/`.blue` 等),不硬编码 hex | spec §6.8;macOS 自动跟随系统主题 |
| 11 | Ingestor 生命周期:**每次 App 启动都起**(非 dev env);`CairnAppDelegate` 持有 | 这是 Cairn 的核心能力;不再需要 CAIRN_DEV_WATCH |
| 12 | **不改 `CAIRN_DEV_WATCH` env 语义**;保留当它额外开 stderr 日志的"更啰嗦模式" | 开发期 debug 有用,不妨碍生产用户 |
| 13 | TimelineView 空态文案:沿用 M1.3 的 "Events stream in as Claude Code runs." | 保持一致 |
| 14 | **不做 Tab↔Session UI 切换** — 用户不能在 UI 里切 session | M2.6 做;M2.4 就"看最新 live session 的流" |
| 15 | Event **去重**:单 session 内按 `event.id` 追加;忽略已在 events 里的 id(防 ingestor 重复 emit) | 防御性,虽然 M2.3 的 sid+line+block UNIQUE 已保证 DB 无重复 |
| 16 | compact_boundary 和 error 照正常渲染,**不特殊插入分隔** | M2.5 决定视觉细节 |
| 17 | api_usage **仍显示**(不过滤);内容可能很"悄悄"(spec §6.4 "绿悄悄") | spec 要求;M2.5 考虑是否默认折叠 |
| 18 | Timeline **不做快捷键**(⌘⇧E 展开/折叠 / ⌘⇧B Budget 是 M2.5+M3.x) | scope |
| 19 | CairnServices 加 target 依赖 `CairnClaude`(若未添加)| `TimelineViewModel` 要 `import CairnClaude` |
| 20 | 测试策略:TimelineViewModel 暴露 `internal handleForTesting(_:)`,测试 `@testable import` 直接灌 IngestEvent,绕过 ingestor.events() 订阅 | 纯 VM 逻辑可测;UI 用 Preview 手动看 |
| 21 | **vm 双持**:AppDelegate(生命周期,survive body redraws + willTerminate stop)+ App struct `@State private var timelineVM: TimelineViewModel?`(SwiftUI 观察;initializeDatabase 里同时 set 两处) | 仅 AppDelegate 持时 vm 赋值不触发 UI 重渲(AppDelegate 不是 @Observable);仅 @State 时 willTerminate 没稳定句柄。双持是 M1.5 database 同类问题的方案 |
| 22 | `ForEach(vm.events, id: \.id)` 显式传 keypath | Event 有 `let id: UUID` 但未 `conform Identifiable`,避免动 CairnCore |
| 23 | `.restored(sid, _)` 也可设 currentSessionId(首个到达时)| handleDiscovered 可能先 emit `.restored` 再之后 `.persisted`;如果 restored 只在 currentSessionId==sid 时处理,首个 restored 会丢。加"若 currentSessionId==nil 设为 sid"逻辑 |

---

## 风险清单

| # | 风险 | 缓解 |
|---|---|---|
| 1 | MainActor 上 for-await 阻塞主线程 | for-await 本身不阻塞(await 点 yield);每个 event handle O(1) 追加数组,不重 |
| 2 | events 数组几千条触发 SwiftUI 重 diff | LazyVStack 只渲染可见行;内部 ForEach 用 `event.id` 作 id 稳定 diff |
| 3 | 自动滚到底影响用户手动向上看历史 | M2.4 简化:不检测用户手动滚;M2.5 做"只在用户在底时自动滚"逻辑 |
| 4 | 多次 `.persisted` 同 id(极罕见,M2.3 UNIQUE 约束过滤)导致数组重复 | 决策 #15:按 id 去重 |
| 5 | 新 session 出现时 UI 突然切 context | 决策 #3:不自动切,用户看到的是第一个到达的 session;M2.6 做 Tab↔Session 绑定后替代 |
| 6 | initializeDatabase 初始化顺序:db 就位 → 开 watcher → 开 ingestor → 开 vm | T6 顺序:db init → vm 构造(持 ingestor 引用) → ingestor.start() 先 → watcher.start() 后 → vm.start()(订阅 ingestor.events) | |

---

## 对外 API 定义

```swift
// Sources/CairnServices/TimelineViewModel.swift

@Observable
@MainActor
public final class TimelineViewModel {
    public private(set) var currentSessionId: UUID?
    public private(set) var events: [Event] = []

    public init(ingestor: EventIngestor)

    /// 启动订阅。对应 stop 取消。内部起 Task @MainActor 循环 for-await。
    public func start() async

    public func stop()
}
```

```swift
// Sources/CairnUI/RightPanel/TimelineView.swift

public struct TimelineView: View {
    @Bindable var vm: TimelineViewModel
    public init(vm: TimelineViewModel)
    public var body: some View { ... }
}
```

---

## Tasks

### Task 1: EventStyleMap(icon/color)

**Files**:
- Create: `Sources/CairnUI/RightPanel/EventStyleMap.swift`

- [ ] **Step 1: 实现**

```swift
// Sources/CairnUI/RightPanel/EventStyleMap.swift
import SwiftUI
import CairnCore

/// spec §6.4 Event Timeline 视觉语言 — icon / color 映射。
/// v1 两种入口:`EventType`(对 toolUse 之外的事件)+ `ToolCategory`(toolUse 细分)。
enum EventStyleMap {
    static func icon(for event: Event) -> String {
        // toolUse 先按 category 分支(spec §6.4 把 toolUse 细分到 10 种)
        if event.type == .toolUse, let cat = event.category {
            switch cat {
            case .shell:       return "🔧"
            case .fileRead:    return "📖"
            case .fileWrite:   return "✏️"
            case .fileSearch:  return "🔍"
            case .webFetch:    return "🌐"
            case .mcpCall:     return "🔌"
            case .subagent:    return "🧬"
            case .todo:        return "📋"
            case .planMgmt:    return "📐"
            case .askUser:     return "❓"
            case .ide:         return "💻"
            case .other:       return "🛠"
            default:           return "🛠"
            }
        }
        switch event.type {
        case .userMessage:       return "👤"
        case .assistantText:     return "💬"
        case .assistantThinking: return "💭"
        case .toolResult:        return "↩︎"
        case .apiUsage:          return "💰"
        case .compactBoundary:   return "───"
        case .error:             return "⚠️"
        case .planUpdated:       return "📐"
        case .sessionBoundary:   return "✴"
        case .approvalRequested, .approvalDecided: return "🔐"
        default:                 return "•"
        }
    }

    static func color(for event: Event) -> Color {
        if event.type == .toolUse, let cat = event.category {
            switch cat {
            case .fileRead, .fileSearch: return .blue
            case .fileWrite:             return .orange
            case .webFetch:              return .purple
            case .mcpCall:               return .teal
            case .subagent:              return .pink
            case .todo:                  return .yellow
            case .askUser:               return .orange
            default:                     return .secondary
            }
        }
        switch event.type {
        case .userMessage:       return .secondary
        case .assistantText:     return .primary
        case .assistantThinking: return .secondary
        case .toolResult:        return .secondary
        case .apiUsage:          return .green
        case .compactBoundary:   return .secondary
        case .error:             return .red
        default:                 return .secondary
        }
    }
}
```

- [ ] **Step 2: build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 3: commit**

```bash
git add Sources/CairnUI/RightPanel/EventStyleMap.swift
git commit -m "feat(m2.4): EventStyleMap — spec §6.4 icon/color mapping for Event"
```

---

### Task 2: TimelineViewModel

**Files**:
- Create: `Sources/CairnServices/TimelineViewModel.swift`
- Modify: `Package.swift`(CairnServices 依赖 CairnClaude 已有,无需改)

- [ ] **Step 1: 检查 Package.swift 已有 CairnClaude 依赖**

```bash
grep "CairnServices\"" Package.swift
```
期望:`.target(name: "CairnServices", dependencies: ["CairnCore", "CairnStorage", "CairnClaude"])`。

- [ ] **Step 2: 实现 TimelineViewModel**

```swift
// Sources/CairnServices/TimelineViewModel.swift
import Foundation
import Observation
import CairnCore
import CairnClaude

/// 右侧 Inspector 的 Event Timeline ViewModel。
///
/// 订阅 `EventIngestor.events()` AsyncStream,在 MainActor 上维护:
/// - `currentSessionId`:M2.4 简化 — 第一个到达的 `.persisted` 事件的 sessionId 即为 current
/// - `events`:当前 session 的按时间顺序事件列表
///
/// M2.6 Tab↔Session 绑定后,`currentSessionId` 会由外部显式 set(用户切 tab)。
@Observable
@MainActor
public final class TimelineViewModel {
    public private(set) var currentSessionId: UUID?
    public private(set) var events: [Event] = []

    private let ingestor: EventIngestor
    private var task: Task<Void, Never>?
    /// 已入 events 数组的 id 集合,防御重复 emit(M2.3 DB 层已去重,UI 再加一层)
    private var seenIds: Set<UUID> = []

    public init(ingestor: EventIngestor) {
        self.ingestor = ingestor
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

    private func handle(_ ev: EventIngestor.IngestEvent) {
        switch ev {
        case .persisted(let e):
            if currentSessionId == nil {
                // 首个 event:设定 current session,清 events 开始记录
                currentSessionId = e.sessionId
                events = []
                seenIds = []
            }
            guard e.sessionId == currentSessionId else { return }
            guard !seenIds.contains(e.id) else { return }
            seenIds.insert(e.id)
            events.append(e)

        case .restored(let sid, let restoredEvents):
            // 若 current 还没定,restored 设定 current(首个 discover 就可能先到)
            if currentSessionId == nil {
                currentSessionId = sid
            }
            guard sid == currentSessionId else { return }
            // 历史 events 按 (lineNumber, blockIndex) 排序,prepend
            let sorted = restoredEvents.sorted {
                ($0.lineNumber, $0.blockIndex) < ($1.lineNumber, $1.blockIndex)
            }
            let newOnes = sorted.filter { !seenIds.contains($0.id) }
            for e in newOnes { seenIds.insert(e.id) }
            events = newOnes + events

        case .error:
            break  // M2.4 不在 UI 显示 ingest 错误;stderr 已 log
        }
    }
}
```

- [ ] **Step 3: build**

```bash
swift build
```

- [ ] **Step 4: commit**

```bash
git add Sources/CairnServices/TimelineViewModel.swift
git commit -m "feat(m2.4): TimelineViewModel — @Observable MainActor subscribing EventIngestor.events()"
```

---

### Task 3: EventRowView

**Files**:
- Create: `Sources/CairnUI/RightPanel/EventRowView.swift`

- [ ] **Step 1: 实现**

```swift
// Sources/CairnUI/RightPanel/EventRowView.swift
import SwiftUI
import CairnCore

/// Event Timeline 单行。spec §6.4 —— icon + summary + 时间戳。
/// M2.4 是"基础"版本;合并("Read × 3")/ 折叠交互是 M2.5。
public struct EventRowView: View {
    let event: Event

    public init(event: Event) {
        self.event = event
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(EventStyleMap.icon(for: event))
                .font(.system(size: 13))
                .frame(width: 20, alignment: .center)

            Text(event.summary)
                .font(.system(.caption, design: .default))
                .foregroundStyle(EventStyleMap.color(for: event))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.formatTime(event.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

#if DEBUG
#Preview("event-rows") {
    VStack(alignment: .leading, spacing: 0) {
        EventRowView(event: Event(
            sessionId: UUID(), type: .userMessage,
            timestamp: Date(), lineNumber: 1, summary: "hello, fix the auth bug"
        ))
        EventRowView(event: Event(
            sessionId: UUID(), type: .toolUse, category: .shell,
            toolName: "Bash", toolUseId: "tu_1",
            timestamp: Date(), lineNumber: 2, summary: "Bash(command=ls -la)"
        ))
        EventRowView(event: Event(
            sessionId: UUID(), type: .assistantText,
            timestamp: Date(), lineNumber: 3, summary: "Let me check the auth module..."
        ))
        EventRowView(event: Event(
            sessionId: UUID(), type: .apiUsage,
            timestamp: Date(), lineNumber: 4, summary: "in=1200 out=340 cache=800"
        ))
        EventRowView(event: Event(
            sessionId: UUID(), type: .error,
            timestamp: Date(), lineNumber: 5, summary: "tool_result reported error"
        ))
    }
    .frame(width: 360)
    .padding()
}
#endif
```

- [ ] **Step 2: build + preview 肉眼(可选)**

```bash
swift build
```
Xcode preview 验(若有),否则 T10 真 app 里看。

- [ ] **Step 3: commit**

```bash
git add Sources/CairnUI/RightPanel/EventRowView.swift
git commit -m "feat(m2.4): EventRowView — one-line icon + summary + timestamp (spec §6.4)"
```

---

### Task 4: TimelineView

**Files**:
- Create: `Sources/CairnUI/RightPanel/TimelineView.swift`

- [ ] **Step 1: 实现**

```swift
// Sources/CairnUI/RightPanel/TimelineView.swift
import SwiftUI
import CairnCore
import CairnServices

/// Event Timeline —— Inspector 里的实时事件流面板。
/// spec §6.4;M2.4 基础版本(无合并 / 折叠 / 搜索)。
public struct TimelineView: View {
    @Bindable var vm: TimelineViewModel

    public init(vm: TimelineViewModel) {
        self.vm = vm
    }

    public var body: some View {
        if vm.events.isEmpty {
            VStack(spacing: 8) {
                Text("Events stream in as Claude Code runs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Open a terminal tab, run `claude`, and talk to it — events will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // Event 有 `let id: UUID` 但未 conform Identifiable;
                    // 用显式 keyPath 避免改 CairnCore。
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.events, id: \.id) { event in
                            EventRowView(event: event)
                                .id(event.id)
                            Divider().opacity(0.3)
                        }
                    }
                }
                .onChange(of: vm.events.count) { _, _ in
                    if let last = vm.events.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: build**

```bash
swift build
```

- [ ] **Step 3: commit**

```bash
git add Sources/CairnUI/RightPanel/TimelineView.swift
git commit -m "feat(m2.4): TimelineView — LazyVStack + auto-scroll-to-bottom on events append"
```

---

### Task 5: RightPanelView 接入 vm

**Files**:
- Modify: `Sources/CairnUI/RightPanel/RightPanelView.swift`
- Modify: `Sources/CairnUI/MainWindowView.swift`(透传 vm)

- [ ] **Step 1: RightPanelView 接 optional vm**

```swift
// Sources/CairnUI/RightPanel/RightPanelView.swift
import SwiftUI
import CairnServices

public struct RightPanelView: View {
    /// optional —— App 启动过程中 vm 尚未 init 时为 nil;SwiftUI 再渲后填入。
    let timelineVM: TimelineViewModel?

    public init(timelineVM: TimelineViewModel?) {
        self.timelineVM = timelineVM
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section(
                    title: "Current Task",
                    emptyLine: "No task selected."
                )

                section(
                    title: "Budget",
                    emptyLine: "Budget appears when a Task is active."
                )

                // Event Timeline 节
                VStack(alignment: .leading, spacing: 8) {
                    Text("Event Timeline").font(.headline)
                    if let vm = timelineVM {
                        TimelineView(vm: vm)
                            .frame(minHeight: 240)
                    } else {
                        Text("Initializing…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
        }
    }

    private func section(title: String, emptyLine: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(emptyLine).font(.callout).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
#Preview {
    RightPanelView(timelineVM: nil).frame(width: 360, height: 600)
}
#endif
```

- [ ] **Step 2: MainWindowView 透传 optional vm**

```swift
// MainWindowView.swift
let timelineVM: TimelineViewModel?  // optional,非 @Bindable(可为 nil 时不能直接 @Bindable)

public init(
    columnVisibility: Binding<NavigationSplitViewVisibility>,
    showInspector: Binding<Bool>,
    split: SplitCoordinator,
    timelineVM: TimelineViewModel?
) {
    // ...
    self.timelineVM = timelineVM
}

// 在 .inspector 里:
.inspector(isPresented: $showInspector) {
    RightPanelView(timelineVM: timelineVM)
    // ...
}
```

`TimelineView` 只对 non-optional vm 渲染,RightPanelView 里用 `if let vm` 分流,TimelineView 内部仍 `@Bindable var vm: TimelineViewModel`(non-optional)。

**更新 MainWindowView 的 `#Preview`**(加 `timelineVM: nil`):

```swift
#if DEBUG
#Preview("Main window") {
    MainWindowView(
        columnVisibility: .constant(.all),
        showInspector: .constant(true),
        split: SplitCoordinator(),
        timelineVM: nil  // ← M2.4 加
    )
    .frame(width: 1280, height: 800)
}
#endif
```

- [ ] **Step 3: build**

```bash
swift build
```

- [ ] **Step 4: commit**

```bash
git add Sources/CairnUI/RightPanel/RightPanelView.swift Sources/CairnUI/MainWindowView.swift
git commit -m "feat(m2.4): RightPanelView + MainWindowView 接入 TimelineViewModel"
```

---

### Task 6: CairnApp 正式化 Ingestor + vm 生命周期

**Files**:
- Modify: `Sources/CairnApp/CairnApp.swift`

- [ ] **Step 1: AppDelegate 加 timelineVM 字段**

```swift
@MainActor
final class CairnAppDelegate: NSObject, NSApplicationDelegate {
    // ... 现有字段
    var timelineVM: TimelineViewModel?
}
```

- [ ] **Step 2: initializeDatabase 末尾把 M2.3 dev harness 升级为"非 dev 也跑"**

保留 `CAIRN_DEV_WATCH=1` 的 stderr 日志,但把 Ingestor + vm 的创建从 env-gated 改为**默认跑**:

```swift
@MainActor
private func initializeDatabase() async {
    // ... 现有 DB / workspace / layout restore 逻辑不变

    // 正式化 M2.3 Ingestor(不再 env-gated):每次启动都起 watcher + ingestor + timelineVM
    guard let db = appDelegate.database else { return }
    let root = URL(fileURLWithPath: "\(NSHomeDirectory())/.claude/projects")
    let watcher = JSONLWatcher(
        database: db, projectsRoot: root,
        defaultWorkspaceId: appDelegate.defaultWorkspaceId
    )
    let ingestor = EventIngestor(database: db, watcher: watcher)
    let vm = TimelineViewModel(ingestor: ingestor)
    appDelegate.jsonlWatcher = watcher
    appDelegate.eventIngestor = ingestor
    appDelegate.timelineVM = vm

    // 顺序:vm.start() 订阅 ingestor → ingestor.start() 订阅 watcher → watcher.start() 开始 emit
    await vm.start()
    await ingestor.start()

    // dev harness 日志(可选)
    if ProcessInfo.processInfo.environment["CAIRN_DEV_WATCH"] == "1" {
        let stream = await ingestor.events()
        Task {
            var persistedCount = 0
            for await event in stream {
                switch event {
                case .persisted: persistedCount += 1
                    if persistedCount.isMultiple(of: 100) {
                        FileHandle.standardError.write(Data(
                            "[Ingestor] persisted \(persistedCount) events\n".utf8
                        ))
                    }
                case .restored(let sid, let es):
                    FileHandle.standardError.write(Data(
                        "[Ingestor] restored \(es.count) events for \(sid)\n".utf8
                    ))
                case .error(let sid, _, let err):
                    FileHandle.standardError.write(Data(
                        "[Ingestor] error on \(sid): \(err)\n".utf8
                    ))
                }
            }
        }
    }

    do {
        try await watcher.start()
    } catch {
        FileHandle.standardError.write(Data(
            "[Ingestor] watcher start failed: \(error)\n".utf8
        ))
    }
}
```

- [ ] **Step 3: App struct 加 `@State` vm + body 透传**

```swift
@main
struct CairnApp: App {
    @NSApplicationDelegateAdaptor(CairnAppDelegate.self) var appDelegate

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector: Bool = true
    @State private var split = SplitCoordinator()
    /// M2.4 双持:delegate 持生命周期版(willTerminate stop);@State 持 UI
    /// 观察版(vm init 后赋值触发 SwiftUI 重渲 RightPanelView)。
    /// initializeDatabase 同时 set `appDelegate.timelineVM` 和 `self.timelineVM`。
    @State private var timelineVM: TimelineViewModel?

    var body: some Scene {
        WindowGroup("Cairn", content: {
            MainWindowView(
                columnVisibility: $columnVisibility,
                showInspector: $showInspector,
                split: split,
                timelineVM: timelineVM  // 首次渲 nil → vm init 后 @State 变化自动重渲
            )
            .task {
                await initializeDatabase()
            }
            // ... 现有 .onChange 链不变
        })
        // ... 现有 .defaultSize / .commands 不变
    }

    @MainActor
    private func initializeDatabase() async {
        // ... 现有 DB / workspace / layout restore 逻辑不变

        guard let db = appDelegate.database else { return }
        let root = URL(fileURLWithPath: "\(NSHomeDirectory())/.claude/projects")
        let watcher = JSONLWatcher(...)
        let ingestor = EventIngestor(database: db, watcher: watcher)
        let vm = TimelineViewModel(ingestor: ingestor)

        // 双持:delegate + @State
        appDelegate.jsonlWatcher = watcher
        appDelegate.eventIngestor = ingestor
        appDelegate.timelineVM = vm
        self.timelineVM = vm  // ← 触发 SwiftUI 重渲

        await vm.start()       // 订阅 ingestor.events()
        await ingestor.start() // 订阅 watcher.events()
        // 可选:CAIRN_DEV_WATCH stderr 日志
        try? await watcher.start()
    }
}
```

- [ ] **Step 4: willTerminate 里补 vm.stop**

```swift
nonisolated func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated {
        saveLayoutNow(reason: "willTerminate")
        timelineVM?.stop()
        if let ingestor = eventIngestor {
            Task { await ingestor.stop() }
        }
        if let watcher = jsonlWatcher {
            Task { await watcher.stop() }
        }
    }
}
```

- [ ] **Step 5: build**

```bash
swift build
```

- [ ] **Step 6: commit**

```bash
git add Sources/CairnApp/CairnApp.swift Sources/CairnUI/
git commit -m "feat(m2.4): CairnApp 正式化 Ingestor + TimelineViewModel 生命周期,RightPanel 接入"
```

---

### Task 7: TimelineViewModelTests

**Files**:
- Create: `Tests/CairnServicesTests/TimelineViewModelTests.swift`

- [ ] **Step 1: 检查 CairnServicesTests target 存在**

```bash
grep "CairnServicesTests" Package.swift
```
若无,先加 `.testTarget(name: "CairnServicesTests", dependencies: ["CairnServices"])`。

- [ ] **Step 2: 写测试**

VM 订阅 `EventIngestor.events()`,直接 mock 一个 EventIngestor 太重。最简:**跳过 ingestor,直接测 handle 方法**。但 `handle` 是 private。

**方案**:`handle(_ ev:)` 保持 private;加一个 `internal` 测试 hook,`@testable import CairnServices` 即可访问。

```swift
// TimelineViewModel.swift 里加
extension TimelineViewModel {
    /// 测试 hook:`@testable import` 下可见。直接 inject IngestEvent,
    /// 绕过 ingestor.events() 订阅,纯测 VM state machine。
    internal func handleForTesting(_ ev: EventIngestor.IngestEvent) {
        handle(ev)
    }
}
```

然后测试:

```swift
// Tests/CairnServicesTests/TimelineViewModelTests.swift
import XCTest
import CairnCore
import CairnClaude
import CairnStorage
@testable import CairnServices

@MainActor
final class TimelineViewModelTests: XCTestCase {
    private func makeVM() async throws -> TimelineViewModel {
        let db = try await CairnDatabase(
            location: .inMemory, migrator: CairnStorage.makeMigrator()
        )
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tvm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let defaultWsId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        try await WorkspaceDAO.upsert(
            Workspace(id: defaultWsId, name: "W", cwd: "/tmp"), in: db
        )
        let watcher = JSONLWatcher(
            database: db, projectsRoot: rootURL, defaultWorkspaceId: defaultWsId
        )
        let ingestor = EventIngestor(database: db, watcher: watcher)
        return TimelineViewModel(ingestor: ingestor)
    }

    func test_firstPersisted_setsCurrentSession() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        let e = Event(sessionId: sid, type: .userMessage,
                      timestamp: Date(), lineNumber: 1, summary: "hi")
        vm.handleForTesting(.persisted(e))
        XCTAssertEqual(vm.currentSessionId, sid)
        XCTAssertEqual(vm.events.count, 1)
    }

    func test_subsequentSameSession_appends() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        for i in 1...5 {
            let e = Event(sessionId: sid, type: .userMessage,
                          timestamp: Date(), lineNumber: Int64(i), summary: "msg \(i)")
            vm.handleForTesting(.persisted(e))
        }
        XCTAssertEqual(vm.events.count, 5)
        XCTAssertEqual(vm.events.map(\.lineNumber), [1,2,3,4,5])
    }

    func test_otherSessionIgnored() async throws {
        let vm = try await makeVM()
        let sid1 = UUID(), sid2 = UUID()
        vm.handleForTesting(.persisted(Event(
            sessionId: sid1, type: .userMessage,
            timestamp: Date(), lineNumber: 1, summary: "s1"
        )))
        vm.handleForTesting(.persisted(Event(
            sessionId: sid2, type: .userMessage,
            timestamp: Date(), lineNumber: 1, summary: "s2-ignored"
        )))
        XCTAssertEqual(vm.currentSessionId, sid1)
        XCTAssertEqual(vm.events.count, 1)
        XCTAssertEqual(vm.events[0].summary, "s1")
    }

    func test_duplicateId_filtered() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        let e = Event(sessionId: sid, type: .userMessage,
                      timestamp: Date(), lineNumber: 1, summary: "dup")
        vm.handleForTesting(.persisted(e))
        vm.handleForTesting(.persisted(e))  // 同 id 再次 emit
        XCTAssertEqual(vm.events.count, 1)
    }

    func test_restored_prependsHistory_whenSessionMatches() async throws {
        let vm = try await makeVM()
        let sid = UUID()
        // 先 live event 设定 current session
        let live = Event(id: UUID(), sessionId: sid, type: .userMessage,
                         timestamp: Date(), lineNumber: 10, summary: "live")
        vm.handleForTesting(.persisted(live))

        // restored 带历史 1-5 行
        let history = (1...5).map { i in
            Event(id: UUID(), sessionId: sid, type: .userMessage,
                  timestamp: Date(), lineNumber: Int64(i), summary: "h\(i)")
        }
        vm.handleForTesting(.restored(sessionId: sid, events: history))
        XCTAssertEqual(vm.events.count, 6)
        XCTAssertEqual(vm.events.first?.summary, "h1")  // prepend 后 h1 在最前
        XCTAssertEqual(vm.events.last?.summary, "live")
    }
}
```

- [ ] **Step 3: 跑**

```bash
swift test --filter TimelineViewModelTests 2>&1 | grep -E "Executed|fail"
```
期望:5 tests pass。

- [ ] **Step 4: commit**

```bash
git add Sources/CairnServices/TimelineViewModel.swift Tests/CairnServicesTests/TimelineViewModelTests.swift Package.swift
git commit -m "test(m2.4): TimelineViewModel 5 tests via handleForTesting hook"
```

---

### Task 8: EventRowViewTests(轻)

**Files**:
- Create: `Tests/CairnUITests/EventRowViewTests.swift`

VM logic 已 T7 覆盖;UI view 用"渲染不崩"最低限度 smoke:

```swift
import XCTest
import SwiftUI
import CairnCore
@testable import CairnUI

final class EventRowViewTests: XCTestCase {
    func test_doesNotCrashForAllEventTypes() {
        for type in EventType.allCases {
            let e = Event(sessionId: UUID(), type: type,
                          timestamp: Date(), lineNumber: 1, summary: "smoke")
            let view = EventRowView(event: e)
            // 仅构造不渲染,确保类型映射完整
            _ = view.body
        }
    }
}
```

- [ ] **Step 1: 实现 + 跑**
- [ ] **Step 2: commit**

---

### Task 9: scaffoldVersion bump

`0.8.0-m2.3` → `0.9.0-m2.4`。3 处断言。

---

### Task 10: 最终验证

- [ ] `swift package clean && swift build`
- [ ] `swift test` 期望 169 + M2.4 新 (~7) = ~176
- [ ] `./scripts/make-app-bundle.sh debug` 重打
- [ ] `open build/Cairn.app`
- [ ] 右侧 Inspector 打开(⌘I),看 Event Timeline 空态
- [ ] 另开终端:`cd /tmp && claude` 跟它聊几句
- [ ] **期望**:Inspector 里 events 实时追加,icon + summary 一行一条,时间戳右对齐,自动滚到底

---

### Task 11: Push + 验收清单交用户

---

### Task 12: 用户验收

**Acceptance script**(你做):

```bash
open build/Cairn.app
# ⌘I 打开 Inspector(若默认关)
# 另开终端:
cd /tmp && claude
# 问它几句,带 tool 调用:"列下 /tmp 的文件"、"读一下 /etc/hosts"
# 回到 Cairn,看 Inspector Event Timeline 面板
```

**验收 5 项**:

| # | 检查 | 期望 |
|---|---|---|
| 1 | Inspector 面板 Timeline 能展开显示 | 不崩,有空态文案或 events |
| 2 | 跑 Claude 后 events 追加 | 能看到 user_message / assistant_text / tool_use 等不同 icon + summary |
| 3 | 实时性(~1 秒内刷新) | 事件出现不超过 watcher latency 0.5s + ingestor 处理 |
| 4 | 自动滚到底 | 最新 event 始终可见 |
| 5 | 不崩 / 不卡顿 | 连续几十轮对话 UI 不冻结 |

---

## Known limitations(留给后续 milestone)

- **无工具卡片合并 / 折叠**:连续 `Read × 3` 不合并(M2.5)
- **无 Tab↔Session 绑定**:Timeline 显示第一个活跃 session;切 tab 不切 session 内容(M2.6)
- **无用户手动切 session**:M2.6 做 tab sidebar
- **无快捷键**(⌘⇧E 展开/折叠):M2.5
- **auto-scroll 不检测用户意图**:用户上滚想看历史会被打断(M2.5 优化)
- **连续同类合并**:spec §6.4 "Read × 3" 留 M2.5
- **error 事件无特殊高亮**:M2.5 视觉区分
- **api_usage 每条一行**:M2.5 考虑默认折叠到 Budget 面板
- **本地化**:字符串中文 / 英文未区分,v1 规范留 M4.1

---

## 完成定义

T1-T11 全打勾 + T12 用户 ✅ + tag `m2-4-done` + milestone-log M2.4 条目。
