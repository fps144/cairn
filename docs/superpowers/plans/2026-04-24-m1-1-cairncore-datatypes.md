# M1.1 实施计划:CairnCore 数据类型

> **For agentic workers:** 本 plan 给 Claude 主导执行(见 `CLAUDE.md`)。每个 Task 按 Step 逐步完成;步骤用 checkbox(`- [ ]`)跟踪。用户职责仅 T14 验收。

**Goal:** 把 CairnCore 从 M0.2 的 `scaffoldVersion` 占位升级为完整领域模型 —— 7 个实体 struct、5 个状态 enum、EventType(封闭 12 种)、ToolCategory(开放集)、≥ 15 个单元测试全绿。

**Architecture:** CairnCore 是**纯领域模型层**,零外部依赖(只用 Foundation),所有类型值语义,Equatable/Hashable 按 id,Codable 支持 JSON round-trip,Sendable 为 Swift 6 迁移预留。v1 "Task has-many Sessions 默认 1:1" 语义通过 `CairnTask.sessionIds: [UUID]` 表达;多对多 join table 留 M1.2 SQLite schema 处理。

**Tech Stack:** Swift 6.3.1 toolchain(语言模式 5)· swift-tools-version 5.9 · Foundation.UUID / Foundation.Date · 无第三方依赖。

**Claude 总耗时:** 约 90-120 分钟(1 个 session 能完成)。
**用户总耗时:** 约 5-10 分钟(仅 T14 验收)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. scaffoldVersion bump + CairnCore 模块命名约定 | Claude | — |
| T2. Workspace 实体 + Codable 测试 | Claude | T1 |
| T3. Tab 实体 + TabState 枚举 + 测试 | Claude | T1 |
| T4. Session 实体 + SessionState 枚举(5 态)+ 测试 | Claude | T1 |
| T5. CairnTask 实体 + TaskStatus 枚举(4 态)+ 测试 | Claude | T1 |
| T6. EventType 枚举(封闭 12 种)+ 测试 | Claude | T1 |
| T7. ToolCategory 开放集 + toolName→category 映射表 + 测试 | Claude | T1 |
| T8. Event 实体(含 type/category/tool 字段)+ 测试 | Claude | T6, T7 |
| T9. Budget 实体 + BudgetState(4 态)+ 状态转换逻辑 + 测试 | Claude | T5 |
| T10. Plan 实体 + PlanStep/PlanSource/PlanStepStatus/PlanStepPriority + 测试 | Claude | T5 |
| T11. ISO-8601 Date 共享编解码策略 + 跨实体 JSON round-trip 集成测试 | Claude | T2-T10 |
| T12. `swift build` + `swift test` 全绿 + 覆盖率自查 | Claude | T11 |
| T13. milestone-log + tag `m1-1-done` + push | Claude | T12 |
| T14. 验收清单(用户跑) | **用户** | T13 |

---

## 文件结构规划

**新建**:

```
Sources/CairnCore/
├── CairnCore.swift               (重命名自 Core.swift,保留 scaffoldVersion)
├── Workspace.swift               (T2)
├── Tab.swift                     (+ TabState,T3)
├── Session.swift                 (+ SessionState,T4)
├── CairnTask.swift               (+ TaskStatus,T5,**注意 Swift.Task 命名冲突,见设计决策 #4**)
├── EventType.swift               (封闭 12 种 enum,T6)
├── ToolCategory.swift            (开放集 struct + 查表,T7)
├── Event.swift                   (T8,组装 EventType/ToolCategory)
├── Budget.swift                  (+ BudgetState + 状态转换,T9)
├── Plan.swift                    (+ PlanStep/PlanSource/PlanStepStatus/PlanStepPriority,T10)
└── ISO8601Coding.swift           (共享编解码策略,T11)
Tests/CairnCoreTests/
├── CairnCoreTests.swift          (已有,T1 更新版本断言)
├── WorkspaceTests.swift          (T2)
├── TabTests.swift                (T3)
├── SessionTests.swift            (T4)
├── CairnTaskTests.swift          (T5)
├── EventTypeTests.swift          (T6)
├── ToolCategoryTests.swift       (T7)
├── EventTests.swift              (T8)
├── BudgetTests.swift             (T9)
├── PlanTests.swift               (T10)
└── JSONRoundTripTests.swift      (跨实体 codable,T11)
```

**删除**:`Sources/CairnCore/Core.swift`(T1 重命名)

**修改**:
- `docs/milestone-log.md` — T13 追加 M1.1 完成条目

---

## 设计决策(pinned,Plan 执行中不重新讨论)

