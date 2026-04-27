# M1.3 实施计划:SwiftUI 主窗口三区 + Sidebar/Panel 可折叠

> **For agentic workers:** 本 plan 给 Claude 主导执行(见 `CLAUDE.md`)。每个 Task 按 Step 逐步完成。用户职责仅 T9 验收(含**必做的肉眼验收**)。

**Goal:** 把 M0.2 的单终端窗口重构为 spec §6 设计的三区主窗口(Sidebar / Main / Right Panel),Sidebar/Panel 可键盘折叠,Main Area 保留现有 SwiftTerm。Sidebar/Panel 本 milestone **只放空态占位**(真实内容 Task/Budget/Timeline 留 M3.x)。

**Architecture:** SwiftUI `NavigationSplitView`(Sidebar + Detail)+ `.inspector()` modifier(Right Panel)组合出三栏。键盘快捷键用 `.keyboardShortcut` 显式覆盖默认:`⌘⇧T` 切 Sidebar、`⌘I` 切 Inspector。所有现有 M0.2 TerminalSurface 内容不动,被包进 Detail 区。

**Tech Stack:** SwiftUI · macOS 14(`NavigationSplitView` + `.inspector` 都是 macOS 14+ API)· CairnUI 模块独立增扩,CairnApp 只改 Scene 入口·无新第三方依赖。

**Claude 总耗时:** 约 60-90 分钟。
**用户总耗时:** 约 5-10 分钟(T9 验收含肉眼核对布局)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. CairnUI `MainWindowView`(`NavigationSplitView` + `.inspector`)骨架 | Claude | — |
| T2. `SidebarView` 空态占位(Task list placeholder) | Claude | T1 |
| T3. `RightPanelView` 空态占位(3 小节:Current Task / Budget / Timeline)| Claude | T1 |
| T4. 顶部 `ToolbarContent`(workspace 选择器占位 + 设置/通知按钮)+ 状态栏 `StatusBarView` | Claude | T1 |
| T5. 键盘快捷键:`⌘⇧T` / `⌘I` / `⌘⇧E` / `⌘N` 等 spec §6.7 标识的 v1 快捷键(实装能触发的那部分) | Claude | T1-T4 |
| T6. `CairnApp.swift` 把 `ContentView()` 替换为 `MainWindowView()`;窗口默认尺寸 1280×800 | Claude | T1 |
| T7. `CairnUI` + `CairnServices` 最小 ViewModel(`MainWindowViewModel` 管折叠状态)+ 单测 | Claude | T1 |
| T8. CairnCore scaffoldVersion bump 到 `0.3.0-m1.3` + 测试断言同步 | Claude | — |
| T9. 手动验收 + build + swift test 全绿 + `open build/Cairn.app` 肉眼核对 | Claude | T1-T8 |
| T10. milestone-log + tag `m1-3-done` + push | Claude | T9 |
| T11. 输出验收清单(含**必做肉眼验收**) | **用户** | T10 |

---

## 文件结构规划

**新建**(CairnUI):

```
Sources/CairnUI/
├── ContentView.swift                 (M0.2 遗留,本 milestone 保留且被 MainWindowView 包)
├── MainWindowView.swift              (T1 新增,三区布局根视图)
├── MainWindowViewModel.swift         (T7,折叠状态 @Observable)
├── Sidebar/
│   └── SidebarView.swift             (T2 空态占位)
├── RightPanel/
│   └── RightPanelView.swift          (T3 空态占位,3 小节)
├── Toolbar/
│   └── ToolbarContent.swift          (T4 顶部工具条)
└── StatusBar/
    └── StatusBarView.swift           (T4 底部 cwd/branch 占位)
```

**修改**:
- `Sources/CairnApp/CairnApp.swift` — T6:`ContentView()` → `MainWindowView()` + `.defaultSize(width: 1280, height: 800)` + 菜单命令
- `Sources/CairnCore/CairnCore.swift` — T8:`0.2.0-m1.2` → `0.3.0-m1.3`
- `Tests/CairnCoreTests/CairnCoreTests.swift` — T8:断言 `m1.2` → `m1.3`
- `Tests/CairnStorageTests/CairnStorageTests.swift` — T8:scaffoldVersion 断言同步
- `docs/milestone-log.md` — T10

**删除**:无

---

## 设计决策(pinned,Plan 执行中不重新讨论)

