#!/usr/bin/env python3
"""
Cairn Phase 0 Probe Script

扫描 ~/.claude/projects/ 下所有 JSONL 会话文件,分析结构,
产出 probe-report.md 回答 spec 附录 B 的问题。

Usage: python probe.py
"""

import json
from pathlib import Path
from collections import Counter


CLAUDE_PROJECTS_DEFAULT = Path("~/.claude/projects").expanduser()


def find_jsonl_files(root=None):
    """递归找 root 下所有 .jsonl,按路径排序。不存在返回 []。"""
    if root is None:
        root = CLAUDE_PROJECTS_DEFAULT
    root = Path(root)
    if not root.exists():
        return []
    return sorted(root.rglob("*.jsonl"))


def parse_jsonl_lines(path):
    """
    遍历 JSONL 文件,yield (行号, 解析结果 or None)。

    - 行号从 1 开始
    - 空行跳过
    - JSON 解析失败的行 yield (行号, None)
    """
    with open(path, 'r', errors='replace') as f:
        for lineno, raw in enumerate(f, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                yield lineno, json.loads(raw)
            except json.JSONDecodeError:
                yield lineno, None


def collect_stats(files):
    """扫描所有 JSONL,返回统计字典。"""
    stats = {
        'file_count': len(files),
        'total_lines': 0,
        'parse_errors': 0,
        'entry_types': Counter(),
        'content_block_types': Counter(),
        'tool_names': Counter(),
        'usage_keys': Counter(),
        'file_sizes_bytes': [],
        'project_hashes': set(),
        'first_entries': [],
    }

    for path in files:
        stats['file_sizes_bytes'].append(path.stat().st_size)
        stats['project_hashes'].add(path.parent.name)

        first_captured = False
        for lineno, entry in parse_jsonl_lines(path):
            stats['total_lines'] += 1
            if entry is None:
                stats['parse_errors'] += 1
                continue

            if not first_captured:
                stats['first_entries'].append(entry)
                first_captured = True

            stats['entry_types'][entry.get('type', 'UNKNOWN')] += 1

            message = entry.get('message') or {}
            if isinstance(message, dict):
                content = message.get('content')
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict):
                            btype = block.get('type', 'UNKNOWN')
                            stats['content_block_types'][btype] += 1
                            if btype == 'tool_use':
                                stats['tool_names'][block.get('name', 'UNKNOWN')] += 1

                usage = message.get('usage')
                if isinstance(usage, dict):
                    for key in usage.keys():
                        stats['usage_keys'][key] += 1

    return stats


def size_percentiles(sizes):
    if not sizes:
        return {}
    s = sorted(sizes)
    n = len(s)
    return {
        'min': s[0],
        'p50': s[n // 2],
        'p90': s[int(n * 0.9)],
        'p99': s[int(n * 0.99)] if n >= 100 else s[-1],
        'max': s[-1],
    }


def write_report(stats, out_path):
    """把 stats 写成 markdown 报告。"""
    from datetime import datetime

    lines = [
        "# Cairn Probe Report",
        "",
        f"**生成时间:** {datetime.now().isoformat(timespec='seconds')}",
        "",
        f"- 扫描 JSONL 文件数: **{stats['file_count']}**",
        f"- Project 目录数: **{len(stats['project_hashes'])}**",
        f"- 总事件行数: **{stats['total_lines']}**",
        f"- 解析失败行数: **{stats['parse_errors']}**",
        "",
        "---",
        "",
        "## §1 Entry Types 分布",
        "",
        "| type | 出现次数 |",
        "|---|---|",
    ]
    for t, n in stats['entry_types'].most_common():
        lines.append(f"| `{t}` | {n} |")

    lines += ["", "## §2 Content Block Types 分布", "",
              "| block type | 出现次数 |", "|---|---|"]
    for t, n in stats['content_block_types'].most_common():
        lines.append(f"| `{t}` | {n} |")

    lines += ["", "## §3 Tool 名字分布", "",
              "对照 spec §2.3 的 toolName → category 映射,检查未覆盖的工具。", "",
              "| tool_name | 出现次数 |", "|---|---|"]
    for t, n in stats['tool_names'].most_common():
        lines.append(f"| `{t}` | {n} |")

    lines += ["", "## §4 Usage 字段 schema", "",
              "| key | 出现次数 |", "|---|---|"]
    for k, n in stats['usage_keys'].most_common():
        lines.append(f"| `{k}` | {n} |")

    p = size_percentiles(stats['file_sizes_bytes'])
    lines += ["", "## §5 JSONL 文件大小分布", "",
              "| 分位 | 字节 | KB |", "|---|---|---|"]
    for k, v in p.items():
        lines.append(f"| {k} | {v:,} | {v/1024:.1f} |")

    lines += ["", "## §6 首条 Entry 样本(验证 cwd 字段位置)", ""]
    for i, entry in enumerate(stats['first_entries'][:3], 1):
        snippet = json.dumps(entry, indent=2, ensure_ascii=False)[:2000]
        lines += [f"### Session {i} 首条", "", "```json", snippet, "```", ""]

    lines += [
        "## §7 Appendix B 问题人工回答指引",
        "",
        "下列问题的答案应整理到 `docs/decisions/0001-probe-findings.md`:",
        "",
        "1. JSONL 第一条 entry 是否含 `system.cwd`?精确字段路径? → **见 §6**",
        "2. `message.usage` 精确 schema? → **见 §4**",
        "3. `~/.claude/projects/{hash}/` 的 hash 规则?可从 cwd 计算? → **需手动比对**",
        "4. 是否存在 `~/.claude/projects/.meta.json`? → **`ls` 可验证**",
        "5. 是否有 spec §4.3 未列出的 entry type? → **对比 §1**",
        "6. JSONL 文件大小分布? → **见 §5**",
        "7. Claude Code 退出是否写 end 标记? → **看末行类型**",
        "8. `.claude/plans/` 目录结构? → **`ls ~/.claude/plans/`**",
        "9. Hook 配置 schema? → **`cat ~/.claude/settings.json`**",
        "10. 大文件 ingest 性能? → **延后到 M2.3**",
        "",
    ]

    out_path.write_text("\n".join(lines))


def main():
    """扫描默认 Claude Code 目录,产出 probe-report.md。"""
    print(f"[probe] 扫描 {CLAUDE_PROJECTS_DEFAULT}...")
    files = find_jsonl_files()
    if not files:
        print(f"[probe] 未找到 JSONL 文件。请先用 Claude Code 跑几个会话。")
        return 1

    print(f"[probe] 找到 {len(files)} 个文件")
    stats = collect_stats(files)

    out_path = Path(__file__).parent / "probe-report.md"
    write_report(stats, out_path)
    print(f"[probe] Report written to {out_path}")
    print(f"[probe] 摘要:")
    print(f"  - 文件数: {stats['file_count']}")
    print(f"  - 总行数: {stats['total_lines']}")
    print(f"  - Entry types: {len(stats['entry_types'])}")
    print(f"  - Tool names: {len(stats['tool_names'])}")
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
