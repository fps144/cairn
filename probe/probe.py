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