| # | 决策 | 选择 | 理由 |
|---|---|---|---|
| 1 | 三栏布局 API | `NavigationSplitView`(Sidebar+Detail)+ `.inspector()` modifier(Right Panel) | 原生 macOS 14+ API,自带过渡动画、默认尺寸管理;自己 HStack 需要再造这些。spec A10 "三区布局" 不限定实现 |
| 2 | 本 milestone **不实现 Task / Workspace 真实内容** | Sidebar 显"暂无 Workspace"空态,Right Panel 显 3 个"暂无"占位 | spec §8.4 M1.3 "启动看到 Section 6 布局" 是 UI**结构**验收,非内容;Task 实体由 M3.1 / Budget 由 M3.3 填 |
| 3 | Main Area 主体仍是 **M0.2 的 TerminalSurface** | 不碰现有 `ContentView`,将其作为 NavigationSplitView 的 detail 列内容 | spec §6.3 "v1 主区域只放终端";M1.3 只加 chrome,不改终端 |
| 4 | 键盘快捷键 | `⌘⇧T` Sidebar / `⌘I` Inspector / `⌘⇧E` 展开所有 Events(v1 noop,事件尚无)/ `⌘N` 新 Workspace(v1 noop) | spec §6.7 v1 共 17 个快捷键;本 milestone 只实装 4 个**结构性**的;其他留各自 milestone |
| 5 | 折叠状态管理 | `@State` 放在 `MainWindowView`(非 `MainWindowViewModel`) | SwiftUI `NavigationSplitView` 的 `columnVisibility` 必须是 `@Binding`,直接 `@State` 最简;ViewModel 管那些跨视图状态 |
| 6 | `MainWindowViewModel` scope | 本 milestone 只管 "当前 workspace 选择"(恒 nil,为 M3.5 Workspace 管理预留接口)+ 折叠状态的初始值 | YAGNI;避免为尚未存在的 Task/Budget 提前设计 VM |
| 7 | 不依赖 CairnStorage | M1.3 UI 层纯占位,不读/写 DB | LayoutState 持久化留 M1.5(OSC 7 + 布局持久化 milestone 专门做) |
| 8 | 测试策略 | 单测 ViewModel 折叠状态 + CairnCore 版本 bump 测试;**不加 XCTest UI 自动化**(留 M4.2) | spec §8.4 M1.3 验收是"手动验收,布局像设计图";UI 自动化在 M4.2 作为质量基准交付 |

---

## 架构硬约束(不得违反)

- CairnUI **允许** import `SwiftUI` / `CairnCore` / `CairnServices` / `CairnTerminal`(spec §3.2);**不能** import `CairnStorage` / `CairnClaude`(spec 明示"UI 不直接 import CairnStorage";CairnClaude 对应通配)
- CairnApp **只** import `SwiftUI` / `CairnUI`
- **不允许**在 View body 里写业务逻辑;状态变更经 `@State` / `@Binding` / `MainWindowViewModel`
- 所有文本必须可本地化:暂时用英文字面量,M4.1 起批量迁移 `String(localized:)`(本 milestone 不做本地化)

---

## T1:`MainWindowView` 三区骨架

**Files:**
- Create: `Sources/CairnUI/MainWindowView.swift`

- [ ] **Step 1:写 MainWindowView**

`Sources/CairnUI/MainWindowView.swift`:

```swift
import SwiftUI
import CairnTerminal

/// Cairn 主窗口根视图。spec §6.1 三区布局。
///
/// 折叠状态由**调用方(Scene)持有**并通过 `@Binding` 注入 —— Scene-level
/// commands 里的 `⌘⇧T` / `⌘I` 菜单项直接 toggle 这两个 state,
/// 避免 `NSApp.tryToPerform(toggleSidebar:)` 这类 AppKit 桥接的脆弱性。
///
/// - Sidebar:Task 列表(M1.3 占位);280pt 默认宽,`⌘⇧T` 折叠
/// - Main Area:TerminalSurface + Tab Bar + Status Bar
/// - Right Panel (Inspector):Current Task / Budget / Timeline(M1.3 占位);360pt 默认宽,`⌘I` 折叠
public struct MainWindowView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showInspector: Bool

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        showInspector: Binding<Bool>
    ) {
        _columnVisibility = columnVisibility
        _showInspector = showInspector
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

    /// Main Area:Tab Bar(v1.3 占位)+ Terminal + Status Bar。
    private var mainArea: some View {
        VStack(spacing: 0) {
            // Tab Bar 占位(M1.4 填充真实 tabs)
            HStack(spacing: 8) {
                Text("~ (zsh)")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Terminal — 直接用 CairnTerminal 模块的 TerminalSurface
            TerminalSurface()

            Divider()

            StatusBarView()
        }
    }
}

#if DEBUG
#Preview("Main window") {
    // Preview 用 .constant 提供静态 Binding
    MainWindowView(
        columnVisibility: .constant(.all),
        showInspector: .constant(true)
    )
    .frame(width: 1280, height: 800)
}
#endif
```

- [ ] **Step 2:验证 SwiftUI 编译**

```bash
swift build 2>&1 | tail -5
```

**Expected**:编译报错 `Cannot find 'SidebarView' in scope` / `Cannot find 'RightPanelView' in scope` / `Cannot find 'ToolbarContent' in scope` / `Cannot find 'StatusBarView' in scope` —— 正常,后续 task 补全。

此步只验证 MainWindowView **本身**语法无误(T1 不 commit,直到 T2-T4 补齐后再一并 commit 或拆 commit)。

