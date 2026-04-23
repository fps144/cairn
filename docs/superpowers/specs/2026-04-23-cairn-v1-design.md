# Cairn v1 设计规范

| 字段 | 值 |
|---|---|
| 文档版本 | v1.0 (初稿) |
| 编写日期 | 2026-04-23 |
| 状态 | Draft(等待用户审阅) |
| 作者 | Claude (Opus 4.7) + sorain |
| 许可 | MIT(项目本身)|
| 目标交付 | Cairn v1.0(约 11 个月活跃开发,业余时间约 20-22 个月日历时间) |

---

## 摘要

**Cairn** 是一款 macOS 原生终端,专为 Claude Code 用户设计。它把每一次 Claude Code 会话自动记录为**结构化、可回放、可审查的任务轨迹**(Task Trace),让用户在长对话和多会话中不再"迷路"。

三个核心差异化:

1. **Task 是一等实体**(不只是 Workspace / Tab):以任务为单位组织代理工作,而不是以"目录"或"窗口"
2. **Event Timeline 结构化展现**:从 Claude Code 的 JSONL 转录文件中抽取 11 种结构化事件,配合工具分类体系,把"几千行滚动输出"变为"可扫视的卡片流"
3. **Budget pre-commitment**:任务级 token / 成本 / 时间预算,默认观察与告警(v1.1 起支持 Hook 强制)

Cairn **不修改** Claude Code 的任何数据文件,采用**观察者**模式(文件系统监听 + 可选 Hook),用户可以随时卸载 Cairn,Claude Code 完整可用。

技术栈:Swift 6 + SwiftUI + AppKit + SwiftTerm + GRDB + swift-log。单进程,纯本地。MIT 开源。

---

## 1. 项目身份与 v1 范围

### 1.1 名称与定位

**名称**:Cairn(/keɪrn/)—— 登山者沿路堆叠的石堆路标。语义对应"为 AI 代理的工作路径留下清晰、可追溯、可审查的轨迹"。

**一句话定位**:

> Cairn 是一款 macOS 原生终端,把 Claude Code 的每一次会话变成一条可读、可审查、可回放的任务轨迹。

### 1.2 目标用户

首批 100 人用户画像:

- 每天至少使用 1 小时 Claude Code 的中高级开发者
- 痛点:"代理干了一堆,滚 5000 行终端不知道具体做了什么、花了多少钱"
- 愿意替换 iTerm2 / Warp,前提是 day-1 体验就比旧工具强

### 1.3 许可证

**MIT License**。理由:
- 最大化采纳率
- 学习型项目不需要法律武器
- 未来若商业化,open-core 路径畅通(核心 MIT + 付费企业特性)

### 1.4 v1 范围(In)

1. 原生 macOS App(SwiftUI + AppKit 混合)
2. 内置终端(SwiftTerm)
3. 多标签页 + 水平分屏
4. **Task 侧边栏**(Workspace 分组)
5. **Event 时间线面板**(JSONL 监听,实时重建)
6. **Budget 显示**(token / 成本 / 时间)
7. **可选 Hook 集成**(用户 opt-in,路由高危工具到审批 UI)
8. **历史会话回放**(扫描 `~/.claude/projects/` 导入)

### 1.5 v1 范围(Out)

明确不做,留待 v2+:

- libghostty 集成(复杂度过高)
- 内置浏览器
- SSH 远程工作区
- 多 AI 工具适配器(Codex / Gemini / OpenCode)
- 深度 MCP Server 实现
- 云端同步 / 团队协作 / 远程沙箱
- 宠物 / 等级 / 游戏化元素
- 自定义主题系统
- i18n(v1 仅中英双语)
- 插件系统
- 自动更新(v1.1 集成 Sparkle)

### 1.6 成功判据

- 可在 macOS 14+ 稳定运行,不崩
- 作者本人能每日工作替代 iTerm2
- 从 v0.1 到 v1.0 积累 ≥ 300 stars,≥ 30 真实活跃用户
- 作者 Swift + macOS 原生 + AI 工具链集成能力从入门升至中级

---

## 2. 核心概念与数据模型

### 2.1 核心实体(8 个,v1 使用 7 个)

```
Workspace ──┬── 包含多个 ──> Tab
            │
            └── 包含多个 ──> Session ──> 包含多个 ──> Event
                                │
                                └──映射──> Task ──┬── 有一个 ──> Budget
                                                  │
                                                  └── 有一个 ──> Plan
                                
                                ──可选生成──> Approval(v1.1 起)
```

| 实体 | 含义 | 状态归属 |
|---|---|---|
| **Workspace** | 项目目录(cwd)+ 窗口/布局状态 | Cairn |
| **Tab** | 终端标签(= 1 PTY 进程 + 滚动缓冲) | Cairn |
| **Session** | Claude Code 会话(以 sessionId UUID 唯一) | Claude Code 拥有,Cairn 只观察 |
| **Task** | 用户意图工作单元(v1 实现为 1 Session = 1 Task) | Cairn |
| **Event** | 从 JSONL 抽出的结构化事件 | 源自 Claude Code,Cairn 缓存元数据 |
| **Budget** | 任务级预算(pre-commitment + 实际消耗) | Cairn |
| **Plan** | 从 `.claude/plans/*.md` 或 `TodoWrite` 派生 | Claude Code 拥有,Cairn 映射 |
| **Approval** | Hook 触发的审批决策记录(v1.1) | Cairn |

### 2.2 Session 与 Task 的关系

**核心设计**:Task 有多个 Sessions(1:N),v1 UI 默认自动创建 1:1 对应。

语义上:
- **Task** = 用户意图(持久,可能跨天)
- **Session** = 一次执行尝试(短暂,分钟-小时)

schema 从 day 1 就支持 `Task.sessions: [SessionID]`。v1 UI 每个新 Claude Code 会话自动创建一个 Task(title 从第一条用户消息抽取)。v1.5+ 支持"attach session to existing task"按钮。

**历史导入**:首次启动扫描 `~/.claude/projects/`,每个历史 Session 创建孤立 Task(status = `completed` 或 `abandoned`)。用户可在 UI 合并误拆的 Tasks。

### 2.3 Event 类型系统(两维设计)

**Event.type**:封闭集 **12 种**(v1 使用 10 种,2 种为 v1.1 预留)

| type | 来源 | v1 展示 |
|---|---|---|
| `user_message` | JSONL user message(非 tool_result) | ✅ |
| `assistant_text` | assistant text block | ✅ |
| `assistant_thinking` | assistant thinking block | ✅ 折叠 |
| `tool_use` | assistant tool_use block(所有工具) | ✅ 核心 |
| `tool_result` | user tool_result block | ✅ |
| `api_usage` | assistant message 的 usage 字段 | ✅ 驱动 Budget |
| `compact_boundary` | 非首条且 `parentUuid: null` | ✅ 标记 |
| `error` | `is_error: true` 的 tool_result / API 错误 | ✅ 高亮 |
| `plan_updated` | `.claude/plans/*.md` 变化 | ✅ |
| `session_boundary` | JSONL 文件打开/关闭 | ✅ |
| `approval_requested` | Hook 触发,等待审批(v1.1) | 🟡 预留 |
| `approval_decided` | Hook 审批完成(v1.1) | 🟡 预留 |

