# M1.5 实施计划:水平分屏 + OSC 7 cwd 跟踪 + 布局 SQLite 持久化

> **For agentic workers:** 本 plan 给 Claude 主导执行。T12 用户肉眼验收。

**Goal:** Phase 1 收尾 milestone,给 Cairn 加 3 个功能:(a) 水平 2 分屏 + 分屏内多 tab;(b) shell OSC 7 escape 上报时自动更新 Tab.cwd + title;(c) 窗口布局(分屏 / tabs / cwd)持久化到 SQLite,关闭 App 重开恢复。**不**持久化滚动缓冲(spec §5.6 决定)。

**Architecture:** 引入 `TabGroup`(包 N 个 TabSession + active id)+ `SplitCoordinator`(1-2 个 TabGroup + activeGroupIndex)。MainWindowView 用 `HSplitView` 渲染 1 或 2 个 TabGroupView,每个 TabGroupView 含 TabBarView + ZStack(已有模式)。OSC 7 在 `ProcessTerminationObserver.hostCurrentDirectoryUpdate` 解析 → 更新 session。布局持久化用 M1.2 的 `LayoutStateDAO`,存 JSON;`LayoutStateSerializer` 专管 codec,debounced 写入,onAppear 读 restore(优先级高于默认 openTab)。

**Tech Stack:** SwiftUI `HSplitView`(macOS 10.15+)· CairnStorage.LayoutStateDAO(M1.2 就绪)· CairnCore.jsonEncoder(M1.1 就绪,ISO-8601)· SwiftTerm `hostCurrentDirectoryUpdate` delegate(M1.4 已留 stub)。

**Claude 耗时**:约 120-180 分钟。
**用户耗时**:约 10 分钟(T12 含 7 项肉眼验收)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. `TabGroup` 抽象 + `SplitCoordinator`(重构 TabsCoordinator) | Claude | — |
| T2. OSC 7 解析器 + TabSession.cwd/title 更新钩子 | Claude | — |
| T3. `LayoutSerializer` Codable 结构 + save/load helpers | Claude | T1 |
| T4. CairnUI 渲染 HSplitView + 2 个 TabGroupView;`TabBarView` 改接 TabGroup | Claude | T1 |
| T5. `CairnApp` Scene state 改为 SplitCoordinator;`⌘⇧D` 分屏;onAppear 恢复布局;变化 debounce 持久化 | Claude | T3, T4 |
| T6. 在 `ProcessTerminationObserver.hostCurrentDirectoryUpdate` 接 OSC 7 处理 | Claude | T2 |
| T7. `SplitCoordinator` / `LayoutSerializer` / OSC 7 parser 单测(≥ 8)| Claude | T1, T2, T3 |
| T8. scaffoldVersion bump `0.4.0-m1.4` → `0.5.0-m1.5` | Claude | — |
| T9. build + test + 肉眼自检 | Claude | T1-T8 |
| T10. milestone-log + tag `m1-5-done` + push | Claude | T9 |
| T11. 验收清单(用户 7 项肉眼) | **用户** | T10 |

---

## 文件结构规划

**新建**:

```
Sources/CairnTerminal/
├── TabSession.swift              (修改:加 updateCwd 方法 + processObserver 调用链)
├── TabsCoordinator.swift         (删:T1 拆为 TabGroup + SplitCoordinator)
├── TabGroup.swift                (T1 新:单组 tabs 管理)
├── SplitCoordinator.swift        (T1 新:1-2 组 + activeGroupIndex)
├── OSC7Parser.swift              (T2 新:file:// URL + percent decode)
└── LayoutSerializer.swift        (T3 新:Codable struct + load/save)

Sources/CairnUI/
├── MainWindowView.swift          (T4 修改:HSplitView + TabGroupView)
├── TabGroupView.swift            (T4 新:单组视图,含 TabBar + ZStack terminal)
└── TabBar/TabBarView.swift       (T4 修改:接 TabGroup 而非 TabsCoordinator)

Sources/CairnApp/CairnApp.swift   (T5 大改:SplitCoordinator + 恢复 / 持久化 / ⌘⇧D)

Tests/CairnTerminalTests/
├── TabsCoordinatorTests.swift    (删:类型不存在)
├── TabGroupTests.swift           (T7 新)
├── SplitCoordinatorTests.swift   (T7 新)
├── OSC7ParserTests.swift         (T7 新)
└── LayoutSerializerTests.swift   (T7 新)
```

**修改**:
- 3 个测试文件的 `scaffoldVersion` 断言
- `docs/milestone-log.md`

---

## 设计决策(pinned)

| # | 决策 | 理由 |
|---|---|---|
| 1 | **`TabGroup` + `SplitCoordinator` 两层** | spec §5.3 明示"最多水平 2 分屏,每侧多 tab";两层匹配 |
| 2 | `HSplitView`(SwiftUI,不是自建 HStack)| 原生拖拽分割条 + macOS 10.15+ 可用,不必自建 |
| 3 | v1 最多 **2 分屏**(spec §5.3 约束) | 超出直接忽略 ⌘⇧D |
| 4 | **关 active tab 若分组空了,自动合并回单组** | UX 符合直觉;避免"空分屏"残留 |
| 5 | OSC 7 解析用 `URL(string: str)` 提取 path,URL 自动 percent-decode | 原生 API 够用,不手写解析 |
| 6 | OSC 7 后 **title 同步更新**(用 cwd 新 basename) | spec §2.6 Tab.title 应反映当前状态 |
| 7 | 布局持久化 Schema 含 **`version: 1`** 字段 | 日后 schema 演进有头部可识别 |
| 8 | 持久化触发时机:**@Observable state 变化 → Task debounce 500ms → write** | 避免 ⌘T/⌘W 快速操作时频繁写 DB |
| 9 | **不持久化滚动缓冲**(spec §5.6 明示)| 重启只恢复 tabs(id/cwd/shell/title),PTY 全新启动 |
| 10 | Workspace scoping:暂用 `defaultWorkspaceId`(与 M1.4 一致) | M3.5 真实 workspace 管理落地后再替换 |
| 11 | onAppear 恢复顺序:**先 restore,再判空才 openTab 默认** | 否则恢复的 tabs 会与默认 tab 共存 |

---

## T1:`TabGroup` + `SplitCoordinator`(替换 `TabsCoordinator`)

