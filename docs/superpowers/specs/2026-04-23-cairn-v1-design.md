# Cairn v1 设计规范

| 字段 | 值 |
|---|---|
| 文档版本 | v1.0 (初稿) |
| 编写日期 | 2026-04-23 |
| 状态 | Draft(等待用户审阅) |
| 作者 | Claude (Opus 4.7) + sorain |
| 许可 | MIT(项目本身)|
| 目标交付 | Cairn v1.0(Claude 主导开发,预计 5-8 个月日历时间,取决于用户验收 session 频率) |
| 定位 | **生产级开源项目**(非学习项目)· 永不签名分发(xattr 路线) |
| 开发模式 | **Claude 全权主导开发,用户仅做产品决策 + milestone 验收** |

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

### 1.6 成功判据(生产级开源项目标准)

**产品侧**:

- macOS 14+ 稳定运行,空闲 CPU < 1%
- 用户本人可每日用它替代 iTerm2 / Warp
- v1.0 首月积累 ≥ 500 GitHub stars,≥ 100 真实活跃用户
- HN / Product Hunt 首发周内进入当天前 20 条

**代码侧**:

- 无 Xcode 编译警告 + SwiftLint 基础规则通过
- 核心模块(CairnCore / CairnClaude)单测覆盖率 ≥ 70%
- 关键路径(JSONL ingest / 终端 IO / DB 迁移)有集成测试
- 关键用户流程有 XCTest UI 自动化测试
- 所有用户字符串经 `String(localized:)`,中英双语交付
- 可访问性:按钮 `accessibilityLabel`,对比度 ≥ 4.5:1,VoiceOver 可导航
- GitHub Actions CI 绿(lint + test + build)

**文档侧**:

- README(中英)含安装、首次使用、xattr 说明
- `docs/user-guide/`(用户文档)
- `docs/development/`(开发者 setup + 架构说明)
- `CONTRIBUTING.md`(贡献者指南)
- `CHANGELOG.md`(Keep-a-Changelog 格式)
- Spec 和 Plans 归档可追溯

**分发侧**:

- v0.1 Beta 起:**未签名 DMG**(xattr 路线,**永不购买 Apple Developer 账号**)
- Homebrew Cask 可用
- Sparkle 自动更新(v1.1 再加)

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

**Usage 字段提取规则** [补充于 M0.1,见 ADR 0001 §Q2]:
M0.1 probe 在真实 `message.usage` 中观察到 12 种 key(远多于 spec 初稿假设的 4 种):
`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`,
`cache_creation`(嵌套结构), `service_tier`, `inference_geo`, `server_tool_use`,
`iterations`, `speed`, `claude_cache_creation_5_m_tokens`, `claude_cache_creation_1_h_tokens`。

**v1 Budget 只提取 4 项**(其余写入 `Event.rawPayloadJson` 保留):
- `usedInputTokens += input_tokens`
- `usedOutputTokens += output_tokens`
- cache tokens 按需求在 v1.1 可视化时扩展

**实现纪律**:usage 字段的 schema 不稳定(上表中 `claude_cache_creation_5_m_tokens` 仅 19 次出现,说明字段可能随 Claude Code 版本新增),**提取代码用 `.get(key, 0)` 不抛错**,未知 key 进 rawPayloadJson 归档。

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
| `type: "system"` | 提取为 Session metadata(含 `cwd`),不进时间线 |
| `type: "custom-title"` | 更新 Task.title |
| `type: "progress"` | v1 忽略(高频中间状态,工具执行进度)[修订于 M0.1,见 ADR 0001] |
| `type: "file-history-snapshot"` | v1 忽略(`.claude/` 内部机制)[修订于 M0.1] |
| `type: "last-prompt"` | 提取为 Session metadata,不进时间线 [修订于 M0.1] |
| `type: "permission-mode"` | 提取为 Session metadata,不进时间线 [修订于 M0.1] |
| `type: "queue-operation"` | v1 忽略 [修订于 M0.1] |
| `type: "agent-name"` | 提取为 Session tag,不进时间线 [修订于 M0.1] |
| `type: "tag"` | 提取为 Session tags(M0.1 实测未出现,实现时保留兜底) |
| entry.parentUuid == null 且非首行 | 同时发 `.compact_boundary` |
| `is_error: true` | 同时发 `.error` |

