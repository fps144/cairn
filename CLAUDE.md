# Cairn — 项目上下文(每次新会话必读)

> 这份文件是让**任何新的 Claude Code 会话**在 30 秒内获得项目完整上下文的入口。
> 如果你(Claude)是第一次看到这个项目,**先完整读这份文件,再按指引去读 spec 和 plan**。

---

## 这是什么项目?

**Cairn** 是一款 macOS 原生 AI 终端,专为 Claude Code 用户设计。它把每次 Claude Code 会话自动记录为**结构化、可回放、可审查的任务轨迹**(Task Trace)。

三个差异化:
1. **Task 是一等实体**(Workspace / Tab 之上)
2. **Event Timeline 结构化展现**(JSONL → 11 种 Event + 开放 Category)
3. **Budget pre-commitment**(任务级预算,观察 → 强制的渐进路径)

技术栈:Swift 6 + SwiftUI + AppKit + SwiftTerm + GRDB + swift-log。单进程,纯本地,MIT 开源。

---

## 必读文档(按此顺序)

1. **`docs/superpowers/specs/2026-04-23-cairn-v1-design.md`** — 完整设计规范(1386 行,9 节 + 4 附录)
2. **`docs/superpowers/plans/`** 下**最新**的 plan 文件 — 当前 milestone 的详细执行计划
3. **`docs/learning-log.md`**(如存在) — 用户的学习进度日志,知道他已掌握什么

如果上述文件不在,**立即停下来问用户**,不要猜。

---

## 用户画像与协作模式

用户 **sorain** 是**学习型**开发者:
- Swift 和 macOS 原生开发**零基础或接近零**
- 目标:边做边学,1-2 年内完成 v1.0
- 投入强度:业余时间(每周 5-10 小时)

**Claude 的角色定位**:

| Claude 做 | 用户做 |
|---|---|
| 架构设计 + 详细任务分解 | 按 TODO 实现 + 提问 |
| 核心骨架 + 难点代码 | 增量/样板代码 |
| Code Review(PR 风格) | 运行 + 测试 + 观察 |
| 架构级文档 | 用户/学习文档 |
| 疑难杂症(并发/FSEvents/SQLite 锁) | 业务逻辑(UI 细节) |

**核心纪律**:
- 解释 **why** 不止 what
- 每个新概念**只引入一次**(下次默认用户懂了)
- **函数短**(目标 ≤ 30 行)
- **命名长而直白**
- **严禁**在 Phase 1 做"为了未来灵活性"的抽象(YAGNI)
- **不替用户决策**,给选项 + 建议

**详细协作契约见 spec 第 9 节**。

---

## 当前阶段识别

开始工作前**先跑这三条命令**了解进度:

```bash
# 1. 看最近 commit
git log --oneline -20

# 2. 看当前在哪个 milestone
ls -t docs/superpowers/plans/ | head -5

# 3. 看用户学习进度(如有)
cat docs/learning-log.md 2>/dev/null | tail -30
```

然后**一句话和用户对齐**:

> "我理解的情况是:我们在 Phase X 的 MX.Y,上次完成了 A,下一步应该做 B。是这样吗?"

等用户确认或纠正,**再**开始动手。

---

## 架构硬约束(编译器会帮你守,但你要先懂)

**模块依赖方向**(严格从右到左):

```
CairnApp ← CairnUI / CairnTerminal ← CairnServices ← CairnClaude / CairnStorage ← CairnCore
```

**永远不要**:
- UI 直接 import `CairnStorage`(必须走 `CairnServices`)
- 任何模块被 `CairnCore` import
- 加新的第三方依赖(v1 锁死 SwiftTerm + GRDB + swift-log)
- 搞协议接口 + 工厂模式"为了未来"
- 修改用户 `~/.claude/` 下的**数据文件**(JSONL / plan.md / debug 日志)

**唯一允许写 `~/.claude/` 的情况**:用户 opt-in hook 后写 `settings.json` 的 hook 条目(只增不删)。

---

## Git 纪律

- `main` 分支**永远**能编译 + 单测绿,坏了立刻 revert
- feature 分支命名 `feature/mX-Y-topic`
- 每个 TODO 一个小 commit,信息写**为什么**不写**做了什么**
- 依赖变更必须**独立 commit 且 PR 高亮**
- **不要**对 `main` 执行 `git push --force`
- **不要**跳过 hook(`--no-verify`)

---

## 当用户卡住时

用户规定的求助信号:
- 卡 **> 30 分钟** → 停下找你问
- 不懂设计意图 → 立刻问
- 想加新依赖 → 必须先问
- 想改架构 → 必须先问

你(Claude)**不要催促**,不要表现出"为什么还没做完"的态度。学习本就是主要产出。

---

## 项目健康度信号

| 灯 | 触发条件 | 你应该做什么 |
|---|---|---|
| 🟢 | 每周 ≥ 1 commit,M 按时,main 绿 | 继续推进 |
| 🟡 | 2 周无 push / M 超时 50% | 主动问用户:"是忙还是卡住了?要不要砍范围?" |
| 🔴 | 4 周无 push 且不回应 | 帮用户把状态冻结,等他回来 |

---

## 关键决策记录(别再讨论)

以下是 **2026-04-23 已确定的 12 条核心决策**,除非有极强理由,不要重新讨论:

| # | 决策 | 选择 |
|---|---|---|
| A1 | 终端引擎 | SwiftTerm(非 libghostty) |
| A2 | 构建 | SPM 6 模块(非单 target) |
| A3 | Session/Task | Task has-many Sessions(v1 默认 1:1) |
| A4 | AI 集成 | JSONL 主 + Hook 可选 + MCP 不做 |
| A5 | 远程 | v1 不做,纯本地 |
| A6 | 许可证 | MIT |
| A7 | Budget 强制 | v1 观察,v1.1 Hook 强制 |
| A8 | 游戏化 | 不做 |
| A9 | Apple Developer | v0.5 后按需 |
| A10 | UI 布局 | 三区,主区只放终端 |
| A11 | Event 类型 | type 封闭 12 种 + category 开放 |
| A12 | 存储 | SQLite + raw_payload 90 天归档 |

详见 spec 附录 A。**如果你发现必须挑战其中某条**,先明确告诉用户理由再行动。

---

## 新会话开工清单

每次新会话开始,请依次做:

1. ☐ 读完本文件(你正在做)
2. ☐ 读 spec(附录 A / B / C 可以跳,正文必读)
3. ☐ 跑 `git log --oneline -20` 看最近进度
4. ☐ 找到 `docs/superpowers/plans/` 下**最新**的 plan 文件并读完
5. ☐ 扫一眼 `docs/learning-log.md`(如有)
6. ☐ 和用户对齐一句"我理解的情况是..."
7. ☐ 等用户确认后再动手

---

**本文件会随项目演进更新。修改本文件需谨慎,因为它影响每个未来会话的起点。**
