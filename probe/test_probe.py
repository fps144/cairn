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


def test_find_jsonl_files(tmp_path):
    from probe import find_jsonl_files

    (tmp_path / "proj-a").mkdir()
    (tmp_path / "proj-b").mkdir()
    (tmp_path / "proj-a" / "s1.jsonl").write_text("")
    (tmp_path / "proj-a" / "s2.jsonl").write_text("")
    (tmp_path / "proj-b" / "s1.jsonl").write_text("")
    (tmp_path / "proj-a" / "ignore.txt").write_text("not jsonl")

    files = find_jsonl_files(tmp_path)
    assert len(files) == 3
    assert all(f.suffix == ".jsonl" for f in files)


def test_find_jsonl_files_missing_dir(tmp_path):
    from probe import find_jsonl_files
    missing = tmp_path / "does-not-exist"
    assert find_jsonl_files(missing) == []


def test_collect_stats_on_minimal_fixture():
    from probe import collect_stats

    stats = collect_stats([FIXTURES / "sample_minimal.jsonl"])

    assert stats['file_count'] == 1
    assert stats['total_lines'] == 7

    assert stats['entry_types']['system'] == 1
    assert stats['entry_types']['user'] == 3
    assert stats['entry_types']['assistant'] == 3

    assert stats['content_block_types']['text'] == 3
    assert stats['content_block_types']['thinking'] == 1
    assert stats['content_block_types']['tool_use'] == 1
    assert stats['content_block_types']['tool_result'] == 1

    assert stats['tool_names']['Read'] == 1
    assert 'input_tokens' in stats['usage_keys']
    assert 'output_tokens' in stats['usage_keys']