---

## T2:`SidebarView` 空态占位

**Files:**
- Create: `Sources/CairnUI/Sidebar/SidebarView.swift`

- [ ] **Step 1:写 SidebarView**

```bash
mkdir -p /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnUI/Sidebar
```

`Sources/CairnUI/Sidebar/SidebarView.swift`:

```swift
import SwiftUI

/// Sidebar:Task 列表(按 Workspace 分组)。spec §6.2。
/// M1.3 只做空态占位;真实 Task 项由 M3.1+ 填充。
public struct SidebarView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 筛选栏(v1.3 占位)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Search tasks")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 空态内容
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("No workspaces yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Tasks from your Claude Code sessions will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Tasks")
    }
}

#if DEBUG
#Preview {
    SidebarView().frame(width: 280, height: 600)
}
#endif
```

---

## T3:`RightPanelView` 3 小节占位

**Files:**
- Create: `Sources/CairnUI/RightPanel/RightPanelView.swift`

- [ ] **Step 1:建目录 + 写 RightPanelView**

```bash
mkdir -p /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnUI/RightPanel
```

`Sources/CairnUI/RightPanel/RightPanelView.swift`:

```swift
import SwiftUI

/// Right Panel(Inspector):当前 Task 的详情 / Budget / Event Timeline。
/// spec §6.1 + §6.5-§6.6。M1.3 只做 3 小节空态占位。
public struct RightPanelView: View {
    public init() {}

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

                section(
                    title: "Event Timeline",
                    emptyLine: "Events stream in as Claude Code runs."
                )
            }
            .padding(16)
        }
    }

    private func section(title: String, emptyLine: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(emptyLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
#Preview {
    RightPanelView().frame(width: 360, height: 600)
}
#endif
```

---

## T4:ToolbarContent + StatusBarView

**Files:**
- Create: `Sources/CairnUI/Toolbar/ToolbarContent.swift`
- Create: `Sources/CairnUI/StatusBar/StatusBarView.swift`

- [ ] **Step 1:建目录 + 写 ToolbarContent**

```bash
mkdir -p /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnUI/Toolbar
mkdir -p /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnUI/StatusBar
```

`Sources/CairnUI/Toolbar/ToolbarContent.swift`:

```swift
import SwiftUI

/// 主窗口顶部工具条。spec §6.1 顶端示意。
/// 本 milestone:workspace 选择器占位 + 通知 / 设置 / Inspector 切换按钮。
///
/// **命名注**:SwiftUI 自身有 `ToolbarContent` 协议;我们这个 struct
/// 取名 `CairnToolbarContent` 以避 `struct X: X` 形式的递归类型歧义。
public struct CairnToolbarContent: ToolbarContent {
    @Binding var showInspector: Bool

    public init(showInspector: Binding<Bool>) {
        _showInspector = showInspector
    }

    public var body: some ToolbarContent {
        // 左侧:Workspace 选择器占位
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("New Workspace...") {
                    // M3.5 填充
                }
                Divider()
                Text("No workspaces yet")
            } label: {
                Label("Workspace", systemImage: "folder")
            }
        }

        // 右侧:系统按钮组
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                // M4.3 诊断 / 通知中心
            } label: {
                Label("Notifications", systemImage: "bell")
            }
            .help("Notifications")

            Button {
                // M4.1 Settings 页
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings")

            Button {
                showInspector.toggle()
            } label: {
                Label("Toggle Inspector",
                      systemImage: showInspector
                        ? "sidebar.right"
                        : "sidebar.trailing")
            }
            // ⌘I 快捷键在 Scene commands 里绑,此处不重复(避免歧义)
            .help("Toggle inspector (⌘I)")
        }
    }
}
```

- [ ] **Step 2:写 StatusBarView**

`Sources/CairnUI/StatusBar/StatusBarView.swift`:

```swift
import SwiftUI
import CairnCore

/// 窗口底部状态栏:cwd / git branch(v1 占位)。spec §6.1。
public struct StatusBarView: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 16) {
            Label("~", systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            // 引用 CairnCore.scaffoldVersion 避免硬编码 —— bump 版本时自动跟随
            Text("Cairn v\(CairnCore.scaffoldVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
```

**Step 3:**此时 `swift build` 应编译通过。跑:

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。

---

## T5:键盘快捷键

**Files:**
- Modify: `Sources/CairnUI/MainWindowView.swift`(在根视图附 `.keyboardShortcut` 没覆盖到的)

实际上 `⌘⇧T`(Sidebar)在 `NavigationSplitView` 上不能直接 keyboardShortcut,要通过 `SidebarCommands`(Scene 级)。

- [ ] **Step 1:改 MainWindowView 暴露 Sidebar 折叠动作**

修改 `MainWindowView` 加一个 public 方法或把 `columnVisibility` 提升为 Binding,让 Scene 层可以注入。更简单:直接在 `SidebarView` 上加 `.keyboardShortcut` 是无效的(它不是 Button)。