**注**:M0.1 probe 在 517 个真实 session 上发现了以上 11 种 JSONL 顶层 `type`(表格共 12 种,其中 `tag` 未实测到但按 Claude Code 历史记录保留)。详见 `docs/decisions/0001-probe-findings.md` §Q5。

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
| `.ended` | mtime > 5min 且**无悬挂 tool_use**(末行类型不作要求)[修订于 M0.1] |
| `.abandoned` | mtime > 30min 且含**未配对的悬挂 tool_use** |
| `.crashed` | 文件被删除 |

辅助:PTY 层检测 `claude` 进程退出 → 立即标 `.ended`;`.live → .idle` 推送"等待输入中"通知。

**M0.1 probe 发现**:Claude Code **不写 end 标记**。真实 session 末行 type 分布极广(user / assistant / system / permission-mode / file-history-snapshot / progress / last-prompt 均观察到),最常见是 `user`(44%,用户 Ctrl+C 或关终端)。原假设"末条是 assistant 判 ended"不成立。详见 ADR 0001 §Q7。

### 4.6 PlanWatcher

监听**全局** `~/.claude/plans/` 目录(单例,非 per-Workspace)[修订于 M0.1,见 ADR 0001 §Q8]。变化时:
1. 读取变化的 plan `.md` 文件
2. 与上次 diff 去重
3. v1 直接作为富文本展示(不解析 markdown)
4. 关联到当前活跃 Task(启发式:文件 mtime + Task 活跃时间窗 + 可能的 frontmatter 元数据)
5. 发 `.plan_updated` Event

**M0.1 probe 发现**:`~/.claude/plans/` 是全局目录(1 个文件 2.7KB),**不是** per-workspace `<project>/.claude/plans/`。spec 原假设"监听每个 Workspace 的 `.claude/plans/`"不成立,PlanWatcher 降为单例订阅。关联活跃 Task 的精确机制留 M3.4 观察足够多 plan 文件后确定。

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

2 层推断 [修订于 M0.1,见 ADR 0001 §Q1/Q3/Q4]:
1. **优先**:扫描 JSONL entries 找**第一个 `type == "system"` 的 entry**,读其顶层 `cwd` 字段。
   - M0.1 probe 实测:**所有 1620 条 system entry 都含 `cwd`**(字段路径是 `entry.cwd`,非 `entry.message.cwd`);但 JSONL **第一条 entry 很多不是 system**(常见是 `permission-mode` / `file-history-snapshot`),所以必须"扫描找第一个 system"而非"读第一条"。
2. **兜底**:从 hash 目录名反推 cwd(不精确)。
   - Hash 规则:cwd 中的 `/`、`_`、`.` **都**替换为 `-`。正向可算,**逆向有歧义**(无法判断 `-` 原字符)。
   - 仅在 JSONL 里找不到任何 `type == "system"` entry 时(罕见,可能是损坏文件)使用。

**原 spec 假设的"第二层 `.meta.json` 类映射"实测不存在**,已从推断链删除。

M0.1 probe 覆盖 517 session / 22 hash 目录 / 27 distinct cwd,映射启发式已充分验证。

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

## 8. 路线图与里程碑(Session-based 模型)

### 8.1 发布节奏与节拍模型

**三次发布**:

```
v0.1 Beta           v0.5                v1.0
Observable          Task Layer          Production + Polish
Terminal            
~8 milestones       ~14 milestones      ~24 milestones
```

