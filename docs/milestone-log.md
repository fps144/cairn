# Milestone Log

> Cairn milestone 完成记录。每个 M 完成时由 Claude 追加一条。
> 用户可快速浏览项目进度;新 session 的 Claude 读此文件定位当前状态。

---

## 约定

- 每条格式:
  - `## M[X.Y] <标题>` 二级标题
  - Completed(ISO 日期)
  - Tag(git tag 名)
  - Summary(3-5 行)
  - Acceptance(如何验证)
  - Known limitations(可选)

---

## 待完成

- [ ] M2.6 - M2.7 ...(详见 spec §8.5)**— Phase 2 v0.1 Beta 冲刺**
- [ ] M3.1 - M3.6 ...(详见 spec §8.6)
- [ ] M4.1 - M4.4 ...(详见 spec §8.7)

---

## 🎉 Phase 1 完成(M0.1 → M1.5)

**节点**:2026-04-28
**tag 范围**:`m0-1-done` → `m1-5-done`
**交付**:可用的原生 macOS 终端(多 tab / 水平分屏 / PTY 生命周期 / 布局跨启动恢复),完整 CairnCore 领域模型 + CairnStorage 持久化底座就绪,120 个单测绿。

**下一阶段**:Phase 2(M2.1 - M2.7)= Claude Code JSONL 观察能力,终点 v0.1 Beta 发布。

---

## 已完成(逆序)

### M2.5 工具卡片合并 + 折叠交互 + 视觉精修

**Completed**: 2026-04-30
**Tag**: `m2-5-done`
**Commits**: 6 个(`79d7ae3` Aggregator / `83a36b0` VM entries/toggle / `4e98b79` 4 UI 组件 + ⌘⇧E / `bed62db` scaffold bump / `7de0f53` T15 4 处修 / `eb1d0e0` 快捷键改 ⌘⌥E)

**Summary**:
- `TimelineEntry` 枚举(`.single/.toolCard/.mergedTools/.compactBoundary`)+ `TimelineAggregator` **两次扫**纯函数算法:第一次识别合并 group(透明事件 api_usage/tool_result/thinking 跳过),第二次线性生成 entries
- `TimelineViewModel` 加 `entries: [TimelineEntry]`(stored)+ `expandedIds: Set<UUID>` + `toggle/toggleExpandAll/isExpanded`;`handleForTesting` hook
- 4 个 UI 组件:`ToolCardView`(折叠一行 + 展开 input/output + 绿✓/红×/progress 状态)/ `MergedToolsView`("Read × N" + 展开 N 小行)/ `ThinkingRowView`(折叠"thinking (N chars)")/ `CompactBoundaryView`(divider)
- `TimelineView` 用 switch-case 按 entry 分派
- 独立 `CommandMenu("Events")` 菜单 + ⌘⌥E "Expand / Collapse All"
- spec §6.4 视觉语言:chevron.right/down 展开按钮(SF Symbols)、RoundedRectangle 卡片背景
- 191 tests 全绿(原 176 + M2.5 新 15:12 aggregator + 3 VM toggle)

**T15 用户反馈 4 处修订**(`7de0f53` + `eb1d0e0`):
1. **Tool 不合并** —— 原 while 遇到非 tool_use 就 break;实际 JSONL 里连续 Read 之间夹 api_usage/tool_result。改两次扫,透明事件跳过继续扫同 cat tool_use;已配对的 tool_use 也合并,对应 result 被 consume 不重复渲染
2. **Timeline 滚动卡顿** —— `entries` 原 computed property 每次 UI 读都 O(N) 聚合;改 stored + handle 末尾 `recomputeEntries()` 一次性更新
3. **⌘⇧E 无效** —— 原 Button 在 `CommandGroup(replacing:.sidebar)` 里不在顶层 menu;改独立 `CommandMenu("Events")`。键位 ⌘⇧E 有 Mail/Xcode/浏览器冲突,换 ⌘⌥E(spec §6.7 原定 ⌘⇧E,M2.7 统一审校时再对齐)
4. **thinking "0 chars" 空壳** —— DB 取证 657/697 条 thinking summary 长度为 0(Claude extended thinking 只留 signature,明文字段空)。aggregator 过滤 summary 空的 thinking 不渲染

**架构合规**(spec §3.2):Aggregator/VM 在 CairnServices;UI 组件在 CairnUI;快捷键在 CairnApp commands;各层职责清晰。

**关键设计决策**(plan pinned,22 条):
- TimelineEntry 枚举代替 Event 数组 + UI 判断模式(聚合逻辑集中在 aggregator,UI 只负责 case 分派)
- Aggregator 纯函数 + 两次扫:O(N) 预索引 + O(N*group) 识别合并 + O(N) 生成
- 只可折叠 entry(toolCard/mergedTools/thinking)提供 toggle,其他永远展开(避免语义反)
- TimelineEntry.id 用 `events[0].id` 不用 UUID() fallback(后者每帧重建所有 row)
- 合并粒度是 category(fileRead 里 Read/NotebookRead 一并合)
- 折叠态不持久化(重开 app 回默认)

**Acceptance**: T15 用户实测:连续 Read 合并、Timeline 滚动流畅、Events 菜单在系统 menu bar 可见、⌘⌥E 展开/折叠生效。

**Known limitations**(M2.6 / M2.7 解决):
- **Tab↔Session 绑定** 仍未做(M2.6;目前多 tab 共享 timeline 仍 auto-switch)
- **"⋮ live" 活跃指示:** M2.6(需要 session 状态)
- **auto-scroll 无手滚检测:** 新消息总拉底,打断用户看历史;macOS 14 无精确 API,M2.7 配 macOS 15+ `onScrollGeometryChange`
- **折叠态不持久化:** 重开 app 全折叠(M3.x)
- **ToolCard JSON 无 syntax highlight:** 纯文本 + lineLimit(M2.7)
- **Merged 展开只显 summary 小行**,不嵌套可再 toggle 的子 ToolCard(M2.7)
- **快捷键 ⌘⌥E 偏离 spec §6.7 定的 ⌘⇧E**:M2.7 冲突审校后统一