**最小代价方案**:用 scene-level `.commands` 写入 `CommandMenu("View")`,包含两个 Toggle 条目,绑定到一个 scene-level `@State`。这会在 Menu Bar 的 "View" 菜单里创建两项。

这意味着 Scene-level state 要管 columnVisibility 和 inspector —— 折叠状态提升到 `CairnApp.swift`。T6 处理。

本 task 先标记:键盘快捷键的主体实装移到 T6。此 T5 退化为**占位 task**,仅记录 spec §6.7 的 17 个快捷键中本 milestone 实装的 4 个,其余留后续。

- [ ] **Step 2:在 `ToolbarContent` 的 Inspector toggle 按钮上已有 `⌘I`(T4 已做)**

Inspector toggle 快捷键由 T4 的 `.keyboardShortcut("i", modifiers: .command)` 提供。

- [ ] **Step 3:记录 spec §6.7 待实装情况**

本 milestone 实装 1 个(⌘I Inspector)。`⌘⇧T` Sidebar 在 T6 Scene 级命令里实装。其余 15 个快捷键(⌘T / ⌘W / ⌘L / ⌘1-9 / 等)留 M1.4 / M3.x。

**此 task 不新增代码,仅做决策记录。不 commit。**

---

## T6:`CairnApp` 切到 `MainWindowView` + Scene 级 @State + 快捷键

**Files:**
- Modify: `Sources/CairnApp/CairnApp.swift`
- Modify: `Package.swift`(CairnUI target 加 `CairnCore` 为直接依赖)

- [ ] **Step 1:Package.swift 加 CairnUI → CairnCore 依赖**

找到 `.target(name: "CairnUI", dependencies: ["CairnServices", "CairnTerminal"])`,改为:

```swift
.target(name: "CairnUI", dependencies: ["CairnCore", "CairnServices", "CairnTerminal"]),
```

**理由**:StatusBarView 里 `Text("Cairn v\(CairnCore.scaffoldVersion)")` 需要 `import CairnCore`;SwiftPM 要求 import 的模块是**直接**声明的 dep(transitive 依赖不能 import)。spec §3.2 只禁止"UI 直接 import CairnStorage",不禁 CairnCore。

- [ ] **Step 2:重写 CairnApp.swift(scene-level @State + commands)**

```swift
import SwiftUI
import CairnUI

@main
struct CairnApp: App {
    // 折叠状态提升到 Scene 层,让 commands 和 MainWindowView 共享。
    // 避免 NSApp.tryToPerform(toggleSidebar:) 这类 AppKit 桥接的脆弱性。
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector: Bool = true

    var body: some Scene {
        WindowGroup("Cairn") {
            MainWindowView(
                columnVisibility: $columnVisibility,
                showInspector: $showInspector
            )
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            // spec §6.7 快捷键 v1 本 milestone 实装这 2 个(其余 15 个留 M1.4+)
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    columnVisibility =
                        (columnVisibility == .detailOnly) ? .all : .detailOnly
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Toggle Inspector") {
                    showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }
}
```

**设计说明**:
- 折叠状态 Scene-level `@State` → commands 和 MainWindowView 共享 `Binding`
- `⌘⇧T` / `⌘I` 菜单命令直接 toggle state,纯 SwiftUI,无 AppKit
- `CommandGroup(replacing: .sidebar)` 替换系统默认的 "Show/Hide Sidebar" 菜单项组,把我们的两个按钮放在 View 菜单的同一区域
- NavigationSplitView 自动响应 `$columnVisibility` 变化做折叠动画
- `.inspector(isPresented: $showInspector)` 自动响应 bool 变化做显示/隐藏

- [ ] **Step 3:swift build 验证**

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。

**失败排查**:
- `No such module 'CairnCore'`(在 StatusBarView):确认 Step 1 的 Package.swift 修改已保存
- `Cannot find 'CairnToolbarContent'`(在 MainWindowView):确认 T4 Step 1 用的是 `CairnToolbarContent` 不是旧的 `ToolbarContent`

- [ ] **Step 4:T1-T6 合并 commit**

由于 T1-T5 各自写了代码但未 commit(T1 因缺依赖直到 T4 才能编译,T5 仅决策),在此统一 commit:

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
git add Sources/CairnUI/ Sources/CairnApp/CairnApp.swift Package.swift
git commit -m "$(cat <<'EOF'
feat(ui): 主窗口三区布局(MainWindowView + Sidebar/Inspector)

spec §6.1 三区结构落地:
- MainWindowView 用 NavigationSplitView + .inspector() 组装
- SidebarView 空态占位("No workspaces yet",M3.1 起填 Task 列表)
- RightPanelView 3 小节占位(Current Task / Budget / Event Timeline)
- CairnToolbarContent 含 Workspace 选择器 + 通知 / 设置 / Inspector toggle
  (struct 命名加 Cairn 前缀避免与 SwiftUI 的 ToolbarContent 协议歧义)
