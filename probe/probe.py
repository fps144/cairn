#!/usr/bin/env python3
"""
Cairn Phase 0 Probe Script

扫描 ~/.claude/projects/ 下所有 JSONL 会话文件,分析结构,
产出 probe-report.md 回答 spec 附录 B 的问题。

Usage: python probe.py
"""

import json
from pathlib import Path


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