---

### M2.4 EventBus + Timeline View 基础

**Completed**: 2026-04-28
**Tag**: `m2-4-done`
**Commits**: 8 个(`d0e23a3` EventStyleMap / `ad3ab37` TimelineViewModel / `1f3ee59` Row+Timeline / `d0565d8` RightPanel+CairnApp 正式化 / `2ba5f55` 7 tests / `026223f` scaffold bump / `0833416` UI 修:auto-switch + SF Symbols + 层级配色)

**Summary**:
- **不新增 EventBus 中间层** —— `EventIngestor.events()` M2.3 已是 fanout AsyncStream,spec §8.5 的 "AsyncStream EventBus" 直接用
- `TimelineViewModel`(CairnServices,`@Observable @MainActor`):订阅 `ingestor.events()`,维护 `currentSessionId + events`;`handleForTesting` 测试 hook(`@testable import`)
- `TimelineView`(CairnUI,`LazyVStack` + `ScrollViewReader` auto-scroll-to-bottom);空态引导文案
- `EventRowView`:SF Symbol icon + summary + 时间戳一行式;error row 红色背景
- `EventStyleMap`:spec §6.4 icon/color 集中映射
- `RightPanelView` 接入 optional vm,瞬态显 "Initializing..."
- `CairnApp` **正式化 Ingestor/Watcher/VM 生命周期**(非 dev env gated);双持 vm(`AppDelegate` 生命周期 + `@State` SwiftUI 观察)
- **176 tests 全绿**(原 169 + M2.4 新 7:5 VM + 2 Row smoke)

**执行阶段修正 / 偏离 plan 的 0 处**:plan 两轮自检提前修好了 6 处,执行时按 plan 零偏差。

**T12 用户反馈的 2 处后续修订**(`0833416` commit):
1. **Session 不刷新** → 改 **auto-switch**:原 plan 锁定第一个到达的 session,用户新开 claude 对话看不到。改为每次 `.persisted` sessionId 不同即切换(清 events + seenIds)
2. **UI 丑 / icon 不统一** → emoji 换 **SF Symbols**(macOS 原生、Dark/Light 自适应、风格统一);配色分三层:icon tint 语义色 / summary `.primary` / timestamp `.tertiary`;error row 加 `.red.opacity(0.08)` 背景;间距放大(3/6→5/8pt)

**关键设计决策**(plan pinned,23 条):
- Parser 纯函数 + Tracker class + Ingestor actor + VM @MainActor 四级清晰分层
- AsyncStream 一路直通,多订阅 fanout
- `Event.withId` / `withPairedEventId` immutable helpers(M2.3 已加)
- M2.4 的 auto-switch 是 T12 迭代产物,保留 Known limitation 明示 M2.6 Tab↔Session 绑定是正式方案

**Acceptance**: 用户 T12 实测新开 claude 对话能立刻切换到 timeline;icon 换 SF Symbols 风格统一;cursor 持久化让 startup 无历史回放(感受"稳定无跳")。

**Known limitations**(M2.6 会解决):
- **Tab↔Session 无绑定**:所有 tab 的 claude 输出共用一个 timeline,auto-switch 覆盖;用户回不到之前 session(events 还在 DB,UI 不显示)
- **连续同类 tool_use 不合并**("Read × 3" 逐条显示,M2.5)
- **api_usage 每条一行**(M2.5 考虑折叠)
- **无快捷键**(⌘⇧E 展开/折叠,M2.5)
- **auto-scroll 不检测用户手滚意图**(上滚看历史会被新 event 打断,M2.5 优化)
- **assistant_thinking 不默认折叠**(spec §6.4 "灰,折叠",M2.5)

---

### M2.3 EventIngestor + Schema v2 + 批量事务

**Completed**: 2026-04-28
**Tag**: `m2-3-done`
**Commits**: 13 个(`d43749d` schema v2 / `86dfd02` upsertByLineBlock / `0ec5628` sync DAO helpers / `1ee7afa` Tracker class + Event helpers / `644961e` EventIngestor 全部 handler / `6af2582` 5 集成测试 / `fa6048b` perf 163ms / `b64d241` harness 切换 / `d3989ae` scaffold bump + docs/push)

**Summary**:
- Schema v2 migration:`events` 加 `UNIQUE INDEX(session_id, line_number, block_index)`—— 解 M2.2 遗留"parser 每次生成新 UUID vs DB 需 stable id"
- `EventDAO.upsertByLineBlockSync`:`ON CONFLICT(sid, line, block) DO UPDATE ... RETURNING id`,一句 SQL 完成 upsert + 返回稳定 id
- `ToolPairingTracker` actor → **class + NSLock**(M2.2 breaking change):能在 `db.writeSync` sync 闭包内同步调 observe
- `Event.withId(_:)` / `withPairedEventId(_:)` immutable helpers(id 是 let)
- `EventIngestor` actor:订阅 watcher stream,**单事务**内编排 upsert → observe → updatePaired → updateCursor
- `JSONLWatcher.WatcherEvent.lines` 加 `byteOffsetAfter` 字段供 cursor 推进
- `Tracker.restore` 修订:只把 `paired_event_id 非空` 的 tool_result 视为已配对,crash-recovery 下孤儿让 tool_use 重进 inflight
- 169 单测全绿(原 160 + M2.3 新 9:2 EventDAO + 4 Tracker + 5 Integration + 1 Perf - 3 原 Tracker async)
- **性能**:1000 行 ingest **163ms**(spec §8.5 硬指标 500ms,3x margin)
- **真实验证**:本机 494 session 全量 ingest,**events 表 44444 行,tool_use/tool_result 99.85% 配对,0 重复(GROUP BY sid+line+block count>1 = 0)**