- StatusBarView 底部 cwd + 引用 CairnCore.scaffoldVersion(避免硬编码)
- TerminalSurface(M0.2 产物)放在 Detail 列,行为不变

键盘快捷键(spec §6.7):v1 本 milestone 实装 ⌘⇧T(Sidebar)+ ⌘I(Inspector);
**纯 SwiftUI**实现:Scene-level @State 管 columnVisibility / showInspector,
Commands 里的 Button.keyboardShortcut 直接 toggle state。避免 NSApp.tryToPerform
(toggleSidebar:) 这类 AppKit 桥接的脆弱性。其余 15 个快捷键留 M1.4 / M3.x。

CairnApp 启动窗口默认尺寸 1280x800;Sidebar 220-400 / ideal 280,
Inspector 280-500 / ideal 360 — 匹配 spec §6.1 的 280px / 360px。

Package.swift 补 CairnUI → CairnCore 依赖(StatusBarView 需要
scaffoldVersion);spec §3.2 允许 UI 直接 import CairnCore,只禁直接
import CairnStorage。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## T7:`MainWindowViewModel` + 单测

**Files:**
- Create: `Sources/CairnUI/MainWindowViewModel.swift`
- Create: `Tests/CairnUITests/MainWindowViewModelTests.swift`
- Modify: `Package.swift`(加 `.testTarget(name: "CairnUITests", dependencies: ["CairnUI"])`)
- Modify: `Sources/CairnUI/MainWindowView.swift`(注入 VM)

- [ ] **Step 1:写 ViewModel(最小化)**

`Sources/CairnUI/MainWindowViewModel.swift`:

```swift
import Foundation
import Observation

/// 主窗口跨视图状态。本 milestone 仅管"折叠初始值"和"当前 workspace"占位。
/// M3.5 Workspace 管理时扩充。
@Observable
@MainActor
public final class MainWindowViewModel {
    /// 当前选中的 workspace id。M1.3 恒 nil,为 M3.5 预留。
    public var currentWorkspaceId: UUID?

    /// 记录用户上次是否把 Sidebar 折叠(M1.5 做布局持久化时再 sync 到
    /// CairnStorage.LayoutStateDAO)。本 milestone 仅作内存态。
    public var sidebarCollapsed: Bool
    public var inspectorCollapsed: Bool

    public init(
        currentWorkspaceId: UUID? = nil,
        sidebarCollapsed: Bool = false,
        inspectorCollapsed: Bool = false
    ) {
        self.currentWorkspaceId = currentWorkspaceId
        self.sidebarCollapsed = sidebarCollapsed
        self.inspectorCollapsed = inspectorCollapsed
    }

    public func toggleSidebar() {
        sidebarCollapsed.toggle()
    }

    public func toggleInspector() {
        inspectorCollapsed.toggle()
    }
}
```

- [ ] **Step 2:加 CairnUITests target**

修改 `Package.swift`,在 `targets:` 数组末尾追加:

```swift
.testTarget(name: "CairnUITests", dependencies: ["CairnUI"]),
```

- [ ] **Step 3:占位测试文件(SPM 要求 target 目录存在)**

```bash
mkdir -p /Users/sorain/xiaomi_projects/AICoding/cairn/Tests/CairnUITests
```

`Tests/CairnUITests/MainWindowViewModelTests.swift`:

```swift
import XCTest
@testable import CairnUI

@MainActor
final class MainWindowViewModelTests: XCTestCase {
    func test_init_defaultsAllCollapsedFalse() {
        let vm = MainWindowViewModel()
        XCTAssertFalse(vm.sidebarCollapsed)
        XCTAssertFalse(vm.inspectorCollapsed)
        XCTAssertNil(vm.currentWorkspaceId)
    }

    func test_toggleSidebar_flipsState() {
        let vm = MainWindowViewModel()
        vm.toggleSidebar()
        XCTAssertTrue(vm.sidebarCollapsed)
        vm.toggleSidebar()
        XCTAssertFalse(vm.sidebarCollapsed)
    }

    func test_toggleInspector_flipsState() {
        let vm = MainWindowViewModel()
        vm.toggleInspector()
        XCTAssertTrue(vm.inspectorCollapsed)
        vm.toggleInspector()
        XCTAssertFalse(vm.inspectorCollapsed)
    }

    func test_customInit_preservesValues() {
        let id = UUID()
        let vm = MainWindowViewModel(
            currentWorkspaceId: id,
            sidebarCollapsed: true,
            inspectorCollapsed: true
        )
        XCTAssertEqual(vm.currentWorkspaceId, id)
        XCTAssertTrue(vm.sidebarCollapsed)
        XCTAssertTrue(vm.inspectorCollapsed)
    }
}
```

- [ ] **Step 4:跑测试**

```bash
swift test --filter MainWindowViewModelTests 2>&1 | tail -5
```

