# Cairn

> 一款 macOS 原生 AI 终端,把 Claude Code 的每次会话变成可读、可审查、可回放的任务轨迹。

**状态**: 🚧 Phase 1 已完成,Phase 2 开发中(尚未发布)

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

**Phase 1 收工**(M0.1 – M1.5):SPM 6 模块、SQLite 持久化、SwiftTerm 多 tab 多分屏、布局跨启动恢复。

**Phase 2 进行中**:Claude Code session 集成 + Event Timeline UI。

见 [`docs/superpowers/plans/`](docs/superpowers/plans/) 下最新的计划文档。

## Shell 配置(可选,让 cd 能更新 tab 标题)

Cairn 按 OSC 7 escape 更新 tab 标题(显示 cwd 的最后一段)。多数 shell 默认不发 OSC 7,`cd` 后 tab 名不变。加一个 chpwd hook emit OSC 7 就好:

**zsh**(推荐加到 `~/.zshrc`):

```zsh
# 让 Cairn / iTerm2 / Terminal.app 的 tab 标题跟随 cwd
function chpwd() {
  printf '\033]7;file://%s%s\007' "$HOST" "$PWD"
}
chpwd   # shell 启动立刻 emit 一次,当前 cwd 生效
```

**bash**(`~/.bashrc`):

```bash
__cairn_osc7() {
  printf '\033]7;file://%s%s\007' "$HOSTNAME" "$PWD"
}
PROMPT_COMMAND="__cairn_osc7${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
__cairn_osc7
```

**fish**(`~/.config/fish/config.fish`):

```fish
function __cairn_osc7 --on-variable PWD
  printf '\033]7;file://%s%s\a' $hostname $PWD
end
__cairn_osc7
```

> 配置完**在 Cairn 里**重开一个 tab 验证:`cd /tmp` → tab 标题变 `tmp`。

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