**Files:**
- Delete: `Sources/CairnTerminal/TabsCoordinator.swift`
- Create: `Sources/CairnTerminal/TabGroup.swift`
- Create: `Sources/CairnTerminal/SplitCoordinator.swift`

- [ ] **Step 1:删除旧 TabsCoordinator**

```bash
rm /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnTerminal/TabsCoordinator.swift
rm /Users/sorain/xiaomi_projects/AICoding/cairn/Tests/CairnTerminalTests/TabsCoordinatorTests.swift
```

- [ ] **Step 2:写 `TabGroup`**

`Sources/CairnTerminal/TabGroup.swift`:

```swift
import Foundation
import Observation
import CairnCore

/// 一组 tabs 的容器(水平分屏里一列就是一个 TabGroup)。
/// @Observable @MainActor class,SplitCoordinator 持有 1-2 个。
@Observable
@MainActor
public final class TabGroup: Identifiable {
    public let id: UUID
    public private(set) var tabs: [TabSession] = []
    public var activeTabId: UUID?

    public init(id: UUID = UUID()) {
        self.id = id
    }

    /// 便利读:当前 active tab(可能 nil,如关完最后 tab 时)。
    public var activeTab: TabSession? {
        guard let id = activeTabId else { return nil }
        return tabs.first(where: { $0.id == id })
    }

    // MARK: - tabs 管理

    @discardableResult
    public func openTab(
        workspaceId: UUID,
        shell: String? = nil,
        cwd: String? = nil,
        onProcessTerminated: @escaping @MainActor (UUID) -> Void
    ) -> TabSession {
        let effectiveCwd = cwd ?? activeTab?.cwd
        var created: TabSession!
        created = TabSessionFactory.create(
            workspaceId: workspaceId,
            shell: shell,
            cwd: effectiveCwd,
            onProcessTerminated: { [weak self] _ in
                guard self != nil else { return }
                onProcessTerminated(created.id)
            }
        )
        tabs.append(created)
        activeTabId = created.id
        return created
    }

    /// 给 restore 用:不启 PTY,直接插入已构造的 session。
    /// 恢复场景由 LayoutSerializer 调用,那里自己构造 session(用 Factory)。
    public func appendRestoredTab(_ session: TabSession) {
        tabs.append(session)
        if activeTabId == nil {
            activeTabId = session.id
        }
    }

    public func activateTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    public func activateNextTab() {
        guard !tabs.isEmpty else { return }
        guard let current = activeTabId,
              let idx = tabs.firstIndex(where: { $0.id == current }) else {
            activeTabId = tabs.first?.id
            return
        }
        let next = (idx + 1) % tabs.count
        activeTabId = tabs[next].id
    }

    public func activatePreviousTab() {
        guard !tabs.isEmpty else { return }
        guard let current = activeTabId,
              let idx = tabs.firstIndex(where: { $0.id == current }) else {
            activeTabId = tabs.last?.id
            return
        }
        let prev = (idx - 1 + tabs.count) % tabs.count
        activeTabId = tabs[prev].id
    }

    /// 关 tab。返回 "组是否变空"(供 SplitCoordinator 决定是否合并分屏)。
    @discardableResult
    public func closeTab(id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return tabs.isEmpty
        }
        tabs[index].terminate()
        tabs.remove(at: index)

        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                let newIndex = max(0, index - 1)
                activeTabId = tabs[newIndex].id
            }
        }
        return tabs.isEmpty
    }

    /// 进程自然退出(不走 terminate,shell 已死)
    @discardableResult
    public func removeTabWithoutTerminate(id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return tabs.isEmpty
        }
        tabs[index].state = .closed
        tabs.remove(at: index)

        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                let newIndex = max(0, index - 1)
                activeTabId = tabs[newIndex].id
            }
        }
        return tabs.isEmpty
    }

    // MARK: - Test helper

    internal func _insertForTesting(_ session: TabSession) {
        tabs.append(session)
        activeTabId = session.id
    }
}
```

- [ ] **Step 3:写 `SplitCoordinator`**

`Sources/CairnTerminal/SplitCoordinator.swift`:

```swift
import Foundation
import Observation
import CairnCore

/// 水平分屏(最多 2 分屏)管理器。每分屏 = 一个 TabGroup。
/// spec §5.3:最多水平 2 分屏,每侧多 tab;不垂直分屏。
@Observable
@MainActor
public final class SplitCoordinator {
    public private(set) var groups: [TabGroup] = []
    public var activeGroupIndex: Int = 0

    public init() {
        // 默认 1 个空组
        groups = [TabGroup()]
    }

    /// 便利读:当前 active group。
    public var activeGroup: TabGroup {
        groups[activeGroupIndex]
    }

    // MARK: - 分屏管理

    /// ⌘⇧D 触发。若当前已 2 分屏,无效。否则在右侧新建一个分屏,
    /// 并在新分屏里开一个新 tab(继承当前 active tab 的 cwd)。
    public func splitHorizontal(
        workspaceId: UUID,
        onProcessTerminated: @escaping @MainActor (UUID) -> Void
    ) {
        guard groups.count < 2 else { return }
        let newGroup = TabGroup()
        // 新分屏自动开一个 tab,cwd 继承当前 active
        newGroup.openTab(
            workspaceId: workspaceId,
            cwd: activeGroup.activeTab?.cwd,
            onProcessTerminated: onProcessTerminated
        )
        groups.append(newGroup)
        activeGroupIndex = groups.count - 1
    }

    /// 组 `id` 关完最后 tab 时,collapse 到 1 组(保留非空的那一组)。
    public func collapseEmptyGroups() {
        guard groups.count > 1 else { return }
        let nonEmpty = groups.filter { !$0.tabs.isEmpty }
        if nonEmpty.count < groups.count {
            groups = nonEmpty.isEmpty ? [TabGroup()] : nonEmpty
            activeGroupIndex = min(activeGroupIndex, groups.count - 1)
        }
    }

    /// 关 active tab;若分组因此变空,自动 collapse。
    public func closeActiveTab() {
        guard let activeId = activeGroup.activeTabId else { return }
        let wasEmpty = activeGroup.closeTab(id: activeId)
        if wasEmpty {
            collapseEmptyGroups()
        }
    }

    /// shell 进程自然退出回调:找到对应 tab 并移除;若组空了 collapse。
    public func handleTabTerminated(tabId: UUID) {
        for group in groups {
            if group.tabs.contains(where: { $0.id == tabId }) {
                let wasEmpty = group.removeTabWithoutTerminate(id: tabId)
                if wasEmpty {
                    collapseEmptyGroups()
                }
                return
            }
        }
    }

    // MARK: - Replace groups(restore 用 + 测试用)

    /// 用给定 groups 替换当前状态。LayoutSerializer.restore 和测试都用。
    /// activeGroupIndex 自动 clamp 到 0..<groups.count(空数组时复位到 0 并
    /// 塞一个空组,保证不变式"至少 1 组")。
    public func replaceGroups(_ newGroups: [TabGroup], activeIndex: Int = 0) {
        groups = newGroups.isEmpty ? [TabGroup()] : newGroups
        activeGroupIndex = max(0, min(activeIndex, groups.count - 1))
    }
}
```