**架构合规**(spec §3.2):
- EventIngestor 放 CairnClaude/Ingestor/,依赖 CairnCore + CairnStorage
- tracker / parser / watcher / ingestor 四组件单一职责分离
- UI / Services / Terminal 未触及

**执行阶段修正 / 偏离 plan 的小处**:
1. **`test_v1Migration_isIdempotent` 断言从 count==1 改 count==2** —— 加了 v2 migration,schema_versions 应有两行
2. SchemaV2 用 `CREATE UNIQUE INDEX` 而非 `ALTER TABLE ADD UNIQUE`(SQLite 不支持后者),等效
3. 按 plan 自检 v2 的修订已贯穿实现:单事务、start 顺序、restore 严格判 paired

**关键设计决策**(plan pinned,21 条):
- 单事务 atomicity —— 解 plan 两事务方案下 crash 孤儿问题
- Tracker actor→class 配合 sync 闭包
- events 表 `paired_event_id` 无 FK(故意,容忍暂态 null)
- handleRemoved no-op —— `.crashed` 状态留 M2.6
- startup-time tracker.restore 从 DB 重建 inflight

**Acceptance**: T14 用户验收 5 项 + 我代跑磁盘取证全通过;重复 ingest 检测 = 0 是最强证据。

**Known limitations**:
- **UI 不接**:events 流没有消费者(M2.4 Timeline)
- **session state 不转换**:ingestor 不判 `.ended/.abandoned/.crashed`(M2.6)
- **handleRemoved no-op**:M2.6 做
- **restore limit 10_000**:大 session 截断(M2.7 懒加载)
- **workspace 反推**:session 一律 default workspace(M2.6)
- **孤儿历史 tool_result**:`paired=null` 的 15 个 tool_result 是 M2.3 之前的历史遗留,新增数据不会再产生(单事务保证)
- **SwiftLog**:stderr 直写(M2.7)

---

### M2.2 JSONLParser + 12 Event 映射 + tool_use↔result 配对

**Completed**: 2026-04-28
**Tag**: `m2-2-done`
**Commits**: 6 个(`4923028` fixture / `0600088` JSONLEntry / `0c0c0a3` Parser / `965f344` ToolPairingTracker / `946043a` 14 测试 + compact 精确化 / `5b02cee` scaffold bump)

**Summary**:
- CairnClaude 新增 `Parser/` 3 文件:`JSONLEntry`(表层 Codable + 双 ISO8601 formatter fallback)/ `JSONLParser`(纯函数,单行 in → 0-N Event out)/ `ToolPairingTracker`(actor,tool_use↔result in-memory 配对 + `restore(from:)` 接口)
- spec §4.3 12 种 JSONL type 映射全部实现:user_message / tool_result / assistant_text / assistant_thinking / tool_use / api_usage / compact_boundary(派生)/ error(派生);忽略类型 8 种(attachment / system / custom-title / progress / file-history-snapshot / permission-mode / last-prompt / queue-operation / agent-name / tag)
- spec §4.4 tool_use↔result 配对:`ToolPairingTracker.observe` 线性 in-memory 填 `pairedEventId`
- 10 个真实 session 裁剪 fixture(sanitize 后)+ 14 个 parser 测试(12 fixture 断言 + 1 性能 smoke + 1 本机真实 smoke)
- **严格范围控制**:不写 events 表(M2.3)、不接 UI(M2.4)、不改 session state(M2.6)
- **160 单测**(原 143 + M2.2 新 17)全绿

**架构合规**(spec §3.2):Parser 在 CairnClaude 内,只依赖 CairnCore;ToolPairingTracker 同;Tests 用 `resources: [.copy("Parser/fixtures")]` bundle 10 fixture;UI/Storage 未触及。

**执行阶段修正 / 偏离 plan 的 3 处**:
1. **SPM `.copy("Parser/fixtures")` 实际扁平化**:plan 猜 bundle 内保留 `Parser/fixtures/` 前缀,实测只保留**末段目录** `fixtures/`。`Bundle.module.url(subdirectory:)` 要写 `"fixtures"` 不是 `"Parser/fixtures"`
2. **`compact_boundary` 过度派生**(plan 第二轮自检漏了):单靠 `parentUuid == nil` 判,metadata entry(permission-mode / last-prompt 等)**无 parentUuid 字段**时 Swift `as? String` 也是 nil,被误派生。本机 52 行真实 session 派生 18 次(应 1 次)。修:`JSONLEntry` 加 `parentUuidExplicitlyNull` 字段,区分 "JSON 显式 null" 和 "字段缺失",parser 只在显式 null 时派生。修后 18 → 1
3. **Package.swift 加 `.testTarget(resources: [.copy("Parser/fixtures")])`**,plan T8 Step 2 已写

**关键设计决策**(plan pinned,21 条):
- Parser 纯函数无状态;配对状态下沉到独立 actor
- 单行可 yield 0-N Event;blockIndex 作 secondary 排序键
- `message.content` 异构用 `JSONSerialization` + `[String: Any]` 手解析,不强 Codable
- `api_usage` 作为独立 Event 从 assistant 派生,summary 填 `"in=X out=Y cache=Z"`
- 忽略类型返回空但**仍走 compact 派生**(type 与 compact 正交)
- 错误行容错:malformed → 空数组 + stderr warning,不抛
- **`pairedEventId` 是 parser 生成的随机 UUID,非 DB stable id** —— M2.3 EventIngestor 必须先 DAO upsert 用 `(sessionId, lineNumber, blockIndex)` 唯一约束换回 DB stable id、覆盖 `event.id`,再调 `tracker.observe`,否则 `tool_result.paired_event_id` 指向不存在的 id

