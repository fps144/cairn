"""probe 脚本的单测。运行:pytest test_probe.py -v"""

from pathlib import Path
import pytest
from probe import parse_jsonl_lines

FIXTURES = Path(__file__).parent / "fixtures"


def test_parse_jsonl_lines_happy_path():
    """能正确解析 sample_minimal.jsonl 的每一行。"""
    path = FIXTURES / "sample_minimal.jsonl"
    results = list(parse_jsonl_lines(path))

    assert len(results) == 7
    for lineno, entry in results:
        assert isinstance(lineno, int)
        assert lineno >= 1

    first_lineno, first = results[0]
    assert first_lineno == 1
    assert first["type"] == "system"


def test_parse_jsonl_lines_empty_file():
    """空文件返回空列表,不报错。"""
    path = FIXTURES / "sample_empty.jsonl"
    assert list(parse_jsonl_lines(path)) == []


def test_parse_jsonl_lines_handles_malformed(tmp_path):
    """坏行 yield (lineno, None),不抛异常。"""
    bad_file = tmp_path / "bad.jsonl"
    bad_file.write_text('{"type":"ok"}\n{not json}\n{"type":"ok2"}\n')

    results = list(parse_jsonl_lines(bad_file))
    assert len(results) == 3
    assert results[0][1]["type"] == "ok"
    assert results[1][1] is None
    assert results[2][1]["type"] == "ok2"