- [ ] **Step 4:build 验证**

```bash
swift build 2>&1 | tail -10
```

会报 `MainWindowView` / `CairnApp` / `TabBarView` 里找不到 `TabsCoordinator` —— T4/T5 修复。**本 step 不 commit**。

---

## T2:OSC 7 解析器 + TabSession.updateCwd 钩子

**Files:**
- Create: `Sources/CairnTerminal/OSC7Parser.swift`
- Modify: `Sources/CairnTerminal/TabSession.swift`(加 `updateCwd(_:)` 方法)

- [ ] **Step 1:写 OSC7Parser**

`Sources/CairnTerminal/OSC7Parser.swift`:

```swift
import Foundation

/// 解析 shell 通过 OSC 7 escape sequence 上报的 cwd。
/// 规范:`\033]7;file://hostname/path\007`
/// SwiftTerm 把 `file://hostname/path` 这段传给我们的 delegate。
/// 我们用 URL 解析取 path 部分(自动 percent-decode)。
public enum OSC7Parser {
    /// 解析 OSC 7 字符串,返回 path;失败返回 nil。
    /// 接受:
    /// - `file://hostname/Users/sorain` → `/Users/sorain`
    /// - `file:///Users/sorain` → `/Users/sorain`(本机 hostname 可空)
    /// - `/Users/sorain`(裸路径,兜底)→ 原样
    public static func parse(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 裸路径直接返回
        if trimmed.hasPrefix("/") {
            return trimmed
        }

        // file:// scheme 用 URL 解析
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "file" else {
            return nil
        }
        let path = url.path
        return path.isEmpty ? nil : path
    }
}
```

- [ ] **Step 2:TabSession 升级为 `@Observable` + 加 `updateCwd`**

修改 `Sources/CairnTerminal/TabSession.swift`:

a) **class 声明加 `@Observable` 宏**(M1.4 无此宏,因 title/state 从不变,TabBarView 无需 reactive 渲染 — M1.5 OSC 7 开始动态改 title,必须 @Observable 让 SwiftUI 追踪):

```swift
@Observable
@MainActor
public final class TabSession: Identifiable, Equatable {
    // 字段不变
}
```

b) 在 class 里加 `updateCwd` 方法:

```swift
/// OSC 7 上报新 cwd 时调用。同时更新 title(basename 反映当前目录)。
public func updateCwd(_ newCwd: String) {
    guard newCwd != cwd else { return }
    cwd = newCwd
    let basename = (newCwd as NSString).lastPathComponent
    let shellName = (shell as NSString).lastPathComponent
    title = "\(basename.isEmpty ? "~" : basename) (\(shellName))"
}
```

**@Observable 的微妙要点**:
- `Identifiable` + `Equatable` 协议 conformance 与 `@Observable` 兼容(@Observable 只是添加 observation tracking 的 overlay,不影响协议实现)
- 已手写的 `static func ==` 保留不变
- `terminalView: LocalProcessTerminalView` 是 NSView 引用,不该被 SwiftUI 追踪变化 —— 这是 @Observable 在引用类型属性上的天然行为(只追踪**赋值**,不追踪引用对象内部变化),符合预期

- [ ] **Step 3:build 验证 + 不 commit(连锁到 T6)**

```bash
swift build 2>&1 | tail -5
```

---

## T3:`LayoutSerializer` Codable + load/save

**Files:**
- Create: `Sources/CairnTerminal/LayoutSerializer.swift`

- [ ] **Step 1:写 LayoutSerializer**

`Sources/CairnTerminal/LayoutSerializer.swift`:

```swift
import Foundation
import CairnCore
import CairnStorage

/// 可序列化的窗口布局快照。
/// 版本化(schema_version),日后 schema 演进有头部。
public struct PersistedLayout: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let activeGroupIndex: Int
    public let groups: [PersistedGroup]

    public struct PersistedGroup: Codable, Equatable, Sendable {
        public let tabs: [PersistedTab]
        public let activeTabId: UUID?
    }

    public struct PersistedTab: Codable, Equatable, Sendable {
        public let id: UUID
        public let workspaceId: UUID
        public let title: String
        public let cwd: String
        public let shell: String
    }
}

/// 把 SplitCoordinator 的 live 状态变成 PersistedLayout,或反过来。
@MainActor
public enum LayoutSerializer {
    public static let currentSchemaVersion = 1

    /// live → persisted
    public static func snapshot(from coordinator: SplitCoordinator) -> PersistedLayout {
        let groups = coordinator.groups.map { group in
            PersistedLayout.PersistedGroup(
                tabs: group.tabs.map { tab in
                    PersistedLayout.PersistedTab(
                        id: tab.id,
                        workspaceId: tab.workspaceId,
                        title: tab.title,
                        cwd: tab.cwd,
                        shell: tab.shell
                    )
                },
                activeTabId: group.activeTabId
            )
        }
        return PersistedLayout(
            schemaVersion: currentSchemaVersion,
            activeGroupIndex: coordinator.activeGroupIndex,
            groups: groups
        )
    }