**Event.category**:开放集(仅 `type = tool_use` 使用,按 toolName 查表映射)

| category | 代表工具 | UI 建议 |
|---|---|---|
| `shell` | `Bash` | 灰,终端字体 |
| `file_read` | `Read`, `NotebookRead` | 蓝,文件图标 |
| `file_write` | `Write`, `Edit`, `NotebookEdit` | 橙,diff 预览 |
| `file_search` | `Glob`, `Grep` | 蓝,搜索图标 |
| `web_fetch` | `WebFetch`, `WebSearch` | 紫,🌐 |
| `mcp_call` | `mcp__*__*` | 青,🔌 |
| `subagent` | `Task`(Agent 工具) | 树缩进 |
| `todo` | `TodoWrite` | 黄,驱动 Plan |
| `plan_mgmt` | `EnterPlanMode` / `ExitPlanMode` | 折叠,状态条 |
| `ask_user` | `AskUserQuestion` | 高亮等待 |
| `ide` | `mcp__ide__*`, Figma 等 | 按源过滤 |
| `other` | 未分类 | 默认 |

### 2.4 Budget 模型

```
Budget {
  taskId: UUID
  
  // Pre-commitment(可选设定)
  maxInputTokens:  Int?
  maxOutputTokens: Int?
  maxCostUSD:      Double?
  maxWallTime:     Int?    // 秒
  
  // Actual(累加 api_usage 事件)
  usedInputTokens:  Int
  usedOutputTokens: Int
  usedCostUSD:      Double
  usedWallTime:     Int
  
  // State
  state: .normal | .warning80 | .exceeded | .paused
}
```

v1 行为:
- 80%:侧边栏黄色告警
- 100%:红色告警 + 桌面通知,**不打断**(v1 观察模式)
- v1.1 起 Hook 启用后:超额拦截写类工具,只允许只读继续

### 2.5 状态归属矩阵

| 状态 | 拥有者 | 失败容忍 |
|---|---|---|
| 终端 PTY / 滚动缓冲 | Cairn | 卡死 kill pty |
| 窗口/标签/分屏布局 | Cairn(SQLite) | 最后布局丢失可接受 |
| Claude Code session 状态 | Claude Code | Cairn 不应写 JSONL |
| Event 索引缓存 | Cairn(SQLite) | 可全量重建 |
| Task / Budget | Cairn(SQLite) | 关键,备份保护 |
| Approval 决策 | Cairn(SQLite) | 审计用,不可改写 |

**核心纪律**:Cairn 对 `~/.claude/` 的写入权限:

| 路径 | Cairn 权限 |
|---|---|
| `~/.claude/projects/**`(JSONL) | **永不写** |
| `~/.claude/plans/**` | **永不写** |
| `~/.claude/debug/**` / `errors/**` | **永不写** |
| `~/.claude/settings.json` 的 hook 字段 | **仅在用户显式 opt-in 单个 workspace 时写;只增不删;随时可撤销** |
| `~/.claude/settings.json` 其他字段 | **永不写** |

### 2.6 完整 Schema(核心字段)

```swift
// Workspace
{ id, name, cwd: Path, createdAt, lastActiveAt, archivedAt? }

// Tab
{ id, workspaceId, title, ptyPid: Int?, scrollBufferRef, state: .active|.closed }

// Session(Claude Code 会话 1:1)
{ id: UUID,                        // = Claude Code sessionId
  workspaceId, 
  jsonlPath: Path,
  startedAt, endedAt?: Date,
  byteOffset: Int64,               // 增量解析游标
  lastLineNumber: Int64,
  modelUsed: String?,
  isImported: Bool,
  state: .live|.idle|.ended|.abandoned|.crashed }

// Task
{ id, workspaceId, 
  title: String,                   // 从第一条 user_message 抽取
  intent: String?,                 // 用户手填 / LLM 提炼
  status: .active|.completed|.abandoned|.archived,
  sessionIds: [UUID],              // v1 长度恒为 1
  createdAt, updatedAt, completedAt? }

// Event
{ id, sessionId, 
  type: EventType,                 // 11 种封闭
  category: ToolCategory?,         // type=tool_use 时有值
  toolName: String?,
  toolUseId: String?,              // 配对 tool_use↔tool_result
  pairedEventId: UUID?,
  timestamp, 
  lineNumber: Int64,               // JSONL 主排序键
  blockIndex: Int,                 // 同行多 block 顺序
  summary: String,                 // ≤200 字摘要
  rawPayloadJson: JSON?,           // 完整数据,懒加载
  byteOffsetInJsonl: Int64? }

// Budget(见 2.4)

// Plan
{ id, taskId,
  source: .todoWrite | .planMd | .manual,
  steps: [PlanStep],               // [{id, content, status, priority}]
  markdownRaw: String?,
  updatedAt }
```

### 2.7 v1 故意不做的模型

- Multi-Agent 关系(cmux 的 swarm 模型):v1 每 Task 单一 Claude session
- Workspace 跨设备同步:纯本地
- Task 依赖图:任务间无关系,平级
- Verification 状态:Task 完成 = 会话结束,不判断实际是否成功(v2 加 build/test 绿灯)

---

## 3. 架构分层与模块划分

### 3.1 模块布局(SPM)

```
Cairn/
├── Package.swift
├── Sources/
│   ├── CairnCore/          纯 Swift 领域模型,无 UI / SQLite 依赖
│   ├── CairnStorage/       SQLite 层(GRDB)
│   ├── CairnClaude/        Claude Code 集成(JSONL / Plan / Hook)
│   ├── CairnTerminal/      SwiftTerm 封装 + PTY
│   ├── CairnServices/      业务编排(Task / Budget / Workspace)
│   ├── CairnUI/            SwiftUI 视图 + ViewModel
│   └── CairnApp/           可执行入口
├── Tests/
│   ├── CairnCoreTests/
│   ├── CairnStorageTests/
│   ├── CairnClaudeTests/   (最大,大量 JSONL fixture)
│   ├── CairnServicesTests/
│   └── CairnUITests/
└── Resources/
    ├── Assets.xcassets
    ├── Localizable.xcstrings
    └── Fixtures/           (测试用 Claude Code JSONL 样本)
```

### 3.2 依赖方向(编译器强制)

```
         CairnApp
            │
    ┌───────┴───────┐
    ▼               ▼
 CairnUI      CairnTerminal
    │
    ▼
CairnServices
    │
    ├───────────────┐
    ▼               ▼
CairnClaude         │
    │               │
    ▼               │
CairnStorage        │
    │               │
    ▼               ▼
       CairnCore(无依赖)
```