**Expected**:`Executed 4 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnUI/MainWindowViewModel.swift \
        Tests/CairnUITests/ \
        Package.swift
git commit -m "feat(ui): MainWindowViewModel + 4 单测 + CairnUITests target

@Observable @MainActor class 管跨视图状态:currentWorkspaceId 占位
(M3.5 Workspace 管理填充)+ sidebarCollapsed / inspectorCollapsed 内存态
(M1.5 LayoutState 持久化时再 sync DB)。

本 milestone VM 实际不注入到 MainWindowView(折叠状态由 @State 直接管,
见设计决策 #5);VM 存在是为 M3.5+ 扩展预留接口 + 提供可单测的
toggle 逻辑。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T8:CairnCore scaffoldVersion bump

**Files:**
- Modify: `Sources/CairnCore/CairnCore.swift`(`0.2.0-m1.2` → `0.3.0-m1.3`)
- Modify: `Tests/CairnCoreTests/CairnCoreTests.swift`(`m1.2` → `m1.3`,2 处)
- Modify: `Tests/CairnStorageTests/CairnStorageTests.swift`(scaffoldVersion 断言 `0.2.0-m1.2` → `0.3.0-m1.3`)

- [ ] **Step 1:bump + 测试 + commit**

```bash
# 用 Edit 改上述 3 个文件
swift test --filter CairnCoreTests 2>&1 | tail -3
swift test --filter CairnStorageTests 2>&1 | tail -3
```

**Expected**:两组测试全绿。

```bash
git add Sources/CairnCore/CairnCore.swift \
        Tests/CairnCoreTests/CairnCoreTests.swift \
        Tests/CairnStorageTests/CairnStorageTests.swift
git commit -m "chore(core): scaffoldVersion 0.2.0-m1.2 → 0.3.0-m1.3

M1.3 进入'三区布局 UI'阶段。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T9:完整 build + test + 手动肉眼验收

**Files:** 无新增。

- [ ] **Step 1:swift build / swift test 全绿**

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build 2>&1 | tail -3
swift test 2>&1 | grep "Executed" | tail -3
```

**Expected**:
- `Build complete!`
- 合计 **≥ 103 tests**(M1.1 的 54 + M1.2 的 45 + M1.3 新增 4 = 103),0 failures

- [ ] **Step 2:打包 + 启动 + 肉眼观察**

```bash
./scripts/make-app-bundle.sh debug --open
sleep 4
pgrep -fl "Cairn.app/Contents/MacOS/CairnApp" | head -1
```

**Claude 肉眼观察清单**(应当自查,用户 T11 时再次确认):
- [ ] 窗口弹出,默认尺寸约 1280×800
- [ ] 左侧 Sidebar 约 280pt 宽,显示"No workspaces yet"空态
- [ ] 中间 Main Area 显示 Tab Bar("~ (zsh)" 占位)+ Terminal + Status Bar
- [ ] 右侧 Inspector 约 360pt 宽,显示 3 个小节(Current Task / Budget / Event Timeline)每个都有"暂无"文字
- [ ] 顶部 Toolbar 显示 Workspace 下拉 / 通知 / 设置 / Inspector toggle 按钮
- [ ] 按 `⌘⇧T` Sidebar 折叠/展开工作
- [ ] 按 `⌘I` Inspector 折叠/展开工作
- [ ] Terminal 仍可输入 `pwd` + Enter,正常回显

若某项不符,记录为延后项,**不阻塞 T10** —— spec §8.4 说"布局像设计图",小 polish 可留 M4.1 Settings 页做时统一修。

- [ ] **Step 3:清理**

```bash
pkill -f "Cairn.app/Contents/MacOS/CairnApp" 2>/dev/null
```

- [ ] **Step 4:不 commit**(本 task 只验证)

---

## T10:milestone-log + tag + push

**Files:**
- Modify: `docs/milestone-log.md`

- [ ] **Step 1:更新 milestone-log**

用 Edit 工具:

(a) 从"待完成"删除 `- [ ] M1.3 主窗口三区布局`

(b) 在"已完成(逆序)"头部插入:

```markdown
### M1.3 SwiftUI 主窗口三区 + Sidebar/Panel 可折叠

**Completed**: 2026-04-27
**Tag**: `m1-3-done`
**Commits**: 3 个(T6 合并 + T7 + T8)

**Summary**:
- `MainWindowView` 用 `NavigationSplitView` + `.inspector()` 组装 spec §6.1 三区
- Sidebar(280pt)显"No workspaces yet" 空态,Task 列表留 M3.1
- Main Area 保留 M0.2 的 TerminalSurface + 新增 Tab Bar / Status Bar 占位
- Right Panel(Inspector,360pt)3 小节占位:Current Task / Budget / Event Timeline
- Toolbar 有 Workspace 下拉 / 通知 / 设置 / Inspector toggle;`⌘I` 切 Inspector,`⌘⇧T` 切 Sidebar(通过 `CommandGroup(replacing: .sidebar)` 替换系统默认 ⌘⇧S)
- `MainWindowViewModel` @Observable + 4 单测(M3.5+ Workspace 管理扩展预留)
- 全仓库 **≥ 103 tests** 全绿,CairnApp 启动窗口符合 spec §6.1 设计图

