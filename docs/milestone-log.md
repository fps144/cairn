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

- [ ] M0.2 Hello World macOS App
- [ ] M1.1 - M1.5 ...(详见 spec §8.4)
- [ ] M2.1 - M2.7 ...(详见 spec §8.5)
- [ ] M3.1 - M3.6 ...(详见 spec §8.6)
- [ ] M4.1 - M4.4 ...(详见 spec §8.7)

---

## 已完成(逆序)

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