    /// persisted → live(PTY 全新启动)
    /// 调用方通过 onProcessTerminated 回调把每个 tab 的 exit 连回 SplitCoordinator。
    public static func restore(
        _ layout: PersistedLayout,
        into coordinator: SplitCoordinator,
        onProcessTerminated: @escaping @MainActor (UUID) -> Void
    ) {
        guard layout.schemaVersion == currentSchemaVersion else {
            // 未来 schema 演进时加 migration;v1.5 严格匹配
            return
        }
        let restoredGroups: [TabGroup] = layout.groups.map { g in
            let group = TabGroup()
            for persisted in g.tabs {
                // forward-ref 模式:session 的新 id 在 factory 返回后才知道,
                // 但 callback 必须在 factory 调用前就构造好。用 var 捕获,
                // callback 里读 created.id(assigned 后可用)。
                // 这样 onProcessTerminated 发的是**新** id,与 SplitCoordinator
                // 里 group.tabs 持有的 session id 一致,handleTabTerminated
                // 能查到。
                var created: TabSession!
                created = TabSessionFactory.create(
                    workspaceId: persisted.workspaceId,
                    shell: persisted.shell,
                    cwd: persisted.cwd,
                    onProcessTerminated: { _ in
                        onProcessTerminated(created.id)
                    }
                )
                group.appendRestoredTab(created)
            }
            // activeTabId 恢复:按"persisted tabs 里匹配 activeTabId 的**位置**"
            if let oldActive = g.activeTabId,
               let pos = g.tabs.firstIndex(where: { $0.id == oldActive }),
               pos < group.tabs.count {
                group.activateTab(id: group.tabs[pos].id)
            }
            return group
        }
        coordinator.replaceGroups(restoredGroups, activeIndex: layout.activeGroupIndex)
    }

    /// 序列化为 JSON String(用 CairnCore.jsonEncoder,ISO-8601 日期)
    public static func encode(_ layout: PersistedLayout) throws -> String {
        let data = try CairnCore.jsonEncoder.encode(layout)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func decode(_ json: String) throws -> PersistedLayout {
        let data = Data(json.utf8)
        return try CairnCore.jsonDecoder.decode(PersistedLayout.self, from: data)
    }

    /// 便利:直接读 LayoutStateDAO。
    public static func load(
        workspaceId: UUID,
        from db: CairnDatabase
    ) async throws -> PersistedLayout? {
        guard let result = try await LayoutStateDAO.fetch(workspaceId: workspaceId, in: db) else {
            return nil
        }
        return try decode(result.layoutJson)
    }

    /// 便利:持久化到 LayoutStateDAO。
    public static func save(
        _ layout: PersistedLayout,
        workspaceId: UUID,
        to db: CairnDatabase
    ) async throws {
        let json = try encode(layout)
        try await LayoutStateDAO.upsert(
            workspaceId: workspaceId,
            layoutJson: json,
            updatedAt: Date(),
            in: db
        )
    }
}
```

**注**:`TabSession.id` 是 `let`,restore 时新 session 拿新 UUID,不能保持原 id。activeTabId 按**位置**匹配(见代码注释)—— 这是 v1 妥协,精确恢复 "哪个 tab active" 留 v2。

- [ ] **Step 2:build 验证 + 不 commit**

```bash
swift build 2>&1 | tail -5
```

---

## T4:`TabGroupView` + `MainWindowView` HSplitView

**Files:**
- Create: `Sources/CairnUI/TabGroupView.swift`
- Modify: `Sources/CairnUI/MainWindowView.swift`
- Modify: `Sources/CairnUI/TabBar/TabBarView.swift`(接 TabGroup 而非 TabsCoordinator)

- [ ] **Step 1:修改 TabBarView 接 TabGroup**

把所有 `TabsCoordinator` 引用换成 `TabGroup`。闭包里的 `coordinator.activateTab` / `closeTab` 走同样 API(TabGroup 有相同方法签名)。

用 Edit 工具修改 `Sources/CairnUI/TabBar/TabBarView.swift`,把 `coordinator: TabsCoordinator` 改为 `group: TabGroup`,函数体内 `coordinator.tabs` / `coordinator.activeTabId` / `coordinator.closeTab` / `coordinator.activateTab` 全部替换为 `group.xxx`。

完整目标代码:

```swift
import SwiftUI
import CairnTerminal

public struct TabBarView: View {
    @Bindable var group: TabGroup

