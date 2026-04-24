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

- [ ] M1.1 - M1.5 ...(详见 spec §8.4)
- [ ] M2.1 - M2.7 ...(详见 spec §8.5)
- [ ] M3.1 - M3.6 ...(详见 spec §8.6)
- [ ] M4.1 - M4.4 ...(详见 spec §8.7)

---

## 已完成(逆序)

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