**本机真实 session 验证**(52 行):
```
api_usage=14  tool_use=8  tool_result=8  user_message=5
assistant_text=3  assistant_thinking=3  compact_boundary=1
```
tool_use/result 完美配对;api_usage 和 assistant 类(3+3+8=14)完美对应。

**Acceptance**: T12 5 项全通过(用户验收)。

**Known limitations**:
- **事件不落盘**:parser 输出被丢弃,M2.3 EventIngestor 接入
- **pairedEventId 非 DB stable id**:M2.3 对接硬约束(见上)
- **cross-entry 配对**:只管单 session 内
- **session 生命周期**:parser 不改 session state,M2.6
- **system.cwd 提取**:parser 返回空(M2.6 Session↔Workspace 映射时处理)
- **SwiftLog**:用 stderr 直写,M2.7 统一

---

### M2.1 JSONLWatcher — FSEvents + vnode + 30s reconcile 三层兜底

**Completed**: 2026-04-28
**Tag**: `m2-1-done`
**Commits**: 12 个(`846c430` probe 笔记 / `fe9c532` IncrementalReader / `26c147b` VnodeWatcher / `ecaca15` FSEventsWatcher / `d6b8bd4` SessionRegistry+Reconciler+ProjectsDirLayout / `c12157c` JSONLWatcher 总装 / `75c8898` dev harness + scaffold bump / `23e6e82` stableUUID + startup reconcile 修)

**Summary**:
- CairnClaude 新增 `Watcher/` 子目录,6 文件单一职责拆:`IncrementalReader`(纯函数 byte-offset 读) / `VnodeWatcher`(DispatchSourceFileSystemObject) / `FSEventsWatcher`(C API) / `SessionRegistry`(actor 内存索引) / `Reconciler`(30s ticker) / `JSONLWatcher`(actor 总装)+ `ProjectsDirLayout`(hash 工具)
- spec §4.2 三层兜底:FSEvents(根目录发现) + per-file vnode(精确触发) + 30s reconcile(全量补漏),外加 startup reconcile(启动即跑一次,不等 30s)
- 对外 API:`JSONLWatcher.events() -> AsyncStream<WatcherEvent>`,三种 case `.discovered(Session)` / `.lines(sessionId, [String], lineNumberStart)` / `.removed(sessionId)`。多订阅 fanout(用 `AsyncStream.makeStream`)
- **严格范围控制**:不解析 JSONL(M2.2 parser)、不写 events 表(M2.3 ingestor)、不接 UI(M2.4)
- 143 单测(原 120 + M2.1 新 23)全绿
- 真实验证:本机 494 个历史 session 全部 discover + ingest,cursor 跨启动 100% 复用(第二次启动仅 15 行新 lines)

**架构合规**(spec §3.2):CairnClaude 只依赖 CairnCore + CairnStorage;CairnApp 新增 CairnClaude 依赖用于 dev harness;UI 层未触及。

**执行阶段修正 / 偏离 plan 的 6 处**:
1. **FSEvents C API 必须加 `kFSEventStreamCreateFlagUseCFTypes`** —— 不加时 eventPaths 是 `char**`,Swift 强转 NSArray SIGTRAP 崩(plan 里漏了这个 flag,执行时 signal 5 定位)
2. **atomic write 触发 Renamed 不是 Created** —— macOS `FileManager.createFile` / `String.write(atomically:true)` 都走 tmp+rename,FSEvents 事件是 Renamed。改 FSEventsWatcher 按 path 存在性把 Renamed 映射到 `.created`/`.removed`,统一语义
3. **plan 自检修好的严重 bug `discover` 覆盖 cursor** —— 这版已预防:先 `SessionDAO.fetch(id:)`,有就复用,避免 `ON CONFLICT DO UPDATE` 把 byte_offset 重置为 0
4. **plan 自检修好的编译错 `events()` actor 隔离违反** —— 这版用 `AsyncStream.makeStream(of:)`
5. **stable UUID 派生**(T12 实测后补的):subagents 子目录下 JSONL 文件名是 `agent-xxx.jsonl` 不是 UUID 格式,`UUID(uuidString:)` fallback `UUID()` 每次随机 → cursor 持久化对这类文件完全失效。用 `SHA256(path)` 前 16 字节派生 v4 格式稳定 UUID,同 path 同 id
6. **startup reconcile**(T12 实测后补的):discover 后不主动 ingest,历史 session 要等 30s reconcile tick 才读。`start()` 末尾跑一次 `runReconcile()`,启动即全量 ingest

**关键设计决策**(plan pinned,24 条):
- 每组件一个文件,单一职责(spec §3.2)
- `IncrementalReader` 纯函数;"永远不读半行"统一 `removeLast()` 处理 trailing \n 边界
- `FSEventsWatcher` / `VnodeWatcher` 单订阅(覆盖 continuation)—— 由 JSONLWatcher 单持有,无影响
- `JSONLWatcher.events()` 多订阅 fanout,**必须在 start() 之前订阅**(否则漏 `.discovered`)
- cursor 每次 ingest 立即写 DB(async,极端情况丢最后一 chunk 可接受,M2.3 ingestor idempotent 兜底)
- session workspace 归属 M2.1 简化为 default;M2.6 用 system.cwd 精确映射

**Acceptance**: T13 验收清单(用户 + Claude 均跑通 5 项核心指标),详见 `docs/superpowers/plans/2026-04-28-m2-1-jsonl-watcher.md`。