反向禁止(编译器保证):
- `CairnCore` 永不 import 其他
- `CairnStorage` 不 import Claude/Services/UI
- `CairnClaude` 不 import Services/UI
- UI 不直接 import `CairnStorage`,必须走 Services

### 3.3 核心数据流

```
JSONL 文件变化
  ↓
JSONLWatcher(三层兜底:FSEvents + vnode + 30s reconcile)
  ↓
EventIngestor(解析 + 映射 + 11 类型)
  ↓
CairnStorage(批量事务写入)
  ↓
EventBus(AsyncStream)
  ↓
TaskCoordinator / BudgetTracker(状态机)
  ↓
UI(@MainActor ViewModel + SwiftUI)
```

### 3.4 并发模型(Swift Concurrency)

| 组件 | 隔离 | 线程 |
|---|---|---|
| `JSONLWatcher` | `actor` | 后台 |
| `EventIngestor` | `actor` | 后台 |
| `CairnStorage` DAO | GRDB 内置 serial writer | DB 内部 |
| `TaskCoordinator` / `BudgetTracker` | `actor` | 后台 |
| `EventBus`(AsyncStream) | actor-safe | — |
| ViewModels | `@MainActor` | 主 |
| PTY IO | SwiftTerm 内置队列 | 后台 |

### 3.5 错误处理哲学

| 错误类型 | 处置 |
|---|---|
| JSONL 某行解析失败 | 记录 + 跳过,不阻塞后续 |
| JSONL 文件消失 | Session 标 `.abandoned`,UI 提示 |
| SQLite 写失败 | 重试 3 次,失败则暂存内存队列 + 通知 |
| PTY 子进程崩溃 | Tab 标红,提供重启按钮 |
| FSEvents 丢事件 | 30s 定时全量 reconcile 兜底 |

**总原则**:Cairn 是观察者,不因 Claude Code 异常而挂掉。Cairn 可用性下限 = Claude Code 自身下限。

### 3.6 外部依赖(v1 锁死三个)

| 依赖 | 用途 |
|---|---|
| **SwiftTerm** | 终端模拟器 |
| **GRDB.swift** | SQLite 封装 |
| **swift-log** | 结构化日志 |

v1 不加:Sparkle(v1.1)、Keychain、前端框架。

### 3.7 单进程架构(不分离 daemon)

Cairn 本身就是 App,所有 service 在 App 进程内,actor 做并发隔离。关 App = 停止观察。下次开 App 增量 reconcile 补齐。

---

## 4. Claude Code 集成机制

### 4.1 三条集成通路及 v1 决策

| 通路 | 优势 | 劣势 | v1 决策 |
|---|---|---|---|
| **① JSONL 文件监听** | 零侵入、数据最全、全版本兼容 | 延迟 300-800ms、只能观察 | ✅ **核心全量** |
| **② Hooks 注入** | 可执行前拦截审批 | 用户 opt-in + 写 settings.json | 🟡 **v1 提供开关默认关** |
| **③ MCP Server** | 结构化双向、Elicitation | 需改 Claude 配置、生命周期复杂 | ❌ **v1 不做,v2 再加** |

### 4.2 JSONLWatcher 三层兜底

```
Layer 1: FSEvents 监听 ~/.claude/projects/ (新文件发现 + 删除)
Layer 2: 对每个活跃 Session,DispatchSourceFileSystemObject (.write 精确触发)
Layer 3: 每 30 秒全量 reconcile(对比 mtime vs 数据库)
```

增量读取伪代码:

```swift
actor JSONLWatcher {
    func ingest(session: Session) async throws {
        let fh = FileHandle(forReadingAtPath: session.jsonlPath)
        try fh.seek(toOffset: session.byteOffset)
        let chunk = try fh.read(upToCount: 1_MB)
        guard let data = chunk else { return }
        
        let lines = data.split(separator: 0x0A)  // \n
        let isLastLineComplete = data.last == 0x0A
        let completeLines = isLastLineComplete ? lines : lines.dropLast()
        
        try await ingestor.ingest(lines: completeLines, session: session)
        session.byteOffset = startOffset + totalBytesOfCompleteLines
        try await store.saveSessionCursor(session)
    }
}
```

**关键约束**:永远不读半行;cursor 存盘供重启续读;按字节偏移。

### 4.3 JSONL → Event 映射规则

| JSONL entry 特征 | 映射 |
|---|---|
| `type: "user"` + 无 tool_result | `.user_message` |
| `type: "user"` + content[x] 是 tool_result | `.tool_result`(× N) |
| `type: "assistant"` + content[x] 是 text | `.assistant_text` |
| `type: "assistant"` + content[x] 是 thinking | `.assistant_thinking` |
| `type: "assistant"` + content[x] 是 tool_use | `.tool_use`(category 按 toolName 映射) |
| `type: "assistant"` + `message.usage` 非空 | 附带 `.api_usage` |
| `type: "attachment"` | v1 忽略 |
| `type: "system"` | 提取为 Session metadata,不进时间线 |
| `type: "custom-title"` | 更新 Task.title |
| `type: "tag"` | 提取为 Session tags |
| entry.parentUuid == null 且非首行 | 同时发 `.compact_boundary` |
| `is_error: true` | 同时发 `.error` |

### 4.4 Tool Use ↔ Tool Result 配对

```swift
struct InflightToolUse {
    let eventId: UUID
    let toolUseId: String
    let startTime: Date
}

// tool_use 到达: inflight[toolUseId] = ...
// tool_result 到达: paired = inflight[toolUseId]; 清除
// 重启: 从 DB 重建未配对 inflight
```

UI:配对的 use + result 折叠为一张工具卡片,默认一行摘要,点开展开。

### 4.5 Session 生命周期检测(启发式 + 辅助信号)

| 状态 | 判据 |
|---|---|
| `.live` | 文件 mtime 过去 60 秒内 |
| `.idle` | mtime 60s-5min,等待中 |
| `.ended` | mtime > 5min 且末条是 assistant(非悬挂 tool_use) |
| `.abandoned` | mtime > 30min 且末条含未完成 tool_use |
| `.crashed` | 文件被删除 |

辅助:PTY 层检测 `claude` 进程退出 → 立即标 `.ended`;`.live → .idle` 推送"等待输入中"通知。

### 4.6 PlanWatcher

监听每个 Workspace 的 `.claude/plans/` 目录。变化时:
1. 读取 plan.md
2. 与上次 diff 去重
3. v1 直接作为富文本展示(不解析 markdown)
4. 关联到当前活跃 Task
5. 发 `.plan_updated` Event

v1.5 考虑解析 checkbox `- [ ]` 成结构化 `PlanStep`。

### 4.7 HookManager(v1 提供开关,默认关)

**cairn-hook** 独立 CLI 可执行,打包在 App Bundle `Resources/cairn-hook`,≤ 200 行 Swift。

启用流程:
1. 用户点"Enable approval hooks"
2. 弹窗确认将写入 `.claude/settings.json` 的变更(仅增加 Cairn 条目)
3. 用户确认 → 写入
4. Cairn 启动 Unix socket 监听 `~/Library/Application Support/Cairn/hook-socket`