**Known limitations**:
- Sidebar / Panel 真实内容(Task 列表 / Budget 详情 / Event 时间线)留 M3.1-M3.3
- 布局折叠状态不持久化(关了 App 再开重置),LayoutStateDAO 接入留 M1.5
- 除 ⌘⇧T / ⌘I 外,spec §6.7 的 15 个快捷键留 M1.4 / M3.x
- 本地化(`String(localized:)`)留 M4.1
```

(c) Commit:

```bash
git add docs/milestone-log.md
git commit -m "docs(log): M1.3 完成记录

3 commits / 4 新单测 / 103+ tests green。
Cairn 从'单终端窗口'进入'带 Chrome 的原生 macOS App'阶段。
M1.4 起在 Main Area 填 Tab Bar 真实功能。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 2:Push + Tag**

```bash
git push origin main 2>&1 | tail -3
git tag -a m1-3-done -m "M1.3 完成:SwiftUI 主窗口三区 + Sidebar/Panel 可折叠"
git push origin m1-3-done 2>&1 | tail -3
```

- [ ] **Step 3:最终验证**

```bash
git tag -l
git status
```

**Expected**:tag 列表含 `m0-1-done / m0-2-done / m1-1-done / m1-2-done / m1-3-done` 共 5 个;working tree clean。

---

## T11:验收清单(用户 + 肉眼验收)

**Owner**: 用户。

Claude 完成 T1-T10 后,在 session 末尾输出:

```markdown
## M1.3 验收清单

**交付物**:
- `Sources/CairnUI/`:MainWindowView / MainWindowViewModel / Sidebar/SidebarView / RightPanel/RightPanelView / Toolbar/ToolbarContent / StatusBar/StatusBarView 共 6 个新 Swift 文件(3 个新子目录)
- `Sources/CairnApp/CairnApp.swift` 更新到 `MainWindowView()` + Scene 级 ⌘⇧T 命令
- CairnCore scaffoldVersion bump 到 `0.3.0-m1.3`
- `Tests/CairnUITests/` 新 target + 4 个 ViewModel 单测
- git tag `m1-3-done` 本地 + 远端

**前置条件**:M1.2 已完成(M1.3 不动 DB,但 Package.swift 共享 GRDB 依赖)。

**验证步骤**:

步骤 1 · 编译
```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build 2>&1 | tail -3
```
期望:`Build complete!`。

步骤 2 · 全测试集绿
```bash
swift test 2>&1 | grep "Executed" | tail -3
```
期望:`Executed 103+ tests, with 0 failures`(M1.1 的 54 + M1.2 的 45 + M1.3 的 4)。

步骤 3 · 新增文件就位
```bash
ls Sources/CairnUI/ Sources/CairnUI/Sidebar/ Sources/CairnUI/RightPanel/ Sources/CairnUI/Toolbar/ Sources/CairnUI/StatusBar/
echo "---"
ls Tests/CairnUITests/
```
期望:各子目录含对应 .swift;Tests/CairnUITests 含 MainWindowViewModelTests.swift。

步骤 4 · **肉眼验收**(本 milestone 的**关键步骤**)

```bash
./scripts/make-app-bundle.sh debug --open
```

打开后**逐项核对**(对照 spec §6.1):

- [ ] 窗口默认尺寸约 1280×800
- [ ] **Sidebar(约 280pt)**:显示"Tasks"标题 + 搜索框 + 居中空态("No workspaces yet" + 副文字)
- [ ] **Main Area**:
  - [ ] 顶部有窄 Tab Bar,含一个"~ (zsh)"占位
  - [ ] 中间是黑色 Terminal,能输入 `pwd`、`ls` 等命令
  - [ ] 底部有窄 Status Bar 显示"~"和"Cairn v0.3.0-m1.3"
- [ ] **Inspector(约 360pt,右)**:3 个圆角卡片,标题分别是 "Current Task" / "Budget" / "Event Timeline",每个下面有灰色"暂无"说明文字
- [ ] **Toolbar 顶部**:Workspace 下拉 / 通知图标 / 设置齿轮 / Inspector toggle 按钮
- [ ] 按 `⌘⇧T`:Sidebar 左滑隐藏 / 再按 ⌘⇧T 滑出
- [ ] 按 `⌘I`:Inspector 右滑隐藏 / 再按 ⌘I 滑出
- [ ] ⌘Q 退出无崩溃

步骤 5 · Git 状态
```bash
git status
git log --oneline -10
git tag -l
```
期望:clean;本地 tag 含 m0-1-done / m0-2-done / m1-1-done / m1-2-done / **m1-3-done** 共 5 个。

**已知限制**:
- Sidebar/Panel 内容是占位,真实内容 M3.x
- 布局折叠状态不持久化,M1.5 做
- 除 ⌘⇧T / ⌘I 外,其他快捷键 M1.4 / M3.x
- 本地化留 M4.1

**下个 M**:**M1.4 多 Tab 管理 + TerminalSurface 封装 + PTY 生命周期**(spec §8.4)。
```

