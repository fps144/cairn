# M1.4 实施计划:多 Tab 管理 + TerminalSurface 封装 + PTY 生命周期

> **For agentic workers:** 本 plan 给 Claude 主导执行(见 `CLAUDE.md`)。每个 Task 按 Step 逐步完成。用户职责仅 T12 验收(含**肉眼验收**)。

**Goal:** 在 M1.3 的 Main Area Tab Bar 占位基础上,实装多 Tab 管理:`⌘T` 新建、`⌘W` 关闭、`⌘L` / `⌘⇧L` 前后切换,每 Tab 是一个独立 PTY 进程,`processTerminated` delegate 触发 Tab 自动关闭。

**Architecture:** `CairnTerminal` 层新增 `TabSession`(@MainActor class 包 `LocalProcessTerminalView` 实例 + 状态)+ `TabsCoordinator`(@Observable class,Scene-level 持有,管 tabs 列表 + active tab)。UI 用 `ZStack` 渲染所有 tab 的 TerminalSurface,非 active 的 `.opacity(0) .allowsHitTesting(false)` 保留 PTY 连接不被 SwiftUI 销毁。TerminalSurface 改为从 TabSession 取**既有**的 NSView 实例(而非每次创建),保证 tab 切换时终端内容不丢。

**Tech Stack:** SwiftUI + CairnCore Tab 实体(M1.1 已就绪)+ CairnTerminal(新增 TabSession/TabsCoordinator)+ SwiftTerm.LocalProcessTerminalView 的 `processDelegate` 回调。无新第三方依赖。

**Claude 总耗时:** 约 90-150 分钟。
**用户总耗时:** 约 10-15 分钟(T12 含肉眼验收 7 项)。

---

## Spec §8.3 vs §8.4 调和说明

- §8.3 roadmap(简短列表):`M1.4 单 Tab 终端 + PTY 生命周期`
- §8.4 详细表:`M1.4 多 Tab 管理 + TerminalSurface 封装 + PTY 生命周期`,验收要求 `⌘T / ⌘W / ⌘L 可用`

**以 §8.4 为准**(更详细 + 验收标准本身要求多 tab 快捷键)。§8.3 roadmap 可能是早期草稿。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. `CairnTerminal.TabSession`(@MainActor class 包 LocalProcessTerminalView + 状态) | Claude | — |
| T2. `CairnTerminal.TabsCoordinator`(@Observable,管 tabs 列表 + active)| Claude | T1 |
| T3. `TerminalSurface` 改造:从 TabSession 取既有 NSView,不每次创建 | Claude | T1 |
| T4. `CairnUI.TabBarView`(tab 胶囊 + 关闭按钮 + 左边灰色边框) | Claude | T2 |
| T5. `MainWindowView` 整合 TabBarView + ZStack 渲染所有 tabs | Claude | T3, T4 |
| T6. `CairnApp` 注入 TabsCoordinator(Scene-level @State)+ commands ⌘T/⌘W/⌘L/⌘⇧L | Claude | T2 |
| T7. processTerminated delegate 接入:shell 退出自动 close tab | Claude | T1 |
| T8. TabsCoordinator 单测(5+ 个:open/close/switch/next/prev) | Claude | T2 |
| T9. `CairnCore.scaffoldVersion` bump 到 `0.4.0-m1.4` + 测试同步 | Claude | — |
| T10. 完整 swift build + test + 肉眼自检 | Claude | T1-T9 |
| T11. milestone-log + tag `m1-4-done` + push | Claude | T10 |
| T12. 验收清单(用户,含**7 项肉眼验收**) | **用户** | T11 |

---

## 文件结构规划

**新建**:

```
Sources/CairnTerminal/
├── TerminalSurface.swift              (M0.2 遗留,T3 重构:从 TabSession 取 NSView)
├── TabSession.swift                   (T1 新增:@MainActor class,live terminal 句柄)
├── TabsCoordinator.swift              (T2 新增:@Observable,管 tabs + active)
└── ProcessTerminationObserver.swift   (T7 新增:LocalProcessTerminalViewDelegate 实现)

Sources/CairnUI/
├── MainWindowView.swift               (T5 修改:加 TabBarView + ZStack terminals)
├── TabBar/
│   └── TabBarView.swift               (T4 新增:胶囊 + 关闭 + 左边框)
└── ...                                 (其余不变)

Tests/CairnTerminalTests/               (新 target)
└── TabsCoordinatorTests.swift         (T8 新增:5+ 单测)
```

**修改**:
- `Package.swift`:新增 `CairnTerminalTests` testTarget
- `Sources/CairnApp/CairnApp.swift`:Scene-level TabsCoordinator + 4 个快捷键 commands
- `Sources/CairnCore/CairnCore.swift`:bump `0.3.0-m1.3` → `0.4.0-m1.4`
- 3 个测试文件的 scaffoldVersion 断言同步

---

## 设计决策(pinned,Plan 执行中不重新讨论)

