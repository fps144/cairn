# Changelog

All notable changes to Cairn will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0-beta] — 2026-04-30

### 首发 🎉

Cairn v0.1 Beta — 一款专为 Claude Code 用户的 macOS 原生 AI 终端。

把 Claude Code 的每次会话变成可读、可审查、可回放的任务轨迹。

### Phase 1:终端基座(M0.1 – M1.5)

- **SPM 6 模块**:CairnCore / CairnStorage / CairnClaude / CairnTerminal / CairnServices / CairnUI / CairnApp,严格依赖方向(spec §3.2)
- **SQLite 持久化**:GRDB 7,12 表 + schema v2 migration
- **SwiftTerm 多 tab + 水平分屏**(最多 2 组,⌘⇧D 触发)
- **PTY 进程生命周期** + OSC 7 cwd 跟踪 + 退出回调
- **布局跨启动恢复**:tabs / cwd / split / activeTab 全部持久化

### Phase 2:Claude 观察(M2.1 – M2.7)

- **JSONLWatcher**(M2.1):FSEvents + per-file `DispatchSourceFileSystemObject` + 30s reconcile 三层兜底监听 `~/.claude/projects/`,跨启动 cursor 持久化
- **JSONLParser**(M2.2):12 Event 映射(`user_message` / `tool_use` / `tool_result` / `assistant_text` / `assistant_thinking` / `api_usage` / `compact_boundary` / `error` 等)+ tool_use↔result 配对追踪 + 10 fixture
- **EventIngestor**(M2.3):单事务批量 upsert + cursor 推进,1000 行 < 200ms(spec 要求 < 500ms)
- **Timeline View**(M2.4):AsyncStream EventBus + LazyVStack + SF Symbols 视觉(从原 emoji 升级,Dark/Light 自适应)
- **工具卡片**(M2.5):连续同类合并("Read × 3")+ 折叠交互 + ⌘⌥E 一键展开 + 空 thinking 过滤
- **Tab↔Session 绑定**(M2.6):按 cwd 精确匹配自动绑 tab + Session 生命周期 5 态机(`live` / `idle` / `ended` / `abandoned` / `crashed`,spec §4.5)+ auto-scroll pin 控制

### Architecture

- **193+ 单元测试** 覆盖:CairnCore 数据模型、GRDB DAO、JSONL parsing、event ingestion、timeline aggregation、session lifecycle 状态机
- **永不签名分发**:MIT 项目不购买 Apple Developer 账号,xattr 解除 quarantine 路线(spec §A9/A14)

### Known Limitations(v1.x 解决)

- **未签名分发** —— 首次需 `xattr -rd com.apple.quarantine` 解除
- **Apple Silicon 专属**(arm64)—— Intel Mac x86_64 暂不支持(v0.2+ 评估)
- **Hook 审批未实现**(v1.1 开启)
- **MCP 集成不做**(v2 再评估,spec §4.1)
- **历史 session 导入 UI 未做**(v1.1)
- **外部 terminal 里跑的 claude** 不自动绑 Cairn tab(需 cwd 精确匹配)
- **同 tab 多 session** —— 一个 tab 连跑两次 `claude` 新 session 覆盖旧绑定(v1.5+ 加 session 切换历史)
- **快捷键 ⌘⌥E**(spec §6.7 原定 `⌘⇧E`,实测与系统/Mail/Xcode 冲突改 ⌘⌥E)
- **TabSessionBroker 单测**(M2.6 跳过,SPM 不支持 `@testable import` executable target;v1.1 加 XCUITest 集成测试)

### 里程碑与 Tag

| Tag | 节点 | 内容 |
|---|---|---|
| `m0-1-done` – `m0-2-done` | 2026-04-23 | Phase 0 探路 |
| `m1-1-done` – `m1-5-done` | 2026-04-24 – 28 | Phase 1 终端基座 |
| `m2-1-done` – `m2-6-done` | 2026-04-28 – 30 | Phase 2 Claude 观察 |
| `m2-7-done` / `v0.1.0-beta` | 2026-04-30 | v0.1 Beta 发布 🎉 |

### What's Next

- **v0.2**:x86_64 Universal Binary + Homebrew Cask + auto-update + 命令面板
- **v1.0**:Hook 审批 + 历史导入 UI + Plan/Todo 面板 + Budget 详情
- **v1.5+**:多 session 并排视图 + Hook 规则可视化编辑器 + checkbox `- [ ]` 解析

---

## Development model

🤖 Built with **Claude Opus 4.7** 主导开发,[@sorain](https://github.com/sorain) 产品验收。

12 个 milestone(M0.1 → M2.7)、~4 周完成 v0.1 Beta。Plans / specs / decision records 完整开源,见 [`docs/`](docs/)。

MIT Licensed.
