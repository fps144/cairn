# Cairn

> 一款 macOS 原生 AI 终端,把 Claude Code 的每次会话变成可读、可审查、可回放的任务轨迹。

**状态**: 🚧 Phase 0 开发中(尚未发布)

## 这是什么

Cairn 是专为 Claude Code 用户设计的原生 macOS 终端。它把代理的工作过程记录为结构化的**任务轨迹**:

- **Task 是一等实体**(Workspace / Tab 之上)
- **Event Timeline** 结构化呈现 Claude Code 输出(12 种事件 + 开放工具分类)
- **Budget** 任务级 token / 成本 / 时间预算

## 安装(v0.1 Beta 后可用)

Cairn 走**未签名分发**路线(不花钱买 Apple Developer 账号)。首次运行前需解除 Gatekeeper quarantine:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Cairn.app
```

## 当前阶段

**M0.1 — 仓库基础设施 + Probe 勘察**(Phase 0 第 1 milestone)

见 [`docs/superpowers/plans/`](docs/superpowers/plans/) 下最新的计划文档。

## 开发模式

Claude(Anthropic Opus 4.7)全权主导开发,项目所有者 [@sorain](https://github.com/sorain) 做产品方向与 milestone 验收。

## 文档

- 📐 **设计规范**: [`docs/superpowers/specs/2026-04-23-cairn-v1-design.md`](docs/superpowers/specs/2026-04-23-cairn-v1-design.md)
- 🤖 **Claude session 入口**: [`CLAUDE.md`](CLAUDE.md)
- 📝 **Milestone 完成记录**: [`docs/milestone-log.md`](docs/milestone-log.md)

## 技术栈

Swift 6 + SwiftUI + AppKit + SwiftTerm + GRDB + swift-log。单进程,纯本地。

## License

[MIT](LICENSE) © 2026 sorain