**Known limitations**:
- **workspace 反推**: session 一律挂到 default workspace(M2.6 升级)
- **session 生命周期**:只维护 `.live`,`.ended`/`.abandoned`/`.crashed` 留 M2.6
- **FSEvents 只看未来**:历史 JSONL 靠启动时 `scanExisting` 一次性加载,500+ session 下启动略重(M2.7 懒加载优化)
- **cursor 写频率**:每 chunk 一次 upsert(M2.7 视负载合批)
- **Cursor 丢最后一 chunk**:Cmd+Q 瞬间 async updateCursor 中断可能丢;下次启动 reconcile 发现 size > offset 会重读,M2.3 ingestor 必须对 event 去重
- **SwiftLog**:用 stderr 直写(M2.7 统一)
- **UI 不接**:本 milestone 只发流,无 UI 消费(M2.4)

---

### M1.5 水平分屏 + OSC 7 cwd 跟踪 + 布局 SQLite 持久化

**Completed**: 2026-04-28
**Tag**: `m1-5-done`
**Commits**: 9 个 — 实现 3(`983b268` / `805b142` / `251c4de`)+ 验收修复 6(`b599520` docs / `c4ccbb3` 分屏 collapse + UI / `d3c370a` 同步写 / `47fbb3b` AppDelegate 保底 / `c663f0a` **真·根因:bootstrap workspace** / `4904634` Package.swift 修)

**Summary**:
- 架构重构:M1.4 的 `TabsCoordinator` 拆为 `TabGroup`(单组 tabs)+ `SplitCoordinator`(1-2 组)
- `TabSession` 升级为 `@Observable`(OSC 7 动态改 title 需要 reactive)+ 新 `updateCwd` 方法
- **OSC 7 cwd 跟踪**:`OSC7Parser` 解析 `file://host/path`(用 URL API 自动 percent-decode),`ProcessTerminationObserver` 2 个 callback(onTerminated + onCwdUpdate),`SessionHolder` forward-ref 解决 observer-先 / session-后构造
- **水平分屏**:MainWindowView 用 `HSplitView` 渲染 1-2 个 `TabGroupView`;`⌘⇧D` 触发 `SplitCoordinator.splitHorizontal`;关 tab 到空组自动 collapse
- **布局持久化**:`LayoutSerializer`(PersistedLayout schemaVersion=1,Codable);`.task` 异步 DB init + restore;`.onChange` 监听多维度 state → `scheduleAutoSave` debounce 500ms 写 `LayoutStateDAO`;`var created: TabSession!` forward-ref 让 restore callback 用新 UUID
- 120 tests 全绿(M1.4 的 110 + M1.5 净增 10 —— 新 17 - 删 TabsCoordinatorTests 的 7)

**架构合规**(spec §3.2):
- `LayoutSerializer` 留在 CairnTerminal **只做 pure encode/decode/snapshot/restore**,不依赖 CairnStorage
- DB 交互(`LayoutStateDAO.fetch` / `.upsert`)移到 `CairnApp.swift` —— orchestrator 层桥接 CairnTerminal + CairnStorage
- Package.swift:`CairnApp` deps += `[CairnTerminal, CairnStorage]`

**执行阶段修正**:
- 架构违反:初稿 `LayoutSerializer` 直接 `import CairnStorage`,build 报 `missing required module 'GRDBSQLite'` → 移除 load/save 到 CairnApp
- JSON 格式断言:`CairnCore.jsonEncoder` 用 `.sortedKeys` 无 `.prettyPrinted`,紧凑格式无空格;测试断言 `"schemaVersion":1`(去掉空格)

**验收阶段 4 轮修复**(用户视觉验证 → 日志诊断 → 逐层定位):
1. **轮 1**(c4ccbb3):UI 问题 — TabBarView × 按钮绕过 `SplitCoordinator.collapseEmptyGroups` → 加 `closeTab(in:id:)` 统一入口;active 分屏全边框太重 → 改顶部 2pt accent 细条;`defaultWorkspaceId = UUID()` 每次启动新 id → 硬编码稳定 UUID;去 500ms debounce
2. **轮 2**(d3c370a):去 debounce 仍不恢复 —— 磁盘取证 `layout_states` 表空 → 猜是 `Task { await upsert }` 被 Cmd+Q kill → `CairnDatabase` actor→`final class`,加 `writeSync`/`readSync`,DAO 加 `upsertSync`,`scheduleAutoSave` 同步写
3. **轮 3**(47fbb3b):仍然不恢复 —— 怀疑 App struct @State `database` value-type 时序 → 新增 `CairnAppDelegate: NSApplicationDelegate` class 持有 `database + split`;`applicationWillTerminate` 里再同步保底 flush;关键节点 stderr 诊断日志
4. **轮 4**(c663f0a,**真·根因**):从日志第一次看到 `SQLite error 19: FOREIGN KEY constraint failed` —— `layout_states.workspace_id REFERENCES workspaces(id)`,但 app 从没往 workspaces 表插过硬编码默认 id → `initializeDatabase` 里先 `WorkspaceDAO.upsert` 默认 workspace(id = 0000...0001, cwd = ~),之后所有 save 通过
5. **收尾**(4904634):轮 4 新 `import CairnCore`,Package.swift `CairnApp` deps 补 `CairnCore`

**经验总结**:写 FK 约束的 DAO,app 启动时必须 bootstrap 前置表行,否则 upsert 全挂。M3.5 接真实 Workspace 管理时补一个 app 级 bootstrap 回归测试(120 单测都是 DAO 内部先插 workspace,没覆盖"裸启动"路径)。

**关键设计决策**(plan pinned):
- ZStack 保活 + HSplitView 2 分屏 + onChange 派生值 debounce 持久化
- restore 时 Swift `let id` 限制,PTY 全新启动用新 UUID,activeTabId 按**位置**匹配(影响极小,id 未暴露给用户)
- 不持久化滚动缓冲(spec §5.6)

