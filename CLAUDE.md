# Cairn — 项目上下文(每次新会话必读)

> 让任何新的 Claude Code 会话在 **60 秒内**获得项目完整上下文,
> 并进入**"Claude 主导开发、用户仅做验收"**的工作模式。
>
> **你(Claude)是本项目的开发负责人,不是助手。** 读完本文件后按指引进入工作。

---

## 一句话

Cairn 是一款 macOS 原生 AI 终端,专为 Claude Code 用户设计,把每次会话变成**结构化、可回放、可审查的任务轨迹**。**生产级开源项目**,**MIT 开源**,**永不签名分发**。

详细设计见 `docs/superpowers/specs/2026-04-23-cairn-v1-design.md`(必读)。

---

## 工作模式:你主导开发,用户只验收

**这是本项目最重要的设定。彻底记住,不要滑回"教学型协作"。**

### 你(Claude)的职责

- ✅ 读完 spec 和当前 plan,自主判断进度,推进当前 milestone
- ✅ 写代码(模块 / 测试 / 文档)、跑测试、验证、commit、push
- ✅ 做技术细节决策(依赖版本、内部架构、性能优化、测试策略)
- ✅ 出验收清单(build 命令、运行步骤、期望行为)
- ✅ 完成 milestone 后主动停下,写清楚交付物 + 如何验收
- ✅ 遇到阻碍(环境问题、需要外部账号 / 密钥)主动暂停问用户

### 用户(sorain)的职责

- ✅ 触发会话(说"继续"或"做 MX.Y"等)
- ✅ 做产品方向决策(加/减功能、发版时机、文案、品牌)
- ✅ 做花钱决策(域名、付费服务)
- ✅ 验收(跑一遍你交付的东西,给 ✅ 或 ❌ + 问题清单)
- ✅ 合并 PR / 打 tag / 发布(如需要)
- ❌ **不**必须写代码
- ❌ **不**必须理解所有技术细节
- ❌ **不**必须每天响应(session 之间任意间隔)

### 不需要用户批准的决策(你自决)

- 依赖库版本升级(同 major 版本内)
- 内部模块拆分 / 重构
- 测试类型(单测 / 集成 / UI 自动化)
- 代码风格细节(命名、注释、错误处理模式)
- 文件组织调整
- 性能优化方案
- 具体 commit 粒度与 message 格式
- CI 配置
- 错误日志格式

### 必须先问用户的决策

| 决策类 | 例子 |
|---|---|
| 产品方向 | 砍某个已在 spec 的功能 / 加一个没在 spec 的功能 |
| 花钱 | Apple Developer / 域名 / 付费 SaaS(当前政策:**永不花钱**) |
| 品牌 | 改名、logo、配色主导 |
| 破坏性 | main 分支 force push / 删除历史 commit |
| 外部账号 | 需要用户 GitHub / Apple / 其他登录 |

---

## 必读文档(按顺序)

每次新会话开始,**按此顺序读**:

1. **`CLAUDE.md`**(本文件)— 工作模式和红线
2. **`docs/superpowers/specs/2026-04-23-cairn-v1-design.md`** — 完整设计规范(1386+ 行)
3. **`docs/superpowers/plans/`** 下**最新**的 plan — 当前 milestone 的详细任务
4. **`docs/milestone-log.md`**(如存在) — 已完成的 milestone 列表与状态

如果 (3) 或 (4) 不存在,**先问用户**"没找到 plan,是要进入下个 milestone 的计划阶段吗?"

---

## Session 循环

**标准循环**(用户只说"继续"就应该触发这个流程):

```
1. 读文档确定当前位置
2. 一句话报告给用户:"我理解的情况是 X,准备做 MY"
3. 等用户 ✅ 后开工
4. 执行:写代码 + 测试 + 文档 + commit
5. 完成 milestone 后输出"验收清单":
   - 要跑的命令(build / test / run)
   - 期望看到的行为
   - 已知限制
6. 更新 docs/milestone-log.md
7. push 到远端
8. 告诉用户:"MY 完成,等待验收。下一个 M 是 Z。"
9. 停下等用户回应
```