审批流:

```
Claude Code PreToolUse 触发
  → cairn-hook(stdin: tool_name + tool_input)
  → Cairn Main App(via Unix socket)
  → 查规则(白名单/黑名单/弹窗)
  → 返回决策(approve/deny/ask)
  → cairn-hook stdout → Claude Code
```

v1 规则(极简):
- 白名单:`Read`, `Glob`, `Grep`, `WebFetch`(用户可编辑)
- 黑名单:无
- 其他:弹窗确认

v1.5 扩展:正则匹配、cwd 规则、时间窗口豁免。

### 4.8 历史导入

首次启动自动:

```swift
func firstLaunchImport() async {
    let allJsonl = walk("~/.claude/projects/**/*.jsonl")
    await withTaskGroup { group in
        for file in allJsonl {
            await sem.wait()
            group.addTask {
                defer { sem.signal() }
                await importHistorical(file)  // 限并发 2
            }
        }
    }
}

func importHistorical(_ path: Path) async {
    let firstEntry = try readFirstLine(path)
    let cwd = firstEntry.system?.cwd ?? deriveWorkspaceFromHash(path)
    let ws = await workspaceStore.findOrCreate(cwd: cwd)
    let session = Session(/*isImported: true*/)
    await ingestor.ingestFull(session)
    await taskCoordinator.createTaskFor(session)
}
```

UI:启动时显示 "发现 42 个历史会话,正在导入 7/42",用户可"跳过"或"后台继续"。

### 4.9 Workspace ↔ Session 映射

3 层推断:
1. **优先**:读 JSONL 第一条 entry 的 `system.cwd`
2. **其次**:检查 `~/.claude/projects/.meta.json` 类映射(实际跑一次确认 schema)
3. **兜底**:询问用户,一次标注后记住

Phase 0 的 probe 脚本会搞清楚真实格式。

### 4.10 已知边界情况

| 场景 | 处置 |
|---|---|
| 用户在 iTerm2 和 Cairn 同时跑 Claude | 兼容。Cairn 只观察 JSONL,不关心终端宿主 |
| 同时开 3 个 Claude Session | 三个 Session 并行监听,三个 Task 同时活跃 |
| Claude 做了 context compact | 发 `.compact_boundary`,UI 渲染折叠分割线 |

---

## 5. 终端引擎与 PTY 管理

### 5.1 SwiftTerm 接入

用 `LocalProcessTerminalView`(SwiftTerm 的高级封装),通过 `NSViewRepresentable` 套进 SwiftUI。

```swift
struct TerminalSurface: NSViewRepresentable {
    let session: TerminalSession
    
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.startProcess(
            executable: session.shell,
            args: [],
            environment: session.env,
            execName: nil
        )
        return view
    }
    
    class Coordinator: LocalProcessTerminalViewDelegate { ... }
}
```

### 5.2 PTY 生命周期(SwiftTerm 托管)

- **创建**:`⌘T` → `TerminalSession` 对象 → `LocalProcessTerminalView.startProcess` (forkpty + execve)
- **IO**:SwiftTerm 后台线程读 master fd,用户输入 → master fd
- **退出**:`processTerminated` delegate → Tab 关闭
- **强杀**:`view.process.terminate(kill)`

### 5.3 Tab / Split 架构

```
MainWindow
 └── WorkspaceView
      └── SplitView (水平)
           ├── TabGroupView (左)
           │    ├── Tab 1: TerminalSurface
           │    └── Tab 2: ...
           └── TabGroupView (右,可选)
```

v1 约束:
- 最多水平 2 分屏,每侧多 tab
- 不做垂直分屏(v1.1)
- 不做任意嵌套

`LayoutState` 用 `@Observable`,存 SQLite `layout_states` 表,重启恢复。

### 5.4 Tab ↔ Session 关联(启发式)

```
Tab (PTY 输出匹配 "Claude Code" 启动横幅)
  → 标 Tab 为 pending-claude,记 claudeDetectedAt
  
JSONLWatcher(独立)
  → 新 JSONL 文件出现(cwd, timestamp)
  → 查询 pending Tabs 匹配:
      - Tab.cwd == JSONL.cwd
      - |JSONL.timestamp - Tab.claudeDetectedAt| < 5s
  → 唯一匹配:绑定;多/无匹配:孤立 Session,用户手动认领
```

v1 方案 A(PTY 输出横幅匹配)。v1.1 加方案 B(`ps` 扫描 PTY 子进程)提高准确度。

### 5.5 OSC 7 CWD 跟踪(必做)

Tab 的 cwd 不能靠启动写死。现代 shell 发 OSC 7:

```
\033]7;file://hostname/path/to/dir\007
```

SwiftTerm delegate:

```swift
func hostCurrentDirectoryUpdated(source: TerminalView) {
    let newCwd = parseOSC7(source.hostCurrentDirectory)
    tabSession.updateCwd(newCwd)
}
```

**兜底**:新 Tab 启动时向环境变量注入 `chpwd_hook` for zsh/bash(用户可关)。

### 5.6 滚动缓冲与重启

v1 决定:**不持久化滚动缓冲,只持久化布局 + cwd**。

理由:ANSI 缓冲持久化复杂;用户真实需求是"重开回到同 cwd",不是"逐字节恢复"。

重启流程:
1. 读 `LayoutState` 重建窗口/tab
2. 每个 Tab 用保存的 cwd + shell 重启 PTY
3. 空终端但目录正确
4. 历史 Session(Task)完整可回放(JSONL 在硬盘)

### 5.7 v1 终端功能边界

| 功能 | v1 |
|---|---|
| 基础终端 / ANSI / 颜色 | ✅ |
| 多 Tab | ✅ |
| 水平分屏 | ✅ |
| 垂直分屏 | ❌ v1.1 |
| 复制粘贴 | ✅ |
| 字体大小调节 | ✅ |
| 终端内搜索 `⌘F` | 🟡 |
| OSC 7 cwd 跟踪 | ✅ |
| OSC 52 剪贴板 | ✅ |
| OSC 133 提示符 | 🟡 识别不导航 |
| iTerm2 图像协议 | ❌ v1.1 |
| vi-mode 复制 | ❌ v1.2 |
| 跨 tab 广播输入 | ❌ v2 |
| 自定义主题 | ❌ v1 用 Dark + Light |

---

## 6. UI 布局与交互

### 6.1 主窗口三区布局

```
┌─ Toolbar ───────────────────────────────────────────────────┐
│ ▼ Workspace   🔔 ⚙    ⌘1 task · ⌘2 task                      │
├──────────┬──────────────────────────────┬───────────────────┤
│ Sidebar  │  Main Area                   │  Right Panel      │
│ (280px,  │  (flex)                      │  (360px,          │
│ 可折叠   │                              │  可折叠 ⌘I)       │
│ ⌘⇧T)     │  Tab Bar                     │                   │
│          │  Terminal                    │  Current Task     │
│ Tasks    │  (SwiftTerm)                 │  Budget           │
│ 按 Ws    │                              │  Timeline         │
│ 分组     │                              │                   │
│          │  Status Bar (cwd, branch)    │                   │
└──────────┴──────────────────────────────┴───────────────────┘
```

