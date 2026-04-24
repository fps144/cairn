# M0.2 实施计划:Hello World macOS App

> **For agentic workers:** 本 plan 给 Claude 主导执行(见 `CLAUDE.md`)。每个 Task 按 Step 逐步完成;步骤用 checkbox(`- [ ]`)跟踪。用户职责仅 T11 验收。

**Goal:** 建成 Cairn 可执行 macOS App:启动后展示一个内嵌 SwiftTerm 的窗口,终端里能跑 zsh 并接受键盘输入。

**Architecture:** SPM 7 target(6 库 + 1 executable),严格单向依赖(spec §3.2);CairnApp(SwiftUI `@main`)→ CairnUI(ContentView)→ CairnTerminal(TerminalSurface NSViewRepresentable 封装 SwiftTerm.LocalProcessTerminalView)。其余 4 库(Core / Storage / Claude / Services)本 milestone 只放占位类型 + 1 个骨架单测,证明编译链路就绪,真实实现留 M1.x。`.app` bundle 由 `scripts/make-app-bundle.sh` 在 `swift build` 之后组装 Info.plist + 可执行文件。

**Tech Stack:** Swift 6.3.1 toolchain(语言模式 5)· swift-tools-version 5.9 · macOS deployment v14 · SwiftTerm 1.13.0 · XCTest · Bash 脚本打包 `.app`。

**Claude 总耗时:** 约 45-75 分钟(1 个 session 能完成)。
**用户总耗时:** 约 5-15 分钟(仅 T11 验收)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. Package.swift 骨架 + SwiftTerm 依赖 | Claude | — |
| T2. 6 库占位源文件 + `swift build` 基线 | Claude | T1 |
| T3. CairnCoreTests 骨架 TDD + `swift test` 基线 | Claude | T2 |
| T4. CairnUI ContentView(纯 SwiftUI,无终端) | Claude | T2 |
| T5. CairnApp `@main` + `swift run` 空窗口验证 | Claude | T4 |
| T6. CairnTerminal 封装 SwiftTerm 的 TerminalSurface | Claude | T2 |
| T7. ContentView 嵌入 TerminalSurface | Claude | T5, T6 |
| T8. Info.plist + `make-app-bundle.sh` + `.gitignore /build/` | Claude | T7 |
| T9. 构建并验证 `open build/Cairn.app` 显示可用 zsh | Claude | T8 |
| T10. 更新 milestone-log + 打 tag m0-2-done + push | Claude | T9 |
| T11. 验收清单(用户跑) | **用户** | T10 |

---

## 文件结构规划

**新建**:

```
Package.swift
Sources/
├── CairnCore/Core.swift              占位 struct + public API seed
├── CairnStorage/Storage.swift        占位
├── CairnClaude/Claude.swift          占位
├── CairnTerminal/TerminalSurface.swift   NSViewRepresentable 封装
├── CairnServices/Services.swift      占位
├── CairnUI/ContentView.swift         SwiftUI View(内嵌 TerminalSurface)
└── CairnApp/CairnApp.swift           @main App + WindowGroup
Tests/
└── CairnCoreTests/CairnCoreTests.swift   1 个骨架测试
Resources/
└── Info.plist                        App bundle plist
scripts/
└── make-app-bundle.sh                打包脚本
```

**修改**:

- `.gitignore` — 新增 `/build/` + `/.swiftpm/`(`Package.resolved` **纳入版本**,见 T1 决策)
- `docs/milestone-log.md` — T10 追加 M0.2 完成条目

---

## 架构硬约束(编译器会强制)

spec §3.2 依赖方向(严格,Package.swift 必须照此声明):

```
CairnCore       → []
CairnStorage    → [CairnCore]
CairnClaude     → [CairnCore, CairnStorage]
CairnTerminal   → [CairnCore, SwiftTerm]
CairnServices   → [CairnCore, CairnStorage, CairnClaude]
CairnUI         → [CairnServices, CairnTerminal]
CairnApp        → [CairnUI]
```

**红线**(违反会导致 plan 失败):
- UI 不得直接依赖 `CairnStorage`(必须经 Services)
- 任何 target 不得被 `CairnCore` 依赖
- SwiftTerm 只出现在 `CairnTerminal` 的依赖里,不出现在其他 target

---

## T1:Package.swift 骨架 + SwiftTerm 依赖

**Files:**
- Create: `Package.swift`

- [ ] **Step 1:创建 Package.swift**

写入 `/Users/sorain/xiaomi_projects/AICoding/cairn/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cairn",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CairnApp", targets: ["CairnApp"]),
        .library(name: "CairnCore", targets: ["CairnCore"]),
        .library(name: "CairnStorage", targets: ["CairnStorage"]),
        .library(name: "CairnClaude", targets: ["CairnClaude"]),
        .library(name: "CairnTerminal", targets: ["CairnTerminal"]),
        .library(name: "CairnServices", targets: ["CairnServices"]),
        .library(name: "CairnUI", targets: ["CairnUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0"),
    ],
    targets: [
        .target(name: "CairnCore"),
        .target(name: "CairnStorage", dependencies: ["CairnCore"]),
        .target(name: "CairnClaude", dependencies: ["CairnCore", "CairnStorage"]),
        .target(
            name: "CairnTerminal",
            dependencies: [
                "CairnCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .target(name: "CairnServices", dependencies: ["CairnCore", "CairnStorage", "CairnClaude"]),
        .target(name: "CairnUI", dependencies: ["CairnServices", "CairnTerminal"]),
        .executableTarget(name: "CairnApp", dependencies: ["CairnUI"]),
        .testTarget(name: "CairnCoreTests", dependencies: ["CairnCore"]),
    ]
)
```