**核心节拍模型**:**Claude 主导开发,用户只做 milestone 验收**。计划按"milestone 数"而非"周数"组织。

- 每个 milestone ≈ Claude 1-3 次 session 能完成的功能单元
- 每个 milestone 结尾 Claude 停下产出验收清单,等用户跑一遍反馈
- 日历时间 = milestone 数 × 用户 session 频率

| 用户 session 频率 | v0.1 Beta(8 M) | v0.5(14 M) | v1.0(24 M) |
|---|---|---|---|
| 每周 1 session | ~2 个月 | ~3.5 个月 | ~6 个月 |
| 每周 2 session | ~1 个月 | ~1.75 个月 | ~3 个月 |
| 每周 3+ session | ~3 周 | ~1.5 个月 | ~2 个月 |

**合理预期**:用户每周 1-2 session → **v1.0 约 4-6 个月日历**。

### 8.2 Milestone 全景(24 个)

```
Phase 0 · 探路(2 milestone)
  ├─ M0.1  仓库基础设施 + Probe 勘察
  └─ M0.2  Hello World macOS App

Phase 1 · 终端基座(5 milestone)
  ├─ M1.1  SPM 6 模块骨架 + CairnCore 数据类型
  ├─ M1.2  CairnStorage(GRDB + 11 表 + migrator)
  ├─ M1.3  主窗口三区 + 侧边栏/Panel 结构
  ├─ M1.4  单 Tab 终端 + PTY 生命周期
  └─ M1.5  多 Tab + 水平分屏 + OSC 7 + 布局持久化

Phase 2 · Claude 观察(7 milestone)── v0.1 Beta
  ├─ M2.1  JSONLWatcher(FSEvents + vnode + reconcile)
  ├─ M2.2  JSONLParser + 12 Event 映射 + 配对
  ├─ M2.3  EventIngestor + 批量事务
  ├─ M2.4  AsyncStream EventBus + Timeline 视图
  ├─ M2.5  工具卡片合并 + 视觉语言实现
  ├─ M2.6  Session 生命周期 + Tab↔Session 关联
  └─ M2.7  v0.1 Beta 打磨 + 未签名 DMG 打包 + 发布

Phase 3 · Task 层(6 milestone)── v0.5
  ├─ M3.1  Task 实体 + 自动创建 + Sidebar
  ├─ M3.2  Task 详情 Panel + 状态机
  ├─ M3.3  BudgetTracker + 预算 UI + 告警
  ├─ M3.4  Plan 双源同步(TodoWrite + plan.md)
  ├─ M3.5  Workspace 管理 + 多 Workspace 隔离
  └─ M3.6  历史导入 + v0.5 发布

Phase 4 · 生产级化(4 milestone)── v1.0
  ├─ M4.1  设置页 + 本地化基础设施 + 中英双语交付
  ├─ M4.2  可访问性(VoiceOver / 对比度 / 键盘导航)
  ├─ M4.3  CI + 诊断导出 + 周自动备份
  └─ M4.4  完整文档(user / dev / contributing) + v1.0 发布
```

### 8.3 Phase 0:探路(2 milestone)

#### M0.1:仓库基础设施 + Probe 勘察

**交付物**:
- LICENSE / README / .gitignore
- GitHub 远端 + 首次 push
- `probe/probe.py`(Python 扫描脚本)+ 单测
- `probe/probe-report.md`(勘察报告)
- `docs/decisions/0001-probe-findings.md`(ADR)
- 必要时修订 spec §4

**用户负责**:生成真实数据(用 Claude Code 跑 3+ 会话);验收跑 probe.py 看 report;GitHub push 授权。

**Claude 负责**:其余所有。

#### M0.2:Hello World macOS App

**交付物**:
- `Package.swift`(6 target 骨架)
- 最小可启动的 macOS SwiftUI App
- SwiftTerm 嵌入运行 zsh
- XCTest 测试目标建好