---

## 回归 Self-Review

### 1. Spec 覆盖

| Spec 位置 | 要求 | 对应 Task | 状态 |
|---|---|---|---|
| §6.1 三区布局 | Toolbar / Sidebar / Main / RightPanel / StatusBar | T1-T4 | ✅ |
| §6.2 Sidebar | Task 列表按 Workspace 分组 | T2 | 🟡 空态占位(真实内容 M3.1)|
| §6.3 Main Area | 主区只放终端 | T1(保留 M0.2 的 TerminalSurface)| ✅ |
| §6.5-6.6 Right Panel | Plan/Todo + Budget | T3 | 🟡 3 小节占位 |
| §6.7 快捷键 | v1 共 17 个 | T4 + T6 | 🟡 实装 ⌘⇧T + ⌘I(2 个);15 个延后 |
| §6.9 UI 纪律 | 字符串本地化 / 可访问性 / 空状态 | T2/T3 提供空态 | 🟡 本地化留 M4.1 |
| §8.4 M1.3 验收 | "启动看到 Section 6 布局;手动验收" | T9 肉眼 + T11 用户 | ✅ |

**2 个有意延后**:Sidebar/Panel 真实内容(留 M3.x)+ 其余快捷键(留 M1.4/M3.x)。Spec §8.4 M1.3 验收只要求"布局像设计图",内容级留下个 milestone。

### 2. Placeholder 扫描

- "TBD" / "FIXME" / "implement later" / "appropriate error" — 本 plan 无违规
- "v1.3 占位" / "M3.1 填充" — 是**明确标注的延后点**,不算 plan placeholder

### 3. 类型 / 命名一致性

- `MainWindowView` / `SidebarView` / `RightPanelView` / `ToolbarContent` / `StatusBarView` / `MainWindowViewModel` — 所有命名统一以功能区域 + "View"/"ViewModel"/"ToolbarContent" 后缀
- `CairnToolbarContent` struct 遵循 SwiftUI `ToolbarContent` 协议。初稿用 `struct ToolbarContent: ToolbarContent` 递归歧义,自检时已重命名。所有调用点(MainWindowView Line 134)已同步
- `columnVisibility` / `showInspector` — 名字 SwiftUI 约定,统一
- 版本 `"0.3.0-m1.3"` — CairnCore/Storage/UI 三处一致

### 4. 任务归属明确

T1-T10 Claude 全做;T11 用户肉眼验收。

### 5. 潜在风险

**风险 1(低)**:**SwiftUI `.inspector()` API 兼容性**。
`.inspector(isPresented:)` 是 macOS 14.0+ API。我们平台是 `.macOS(.v14)`,满足。本机 Xcode 26.4 应稳定。

**风险 2(已消除)**:~~`toggleSidebar:` selector 桥接~~。
**自检时重构**:把折叠状态提升到 Scene-level `@State`,commands 里的 `Button.keyboardShortcut` 直接 toggle state,`MainWindowView` 通过 `@Binding` 接收。**纯 SwiftUI,无 AppKit 桥接**。初稿的 `NSApp.keyWindow?.firstResponder?.tryToPerform(toggleSidebar:)` 路径已从 plan 删除。

**风险 3(已消除)**:~~`ToolbarContent` 名字冲突~~。
**自检时重命名**:`struct ToolbarContent: ToolbarContent` 的递归类型歧义确定会报错(同时作为类型名和 conformed 协议名)。重命名为 `CairnToolbarContent`,MainWindowView 引用处同步。

**风险 4(低)**:**`@MainActor` VM 在测试中的使用**。
`MainWindowViewModelTests` 用 `@MainActor` 类级标注,需要测试 class 也 `@MainActor` 或测试方法 async。本 plan 用 class-level `@MainActor`,XCTest 支持。

**风险 5(自检新发现,已消除)**:**CairnUI import CairnCore 需直接 dep**。
SwiftPM 要求 `import` 的模块是直接声明的依赖(不能靠 transitive)。StatusBarView 用 `CairnCore.scaffoldVersion` 需要 CairnUI target 直接依赖 CairnCore。T6 Step 1 加此依赖,spec §3.2 允许(只禁 UI 直接 import CairnStorage)。

### 6. 结论

Plan 完整可执行。M1.3 UI 代码相对 DAO 代码更"视觉",测试覆盖有限,肉眼验收是 spec §8.4 明确要求,不减配。
执行耗时 60-90 分钟,Claude 自验后交给用户肉眼检查。