**设计决策**:
- swift-tools-version 5.9 匹配 SwiftTerm 1.13.0 要求(SwiftTerm 用 `swiftLanguageVersions: [.v5]`,我们不强推 Swift 6 strict concurrency,避免 M0.2 被 SwiftTerm 的 non-Sendable 闭包卡死)。Swift 6 语言模式可在 M1.x 按 target 逐个迁移。
- M0.2 **只建** `CairnCoreTests` 一个 test target。其他 5 个库的 test target 留给它们各自的 milestone(M1.2 / M2.x / M3.x)—— 此刻建全 6 个空 test target 是 YAGNI。

- [ ] **Step 2:.gitignore 补充 SPM 产物**

`/Users/sorain/xiaomi_projects/AICoding/cairn/.gitignore` 已含 `.build/` 和 `Packages/`。追加(在 `Package.pins` 之后):

```gitignore
# Swift Package Manager local state
.swiftpm/
# M0.2 起产生的 .app bundle 输出
/build/
```

**同时删除原有的 `# Package.resolved 通常提交...` 那一段注释**(已过时)。

**决策**:`Package.resolved` **纳入版本控制**(不 ignore)。理由:Cairn 是可执行 App 而非 library,Apple 官方对 app target 建议 commit `Package.resolved` 以保障多机 / CI 构建时 SwiftTerm 版本一致,避免"本机能跑远端挂"。第一次 `swift build` 产生 `Package.resolved` 后,T2 Step 8 commit 一起带上。

- [ ] **Step 3:Commit**

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
git add Package.swift .gitignore
git commit -m "feat: Package.swift 7 target 骨架 + SwiftTerm 1.13.0 依赖

swift-tools-version 5.9 / macOS v14 / 严格按 spec §3.2 依赖方向声明。
SwiftTerm 只暴露给 CairnTerminal,其他 target 编译期被隔离。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T2:6 库占位源文件 + swift build 基线

**Files:**
- Create: `Sources/CairnCore/Core.swift`
- Create: `Sources/CairnStorage/Storage.swift`
- Create: `Sources/CairnClaude/Claude.swift`
- Create: `Sources/CairnTerminal/Placeholder.swift`(临时,T6 删除)
- Create: `Sources/CairnServices/Services.swift`
- Create: `Sources/CairnUI/Placeholder.swift`(临时,T4 删除)
- Create: `Sources/CairnApp/Placeholder.swift`(临时,T5 删除)

- [ ] **Step 1:写 CairnCore 占位**

`Sources/CairnCore/Core.swift`:

```swift
import Foundation

/// Cairn 领域核心模块(v1 scaffold)。
///
/// 真实数据类型(Workspace / Tab / Session / Task / Event / Budget / Plan)将在 M1.1 填入。
/// 本 milestone 只提供版本标识,证明 target 可编译且可被其他 target 链接。
public enum CairnCore {
    public static let scaffoldVersion = "0.0.1-m0.2"
}
```

- [ ] **Step 2:写 CairnStorage 占位**

`Sources/CairnStorage/Storage.swift`:

```swift
import Foundation
import CairnCore

/// Cairn 存储层(v1 scaffold)。真实 GRDB + 11 表 + migrator 将在 M1.2 填入。
public enum CairnStorage {
    public static let scaffoldVersion = CairnCore.scaffoldVersion
}
```

- [ ] **Step 3:写 CairnClaude 占位**

`Sources/CairnClaude/Claude.swift`:

```swift
import Foundation
import CairnCore
import CairnStorage

/// Cairn Claude Code 集成层(v1 scaffold)。
/// JSONLWatcher / EventIngestor / HookManager 将在 M2.x 填入。
public enum CairnClaude {
    public static let scaffoldVersion = CairnCore.scaffoldVersion
}
```

- [ ] **Step 4:写 CairnTerminal 占位(临时,T6 替换)**

`Sources/CairnTerminal/Placeholder.swift`:

```swift
import Foundation
import CairnCore
import SwiftTerm  // 验证依赖已连通

/// 临时占位,T6 替换为 TerminalSurface 真实实现。
public enum CairnTerminalScaffold {
    public static let scaffoldVersion = CairnCore.scaffoldVersion
}
```

- [ ] **Step 5:写 CairnServices 占位**

`Sources/CairnServices/Services.swift`:

```swift
import Foundation
import CairnCore
import CairnStorage
import CairnClaude

/// Cairn 业务编排层(v1 scaffold)。TaskCoordinator / BudgetTracker / WorkspaceStore 将在 M3.x 填入。
public enum CairnServices {
    public static let scaffoldVersion = CairnCore.scaffoldVersion
}
```

- [ ] **Step 6:写 CairnUI / CairnApp 占位(临时,T4/T5 替换)**