| # | 决策 | 选择 | 理由 |
|---|---|---|---|
| 1 | ID 类型 | `Foundation.UUID` | Swift 原生,值语义,`.uuidString` 可直接存 SQLite TEXT 列(M1.2 用) |
| 2 | 时间戳 | `Foundation.Date` + ISO-8601 Codable 策略 | 跨 JSONL / SQLite / API 互通;ISO-8601 是 spec §7.2 要求 |
| 3 | 路径 | `String`(期望绝对路径) | 简单;不用 Foundation.URL(避免 file:// 前缀歧义) |
| 4 | **CairnTask 命名** | **`CairnTask`(不是 `Task`)** | Swift 标准库 `Task`(结构化并发)会命名冲突;`CairnTask` 避免歧义,上下文中无需 `CairnCore.Task` 显式限定 |
| 5 | Enum 协议 | `String` raw value + `Codable` + `Sendable` + `CaseIterable` | String raw value 便于 SQLite 列存 + JSON 互通;CaseIterable 便于 UI 遍历 |
| 6 | Struct 协议 | `Equatable`(id 比较)+ `Hashable`(id hash)+ `Codable` + `Sendable` | v1 身份由 id 唯一确定,业务字段变化不破坏"同一实体"语义 |
| 7 | ToolCategory 数据结构 | `struct ToolCategory: RawRepresentable, Hashable, Codable, Sendable` + 静态常量(已知 12 种)+ `from(toolName:)` 查表 | spec §2.3 明确"category 开放集,按 toolName 查表";Swift 无"开放 enum",用 struct 裹 String 是标准模式 |
| 8 | Event.rawPayloadJson | `String?`(持有原始 JSON 字符串,不解析) | 懒加载避开早期解析;spec §2.6 "完整数据,懒加载" |

**ToolCategory 静态映射表**(本 plan 锁定,与 spec §2.3 一致):

| toolName(Claude Code 原始)| ToolCategory |
|---|---|
| `Bash` | `.shell` |
| `Read`, `NotebookRead` | `.fileRead` |
| `Write`, `Edit`, `NotebookEdit` | `.fileWrite` |
| `Glob`, `Grep` | `.fileSearch` |
| `WebFetch`, `WebSearch` | `.webFetch` |
| `mcp__*__*`(前缀匹配) | `.mcpCall` |
| `Agent`, `Task`(Claude Code 的 agent 工具)| `.subagent` |
| `TodoWrite` | `.todo` |
| `EnterPlanMode`, `ExitPlanMode` | `.planMgmt` |
| `AskUserQuestion` | `.askUser` |
| `mcp__ide__*`(前缀匹配) | `.ide` |
| 其他未命中 | `.other` |

**注**:M0.1 probe 发现 `TaskCreate / TaskUpdate / TaskList / TaskGet / TaskOutput / TaskStop` 等 `Task*` 系列(不是 spec §2.3 原列的 Agent 工具的 `Task`)和 `Skill`、`ListMcpResourcesTool` 也出现。M1.1 只实现上表的查表,`Task*` 系列按 `startsWith("Task") && != "Task"` 判定归到 `.todo`,`Skill` 归 `.other`,`ListMcpResourcesTool` 归 `.mcpCall`(前缀 `mcp__` 的 variant)。这些扩展在 T7 的 `ToolCategory.from(toolName:)` 里实装。

---

## 架构硬约束(不得违反)

- CairnCore **零外部依赖**(只能 `import Foundation`)
- 所有 public 类型 `public`;所有 init `public`;所有 stored property `public let` 或 `public var`(按语义)
- 不得引入业务逻辑 / IO / 异步操作 / 并发原语 —— CairnCore 是纯数据层
- Budget 的状态转换函数**必须是纯函数**(不可变更 self,返回新 state),符合 spec §3 分层要求(Core 无状态)

---

## T1:scaffoldVersion bump + CairnCore 模块命名约定

**Files:**
- Rename: `Sources/CairnCore/Core.swift` → `Sources/CairnCore/CairnCore.swift`
- Modify: `Sources/CairnCore/CairnCore.swift`(版本号 0.0.1-m0.2 → 0.1.0-m1.1)
- Modify: `Tests/CairnCoreTests/CairnCoreTests.swift`(断言 `"m1.1"` 替代 `"m0.2"`)

- [ ] **Step 1:用 git mv 保留重命名历史**

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
git mv Sources/CairnCore/Core.swift Sources/CairnCore/CairnCore.swift
```

- [ ] **Step 2:编辑 CairnCore.swift 内容**

用 Edit 工具把 `Sources/CairnCore/CairnCore.swift` 内容整体替换为:

```swift
import Foundation

/// Cairn 领域核心模块。零外部依赖,纯值语义。
///
/// 本模块包含 7 个核心实体(Workspace / Tab / Session / CairnTask / Event / Budget / Plan),
/// 5 个状态机 enum(TabState / SessionState / TaskStatus / BudgetState / PlanStepStatus),
/// 以及 EventType(封闭 12 种)、ToolCategory(开放集)。
///
/// 所有类型 public + Codable + Equatable/Hashable(by id)+ Sendable。
/// 日期序列化统一 ISO-8601,见 `ISO8601Coding.swift`。
public enum CairnCore {
    /// 模块版本标识。每个 milestone 完成时 bump。
    public static let scaffoldVersion = "0.1.0-m1.1"
}
```

- [ ] **Step 3:更新 CairnCoreTests.swift 里的版本断言**

用 Edit 工具把 `Tests/CairnCoreTests/CairnCoreTests.swift` 里的 `"m0.2"` 替换为 `"m1.1"`(2 处):一处在断言里,一处在失败消息里。

最终文件内容:

```swift
import XCTest
@testable import CairnCore

final class CairnCoreTests: XCTestCase {
    func test_scaffoldVersion_startsWithZero() {
        XCTAssertTrue(CairnCore.scaffoldVersion.hasPrefix("0."))
    }

    func test_scaffoldVersion_containsMilestoneTag() {
        XCTAssertTrue(
            CairnCore.scaffoldVersion.contains("m1.1"),
            "版本字符串应包含当前 milestone 标识,实际是 \(CairnCore.scaffoldVersion)"
        )
    }
}
```

- [ ] **Step 4:验证测试仍通过**

```bash
swift test --filter CairnCoreTests 2>&1 | tail -5
```

**Expected**:`Executed 2 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/ Tests/CairnCoreTests/CairnCoreTests.swift
git commit -m "refactor(core): 重命名 Core.swift → CairnCore.swift,版本 bump m1.1

与模块名一致,为 M1.1 填充领域模型做准备。
scaffoldVersion 从 0.0.1-m0.2 升到 0.1.0-m1.1(minor 版本号表示
Cairn 进入'有真实领域模型'阶段)。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T2:Workspace 实体 + Codable 测试

**Files:**
- Create: `Sources/CairnCore/Workspace.swift`
- Create: `Tests/CairnCoreTests/WorkspaceTests.swift`

- [ ] **Step 1:先写测试(红灯)**

`Tests/CairnCoreTests/WorkspaceTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class WorkspaceTests: XCTestCase {
    func test_init_preservesAllFields() {
        let id = UUID()
        let now = Date()
        let ws = Workspace(
            id: id,
            name: "MyProject",
            cwd: "/Users/sorain/myproj",
            createdAt: now,
            lastActiveAt: now,
            archivedAt: nil
        )
        XCTAssertEqual(ws.id, id)
        XCTAssertEqual(ws.name, "MyProject")
        XCTAssertEqual(ws.cwd, "/Users/sorain/myproj")
        XCTAssertEqual(ws.createdAt, now)
        XCTAssertEqual(ws.lastActiveAt, now)
        XCTAssertNil(ws.archivedAt)
    }

    func test_codable_roundTrip() throws {
        let original = Workspace(
            id: UUID(),
            name: "Cairn",
            cwd: "/tmp",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastActiveAt: Date(timeIntervalSince1970: 1_700_001_000),
            archivedAt: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workspace.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func test_equatable_byId() {
        let id = UUID()
        let a = Workspace(id: id, name: "A", cwd: "/a",
                          createdAt: Date(), lastActiveAt: Date(), archivedAt: nil)
        let b = Workspace(id: id, name: "B", cwd: "/b",
                          createdAt: Date(), lastActiveAt: Date(), archivedAt: nil)
        // 当前实现 Equatable 默认按所有字段;本测试记录"v1 按所有字段比较"的决策,
        // 避免日后误改为"按 id 比较"破坏 Codable round-trip 测试。
        XCTAssertNotEqual(a, b, "v1 Equatable 比较所有字段(含 name/cwd),不仅 id")
    }
}
```

**注**:Plan 设计决策 #6 说 "Equatable by id",但 Swift 的 synthesized Equatable 比较所有字段。T2 的 `test_equatable_byId` 测试实际验证"字段级比较"语义(符合 synthesized 行为)—— 我们对 #6 的准确解读是"Hashable by id,Equatable by struct 字段"。这样 round-trip 测试才能验证字段完整性。

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter WorkspaceTests 2>&1 | tail -5
```

**Expected**:`error: Cannot find 'Workspace' in scope` 或类似编译错。

- [ ] **Step 3:写实体实现**

`Sources/CairnCore/Workspace.swift`:

```swift
import Foundation

/// Cairn 中的工作空间:一个项目的根目录 + 关联状态。
///
/// spec §2.1:Workspace 包含多个 Tab / Session,拥有窗口/布局状态。
/// M1.1 只定义纯数据;布局状态(LayoutState)留 M1.3。
public struct Workspace: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var cwd: String
    public let createdAt: Date
    public var lastActiveAt: Date
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        cwd: String,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.archivedAt = archivedAt
    }
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter WorkspaceTests 2>&1 | tail -5
```

**Expected**:`Executed 3 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/Workspace.swift Tests/CairnCoreTests/WorkspaceTests.swift
git commit -m "feat(core): Workspace 实体 + 3 Codable 测试

值语义 struct,UUID 主键,name/cwd 可变,archivedAt 可选。
Codable round-trip 通过 ISO-8601 日期策略。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T3:Tab 实体 + TabState 枚举 + 测试

**Files:**
- Create: `Sources/CairnCore/Tab.swift`
- Create: `Tests/CairnCoreTests/TabTests.swift`

- [ ] **Step 1:先写测试(红灯)**

`Tests/CairnCoreTests/TabTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class TabTests: XCTestCase {
    func test_init_preservesAllFields() {
        let id = UUID()
        let workspaceId = UUID()
        let tab = Tab(
            id: id,
            workspaceId: workspaceId,
            title: "~/myproj (zsh)",
            ptyPid: 12345,
            state: .active
        )
        XCTAssertEqual(tab.id, id)
        XCTAssertEqual(tab.workspaceId, workspaceId)
        XCTAssertEqual(tab.title, "~/myproj (zsh)")
        XCTAssertEqual(tab.ptyPid, 12345)
        XCTAssertEqual(tab.state, .active)
    }

    func test_tabState_rawValues() {
        XCTAssertEqual(TabState.active.rawValue, "active")
        XCTAssertEqual(TabState.closed.rawValue, "closed")
        XCTAssertEqual(TabState.allCases.count, 2)
    }

    func test_codable_roundTrip_withNilPtyPid() throws {
        let original = Tab(
            id: UUID(),
            workspaceId: UUID(),
            title: "Closed tab",
            ptyPid: nil,
            state: .closed
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter TabTests 2>&1 | tail -5
```

- [ ] **Step 3:写实现**

`Sources/CairnCore/Tab.swift`:

```swift
import Foundation

/// 终端标签(1 PTY 进程 + 滚动缓冲)。spec §2.1 / §5.3。
///
/// M1.1 不含 scrollBufferRef(spec §2.6 列出但 v1 不持久化,见 §5.6);
/// layoutState 独立持久化在 M1.2 的 layout_states 表。
public struct Tab: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var workspaceId: UUID
    public var title: String
    public var ptyPid: Int?
    public var state: TabState

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        title: String,
        ptyPid: Int? = nil,
        state: TabState = .active
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.ptyPid = ptyPid
        self.state = state
    }
}

/// Tab 生命周期状态。spec §2.6 明确只有 active / closed 两态。
public enum TabState: String, Codable, CaseIterable, Sendable {
    case active
    case closed
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter TabTests 2>&1 | tail -5
```