**验收**:用户 `open Cairn.app` 看到空窗口,里面有能输入的 zsh 终端。

### 8.4 Phase 1:终端基座(5 milestone)

| M | 内容 | 交付物 | 验收 |
|---|---|---|---|
| M1.1 | SPM 6 模块骨架 + CairnCore 数据类型 | 编译通过;≥ 10 单测绿 | `swift test` 全绿 |
| M1.2 | CairnStorage:GRDB + 11 表 + migrator + DAO | `schema_versions` 插入 v1;完整 CRUD 单测 | 单测全绿 |
| M1.3 | SwiftUI 主窗口三区 + Sidebar/Panel 可折叠 | 启动看到 Section 6 布局 | 手动验收,布局像设计图 |
| M1.4 | 多 Tab 管理 + TerminalSurface 封装 + PTY 生命周期 | `⌘T` / `⌘W` / `⌘L` 可用 | 手动创建/切换/关闭 Tab 工作 |
| M1.5 | 水平分屏 + OSC 7 cwd 跟踪 + 布局 SQLite 持久化 | 关 App 开 App 布局恢复 + cd 自动更新 cwd | 手动验收 |

**Phase 1 验收终点**:可替代 iTerm2 日常使用的原生终端(尚无 AI 集成)。

### 8.5 Phase 2:Claude 观察(7 milestone)→ **v0.1 Beta 发布**

| M | 内容 | 关键验证 |
|---|---|---|
| M2.1 | JSONLWatcher:FSEvents + vnode + 30s reconcile 三层 | 单测 + 用真实 JSONL 触发验证 |
| M2.2 | JSONLParser:12 Event 映射 + tool_use↔result 配对 + 10 fixture | fixture 测试全绿 + 真实 session 解析 |
| M2.3 | EventIngestor:批量事务写 SQLite + cursor 推进 | 压力测试:1000 行 < 500ms |
| M2.4 | AsyncStream EventBus + Timeline View 基础 | 边跑 Claude 边看 Panel 刷新 |
| M2.5 | 工具卡片合并 + 视觉语言(Section 6.4)+ 折叠交互 | UI 自动化测试 + 手动截图对齐 |
| M2.6 | Session 生命周期检测 + Tab↔Session 关联 | 多种场景:正常结束/意外崩/idle |
| M2.7 | v0.1 Beta 打磨 + 未签名 DMG 脚本 + 发布 | Release + 首发 HN/X/Claude Discord |

**v0.1 Beta 发布说明**(Claude 写 CHANGELOG + release notes):
- 定位:Observable Terminal —— 把 Claude Code 的输出结构化呈现
- 不含:Task 概念 / Budget / Plan / 历史导入(v0.5 再加)
- 分发:未签名 DMG,README 首页写 `xattr` 命令
- 目标:首发 2 周 ≥ 200 stars + ≥ 40 真实用户 + ≥ 20 issues

### 8.6 Phase 3:Task 层(6 milestone)→ **v0.5 发布**

| M | 内容 |
|---|---|
| M3.1 | Task 实体 + 自动从 Session 创建 + Sidebar Task 列表(Section 6.2) |
| M3.2 | Task 详情 Panel(右上区) + 状态机 + 用户操作(归档/重命名/合并) |
| M3.3 | BudgetTracker:api_usage 聚合 → Budget.state + 80%/100% 告警 |
| M3.4 | Plan 双源同步:TodoWrite 解析 + plan.md 监听 + Panel 渲染 |
| M3.5 | Workspace 管理:创建/切换/归档 + 多 Workspace 布局隔离 |
| M3.6 | 历史 JSONL 导入(首次启动扫描)+ v0.5 发布 |

**v0.5 发布目标**:完整核心功能,**≥ 500 stars,≥ 100 活跃用户**。Claude 出 CHANGELOG + 升级指南。