| # | 决策 | 选择 | 理由 |
|---|---|---|---|
| 1 | 多 Tab 的 NSView 保活策略 | **ZStack 渲染所有 tabs,非 active 用 `.opacity(0) + .allowsHitTesting(false)`** | macOS SwiftUI 里最稳定的保活模式:view 始终在 hierarchy,NSView 不被销毁,终端内容 / 进程 / 滚动缓冲全部保留。代价:inactive tabs 也消耗渲染资源(v1 接受,tab 数少)|
| 2 | `LocalProcessTerminalView` 实例由 `TabSession` 持有 | TabSession class 在 init 时 create,整个生命周期不 replace | TerminalSurface.makeNSView 返回 session 持有的 view,不 create;Coordinator 管生命周期 |
| 3 | `TabSession` 是 `@MainActor` class 而非 struct | **class** | LocalProcessTerminalView 是 NSView 引用类型,class wrapper 匹配其生命周期语义;值语义不适合(NSView 不是 Sendable)|
| 4 | `TabsCoordinator` 用 `@Observable` | `@Observable @MainActor final class` | 一致 M1.3 MainWindowViewModel;UI 订阅 tabs 数组和 activeTabId 变化 |
| 5 | Tab 关闭时的 PTY 清理 | 调 `view.process.terminate(asKillSignal: true)` 强杀 | spec §5.2 "强杀:view.process.terminate(kill)" 原文;graceful shutdown 的 SIGTERM 留给 M4.3 退出流程 |
| 6 | processTerminated(shell 自然退出 / crash)的 tab 处置 | **自动从 tabs 列表移除**(不保留 "closed" 态 tab)| spec §2.6 Tab.state `.active` / `.closed` 两态,但 UI 展示 closed tab 意义不大;M4.3 诊断导出时再考虑保留崩溃记录 |
| 7 | ⌘T 新建 tab 的 cwd 继承 | **新 tab cwd = activeTab.cwd**(无 active 时 = `$HOME`) | 用户常见流程:在 project 目录开新 tab 做副任务,继承 cwd 省去再 `cd`;spec §5.5 OSC 7 cwd 跟踪留 M1.5,此处用启动 cwd |
| 8 | Tab 标题生成 | `basename(cwd) + " (" + basename(shell) + ")"`,如 `cairn (zsh)` | spec §2.6 Tab.title 是 String;具体字符串从简(M1.5 OSC 7 后可动态 update)|
| 9 | Tab 左边框颜色 | **v1 全部灰色**(spec §6.3 的 blue/orange/red 留 M2.x) | 蓝色需要 Claude 进程检测(M2.6),橙色等待输入,红色错误 — 都依赖 JSONLWatcher 的 session 生命周期检测;v1.4 只做结构,颜色迭代留后续 |
| 10 | 不加 XCTest UI 自动化 | 单测覆盖 TabsCoordinator 逻辑即可;UI 交互肉眼验收 | 与 M1.3 一致策略;UI 自动化集中到 M4.2 |

---

## 架构硬约束(不得违反)

- `TabSession` / `TabsCoordinator` **只在 CairnTerminal 模块**,不暴露 SwiftTerm 原生类型(TerminalView 除外)给上层 CairnUI —— CairnUI 应只和 `TabSession` 这个抽象打交道
- `TabsCoordinator` **只管 live 状态**(tabs 列表 + activeTabId),**不**持久化;LayoutState SQLite 同步留 M1.5
- `LocalProcessTerminalView.processDelegate` 的回调**必须在 @MainActor**(SwiftTerm delegate 约定 + 我们的 coordinator 是 MainActor)
- 关闭 tab 流程:(1) coordinator.closeTab → (2) session.terminate() → (3) SwiftUI 视图层响应 tabs 变化自动移除

---

## T1:`TabSession` 类

**Files:**
- Create: `Sources/CairnTerminal/TabSession.swift`

- [ ] **Step 1:写 TabSession**

`Sources/CairnTerminal/TabSession.swift`:

```swift
import Foundation
import AppKit
import SwiftTerm
import CairnCore

/// 一个 live 终端 tab 的句柄。包装 SwiftTerm `LocalProcessTerminalView`
/// 实例 + Cairn 领域元数据(Tab 实体 + TabState)。
///
/// 跨 UI 重绘保活:本类是 @MainActor class,强引用 terminalView。
/// TerminalSurface.makeNSView 不再创建新 view,而是取 session.terminalView,
/// 这样 tab 切换时 NSView 不被销毁,PTY 进程和滚动缓冲全部保留。
@MainActor
public final class TabSession: Identifiable, Equatable {
    public let id: UUID
    public var workspaceId: UUID
    public var title: String
    /// 启动 shell 时的 cwd(spec §5.5 OSC 7 动态跟踪留 M1.5)。
    public var cwd: String
    /// 启动 shell 的路径(从 $SHELL 或默认 /bin/zsh)。
    public let shell: String
    /// `TabState.active`(进程运行中)或 `.closed`(进程已退出)。
    public var state: TabState
    /// 底层 SwiftTerm view(NSView 子类)。整个 TabSession 生命周期不变。
    public let terminalView: LocalProcessTerminalView

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        title: String,
        cwd: String,
        shell: String,
        terminalView: LocalProcessTerminalView
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.cwd = cwd
        self.shell = shell
        self.state = .active
        self.terminalView = terminalView
    }

    /// 强制杀 PTY 进程(spec §5.2 "强杀")。调用后 state = .closed。
    /// 用 optional chain(SwiftTerm 的 process 是 IUO,防测试里未 startProcess
    /// 的 session 调 terminate 时 force-unwrap crash)。
    public func terminate() {
        terminalView.process?.terminate(asKillSignal: true)
        state = .closed
    }

    public static func == (lhs: TabSession, rhs: TabSession) -> Bool {
        lhs.id == rhs.id
    }
}

/// Factory:创建 TabSession 时同步启动 PTY 进程。
/// 从 coordinator 调用,一次完成"创建对象 + startProcess"。
@MainActor
public enum TabSessionFactory {
    /// 创建新 TabSession + 启动 shell 进程。
    /// - Parameters:
    ///   - workspaceId: 所属 workspace id
    ///   - shell: 要启的 shell 路径;nil 时用 $SHELL,兜底 /bin/zsh
    ///   - cwd: 启动目录;nil 时用 $HOME
    /// - Returns: TabSession 实例,已 startProcess
    public static func create(
        workspaceId: UUID,
        shell shellPath: String? = nil,
        cwd startCwd: String? = nil
    ) -> TabSession {
        let shell = shellPath
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        let cwd = startCwd
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? "/"
        let shellIdiom = "-" + (shell as NSString).lastPathComponent
        let basename = (cwd as NSString).lastPathComponent
        let shellName = (shell as NSString).lastPathComponent
        let title = "\(basename.isEmpty ? "~" : basename) (\(shellName))"

        let view = LocalProcessTerminalView(frame: .zero)
        view.startProcess(
            executable: shell,
            args: [],
            environment: nil,
            execName: shellIdiom,
            currentDirectory: cwd
        )

        return TabSession(
            workspaceId: workspaceId,
            title: title,
            cwd: cwd,
            shell: shell,
            terminalView: view
        )
    }
}
```