**Acceptance**: 见 M1.5 计划文档 T11 验收清单(7 项肉眼)。

**Known limitations**:
- OSC 7 需 shell 主动发(已在 README 写 zsh/bash/fish 配置示例;shell 侧 chpwd hook 兜底留 v1.5+ 原生方案)
- restore 后 tab 用新 UUID(与 persisted.id 不等价)
- 分屏拖拽位置不持久化(v1 接受)
- 窗口宽度/位置由 macOS `NSWindow` frame autosave 管(标准 macOS 行为,不是 Cairn 记的)
- 本地化留 M4.1

---

### M1.4 多 Tab 管理 + TerminalSurface 封装 + PTY 生命周期

**Completed**: 2026-04-27
**Tag**: `m1-4-done`
**Commits**: 5 个(`6e4edb4` / `56fed9c` / `2406cea` / `888e7a0` / `dcb4953`)

**Summary**:
- `CairnTerminal.TabSession`(@MainActor class)包 `LocalProcessTerminalView` + 领域元数据 + `ProcessTerminationObserver` 强引用
- `CairnTerminal.TabsCoordinator`(@Observable)管 tabs + activeTabId;API:openTab / closeTab / closeActiveTab / activateTab / activateNextTab / activatePreviousTab
- `TerminalSurface` 改为 `init(session:)` + `makeNSView` 返回 session 既有 NSView —— tab 切换时 PTY + 缓冲保活
- 删除 M0.2 遗留的 `ContentView.swift`(死代码)
- `CairnUI.TabBarView` 胶囊样式 + 关闭按钮 + 左 3pt 灰色状态条(v1.4 全灰;blue/orange/red 留 M2.x)
- `MainWindowView` Main Area 用 ZStack 渲染所有 tabs:active `.opacity(1)` `.allowsHitTesting(true)`,inactive `.opacity(0)` `.allowsHitTesting(false)`
- `CairnApp` Scene-level 注入 `TabsCoordinator`,onAppear 自动开一个 tab,commands 加 `⌘T` / `⌘W` / `⌘L` / `⌘⇧L`
- shell 退出通过 `ProcessTerminationObserver` 触发 `removeTabWithoutTerminate`,tab 自动从 coordinator 移除
- **110 tests 全绿**(M1.1 54 + M1.2 45 + M1.3 4 + M1.4 7)

**执行阶段修正 4 处 SwiftTerm/SwiftUI API 差异**(plan 预判部分命中):
- `process.terminate(asKillSignal: true)` → `process.terminate()`(SwiftTerm 1.13 签名无参)**— plan 风险 5 已预判,执行时 1 次 build 定位**
- `LocalProcessTerminalViewDelegate` 4 方法 source 类型混用(`sizeChanged`/`setTerminalTitle` 要 `LocalProcessTerminalView`,`hostCurrentDirectoryUpdate`/`processTerminated` 要 `TerminalView`)
- `WindowGroup("Cairn") { ... }` 在 macOS 14+ 有 `content:` / `makeContent:` 签名歧义 → 显式 `content:` 标签
- `withAnimation { openTab(...) }` 泛型 Result 推断为 `TabSession` 与 Button Void 冲突 → `_ =` discard

**关键设计决策**(plan pinned):
- ZStack + opacity/hitTesting 保活策略
- TabSession @MainActor class 强引用 LocalProcessTerminalView
- 关 active tab 切前驱优先
- Tab 左边框 v1 全灰
- 新 tab cwd 继承 active tab
- 不加 XCTest UI 自动化

**Acceptance**: 见 M1.4 计划文档 T12 验收清单。

**Known limitations**:
- OSC 7 cwd 跟踪留 M1.5(现在 cwd 不随 shell `cd` 动态更新)
- 布局持久化(关 App 再开 tabs 全丢)留 M1.5
- Tab 左边框 blue/orange/red 颜色语义留 M2.x
- Tab 标题不响应 `setTerminalTitle`(OSC 2)留 M1.5

---

### M1.3 SwiftUI 主窗口三区 + Sidebar/Panel 可折叠

**Completed**: 2026-04-27
**Tag**: `m1-3-done`
**Commits**: 3 个(`3a90342` / `5e0be96` / `060ddf5`)

**Summary**:
- `MainWindowView` 用 `NavigationSplitView` + `.inspector()` 组装 spec §6.1 三区
- Sidebar(280pt)显"No workspaces yet" 空态,Task 列表留 M3.1
- Main Area 保留 M0.2 的 TerminalSurface + 新增 Tab Bar / Status Bar 占位
- Right Panel(Inspector,360pt)3 小节占位:Current Task / Budget / Event Timeline
- Toolbar 有 Workspace 下拉 / 通知 / 设置 / Inspector toggle;`⌘I` 切 Inspector,`⌘⇧T` 切 Sidebar(通过 Scene-level `@State` + `CommandGroup(replacing: .sidebar)` 实现,**纯 SwiftUI**,无 AppKit 桥接)
- `MainWindowViewModel` @Observable + 4 单测(M3.5+ Workspace 管理扩展预留)
- StatusBarView 底部显示 "Cairn v" + `CairnCore.scaffoldVersion`(DRY,避免硬编码)
- 全仓库 **103 tests** 全绿,CairnApp 启动符合 spec §6.1 设计图

**关键设计决策**(plan pinned):
- 三栏 API:`NavigationSplitView` + `.inspector()` 原生组装(不自建 HStack)
- 折叠状态 Scene-level `@State`(非 ViewModel),commands Button 直接 toggle state
- Main Area 不碰 M0.2 的 TerminalSurface(v1 主区只放终端,spec §6.3)
- 不加 XCTest UI 自动化(spec §8.4 "手动验收";UI 自动化 M4.2 统一做)
- 本 milestone 实装 2 个快捷键(⌘⇧T / ⌘I);其余 15 个留 M1.4+