### 6.2 Sidebar(Task 一等,Workspace 分组)

Task 条目显示:
- 状态图标:● running / ○ completed / ◐ paused / ⊘ exceeded / ✗ failed
- Title(前 40 字)
- Budget 百分比(有预算时,颜色编码)
- 时间戳("12m" / "— 2d")

交互:
- 点击 → 切换活跃 Task
- 双击 → 新窗口(v1.5)
- 右键 → 归档 / 合并 / 重命名 / 导出
- 拖拽到另 Workspace → 迁移(v1.1)

筛选栏:搜索 + 状态过滤 + 时间过滤。

### 6.3 Main Area(v1 只放终端)

v1 主区域**只放终端**,不允许 Event Timeline 占主区。

Tab 行为:
- `⌘T`:新 Tab
- `⌘W`:关 Tab
- `⌘⇧D`:水平分屏
- `⌘L` / `⌃⇥`:循环切换

Tab 颜色左窄边框:
- 灰:普通 shell
- 蓝:检测 Claude 在跑
- 橙:等待用户输入
- 红:检测到错误

Tab 上 ▲ 图标:关联 Task 有新事件。

### 6.4 Event Timeline 视觉语言

默认折叠卡片流,点 ▸ 展开:

| Event category | 图标 | 颜色 |
|---|---|---|
| user_message | 👤 | 灰 |
| assistant_text | 💬 | 默认 |
| assistant_thinking | 💭 | 灰,折叠 |
| shell | 🔧 | 灰底 |
| file_read | 📖 | 蓝 |
| file_write | ✏️ | 橙 |
| file_search | 🔍 | 蓝 |
| web_fetch | 🌐 | 紫 |
| mcp_call | 🔌 | 青 |
| subagent | 🧬 | 洋红 |
| todo | 📋 | 黄 |
| ask_user | ❓ | 橙 |
| error | ⚠️ | 红 |
| api_usage | 💰 | 绿(悄悄) |
| compact_boundary | ─── | 灰 divider |

连续同类合并("Read × 3",展开看详情)。底部 `⋮ live` 实时指示。

### 6.5 Plan / Todo 面板

```
📋 JWT 认证重构
From TodoWrite

✅ 1. 调研现有 session 实现
✅ 2. 设计 JWT payload
● 3. 替换 session.ts → jwt        ← 脉动动画
○ 4. 更新所有中间件
○ 5. 跑完整 auth 测试套件
```

v1 只读,v1.5 允许手动编辑。

### 6.6 Budget 呈现

小预览:`💰 $0.68 / $5.00 ▓▓░░░░░░ 14%`

详细展开:
- Cost / Input / Output / Wall-time
- 各自占比 + 颜色(绿/黄/红)
- Model 标识
- Last API call 相对时间
- [编辑预算] [重置]

### 6.7 v1 键盘快捷键(17 个,克制)

| 快捷键 | 功能 |
|---|---|
| `⌘T` | 新建 Tab |
| `⌘W` | 关闭 Tab |
| `⌘⇧D` | 水平分屏 |
| `⌘L` / `⌘⇧L` | 下一个 / 上一个 Tab |
| `⌘1`-`⌘9` | 跳到第 N 个 Task |
| `⌘K` | 清空终端 |
| `⌘F` | 终端搜索 |
| `⌘⇧T` | 切换 Sidebar |
| `⌘I` | 切换 Right Panel |
| `⌘⇧E` | 展开/折叠所有 Events |
| `⌘⇧B` | 展开 Budget 详情 |
| `⌘N` | 新建 Workspace |
| `⌘,` | 设置 |
| `⌘+` / `⌘-` | 字体 |
| `⌘0` | 重置字体 |
| `⌘Q` | 退出 |

**不加**:命令面板(v1.1)、和弦(v1.2)、自定义绑定(v1.5)。

### 6.8 主题与字体

- Dark(默认)+ Light,仅这两个
- 默认字体 `SF Mono`,可选 `JetBrains Mono` / `Fira Code` / `Menlo`
- v1 不做自定义主题、不读 Ghostty 配置、不做 ligature 开关

### 6.9 UI 纪律

1. 本地化:所有用户字符串 `String(localized:)`,键放 `Localizable.xcstrings`
2. 可访问性:按钮有 `accessibilityLabel`,对比度 ≥ 4.5:1
3. 快捷键:新增必须登记到 `KeyboardShortcutSettings`(为 v1.5 留接口)
4. 空状态:每 View 定义 loading / empty / error 三态
5. 性能:Timeline > 500 Event 启 LazyVStack;Sidebar > 100 Task 虚拟滚动

---

## 7. 持久化与状态恢复

### 7.1 存储位置

```
~/Library/Application Support/Cairn/
├── cairn.sqlite            (WAL 模式)
├── cairn.sqlite-wal
├── cairn.sqlite-shm
├── logs/
│   ├── cairn.log
│   └── cairn.log.YYYYMMDD
├── hook-socket             (Unix socket,hook IPC)
└── backups/                (每周自动,保留最近 4 份)
    └── cairn-YYYYMMDD.sqlite.gz

~/Library/Preferences/com.cairn.app.plist   (App 配置)
~/Library/Caches/Cairn/                     (可删缓存)
```

### 7.2 完整 SQLite Schema(11 张表)

见附录 D(full SQL)。核心表:

- `workspaces`
- `sessions`(含 byte_offset 增量游标)
- `tasks`
- `task_sessions`(N:M 关联表,v1 恒 1:1)
- `events`(含 raw_payload_json,索引 session+line+block_index)
- `budgets`
- `plans`
- `layout_states`
- `approvals`(v1.1 启用)
- `settings`(key-value)
- `schema_versions`(migration 追踪)

Schema 纪律:
- 每个 FK 显式 `ON DELETE CASCADE`
- JSON 列后缀 `_json`
- 时间列一律 ISO-8601 字符串
- 索引查询驱动

### 7.3 Migration 策略

GRDB `DatabaseMigrator`,append-only。每次迁移前自动备份到 `backups/pre-migration-{v}.sqlite.gz`。破坏性变更走"建新表 → 复制 → 重命名"。

### 7.4 数据量与归档

10 session/日的用户 1 年:~1M events,~570MB summary + 2-5GB raw_payload。

**raw_payload 归档**:
- 0-90 天:存 SQLite
- 90 天后:后台任务置 NULL,依赖 `byte_offset_in_jsonl` 从 JSONL 懒加载
- JSONL 被用户删:展开提示"原始数据不可用"

目标:SQLite ≤ 1GB/年。

### 7.5 重启恢复清单