- [ ] **Step 2:swift build 验证**

```bash
swift build 2>&1 | tail -3
```

**Expected**:`Build complete!`(单独的 TabSession class 不影响其他 target)。

- [ ] **Step 3:Commit**

```bash
git add Sources/CairnTerminal/TabSession.swift
git commit -m "feat(terminal): TabSession live 句柄 + Factory

@MainActor class 包 LocalProcessTerminalView 引用,
+ Cairn 领域元数据(id / workspaceId / title / cwd / shell / state)。
Factory 一次完成 NSView 创建 + startProcess 启动。
title 格式 'basename(cwd) (basename(shell))',如 'cairn (zsh)'。
M1.5 OSC 7 之后 title 可动态跟随 cwd 变化。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T2:`TabsCoordinator`

**Files:**
- Create: `Sources/CairnTerminal/TabsCoordinator.swift`

- [ ] **Step 1:写 TabsCoordinator**

```swift
import Foundation
import Observation
import CairnCore

/// 多 tab 管理器。@MainActor @Observable,UI 订阅 tabs / activeTabId 变化。
/// Scene-level 注入(见 CairnApp.swift)。
@Observable
@MainActor
public final class TabsCoordinator {
    public private(set) var tabs: [TabSession] = []
    public var activeTabId: UUID?

    public init() {}

    /// 新建 tab 并设为 active。
    /// - Parameters:
    ///   - workspaceId: 所属 workspace;v1 无 workspace 时用占位 UUID
    ///   - shell / cwd:可选;nil 则继承 active tab 的 cwd,最终兜底 $HOME / $SHELL
    @discardableResult
    public func openTab(
        workspaceId: UUID,
        shell: String? = nil,
        cwd: String? = nil
    ) -> TabSession {
        let effectiveCwd = cwd ?? activeTab?.cwd
        let session = TabSessionFactory.create(
            workspaceId: workspaceId,
            shell: shell,
            cwd: effectiveCwd
        )
        tabs.append(session)
        activeTabId = session.id
        return session
    }

    /// 关闭 tab。强杀 PTY,从 tabs 列表移除。
    /// 若关闭的是 active tab,activeTabId 切到最近的另一个 tab(前驱优先,否则后继),
    /// 全空则置 nil。
    public func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].terminate()
        tabs.remove(at: index)

        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                // 优先切到关闭位置的前驱,否则用原位置(现在是后继)
                let newIndex = max(0, index - 1)
                activeTabId = tabs[newIndex].id
            }
        }
    }

    /// 切换到指定 id。若 id 不在 tabs 中,无效果。
    public func activateTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    /// ⌘L:下一个 tab(循环)。
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

    /// ⌘⇧L:上一个 tab(循环)。
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

    /// 关闭当前 active tab(⌘W 用)。
    public func closeActiveTab() {
        guard let id = activeTabId else { return }
        closeTab(id: id)
    }

    /// 便利读取当前 active tab。
    public var activeTab: TabSession? {
        guard let id = activeTabId else { return nil }
        return tabs.first(where: { $0.id == id })
    }
}
```

- [ ] **Step 2:swift build 验证**

```bash
swift build 2>&1 | tail -3
```

- [ ] **Step 3:Commit**

```bash
git add Sources/CairnTerminal/TabsCoordinator.swift
git commit -m "feat(terminal): TabsCoordinator @Observable 多 tab 管理

API:openTab / closeTab(id:) / closeActiveTab / activateTab(id:) /
activateNextTab / activatePreviousTab + activeTab 便利读。
⌘L 下一个,⌘⇧L 上一个(循环切换)。关闭 active tab 切到前驱
(没有就后继)。@MainActor 保证 LocalProcessTerminalView 操作
在 main thread。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T3:`TerminalSurface` 改造,从 TabSession 取既有 NSView

**Files:**
- Modify: `Sources/CairnTerminal/TerminalSurface.swift`

**注**:M0.2 的 TerminalSurface 每次 makeNSView 创建新 LocalProcessTerminalView。改造后,接受一个 TabSession,makeNSView 返回 session.terminalView(既有)。

- [ ] **Step 1:重写 TerminalSurface**

`Sources/CairnTerminal/TerminalSurface.swift`:

```swift
import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI 封装的 SwiftTerm 终端视图。
/// **M1.4 重构**:从 TabSession 取既有 NSView,不再每次创建。
/// 这样在多 tab ZStack 里 tab 切换(.opacity toggle)不会导致 NSView
/// 被销毁,PTY 进程和滚动缓冲保留。
///
/// M1.4 之前的无参版本(M0.2 单 tab 场景)已废弃,不再保留。
public struct TerminalSurface: NSViewRepresentable {
    private let session: TabSession

    public init(session: TabSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        // 不创建新 view,返回 session 持有的(在 TabSession.init 时 create)。
        // 这是多 tab 保活的关键。
        return session.terminalView
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // 不响应 state change。字号 / 主题动态切换留 M3.x。
    }
}
```

- [ ] **Step 2:验证 MainWindowView 里旧调用会暂时报错**

M1.3 的 `MainWindowView` 里有 `TerminalSurface()`(无参)。T3 后要改为 `TerminalSurface(session: ...)`,这在 T5 完成。本 step 预期编译失败:

```bash
swift build 2>&1 | grep "error:" | head -5
```

**Expected**:`Missing argument for parameter 'session'`——正常,T5 补齐。

**T3 不 commit**(整体连锁修改,T5 一起 commit)。

---