### 8.7 Phase 4:生产级化(4 milestone)→ **v1.0**

| M | 内容 | 交付清单 |
|---|---|---|
| M4.1 | 设置页 UI + 本地化基础设施 + 中英双语**所有字符串** | `Localizable.xcstrings` 完整;语言切换即时生效 |
| M4.2 | 可访问性:VoiceOver 全链路导航 + 对比度审查 + 键盘导航完整 | XCTest 可访问性测试 + 手动 VoiceOver 跑一遍 |
| M4.3 | GitHub Actions CI(lint + test + build)+ 诊断导出 + 周自动备份 | CI 绿;诊断 zip 可导出;备份脚本每周跑 |
| M4.4 | 完整文档 + Homebrew Cask + Sparkle 更新 + v1.0 发布 | 见下 |

**M4.4 完整文档清单**:
- `README.md`(中英)
- `docs/user-guide/`(用户文档)
- `docs/development/setup.md`(开发环境)
- `docs/development/architecture.md`(架构说明)
- `CONTRIBUTING.md`
- `CHANGELOG.md`(Keep-a-Changelog 格式)
- 官网(GitHub Pages,简洁介绍 + 截图 + 下载)

**v1.0 发布目标**:**≥ 1500 stars,≥ 500 活跃用户,≥ 3 外部贡献者**。

### 8.8 分工(Claude 主导模式)

| Claude 负责 | 用户负责 |
|---|---|
| 读 spec + plan,自主判断当前进度 | 触发 session(说"继续"或具体需求) |
| 写所有代码(Swift / Python / Shell) | 产品方向决策(加减功能) |
| 写所有测试 | 花钱决策(当前政策:零花费) |
| 写所有架构文档 + 用户文档 | 品牌决策(文案、logo、配色) |
| commit + push + 打 tag | 验收(跑命令、核对输出) |
| milestone 完成时输出验收清单 | 接受或拒绝验收,反馈问题 |
| 维护 CHANGELOG / release notes | 发布时机决定 |

### 8.9 外部成本(零花费路线)

| 项 | 是否必要 | 成本 | 备注 |
|---|---|---|---|
| Xcode | ✅ 必须 | $0 | 用户本机 |
| GitHub 免费账号 | ✅ 必须 | $0 | 公开 repo 可用 |
| 免费 Apple ID(Xcode 登录) | ✅ 必须 | $0 | 本地构建用 |
| **Apple Developer** | ❌ **决定不买** | $99/年 | 永不签名,xattr 路线 |
| **域名** | ❌ **不买** | $10-100/年 | 用 `cairn.github.io` / GitHub Pages 就够 |
| Homebrew Tap | ✅ 必须 | $0 | 独立 GitHub repo `homebrew-cairn` |
| GitHub Actions CI | ✅ 必须 | $0 | 公开 repo 免费 |
| Sentry/PostHog 遥测 | ❌ **不加** | — | 隐私优先,零遥测 |

**总成本:$0/年。** 这也是"零门槛参与的真开源"的一部分。

### 8.10 风险清单(更新版)

| 风险 | 概率 | 应对 |
|---|---|---|
| JSONL schema 变化(Claude 升级) | 中 | Probe + fixture 覆盖矩阵;Parser 版本兼容 |
| Claude 误判当前 milestone 状态 | 中 | CLAUDE.md 强制开工前核对 `git log` + `milestone-log` |
| 未签名导致采纳率低(xattr 摩擦) | 高 | README 首页显著提示 + 可选 Homebrew 自动化 |
| SwiftTerm 致命 bug | 低 | 分层设计,v2 可切 libghostty,TerminalSurface 一层封装 |
| SQLite 大数据量性能 | 低 | 归档 + 索引 + 分页 |
| 被 cmux / codux 抄设计 | 中 | 差异化靠 Task 抽象执行质量 + 社区,设计不藏 |
| macOS 新版(2026+)破坏 API | 中 | CI 用最新 Xcode 和 beta |
| 质量标准降格风险 | **中高** | CLAUDE.md 明列生产级基准;每 M 自查对齐 |
| Session 间 Claude 读错进度 | 中 | CLAUDE.md 强制开工核对协议 + 一句话报告后等用户 ✅ |