| 项 | 恢复 |
|---|---|
| 窗口大小/位置 | ✅ |
| Workspace 列表 | ✅ |
| 当前活跃 Workspace | ✅ |
| Tab 布局 + cwd | ✅ |
| Task 列表与状态 | ✅ |
| Budget 累计 | ✅ |
| Plan 状态 | ✅ |
| Event Timeline 可回放 | ✅ |
| PTY 活跃进程 | ❌ |
| 终端滚动缓冲 | ❌ |
| Panel 开关 | ✅ |
| Timeline 滚动位置 | 🟡 尽力而为 |

启动流程:
1. 打开 DB,跑 migration
2. 读 settings / workspaces / layout_states
3. 还原窗口 + 工作区
4. 每 Tab 重启 shell(cwd 正确)
5. 后台扫描 `~/.claude/projects/`:已知 session 继续增量,新 session 创建 Session 记录
6. UI 显示,底部状态条提示 "Syncing 2 sessions..."

### 7.6 备份与导出

v1 提供:
- 自动周备份(每周日凌晨,保留最近 4 份)
- 手动备份(设置 > 数据)
- 诊断包导出(日志 + 最近 1000 events 摘要 + 配置,**不含 JSONL 内容**)
- 备份恢复(替换前先存 `backups/before-restore.sqlite.gz`)

v1.5:单 Task 导出(zip)、iCloud Drive 跨机器恢复。

### 7.7 隐私

三条硬原则:

1. **默认零遥测**。第一次启动不推送任何数据。设置里可开 PostHog/Sentry,文案列举上报字段。
2. **JSONL 不复制,只索引**。SQLite 存 summary + byte_offset。用户删 JSONL 自动标记"原始不可用"。
3. **导出包警告**。"可能含源代码、命令历史,勿上传不信任地方。"

Keychain:v1 不存 secret,不用 Keychain。

### 7.8 性能纪律

| 路径 | 纪律 |
|---|---|
| Event 写入 | 事务批量,单事务 ≤ 500 条 |
| Event 查询(Timeline) | 分页 100 条 |
| Task 列表 | 按状态预过滤,> 100 虚拟滚动 |
| Session 游标 | 节流:同 session ≤ 1 次/秒 |
| raw_payload 懒加载 | UI 展开时才 SELECT |
| 启动 reconcile | `.utility` 优先级,不阻塞 UI |
| SQLite PRAGMA | `journal_mode=WAL; synchronous=NORMAL; cache_size=-64000` |

---

## 8. 路线图与里程碑

### 8.1 三次发布

```
v0.1 Beta       v0.5            v1.0
Observable      Task Layer      Polish + 公证
Terminal        
~6 月活跃        ~9 月           ~11 月活跃
~12 月日历       ~18 月           ~22 月日历(业余 ~50% 效率)
```

(活跃开发 = 真正写代码的工作周对应的时长。业余时间项目按 50% 效率估算日历时间。)

### 8.2 四阶段

| 阶段 | 活跃周 | 产出 | 发布 |
|---|---|---|---|
| Phase 0 · 探路 | 2w | 环境 + JSONL 勘察 | — |
| Phase 1 · 终端基座 | 10w | 原生终端 + Tab/分屏 | — |
| Phase 2 · Claude 观察 | 12w | JSONL → Timeline | **v0.1 Beta** |
| Phase 3 · Task 层 | 12w | Task/Budget/Plan 完整 | **v0.5** |
| Phase 4 · 发布 | 8w | 公证 + Homebrew + 文档 | **v1.0** |
| **总** | **44w** | | |

### 8.3 Phase 0:探路(2 周)

#### M0.1(W1):开发环境 + JSONL 勘察

| 任务 | 产出 |
|---|---|
| Xcode 安装 + 命令行工具 | `xcodebuild -version` 正常 |
| GitHub repo `cairn` + MIT LICENSE | 初始 commit |
| 用户跑 3-5 个真实 Claude 会话 | `~/.claude/projects/` 有内容 |
| probe 脚本 | `probe-report.md` |
| 对比 Section 4 映射表 | 差异清单 |

probe 脚本产出:
- 真实 `system.cwd` 字段位置
- `usage` 精确 schema
- 未预料的 entry type
- JSONL 大小分布

#### M0.2(W2):Hello World

| 任务 | 产出 |
|---|---|
| `Package.swift` 最小化 | `swift build` 成功 |
| 最小 SwiftUI App | 空窗口 |
| SwiftTerm 嵌入跑 zsh | echo 回显 |
| `.gitignore` | git status 干净 |

### 8.4 Phase 1:终端基座(10w)

| M | W | 内容 | 产物 |
|---|---|---|---|
| M1.1 | 3-4 | 6 模块骨架 + CairnCore 类型 + 10 单测 | 编译通过 |
| M1.2 | 5-6 | CairnStorage + GRDB + 11 表 + migrator | schema_versions v1 写入 |
| M1.3 | 7-8 | 主窗口三区 + 侧边栏/Panel 可折叠 | Section 6 壳子 |
| M1.4 | 9-10 | 多 Tab + TerminalSurface + PTY | ⌘T/⌘W/⌘L 可用 |
| M1.5 | 11-12 | 水平分屏 + OSC 7 + 布局持久化 | 重启布局完整 |

Phase 1 验收:能替代 iTerm2 日常用的原生终端(无 AI 集成)。

### 8.5 Phase 2:Claude 观察(12w)→ v0.1 Beta

| M | W | 内容 |
|---|---|---|
| M2.1 | 13-14 | JSONLWatcher 三层 |
| M2.2 | 15-16 | JSONLParser 11 种映射 + tool pairing + 10 fixture |
| M2.3 | 17-18 | EventIngestor 批量事务 + cursor 推进 |
| M2.4 | 19-20 | AsyncStream EventBus + 基础 Timeline |
| M2.5 | 21-22 | 工具卡片合并 + 视觉语言实现 |
| M2.6 | 23-24 | Session 生命周期 + Tab↔Session 关联 + Beta 打磨 |

v0.1 Beta 首发:GitHub Release 未公证 DMG;README 教 `xattr`;HN + X + Claude Discord;目标 2 周 100 stars + 20 用户 + 10 issues。

v0.1 明确不含:Task 概念、Budget、Plan、历史导入。卖点:"能把 Claude Code 输出结构化呈现的终端"。

### 8.6 Phase 3:Task 层(12w)→ v0.5

| M | W | 内容 |
|---|---|---|
| M3.1 | 25-26 | Task 实体 + Session 自动建 Task + sidebar |
| M3.2 | 27-28 | Task 详情 Panel + 状态机 + 用户操作 |
| M3.3 | 29-30 | BudgetTracker + 预算 UI + 告警 |
| M3.4 | 31-32 | Plan 从 TodoWrite + plan.md 双源 + Panel |
| M3.5 | 33-34 | Workspace 管理 + 多 Workspace 隔离 |
| M3.6 | 35-36 | 历史导入 + v0.5 发布 |

v0.5 目标:500 stars, 100 活跃用户, 5-10 外部贡献者。