**执行中自检预先修复的 4 处 bug**(详见 plan 二次修订 commit `02418bb`):
- `struct ToolbarContent: ToolbarContent` 递归类型歧义 → 改名 `CairnToolbarContent`
- `NSApp.tryToPerform(toggleSidebar:)` AppKit 桥接脆弱 → 重构为 Scene-level `@State` + Commands
- `Text("Cairn v0.3.0-m1.3")` 硬编码版本 → 引用 `CairnCore.scaffoldVersion`
- CairnUI 未声明 CairnCore 直接依赖 → Package.swift 加 `CairnCore` 到 CairnUI deps

**Acceptance**: 见 M1.3 计划文档 T11 验收清单(含**必做 8 项肉眼验收**)。

**Known limitations**:
- Sidebar / Panel 真实内容(Task 列表 / Budget 详情 / Event 时间线)留 M3.1-M3.3
- 布局折叠状态不持久化(关了 App 再开重置),LayoutStateDAO 接入留 M1.5
- 除 ⌘⇧T / ⌘I 外,spec §6.7 的 15 个快捷键留 M1.4 / M3.x
- 本地化(`String(localized:)`)留 M4.1

---

### M1.2 CairnStorage(GRDB + 11 表 + migrator + DAO)

**Completed**: 2026-04-27
**Tag**: `m1-2-done`
**Commits**: 12 个(`5819839` … `098b8ed`)

**Summary**:
- Package.swift 加 GRDB 7.10.0 依赖,**tools-version 5.9 不变**(自检发现 SwiftPM 允许低 tools 包依赖高 tools 包;本机 Swift 6.3.1 解析 GRDB 的 6.1 manifest 无障碍 —— 实证通过)
- `CairnStorage` 模块完整落地:`CairnDatabase` actor(封装 `DatabaseQueue`)+ `DatabaseConfiguration`(cache_size/foreign_keys PRAGMA)+ `DatabaseMigrator`(v1 schema)+ 9 个 DAO + Row 映射辅助(UUID 显式 `DatabaseValueConvertible` 扩展)
- **11 张表全部创建**,索引齐全(spec §D),`schema_versions(1, ...)` 已插入
- **99 个单测全绿**(M1.1 的 54 + M1.2 的 45)—— 超 plan 目标 45
- CASCADE / UNIQUE / 分页 / 枚举 rawValue roundtrip / JSON 列 / 内存 DB / 幂等 migration 全覆盖

**关键设计决策**(plan pinned):
- `DatabaseQueue` 不是 `Pool`(桌面单进程,写少读多)
- Date 存 ISO-8601 TEXT(含 fractional seconds,毫秒精度)—— spec §7.2 硬要求
- DAO 手写 `from(row:)` / `toArguments()`,不用 GRDB `FetchableRecord` 自动合成 —— 列名 snake_case 与 Swift camelCase 映射精确可控
- `Plan.steps` 用 `steps_json` 列存 JSON(spec §D)
- `CairnTask.sessionIds` 走 `task_sessions` 关联表,DAO upsert 用 delete-then-insert 同步
- **upsert 用 `ON CONFLICT(id) DO UPDATE`** 而非 `INSERT OR REPLACE` —— 后者会在 UNIQUE 冲突时删除冲突行,破坏语义

**执行中遇到并解决的问题**:
- GRDB 7 的 `queue.read/write` 是 async,Database actor 方法体改用 `try await`
- `INSERT OR REPLACE` 对 UNIQUE(cwd) 冲突不抛错 → 改为 `ON CONFLICT(id) DO UPDATE`
- ISO-8601 默认不含 fractional seconds,`Date()` 有微秒精度,round-trip 丢精度 → 启用 `.withFractionalSeconds`,测试用整数秒 `Date(timeIntervalSince1970:)`
- `XCTAssertNil/Equal` 的 autoclosure 不支持 async 调用 → 先 `let val = try await`,再断言
- `task_sessions` 的 PRIMARY KEY 让 SELECT 默认按 session_id 字典序,导致 roundtrip 测试 flaky → DAO 强制 `ORDER BY session_id`,测试对齐

**Acceptance**: 见 M1.2 计划文档 T15 验收清单。

**Known limitations**:
- Approval DAO 是 v1.1 skeleton(CRUD 可用),领域类型封装留 v1.1 HookManager
- `synchronous=NORMAL` PRAGMA 未启用,M4.3 性能测试时按需加
- 备份 / 归档 / 诊断导出(spec §7.6)留 M4.3
- raw_payload_json 90 天归档策略(spec §7.4)留 M4.3
- Date 精度上限毫秒(SQLite TEXT + ISO-8601 fractional 的物理极限)

---

### M1.1 CairnCore 数据类型

**Completed**: 2026-04-24
**Tag**: `m1-1-done`
**Commits**: 11 个(`334281d` … `e3ede8a`)

**Summary**:
- CairnCore 从占位升级为完整领域模型,11 个新 Swift 源文件 + 10 个测试文件
- **7 实体**:`Workspace` / `Tab` / `Session` / `CairnTask` / `Event` / `Budget` / `Plan`(+ 内嵌 `PlanStep`)
- **6 状态 enum**:`TabState`(2) / `SessionState`(5) / `TaskStatus`(4) / `BudgetState`(4) / `PlanStepStatus`(3) / `PlanStepPriority`(3)
- **`EventType` 封闭 12 种**(对齐 spec §2.3,含 v1.1 预留 approval_*);**`ToolCategory` 开放集**(struct RawRepresentable)+ toolName 查表(含 M0.1 probe 扩展)+ `PlanSource` 3 种来源
- **`Budget.computeState()` 纯函数**推导 state,遵守 spec §3 "Core 无状态" 纪律
- **`CairnCore.jsonEncoder` / `jsonDecoder`** 共享实例,ISO-8601 日期策略
- **54 个单元测试全绿**(远超 spec §8.4 要求的 10 个);跨 7 实体 JSON round-trip 覆盖

