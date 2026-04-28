# M2.1 Probe 要点 — JSONLWatcher 实现前置

> 从 `docs/decisions/0001-probe-findings.md` + spec §4.2–4.5 摘要。作为 T2–T8 实现基线。

## 环境现状

- `~/.claude/projects/` 本机目前 **21 个 hash 目录**(M0.1 probe 当时 22 个,最近有清理)。有 `-Users-sorain-xiaomi-projects-AICoding-cairn`(本仓库)。
- 目录权限:多数 `drwx------`(只 owner 可读),部分 `drwxr-xr-x`。app 运行为当前用户,可正常访问。

## probe Q1:`type=system` entry 的 cwd 位置

- spec 原假设:首条 entry 含 `system.cwd`
- 实测:**假设不成立**。首条 type 多样(permission-mode / file-history-snapshot 均观察到)
- **正确做法**:扫描 entries 找第一个 `type == system`,取顶层 `entry.cwd`(不是 `entry.system.cwd`,也不是 `entry.message.cwd`)
- 1620 个 system entry 跨 27 个不同 cwd,**100%** 含顶层 `cwd` 字段

**M2.1 影响**:本 milestone 不 parse JSONL,session → workspace 反推留 M2.6。watcher 只用文件路径的 hash 目录名当"弱 hint",实际 workspace 绑定在 M2.6 用 system.cwd 精确化。

## probe Q3:hash 规则

- **规则**:cwd 中的 `/` `_` `.` **全部**替换为 `-`
- 正向可算(ProjectsDirLayout.hash)
- **逆向有歧义**(因为 `-` 原本是 `/` / `_` / `.` 哪个不可判)

**M2.1 影响**:只实现 forward hash;反向靠 system.cwd(M2.6)。

## probe Q5:JSONL 顶层 type 分布

spec §4.3 列 6 种,实测 **11 种**。频次 top-5:`assistant`(20564) / `user`(13261) / `progress`(9745) / `system`(1620) / `file-history-snapshot`(1472)。

**M2.1 影响**:**无**。本 milestone 不 parse entry,11 种还是 6 种与 watcher 无关。M2.2 parser 的工作。

## probe Q6:文件大小分布

- p50 ≈ 几百 KB
- p95 ≈ 3 MB
- p99 ≈ 30 MB
- max 见过 100+ MB

**M2.1 影响**:
- `IncrementalReader.maxBytes` 默认 1 MB 合适(多数 session 一次读完;大 session 分多次 tick 读完)
- `scanExisting` 启动时一次 enumerate 所有 hash dir × 所有 .jsonl —— 21 目录 × 各几个 = 几十~几百文件,不阻塞
- 首次读大文件(30 MB)按 1 MB 块,30 次 vnode/reconcile tick 读完,每次 ms 级

## probe Q7:session 无 end 标记

- 末行 type 分布极广(user 占 44%)
- **M2.1 影响**:无。session state 的 `.ended` / `.abandoned` / `.crashed` 判定是 M2.6。watcher 只维护 `.live`。

## 实现要点清单(M2.1 基线)

1. `~/.claude/projects/` 目录确认存在、本用户可读
2. 文件名**多是** UUID.jsonl(Claude Code 用 session id 命名),`UUID(uuidString: basename) ?? UUID()` 即可复用
3. 首次 enumerate 21 hash 目录,几十 session 文件,可接受
4. 每个 session 一个 `VnodeWatcher`;大文件读 1 MB 块,30+ tick 自然消化
5. hash 目录名只用来判"session 来自哪个 hash",不反推精确 workspace —— 那是 M2.6 的事

---

**结论**:实现可按 plan 原设计进行,无因 probe 发现的设计变更。