**Expected**:`Executed 3 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/Tab.swift Tests/CairnCoreTests/TabTests.swift
git commit -m "feat(core): Tab + TabState 枚举 + 3 测试

ptyPid 可选(closed 状态无 pid);state String enum 便于 SQLite 列存。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T4:Session 实体 + SessionState 枚举 + 测试

**Files:**
- Create: `Sources/CairnCore/Session.swift`
- Create: `Tests/CairnCoreTests/SessionTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnCoreTests/SessionTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class SessionTests: XCTestCase {
    func test_init_defaults() {
        let session = Session(
            workspaceId: UUID(),
            jsonlPath: "/Users/sorain/.claude/projects/-hash/abc.jsonl",
            startedAt: Date()
        )
        XCTAssertEqual(session.byteOffset, 0)
        XCTAssertEqual(session.lastLineNumber, 0)
        XCTAssertNil(session.endedAt)
        XCTAssertNil(session.modelUsed)
        XCTAssertFalse(session.isImported)
        XCTAssertEqual(session.state, .live)
    }

    func test_sessionState_allCases() {
        XCTAssertEqual(Set(SessionState.allCases.map(\.rawValue)),
                       ["live", "idle", "ended", "abandoned", "crashed"])
    }

    func test_codable_roundTrip() throws {
        let original = Session(
            id: UUID(),
            workspaceId: UUID(),
            jsonlPath: "/tmp/s.jsonl",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600),
            byteOffset: 12_345,
            lastLineNumber: 67,
            modelUsed: "claude-opus-4-7",
            isImported: false,
            state: .ended
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Session.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter SessionTests 2>&1 | tail -5
```

- [ ] **Step 3:写实现**

`Sources/CairnCore/Session.swift`:

```swift
import Foundation

/// Claude Code 会话(以 Claude 的 sessionId UUID 唯一标识)。
///
/// spec §2.1:Claude Code 拥有 session 状态,Cairn 只观察 / 缓存元数据。
/// spec §2.6:含 byteOffset 增量解析游标;isImported 标记是否从历史 JSONL 扫出。
public struct Session: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var workspaceId: UUID
    public var jsonlPath: String
    public var startedAt: Date
    public var endedAt: Date?
    public var byteOffset: Int64
    public var lastLineNumber: Int64
    public var modelUsed: String?
    public var isImported: Bool
    public var state: SessionState

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        jsonlPath: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        byteOffset: Int64 = 0,
        lastLineNumber: Int64 = 0,
        modelUsed: String? = nil,
        isImported: Bool = false,
        state: SessionState = .live
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.jsonlPath = jsonlPath
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.byteOffset = byteOffset
        self.lastLineNumber = lastLineNumber
        self.modelUsed = modelUsed
        self.isImported = isImported
        self.state = state
    }
}