**关键设计决策**(plan pinned):
- 类型名 `CairnTask` 不是 `Task` —— 避免 Swift 标准库 `Task`(结构化并发)命名冲突
- `ToolCategory` 用 struct RawRepresentable 实现"开放 enum";已知 12 种作静态常量,未知 toolName 兜底 `.other`
- Equatable/Hashable 按所有字段(Swift synthesized),保证 round-trip 测试能真实验证字段完整性
- Budget 状态推导为纯函数 `computeState()`;`.paused` 由用户手动设置,computeState 不自动恢复
- 共享 JSONEncoder/Decoder 单例,但 `encode()` 未官方保证并发安全,M2.3 并发场景再按需改

**Acceptance**: 见 M1.1 计划文档 T14 验收清单。

**Known limitations**:
- Approval 实体(spec §2.1 列出,v1.1 起用)本 milestone **不实现**
- `PlanStep` 的 markdown 解析器留 M3.4(PlanWatcher)
- Budget cost 计算依赖 api_usage 累加,具体模型价格表留 M3.3(BudgetTracker)
- 所有实体的 SQLite 持久化留 M1.2(GRDB schema + DAO)

---

### M0.2 Hello World macOS App

**Completed**: 2026-04-24
**Tag**: `m0-2-done`
**Commits**: 8 个(`7f51602` … `ebb8266`)+ 本 log 记录

**Summary**:
- Package.swift 7 target(6 库 + 1 executable)按 spec §3.2 严格依赖方向声明
- SwiftTerm 1.13.0 作为唯一第三方依赖接入(只暴露给 CairnTerminal);Package.resolved 纳入版本
- `@main` SwiftUI App + ContentView 全屏嵌入 TerminalSurface(login shell idiom,走 .zprofile)
- `scripts/make-app-bundle.sh` 把 `swift build` 产出打包成未签名 `build/Cairn.app`(Info.plist CFBundleIdentifier=com.cairn.app,plutil -lint 通过)
- `swift build`(首次 40s,后续 ~3s)+ `swift test --filter CairnCoreTests`(2 tests passed)全绿
- `open build/Cairn.app` 成功拉起 CairnApp 进程(Mach-O arm64,parent=launchd),能干净退出

**关键修订**(自检发现,详见 `docs/superpowers/plans/2026-04-24-m0-2-hello-world.md` Self-Review §6):
- Plan 初稿 T6 TerminalSurface 含 3 个会让 swift build 编译失败的 API bug(`Terminal.getEnvironmentVariables` 不存在 / `view.send(data:)` 签名错 / `cd` 发送 hack 冗余)—— 用户要求深度自检时通过实读 SwiftTerm v1.13.0 源码修正,执行阶段 T6 一次编译通过

**Acceptance**: 见 M0.2 计划文档 T11 验收清单。

**Known limitations**:
- 只有 `CairnCoreTests` 1 个 test target(2 个测试);其他 5 个库的测试随它们 milestone 填入
- TerminalSurface 不做 delegate 回调(M1.4)、不做 OSC 7 cwd 跟踪(M1.5)
- 无 icon.icns,Dock 用 macOS 默认 generic 图标;设计稿 / 图标留待 v0.1 Beta(M2.7)
- 未签名路径,若 `.app` 产物被传输跨机(如下载到其他 Mac)触发 Gatekeeper 需 `xattr -rd com.apple.quarantine build/Cairn.app`;本机 swift build 产物不带 quarantine,直接 open 不触发

---

### M0.1 仓库基础设施 + Probe 勘察

**Completed**: 2026-04-24
**Tag**: `m0-1-done`
**Commits**: 9 个(`d7aa1a0` … `d76f892`)

**Summary**:
- 仓库骨架文件就位:LICENSE(MIT)/ .gitignore / README / milestone-log
- GitHub remote 配置 + main 首推(https://github.com/fps144/cairn)
- Python probe 脚本完整,**7 单测全绿**
- `probe/probe-report.md` 基于 **517 个真实 session / 48,206 事件行** 生成
- ADR 0001 记录 10 个 probe 问题的答复 + 5 条 spec 修订清单
- Spec 按 ADR 修订 5 处(§2.4 / §4.3 / §4.5 / §4.6 / §4.9),均带 [修订于 M0.1] 标记

**重要发现**(详见 `docs/decisions/0001-probe-findings.md`):
- PlanWatcher 必须改为监听**全局** `~/.claude/plans/`(不是 per-workspace)
- JSONL 第一条 entry 常为 `permission-mode` / `file-history-snapshot`,需扫描找第一个 `type=system` entry 才能拿 `cwd`
- Claude Code 退出**不写 end 标记**,Session 生命周期判定要去掉"末条是 assistant"要求
- Hash 规则:cwd 中 `/`、`_`、`.` 全变 `-`,正向可算逆向有歧义
- `message.usage` 实测 12 个字段(spec 初稿只假设了 4 个),v1 Budget 仍只提 4 项,其余归档
- 发现 11 种 JSONL 顶层 entry type(spec 初稿只列 6 种)

**Acceptance**:见 M0.1 计划文档 T12 验收清单(本 session 结尾输出)。

**Known limitations**:
- Appendix B Q10 大文件 ingest 性能测试延后到 M2.3(已知 max=68MB, P99=3MB)
- Hook schema 无法从现状观察验证(用户尚未配过 hook),M2.x 实现 HookManager 时参考 Claude Code 官方文档