### 8.7 Phase 4:抛光(8w)→ v1.0

| M | W | 内容 |
|---|---|---|
| M4.1 | 37-38 | 设置页 + 遥测开关 + 本地化 |
| M4.2 | 39-40 | 诊断导出 + 周备份 + CI |
| M4.3 | 41-42 | 代码签名 + Notarization + Sparkle(**需决定 $99/年**) |
| M4.4 | 43-44 | Homebrew Cask + 官网 + 文档 + v1.0 |

### 8.8 分工

| Claude | sorain |
|---|---|
| M 开始时出详细 TODO + 验收标准 | 读设计 + 提问 |
| 写核心骨架 + 难点(并发、FSEvents、Parser) | 写增量/样板代码 |
| Code review(PR 审阅) | 运行、测试、观察 bug |
| 架构级技术文档 | 用户文档(README、安装) |
| 疑难杂症(SwiftTerm 崩、SQLite 锁) | 业务逻辑(UI 细节) |

### 8.9 外部成本

| 项 | 必要 | 成本 | 时机 |
|---|---|---|---|
| Xcode | ✅ | $0 | 现在 |
| GitHub 免费 | ✅ | $0 | M0.1 |
| 免费 Apple ID | ✅ | $0 | M0.2 |
| **Apple Developer** | **❌ 非必需** | $99/年 | v0.5 后按需 |
| 域名 | 🟡 | $10-100/年 | v0.5 前 |
| Homebrew Tap | ✅ | $0 | M4.4 |
| GitHub Actions CI | ✅ | $0(公开 repo) | M4.2 |

**Apple Developer 决策逻辑**:
- v0.1 Beta:路径 A(未签名 + xattr 指南),$0
- v0.5:根据用户反馈决定是否升级为路径 C(Developer ID + Notarization)

### 8.10 风险清单

| 风险 | 概率 | 应对 |
|---|---|---|
| JSONL schema 变化 | 中 | probe + fixture + 兼容矩阵 |
| 用户时间断档 | 高 | v0.1 Beta 6 个月可达,止损点清晰 |
| SwiftTerm 致命 bug | 低 | 分层设计,可切 libghostty |
| SQLite 大数据量性能 | 低 | 归档 + 索引 + 分页 |
| 被 cmux/codux 抄设计 | 中 | 差异化靠执行 + 社区,不藏 |
| macOS 新版破坏 API | 中 | 每 M 在最新 Xcode beta 跑 |

---

## 9. 协作方式与学习节奏

### 9.1 Milestone 协作节奏

**Day 1**:Claude 出 TODO 清单 + 骨架代码 + 列"本 M 学的概念 1-3 个"。用户读 PR,提问,本地跑。

**Day 2-13**:用户按 TODO 实现,每 TODO 一 commit,每天 push。卡 > 30min 立刻问。Claude 每次 push 做 review(分"必改/建议/吐槽")。

**Day 14**:一起 Demo,验收,写 retro,更新 `learning-log.md`,merge + tag。

### 9.2 Git 工作流

- `main` 永远 green
- feature 分支 `feature/mX-Y-topic`
- 每个 TODO 一个小 commit
- 完成后 PR → main
- 不 `git push --force` 到 main

Commit 规范:一行摘要 ≤ 50 字,正文描述**为什么**。

三条铁律:
1. `main` 永远能编译 + 单测绿,坏了立刻 revert
2. 依赖变更必须独立 commit 且 PR 高亮
3. 依赖变更需事前批准

### 9.3 代码风格(以教为目的)

- 函数短(目标 ≤ 30 行)
- 命名长而直白
- 注释只写"为什么"
- 每个新概念只引入一次
- 错误信息要有内容
- **严禁 Phase 1 就搞协议接口 + 工厂模式**(YAGNI 写进 CONTRIBUTING.md)

### 9.4 用户参与要求

必做:
- 每个 PR 至少读 3 遍
- 敢于质疑
- 自己跑起来
- 每 M 更新 `docs/learning-log.md`

禁止:
- 不问就合并看不懂的代码
- 沉默消失 3 周
- 绕过设计决策私自加东西

### 9.5 学习路径

**Phase 0-1**:Swift 官方 Language Guide 1-10 章 + SwiftUI Tutorial Essentials + Paul Hudson Hacking with Swift(查漏补缺)

**Phase 2**:WWDC Meet async/await + Swift Concurrency 官方 + GRDB README

**Phase 3-4**:WWDC 2024/2025 SwiftUI 按需 + Notarization 文档(M4.3 前)

不推荐:先学后做的教程模式;付费课程;iOS 教程(macOS 不同)。

### 9.6 何时问 / 何时做

| 情况 | 动作 |
|---|---|
| 不懂语法 | 查文档 5 分钟,解决不了问 |
| 不懂设计 | 立刻问 |
| 卡 > 30 分钟 | 停下问 |
| 加新依赖 | 必须先问 |
| 改架构 | 必须先问 |
| 遇到违反设计的需求 | 开 issue 讨论 |
| bug 能复现 | 尝试自修 → PR → review |
| bug 不能复现 | 记 `docs/bugs/` |

### 9.7 docs 结构

```
docs/
├── superpowers/
│   ├── specs/           设计文档(本文件)
│   └── plans/           实施计划(writing-plans 产出)
├── architecture.md      活文档,随开发更新
├── api-contracts.md     内部协议契约
├── learning-log.md      用户学习日志(按周)
├── bugs/                无法立即修的 bug
├── decisions/           ADR 风格重要决策记录
└── CONTRIBUTING.md      v0.5 开源前写
```

### 9.8 项目健康度信号

| 灯 | 条件 | 动作 |
|---|---|---|
| 🟢 | 每周 ≥ 1 commit + M 按时 + main 绿 + log 更新 | 继续 |
| 🟡 | 2 周无 push / M 超时 50% / log 3 周未更新 | Claude 主动问,retro,砍范围 |
| 🔴 | 4 周无 push 且不回应 / main 崩 3 天 | 项目转保留状态 |

### 9.9 动摇时的应对

| 情况 | 应对 |
|---|---|
| 太忙继续不下去 | 一起砍范围。v0.1 Beta 就停也有价值 |
| 失去信心 | Retro,方向错?暂时疲劳?必要时 pivot |
| 有人要加入 | v0.5 前单人推,之后纳入 |
| Claude 帮不动了 | 设计层已覆盖难点,真出现停下重设计 |

### 9.10 Claude 的承诺

1. 不替用户决策,给选项 + 建议
2. 坦白不知道的事,先验证再答
3. 不糊弄性产出代码
4. 设计错会承认并重来
5. 不让项目陷入"我写你不懂"

---

## 附录 A:关键决策记录

