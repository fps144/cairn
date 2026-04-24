# ADR 0001:Phase 0 Probe 勘察发现

**日期:** 2026-04-24
**状态:** Accepted
**决策者:** Claude(技术) + sorain(产品验收)
**Milestone:** M0.1

---

## 背景

Spec v1(2026-04-23)基于 Claude Code 源码分析报告写作,**未在真实 JSONL 数据上验证**。
M0.1 probe(`probe/probe.py`)扫描本机 `~/.claude/projects/`,
基于 **517 个真实 session / 48,206 事件行 / 22 个 project hash 目录 / 160 MB 原始数据**,
产出 `probe/probe-report.md`。本 ADR 汇总发现与对 spec 的影响。

**样本质量**:10 条 parse error(0.02%),均为 JSONL 中混入的非 JSON 行(疑为 agent 输出被截断嵌入),良性,parser 正确跳过。

---

## Appendix B 10 个问题的实测答复

### Q1. JSONL 第一条 entry 是否含 `system.cwd`?

**spec 原假设(§4.9)**:"读 JSONL **第一条 entry** 的 `system.cwd`"。

**实测**:**假设不成立**。Session 1 首条是 `permission-mode`,Session 2 首条是 `file-history-snapshot`,Session 3 首条也是 `permission-mode`。第一条 entry 的 type 分布多样,**并非总是 `system`**。

**但**:扫描全部 1620 条 `type=system` entry,**100% 含顶层 `cwd` 字段**(字段路径是 `entry.cwd`,非 `entry.message.cwd`,非 `entry.system.cwd`)。跨 27 个不同 cwd 路径。

**对应 spec §4.9 修订**:
- ❌ 原文:"读 JSONL 第一条 entry 的 `system.cwd`"
- ✅ 新文:"扫描 entries 找**第一个 `type==system` 的 entry**,取其顶层 `cwd` 字段"

---

### Q2. `message.usage` 精确 schema?

**spec 原假设(§2.4)**:4 个字段 — `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`。

**实测**:出现 12 个不同 key:

| key | 出现次数 |
|---|---|
| `input_tokens` | 20,564 |
| `output_tokens` | 20,564 |
| `cache_read_input_tokens` | 20,288 |
| `cache_creation_input_tokens` | 20,287 |
| `cache_creation` | 20,287 |
| `service_tier` | 11,007 |
| `inference_geo` | 10,856 |
| `server_tool_use` | 10,714 |
| `iterations` | 10,714 |
| `speed` | 10,714 |
| `claude_cache_creation_5_m_tokens` | 19 |
| `claude_cache_creation_1_h_tokens` | 19 |

`cache_creation` 看起来是嵌套结构(与 `cache_creation_input_tokens` 同时存在)。`server_tool_use` 与内置 WebSearch/WebFetch 可能相关。

**对应 spec §2.4 修订**:Budget 模型的 `usedInputTokens / usedOutputTokens` 仍从 `input_tokens + output_tokens` 累加;需要在 spec §2.4 / §4.3 补充说明"usage 字段较 spec 原假设多,实现时不强依赖字段完备性,只提取 input/output/cache_{read,creation}_input_tokens 四项"。

---

### Q3. `~/.claude/projects/{hash}/` 的 hash 规则?

**spec 原假设(§4.9)**:未明说规则,提出"检查 `.meta.json` 类映射 + 询问用户兜底"。

**实测**:Hash 规则 = cwd 中的 `/`、`_`、`.` **都**替换为 `-`。

验证:
- `/Users/sorain` → `-Users-sorain` ✅
- `/Users/sorain/.vext/workspaces/01KN4B9E6FCYDS3KW0SQEHG3N5/mvp` → `-Users-sorain--vext-workspaces-01KN4B9E6FCYDS3KW0SQEHG3N5-mvp` ✅(含 `.` → `-` 和 `/.` → `--` 的双重替换)

**可逆性**:**正向可算,逆向有歧义**(因为 `-` 不能判断原字符是 `/`、`_`、`.` 还是 `-` 本身)。

**对应 spec §4.9 修订**:
- 三层推断降为**两层**:(a)优先用 JSONL 里扫到的 `system.cwd`(见 Q1);(b)兜底才用 hash 目录名反推 cwd(不精确,用于"孤儿 session 建 workspace")。
- 原假设的第二层「`.meta.json` 类映射」**不存在**(见 Q4),从推断链中删除。

---

### Q4. 是否存在 `~/.claude/projects/.meta.json`?

**spec 原假设(§4.9)**:"检查 `~/.claude/projects/.meta.json` 类映射文件"作为推断第二层。

**实测**:**不存在**。`~/.claude/projects/` 下仅有 22 个 hash 目录,无 `.meta.json` 也无其他索引文件。