/// Session 生命周期状态(5 态)。
///
/// spec §4.5 判据(M0.1 probe 修订后):
/// - `.live`: mtime < 60s
/// - `.idle`: mtime 60s-5min
/// - `.ended`: mtime > 5min 且无悬挂 tool_use(不要求末条是 assistant,M0.1 修订)
/// - `.abandoned`: mtime > 30min 且含未配对悬挂 tool_use
/// - `.crashed`: 文件被删除
public enum SessionState: String, Codable, CaseIterable, Sendable {
    case live
    case idle
    case ended
    case abandoned
    case crashed
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter SessionTests 2>&1 | tail -5
```

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/Session.swift Tests/CairnCoreTests/SessionTests.swift
git commit -m "feat(core): Session + SessionState 枚举(5 态)+ 3 测试

byteOffset 和 lastLineNumber 是 spec §4.2 JSONLWatcher 增量解析游标,
Int64 足够大文件(max 68MB 实测,P99 3MB)。isImported 区分实时 vs
历史首次导入 session。

SessionState 注释同步 M0.1 ADR 0001 修订(去掉'末条是 assistant'要求)。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T5:CairnTask 实体 + TaskStatus 枚举 + 测试

**Files:**
- Create: `Sources/CairnCore/CairnTask.swift`
- Create: `Tests/CairnCoreTests/CairnTaskTests.swift`

**注**:类型名是 `CairnTask` 不是 `Task`(设计决策 #4:避免 Swift.Task 命名冲突)。spec 文本用 "Task" 是 UX 级别的语义,代码层用 `CairnTask` 是工程纪律,两者不冲突。

- [ ] **Step 1:先写测试**

`Tests/CairnCoreTests/CairnTaskTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class CairnTaskTests: XCTestCase {
    func test_init_v1_hasSingleSession() {
        let sessionId = UUID()
        let task = CairnTask(
            workspaceId: UUID(),
            title: "Refactor auth",
            sessionIds: [sessionId]
        )
        XCTAssertEqual(task.sessionIds.count, 1,
                       "spec §2.2 说 v1 UI 默认 Task has one Session(1:1)")
        XCTAssertEqual(task.sessionIds.first, sessionId)
        XCTAssertEqual(task.status, .active)
        XCTAssertNil(task.intent)
        XCTAssertNil(task.completedAt)
    }

    func test_taskStatus_allCases() {
        XCTAssertEqual(Set(TaskStatus.allCases.map(\.rawValue)),
                       ["active", "completed", "abandoned", "archived"])
    }

    func test_codable_roundTrip_completed() throws {
        let original = CairnTask(
            id: UUID(),
            workspaceId: UUID(),
            title: "Implement M1.1",
            intent: "Fill CairnCore with real data types",
            status: .completed,
            sessionIds: [UUID(), UUID()],  // 测试 >1 session 也能序列化
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_010_000),
            completedAt: Date(timeIntervalSince1970: 1_700_010_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CairnTask.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter CairnTaskTests 2>&1 | tail -5
```

- [ ] **Step 3:写实现**

`Sources/CairnCore/CairnTask.swift`:

```swift
import Foundation

/// 用户意图工作单元。spec §2.1 "Task 是一等实体"。
///
/// **命名注**:本类型对应 spec 的"Task"。Swift 标准库 `Task` 是结构化并发原语,
/// 为避免命名冲突,CairnCore 公开类型名为 `CairnTask`。UI 层仍向用户展示 "Task"。
///
/// spec §2.2:Task has-many Sessions(1:N),v1 UI 默认 1:1。schema 从 day 1
/// 支持 `sessionIds: [UUID]` 数组,v1 长度恒为 1,v1.5+ 支持"attach session
/// to existing task"。
public struct CairnTask: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var workspaceId: UUID
    public var title: String
    public var intent: String?
    public var status: TaskStatus
    public var sessionIds: [UUID]
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        title: String,
        intent: String? = nil,
        status: TaskStatus = .active,
        sessionIds: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.intent = intent
        self.status = status
        self.sessionIds = sessionIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

/// Task 生命周期状态(4 态)。spec §2.6。
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case active
    case completed
    case abandoned
    case archived
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter CairnTaskTests 2>&1 | tail -5
```

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/CairnTask.swift Tests/CairnCoreTests/CairnTaskTests.swift
git commit -m "feat(core): CairnTask + TaskStatus 枚举(4 态)+ 3 测试

命名 CairnTask 避开 Swift.Task(结构化并发)冲突;UX 仍展示为 'Task'。
sessionIds 数组支持 spec §2.2 规定的 1:N 关系(v1 长度恒 1)。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T6:EventType 枚举(封闭 12 种)+ 测试

**Files:**
- Create: `Sources/CairnCore/EventType.swift`
- Create: `Tests/CairnCoreTests/EventTypeTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnCoreTests/EventTypeTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class EventTypeTests: XCTestCase {
    func test_allCases_hasTwelveMembers() {
        XCTAssertEqual(EventType.allCases.count, 12,
                       "spec §2.3:type 封闭 12 种(v1 活跃 10 + v1.1 预留 2)")
    }

    func test_rawValues_matchSpec() {
        XCTAssertEqual(Set(EventType.allCases.map(\.rawValue)), Set([
            "user_message",
            "assistant_text",
            "assistant_thinking",
            "tool_use",
            "tool_result",
            "api_usage",
            "compact_boundary",
            "error",
            "plan_updated",
            "session_boundary",
            "approval_requested",
            "approval_decided",
        ]))
    }

    func test_codable_roundTrip() throws {
        for caseValue in EventType.allCases {
            let data = try JSONEncoder().encode(caseValue)
            let decoded = try JSONDecoder().decode(EventType.self, from: data)
            XCTAssertEqual(caseValue, decoded)
        }
    }

    func test_v1Reserved_vs_v11Active() {
        // v1.1 预留:approval_requested, approval_decided
        let v11Reserved: Set<EventType> = [.approvalRequested, .approvalDecided]
        XCTAssertEqual(v11Reserved.count, 2)
        let v1Active = Set(EventType.allCases).subtracting(v11Reserved)
        XCTAssertEqual(v1Active.count, 10)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter EventTypeTests 2>&1 | tail -5
```

- [ ] **Step 3:写实现**

`Sources/CairnCore/EventType.swift`:

```swift
import Foundation

/// Event 类型的**封闭集**。spec §2.3:12 种(v1 活跃 10,v1.1 预留 2)。
///
/// 两维设计中的"第一维"(type)。第二维 `ToolCategory` 是开放集,
/// 仅当 `type == .toolUse` 时使用,定义见 `ToolCategory.swift`。
public enum EventType: String, Codable, CaseIterable, Sendable {
    case userMessage = "user_message"
    case assistantText = "assistant_text"
    case assistantThinking = "assistant_thinking"
    case toolUse = "tool_use"
    case toolResult = "tool_result"
    case apiUsage = "api_usage"
    case compactBoundary = "compact_boundary"
    case error
    case planUpdated = "plan_updated"
    case sessionBoundary = "session_boundary"
    // v1.1 预留:
    case approvalRequested = "approval_requested"
    case approvalDecided = "approval_decided"
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter EventTypeTests 2>&1 | tail -5
```

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/EventType.swift Tests/CairnCoreTests/EventTypeTests.swift
git commit -m "feat(core): EventType 枚举(封闭 12 种)+ 4 测试

Swift case 用 camelCase,rawValue 用 snake_case 匹配 spec §2.3 文本,
便于跨语言互通(JSONL 里可能用 snake_case)。
v1.1 预留的 approvalRequested / approvalDecided 用测试显式标注。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T7:ToolCategory 开放集 + 查表 + 测试

**Files:**
- Create: `Sources/CairnCore/ToolCategory.swift`
- Create: `Tests/CairnCoreTests/ToolCategoryTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnCoreTests/ToolCategoryTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class ToolCategoryTests: XCTestCase {
    func test_staticConstants_coverSpecCategories() {
        // spec §2.3 列出的 12 种 category
        let expected: Set<String> = [
            "shell", "file_read", "file_write", "file_search",
            "web_fetch", "mcp_call", "subagent", "todo",
            "plan_mgmt", "ask_user", "ide", "other",
        ]
        let staticValues: Set<String> = [
            ToolCategory.shell, .fileRead, .fileWrite, .fileSearch,
            .webFetch, .mcpCall, .subagent, .todo,
            .planMgmt, .askUser, .ide, .other,
        ].map(\.rawValue).reduce(into: Set<String>()) { $0.insert($1) }
        XCTAssertEqual(staticValues, expected)
    }

    func test_fromToolName_shellTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "Bash"), .shell)
    }

    func test_fromToolName_fileReadTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "Read"), .fileRead)
        XCTAssertEqual(ToolCategory.from(toolName: "NotebookRead"), .fileRead)
    }

    func test_fromToolName_fileWriteTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "Write"), .fileWrite)
        XCTAssertEqual(ToolCategory.from(toolName: "Edit"), .fileWrite)
        XCTAssertEqual(ToolCategory.from(toolName: "NotebookEdit"), .fileWrite)
    }

    func test_fromToolName_searchTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "Glob"), .fileSearch)
        XCTAssertEqual(ToolCategory.from(toolName: "Grep"), .fileSearch)
    }

    func test_fromToolName_webTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "WebFetch"), .webFetch)
        XCTAssertEqual(ToolCategory.from(toolName: "WebSearch"), .webFetch)
    }

    func test_fromToolName_mcpPrefix() {
        XCTAssertEqual(ToolCategory.from(toolName: "mcp__feishu-mcp__fetch-doc"), .mcpCall)
        XCTAssertEqual(ToolCategory.from(toolName: "ListMcpResourcesTool"), .mcpCall)
    }

    func test_fromToolName_ideSubPrefix() {
        // mcp__ide__* 是 mcpCall 的特化 → ide
        XCTAssertEqual(ToolCategory.from(toolName: "mcp__ide__getDiagnostics"), .ide)
    }

    func test_fromToolName_subagent() {
        XCTAssertEqual(ToolCategory.from(toolName: "Agent"), .subagent)
        XCTAssertEqual(ToolCategory.from(toolName: "Task"), .subagent,
                       "Claude Code 的 Task 工具是 agent,不是 task 实体")
    }

    func test_fromToolName_todoAndTaskMgmt() {
        XCTAssertEqual(ToolCategory.from(toolName: "TodoWrite"), .todo)
        // M0.1 probe 扩展:TaskCreate / TaskUpdate / TaskList 等归入 todo
        XCTAssertEqual(ToolCategory.from(toolName: "TaskCreate"), .todo)
        XCTAssertEqual(ToolCategory.from(toolName: "TaskUpdate"), .todo)
        XCTAssertEqual(ToolCategory.from(toolName: "TaskList"), .todo)
    }

    func test_fromToolName_planMgmt() {
        XCTAssertEqual(ToolCategory.from(toolName: "EnterPlanMode"), .planMgmt)
        XCTAssertEqual(ToolCategory.from(toolName: "ExitPlanMode"), .planMgmt)
    }

    func test_fromToolName_askUser() {
        XCTAssertEqual(ToolCategory.from(toolName: "AskUserQuestion"), .askUser)
    }

    func test_fromToolName_unknownFallsToOther() {
        XCTAssertEqual(ToolCategory.from(toolName: "SomeUnknownTool"), .other)
        XCTAssertEqual(ToolCategory.from(toolName: ""), .other)
    }

    func test_customCategory_viaRawValue() {
        let custom = ToolCategory(rawValue: "experimental_category_v1")
        XCTAssertEqual(custom.rawValue, "experimental_category_v1")
        // custom 不等于任何静态常量
        XCTAssertNotEqual(custom, .other)
    }

    func test_codable_roundTrip() throws {
        for sample in [ToolCategory.shell, .mcpCall, .ide, .other,
                       ToolCategory(rawValue: "custom")] {
            let data = try JSONEncoder().encode(sample)
            let decoded = try JSONDecoder().decode(ToolCategory.self, from: data)
            XCTAssertEqual(sample, decoded)
        }
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter ToolCategoryTests 2>&1 | tail -5
```

- [ ] **Step 3:写实现**

`Sources/CairnCore/ToolCategory.swift`:

```swift
import Foundation

/// 工具分类的**开放集**。spec §2.3:仅当 `Event.type == .toolUse` 时使用,
/// 按 `toolName` 查表映射。
///
/// Swift 没有"开放 enum",所以用 `struct RawRepresentable`:
/// - 12 个静态常量对应 spec §2.3 已命名的类别
/// - `from(toolName:)` 按 spec §2.3 的映射表 + M0.1 probe 扩展解析
/// - 未知 toolName 兜底到 `.other`
/// - 允许外部用 `ToolCategory(rawValue: "custom")` 构造新类别
public struct ToolCategory: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - 静态常量(spec §2.3 的 12 种已命名类别)

extension ToolCategory {
    public static let shell = ToolCategory(rawValue: "shell")
    public static let fileRead = ToolCategory(rawValue: "file_read")
    public static let fileWrite = ToolCategory(rawValue: "file_write")
    public static let fileSearch = ToolCategory(rawValue: "file_search")
    public static let webFetch = ToolCategory(rawValue: "web_fetch")
    public static let mcpCall = ToolCategory(rawValue: "mcp_call")
    public static let subagent = ToolCategory(rawValue: "subagent")
    public static let todo = ToolCategory(rawValue: "todo")
    public static let planMgmt = ToolCategory(rawValue: "plan_mgmt")
    public static let askUser = ToolCategory(rawValue: "ask_user")
    public static let ide = ToolCategory(rawValue: "ide")
    public static let other = ToolCategory(rawValue: "other")
}

// MARK: - toolName → category 查表

extension ToolCategory {
    /// 按 Claude Code toolName 映射到 category。
    ///
    /// spec §2.3 静态表 + M0.1 probe 实测扩展(Task* / Skill / ListMcpResourcesTool)。
    /// 未知 toolName 兜底到 `.other`。
    public static func from(toolName: String) -> ToolCategory {
        // IDE 特化(mcp__ide__* 是 mcpCall 的子分类,优先级高)
        if toolName.hasPrefix("mcp__ide__") {
            return .ide
        }
        // MCP 通用前缀
        if toolName.hasPrefix("mcp__") {
            return .mcpCall
        }
        // MCP 资源列举工具(不走 mcp__ 前缀)
        if toolName == "ListMcpResourcesTool" || toolName == "ReadMcpResourceTool" {
            return .mcpCall
        }
        // 精确名称查表
        switch toolName {
        case "Bash":
            return .shell
        case "Read", "NotebookRead":
            return .fileRead
        case "Write", "Edit", "NotebookEdit":
            return .fileWrite
        case "Glob", "Grep":
            return .fileSearch
        case "WebFetch", "WebSearch":
            return .webFetch
        case "Agent", "Task":
            return .subagent
        case "TodoWrite":
            return .todo
        case "EnterPlanMode", "ExitPlanMode":
            return .planMgmt
        case "AskUserQuestion":
            return .askUser
        default:
            break
        }
        // M0.1 probe 发现的 Task* 系列(TaskCreate/Update/List/Get/Output/Stop 等)
        // 都是任务管理工具,归 todo
        if toolName.hasPrefix("Task") && toolName != "Task" {
            return .todo
        }
        return .other
    }
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter ToolCategoryTests 2>&1 | tail -5
```

**Expected**:`Executed 14 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/ToolCategory.swift Tests/CairnCoreTests/ToolCategoryTests.swift
git commit -m "feat(core): ToolCategory 开放集 + toolName 查表 + 14 测试

struct RawRepresentable 模拟'开放 enum'。12 静态常量对应 spec §2.3,
from(toolName:) 实装查表 + M0.1 probe 的扩展(Task*/MCP/IDE)。
未知 toolName 兜底 .other 不破坏。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T8:Event 实体 + 测试

**Files:**
- Create: `Sources/CairnCore/Event.swift`
- Create: `Tests/CairnCoreTests/EventTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnCoreTests/EventTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class EventTests: XCTestCase {
    func test_init_userMessage_hasNoToolFields() {
        let event = Event(
            sessionId: UUID(),
            type: .userMessage,
            timestamp: Date(),
            lineNumber: 1,
            summary: "Hello Claude"
        )
        XCTAssertNil(event.category)
        XCTAssertNil(event.toolName)
        XCTAssertNil(event.toolUseId)
        XCTAssertEqual(event.blockIndex, 0)
    }

    func test_init_toolUse_hasCategoryAndToolName() {
        let event = Event(
            sessionId: UUID(),
            type: .toolUse,
            category: .fileRead,
            toolName: "Read",
            toolUseId: "toolu_01",
            timestamp: Date(),
            lineNumber: 42,
            summary: "Read README.md"
        )
        XCTAssertEqual(event.category, .fileRead)
        XCTAssertEqual(event.toolName, "Read")
        XCTAssertEqual(event.toolUseId, "toolu_01")
    }

    func test_codable_roundTrip_withRawPayload() throws {
        let original = Event(
            id: UUID(),
            sessionId: UUID(),
            type: .toolResult,
            category: nil,
            toolName: nil,
            toolUseId: "toolu_01",
            pairedEventId: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            lineNumber: 43,
            blockIndex: 0,
            summary: "File read OK (1234 bytes)",
            rawPayloadJson: #"{"type":"tool_result","content":"..."}"#,
            byteOffsetInJsonl: 98_765
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Event.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_defaults_minimalEvent() {
        let event = Event(
            sessionId: UUID(),
            type: .assistantText,
            timestamp: Date(),
            lineNumber: 5,
            summary: "response"
        )
        XCTAssertEqual(event.blockIndex, 0,
                       "blockIndex 默认 0 — spec §2.6 为单 block 行的默认位置")
        XCTAssertNil(event.rawPayloadJson)
        XCTAssertNil(event.byteOffsetInJsonl)
        XCTAssertNil(event.pairedEventId)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter EventTests 2>&1 | tail -5
```

- [ ] **Step 3:写实现**

`Sources/CairnCore/Event.swift`:

```swift
import Foundation

/// 从 JSONL 抽出的结构化事件。spec §2.3 两维设计 + §2.6 完整字段。
///
/// - `type` 封闭 12 种,必填
/// - `category` 开放集,仅当 `type == .toolUse` 时通常非 nil(按 toolName 查表)
/// - `toolUseId` 用于 Claude Code 分配的 tool_use↔tool_result 配对,
///   `pairedEventId` 是 Cairn 在解析时填入的对端 Event.id
/// - `(sessionId, lineNumber, blockIndex)` 是主排序键(spec §2.6 索引)
/// - `rawPayloadJson` 持有原始 JSON 字符串(不解析,懒加载设计)
public struct Event: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var sessionId: UUID
    public var type: EventType
    public var category: ToolCategory?
    public var toolName: String?
    public var toolUseId: String?
    public var pairedEventId: UUID?
    public var timestamp: Date
    public var lineNumber: Int64
    public var blockIndex: Int
    public var summary: String
    public var rawPayloadJson: String?
    public var byteOffsetInJsonl: Int64?

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        type: EventType,
        category: ToolCategory? = nil,
        toolName: String? = nil,
        toolUseId: String? = nil,
        pairedEventId: UUID? = nil,
        timestamp: Date,
        lineNumber: Int64,
        blockIndex: Int = 0,
        summary: String,
        rawPayloadJson: String? = nil,
        byteOffsetInJsonl: Int64? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.type = type
        self.category = category
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.pairedEventId = pairedEventId
        self.timestamp = timestamp
        self.lineNumber = lineNumber
        self.blockIndex = blockIndex
        self.summary = summary
        self.rawPayloadJson = rawPayloadJson
        self.byteOffsetInJsonl = byteOffsetInJsonl
    }
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter EventTests 2>&1 | tail -5
```

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/Event.swift Tests/CairnCoreTests/EventTests.swift
git commit -m "feat(core): Event 实体 + 4 测试

组装 EventType(封闭)+ ToolCategory(开放),覆盖 spec §2.6 全部字段
(id/sessionId/type/category/toolName/toolUseId/pairedEventId/timestamp/
lineNumber/blockIndex/summary/rawPayloadJson/byteOffsetInJsonl)。
rawPayloadJson 作 String? 懒加载 —— spec §2.6 要求'完整数据,懒加载'。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T9:Budget 实体 + BudgetState + 状态转换 + 测试

**Files:**
- Create: `Sources/CairnCore/Budget.swift`
- Create: `Tests/CairnCoreTests/BudgetTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnCoreTests/BudgetTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class BudgetTests: XCTestCase {
    func test_init_defaults_allUsedZero() {
        let budget = Budget(taskId: UUID())
        XCTAssertEqual(budget.usedInputTokens, 0)
        XCTAssertEqual(budget.usedOutputTokens, 0)
        XCTAssertEqual(budget.usedCostUSD, 0.0)
        XCTAssertEqual(budget.usedWallSeconds, 0)
        XCTAssertEqual(budget.state, .normal)
        XCTAssertNil(budget.maxInputTokens)
    }

    func test_budgetState_allCases() {
        XCTAssertEqual(Set(BudgetState.allCases.map(\.rawValue)),
                       ["normal", "warning80", "exceeded", "paused"])
    }

    func test_computeState_noCaps_alwaysNormal() {
        // 无 pre-commitment → 永远 .normal(观察模式)
        let budget = Budget(
            taskId: UUID(),
            usedInputTokens: 1_000_000,
            usedOutputTokens: 500_000,
            usedCostUSD: 100.0,
            usedWallSeconds: 999999
        )
        XCTAssertEqual(budget.computeState(), .normal)
    }

    func test_computeState_costUnderWarning() {
        let budget = Budget(
            taskId: UUID(),
            maxCostUSD: 10.0,
            usedCostUSD: 5.0  // 50%
        )
        XCTAssertEqual(budget.computeState(), .normal)
    }

    func test_computeState_costAt80_triggersWarning() {
        let budget = Budget(
            taskId: UUID(),
            maxCostUSD: 10.0,
            usedCostUSD: 8.0  // exactly 80%
        )
        XCTAssertEqual(budget.computeState(), .warning80)
    }

    func test_computeState_costOver100_exceeded() {
        let budget = Budget(
            taskId: UUID(),
            maxCostUSD: 10.0,
            usedCostUSD: 10.5
        )
        XCTAssertEqual(budget.computeState(), .exceeded)
    }

    func test_computeState_anyCapExceeded_exceeded() {
        // 任何一个 cap 超过 100% 都触发 exceeded(不是任意 80% 触发 warning)
        let budget = Budget(
            taskId: UUID(),
            maxInputTokens: 1000,
            maxCostUSD: 10.0,
            usedInputTokens: 1500,  // exceeded on tokens
            usedCostUSD: 3.0  // normal on cost
        )
        XCTAssertEqual(budget.computeState(), .exceeded)
    }

    func test_computeState_pausedIsSticky() {
        // paused 不由 computeState 自动恢复;它是手动状态
        let budget = Budget(
            taskId: UUID(),
            maxCostUSD: 10.0,
            usedCostUSD: 1.0,
            state: .paused
        )
        XCTAssertEqual(budget.computeState(), .paused,
                       "paused 由用户手动设置,computeState 不应自动恢复")
    }

    func test_codable_roundTrip() throws {
        let original = Budget(
            taskId: UUID(),
            maxInputTokens: 100_000,
            maxOutputTokens: 50_000,
            maxCostUSD: 5.00,
            maxWallSeconds: 3600,
            usedInputTokens: 12_345,
            usedOutputTokens: 6_789,
            usedCostUSD: 0.68,
            usedWallSeconds: 120,
            state: .normal,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Budget.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter BudgetTests 2>&1 | tail -5
```

- [ ] **Step 3:写实现**

`Sources/CairnCore/Budget.swift`:

```swift
import Foundation

/// 任务级 token / 成本 / 时间预算。spec §2.4。
///
/// v1 观察模式:到达 80% / 100% 只告警,不打断(spec §2.4)。
/// v1.1 Hook 启用后才会拦截(M1 不实现拦截逻辑,只持有状态)。
public struct Budget: Codable, Equatable, Hashable, Sendable {
    public let taskId: UUID

    // Pre-commitment(可选,全 nil 表示无限制 = 永远 normal)
    public var maxInputTokens: Int?
    public var maxOutputTokens: Int?
    public var maxCostUSD: Double?
    public var maxWallSeconds: Int?

    // Actual(累加 api_usage 事件)
    public var usedInputTokens: Int
    public var usedOutputTokens: Int
    public var usedCostUSD: Double
    public var usedWallSeconds: Int

    public var state: BudgetState
    public var updatedAt: Date

    public init(
        taskId: UUID,
        maxInputTokens: Int? = nil,
        maxOutputTokens: Int? = nil,
        maxCostUSD: Double? = nil,
        maxWallSeconds: Int? = nil,
        usedInputTokens: Int = 0,
        usedOutputTokens: Int = 0,
        usedCostUSD: Double = 0,
        usedWallSeconds: Int = 0,
        state: BudgetState = .normal,
        updatedAt: Date = Date()
    ) {
        self.taskId = taskId
        self.maxInputTokens = maxInputTokens
        self.maxOutputTokens = maxOutputTokens
        self.maxCostUSD = maxCostUSD
        self.maxWallSeconds = maxWallSeconds
        self.usedInputTokens = usedInputTokens
        self.usedOutputTokens = usedOutputTokens
        self.usedCostUSD = usedCostUSD
        self.usedWallSeconds = usedWallSeconds
        self.state = state
        self.updatedAt = updatedAt
    }

    /// 根据 used vs max 比例**推导**state,不修改 self(纯函数)。
    ///
    /// 规则:
    /// - `state == .paused` → 保持 .paused(paused 由用户手动设置)
    /// - 任何一个 cap 被超(used >= max)→ `.exceeded`
    /// - 任何一个 cap 到达 80%(used / max >= 0.80)→ `.warning80`
    /// - 其他 → `.normal`
    public func computeState() -> BudgetState {
        if state == .paused { return .paused }

        var maxRatio = 0.0
        var anyExceeded = false

        if let cap = maxInputTokens, cap > 0 {
            let ratio = Double(usedInputTokens) / Double(cap)
            maxRatio = max(maxRatio, ratio)
            if usedInputTokens >= cap { anyExceeded = true }
        }
        if let cap = maxOutputTokens, cap > 0 {
            let ratio = Double(usedOutputTokens) / Double(cap)
            maxRatio = max(maxRatio, ratio)
            if usedOutputTokens >= cap { anyExceeded = true }
        }
        if let cap = maxCostUSD, cap > 0 {
            let ratio = usedCostUSD / cap
            maxRatio = max(maxRatio, ratio)
            if usedCostUSD >= cap { anyExceeded = true }
        }
        if let cap = maxWallSeconds, cap > 0 {
            let ratio = Double(usedWallSeconds) / Double(cap)
            maxRatio = max(maxRatio, ratio)
            if usedWallSeconds >= cap { anyExceeded = true }
        }

        if anyExceeded { return .exceeded }
        if maxRatio >= 0.80 { return .warning80 }
        return .normal
    }
}

/// Budget 状态(4 态)。spec §2.4。
public enum BudgetState: String, Codable, CaseIterable, Sendable {
    case normal
    case warning80
    case exceeded
    case paused
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter BudgetTests 2>&1 | tail -5
```

**Expected**:`Executed 9 tests, with 0 failures`。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/Budget.swift Tests/CairnCoreTests/BudgetTests.swift
git commit -m "feat(core): Budget + BudgetState(4 态)+ computeState 纯函数 + 9 测试

pre-commitment 全 nil 时永远 normal。任意 cap 超 100% → exceeded,
任意 cap 达 80% → warning80,paused 由用户手动 sticky。
computeState 不 mutate self(纯函数),遵守 spec §3 'CairnCore 无状态'。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T10:Plan 实体 + PlanStep/PlanSource/PlanStepStatus/PlanStepPriority + 测试

**Files:**
- Create: `Sources/CairnCore/Plan.swift`
- Create: `Tests/CairnCoreTests/PlanTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnCoreTests/PlanTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class PlanTests: XCTestCase {
    func test_planSource_allCases() {
        XCTAssertEqual(Set(PlanSource.allCases.map(\.rawValue)),
                       ["todo_write", "plan_md", "manual"])
    }

    func test_planStepStatus_allCases() {
        XCTAssertEqual(Set(PlanStepStatus.allCases.map(\.rawValue)),
                       ["pending", "in_progress", "completed"])
    }

    func test_planStepPriority_allCases() {
        XCTAssertEqual(Set(PlanStepPriority.allCases.map(\.rawValue)),
                       ["low", "medium", "high"])
    }

    func test_planStep_init_defaults() {
        let step = PlanStep(content: "Research auth libraries")
        XCTAssertEqual(step.status, .pending)
        XCTAssertEqual(step.priority, .medium)
    }

    func test_plan_codable_roundTrip() throws {
        let original = Plan(
            id: UUID(),
            taskId: UUID(),
            source: .todoWrite,
            steps: [
                PlanStep(content: "Step 1", status: .completed, priority: .high),
                PlanStep(content: "Step 2", status: .inProgress, priority: .medium),
                PlanStep(content: "Step 3", status: .pending, priority: .low),
            ],
            markdownRaw: "# My Plan\n- [x] Step 1\n- [ ] Step 2\n",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Plan.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_plan_stepsOrderPreserved() {
        let s1 = PlanStep(content: "First")
        let s2 = PlanStep(content: "Second")
        let plan = Plan(taskId: UUID(), source: .manual, steps: [s1, s2])
        XCTAssertEqual(plan.steps.map(\.content), ["First", "Second"])
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter PlanTests 2>&1 | tail -5
```

- [ ] **Step 3:写实现**

`Sources/CairnCore/Plan.swift`:

```swift
import Foundation

/// Task 的执行计划。spec §2.6。
///
/// 来源有三:TodoWrite 工具产出、`.claude/plans/*.md` 文件、用户手动输入。
/// M1.1 提供数据结构,实际解析(markdown → steps)留 M3.4 PlanWatcher。
public struct Plan: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var taskId: UUID
    public var source: PlanSource
    public var steps: [PlanStep]
    public var markdownRaw: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        taskId: UUID,
        source: PlanSource,
        steps: [PlanStep] = [],
        markdownRaw: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.source = source
        self.steps = steps
        self.markdownRaw = markdownRaw
        self.updatedAt = updatedAt
    }
}

/// Plan 的数据来源。spec §2.6。
public enum PlanSource: String, Codable, CaseIterable, Sendable {
    case todoWrite = "todo_write"
    case planMd = "plan_md"
    case manual
}

/// Plan 中的单步。spec §2.6 `{id, content, status, priority}`。
public struct PlanStep: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var content: String
    public var status: PlanStepStatus
    public var priority: PlanStepPriority

    public init(
        id: UUID = UUID(),
        content: String,
        status: PlanStepStatus = .pending,
        priority: PlanStepPriority = .medium
    ) {
        self.id = id
        self.content = content
        self.status = status
        self.priority = priority
    }
}

/// PlanStep 执行状态(3 态,对齐 Claude Code TodoWrite 语义)。
public enum PlanStepStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

/// PlanStep 优先级。TodoWrite 规范。
public enum PlanStepPriority: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter PlanTests 2>&1 | tail -5
```

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/Plan.swift Tests/CairnCoreTests/PlanTests.swift
git commit -m "feat(core): Plan + PlanStep + 3 枚举(Source/Status/Priority)+ 6 测试

source 覆盖 TodoWrite / plan.md / manual 三种来源;step 状态机对齐
Claude Code TodoWrite(pending/in_progress/completed),优先级 low/medium/high。
markdownRaw 保留原始 md 文本,M3.4 PlanWatcher 时再做 markdown→steps 解析。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T11:ISO-8601 Date 共享策略 + 跨实体 JSON round-trip

**Files:**
- Create: `Sources/CairnCore/ISO8601Coding.swift`
- Create: `Tests/CairnCoreTests/JSONRoundTripTests.swift`

- [ ] **Step 1:先写测试**

`Tests/CairnCoreTests/JSONRoundTripTests.swift`:

```swift
import XCTest
@testable import CairnCore

final class JSONRoundTripTests: XCTestCase {
    /// 验证 CairnCore 共享的 encoder/decoder 对所有实体 round-trip 保真。
    /// spec §7.2:ISO-8601 字符串。
    func test_sharedEncoder_outputsISO8601DateStrings() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14T22:13:20Z
        let ws = Workspace(name: "W", cwd: "/", createdAt: date, lastActiveAt: date)
        let data = try CairnCore.jsonEncoder.encode(ws)
        let jsonStr = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(
            jsonStr.contains("2023-11-14T22:13:20Z"),
            "共享 encoder 应产出 ISO-8601 日期字符串,实际: \(jsonStr)"
        )
    }

    func test_allEntities_roundTripViaSharedCoder() throws {
        // Workspace
        try assertRoundTrip(
            Workspace(name: "w", cwd: "/tmp",
                      createdAt: .init(timeIntervalSince1970: 1),
                      lastActiveAt: .init(timeIntervalSince1970: 2))
        )
        // Tab
        try assertRoundTrip(
            Tab(workspaceId: UUID(), title: "t")
        )
        // Session
        try assertRoundTrip(
            Session(workspaceId: UUID(), jsonlPath: "/x",
                    startedAt: .init(timeIntervalSince1970: 1))
        )
        // CairnTask
        try assertRoundTrip(
            CairnTask(workspaceId: UUID(), title: "task",
                      createdAt: .init(timeIntervalSince1970: 1),
                      updatedAt: .init(timeIntervalSince1970: 2))
        )
        // Event
        try assertRoundTrip(
            Event(sessionId: UUID(), type: .toolUse,
                  category: .shell, toolName: "Bash",
                  timestamp: .init(timeIntervalSince1970: 1),
                  lineNumber: 1, summary: "bash")
        )
        // Budget
        try assertRoundTrip(
            Budget(taskId: UUID(),
                   updatedAt: .init(timeIntervalSince1970: 1))
        )
        // Plan
        try assertRoundTrip(
            Plan(taskId: UUID(), source: .manual,
                 updatedAt: .init(timeIntervalSince1970: 1))
        )
    }

    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let data = try CairnCore.jsonEncoder.encode(value)
        let decoded = try CairnCore.jsonDecoder.decode(T.self, from: data)
        XCTAssertEqual(value, decoded, "round-trip 失败: \(T.self)",
                       file: file, line: line)
    }
}
```

- [ ] **Step 2:跑测试确认红**

```bash
swift test --filter JSONRoundTripTests 2>&1 | tail -5
```

- [ ] **Step 3:写实现**

`Sources/CairnCore/ISO8601Coding.swift`:

```swift
import Foundation

/// CairnCore 共享的 JSON 编解码器。统一使用 ISO-8601 日期字符串。
///
/// spec §7.2:时间列一律 ISO-8601 字符串。
/// 使用场景:JSONL ingest 写入 summary JSON、SQLite 列存、导出诊断包。
extension CairnCore {
    /// 共享 JSONEncoder 单例。
    /// 注:JSONEncoder 的 `encode()` 方法在官方文档中**未明确保证**并发安全;
    /// M1.1 仅在单线程测试中使用,并发场景(M2.3 EventIngestor)届时按需
    /// 改为 per-call 新实例或用 actor 封装。
    public static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

- [ ] **Step 4:跑测试确认绿**

```bash
swift test --filter JSONRoundTripTests 2>&1 | tail -10
```

**Expected**:`Executed 2 tests, with 0 failures`,且看到 `"2023-11-14T22:13:20Z"` 在输出中。

- [ ] **Step 5:Commit**

```bash
git add Sources/CairnCore/ISO8601Coding.swift Tests/CairnCoreTests/JSONRoundTripTests.swift
git commit -m "feat(core): CairnCore.jsonEncoder/jsonDecoder 共享实例 + 跨实体 round-trip

ISO-8601 日期策略统一;outputFormatting=.sortedKeys 便于 diff / 回归测试。
跨 7 个实体 round-trip 测试一次性验证'Codable 对每个实体都保真'。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## T12:swift build + swift test 全绿 + 覆盖率自查

**Files:** 无新增。

- [ ] **Step 1:完整 swift build**

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build 2>&1 | tail -5
```

**Expected**:`Build complete!`,本项目代码**无 warning**(SwiftTerm 自身 warning 除外)。

**失败排查**:
- `redeclaration of 'CairnCore'`:检查 CairnCore.swift 和 ISO8601Coding.swift 都用 `extension CairnCore`,不是重复 `public enum CairnCore`
- 编译报某 Codable 合成失败:某实体字段类型没符合 Codable,检查是否有漏加 Codable 的嵌套类型

- [ ] **Step 2:完整 swift test**

```bash
swift test 2>&1 | tail -10
```

**Expected**:`Executed N tests, with 0 failures`,N ≥ 50(累加:CairnCore 2 + Workspace 3 + Tab 3 + Session 3 + CairnTask 3 + EventType 4 + ToolCategory 14 + Event 4 + Budget 9 + Plan 6 + JSONRoundTrip 2 = **53 tests**)。

- [ ] **Step 3:覆盖率快速自查(不强求)**

```bash
swift test --enable-code-coverage 2>&1 | tail -3
```

**Expected**:run 成功即可。本 milestone 不强求 70% 覆盖率自动门控(M4.3 CI 起强制);目测 ≥ 50 tests over 7 entities + 5 enums 已足够密。

- [ ] **Step 4:不 commit**(本 task 只是验证 gate,无文件变更)

---

## T13:milestone-log + tag m1-1-done + push

**Files:**
- Modify: `docs/milestone-log.md`

- [ ] **Step 1:更新 milestone-log.md**

用 Edit 工具在 `docs/milestone-log.md` 里:

(a) 把 `- [ ] M1.1 - M1.5 ...(详见 spec §8.4)` 这行修改为只剩 M1.2-M1.5:

```markdown
- [ ] M1.2 CairnStorage(GRDB + 11 表 + migrator)
- [ ] M1.3 主窗口三区布局
- [ ] M1.4 多 Tab + PTY 生命周期
- [ ] M1.5 水平分屏 + OSC 7 + 布局持久化
```

(b) 在 "已完成(逆序)" 下、**M0.2 条目之前**插入:

```markdown
### M1.1 CairnCore 数据类型

**Completed**: 2026-04-24(或 Claude 实际完成日)
**Tag**: `m1-1-done`
**Commits**: 11 个(T1 bump + T2-T10 实体 + T11 共享 codec)

**Summary**:
- CairnCore 从占位升级为完整领域模型,12 个新源文件(7 实体 + 2 enum/struct + 共享 codec + 各自 tests)
- 7 实体:`Workspace` / `Tab` / `Session` / `CairnTask` / `Event` / `Budget` / `Plan` + `PlanStep`
- 5 状态 enum:`TabState`(2) / `SessionState`(5) / `TaskStatus`(4) / `BudgetState`(4) / `PlanStepStatus`(3) / `PlanStepPriority`(3)
- `EventType` 封闭 12 种(对齐 spec §2.3,v1.1 预留 approval_*);`ToolCategory` 开放集(struct RawRepresentable)+ toolName 查表(含 M0.1 probe 扩展)
- `Budget.computeState()` 纯函数推导 state,遵守 spec §3 "Core 无状态" 纪律
- `CairnCore.jsonEncoder` / `jsonDecoder` 共享实例,ISO-8601 日期策略
- **≥ 53 个单元测试全绿**,远超 spec §8.4 要求的 10 个;跨 7 实体 JSON round-trip 覆盖

**关键设计决策**(plan pinned):
- 类型名 `CairnTask` 不是 `Task` —— 避免 Swift 标准库 `Task`(结构化并发)命名冲突
- `ToolCategory` 用 struct RawRepresentable 实现"开放 enum";已知 12 种作静态常量,未知 toolName 兜底 `.other`
- Budget 状态推导为纯函数 `computeState()`;`.paused` 由用户手动设置,computeState 不自动恢复

**Acceptance**: 见 M1.1 计划文档 T14 验收清单。

**Known limitations**:
- `PlanStep` 的 markdown 解析器留 M3.4(PlanWatcher)
- Budget cost 计算依赖 api_usage 累加,具体模型价格表留 M3.3(BudgetTracker)
- 所有实体的 SQLite 持久化留 M1.2(GRDB schema + DAO)
```

- [ ] **Step 2:Commit**

```bash
git add docs/milestone-log.md
git commit -m "docs(log): M1.1 完成记录

11 commits / 53+ tests green / 7 实体 + 5 enum + 开放集 ToolCategory。
CairnCore 从'占位 scaffoldVersion'升级为'完整领域模型';
M1.2 起可安全依赖 CairnCore 做 SQLite schema 设计。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 3:Push + Tag**

```bash
git push origin main 2>&1 | tail -3
git tag -a m1-1-done -m "M1.1 完成:CairnCore 数据类型"
git push origin m1-1-done 2>&1 | tail -3
```

**Expected**:
- main push 成功
- `* [new tag] m1-1-done -> m1-1-done`

- [ ] **Step 4:最终验证**

```bash
git status
git log --oneline -15
git tag -l
```

**Expected**:
- `working tree clean`
- 本 milestone 新增 12+ commits
- tag 列表含 `m0-1-done` / `m0-2-done` / `m1-1-done`

---

## T14:验收清单(用户执行)

**Owner**: 用户。

Claude 完成 T1-T13 后,在 session 末尾输出以下验收清单:

```markdown
## M1.1 验收清单

**交付物**:
- 12 个新 Swift 文件(`Sources/CairnCore/{CairnCore,Workspace,Tab,Session,CairnTask,EventType,ToolCategory,Event,Budget,Plan,ISO8601Coding}.swift` + 各自 tests)
- 原 `Core.swift` 重命名为 `CairnCore.swift`
- ≥ 53 个单测全绿
- git tag `m1-1-done` 推到远端

**前置条件**:Xcode + Swift toolchain 已装(M0.2 已验证)。

**验证步骤**:

步骤 1 · 编译通过
```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build 2>&1 | tail -3
```
期望:`Build complete!`,本项目代码无 error/warning。

步骤 2 · 全测试集绿
```bash
swift test 2>&1 | tail -5
```
期望:`Executed 53 tests, with 0 failures`(数字可能小幅波动,但 ≥ 50)。

步骤 3 · 源文件就位
```bash
ls Sources/CairnCore/
ls Tests/CairnCoreTests/
```
期望:Sources/CairnCore 有 11 个 .swift(CairnCore, Workspace, Tab, Session, CairnTask, EventType, ToolCategory, Event, Budget, Plan, ISO8601Coding);Tests/CairnCoreTests 有 11 个 .swift(每个实体 + JSONRoundTrip)。

步骤 4 · Git 状态 + tag + 远端
```bash
git status
git log --oneline -15
git tag -l
git ls-remote origin refs/tags/m1-1-done 2>&1 | head -1
```
期望:
- `working tree clean`
- 最近 commit 是 "docs(log): M1.1 完成记录"
- 本地 tag 列表含 `m0-1-done` / `m0-2-done` / `m1-1-done`
- `ls-remote` 显示 `m1-1-done` 在远端存在

步骤 5 · CairnApp 仍可启动(回归)
```bash
./scripts/make-app-bundle.sh debug 2>&1 | tail -3
open build/Cairn.app
# 肉眼确认终端仍可用,然后 ⌘Q 关闭
```
期望:M0.2 的 hello-world app 不受 M1.1 影响,终端仍正常。

**已知限制 / 延后项**:
- PlanStep markdown 解析留 M3.4(PlanWatcher)
- Budget 具体模型价格表留 M3.3(BudgetTracker)
- SQLite 持久化 schema + DAO 留 M1.2

**下个 M**:M1.2 CairnStorage(GRDB + 11 表 + migrator + DAO)。
```

---

## 回归 Self-Review

### 1. Spec 覆盖

| Spec 位置 | 要求 | 对应 Task | 状态 |
|---|---|---|---|
| §2.1 实体 | 8 个(v1 用 7) | T2-T10 | 7 做,Approval(v1.1)不做 |
| §2.2 | Task has-many Sessions | T5 `sessionIds: [UUID]` | ✅ |
| §2.3 EventType | 封闭 12 种 | T6 | ✅ |
| §2.3 ToolCategory | 开放集 + toolName 查表 | T7 | ✅ |
| §2.4 Budget | 4 态 + computeState | T9 | ✅ |
| §2.5 状态归属 | Cairn 拥有 Task/Budget/Event | T5/T8/T9 | ✅ |
| §2.6 Schema | 完整字段列表 | T2-T10 | ✅ |
| §3 CairnCore 纪律 | 零依赖,纯值,不 import 其他 | 所有 Task | ✅(只 import Foundation)|
| §7.2 时间格式 | ISO-8601 字符串 | T11 | ✅ |
| §8.4 M1.1 | ≥ 10 单测 | T12 目测 53 | ✅ 超量 |

**1 个 gap**:Approval 实体(spec §2.1 列出,v1.1 起用)—— spec §8.4 M1.1 没要求,且 v1.1 再说,**不补**。已记录在 Known limitations。

### 2. Placeholder 扫描

- "TBD" / "TODO" / "FIXME" / "implement later" / "appropriate" / "similar to" — 逐 Task 检查,无违规
- 所有代码块**完整**:Swift 源文件、测试文件、commit 命令、验证命令均可直接粘贴执行
- Self-Review §1 里的"(或 Claude 实际完成日)"是 T13 模板里的真正占位,执行时填日期,不是 plan 缺失

### 3. 类型 / 命名一致性

- `Workspace.id` / `Workspace.cwd` / `Workspace.lastActiveAt` — T2 定义,T11 使用,一致
- `Session.jsonlPath` / `Session.byteOffset` / `Session.lastLineNumber` — T4 定义,后续无修改
- `CairnTask.sessionIds: [UUID]` — T5 定义,T14 验收里未引用该字段(无引用错)
- `Event.type: EventType` + `Event.category: ToolCategory?` — T8 定义,匹配 T6/T7
- `ToolCategory.fileRead` 驼峰 vs `rawValue = "file_read"` snake_case — T7 tests 明确验证两种表示,一致
- `PlanStepStatus.inProgress` = `"in_progress"` rawValue — T10 tests 验证,与 Claude Code TodoWrite schema 一致
- `Budget.usedWallSeconds`(不是 `usedWallTime`)—— 与 spec §2.4 `maxWallTime: Int? // 秒` 对应但命名更清晰;SQLite schema(§D 附录)叫 `used_wall_seconds`,一致
- `CairnCore.jsonEncoder` / `jsonDecoder` — T11 定义,T14 验收未显式要求,但所有实体 round-trip 测试用它
- `Event.rawPayloadJson: String?` — T8 定义为 String,spec §2.6 写 `rawPayloadJson: JSON?`(抽象),T7 设计决策 #8 pin 为 String?,一致

### 4. 任务归属明确

- T1-T13 Claude 全做
- T14 用户执行 5 步验收
- 无模糊归属

### 5. 命令可执行性

- 所有 `swift test --filter` 命令 filter 名与 XCTestCase 类名一致
- `git add` 路径精确
- `git commit -m "..."` 里有多行 message,用 HEREDOC 风格嵌入(遵守 spec Git 纪律)

### 6. 潜在风险

**风险 1(低)**:Codable 合成对 `ToolCategory`(struct wrapping String)不能自动合成 —— Swift Codable 对 RawRepresentable 有内置规则,会 encode 为裸 String。T7 tests 有 `test_codable_roundTrip` 验证,若不工作会红。

**风险 2(低)**:Swift 5 模式下 Sendable 是 opt-in 声明,合成规则宽松;Swift 6 迁移(后续 milestone)可能需要 `@unchecked Sendable` 修复。M1.1 不处理。

**风险 3(低)**:`CairnTask` 这个名字可能让某些 Swift 用户疑惑,但文档注释解释了(设计决策 #4 + 源文件文档)。

### 7. 结论

Plan 完整可执行,设计决策 pinned,无 placeholder,命令可直接粘贴。
执行者按 T1-T13 走,T12 的 53 tests 全绿即 milestone 达成。