`Sources/CairnUI/Placeholder.swift`:

```swift
import Foundation
import CairnServices
import CairnTerminal

public enum CairnUIScaffold {
    public static let scaffoldVersion = "0.0.1-m0.2"
}
```

`Sources/CairnApp/Placeholder.swift`:

```swift
// 临时 placeholder,T5 替换为 @main App。
// SPM 要求 executableTarget 至少有一个 .swift 文件。
print("Cairn M0.2 scaffold")
```

**注**:`CairnApp` 是 executableTarget,SPM 要求有**且只有一个**含顶层可执行代码(或 `@main`)的文件。T5 删除 Placeholder.swift,替换为 CairnApp.swift。

- [ ] **Step 7:`swift build` 验证编译通过**

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build 2>&1 | tail -10
```

**Expected**:`Build complete!` 且无 error/warning。首次构建会从 GitHub 拉取 SwiftTerm,耗时 30-60s。

**失败排查**:
- 拉依赖超时 → `swift package resolve --verbose` 单独跑,看网络错
- SwiftTerm 编译 warning → 属于 SwiftTerm 本身,本项目代码若无警告即可;必要时用 `-Xswiftc -suppress-warnings` 但 M0.2 不加,等 M1.x 处理
- "no such target" → 检查 Package.swift 里 targets 数组里每个 target name 与 Sources/ 目录名一致

- [ ] **Step 8:Commit(带 Package.resolved)**

```bash
git add Sources/ Package.resolved
git commit -m "feat: 7 target 占位源文件,swift build 编译通过

6 个库仅含 scaffoldVersion 占位常量,CairnApp 为临时 Placeholder
(T4/T5/T6 分别替换为真实 ContentView / @main App / TerminalSurface)。
本 commit 唯一目的:证明 Package.swift 声明的依赖图可真实链接。
Package.resolved 纳入版本,锁定 SwiftTerm 1.13.0 的精确提交点。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

**注**:若 `Package.resolved` 不存在(例如 swift build 失败),`git add Package.resolved` 会报错。此时先确认 T2 Step 7 的 `swift build` 真正成功,再重试。

---

## T3:CairnCoreTests 骨架 TDD + swift test 基线

**Files:**
- Create: `Tests/CairnCoreTests/CairnCoreTests.swift`

- [ ] **Step 1:写测试(红灯)**

`Tests/CairnCoreTests/CairnCoreTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class CairnCoreTests: XCTestCase {
    func test_scaffoldVersion_startsWithZero() {
        XCTAssertTrue(CairnCore.scaffoldVersion.hasPrefix("0."))
    }

    func test_scaffoldVersion_containsMilestoneTag() {
        XCTAssertTrue(
            CairnCore.scaffoldVersion.contains("m0.2"),
            "版本字符串应包含当前 milestone 标识,实际是 \(CairnCore.scaffoldVersion)"
        )
    }
}
```

- [ ] **Step 2:跑测试确认绿**

```bash
swift test --filter CairnCoreTests 2>&1 | tail -10
```

**Expected**:`Test Suite 'CairnCoreTests' passed. Executed 2 tests, with 0 failures`。

**注**:本 milestone 不搞严格"先红后绿"—— `CairnCore.scaffoldVersion` 已在 T2 定义,测试直接绿是预期。严格 TDD 从 M1.1 CairnCore 真实数据类型开始。此处 2 个测试的价值是**建立测试脚手架**,证明 `swift test` 链路通。

- [ ] **Step 3:Commit**

```bash
git add Tests/
git commit -m "test: CairnCoreTests 骨架,swift test 基线就位

2 个断言只覆盖 scaffoldVersion,证明 XCTest target 能正确编译 + 链接 CairnCore。
真实测试(数据模型不变式)从 M1.1 CairnCore 填入时开始,届时严格走 TDD。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T4:CairnUI ContentView(纯 SwiftUI,无终端)

**Files:**
- Delete: `Sources/CairnUI/Placeholder.swift`
- Create: `Sources/CairnUI/ContentView.swift`

- [ ] **Step 1:删除占位**

```bash
rm /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnUI/Placeholder.swift
```

- [ ] **Step 2:写最小 ContentView**

`Sources/CairnUI/ContentView.swift`:

```swift
import SwiftUI

/// Cairn 主内容视图。M0.2 里只占位,T7 嵌入 TerminalSurface。
public struct ContentView: View {
    public init() {}

