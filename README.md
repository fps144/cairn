# Cairn

> 一款 macOS 原生 AI 终端,把 Claude Code 的每次会话变成可读、可审查、可回放的任务轨迹。

**状态**: 🎉 **v0.1 Beta 已发布** —— [下载最新 DMG](https://github.com/fps144/cairn/releases/latest)

## 这是什么

Cairn 是专为 Claude Code 用户设计的原生 macOS 终端。它把代理的工作过程记录为结构化的**任务轨迹**:

- **多 Tab + 水平分屏 + 布局跨启动恢复**
- **实时 JSONL 观察** —— FSEvents + DispatchSource + 30s reconcile 三层兜底监听 `~/.claude/projects/`
- **Event Timeline** —— 12 种事件类型 + 工具卡片合并 + 折叠交互 + SF Symbols 视觉
- **Tab↔Session 自动绑定** —— 按 cwd 精确匹配,session 生命周期 5 态指示(`● live` / `○ idle` / `✓ ended` / `⚠ abandoned` / `✗ crashed`)

## 安装

### 1. 下载

从 [GitHub Releases](https://github.com/fps144/cairn/releases/latest) 下载最新 DMG。

### 2. 拖到 Applications

挂载 DMG → 把 `Cairn.app` 拖到 `Applications`。

### 3. 解除 Gatekeeper quarantine(首次必做)

Cairn 走**永不签名**分发路线(不购买 Apple Developer 账号)。macOS 会阻止未签名 app,首次运行需手动解除:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Cairn.app
```

之后双击启动即可。

> ⚠️ **v0.1 Beta**:建议先在非关键项目试用。Bug 反馈到 [Issues](https://github.com/fps144/cairn/issues)。

### 系统要求

- macOS 14 Sonoma 或更新
- Apple Silicon(arm64)—— Intel Mac 暂不支持
- [Claude Code CLI](https://docs.claude.com/claude-code) 已安装

## 快捷键

| 快捷键 | 功能 |
|---|---|
| `⌘T` | 新建 Tab |
| `⌘W` | 关闭 Tab |
| `⌘⇧D` | 水平分屏(最多 2 组) |
| `⌘L` / `⌘⇧L` | 下一/上一 Tab |
| `⌘⇧T` | 切换 Sidebar |
| `⌘I` | 切换 Inspector(右侧 Timeline) |
| `⌘⌥E` | 展开/折叠所有 Events(toolCard / mergedTools / thinking) |

> 注:spec §6.7 原定 `⌘⇧E`,实测与系统/Mail/Xcode 冲突,改为 `⌘⌥E`。

## Shell 配置(可选,让 cd 能更新 tab 标题)

Cairn 按 OSC 7 escape 更新 tab 标题(显示 cwd 的最后一段)。多数 shell 默认不发 OSC 7,`cd` 后 tab 名不变。加一个 chpwd hook emit OSC 7 就好:

**zsh**(推荐加到 `~/.zshrc`):

```zsh
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

## 已知限制(v0.1 Beta)

- **未签名分发** —— 首次需 `xattr` 解除 quarantine(MIT 项目永不购买 Developer 账号)
- **Apple Silicon 专属** —— x86_64 Intel Mac 暂不支持(v0.2+ 看需求)
- **Hook 审批未实现** —— v1.1 开启
- **MCP 集成不做** —— v2 再评估(spec §4.1)
- **历史 session 导入 UI 未做** —— v1.1
- **Tab↔Session 绑定基于 cwd 精确匹配** —— 外部 terminal(iTerm/Trae 等)里跑的 claude 不会绑到 Cairn(v1.1 加手动绑定)
- **同 tab 多 session** —— 一个 tab 里连跑两次 `claude`,新 session 覆盖旧绑定(v1.5+ 加 session 切换历史)

完整 changelog 见 [`CHANGELOG.md`](CHANGELOG.md)。

## 开发模式

Claude(Anthropic Opus 4.7)全权主导开发,项目所有者 [@sorain](https://github.com/sorain) 做产品方向与 milestone 验收。

12 个 milestone(M0.1 → M2.7)、4 周完成 v0.1 Beta,~200 单元测试覆盖,详见 [`docs/milestone-log.md`](docs/milestone-log.md)。

## 文档

- 📐 **设计规范**: [`docs/superpowers/specs/2026-04-23-cairn-v1-design.md`](docs/superpowers/specs/2026-04-23-cairn-v1-design.md)
- 📋 **Changelog**: [`CHANGELOG.md`](CHANGELOG.md)
- 🤖 **Claude session 入口**: [`CLAUDE.md`](CLAUDE.md)
- 📝 **Milestone 完成记录**: [`docs/milestone-log.md`](docs/milestone-log.md)

## 技术栈

Swift 6 + SwiftUI + AppKit + SwiftTerm + GRDB。单进程,纯本地,无网络通信(除 Claude Code 自身)。

## License

[MIT](LICENSE) © 2026 sorain