| # | 决策 | 选择 | 关键理由 |
|---|---|---|---|
| A1 | 终端引擎 | SwiftTerm(非 libghostty) | 纯 Swift,learner 友好,v1.5 可切换 |
| A2 | 构建系统 | SPM 多模块(非单 target) | 编译器强制分层,教学价值 |
| A3 | Session vs Task | Task has-many Sessions(v1 默认 1:1) | 语义正确,schema 向前兼容 |
| A4 | AI 集成通路 | JSONL 主 + Hook 可选 + MCP 不做 | 零侵入,稳定性可控 |
| A5 | 远程能力 | v1 不做(纯本地) | cmux 的 Go daemon 对学习项目过重 |
| A6 | 许可证 | MIT | 最大化采纳,open-core 路径畅通 |
| A7 | Budget 强制 | v1 观察,v1.1 Hook 强制 | 不 patch Claude,零侵入 |
| A8 | 游戏化 | 不做(宠物/等级) | 专业工具,Codux 前车之鉴 |
| A9 | Apple Developer | v0.5 后按需 | 先验证价值再花钱 |
| A10 | UI 布局 | 三区(Sidebar/Main/Panel),主区只放终端 | 保持"终端首先是终端"心智 |
| A11 | Event 类型 | type 封闭 12 种 + category 开放 | 结构稳定,扩展灵活 |
| A12 | 存储方案 | SQLite + raw_payload 90 天归档 | 稳定 ≤ 1GB/年 |

---

## 附录 B:Phase 0 待验证问题清单

probe 脚本**必须**在 Phase 0 回答的问题:

1. JSONL 第一条 entry 是否含 `system.cwd` 字段?若是,精确字段路径?
2. `message.usage` 精确 schema(input_tokens / output_tokens / cache 等)?
3. `~/.claude/projects/{hash}/` 的 hash 规则?是否可从 cwd 计算?
4. 是否存在 `~/.claude/projects/.meta.json` 类映射文件?
5. 是否有 Section 4.3 未列出的 entry type 出现?
6. JSONL 文件大小分布(P50 / P90 / P99)?
7. Claude Code 退出时是否写 end 标记?
8. `.claude/plans/` 目录结构与文件命名规则?
9. Hook 配置(`.claude/settings.json`)的精确 schema?
10. 大文件(多 MB)的 ingest 性能上限?

所有问题在 `probe-report.md` 中回答后,回到 Section 4 / 7 做必要修订。

---

## 附录 C:术语表

| 术语 | 定义 |
|---|---|
| **Workspace** | Cairn 中一个项目的根目录 + 关联窗口/布局状态 |
| **Tab** | 一个终端标签,对应一个 PTY 子进程 |
| **Session** | 一次 Claude Code 会话,以 Claude 的 sessionId UUID 唯一标识 |
| **Task** | 用户的意图工作单元,v1 对应一个 Session |
| **Event** | 从 JSONL 抽取的结构化单元,12 种 type(v1 活跃 10 种,v1.1 增加 2 种) |
| **Category** | 仅 `tool_use` 类 Event 的子分类,按 toolName 映射 |
| **Budget** | 任务级 token/成本/时间预算,pre-commitment + 实际 |
| **Plan** | Task 的执行计划,来自 TodoWrite 或 plan.md |
| **Approval** | Hook 触发的审批决策记录(v1.1) |
| **JSONL** | Claude Code 的会话转录格式,每行一 JSON |
| **cursor** | Session 的字节偏移,用于增量解析 |
| **Hook** | Claude Code 在工具执行前后调用的用户脚本 |
| **MCP** | Model Context Protocol,Claude Code 的工具协议 |

---

## 附录 D:SQLite 完整 Schema

```sql
-- 核心实体
CREATE TABLE workspaces (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  cwd TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP NOT NULL,
  last_active_at TIMESTAMP NOT NULL,
  archived_at TIMESTAMP
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  jsonl_path TEXT NOT NULL,
  byte_offset INTEGER DEFAULT 0,
  last_line_number INTEGER DEFAULT 0,
  started_at TIMESTAMP NOT NULL,
  ended_at TIMESTAMP,
  state TEXT NOT NULL,
  model_used TEXT,
  is_imported INTEGER DEFAULT 0,
  created_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_sessions_workspace ON sessions(workspace_id);
CREATE INDEX idx_sessions_state ON sessions(state) WHERE state IN ('live','idle');

CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id),
  title TEXT NOT NULL,
  intent TEXT,
  status TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  completed_at TIMESTAMP
);
CREATE INDEX idx_tasks_workspace_status ON tasks(workspace_id, status);

CREATE TABLE task_sessions (
  task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
  session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE,
  attached_at TIMESTAMP NOT NULL,
  PRIMARY KEY (task_id, session_id)
);

-- 衍生数据
CREATE TABLE events (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  category TEXT,
  tool_name TEXT,
  tool_use_id TEXT,
  paired_event_id TEXT,
  timestamp TIMESTAMP NOT NULL,
  line_number INTEGER NOT NULL,
  block_index INTEGER DEFAULT 0,
  summary TEXT NOT NULL,
  raw_payload_json TEXT,
  byte_offset_in_jsonl INTEGER
);
CREATE INDEX idx_events_session_seq ON events(session_id, line_number, block_index);
CREATE INDEX idx_events_tool_use_id ON events(tool_use_id) WHERE tool_use_id IS NOT NULL;
CREATE INDEX idx_events_type ON events(session_id, type);

CREATE TABLE budgets (
  task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,
  max_input_tokens INTEGER,
  max_output_tokens INTEGER,
  max_cost_usd REAL,
  max_wall_seconds INTEGER,
  used_input_tokens INTEGER DEFAULT 0,
  used_output_tokens INTEGER DEFAULT 0,
  used_cost_usd REAL DEFAULT 0,
  used_wall_seconds INTEGER DEFAULT 0,
  state TEXT DEFAULT 'normal',
  updated_at TIMESTAMP NOT NULL
);

CREATE TABLE plans (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  source TEXT NOT NULL,
  steps_json TEXT NOT NULL,
  markdown_raw TEXT,
  updated_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_plans_task ON plans(task_id, updated_at DESC);

-- UI 状态
CREATE TABLE layout_states (
  workspace_id TEXT PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
  layout_json TEXT NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- v1.1 预留
CREATE TABLE approvals (
  id TEXT PRIMARY KEY,
  session_id TEXT REFERENCES sessions(id),
  tool_name TEXT NOT NULL,
  tool_input_json TEXT NOT NULL,
  decision TEXT NOT NULL,
  decided_by TEXT NOT NULL,
  decided_at TIMESTAMP NOT NULL,
  reason TEXT
);

-- 基础设施
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE TABLE schema_versions (
  version INTEGER PRIMARY KEY,
  applied_at TIMESTAMP NOT NULL,
  description TEXT
);
INSERT INTO schema_versions VALUES (1, CURRENT_TIMESTAMP, 'v1.0 initial schema');
```

---

**文档结束。**

下一步:
1. 用户审阅本 spec,提修改意见或确认通过
2. 通过后调用 `writing-plans` 技能,产出 **M0.1(W1:开发环境 + JSONL 勘察)** 的详细实施计划
3. 按计划开始 Phase 0 工作