**异常分支**:
- 遇到需要用户决策 → 暂停,提问,不要硬猜
- 遇到环境缺失(如 Xcode 没装)→ 暂停,告诉用户怎么装
- 遇到测试失败修不了 → 暂停,报告给用户 + 我的分析

**不要**:
- 一个 session 做多个 milestone(用户来不及验收)
- 不验收就推进
- 跑掉不回报

---

## 验收协议

每完成一个 milestone,你必须在会话结尾输出**完整验收清单**:

```markdown
## M[X.Y] 验收清单

**交付物:**
- [文件/功能列表]

**验证步骤:**
```bash
# 1. 构建
[具体命令]
# 期望:[具体输出]

# 2. 运行测试
[具体命令]
# 期望:N passed, 0 failed

# 3. 手动验证(如适用)
[步骤]
# 期望:[观察到的行为]
```

**已知限制 / 延后项:**
- [清单,若无写"无"]

**下个 M:** [M X.Y+1 标题]
```

**用户只需做**:粘贴命令跑一遍,核对输出,回"✅" 或 "❌ + 具体问题"。

---

## 架构硬约束(编译器强制,不要违反)

**模块依赖方向**(严格从右到左):

```
CairnApp ← CairnUI / CairnTerminal ← CairnServices ← CairnClaude / CairnStorage ← CairnCore
```

**永远不要**:
- UI 直接 import `CairnStorage`(必须走 Services)
- 任何模块被 `CairnCore` import
- 为"未来灵活性"提前抽象(YAGNI)
- 修改用户 `~/.claude/` 下的**数据文件**(JSONL / plan.md / debug 日志)

**唯一允许写 `~/.claude/`**:用户 opt-in hook 后写 `settings.json` 的 hook 条目(只增不删)。

---

## Git 纪律

- `main` 永远 green(编译 + 单测通过)
- feature 分支 `feature/mX-Y-topic`,完成后 merge(可直接 fast-forward,小项目不强求 PR)
- commit 信息写**为什么**不写**做了什么**
- 每个 milestone 完成后打 tag `mX-Y-done`
- 依赖变更**独立 commit** 且在 message 里高亮
- **绝不**对 main `git push --force`
- **绝不**跳过 hook(`--no-verify`)

---

## 质量基准(生产级开源项目)

比"学习型"更高的要求。不要降格。

| 维度 | 要求 |
|---|---|
| 代码 | 无警告通过 Xcode + SwiftLint 基础规则 |
| 单元测试 | 核心模块覆盖率 ≥ 70%(CairnCore / CairnClaude 重点) |
| 集成测试 | 关键路径(JSONL ingest / 终端 IO / 数据库迁移)有场景级用例 |
| UI 自动化 | 关键用户流程(新建 Tab / 切换 Task / 审批 Hook)XCTest UI 测试 |
| 本地化 | 所有用户字符串 `String(localized:)`;v1 交付中英双语 |
| 可访问性 | 按钮 `accessibilityLabel`;对比度 ≥ 4.5:1;VoiceOver 可导航 |
| 文档 | user docs / dev setup / contributing / architecture 都有 |
| 错误 | 用户可见错误有可读消息;不可恢复错误产生诊断包 |
| 性能 | 空闲 CPU < 1%;Event Timeline 1000 条 < 16ms 帧 |

每个 milestone 完成时,你自查:**本 milestone 的新代码是否满足上述基准?** 不满足的加到延后项或下个 milestone 补。

---

## 分发策略(永不签名)

**定:** v1 永远以**未签名 DMG** 分发。不买 Apple Developer 账号。

用户安装需跑:
```bash
sudo xattr -rd com.apple.quarantine /Applications/Cairn.app
```

**你要做的**:
- README 首页清楚说明上述步骤
- v0.1 Beta 起:DMG 打包脚本 + GitHub Release 流程
- 不要为了"方便用户"临时签名或变通
- 不要搞 ad-hoc signing(还是会报错,无意义)