---

## 9. 协作方式与验收协议(Claude 主导模式)

### 9.1 Session 循环(标准流程)

每次用户触发一个 Claude Code session,Claude 按此流程执行:

```
1. 读 CLAUDE.md + spec + 最新 plan(docs/superpowers/plans/ 下最新文件)
2. 跑:git log --oneline -10  git status  cat docs/milestone-log.md | tail
3. 一句话对用户报告:"我看到的状态是 X,准备做 MY,开始?"
4. 等用户 ✅
5. 执行 milestone(代码 + 测试 + 文档 + commit + push)
6. 产出验收清单(验收命令 + 期望输出 + 已知限制)
7. 更新 docs/milestone-log.md
8. 告知用户"MY 完成,等验收"
9. 停下
```

**绝对不要**:
- 一个 session 推进多个 milestone(积压用户验收)
- 不验收就继续下一步
- 跑掉不回报

### 9.2 用户验收协议

用户只需做 3 件事:

1. **粘贴命令跑一遍**(Claude 产出的验收命令)
2. **核对输出是否符合期望**
3. **回复**:
   - ✅ 通过 → 下个 session 推进下个 M
   - ❌ 不通过 + 具体描述问题 → 下个 session Claude 修

**用户不必做**:
- 读代码(除非自己想)
- 理解架构(信任 spec 就够)
- 调试(把现象给 Claude,Claude 查)
- 写文档 / 提交代码

### 9.3 验收清单模板(Claude 每个 milestone 结尾输出)

```markdown
## M[X.Y] 验收清单

**交付物:**
- [列出本 milestone 创建/修改的关键文件]

**前置条件:**
- [如需,例如"已装 Xcode 16+"]

**验证步骤:**

步骤 1 · 构建
```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn
swift build
```
期望: Build complete! 无 warnings。

步骤 2 · 单元测试
```bash
swift test
```
期望: N passed, 0 failed。

步骤 3 · (可选)手动运行验证
```bash
open build/... / xcrun ...
```
期望: [具体用户可观察的行为]

**已知限制 / 延后项:**
- [清单,无则写"无"]

**下个 M:** M[X.Y+1] [标题]
```

### 9.4 Git 工作流(Claude 主导)

- `main` 永远 green
- 直接在 main 上小步推进(小项目无需 PR 流程,Claude 单向写入)
- 每个逻辑变更一个 commit
- Milestone 完成后打 tag `mX-Y-done`
- 依赖变更**独立 commit** 且在 message 中高亮
- **绝不** `git push --force` 到 main
- **绝不** 使用 `--no-verify`