## T4:`TabBarView` 胶囊 + 关闭按钮 + 灰色边框

**Files:**
- Create: `Sources/CairnUI/TabBar/TabBarView.swift`

- [ ] **Step 1:建目录 + 写 TabBarView**

```bash
mkdir -p /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnUI/TabBar
```

`Sources/CairnUI/TabBar/TabBarView.swift`:

```swift
import SwiftUI
import CairnTerminal

/// Main Area 顶部的 Tab Bar。spec §6.3。
/// 每个 tab 一个胶囊:左边 4pt 灰色边框 + 标题 + 关闭按钮。
/// M1.4 左边框 v1 全部灰色(Claude 蓝 / 等输入橙 / 错误红留 M2.x)。
public struct TabBarView: View {
    @Bindable var coordinator: TabsCoordinator

    public init(coordinator: TabsCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(coordinator.tabs) { tab in
                    tabPill(for: tab)
                }
                // 右侧占位(使 tab 左对齐)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func tabPill(for tab: TabSession) -> some View {
        let isActive = tab.id == coordinator.activeTabId
        return HStack(spacing: 6) {
            // 左边 4pt 灰色状态边框(v1.4 全灰,spec §6.3 后续颜色留 M2.x)
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
                    coordinator.closeTab(id: tab.id)
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
            coordinator.activateTab(id: tab.id)
        }
    }
}
```

- [ ] **Step 2:swift build(单独这个文件会连锁牵 MainWindowView)**

Step 4 时连锁 build 通过。T4 本身不 commit。

---

## T5:`MainWindowView` 整合 + ZStack 所有 terminals

**Files:**
- Modify: `Sources/CairnUI/MainWindowView.swift`

- [ ] **Step 1:重写 MainWindowView**

```swift
import SwiftUI
import CairnTerminal

/// Cairn 主窗口根视图。spec §6.1 三区布局。
///
/// 折叠状态由调用方(Scene)持有并通过 @Binding 注入;
/// TabsCoordinator 同样由 Scene 注入,作跨视图 tab 状态管理器。
public struct MainWindowView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showInspector: Bool
    @Bindable var tabsCoordinator: TabsCoordinator

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        showInspector: Binding<Bool>,
        tabsCoordinator: TabsCoordinator
    ) {
        _columnVisibility = columnVisibility
        _showInspector = showInspector
        self.tabsCoordinator = tabsCoordinator
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

    /// Main Area:TabBarView + ZStack(所有 tab 的 TerminalSurface)+ StatusBar。
    private var mainArea: some View {
        VStack(spacing: 0) {
            TabBarView(coordinator: tabsCoordinator)

            Divider()

            // ZStack 渲染所有 tabs 的 terminal view,非 active 用 opacity=0
            // 保活(NSView 不被 SwiftUI 销毁,PTY + 缓冲保留)。
            ZStack {
                if tabsCoordinator.tabs.isEmpty {
                    emptyState
                } else {
                    ForEach(tabsCoordinator.tabs) { tab in
                        TerminalSurface(session: tab)
                            .opacity(tab.id == tabsCoordinator.activeTabId ? 1 : 0)
                            .allowsHitTesting(tab.id == tabsCoordinator.activeTabId)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            StatusBarView()
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

#if DEBUG
#Preview("Main window") {
    MainWindowView(
        columnVisibility: .constant(.all),
        showInspector: .constant(true),
        tabsCoordinator: TabsCoordinator()
    )
    .frame(width: 1280, height: 800)
}
#endif
```

- [ ] **Step 2:swift build 应该编译通过(TabsCoordinator + TabSession + TabBarView 都已就位)**

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。若报 `TerminalSurface()` 无参调用错,是 CairnApp.swift 还没改(T6)。

---

## T6:`CairnApp` 注入 TabsCoordinator + commands

**Files:**
- Modify: `Sources/CairnApp/CairnApp.swift`

- [ ] **Step 1:重写 CairnApp**

```swift
import SwiftUI
import CairnUI
import CairnTerminal

@main
struct CairnApp: App {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector: Bool = true
    @State private var tabsCoordinator = TabsCoordinator()

    /// v1 没有真实 workspace 管理,用固定 UUID 作 "default workspace"
    /// 占位。M3.5 Workspace 管理就位后替换为真实 workspace id。
    private let defaultWorkspaceId = UUID()

    var body: some Scene {
        WindowGroup("Cairn") {
            MainWindowView(
                columnVisibility: $columnVisibility,
                showInspector: $showInspector,
                tabsCoordinator: tabsCoordinator
            )
            .onAppear {
                // 启动时默认开一个 tab(方便用户)
                if tabsCoordinator.tabs.isEmpty {
                    tabsCoordinator.openTab(workspaceId: defaultWorkspaceId)
                }
            }
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    withAnimation {
                        columnVisibility =
                            (columnVisibility == .detailOnly) ? .all : .detailOnly
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

            // M1.4 Tab 快捷键(spec §6.7)
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    withAnimation {
                        tabsCoordinator.openTab(workspaceId: defaultWorkspaceId)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    withAnimation {
                        tabsCoordinator.closeActiveTab()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Next Tab") {
                    tabsCoordinator.activateNextTab()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Previous Tab") {
                    tabsCoordinator.activatePreviousTab()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}
```

- [ ] **Step 2:swift build 验证**

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。

- [ ] **Step 3:Commit T3-T6 合并**