**对应 spec §4.9 修订**:从 Workspace↔Session 映射的三层推断中删除第二层。

---

### Q5. Entry types 是否都在 spec §4.3 中?

**spec §4.3 列出的 JSONL 顶层 entry type**(6 种):
- `user`
- `assistant`
- `attachment`
- `system`
- `custom-title`
- `tag`

**实测(11 种,按频次降序)**:

| type | 频次 | spec §4.3 覆盖 |
|---|---|---|
| `assistant` | 20,564 | ✅ |
| `user` | 13,261 | ✅ |
| `progress` | 9,745 | ❌ **缺** |
| `system` | 1,620 | ✅ |
| `file-history-snapshot` | 1,472 | ❌ **缺** |
| `attachment` | 780 | ✅ |
| `last-prompt` | 318 | ❌ **缺** |
| `permission-mode` | 304 | ❌ **缺** |
| `queue-operation` | 130 | ❌ **缺** |
| `custom-title` | 1 | ✅ |
| `agent-name` | 1 | ❌ **缺** |
| `tag` | 0 | ⚠️ **未出现** |

**对应 spec §4.3 修订**:JSONL → Event 映射表需增加 6 种 type 的处理策略,删除(或标注"未实测到")`tag`:

- `progress` — 高频(20% of events),可能是工具执行进度中间状态。**建议**:v1 忽略,不创建 Event;留 M2.2 fixture 分析。
- `file-history-snapshot` — 文件变更快照,`.claude/` 内部机制。**建议**:v1 忽略。
- `last-prompt` — 与最近 prompt 相关元数据。**建议**:v1 作 Session metadata,不进 Timeline。
- `permission-mode` — 当前 permission 设置(default / acceptEdits 等)。**建议**:v1 作 Session metadata,不进 Timeline。
- `queue-operation` — 队列操作元数据。**建议**:v1 忽略。
- `agent-name` — 子 agent 名字。**建议**:提取为 Session tag,不进 Timeline。

---

### Q6. JSONL 文件大小分布

| 分位 | 大小 |
|---|---|
| min | 1.9 KB |
| p50 | 60.2 KB |
| p90 | 265.9 KB |
| p99 | 3,070.1 KB (3 MB) |
| max | 68,681.0 KB (68 MB) |

**spec §7.4 估算(1GB/年)**:与 P99 3MB 一致。但 **max 68MB** 比估算高一个数量级,且极罕见(1/517)。

**对应 spec 修订**:§7.4 保留 1GB/年估算;在 §4.2 JSONLWatcher 的"按字节偏移增量读取"设计中,追加"单次读取块大小 1MB"的纪律(已在 spec 伪代码中)。**无需结构性修改**。

**影响 M2.3**:EventIngestor 压力测试需用 68MB 真实文件而非合成数据。

---

### Q7. Claude Code 退出时是否写 end 标记?

**spec 原假设(§4.5)**:`.ended` = "mtime > 5min 且末条是 assistant(非悬挂 tool_use)"。

**实测(前 50 session 末行 type 分布)**:
- `user` — 22(44%)
- `assistant` — 8(16%)
- `system` — 8(16%)
- `permission-mode` — 5(10%)
- `file-history-snapshot` — 5(10%)
- `progress` — 1
- `last-prompt` — 1

**没有任何专门的 `end` 标记**。最常见末行是 `user`(用户按 Ctrl+C / 关闭终端,Claude 未回复),其次是 `assistant` / `system`。假设"末条是 assistant"**错误**。

**对应 spec §4.5 修订**:
- ❌ 原:`.ended` = mtime > 5min 且末条是 assistant(非悬挂 tool_use)
- ✅ 新:`.ended` = mtime > 5min 且**无悬挂 tool_use**(末条类型不作要求)
- `.abandoned` 保持:mtime > 30min 且含**未配对的悬挂 tool_use**

---

### Q8. `.claude/plans/` 目录结构?

**spec 原假设(§4.6 PlanWatcher)**:"监听每个 Workspace 的 `.claude/plans/` 目录"。

**实测**:**plans 是全局目录,不是 per-workspace**:
- `~/.claude/plans/` 存在,内含 1 个文件 `functional-soaring-bubble.md`(2.7 KB)
- 本项目 `cairn/.claude/plans/` **不存在**;`cairn/.claude/` 下仅有 `settings.local.json`
- 搜索全盘 `*/.claude/plans/` 只发现 `~/.claude/plans` 和两个 superpowers 插件的 cache 目录(不相关)