Commit 信息格式:
```
<type>: <一行摘要(≤ 60 字)>

<可选正文:解释"为什么"这样做,不解释"做了什么">

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

常见 type:`feat / fix / refactor / test / docs / chore / ci / build`。

### 9.5 代码质量标准(生产级,不降格)

这是**硬基准**,每个 milestone 完成时 Claude 自查:

| 维度 | 要求 |
|---|---|
| 编译 | Xcode + SwiftLint 基础规则无警告 |
| 单元测试 | 核心模块 ≥ 70% 覆盖(CairnCore / CairnClaude 重点) |
| 集成测试 | 关键路径(JSONL / PTY / DB 迁移)有场景级用例 |
| UI 测试 | 关键用户流程(⌘T / Task 切换 / Hook 审批)XCTest UI 自动化 |
| 本地化 | 所有字符串 `String(localized:)` + `Localizable.xcstrings` |
| 可访问性 | `accessibilityLabel` 齐 + 对比度 ≥ 4.5:1 + VoiceOver 可用 |
| 函数 | 单函数 ≤ 30 行(目标值,不是硬限制) |
| 命名 | 长而直白(`ingestJSONLLinesAndEmitEvents` 好于 `process`) |
| 注释 | 只写"为什么",不写"做什么" |
| 错误 | 用户可见错误有可读消息;不可恢复错误生成诊断包 |
| 性能 | 空闲 CPU < 1%;Timeline 1000 条 < 16ms 帧 |
| YAGNI | 严禁"为未来灵活性"提前抽象 |

### 9.6 Claude 必须先问用户的事

| 情况 | 为什么必须问 |
|---|---|
| 想加 spec 之外的新功能 | 越权,产品方向 |
| 想砍 spec 已有的功能 | 同上 |
| 想引入新第三方依赖(≠ spec §3.6) | 增加维护面 |
| 遇到 spec 内部矛盾 | 设计分歧 |
| 想做破坏性变更(force push / 删 commit) | 不可逆 |
| 环境异常(用户机器配置问题) | Claude 改不了 |
| 多种技术方案等价,但用户有偏好 | 给选项 |
| 测试反复失败,怀疑是设计 bug 而非实现 bug | 需要重新对齐 |

**模板**:
> "我遇到 X。原因是 Y。选项 A(代价 A)/ 选项 B(代价 B)。建议 A。等你决定。"

**不要**在这些情况下硬闯。硬闯 = 浪费 session + 埋坑。

### 9.7 Claude 不需要问的事(自决)

- 依赖版本选择(同 major 内)
- 代码风格细节(命名、注释、错误处理)
- 内部文件组织 / 模块拆分
- 测试类型与数量(只要满足 §9.5 基准)
- 性能优化策略
- commit 粒度 / message 格式
- CI 配置细节
- 日志格式

### 9.8 文档结构(生产级版本)

```
cairn/
├── README.md                      用户入口,中英双语
├── CHANGELOG.md                   Keep-a-Changelog 格式(v0.1 起)
├── CONTRIBUTING.md                贡献指南(v0.5 前写)
├── LICENSE                        MIT
├── CLAUDE.md                      Claude session 开工文件
└── docs/
    ├── superpowers/
    │   ├── specs/                 设计规范
    │   └── plans/                 milestone 计划
    ├── user-guide/                用户文档(v0.5 起补)
    │   ├── installation.md
    │   ├── first-run.md
    │   └── features/              按功能分篇
    ├── development/
    │   ├── setup.md               开发环境搭建
    │   ├── architecture.md        活文档,随开发更新
    │   └── api-contracts.md       内部协议契约
    ├── decisions/                 ADR 风格决策记录
    │   └── 0001-probe-findings.md
    ├── milestone-log.md           milestone 完成记录(每 M 更新)
    └── bugs/                      无法即修的 bug 记录