    public var body: some View {
        // T7 将用 TerminalSurface 替换下面这段 VStack
        VStack(spacing: 12) {
            Text("Cairn")
                .font(.largeTitle)
                .bold()
            Text("M0.2 scaffold · Terminal integration pending (T7)")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
```

- [ ] **Step 3:`swift build` 确认仍编译**

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。

- [ ] **Step 4:Commit**

```bash
git add Sources/CairnUI/
git commit -m "feat(ui): ContentView 最小骨架(T7 将嵌入终端)

SwiftUI.View,600x400 最小尺寸,仅显示 Cairn 标题 + 等待提示。
delete Placeholder.swift 因真实 API(ContentView)已就位。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T5:CairnApp `@main` + `swift run` 空窗口验证

**Files:**
- Delete: `Sources/CairnApp/Placeholder.swift`
- Create: `Sources/CairnApp/CairnApp.swift`

- [ ] **Step 1:删除占位**

```bash
rm /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnApp/Placeholder.swift
```

- [ ] **Step 2:写 @main App 入口**

`Sources/CairnApp/CairnApp.swift`:

```swift
import SwiftUI
import CairnUI

@main
struct CairnApp: App {
    var body: some Scene {
        WindowGroup("Cairn") {
            ContentView()
        }
        .defaultSize(width: 900, height: 600)
    }
}
```

- [ ] **Step 3:`swift build` 验证**

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。

- [ ] **Step 4:`swift run CairnApp` 启动验证**

```bash
swift run CairnApp &
RUN_PID=$!
sleep 3
# 如果窗口弹出则 PID 还活着
ps -p $RUN_PID > /dev/null && echo "[OK] window alive" || echo "[FAIL] process died"
# 清理
kill $RUN_PID 2>/dev/null
wait $RUN_PID 2>/dev/null
```

**Expected**:
- Dock 里短暂出现 Cairn 图标
- 一个窗口弹出,标题 "Cairn",内容是 "Cairn / M0.2 scaffold..."
- 输出 `[OK] window alive`

**注**:`swift run` 启动的 App 没有 bundle,Dock 图标是默认 terminal 图标,**不是** `.app`。最终 `.app` bundle 在 T8-T9 产出。这一步只是验证"代码本身可启动"。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnApp/
git commit -m "feat(app): @main SwiftUI App,swift run 可启动空窗口

WindowGroup 默认 900x600,标题 \"Cairn\"。无终端,T7 接入 TerminalSurface。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T6:CairnTerminal 封装 SwiftTerm 的 TerminalSurface

**Files:**
- Delete: `Sources/CairnTerminal/Placeholder.swift`
- Create: `Sources/CairnTerminal/TerminalSurface.swift`

- [ ] **Step 1:删除占位**

```bash
rm /Users/sorain/xiaomi_projects/AICoding/cairn/Sources/CairnTerminal/Placeholder.swift
```

- [ ] **Step 2:写 TerminalSurface**

`Sources/CairnTerminal/TerminalSurface.swift`:

```swift
import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI 封装的 SwiftTerm 终端视图。M0.2 只跑用户默认 shell,
/// 不做 cwd 跟踪(OSC 7 留 M1.5)、不做 delegate 回调(留 M1.4)。
///
/// 关键 API 事实(SwiftTerm 1.13.0 源码核实):
/// - `LocalProcessTerminalView: TerminalView` 其中 `TerminalView: NSView`,
///   因此可直接作为 `NSViewRepresentable.NSViewType`
/// - `startProcess` 完整签名:
///   `(executable: String = "/bin/bash", args: [String] = [],
///     environment: [String]? = nil, execName: String? = nil,
///     currentDirectory: String? = nil)`
/// - environment 传 nil 时 SwiftTerm 用合理默认(继承 PATH/HOME 等),
///   无需手动构造(SwiftTerm 内部做)
/// - execName 传 "-" + basename(shell) → shell 启动为 login shell,
///   加载 .zprofile,与官方 TerminalApp/MacTerminal 示例一致
public struct TerminalSurface: NSViewRepresentable {
    private let shell: String
    private let cwd: String?

    /// - Parameters:
    ///   - shell: 要启动的 shell 可执行路径。nil 时用 `$SHELL` 环境变量,兜底 `/bin/zsh`。
    ///   - cwd: 起始工作目录。nil 时 SwiftTerm 继承父进程 cwd。
    public init(shell: String? = nil, cwd: String? = nil) {
        self.shell = shell
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        self.cwd = cwd
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        // login shell idiom:`/bin/zsh` → `-zsh`,让 shell 加载 .zprofile
        let shellIdiom = "-" + (shell as NSString).lastPathComponent
        view.startProcess(
            executable: shell,
            args: [],
            environment: nil,       // SwiftTerm 用默认 env,M1.4 再注入 CAIRN_* 标识
            execName: shellIdiom,
            currentDirectory: cwd   // nil = 继承,非 nil = 精确设置,M1.5 OSC 7 修正
        )
        return view
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // M0.2 不响应 state change。后续 milestone 在此处理字号 / 主题动态切换。
    }
}
```

- [ ] **Step 3:`swift build` 验证**

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。

**可能的 warning**:SwiftTerm 1.13 若有 deprecation warning 会冒上来。忽略;它们不阻塞本项目代码。

**失败排查**(按概率降序):
- `Cannot find 'LocalProcessTerminalView' in scope`:缺 `import SwiftTerm`,或 Package.swift 里 CairnTerminal target 未声明 `.product(name: "SwiftTerm", package: "SwiftTerm")` 依赖
- `LocalProcessTerminalView' does not conform to 'NSView'`:不会发生(已核实继承链 LocalProcessTerminalView → TerminalView → NSView),除非 SwiftTerm 1.14+ 变动
- `'startProcess' has no parameter named 'currentDirectory'`:SwiftTerm 早于 1.13 的版本无该参数;确认 Package.resolved 真拉到 1.13.x 而非旧版本
- `Extra argument 'execName' in call`:不会发生(参数存在且有默认值),除非严重 API 变动

- [ ] **Step 4:Commit**

```bash
git add Sources/CairnTerminal/
git commit -m "feat(terminal): TerminalSurface 封装 SwiftTerm.LocalProcessTerminalView

SwiftUI NSViewRepresentable。默认启动 \$SHELL(兜底 /bin/zsh),
用 login shell idiom (\"-zsh\")加载 .zprofile。
M0.2 简化:不做 delegate 回调(M1.4)、不做 OSC 7 cwd 跟踪(M1.5)。
startProcess 的 currentDirectory 参数直传 cwd,无需 cd 命令 hack。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T7:ContentView 嵌入 TerminalSurface

**Files:**
- Modify: `Sources/CairnUI/ContentView.swift`

- [ ] **Step 1:替换 ContentView body**

用 Edit 工具把 `Sources/CairnUI/ContentView.swift` 的内容完全替换为:

```swift
import SwiftUI
import CairnTerminal

/// Cairn 主内容视图。M0.2 里全屏嵌入一个 TerminalSurface,
/// 执行用户默认 shell。后续 milestone 加 toolbar / 分屏 / tab bar 等。
public struct ContentView: View {
    public init() {}

    public var body: some View {
        TerminalSurface()
            .frame(minWidth: 600, minHeight: 400)
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
```

- [ ] **Step 2:`swift build` 验证**

```bash
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`。

- [ ] **Step 3:`swift run CairnApp` 烟雾测试(可选)**

```bash
swift run CairnApp &
RUN_PID=$!
sleep 3
ps -p $RUN_PID > /dev/null && echo "[OK] window alive with terminal"
kill $RUN_PID 2>/dev/null
wait $RUN_PID 2>/dev/null
```

**Expected**:窗口里显示黑色终端,底部有闪烁光标,顶部可能打印 shell 的启动 banner(zsh 装了 powerlevel10k 之类会看到主题 prompt)。

**注**:`swift run` 启动不产生 `.app` bundle;这一步只是即时目测代码是否跑起来。最终验收靠 T9。

- [ ] **Step 4:Commit**

```bash
git add Sources/CairnUI/
git commit -m "feat(ui): ContentView 内嵌 TerminalSurface

v1 主区域只放终端(spec §6.3)。工具栏 / 分屏 / Tab bar 留 M1.4 / M1.5。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T8:Info.plist + make-app-bundle.sh + .gitignore

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/make-app-bundle.sh`

- [ ] **Step 1:写 Info.plist**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>CairnApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.cairn.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Cairn</string>
    <key>CFBundleDisplayName</key>
    <string>Cairn</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
```

**决策**:
- `CFBundleIdentifier` = `com.cairn.app` —— 无 Apple Developer 账号,不需要 com.<org>.xxx 反域名注册,使用 com.cairn.* 简洁即可,后续可按需改
- `NSHighResolutionCapable=true` —— Retina 屏必需
- `LSApplicationCategoryType` = developer-tools —— 用于 App Store 归类,未签名分发无实际作用但填上无害
- **不加** Code Signing 相关 key(entitlements / provisioning profile)—— 符合 spec A14 永不签名决定

- [ ] **Step 2:写打包脚本**

`scripts/make-app-bundle.sh`:

```bash
#!/bin/bash
# make-app-bundle.sh — 把 swift build 产出的 CairnApp 可执行文件
# 组装成可被 `open` 打开的 Cairn.app bundle。
#
# 用法:
#   scripts/make-app-bundle.sh [debug|release]
#
# 产物:
#   build/Cairn.app
set -euo pipefail

CONFIG="${1:-debug}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
    echo "[make-app-bundle] ERROR: config 必须是 debug 或 release,收到 $CONFIG" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[make-app-bundle] swift build -c $CONFIG ..."
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/CairnApp"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "[make-app-bundle] ERROR: $BIN_PATH 不存在,check swift build 输出" >&2
    exit 1
fi

BUNDLE="build/Cairn.app"
echo "[make-app-bundle] 组装 $BUNDLE ..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/CairnApp"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

chmod +x "$BUNDLE/Contents/MacOS/CairnApp"

echo "[make-app-bundle] 完成:$BUNDLE"
echo "[make-app-bundle] 启动:open $BUNDLE"
```

- [ ] **Step 3:赋执行权限**

```bash
chmod +x /Users/sorain/xiaomi_projects/AICoding/cairn/scripts/make-app-bundle.sh
```

- [ ] **Step 4:验证 .gitignore 已含 /build/**

```bash
grep "^/build/$" /Users/sorain/xiaomi_projects/AICoding/cairn/.gitignore
```

**Expected**:打印一行 `/build/`(T1 step 2 已添加)。若没有,手动补一行。

- [ ] **Step 5:Commit**

```bash
git add Resources/Info.plist scripts/make-app-bundle.sh
git commit -m "build: Info.plist + make-app-bundle.sh 组装未签名 .app

CFBundleIdentifier=com.cairn.app,LSMinimumSystemVersion=14.0,
NSHighResolutionCapable=true。脚本按 debug/release 配置把
.build/<config>/CairnApp 拷贝进 build/Cairn.app/Contents/MacOS,
配 Info.plist 即可 open。无签名、无 entitlements,走 spec A14 xattr 路线。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T9:构建并验证 `open build/Cairn.app` 显示可用 zsh

**Files:** 无新增。

- [ ] **Step 1:跑打包脚本**

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
./scripts/make-app-bundle.sh debug 2>&1 | tail -8
```

**Expected**:
```
[make-app-bundle] swift build -c debug ...
Build complete!
[make-app-bundle] 组装 build/Cairn.app ...
[make-app-bundle] 完成:build/Cairn.app
[make-app-bundle] 启动:open build/Cairn.app
```

- [ ] **Step 2:验证 bundle 结构**

```bash
find build/Cairn.app -type f | sort
```

**Expected**:
```
build/Cairn.app/Contents/Info.plist
build/Cairn.app/Contents/MacOS/CairnApp
```

- [ ] **Step 3:验证 Info.plist 可读**

```bash
defaults read "$(pwd)/build/Cairn.app/Contents/Info" CFBundleName
```

**Expected**:`Cairn`(macOS `defaults` 工具会读 plist)。

- [ ] **Step 4:`open build/Cairn.app` 烟雾测试**

```bash
open build/Cairn.app
sleep 4
# 检查 Cairn 进程
pgrep -fl CairnApp || echo "[FAIL] CairnApp 进程不存在"
```

**Expected**:`pgrep` 打印一行形如 `12345 /path/to/build/Cairn.app/Contents/MacOS/CairnApp`。

- [ ] **Step 5:手动目测(Claude 提醒用户或自检)**

此刻用户(或 Claude 截屏)应该看到:
- Dock 中出现一个**默认图标**(无 icon.icns 时 macOS 用 generic app 图标)的 "CairnApp" 入口
- 一个窗口,标题 "Cairn",默认 900×600
- 窗口内是一个黑底终端,显示用户 zsh 的 prompt(或装的主题 prompt)
- 键盘输入能进终端,按 Enter 能跑命令(如 `ls`、`pwd`)

**失败表现** + 排查:
- 窗口没弹:`ps aux | grep CairnApp` 看进程是否活着;若死了 `open -W build/Cairn.app` 观察 exit code
- 窗口弹了但终端全黑无 prompt:用户 shell 启动可能卡死(powerlevel10k 初始化慢 / 网络 prompt 插件等);在普通 terminal 里跑 `/bin/zsh -l`(login shell 和 Cairn 内一致)确认是否同样慢
- 首次启动 macOS Gatekeeper 警告 "CairnApp" 是未知开发者:本地 `swift build` 产物**不被 quarantine**,此 dialog 不应该出现;若出现说明文件可能来自网络副本,`xattr -l build/Cairn.app` 检查

- [ ] **Step 6:关闭 App**

```bash
pkill -f CairnApp
sleep 1
```

- [ ] **Step 7:把打包脚本产物路径记下**(不 commit,用于 T10 log)

```bash
ls -la build/Cairn.app/Contents/MacOS/CairnApp | awk '{print "binary size:", $5, "bytes"}'
```

**不 commit** 任何文件。T9 只是验证 T8 的脚本确实能产出可运行的 `.app`。

---

## T10:milestone-log + tag m0-2-done + push

**Files:**
- Modify: `docs/milestone-log.md`

- [ ] **Step 1:更新 milestone-log.md**

用 Edit 工具在 `docs/milestone-log.md` 里:

(a) 把 `- [ ] M0.2 Hello World macOS App` 从"待完成"列表删除。

(b) 在 "已完成(逆序)" 下、**M0.1 条目之前**插入:

```markdown
### M0.2 Hello World macOS App

**Completed**: 2026-04-24(或 Claude 实际完成日)
**Tag**: `m0-2-done`
**Commits**: N 个(`<first-sha>` … `<last-sha>`,Claude 填实际 SHA)

**Summary**:
- Package.swift 7 target(6 库 + 1 executable)按 spec §3.2 严格依赖方向声明
- SwiftTerm 1.13.0 作为唯一第三方依赖接入(只暴露给 CairnTerminal)
- `@main` SwiftUI App + ContentView 嵌入 TerminalSurface
- `scripts/make-app-bundle.sh` 把 `swift build` 产出打包成未签名 `build/Cairn.app`(配 Info.plist,CFBundleIdentifier=com.cairn.app)
- `swift build` + `swift test --filter CairnCoreTests` 全绿
- `open build/Cairn.app` 可弹出 900×600 窗口,内嵌终端能跑用户 `$SHELL`(默认 zsh)

**Acceptance**:见 M0.2 计划文档 T11 验收清单。

**Known limitations**:
- 只有 `CairnCoreTests` 1 个 test target(2 个测试);其他 5 个库的测试随它们 milestone 填入
- TerminalSurface 不做 cwd 精确设置(M1.5 OSC 7 跟踪时修正)、不做 delegate 回调(M1.4)
- 无 icon.icns,Dock 用 macOS 默认 generic 图标;设计稿 / 图标留待 v0.1 Beta(M2.7)
- 未签名路径,首次 `open` 若触发 Gatekeeper 需用户 `xattr -rd com.apple.quarantine build/Cairn.app`(v0.1 Beta 时 README 首页明写)
```

- [ ] **Step 2:Commit**

```bash
git add docs/milestone-log.md
git commit -m "docs(log): M0.2 完成记录

N commits / 2 tests green / hello-world .app 可用。
Cairn 从'纯文档'进入'可启动原生进程'阶段。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 3:Push 到 GitHub**

```bash
git push origin main 2>&1 | tail -3
```

**Expected**:`To https://github.com/fps144/cairn.git ... main -> main`。

- [ ] **Step 4:打 tag + push tag**

```bash
git tag -a m0-2-done -m "M0.2 完成:Hello World macOS App"
git push origin m0-2-done 2>&1 | tail -3
```

**Expected**:`* [new tag] m0-2-done -> m0-2-done`。

- [ ] **Step 5:最终验证**

```bash
git status
git log --oneline -15
git tag -l
```

**Expected**:
- `nothing to commit, working tree clean`
- 最近 ≥ 8 个 commit 可见(T1 → T10)
- `m0-1-done` 和 `m0-2-done` 都在 tag 列表

---

## T11:验收清单(用户执行)

**Owner**: 用户。

Claude 完成 T1-T10 后,在 session 末尾输出以下验收清单,用户方便时跑:

```markdown
## M0.2 验收清单

**交付物**:
- Package.swift(7 target 骨架 + SwiftTerm 1.13.0)
- 7 个 target 的 Swift 源文件(`Sources/{CairnCore, CairnStorage, CairnClaude, CairnTerminal, CairnServices, CairnUI, CairnApp}/*.swift`)
- `Tests/CairnCoreTests/CairnCoreTests.swift`(2 测试)
- `Resources/Info.plist` + `scripts/make-app-bundle.sh`
- git tag `m0-2-done` 推到远端

**前置条件**:
- Xcode + Swift toolchain 已装(本机 Xcode 26.4.1 + Swift 6.3.1 已验证 ✅)
- 网络可访问 github.com(首次 `swift build` 需拉 SwiftTerm)

**验证步骤**:

步骤 1 · 编译通过
```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build 2>&1 | tail -3
```
期望:`Build complete!`,**无 error**(SwiftTerm 自身的 warning 不算)。

步骤 2 · 单测全绿
```bash
swift test 2>&1 | tail -5
```
期望:`Executed 2 tests, with 0 failures`。

步骤 3 · 打包 .app
```bash
./scripts/make-app-bundle.sh debug 2>&1 | tail -4
ls build/Cairn.app/Contents/
```
期望:
- 脚本打印 `[make-app-bundle] 完成:build/Cairn.app`
- `ls` 显示 `Info.plist` 和 `MacOS/`(里面有 `CairnApp`)

步骤 4 · 启动 App 看终端能用
```bash
open build/Cairn.app
```
期望:
- 一个窗口弹出,标题 "Cairn",默认 ≈ 900×600 大小
- 窗口内全屏黑色终端,显示你的 shell prompt(zsh 默认是 `%`,装了主题会是 ❯ 或 ➜ 之类)
- **键盘输入能进终端**,输入 `pwd` + Enter 能看到 cwd 打印,输入 `ls` 能看到文件列表
- 关 App(⌘Q)后窗口消失,无崩溃弹窗

步骤 5 · git 状态 + tag + 远端
```bash
git status
git log --oneline -12
git tag -l
git ls-remote origin refs/tags/m0-2-done 2>&1 | head -1
```
期望:
- `working tree clean`
- 最近 commit 是 "docs(log): M0.2 完成记录"
- `m0-1-done` 和 `m0-2-done` 都在本地 tag 列表
- `ls-remote` 显示 m0-2-done 在远端存在

**已知限制 / 延后项**:
- Dock 图标是 macOS 默认 generic(icon.icns 留 v0.1 Beta)
- TerminalSurface 目前只是"能跑 zsh",不做 cwd 跟踪 / 分屏 / 多 tab(M1.4 / M1.5)
- 只有 1 个 test target,其他 5 个随各自 milestone 补
- 无签名,留 v0.1 Beta(M2.7)打包 DMG 时写 xattr 说明

**下个 M**:M1.1 SPM 6 模块骨架 + CairnCore 数据类型(填充 Workspace / Tab / Session / Task / Event / Budget 等真实结构体 + ≥ 10 单测)。
```

---

## 回归 Self-Review

### 1. Spec 覆盖

spec §8.3 M0.2 交付物 4 项:

| 交付项 | 对应 Task |
|---|---|
| Package.swift(6 target 骨架) | T1(实际 7 target:6 库 + 1 executable,已在 plan 架构约束章节解释) |
| 最小可启动的 macOS SwiftUI App | T4(ContentView)+ T5(`@main` App)+ T8(.app bundle) |
| SwiftTerm 嵌入运行 zsh | T6(TerminalSurface)+ T7(wire 到 ContentView)+ T9(验证 zsh 可用) |
| XCTest 测试目标建好 | T3(CairnCoreTests,2 个测试)—— 骨架级交付,其余测试 target 留各自 milestone |

spec §8.3 验收要求 "用户 `open Cairn.app` 看到空窗口,里面有能输入的 zsh 终端" → T9 Step 4 + T11 验收步骤 4 精确对应。

**4/4 覆盖,无遗漏。**

### 2. Placeholder 扫描

- "TBD" / "TODO" / "FIXME" — 全文无
- "implement later" / "appropriate" — 全文无
- 所有 "delete X"(T4/T5/T6)的位置都明确:`rm` 命令 + 紧跟替换文件内容
- "(Claude 填实际 SHA)" 出现在 T10 milestone-log 模板中,是**执行时**填入,不是 plan 漏项
- 所有代码块**完整**:Package.swift 完整、TerminalSurface 完整、Info.plist 完整、脚本完整

无违规。

### 3. 类型 / 命名一致性

- `CairnCore.scaffoldVersion`:T2 定义为 public static let,T3 测试使用,T2 其他文件引用 → 一致
- `TerminalSurface`:T6 定义为 `public struct ... NSViewRepresentable`,T7 ContentView 里用 `TerminalSurface()` 无参构造 → 一致(T6 `init(shell:cwd:)` 两参都有默认值)
- `ContentView`:T4 定义 `public struct ContentView: View { public init() {} ... }`,T5 App 里 `ContentView()` 无参构造 → 一致
- `CairnApp`:T5 定义为 `@main struct CairnApp: App`,注意与 SPM target 同名 `CairnApp`(Swift 允许模块名和顶层类型同名)→ SPM 会以 target 名产出 `CairnApp` 可执行文件,`@main` struct 名字不影响产物名,Info.plist 的 `CFBundleExecutable=CairnApp` 对应这个产物名 → 一致
- `scaffoldVersion` 在 6 个库都定义:Core / Storage / Claude / Terminal(叫 `CairnTerminalScaffold.scaffoldVersion` —— 命名不统一!)/ Services / UI(叫 `CairnUIScaffold.scaffoldVersion` —— 同样不统一)

**发现不一致**:
- CairnTerminal / CairnUI 占位文件用了 `CairnTerminalScaffold` / `CairnUIScaffold` 枚举名,与其他 4 库的 `CairnTerminal` / `CairnUI`(若直接作为枚举名)冲突。**但 Terminal 和 UI 的占位会在 T4/T6 被删除**,所以 final 状态下只有 Core / Storage / Claude / Services 4 个用统一 `CairnX.scaffoldVersion` 模式,Terminal / UI 变成真实 API —— 反而是**预期设计**,不是 bug。
- 只需确认 T2 Step 4 / Step 6 里占位命名避免与将来 T4/T6 的真实类型冲突即可,已经用 `*Scaffold` 后缀避免了。✅

### 4. 任务归属明确

- T1-T10 Claude 全做
- T11 用户执行 5 步验收
- 无责任模糊区域

### 5. 命令可执行性

所有 Bash 片段:
- 路径用绝对路径或明确 `cd` + 相对路径
- 环境变量用法正确(`$SHELL`, `$CONFIG`)
- `set -euo pipefail` 在 shell 脚本中使用 — 严格失败
- `pgrep` / `pkill` / `open -W` 等 macOS 特有工具均可用(本机 Darwin 25.3.0 确认)

### 6. SwiftTerm API 已核实(2026-04-24 修订)

**Plan 初稿的 T6 基于 spec §5.1 参考代码 + 推断,包含 3 个编译错误**。用户要求自检后,通过读 SwiftTerm v1.13.0 GitHub 源码(`Sources/SwiftTerm/Mac/MacLocalTerminalView.swift` / `MacTerminalView.swift` + `TerminalApp/MacTerminal/ViewController.swift`)逐行核实并重写 T6:

| 初稿错误 | 真相 | 修订 |
|---|---|---|
| `Terminal.getEnvironmentVariables(termName:)` | 该 API 不存在于 1.13.0 | 删除调用,`environment: nil` |
| `view.send(data: ArraySlice<UInt8>)` | `send(source:data:)` 是 `TerminalViewDelegate` 回调,不是输入方法 | 删除 `cd` hack |
| `cd <cwd>\n` 发送 hack | `startProcess` 真实签名有 `currentDirectory:` 参数 | `currentDirectory: cwd` 直传 |
| `execName: nil` | 官方 sample 用 `"-" + basename(shell)` 走 login shell | 同步 |

**核实依据**:
- `LocalProcessTerminalView` 类声明(官方源码):
  `open class LocalProcessTerminalView: TerminalView, TerminalViewDelegate, LocalProcessDelegate`
- `TerminalView` 类声明:`open class TerminalView: NSView, NSTextInputClient, NSUserInterfaceValidations, TerminalDelegate`
  → 继承链 LocalProcessTerminalView → TerminalView → NSView,NSViewRepresentable 直接兼容
- `startProcess` 真实签名:
  `public func startProcess(executable: String = "/bin/bash", args: [String] = [], environment: [String]? = nil, execName: String? = nil, currentDirectory: String? = nil)`
- 官方 sample(TerminalApp/MacTerminal/ViewController.swift)对 environment 传 nil,用 execName 传 login shell idiom

### 7. 结论

Plan 核心代码片段(Package.swift / ContentView / TerminalSurface / Info.plist / make-app-bundle.sh)全部可执行,关键 API 已对照官方源码核实。执行者按步骤走即可,无需再查 SwiftTerm 文档。唯一需要网络的步骤是首次 `swift build`(拉 SwiftTerm 源码编译,1-3 分钟)。