---

## 当前状态识别(每次开工前跑)

```bash
cd /Users/sorain/xiaomi_projects/AICoding/cairn

# 1. 看最近 10 个 commit
git log --oneline -10

# 2. 看最新 plan
ls -t docs/superpowers/plans/ | head -3

# 3. 看已完成 milestones
cat docs/milestone-log.md 2>/dev/null | tail -50

# 4. 工作树状态
git status
```

**然后一句话**和用户对齐:

> "我看到的状态:最近完成 M[X.Y],main 是 [clean/dirty],准备推进 M[X.Y+1]。开始?"

等 ✅ 后开工。

---

## 12 条已确定决策(别再讨论)

下面是 2026-04-23 已锁定决策,**有极强理由才重新讨论**:

| # | 决策 | 选择 |
|---|---|---|
| A1 | 终端引擎 | SwiftTerm(非 libghostty) |
| A2 | 构建 | SPM 6 模块 |
| A3 | Session/Task | Task has-many Sessions(v1 默认 1:1) |
| A4 | AI 集成 | JSONL 主 + Hook 可选 + MCP 不做 |
| A5 | 远程 | v1 不做 |
| A6 | 许可证 | MIT |
| A7 | Budget 强制 | v1 观察,v1.1 Hook 强制 |
| A8 | 游戏化 | 不做 |
| A9 | Apple Developer | **永不购买(最新决定)** |
| A10 | UI 布局 | 三区,主区只放终端 |
| A11 | Event 类型 | type 封闭 12 种 + category 开放 |
| A12 | 存储 | SQLite + raw_payload 90 天归档 |
| A13 | 开发模式 | **Claude 主导 + 用户验收** |
| A14 | 分发 | **永不签名,xattr 路线** |
| A15 | v1 范围 | **保持聚焦,不提前纳入 MCP/多工具/浏览器** |

详见 spec 附录 A。

---

## 最短失败路径(别踩)

这些是从经验总结的反模式,你要警觉:

1. **"既然用户不验收,我就先推 3 个 milestone"** → 错。每个 milestone 停下等验收,别积压。
2. **"这个小 bug 先不修,继续做下个功能"** → 错。main 永远 green,不留技术债给下个 session。
3. **"用户说全权,我加一个不在 spec 的小功能"** → 错。spec 外的功能先问用户。
4. **"不验收的话,就跳过测试"** → 错。生产级要求单测 70%+,不能因为没人监督就降格。
5. **"我自己设计个新架构更好"** → 错。spec 已经过充分讨论,除非撞墙别重新设计。
6. **"用户没回应,我假设是默认同意"** → 错。用户沉默 = 未批准。
7. **"main 崩了等下个 session 修"** → 错。main 坏了**立刻** revert,不许过夜。

---

## 新会话开工清单

☐ 读本文件(CLAUDE.md)
☐ 读 spec
☐ 读最新 plan(`docs/superpowers/plans/` 最新文件)
☐ 读 milestone-log(如存在)
☐ 跑"当前状态识别"那 4 个命令
☐ 一句话给用户报告当前状态
☐ 等用户 ✅ 后开工
☐ 完成 milestone → 输出验收清单 → 停

---

## 应急协议

如果你(Claude)发现以下任一情况,**立刻停下来告诉用户**:

- Spec 内部矛盾,无法执行
- 测试有几个一直修不好,影响下游
- 发现已做的东西根本跑不起来(不是 bug,是架构错)
- 用户机器环境异常(Xcode 装坏、文件权限不对)
- GitHub / 网络不通,无法 push
- 怀疑自己读错了 plan,不确定当前 milestone

说话模板:

> "我遇到 X,我认为原因是 Y,有两个选项:A(代价 A)/ B(代价 B)。等你决定。"

**不要硬闯。** 硬闯 = 浪费 session + 埋坑。

---

**本文件是全局宪法。修改需用户明确批准。**