```

注意:把 `learning-log.md` 删除 / 改名为 `milestone-log.md`,反映定位调整。

### 9.9 项目健康度信号(Claude 自律)

| 灯 | 条件 | Claude 应对 |
|---|---|---|
| 🟢 | 上个 milestone 通过验收;main 绿;文档同步 | 继续推进 |
| 🟡 | 上个 milestone 验收发现小问题 | 下个 session 先修再推进 |
| 🔴 | main 构建失败 / 测试多条失败 / 关键功能退化 | **立刻停下,不推进新功能**;下个 session 专注修复 |

Claude 发现 🔴 情况时,主动在 session 结尾告诉用户:
> "当前状态 🔴:XX 坏了。下个 session 我会先修这个,不做新 milestone,除非你说可以跳过。"

### 9.10 Claude 的承诺(生产级版本)

1. **不替用户做产品决策**(功能、文案、花钱、发布时机)
2. **坦白不知道的事**(需要查证就明说"让我先验证")
3. **不糊弄性产出**:代码必须跑过、测过、自查过质量基准
4. **设计错会承认并重修**(不硬撑错误设计)
5. **不积压工作**:每个 milestone 完结 → 停 → 等验收 → 再推
6. **不降低质量基准**(测试 / 文档 / 可访问性)
7. **不引入未在 spec 的依赖 / 功能** 不先问用户
8. **main 永远可用**:红灯立刻停,不推新功能
9. **验收清单必须完整**:命令 + 期望 + 限制清清楚楚

### 9.11 session 之间的连续性保证

由于 Claude 每个 session 是全新上下文,**一致性靠文档保证**:

| 信息 | 存储位置 | 用途 |
|---|---|---|
| 工作模式和红线 | `CLAUDE.md` | 每次开工必读 |
| 设计决策 | spec | 唯一真相源 |
| 当前 milestone | 最新 `plans/` 文件 | 本周做什么 |
| 已完成 milestone | `docs/milestone-log.md` | 进度判断 |
| 架构演进 | `docs/development/architecture.md` | 活文档 |
| 决策变更 | `docs/decisions/NNNN-*.md` | ADR 审计 |

**Claude 的自律**:改了架构/决策就**同步更新文档**,不留隔代漂移。

---

## 附录 A:关键决策记录

| # | 决策 | 选择 | 关键理由 |
|---|---|---|---|
| A1 | 终端引擎 | SwiftTerm(非 libghostty) | 纯 Swift(无 C 桥接维护成本)+ Codux 已验证 + v1.5 可切换到 libghostty 若需 GPU 性能 |
| A2 | 构建系统 | SPM 多模块(非单 target) | 编译器强制分层,教学价值 |
| A3 | Session vs Task | Task has-many Sessions(v1 默认 1:1) | 语义正确,schema 向前兼容 |
| A4 | AI 集成通路 | JSONL 主 + Hook 可选 + MCP 不做 | 零侵入,稳定性可控 |
| A5 | 远程能力 | v1 不做(纯本地) | cmux 的 Go daemon 对学习项目过重 |
| A6 | 许可证 | MIT | 最大化采纳,open-core 路径畅通 |
| A7 | Budget 强制 | v1 观察,v1.1 Hook 强制 | 不 patch Claude,零侵入 |
| A8 | 游戏化 | 不做(宠物/等级) | 专业工具,Codux 前车之鉴 |
| A9 | Apple Developer | **永不购买**(2026-04-24 定) | 零花费路线;用户 xattr 绕过 Gatekeeper |
| A10 | UI 布局 | 三区(Sidebar/Main/Panel),主区只放终端 | 保持"终端首先是终端"心智 |
| A11 | Event 类型 | type 封闭 12 种 + category 开放 | 结构稳定,扩展灵活 |
| A12 | 存储方案 | SQLite + raw_payload 90 天归档 | 稳定 ≤ 1GB/年 |
| A13 | 开发模式 | **Claude 主导开发 + 用户仅验收**(2026-04-24 定) | 用户无时间深度参与;质量由 Claude 对 CLAUDE.md 自律保障 |
| A14 | 分发策略 | **永不签名,xattr 路线**(2026-04-24 定) | 与 A9 一致;README 首页清晰说明 |
| A15 | v1 范围 | **保持聚焦**,不提前纳入 MCP / 多工具 / 浏览器(2026-04-24 定) | 先聚焦发布 v0.1 Beta,再按社区反馈决定扩展方向 |
| A16 | 质量基准 | **生产级不降格**:单测 70%+ / UI 自动化 / 可访问性 / 本地化(2026-04-24 定) | 定位"完整开源级"的直接体现 |
| A17 | 遥测 | **零遥测**(不加 PostHog/Sentry) | 隐私优先 + 零成本 |
| A18 | 域名 | **不买**,用 `cairn.github.io` / GitHub Pages | 零花费路线 |

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