```bash
git add Sources/CairnTerminal/TerminalSurface.swift \
        Sources/CairnUI/TabBar/ \
        Sources/CairnUI/MainWindowView.swift \
        Sources/CairnApp/CairnApp.swift
git commit -m "$(cat <<'EOF'
feat(ui): 多 Tab 主窗口 + TabBarView + TerminalSurface 接入 TabSession

TerminalSurface 改为从 TabSession 取既有 LocalProcessTerminalView
(不每次 makeNSView 都 create),多 tab 切换时 PTY + 缓冲保活。

TabBarView 渲染胶囊 + 关闭按钮 + 左边 3pt 灰色状态条
(v1.4 全灰;spec §6.3 的 blue/orange/red 随 M2.x Claude 检测一起加)。
点击切换、关闭按钮 ⌘W 提示。

MainWindowView 新增 TabsCoordinator @Bindable,Main Area 用 ZStack
渲染 tabs:active 不透明、inactive .opacity(0) + allowsHitTesting(false)
保活。空 tabs 态显示 "No active tab" 提示。

CairnApp Scene-level 注入 TabsCoordinator;onAppear 自动开一个 tab;
commands 加 ⌘T(新建)/ ⌘W(关闭)/ ⌘L(下一个)/ ⌘⇧L(上一个)。
所有状态改动 withAnimation 包裹,保持 M1.3 已有的丝滑体验。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## T7:processTerminated delegate → tab 自动关闭

**Files:**
- Modify: `Sources/CairnTerminal/TabSession.swift`(加 LocalProcessTerminalViewDelegate 实现)
- Modify: `Sources/CairnTerminal/TabsCoordinator.swift`(暴露"tab 自然退出"的处理方法)

**设计要点**:SwiftTerm 的 `LocalProcessTerminalView` 通过 `processDelegate` 通知外部进程退出。delegate 的 `processTerminated(_:exitCode:)` 在 shell exit(或被杀)后被调用。我们在此时把对应 tab 从 coordinator 移除。

- [ ] **Step 1:TabSession 加 `ProcessTerminationObserver`(嵌套 class 实现 delegate)**

追加到 `TabSession.swift` 末尾:

```swift

/// 监听 LocalProcessTerminalView 的 processTerminated 事件。
/// 为避免 SwiftTerm 原生 delegate 协议泄漏到 coordinator,用一个
/// 内部 observer class 转发。
@MainActor
public final class ProcessTerminationObserver: NSObject, LocalProcessTerminalViewDelegate {
    public typealias Callback = @MainActor (_ exitCode: Int32?) -> Void

    private let onTerminated: Callback

    public init(onTerminated: @escaping Callback) {
        self.onTerminated = onTerminated
        super.init()
    }

    // MARK: - LocalProcessTerminalViewDelegate