    public init(group: TabGroup) {
        self.group = group
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(group.tabs) { tab in
                    tabPill(for: tab)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func tabPill(for tab: TabSession) -> some View {
        let isActive = tab.id == group.activeTabId
        return HStack(spacing: 6) {
            Rectangle()
                .fill(Color.secondary)
                .frame(width: 3, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            Text(tab.title)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            Button {
                withAnimation {
                    _ = group.closeTab(id: tab.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        isActive ? Color.secondary.opacity(0.15) : .clear,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .help("Close tab (⌘W)")
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(
            isActive
                ? AnyShapeStyle(.regularMaterial)
                : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            group.activateTab(id: tab.id)
        }
    }
}
```

- [ ] **Step 2:写 TabGroupView(单分屏视图)**

`Sources/CairnUI/TabGroupView.swift`:

```swift
import SwiftUI
import CairnTerminal

/// 一个分屏 = TabBar + ZStack(所有 tab 的 TerminalSurface)。
/// 空态时显示提示。
public struct TabGroupView: View {
    @Bindable var group: TabGroup
    let isActiveGroup: Bool
    let onTapActivate: () -> Void

    public init(
        group: TabGroup,
        isActiveGroup: Bool,
        onTapActivate: @escaping () -> Void
    ) {
        self.group = group
        self.isActiveGroup = isActiveGroup
        self.onTapActivate = onTapActivate
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabBarView(group: group)

            Divider()

            ZStack {
                if group.tabs.isEmpty {
                    emptyState
                } else {
                    ForEach(group.tabs) { tab in
                        TerminalSurface(session: tab)
                            .opacity(tab.id == group.activeTabId ? 1 : 0)
                            .allowsHitTesting(tab.id == group.activeTabId)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(
            Rectangle()
                .stroke(isActiveGroup ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        )
        .onTapGesture {
            onTapActivate()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No active tab")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Press ⌘T to open a new terminal.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3:修改 MainWindowView 用 HSplitView + SplitCoordinator**

```swift
import SwiftUI
import CairnTerminal

public struct MainWindowView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showInspector: Bool
    @Bindable var split: SplitCoordinator

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        showInspector: Binding<Bool>,
        split: SplitCoordinator
    ) {
        _columnVisibility = columnVisibility
        _showInspector = showInspector
        self.split = split
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
        } detail: {
            mainArea
        }
        .inspector(isPresented: $showInspector) {
            RightPanelView()
                .inspectorColumnWidth(min: 280, ideal: 360, max: 500)
        }
        .toolbar {
            CairnToolbarContent(showInspector: $showInspector)
        }
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            splitContent
            Divider()
            StatusBarView()
        }
    }

    @ViewBuilder
    private var splitContent: some View {
        if split.groups.count >= 2 {
            HSplitView {
                TabGroupView(
                    group: split.groups[0],
                    isActiveGroup: split.activeGroupIndex == 0,
                    onTapActivate: { split.activeGroupIndex = 0 }
                )
                TabGroupView(
                    group: split.groups[1],
                    isActiveGroup: split.activeGroupIndex == 1,
                    onTapActivate: { split.activeGroupIndex = 1 }
                )
            }
        } else {
            TabGroupView(
                group: split.groups[0],
                isActiveGroup: true,
                onTapActivate: {}
            )
        }
    }
}

#if DEBUG
#Preview("Main window") {
    MainWindowView(
        columnVisibility: .constant(.all),
        showInspector: .constant(true),
        split: SplitCoordinator()
    )
    .frame(width: 1280, height: 800)
}
#endif
```

- [ ] **Step 4:build 验证 + 不 commit(连锁到 T5)**

---

## T5:`CairnApp` 改 SplitCoordinator + ⌘⇧D + 恢复/持久化

**Files:**
- Modify: `Sources/CairnApp/CairnApp.swift`

- [ ] **Step 1:重写 CairnApp**

```swift
import SwiftUI
import CairnUI
import CairnTerminal
import CairnStorage

@main
struct CairnApp: App {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector: Bool = true
    @State private var split = SplitCoordinator()

    /// M1.5 持久化:每次 @Observable 变化后 debounce 500ms 再写 DB
    @State private var saveTask: Task<Void, Never>?

    /// v1 defaultWorkspaceId(M3.5 后替换为真实)
    private let defaultWorkspaceId = UUID()

    /// 持久化用的 DB(onAppear 时初始化)
    @State private var database: CairnDatabase?

    var body: some Scene {
        WindowGroup("Cairn", content: {
            MainWindowView(
                columnVisibility: $columnVisibility,
                showInspector: $showInspector,
                split: split
            )
            .task {
                // 1. 打开 DB(v1 生产路径,测试时也 OK)
                do {
                    let db = try await CairnDatabase(
                        location: .productionSupportDirectory,
                        migrator: CairnStorage.makeMigrator()
                    )
                    self.database = db
                    // 2. 尝试 restore
                    if let layout = try await LayoutSerializer.load(
                        workspaceId: defaultWorkspaceId, from: db
                    ) {
                        LayoutSerializer.restore(
                            layout,
                            into: split,
                            onProcessTerminated: { [weak split] tabId in
                                split?.handleTabTerminated(tabId: tabId)
                            }
                        )
                    }
                    // 3. 若 restore 后仍无 tab(首次启动),开一个默认
                    if split.activeGroup.tabs.isEmpty {
                        split.activeGroup.openTab(
                            workspaceId: defaultWorkspaceId,
                            onProcessTerminated: { [weak split] tabId in
                                split?.handleTabTerminated(tabId: tabId)
                            }
                        )
                    }
                    // 4. 启动自动保存监听
                    scheduleAutoSave()
                } catch {
                    // DB 打不开也要能用(开空 tab,持久化功能跳过)
                    print("[CairnApp] DB init failed: \(error)")
                    if split.activeGroup.tabs.isEmpty {
                        split.activeGroup.openTab(
                            workspaceId: defaultWorkspaceId,
                            onProcessTerminated: { [weak split] tabId in
                                split?.handleTabTerminated(tabId: tabId)
                            }
                        )
                    }
                }
            }
            // Observable 变化触发保存 debounce
            .onChange(of: split.groups.map { $0.tabs.count }) { _, _ in scheduleAutoSave() }
            .onChange(of: split.groups.map { $0.activeTabId }) { _, _ in scheduleAutoSave() }
            .onChange(of: split.activeGroupIndex) { _, _ in scheduleAutoSave() }
        })
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    withAnimation {
                        columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Toggle Inspector") {
                    withAnimation {
                        showInspector.toggle()
                    }
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    withAnimation {
                        _ = split.activeGroup.openTab(
                            workspaceId: defaultWorkspaceId,
                            onProcessTerminated: { [weak split] tabId in
                                split?.handleTabTerminated(tabId: tabId)
                            }
                        )
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    withAnimation {
                        split.closeActiveTab()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Next Tab") {
                    split.activeGroup.activateNextTab()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Previous Tab") {
                    split.activeGroup.activatePreviousTab()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                // ⌘⇧D:水平分屏(spec §6.7)
                Button("Split Horizontal") {
                    withAnimation {
                        split.splitHorizontal(
                            workspaceId: defaultWorkspaceId,
                            onProcessTerminated: { [weak split] tabId in
                                split?.handleTabTerminated(tabId: tabId)
                            }
                        )
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - Persistence

    /// Debounce 500ms 保存布局。反复调用会覆盖前一个 task。
    @MainActor
    private func scheduleAutoSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [split, database, defaultWorkspaceId] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let db = database else { return }
            let layout = LayoutSerializer.snapshot(from: split)
            try? await LayoutSerializer.save(
                layout,
                workspaceId: defaultWorkspaceId,
                to: db
            )
        }
    }
}
```

- [ ] **Step 2:合并 commit T1-T5**

```bash
swift build 2>&1 | tail -5
```

**Expected**: `Build complete!`。

```bash
git add Sources/CairnTerminal/TabGroup.swift \
        Sources/CairnTerminal/SplitCoordinator.swift \
        Sources/CairnTerminal/OSC7Parser.swift \
        Sources/CairnTerminal/LayoutSerializer.swift \
        Sources/CairnTerminal/TabSession.swift \
        Sources/CairnTerminal/TabsCoordinator.swift \
        Sources/CairnUI/TabBar/TabBarView.swift \
        Sources/CairnUI/TabGroupView.swift \
        Sources/CairnUI/MainWindowView.swift \
        Sources/CairnApp/CairnApp.swift \
        Tests/CairnTerminalTests/TabsCoordinatorTests.swift
git commit -m "feat(terminal): 水平分屏 + OSC 7 cwd 跟踪 + 布局持久化

架构:
- TabGroup(单组 tabs)+ SplitCoordinator(1-2 组 + activeGroupIndex)
  替代 TabsCoordinator。TabGroup.closeTab 返回'组是否空',
  SplitCoordinator.collapseEmptyGroups 自动合并空分屏。
- OSC7Parser:file:// URL + 裸路径两种输入,URL 解析自动 percent-decode
- TabSession.updateCwd:OSC 7 触发时更新 cwd + 同步 title basename
- LayoutSerializer:PersistedLayout(schemaVersion=1)<-> SplitCoordinator
  snapshot/restore;持久化到 CairnStorage.LayoutStateDAO

UI:
- TabGroupView(单分屏视图)= TabBarView + ZStack terminals
- MainWindowView 用 HSplitView 渲染 1 或 2 个 TabGroupView
- TabBarView 从 TabsCoordinator 改为 TabGroup 接口

CairnApp:
- @State split 替代 tabsCoordinator
- .task 里打 DB + restore layout(若有)+ 兜底 openTab 默认
- .onChange of (tabs counts / active ids / activeGroupIndex) → scheduleAutoSave
- scheduleAutoSave:cancel 旧 Task + 新 Task debounce 500ms → 写 DB
- ⌘⇧D 新快捷键触发 splitHorizontal

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T6:OSC 7 delegate 接入

**Files:**
- Modify: `Sources/CairnTerminal/TabSession.swift`(`hostCurrentDirectoryUpdate` 调用 updateCwd)

- [ ] **Step 1:修改 ProcessTerminationObserver**

把 `ProcessTerminationObserver` 从只管 termination 升级为管多个 delegate 事件。需要接收 hostDirectoryUpdate callback:

```swift
@MainActor
public final class ProcessTerminationObserver: NSObject, LocalProcessTerminalViewDelegate {
    public typealias TerminationCallback = @MainActor (_ exitCode: Int32?) -> Void
    public typealias CwdUpdateCallback = @MainActor (_ newDirectory: String) -> Void

    private let onTerminated: TerminationCallback
    private let onCwdUpdate: CwdUpdateCallback

    public init(
        onTerminated: @escaping TerminationCallback,
        onCwdUpdate: @escaping CwdUpdateCallback
    ) {
        self.onTerminated = onTerminated
        self.onCwdUpdate = onCwdUpdate
        super.init()
    }

    public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory,
              let parsed = OSC7Parser.parse(directory) else { return }
        onCwdUpdate(parsed)
    }

    public func processTerminated(source: TerminalView, exitCode: Int32?) {
        onTerminated(exitCode)
    }
}
```

- [ ] **Step 2:`TabSessionFactory.create` 签名加 onCwdUpdate 参数**

```swift
public static func create(
    workspaceId: UUID,
    shell shellPath: String? = nil,
    cwd startCwd: String? = nil,
    onProcessTerminated: @escaping @MainActor (Int32?) -> Void
) -> TabSession {
    // ...前半部分不变...
    let view = LocalProcessTerminalView(frame: .zero)

    // 用 nested box 持有 session 引用,让 observer 能回调 updateCwd
    let sessionHolder = SessionHolder()
    let observer = ProcessTerminationObserver(
        onTerminated: onProcessTerminated,
        onCwdUpdate: { [weak sessionHolder] newCwd in
            sessionHolder?.session?.updateCwd(newCwd)
        }
    )
    view.processDelegate = observer

    view.startProcess(
        executable: shell, args: [],
        environment: nil,
        execName: shellIdiom,
        currentDirectory: cwd
    )

    let session = TabSession(
        workspaceId: workspaceId,
        title: title,
        cwd: cwd,
        shell: shell,
        terminalView: view
    )
    session.processObserver = observer
    sessionHolder.session = session  // 现在 observer 的 callback 能找到 session
    return session
}

/// Observer 创建后 session 还没构造好;用这个 holder 让 observer callback
/// 拿到之后构造出的 session。
@MainActor
private final class SessionHolder {
    weak var session: TabSession?
}
```

- [ ] **Step 3:build 验证 + commit**

```bash
swift build 2>&1 | tail -5
git add Sources/CairnTerminal/TabSession.swift
git commit -m "feat(terminal): OSC 7 cwd 更新通过 ProcessTerminationObserver 接入

ProcessTerminationObserver 升级支持 2 个 callback:termination + cwd update。
TabSessionFactory 用 SessionHolder 解决 'observer 先构造 / session 后构造'
的 forward ref;observer callback 通过 weak holder 找到 session 调 updateCwd。
OSC 7 escape 触发 shell 发 directory → SwiftTerm 解 → observer parse →
session.updateCwd 更新 cwd + title basename。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T7:单测

**Files:**
- Create: `Tests/CairnTerminalTests/TabGroupTests.swift`
- Create: `Tests/CairnTerminalTests/SplitCoordinatorTests.swift`
- Create: `Tests/CairnTerminalTests/OSC7ParserTests.swift`
- Create: `Tests/CairnTerminalTests/LayoutSerializerTests.swift`

- [ ] **Step 1:TabGroupTests(5 测试)**

`Tests/CairnTerminalTests/TabGroupTests.swift`:

```swift
import XCTest
import AppKit
import SwiftTerm
@testable import CairnTerminal

@MainActor
final class TabGroupTests: XCTestCase {
    private func makeFake() -> TabSession {
        TabSession(
            workspaceId: UUID(), title: "t", cwd: "/tmp", shell: "/bin/zsh",
            terminalView: LocalProcessTerminalView(frame: .zero)
        )
    }

    func test_init_hasEmptyTabs() {
        let g = TabGroup()
        XCTAssertTrue(g.tabs.isEmpty)
        XCTAssertNil(g.activeTabId)
    }

    func test_appendRestored_activatesFirst() {
        let g = TabGroup()
        let a = makeFake(); g.appendRestoredTab(a)
        XCTAssertEqual(g.activeTabId, a.id)
        let b = makeFake(); g.appendRestoredTab(b)
        // active 不变(appendRestored 只在 nil 时设置)
        XCTAssertEqual(g.activeTabId, a.id)
    }

    func test_closeTab_returnsTrueWhenEmpty() {
        let g = TabGroup()
        let a = makeFake(); g._insertForTesting(a)
        let wasEmpty = g.closeTab(id: a.id)
        XCTAssertTrue(wasEmpty)
        XCTAssertTrue(g.tabs.isEmpty)
    }

    func test_closeTab_returnsFalseWhenNotEmpty() {
        let g = TabGroup()
        g._insertForTesting(makeFake())
        let b = makeFake(); g._insertForTesting(b)
        let wasEmpty = g.closeTab(id: b.id)
        XCTAssertFalse(wasEmpty)
        XCTAssertEqual(g.tabs.count, 1)
    }

    func test_activateNextTab_cycles() {
        let g = TabGroup()
        let a = makeFake(); g._insertForTesting(a)
        let b = makeFake(); g._insertForTesting(b)
        g.activateNextTab()
        XCTAssertEqual(g.activeTabId, a.id)  // wrap 回前
    }
}
```

- [ ] **Step 2:SplitCoordinatorTests(4 测试)**

```swift
import XCTest
import AppKit
import SwiftTerm
@testable import CairnTerminal

@MainActor
final class SplitCoordinatorTests: XCTestCase {
    private func makeFake() -> TabSession {
        TabSession(
            workspaceId: UUID(), title: "t", cwd: "/tmp", shell: "/bin/zsh",
            terminalView: LocalProcessTerminalView(frame: .zero)
        )
    }

    func test_init_singleGroup() {
        let c = SplitCoordinator()
        XCTAssertEqual(c.groups.count, 1)
        XCTAssertEqual(c.activeGroupIndex, 0)
    }

    func test_collapseEmptyGroups_removesEmptyExceptLast() {
        let c = SplitCoordinator()
        let g1 = TabGroup(); g1._insertForTesting(makeFake())
        let g2 = TabGroup()  // 空
        c.replaceGroups([g1, g2])
        c.collapseEmptyGroups()
        XCTAssertEqual(c.groups.count, 1)
        XCTAssertFalse(c.groups[0].tabs.isEmpty)
    }

    func test_collapseEmptyGroups_allEmpty_keepsOne() {
        let c = SplitCoordinator()
        c.replaceGroups([TabGroup(), TabGroup()])
        c.collapseEmptyGroups()
        // 全空时 collapse 成 1 空组
        XCTAssertEqual(c.groups.count, 1)
    }

    func test_handleTabTerminated_removesFromCorrectGroup() {
        let c = SplitCoordinator()
        let g1 = TabGroup(); let a = makeFake(); g1._insertForTesting(a)
        let g2 = TabGroup(); let b = makeFake(); g2._insertForTesting(b)
        c.replaceGroups([g1, g2])
        c.handleTabTerminated(tabId: a.id)
        // a 不在了,g1 collapse,总 groups 变 1(只剩 g2)
        XCTAssertEqual(c.groups.count, 1)
        XCTAssertTrue(c.groups[0].tabs.contains(where: { $0.id == b.id }))
    }
}
```

- [ ] **Step 3:OSC7ParserTests(5 测试)**

```swift
import XCTest
@testable import CairnTerminal

final class OSC7ParserTests: XCTestCase {
    func test_fileUrlWithHostname() {
        XCTAssertEqual(OSC7Parser.parse("file://imac/Users/sorain"),
                       "/Users/sorain")
    }

    func test_fileUrlEmptyHostname() {
        XCTAssertEqual(OSC7Parser.parse("file:///Users/sorain"),
                       "/Users/sorain")
    }

    func test_barePath_fallback() {
        XCTAssertEqual(OSC7Parser.parse("/Users/sorain"), "/Users/sorain")
    }

    func test_percentEncoded_decoded() {
        // "file:///Users/sor%20ain" → "/Users/sor ain"
        XCTAssertEqual(OSC7Parser.parse("file:///Users/sor%20ain"),
                       "/Users/sor ain")
    }

    func test_invalidScheme_returnsNil() {
        XCTAssertNil(OSC7Parser.parse("http://example.com/"))
        XCTAssertNil(OSC7Parser.parse(""))
    }
}
```

- [ ] **Step 4:LayoutSerializerTests(3 测试)**

```swift
import XCTest
import AppKit
import SwiftTerm
@testable import CairnTerminal

@MainActor
final class LayoutSerializerTests: XCTestCase {
    private func makeFake(title: String = "t", cwd: String = "/tmp") -> TabSession {
        TabSession(
            workspaceId: UUID(), title: title, cwd: cwd, shell: "/bin/zsh",
            terminalView: LocalProcessTerminalView(frame: .zero)
        )
    }

    func test_snapshot_roundTripViaJson() throws {
        let c = SplitCoordinator()
        let g1 = TabGroup()
        g1._insertForTesting(makeFake(title: "a", cwd: "/a"))
        g1._insertForTesting(makeFake(title: "b", cwd: "/b"))
        c.replaceGroups([g1])

        let layout = LayoutSerializer.snapshot(from: c)
        XCTAssertEqual(layout.schemaVersion, 1)
        XCTAssertEqual(layout.groups.count, 1)
        XCTAssertEqual(layout.groups[0].tabs.count, 2)

        let json = try LayoutSerializer.encode(layout)
        let decoded = try LayoutSerializer.decode(json)
        XCTAssertEqual(layout, decoded)
    }

    func test_snapshot_preservesTwoGroups() {
        let c = SplitCoordinator()
        let g1 = TabGroup(); g1._insertForTesting(makeFake(title: "a"))
        let g2 = TabGroup(); g2._insertForTesting(makeFake(title: "b"))
        c.replaceGroups([g1, g2])
        c.activeGroupIndex = 1

        let layout = LayoutSerializer.snapshot(from: c)
        XCTAssertEqual(layout.groups.count, 2)
        XCTAssertEqual(layout.activeGroupIndex, 1)
    }

    func test_encode_containsSchemaVersion1() throws {
        let c = SplitCoordinator()
        let layout = LayoutSerializer.snapshot(from: c)
        let json = try LayoutSerializer.encode(layout)
        XCTAssertTrue(json.contains(#""schemaVersion" : 1"#))
    }
}
```

- [ ] **Step 5:跑测试 + commit**

```bash
swift test 2>&1 | grep "Executed" | tail -3
git add Tests/CairnTerminalTests/
git commit -m "test(terminal): M1.5 共 17 单测(TabGroup/SplitCoordinator/OSC7/Layout)

TabGroupTests 5 个:空态 / appendRestored / closeTab 返回值 /
activateNext rotation。
SplitCoordinatorTests 4 个:init 单组 / collapseEmptyGroups 保留规则 /
handleTabTerminated 定位组并 collapse。
OSC7ParserTests 5 个:file:// 有/无 hostname / 裸路径 / percent decode /
invalid scheme。
LayoutSerializerTests 3 个:snapshot roundtrip via JSON / 保留 2 groups /
schema version 1 marker。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T8:scaffoldVersion bump

**Files:**
- `Sources/CairnCore/CairnCore.swift`:`0.4.0-m1.4` → `0.5.0-m1.5`
- 3 测试文件断言同步

- [ ] **Step 1:bump + commit**

---

## T9:build + test + 自检启动

- [ ] **Step 1:swift build / swift test**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep "Executed" | tail -3
```

**Expected**:`≥ 127 tests, 0 failures`(M1.4 的 110 + M1.5 的 17)。

- [ ] **Step 2:打包 + 启动 + 自检**

Claude 层自检:
- [ ] 启动后开启默认 tab
- [ ] `⌘⇧D` 分屏出现 2 个分屏
- [ ] `⌘T` 在 active 分屏开新 tab
- [ ] `cd /tmp` 后 Tab 标题更新为 `tmp (zsh)`
- [ ] 关 App 再开,tabs 按数量 / cwd 恢复(shell 重新启动)

---

## T10:milestone-log + tag

见前 milestone 格式,提 M1.5 完成。

---

## T11:验收清单(用户肉眼 7 项)

```markdown
## M1.5 验收清单

**验证**:

步骤 1 · 编译
```bash
swift build 2>&1 | tail -3
```

步骤 2 · 测试
```bash
swift test 2>&1 | grep "Executed" | tail -3
```
期望 `≥ 127 tests green`。

步骤 3 · 肉眼验收(7 项)

```bash
./scripts/make-app-bundle.sh debug --open
```

- [ ] [1] 启动后默认开一个 tab(或恢复上次布局)
- [ ] [2] `⌘⇧D` 按下出现右侧第 2 分屏,带自己的 tab bar
- [ ] [3] 点击分屏 active 变化(当前分屏边框有淡色 accent)
- [ ] [4] 任一 tab 里 `cd /tmp` 后几秒内 tab 标题变为 `tmp (zsh)`
- [ ] [5] 用 `⌘W` 关分屏最后一个 tab,分屏自动消失,回单屏
- [ ] [6] 完全退出 App(⌘Q)再重开,tabs 数 / cwd / 分屏结构恢复
  (shell 是全新启动,buffer 空,但 prompt 已 cd 到恢复的 cwd)
- [ ] [7] 现有 M1.4 功能回归:⌘T / ⌘W / ⌘L / ⌘⇧L 仍工作

**Known limitations**:
- 滚动缓冲不持久化(spec §5.6 明示)
- 恢复的 tab 使用新 UUID,activeTabId 按位置匹配(v1 妥协)
- OSC 7 依赖 shell 主动发送 —— 某些最小化配置可能不发
- 分屏宽度的拖拽位置不持久化(v1 接受,M4.x 可加)

**下个 M**:M2.1 JSONLWatcher(Phase 2 开端,迈向 v0.1 Beta)。
```

---

## Self-Review

### 1. Spec 覆盖

| Spec | 要求 | Task |
|---|---|---|
| §5.3 水平分屏 | 最多 2 分屏 | T1 SplitCoordinator max 2 |
| §5.5 OSC 7 | 必做 | T2 Parser + T6 delegate |
| §5.6 重启恢复 | tabs 重启 PTY,cwd 保留 | T3 Serializer + T5 onAppear restore |
| §6.7 快捷键 ⌘⇧D | 分屏 | T5 commands |
| §8.4 M1.5 验收 | 布局恢复 + cd 更新 cwd | T11 项 [4] + [6] |

### 2. Placeholder 扫描

无 TBD/FIXME。

### 3. 类型一致性

- `TabGroup` / `SplitCoordinator` / `PersistedLayout` / `LayoutSerializer` / `OSC7Parser` 命名统一
- `activeTabId: UUID?` / `activeGroupIndex: Int` —— 跨 T1/T3 保持

### 4. 风险

**风险 1(中)**:**HSplitView 在 SwiftUI 里的 behavior**。
`HSplitView` 是旧 SwiftUI API(macOS 10.15+),但近年来有推出 `NavigationSplitView` 取代部分用例。HSplitView 在实现真正的拖拽分屏 + 2 列等宽时可能 quirky。**执行时肉眼验证拖拽分割条是否工作**;若不行,改用自建 HStack + `.resizable` / GeometryReader + 手动 drag gesture。

**风险 2(中)**:**@Observable 的 .onChange + 数组映射 trigger 可靠性**。
`.onChange(of: split.groups.map { $0.tabs.count })` 用派生值监听,可能漏变化(如内部 cwd 改动不触发)。若持久化不完全,手动调 `scheduleAutoSave` 在所有可能改状态的方法里。

**风险 3(已消除)**:~~`LayoutSerializer.restore` callback 捕获旧 `persisted.id` 而非新 session id~~。
初稿 callback 里 `onProcessTerminated(persisted.id)` 会发送**旧** UUID,但 `SplitCoordinator.handleTabTerminated` 查的是 group 里 session 的**新** UUID(TabSession.id 是 let 不可改,Factory 为恢复的 session 分配新 id),shell exit 时查不到 tab、tab 不会自动移除。
修正:用 `var created: TabSession!` forward-ref 模式,callback 里引用 `created.id`(factory 返回后可用的新 id)—— 与 `TabGroup.openTab` 里同样模式一致。

**风险 6(已消除)**:~~TabSession 未 @Observable,OSC 7 改 title 后 UI 不刷新~~。
初稿漏了这点,M1.4 因 title 静态无人察觉;M1.5 T2 Step 2 加上 `@Observable` 宏后,`cwd` / `title` / `state` 的 setter 产生 observation trigger,TabBarView 在 `tab.title` 变化时自动重渲。

**残留风险**:**restore 后 tab 用新 UUID,不保留 persisted.id**。
Swift `let id: UUID` 无法修改;M1.5 的妥协是 activeTabId 按**位置**匹配(见 T3 restore 逻辑)。用户视角:重启后 tab 视觉相似但底层 id 不同。影响极小(id 未暴露给用户)。

**风险 4(低)**:**OSC 7 shell 配置**。
需要 shell 主动发 OSC 7。zsh 默认不发,需配 `chpwd` hook 或装主题(powerlevel10k / starship 自带)。**兜底**:spec §5.5 说 "新 Tab 启动时向环境变量注入 chpwd_hook for zsh/bash(用户可关)" —— 本 milestone **不做这个兜底**(留 v1.5 polish);若用户未配,`cd` 不更新 title,但基本功能不坏。

### 5. 结论

Plan 可执行。2 个中风险需肉眼验证。
