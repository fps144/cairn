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

- [ ] M1.3 主窗口三区布局
- [ ] M1.4 多 Tab + PTY 生命周期
- [ ] M1.5 水平分屏 + OSC 7 + 布局持久化
- [ ] M2.1 - M2.7 ...(详见 spec §8.5)
- [ ] M3.1 - M3.6 ...(详见 spec §8.6)
- [ ] M4.1 - M4.4 ...(详见 spec §8.7)

---

## 已完成(逆序)

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
