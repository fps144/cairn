# Cairn Probe Report

**生成时间:** 2026-04-24T11:19:48

- 扫描 JSONL 文件数: **517**
- Project 目录数: **22**
- 总事件行数: **48206**
- 解析失败行数: **10**

---

## §1 Entry Types 分布

| type | 出现次数 |
|---|---|
| `assistant` | 20564 |
| `user` | 13261 |
| `progress` | 9745 |
| `system` | 1620 |
| `file-history-snapshot` | 1472 |
| `attachment` | 780 |
| `last-prompt` | 318 |
| `permission-mode` | 304 |
| `queue-operation` | 130 |
| `custom-title` | 1 |
| `agent-name` | 1 |

## §2 Content Block Types 分布

| block type | 出现次数 |
|---|---|
| `tool_use` | 11399 |
| `tool_result` | 11396 |
| `text` | 5109 |
| `thinking` | 4537 |
| `image` | 48 |

## §3 Tool 名字分布

对照 spec §2.3 的 toolName → category 映射,检查未覆盖的工具。

| tool_name | 出现次数 |
|---|---|
| `Read` | 3418 |
| `Bash` | 3155 |
| `Edit` | 1597 |
| `Write` | 621 |
| `TaskUpdate` | 618 |
| `Grep` | 427 |
| `Agent` | 364 |
| `TaskCreate` | 301 |
| `Glob` | 298 |
| `Skill` | 291 |
| `WebFetch` | 71 |
| `AskUserQuestion` | 43 |
| `mcp__ide__getDiagnostics` | 43 |
| `mcp__feishu-mcp__fetch-doc` | 33 |
| `mcp__feishu-mcp__update-doc` | 24 |
| `TaskOutput` | 20 |
| `mcp__feishu-mcp__create-doc` | 19 |
| `TodoWrite` | 12 |
| `TaskList` | 12 |
| `mcp__feishu-mcp__fetch-file` | 8 |
| `mcp__plugin_figma_figma__get_design_context` | 7 |
| `WebSearch` | 5 |
| `TaskGet` | 3 |
| `mcp__feishu-mcp__authenticate` | 2 |
| `TaskStop` | 2 |
| `mcp__kg-mcp__kg_whoami` | 1 |
| `ListMcpResourcesTool` | 1 |
| `ExitPlanMode` | 1 |
| `mcp__plugin_figma_figma__get_code_connect_suggestions` | 1 |
| `mcp__plugin_figma_figma__send_code_connect_mappings` | 1 |

## §4 Usage 字段 schema

| key | 出现次数 |
|---|---|
| `input_tokens` | 20564 |
| `output_tokens` | 20564 |
| `cache_read_input_tokens` | 20288 |
| `cache_creation_input_tokens` | 20287 |
| `cache_creation` | 20287 |
| `service_tier` | 11007 |
| `inference_geo` | 10856 |
| `server_tool_use` | 10714 |
| `iterations` | 10714 |
| `speed` | 10714 |
| `claude_cache_creation_5_m_tokens` | 19 |
| `claude_cache_creation_1_h_tokens` | 19 |

## §5 JSONL 文件大小分布

| 分位 | 字节 | KB |
|---|---|---|
| min | 1,915 | 1.9 |
| p50 | 61,635 | 60.2 |
| p90 | 272,234 | 265.9 |
| p99 | 3,143,733 | 3070.1 |
| max | 70,329,316 | 68681.0 |

## §6 首条 Entry 样本(验证 cwd 字段位置)

### Session 1 首条

```json
{
  "type": "permission-mode",
  "permissionMode": "default",
  "sessionId": "03b33d61-0f90-455b-b35d-f94b8dad0c29"
}
```

### Session 2 首条

```json
{
  "type": "file-history-snapshot",
  "messageId": "ebfab6ac-85eb-4b14-b00f-7b35996caf65",
  "snapshot": {
    "messageId": "ebfab6ac-85eb-4b14-b00f-7b35996caf65",
    "trackedFileBackups": {},
    "timestamp": "2026-04-01T07:35:47.918Z"
  },
  "isSnapshotUpdate": false
}
```

### Session 3 首条

```json
{
  "type": "permission-mode",
  "permissionMode": "default",
  "sessionId": "360bf898-3464-48ca-a48f-d1ca676beace"
}
```

## §7 Appendix B 问题人工回答指引

下列问题的答案应整理到 `docs/decisions/0001-probe-findings.md`:

1. JSONL 第一条 entry 是否含 `system.cwd`?精确字段路径? → **见 §6**
2. `message.usage` 精确 schema? → **见 §4**
3. `~/.claude/projects/{hash}/` 的 hash 规则?可从 cwd 计算? → **需手动比对**
4. 是否存在 `~/.claude/projects/.meta.json`? → **`ls` 可验证**
5. 是否有 spec §4.3 未列出的 entry type? → **对比 §1**
6. JSONL 文件大小分布? → **见 §5**
7. Claude Code 退出是否写 end 标记? → **看末行类型**
8. `.claude/plans/` 目录结构? → **`ls ~/.claude/plans/`**
9. Hook 配置 schema? → **`cat ~/.claude/settings.json`**
10. 大文件 ingest 性能? → **延后到 M2.3**