    public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // v1 无需处理(SwiftTerm 内部已发 TIOCSWINSZ)
    }

    public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // v1 不用 OSC 2/1 标题(M1.5 OSC 7 cwd 一起考虑)
    }

    public func hostCurrentDirectoryUpdate(source: LocalProcessTerminalView, directory: String?) {
        // OSC 7 cwd 跟踪留 M1.5
    }

    public func processTerminated(source: TerminalView, exitCode: Int32?) {
        onTerminated(exitCode)
    }
}
```

- [ ] **Step 2:TabSessionFactory 创建 session 后安装 observer**

修改 `TabSessionFactory.create`,加一个 callback 参数:

```swift
public static func create(
    workspaceId: UUID,
    shell shellPath: String? = nil,
    cwd startCwd: String? = nil,
    onProcessTerminated: @escaping @MainActor (Int32?) -> Void = { _ in }
) -> TabSession {
    // ... 前面不变 ...

    let view = LocalProcessTerminalView(frame: .zero)

    // 安装 delegate
    let observer = ProcessTerminationObserver(onTerminated: onProcessTerminated)
    view.processDelegate = observer

    view.startProcess(
        executable: shell,
        args: [],
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
    // 把 observer 绑到 session 上防止被释放
    session.processObserver = observer
    return session
}
```

- [ ] **Step 3:TabSession 加 processObserver 存储属性**

在 TabSession class 里加一个 `internal var processObserver: ProcessTerminationObserver?`,用于强引用 observer 避免 SwiftTerm 的 weak processDelegate 被释放:

```swift
// TabSession class 内部加:
internal var processObserver: ProcessTerminationObserver?
```

- [ ] **Step 4:TabsCoordinator 暴露"process terminated" 处理**

TabsCoordinator.openTab 里,在 create 时注入 callback 指向自己的 cleanup 方法:

```swift
@discardableResult
public func openTab(
    workspaceId: UUID,
    shell: String? = nil,
    cwd: String? = nil
) -> TabSession {
    let effectiveCwd = cwd ?? activeTab?.cwd
    var createdSession: TabSession!
    createdSession = TabSessionFactory.create(
        workspaceId: workspaceId,
        shell: shell,
        cwd: effectiveCwd,
        onProcessTerminated: { [weak self] _ in
            guard let self else { return }
            // shell exit → 自动把 tab 从列表移除(不走 terminate,
            // 进程已经自己退了)。
            self.removeTabWithoutTerminate(id: createdSession.id)
        }
    )
    tabs.append(createdSession)
    activeTabId = createdSession.id
    return createdSession
}

/// 内部用:tab 进程自然退出时,从列表移除(不再调 terminate)。
private func removeTabWithoutTerminate(id: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
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
}
```

- [ ] **Step 5:swift build 验证 + commit**

```bash
swift build 2>&1 | tail -3
git add Sources/CairnTerminal/TabSession.swift Sources/CairnTerminal/TabsCoordinator.swift
git commit -m "feat(terminal): processTerminated delegate 接入,shell 退出自动关 tab

ProcessTerminationObserver 实现 LocalProcessTerminalViewDelegate,
仅响应 processTerminated,其他回调(sizeChanged / titles / OSC 7)
M1.5 + M2.x 再填。

TabSession 强引用 processObserver(SwiftTerm 的 processDelegate
是 weak),防止被 ARC 释放丢 delegate 回调。

TabsCoordinator.openTab 注入 callback:[weak self] 避开循环引用;
process exit 时走 removeTabWithoutTerminate(不再 terminate,进程已退),
保持 tabs 列表跟随真实进程状态。关 active tab 的 active 切换逻辑
与手动 closeTab 一致。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T8:TabsCoordinator 单测

**Files:**
- Modify: `Package.swift`(加 `.testTarget(name: "CairnTerminalTests", ...)`)
- Create: `Tests/CairnTerminalTests/TabsCoordinatorTests.swift`

**注意**:TabsCoordinator 测试需要真实 `LocalProcessTerminalView` —— 但创建这个会 fork PTY 进程,测试环境可能限制。替代方案:在 TabsCoordinator 里暴露"注入 factory"的路径,测试时注入 mock。

**简化方案**(M1.4 采纳):测试只覆盖 coordinator 的**纯状态逻辑**(activateNext / activatePrevious 的 rotation 算法,close 后 activeTabId 切换逻辑)—— 用"mock session" 方案:让 TabsCoordinator 提供一个"内部测试专用"的 openTab 重载 `_openTabForTesting(_:)`,直接接受已构造的 TabSession。

实际代码:我们把 openTab 里的 `tabs.append(session); activeTabId = session.id` 抽成 private `addAndActivate(_:)`,测试通过 `@testable` 访问并 inject 伪造 session。

- [ ] **Step 1:TabsCoordinator 加 internal 测试入口**

在 TabsCoordinator 末尾加:

```swift
#if DEBUG
extension TabsCoordinator {
    /// 仅测试用:直接注入已构造的 TabSession,跳过 PTY 进程启动。
    /// `@testable import CairnTerminal` 可访问。
    internal func _insertForTesting(_ session: TabSession) {
        tabs.append(session)
        activeTabId = session.id
    }
}
#endif
```

- [ ] **Step 2:Package.swift 加 testTarget**

追加到 targets 数组:

```swift
.testTarget(name: "CairnTerminalTests", dependencies: ["CairnTerminal"]),
```

- [ ] **Step 3:写单测**

```bash
mkdir -p /Users/sorain/xiaomi_projects/AICoding/cairn/Tests/CairnTerminalTests
```

`Tests/CairnTerminalTests/TabsCoordinatorTests.swift`:

```swift
import XCTest
import AppKit
import SwiftTerm
@testable import CairnTerminal

@MainActor
final class TabsCoordinatorTests: XCTestCase {
    /// 不启动真实 PTY 进程的 TabSession(测试用)。
    private func makeFakeSession(workspaceId: UUID = UUID()) -> TabSession {
        let view = LocalProcessTerminalView(frame: .zero)
        // 不调 startProcess,view 里 process 未启动 —— 测试只看状态逻辑,
        // 不实际 IO。terminate() 调用在 .closed 场景但不实际触发,
        // 但因为 process 未启动,terminate 可能 noop 或 warning —— 不影响
        // 纯状态断言。
        return TabSession(
            workspaceId: workspaceId,
            title: "test",
            cwd: "/tmp",
            shell: "/bin/zsh",
            terminalView: view
        )
    }

    func test_openTab_viaInsertHelper_appendsAndActivates() {
        let c = TabsCoordinator()
        let s = makeFakeSession()
        c._insertForTesting(s)
        XCTAssertEqual(c.tabs.count, 1)
        XCTAssertEqual(c.activeTabId, s.id)
        XCTAssertEqual(c.activeTab?.id, s.id)
    }

    func test_activateNextTab_cycles() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        let b = makeFakeSession(); c._insertForTesting(b)
        let d = makeFakeSession(); c._insertForTesting(d)
        // 当前 active 是 d(最后 insert 的),next 应 wrap 到 a
        c.activateNextTab()
        XCTAssertEqual(c.activeTabId, a.id)
        c.activateNextTab()
        XCTAssertEqual(c.activeTabId, b.id)
    }

    func test_activatePreviousTab_cycles() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        let b = makeFakeSession(); c._insertForTesting(b)
        let d = makeFakeSession(); c._insertForTesting(d)
        c.activateTab(id: a.id)
        c.activatePreviousTab()
        // 从 a 往前 wrap 到最后一个(d)
        XCTAssertEqual(c.activeTabId, d.id)
    }

    func test_closeTab_activatesPredecessor() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        let b = makeFakeSession(); c._insertForTesting(b)
        let d = makeFakeSession(); c._insertForTesting(d)
        c.activateTab(id: b.id)  // 当前 b
        c.closeTab(id: b.id)
        XCTAssertEqual(c.tabs.count, 2)
        // b 关掉,active 切到前驱 a
        XCTAssertEqual(c.activeTabId, a.id)
    }

    func test_closeTab_lastTab_activeIdNil() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        c.closeTab(id: a.id)
        XCTAssertTrue(c.tabs.isEmpty)
        XCTAssertNil(c.activeTabId)
    }

    func test_activateTab_ignoresUnknownId() {
        let c = TabsCoordinator()
        let a = makeFakeSession(); c._insertForTesting(a)
        let fakeId = UUID()
        c.activateTab(id: fakeId)
        // 未改变
        XCTAssertEqual(c.activeTabId, a.id)
    }

    func test_activateNextTab_fromEmpty_isNoop() {
        let c = TabsCoordinator()
        c.activateNextTab()  // 不 crash
        XCTAssertNil(c.activeTabId)
    }
}
```

- [ ] **Step 4:跑测试 + commit**

```bash
swift test --filter TabsCoordinatorTests 2>&1 | tail -5
```

**Expected**:`Executed 7 tests, with 0 failures`。

```bash
git add Sources/CairnTerminal/TabsCoordinator.swift Package.swift \
        Tests/CairnTerminalTests/
git commit -m "test(terminal): TabsCoordinator 7 单测 + CairnTerminalTests target

覆盖:openTab / activateNextTab / activatePreviousTab(带 rotation)
/ closeTab(含前驱切换 + 最后一个切 nil)/ activateTab 的未知 id
noop / activateNextTab 空态 noop。

_insertForTesting 是 #if DEBUG internal 测试入口 —— 不启动真实
PTY,绕开 XCTest 沙箱对 forkpty 的限制。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T9:CairnCore bump 到 `0.4.0-m1.4`

**Files:**
- Modify: `Sources/CairnCore/CairnCore.swift`
- Modify: `Tests/CairnCoreTests/CairnCoreTests.swift`(两处 "m1.3" → "m1.4")
- Modify: `Tests/CairnStorageTests/CairnStorageTests.swift`(scaffoldVersion 断言 `"0.3.0-m1.3"` → `"0.4.0-m1.4"`)

- [ ] **Step 1:编辑 + 跑测试 + commit**

```bash
swift test 2>&1 | grep "Executed" | tail -1
```

**Expected**:`Executed ≥ 110 tests, with 0 failures`(M1.1 54 + M1.2 45 + M1.3 4 + M1.4 7 = 110)。

```bash
git add Sources/CairnCore/CairnCore.swift \
        Tests/CairnCoreTests/CairnCoreTests.swift \
        Tests/CairnStorageTests/CairnStorageTests.swift
git commit -m "chore(core): scaffoldVersion 0.3.0-m1.3 → 0.4.0-m1.4"
```

---

## T10:完整 swift build + test + 肉眼自检

**Files:** 无新增。

- [ ] **Step 1:build + test**

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build 2>&1 | tail -3
swift test 2>&1 | grep "Executed" | tail -3
```

**Expected**:Build complete;总 ≥ 110 tests green。

- [ ] **Step 2:打包 + 启动自检**

```bash
./scripts/make-app-bundle.sh debug --open
sleep 4
pgrep -fl "Cairn.app/Contents/MacOS/CairnApp" | head -1
```

**Claude 层自检**:
- [ ] 窗口弹出,默认 1280×800
- [ ] 启动时自动有 1 个 tab("~ (zsh)" 或 "$HOME basename (zsh)")
- [ ] StatusBar 底部显示 `Cairn v0.4.0-m1.4`
- [ ] `⌘T` 按下开第 2 个 tab,active 切到新 tab
- [ ] `⌘L` 循环切换
- [ ] `⌘W` 关闭当前 tab

**注**:视觉级(tab 胶囊样式 / 颜色 / 点击交互)留 T12 用户肉眼。

- [ ] **Step 3:清理**

```bash
pkill -f "Cairn.app/Contents/MacOS/CairnApp" 2>/dev/null
```

---

## T11:milestone-log + tag m1-4-done + push

**Files:**
- Modify: `docs/milestone-log.md`

- [ ] **Step 1:追加 M1.4 完成条目**

```markdown
### M1.4 多 Tab 管理 + TerminalSurface 封装 + PTY 生命周期

**Completed**: 2026-04-27(或 Claude 实际完成日)
**Tag**: `m1-4-done`
**Commits**: ~6 个(T1 / T2 / T3-T6 合并 / T7 / T8 / T9)

**Summary**:
- `CairnTerminal.TabSession`(@MainActor class)包 `LocalProcessTerminalView` 实例 + 领域元数据(id / workspaceId / title / cwd / shell / state)
- `CairnTerminal.TabsCoordinator`(@Observable)管 tabs 列表 + activeTabId,API:openTab / closeTab / closeActiveTab / activateTab / activateNextTab / activatePreviousTab
- `TerminalSurface` 改为从 TabSession 取既有 NSView —— tab 切换时 PTY + 缓冲**不丢**
- `CairnUI.TabBarView` 胶囊样式 + 关闭按钮 + 左边 3pt 灰色状态条(v1.4 全灰,spec §6.3 的 blue/orange/red 随 M2.x 加)
- `MainWindowView` Main Area 用 ZStack 渲染所有 tabs:active .opacity(1) .allowsHitTesting(true),inactive .opacity(0) .allowsHitTesting(false)
- `CairnApp` Scene-level 注入 `TabsCoordinator`,onAppear 自动开一个 tab,commands 加 `⌘T` / `⌘W` / `⌘L` / `⌘⇧L`
- `ProcessTerminationObserver` 接 SwiftTerm `LocalProcessTerminalViewDelegate`,shell 退出自动把 tab 从 coordinator 移除
- 7 个单测覆盖 coordinator 状态逻辑;**总 110+ tests green**

**关键设计决策**(plan pinned 10 条,见对应 plan):
- ZStack 保活 inactive tab(.opacity + .allowsHitTesting),代价是渲染开销
- TabSession @MainActor class + @Observable coordinator
- 关 active tab 切前驱优先
- Tab 左边框 v1 全灰,颜色语义迭代留 M2.x
- 新 tab cwd 继承 active tab 的 cwd
- 不加 XCTest UI 自动化,肉眼验收

**Acceptance**: 见 M1.4 计划文档 T12 验收清单。

**Known limitations**:
- OSC 7 cwd 跟踪留 M1.5(现在 cwd 不会随 shell cd 动态更新)
- 布局持久化(关 App 再开 tabs 全丢)留 M1.5
- Tab 左边框 blue/orange/red 颜色留 M2.x
- Tab 标题不响应 `setTerminalTitle`(OSC 2)—— M1.5 起
```

- [ ] **Step 2:Push + Tag**

```bash
git add docs/milestone-log.md
git commit -m "docs(log): M1.4 完成记录"
git push origin main 2>&1 | tail -3
git tag -a m1-4-done -m "M1.4 完成:多 Tab 管理 + PTY 生命周期"
git push origin m1-4-done 2>&1 | tail -3
```

---

## T12:验收清单(用户,含肉眼验收)

**Owner**: 用户。

```markdown
## M1.4 验收清单

**验证步骤**:

步骤 1 · 编译
```bash
swift build 2>&1 | tail -3
```
期望:`Build complete!`。

步骤 2 · 测试
```bash
swift test 2>&1 | grep "Executed" | tail -3
```
期望:`Executed ≥ 110 tests, with 0 failures`。

步骤 3 · 文件就位
```bash
ls Sources/CairnTerminal/ Sources/CairnUI/TabBar/ Tests/CairnTerminalTests/
```

步骤 4 · **肉眼验收**(7 项)

```bash
./scripts/make-app-bundle.sh debug --open
```

- [ ] 启动时自动开一个 tab(标题类似 `HOME_basename (zsh)`)
- [ ] Tab Bar 顶部,active tab 胶囊有淡灰底色,inactive 透明
- [ ] 每个 tab 胶囊左边有 3pt 灰色竖条 + 标题 + 右侧 × 关闭按钮
- [ ] 按 `⌘T`:新 tab 出现,active 切到新 tab,终端从前一 tab 的 cwd 启动
- [ ] 按 `⌘L`:循环切到下一个 tab;`⌘⇧L` 切到上一个
- [ ] 按 `⌘W` 或点 ×:当前 tab 关闭,active 切到前驱(没前驱就后继);最后一个 tab 关掉后显示空态提示 "Press ⌘T to open a new terminal"
- [ ] 在任一 tab 里输入 `exit` + Enter:该 tab 几秒内自动消失(processTerminated 触发)

步骤 5 · Git
```bash
git tag -l
```
期望:6 tag(m0-1 到 m1-4)。

**Known limitations**: 同 milestone-log。

**下个 M**:M1.5 水平分屏 + OSC 7 cwd 跟踪 + 布局 SQLite 持久化。
```

---

## 回归 Self-Review

### 1. Spec 覆盖

| Spec 位置 | 要求 | 对应 Task | 状态 |
|---|---|---|---|
| §5.1 TerminalSession 抽象 | 有 | TabSession(T1)| ✅ |
| §5.2 PTY 生命周期 | 创建 / IO / 退出 / 强杀 | T1 create + T7 exit delegate + coordinator terminate(kill) | ✅ |
| §5.3 Tab/Split 架构 | TabGroupView | T4 TabBarView + T5 MainWindowView | ✅(split 留 M1.5)|
| §6.3 Main Area Tab 行为 | ⌘T/⌘W/⌘L + 左边灰色/蓝/橙/红 | T6 shortcuts + T4 灰色(其他颜色 M2.x)| 🟡 颜色只实装灰 |
| §6.7 快捷键 | v1 17 个 | M1.3 + M1.4 累计 6 个(⌘⇧T/⌘I/⌘T/⌘W/⌘L/⌘⇧L);剩 11 个留后续 | 🟡 渐进 |
| §8.4 M1.4 验收 | ⌘T/⌘W/⌘L 可用 | T6 + T12 | ✅ |

### 2. Placeholder 扫描

- "TBD" / "FIXME" / "implement later" — 本 plan 无违规
- "M1.5 再填" / "M2.x 起" 是**明确延后点**,不算 placeholder

### 3. 类型 / 命名一致性

- `TabSession` / `TabsCoordinator` / `TabSessionFactory` / `ProcessTerminationObserver` —— 统一 Tab* 前缀
- `openTab` / `closeTab` / `closeActiveTab` / `activateTab` / `activateNextTab` / `activatePreviousTab` —— 动词 + Tab(s)模式,一致
- `view.process.terminate(asKillSignal: true)` —— SwiftTerm API 签名,T1 Step 1 使用,与 spec §5.2 "terminate(kill)" 对齐

### 4. 任务归属 & 自检

- T1-T11 Claude 全做;T12 用户
- 无模糊区域

### 5. 潜在风险

**风险 1(中)**:**ZStack + .opacity 保活 inactive tab 的实际效果**。
SwiftUI 虽然保留 view,但每次 @Observable 变化会重建 body;`NSViewRepresentable.makeNSView` 理论上只调一次(SwiftUI 用 Coordinator 缓存),但若 SwiftUI 决定重建整个 ZStack,NSView 会被销毁。
**缓解**:`TabSession.terminalView` 是 session 持有的强引用,即使 SwiftUI 销毁 NSViewRepresentable struct,NSView 本身不被销毁(因 session 持有)。下次 TerminalSurface 重建时 makeNSView 返回同一实例,attach 回视图树。**执行时需肉眼验证**:切 tab 回来后终端内容还在 + cursor 可输入。

**风险 2(中)**:**`LocalProcessTerminalView` 重挂到不同父视图时光标 / 焦点行为**。
SwiftUI ZStack 切换 tab 时,原 NSView 从一个位置 detach,attach 到(视觉意义上)另一位置 —— 实际上 NSView 只有一个位置,SwiftUI 只改 opacity,layout 不变。焦点不应丢。**执行时肉眼验证**:⌘L 切 tab 后键盘输入进到新 active tab,而不是旧。

**风险 3(低)**:**SwiftTerm `processDelegate` 是 weak 引用**。
若 TabSession 不持有 observer,observer 被 ARC 释放 → delegate 回调丢失 → tab 不会在 shell exit 时自动关。
**修**:T7 Step 3 加 `TabSession.processObserver` 强引用。

**风险 4(已消除)**:~~测试里创建 `LocalProcessTerminalView` 不 startProcess 是否安全~~。
T1 Step 1 的 TabSession.terminate 已用 `terminalView.process?.terminate(asKillSignal: true)` optional chain;SwiftTerm `process` 声明是 IUO (`LocalProcess!`),未 startProcess 时用 `?.` 安全 no-op,不会 force-unwrap crash。

**风险 5(低,执行时验证)**:**`process.terminate(asKillSignal:)` API 签名**。
spec §5.2 写 "terminate(kill)",本 plan 按 `terminate(asKillSignal: Bool)` 翻译。若 SwiftTerm 1.13 真实签名是 `terminate()` 无参,T1 build 会报错,改为无参即可(语义是强杀)。

### 6. 结论

Plan 可执行。2 个中级风险(ZStack 保活 / 焦点)需肉眼验证;2 个低风险有明确 fix 路径。