**对应 spec §4.6 修订(重大)**:
- ❌ 原:"监听每个 Workspace 的 `.claude/plans/` 目录"
- ✅ 新:"监听**全局** `~/.claude/plans/` 目录"
- **关联到当前活跃 Task** 的启发式改为:用文件 mtime + 文件名语义 + 可能的 frontmatter(需 M3.4 进一步观察)
- **架构影响**:PlanWatcher 在 `CairnClaude` 模块里从 per-Workspace 降为单例,订阅全局目录。

---

### Q9. Hook 配置 schema?

**实测**:`~/.claude/settings.json` 存在(1240 字节),顶层 keys:`env`, `statusLine`, `enabledPlugins`, `extraKnownMarketplaces`, `skipDangerousModePermissionPrompt`, `model`, `permissions`。**无 `hooks` 字段**(用户未配过任何 hook)。

项目级 `cairn/.claude/settings.local.json` 存在但极小(272 字节)。

**结论**:hook schema 无法从现状**直接观察验证**。实现 HookManager 时必须参考 Claude Code 官方文档的 hooks 配置 schema。

**对应 spec §4.7 修订(软修订)**:在 "HookManager v1 提供开关,默认关" 段落补充一句:"hooks schema 依赖 Claude Code 官方文档;实现前需在 Claude Code 发布说明中确认当前版本的 hook 事件类型与输入格式"。

---

### Q10. 大文件 ingest 性能?

**延后到 M2.3**。已知 max = 68 MB,P99 = 3 MB。EventIngestor 压力测试用真实 68MB 文件作 worst-case baseline。

---

## 额外发现(Appendix B 之外)

### Tool 名字分布远超 spec §2.3 列表

实测 30 种 tool_name(前 10):Read (3418), Bash (3155), Edit (1597), Write (621), TaskUpdate (618), Grep (427), Agent (364), TaskCreate (301), Glob (298), Skill (291)。

`Task*` 系列(`TaskCreate` / `TaskUpdate` / `TaskGet` / `TaskList` / `TaskOutput` / `TaskStop`)在 spec §2.3 category 表里**无位置**。这些不是 spec 里的 `Task`(subagent)工具,而是新的任务管理工具,应归到 `todo` category。`Skill` 是新概念。`mcp__ide__getDiagnostics` / `ListMcpResourcesTool` 应归 `mcp_call` / `ide`。

**影响**:spec §2.3 的 category 是"开放集,按 toolName 查表映射",**不需修改 schema**,只需在 M2.2 实现时扩充查表。**本 ADR 不修 spec,留 M2.2 技术实现记录。**

### 22 hash 目录 vs 27 distinct system.cwd

`ls ~/.claude/projects/` 有 22 个 hash 目录,但 `system.cwd` 出现 27 种不同路径。差额 5 个可能是:
- 同一 hash 目录下的 session 来自多个 cwd(如果用户在同一项目内 cd 过子目录后开新 claude session)
- 或 hash 规则有更多边界字符未测出

**影响**:兜底路径必须信任 JSONL 里的 `system.cwd`,不能假设"hash 目录 ↔ 单一 cwd"。

---

## Spec 修订清单(T10 执行)

| # | Spec 位置 | 原文(摘) | 修订 | 理由 |
|---|---|---|---|---|
| 1 | §4.3 JSONL entry 映射表 | 6 种 type(含 `tag`) | 增加 6 种(`progress` / `file-history-snapshot` / `last-prompt` / `permission-mode` / `queue-operation` / `agent-name`),标注 `tag` 为"未实测到" | Q5 |
| 2 | §4.5 Session 生命周期 `.ended` | "末条是 assistant(非悬挂 tool_use)" | 去掉"末条是 assistant"要求,只保留 "无悬挂 tool_use" | Q7 |
| 3 | §4.6 PlanWatcher | "监听每个 Workspace 的 `.claude/plans/`" | "监听**全局** `~/.claude/plans/`" + 关联活跃 Task 的启发式说明 | Q8 |
| 4 | §4.9 Workspace↔Session 映射 | "读第一条 entry 的 `system.cwd`" | "扫描 entries 找第一个 `type==system` 的 entry,取其顶层 `cwd`";删除 `.meta.json` 兜底层 | Q1, Q4 |
| 5 | §2.4 Budget 模型 usage 字段 | 4 个字段假设 | 补充说明 usage 实际 12 字段;Budget 只提取 input/output/cache 四项 | Q2 |

**共 5 条修订**。无 ADR 之外的变更。

---

## 后续行动

- [x] (T10 完成)按上表修订 spec 5 处。
- [x] (T11 完成)更新 milestone-log 记录 M0.1 完成。
- [ ] (M2.2 时)实现 EventIngestor 时扩充 tool category 查表,覆盖 `Task*` / `Skill` / `ListMcpResourcesTool`。
- [ ] (M2.3 时)EventIngestor 压测用真实 68MB session。
